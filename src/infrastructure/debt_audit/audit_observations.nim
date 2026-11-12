## src/infrastructure/debt_audit/audit_observations.nim — Observation extraction + shared types.
##
## Pure extraction from the audited repository tree into structured observations
## (JSONL-ready). Defines all shared records used by audit_rules /
## audit_correlate / audit_projection. This is the ONLY module that defines
## these exported types.
##
## Determinism: observation extraction walks the repo tree in sorted order and
## never reads mtime as identity. SHA-256 evidence is optional (bundle digest).

import core/trusted/layer_declaration
axiomLayer "infrastructure"

import std/[json, os, strutils, tables, sets, times, algorithm]

# ---------------------------------------------------------------------------
# Shared exported types  (only module defining these)
# ---------------------------------------------------------------------------

## File-level metadata collected during repo scan.
type FileObs* = object
  path*: string
  size*: int64
  mtimeNs*: int64
  sha256*: string
  fileType*: string
  executable*: bool
  tracked*: bool

## Single observation record emitted by extractObservations.
type Obs* = object
  domain*: string
  kind*: string
  path*: string
  line*: int
  data*: string
  shaEvidence*: string

## Context passed through the audit pipeline.  Populated by the audit driver
## (`cmdAuditDirDoc` in tools/debt_engine.nim) and consumed by audit_rules.
type RuleCtx* = object
  repoRoot*: string
  bundleDir*: string
  files*: seq[FileObs]
  obs*: seq[Obs]
  makeTargets*: HashSet[string]
  allowlist*: HashSet[string]
  registryEntries*: Table[string, JsonNode]
  # -- directory roots (repo-relative or absolute) used by rule evaluators --
  binDir*: string
  tmpDir*: string
  srcDir*: string
  docsDir*: string
  toolsDir*: string
  testDir*: string
  logDir*: string
  debtEnginePath*: string
  # -- dependency hints populated by the engine --
  excludedDirs*: seq[string]      ## dirs excluded from directory-debt rules
  knownProducers*: seq[string]    ## bin/ producer path fragments (make/CI)
  referenceFiles*: seq[string]    ## files read to detect "referenced" tokens
  registryFiles*: seq[string]     ## every path listed in the debt registry
  toolchainVersions*: seq[(string, string)]  ## (name, expectedVersion)

# ---------------------------------------------------------------------------
# loadFiles — walk a root directory, collect FileObs for regular files
# ---------------------------------------------------------------------------

const HeavyDirs* = ["tmp", "bin", "nimcache", "build", "logs", "data",
                    "vendor", "deps", ".lake", ".git", "trusted", "benchmarks"]

func detectFileType*(filename: string): string {.raises: [].} =
  case filename.toLowerAscii()
  of "*.nim", "*.nims": "nim"
  of "*.lean", "*.hlean": "lean"
  of "*.md": "markdown"
  of "*.json": "json"
  of "*.toml": "toml"
  of "*.yml", "*.yaml": "yaml"
  of "*.sh", "*.bash": "shell"
  of "*.txt": "text"
  else: "other"

proc loadFiles*(root: string; skipHeavy: bool = true): seq[FileObs] {.raises: [OSError, ValueError].} =
  ## Walk *root* recursively in deterministic lexicographic order.
  ## No git calls; no third-party deps. Heavy directories are skipped so the
  ## observation layer stays cheap (bin/ artifacts are handled by rules).
  if not dirExists(root):
    return @[]

  var stack: seq[string] = @[root]
  while stack.len > 0:
    let dir = stack.pop()
    var entries: seq[string]
    for (kind, path) in walkDir(dir):
      if kind == pcDir:
        let baseName = extractFilename(path)
        var heavy = false
        if skipHeavy:
          for h in HeavyDirs:
            if baseName == h:
              heavy = true
              break
        if not heavy:
          stack.add(path)
      elif kind == pcFile:
        entries.add(path)
    entries.sort()

    for entry in entries:
      let fi = getFileInfo(entry)
      let relPath = relativePath(entry, root)
      let execFlag = (fpUserExec in getFilePermissions(entry)) or
                     (fpGroupExec in getFilePermissions(entry)) or
                     (fpOthersExec in getFilePermissions(entry))
      result.add(FileObs(
        path: relPath,
        size: fi.size.int64,
        mtimeNs: toUnix(fi.lastWriteTime) * 1_000_000_000,
        sha256: "",
        fileType: detectFileType(entry),
        executable: execFlag,
        tracked: true
      ))

# ---------------------------------------------------------------------------
# loadAllowlist — the 7 committed untracked binaries under bin/ (canonical)
# ---------------------------------------------------------------------------

const AllowlistBin* = [
  "bin/readfile_guard",
  "bin/axiom-upgrade",
  "bin/generate-pbt-tests",
  "bin/generate-runners",
  "bin/hermetic-build",
  "bin/axiom_local_docs_lookup",
  "bin/setup-agent-capabilities"
]

proc loadAllowlist*(): HashSet[string] =
  result = initHashSet[string]()
  for p in AllowlistBin:
    result.incl(p)

# ---------------------------------------------------------------------------
# Private helpers — plain-string pattern matching (no regex)
# ---------------------------------------------------------------------------

func isRelevantPath*(relPath: string): bool {.raises: [].} =
  if relPath == "Makefile" or relPath == ".gitignore": return true
  if relPath == ".github/workflows/ci.yml": return true
  if relPath == "config/audit_rules.json": return true
  if relPath.startsWith("src/") or relPath.startsWith("config/") or
     relPath.startsWith("docs/") or relPath.startsWith("tools/") or
     relPath.startsWith(".github/"):
    return true
  false

func matchesQuirkMarker*(line: string): (bool, string) {.raises: [].} =
  ## Detect QUIRK(DEBT#NNN). Returns (true, "DEBT#NNN") or (false, "").
  let qi = line.toLowerAscii().find("quirk(")
  if qi < 0: return (false, "")
  let afterParen = qi + 6
  if afterParen >= line.len or line[afterParen] != '(': return (false, "")
  let inner = line[afterParen + 1 ..< line.len]
  let di = inner.find("debt#")
  if di < 0: return (false, "")
  let idStart = afterParen + 1 + di + 5
  var digits = ""
  for i in idStart ..< min(idStart + 32, line.len):
    let c = line[i]
    if c.isDigit: digits.add(c)
    else: break
  if digits.len > 0: result = (true, "DEBT#" & digits)

func isBareQuirk*(line: string): bool {.raises: [].} =
  let t = line.strip()
  if t.len >= 2 and (t.startsWith("//") or t.startsWith("#")):
    let inner = t[2 .. ^1].strip().toLowerAscii()
    if inner == "quirk" or (inner.startsWith("quirk ") and not inner.contains("debt#")):
      return true
  false

func findDebtRefs*(line: string): seq[string] {.raises: [].} =
  var refs: seq[string] = @[]
  var fromPos = 0
  while fromPos < line.len:
    let idx = line.find("DEBT#", fromPos)
    if idx < 0: break
    var digits = ""
    for i in idx + 5 ..< min(idx + 37, line.len):
      if line[i].isDigit: digits.add(line[i])
      else: break
    if digits.len > 0: refs.add("DEBT#" & digits)
    fromPos = idx + 1
  refs

func findDocLinks*(line: string): seq[string] {.raises: [].} =
  var targets: seq[string] = @[]
  var fromPos = 0
  while fromPos < line.len:
    let cb = line.find("](", fromPos)
    if cb < 0: break
    let cp = line.find(')', cb + 2)
    if cp < 0: break
    let target = line[cb + 2 ..< cp].strip()
    if target.len > 0: targets.add(target)
    fromPos = cp + 1
  targets

func isMakeTargetLine*(line: string): bool {.raises: [].} =
  let t = line.strip()
  if t.len == 0 or t.startsWith('#') or t.startsWith('\t'): return false
  if '=' in t.split(':')[0]: return false
  let ci = t.find(':')
  if ci <= 0: return false
  let name = t[0 ..< ci].strip()
  if name.len == 0: return false
  for c in name:
    if not (c.isAlphaNumeric or c == '_' or c == '-'): return false
  true

func extractMakeTargetName*(line: string): string {.raises: [].} =
  let t = line.strip()
  let ci = t.find(':')
  if ci > 0: result = t[0 ..< ci].strip()
  else: result = t.splitWhitespace()[0]

func isMakeProducerLine*(line: string): bool {.raises: [].} =
  ## Command line in Makefile containing bin/ or ./foo.
  let t = line.strip()
  if t.len == 0 or t.startsWith('#'): return false
  if not (t.startsWith('\t') or t.startsWith("./") or
          t.contains("bin/") or t.contains("./")):
    return false
  true

func extractMakeProducerPaths*(line: string): seq[string] {.raises: [].} =
  var paths: seq[string] = @[]
  for word in line.strip().splitWhitespace():
    let w = word.replace("'", "").replace("\"", "")
    if w.startsWith("bin/") or w.startsWith("./bin/") or
       (w.startsWith("./") and w.len > 2):
      paths.add(w.replace(":", ""))
  paths

func isCiPathLine*(line: string): bool {.raises: [].} =
  let t = line.strip()
  if t.len == 0 or t.startsWith('#'): return false
  t.contains("bin/")

func extractCiPaths*(line: string): seq[string] {.raises: [].} =
  var paths: seq[string] = @[]
  for word in line.strip().splitWhitespace():
    let w = word.replace("'", "").replace("\"", "").replace(",", "")
    if w.contains("bin/"): paths.add(w)
  paths

func isToolRefLine*(line: string): bool {.raises: [].} =
  let t = line.strip()
  if t.len == 0 or t.startsWith('#'): return false
  t.contains("tools/")

func extractToolRefs*(line: string): seq[string] {.raises: [].} =
  var paths: seq[string] = @[]
  for word in line.strip().splitWhitespace():
    let w = word.replace("'", "").replace("\"", "").replace(",", "")
    if w.contains("tools/"): paths.add(w)
  paths

func hasDocClaimToken*(line: string): bool {.raises: [].} =
  let lower = line.toLowerAscii()
  for prefix in @["bin/", "tools/", "config/"]:
    var fromPos = 0
    while fromPos < lower.len:
      let idx = lower.find(prefix, fromPos)
      if idx < 0: break
      var idc = ""
      for i in idx + prefix.len ..< min(idx + prefix.len + 128, lower.len):
        let c = lower[i]
        if c.isAlphaNumeric or c in ['/', '.', '_', '-']: idc.add(c)
        else: break
      if idc.len > 0: return true
      fromPos = idx + 1
  false

func extractDocClaimTokens*(line: string): seq[string] {.raises: [].} =
  var tokens: seq[string] = @[]
  let lower = line.toLowerAscii()
  for prefix in @["bin/", "tools/", "config/"]:
    var fromPos = 0
    while fromPos < lower.len:
      let idx = lower.find(prefix, fromPos)
      if idx < 0: break
      var idc = ""
      for i in idx + prefix.len ..< min(idx + prefix.len + 128, lower.len):
        let c = lower[i]
        if c.isAlphaNumeric or c in {'/', '.', '_', '-'}: idc.add(c)
        else: break
      if idc.len > 0: tokens.add(idc)
      fromPos = idx + 1
  tokens

func isMakeTargetPreceded*(line: string): bool {.raises: [].} =
  let lower = line.toLowerAscii()
  lower.contains("make ") or lower.contains("target")

func extractMakeTargetPreceded*(line: string): seq[string] {.raises: [].} =
  var tokens: seq[string] = @[]
  let mi = line.toLowerAscii().find("make ")
  if mi >= 0:
    let w = line[mi + 5 ..< line.len].strip().splitWhitespace()
    if w.len > 0 and w[0].len > 0: tokens.add(w[0])
  let ti = line.toLowerAscii().find("target")
  if ti >= 0 and ti + 6 < line.len:
    let w = line[ti + 6 ..< line.len].strip().splitWhitespace()
    if w.len > 0 and w[0].len > 0 and w[0] notin tokens: tokens.add(w[0])
  tokens

# ---------------------------------------------------------------------------
# extractObservations — main extraction proc (scans the audited tree)
# ---------------------------------------------------------------------------

proc extractObservations*(ctx: var RuleCtx) {.raises: [CatchableError].} =
  ## Walk RELEVANT blobs of the audited repo (ctx.repoRoot) and append Obs
  ## records to ctx.obs. Kinds: quirk_marker, debt_ref, doc_link,
  ## make_target, make_producer, ci_path, tool_ref, registry_file,
  ## doc_claim_path, doc_claim_target.
  ## Deterministic sorted walk; line numbers counted from 1.
  if ctx.files.len == 0:
    ctx.files = loadFiles(ctx.repoRoot)

  for fileObs in ctx.files:
    let fullPath = joinPath(ctx.repoRoot, fileObs.path)
    if not fileExists(fullPath): continue
    if not isRelevantPath(fileObs.path): continue
    var xcl = false
    for d in ctx.excludedDirs:
      if fileObs.path == d or fileObs.path.startsWith(d):
        xcl = true
        break
    if xcl: continue
    var content: string
    try:
      content = readFile(fullPath)
    except CatchableError:
      continue

    let lines = content.splitLines
    for lineIdx in 0 ..< lines.len:
      let line = lines[lineIdx]
      let lineNum = lineIdx + 1

      # --- quirk_marker ---
      let (isQ, qid) = matchesQuirkMarker(line)
      if isQ:
        ctx.obs.add(Obs(domain: "debt", kind: "quirk_marker",
          path: fileObs.path, line: lineNum, data: qid, shaEvidence: ""))
      elif isBareQuirk(line):
        ctx.obs.add(Obs(domain: "debt", kind: "quirk_marker",
          path: fileObs.path, line: lineNum, data: "bare", shaEvidence: ""))

      # --- debt_ref ---
      for r in findDebtRefs(line):
        ctx.obs.add(Obs(domain: "debt", kind: "debt_ref",
          path: fileObs.path, line: lineNum, data: r, shaEvidence: ""))

      # --- doc_link ---
      if fileObs.fileType == "markdown":
        for link in findDocLinks(line):
          ctx.obs.add(Obs(domain: "doc", kind: "doc_link",
            path: fileObs.path, line: lineNum, data: link, shaEvidence: ""))

      # --- make_target ---
      if fileObs.path == "Makefile" and isMakeTargetLine(line):
        let tn = extractMakeTargetName(line)
        ctx.makeTargets.incl(tn)
        ctx.obs.add(Obs(domain: "build", kind: "make_target",
          path: fileObs.path, line: lineNum, data: tn, shaEvidence: ""))

      # --- make_producer ---
      if fileObs.path == "Makefile" and isMakeProducerLine(line):
        for p in extractMakeProducerPaths(line):
          ctx.obs.add(Obs(domain: "build", kind: "make_producer",
            path: fileObs.path, line: lineNum, data: p, shaEvidence: ""))

      # --- ci_path ---
      if fileObs.path == ".github/workflows/ci.yml" and isCiPathLine(line):
        for p in extractCiPaths(line):
          ctx.obs.add(Obs(domain: "ci", kind: "ci_path",
            path: fileObs.path, line: lineNum, data: p, shaEvidence: ""))

      # --- tool_ref ---
      if isToolRefLine(line):
        for p in extractToolRefs(line):
          ctx.obs.add(Obs(domain: "tooling", kind: "tool_ref",
            path: fileObs.path, line: lineNum, data: p, shaEvidence: ""))

      # --- doc_claim_path ---
      if fileObs.fileType == "markdown" and hasDocClaimToken(line):
        for t in extractDocClaimTokens(line):
          ctx.obs.add(Obs(domain: "doc", kind: "doc_claim_path",
            path: fileObs.path, line: lineNum, data: t, shaEvidence: ""))

      # --- doc_claim_target ---
      if fileObs.path == "Makefile" and isMakeTargetPreceded(line):
        for t in extractMakeTargetPreceded(line):
          ctx.obs.add(Obs(domain: "build", kind: "doc_claim_target",
            path: fileObs.path, line: lineNum, data: t, shaEvidence: ""))

  # --- registry_file: scan canonical debt registry SSOT ---
  let regPath = joinPath(ctx.repoRoot, "data", "debt_registry.json")
  if fileExists(regPath):
    try:
      let regNode = parseJson(readFile(regPath))
      if regNode.kind == JObject and regNode.hasKey("entries"):
        for entry in regNode["entries"]:
          if entry.kind != JObject: continue
          let eid = entry["id"].getStr("")
          if eid.len > 0:
            ctx.registryEntries[eid] = entry
          let files = entry["files"]
          if files != nil and files.kind == JArray:
            for fe in files:
              if fe.kind == JString:
                let fStr = fe.getStr("")
                ctx.registryFiles.add(fStr)
                ctx.obs.add(Obs(domain: "registry", kind: "registry_file",
                  path: fStr, line: 0, data: eid, shaEvidence: ""))
      ctx.registryFiles.sort()
    except CatchableError:
      discard

# ---------------------------------------------------------------------------
# toJson — serialize FileObs / Obs sequences to JSON nodes
# ---------------------------------------------------------------------------

func toJson*(files: seq[FileObs]): JsonNode {.raises: [].} =
  result = newJArray()
  for f in files:
    result.add(%*{
      "path": f.path, "size": f.size, "mtimeNs": f.mtimeNs,
      "sha256": f.sha256, "fileType": f.fileType,
      "executable": f.executable, "tracked": f.tracked
    })

func toJson*(obs: seq[Obs]): JsonNode {.raises: [].} =
  result = newJArray()
  for o in obs:
    result.add(%*{
      "domain": o.domain, "kind": o.kind, "path": o.path,
      "line": o.line, "data": o.data, "shaEvidence": o.shaEvidence
    })