## doc_path_validator.nim — Validates documentation file path references.
##
## Walks docs/**/*.md and AGENTS.md, extracts file path references via three
## detection patterns (markdown links, backtick refs, prose refs), checks they
## exist on disk, and verifies case-sensitivity.
##
## Detection Patterns & Severity:
##   L (link)    \[[^\]]*\]\((src|tools|bin|docs)/[^)\s]+\)`
##               → Markdown link whose target is a repo file path. Severity: ERROR
##   B (backtick) `(src|tools|bin|docs)/[\w.\-]+\.(nim|json|md)`
##               → Backtick inline code file reference. Severity: WARNING
##   P (prose)   (src|tools|bin|docs)/[\w/\-\.]+\.(nim|json|md)
##               → Prose-style reference. Severity: WARNING
##
## Archived/Skipped docs (DEBT#403): documents listed in tools/ci/archived_docs.json
## under "archived" (retrospective) or "skippedDocs" (forward-plan scopes like
## docs/design/ whose normal function is to reference future paths) are SKIPPED
## entirely — their references are neither extracted nor validated.
## Active docs are still strictly validated. This only reduces false-positive
## warnings from retrospective or forward-plan docs; it does not weaken active-doc checking.
##
## Exit codes:
##   0 — all paths valid
##   1 — stale or mismatched paths found
##
## Usage:
##   nim c --hints:off -o:bin/doc_path_validator tools/ci/doc_path_validator.nim
##   bin/doc_path_validator [repoRoot] [--fix] [--json] [--archived <path>]

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[json, os, osproc, re, strutils, editdistance, options, strtabs, streams, tables]
import doc_path_validator_core

type PatternType = enum PTLink, PTBacktick, PTProse

type StaleEntry = object
  docFile: string
  stalePath: string
  suggestedPath: string
  distance: int
  patternType: PatternType
  resolveReason: string   # policy reject reason text (empty for non-policy findings)

const
  LinkPatternStr = """\[[^\]]*\]\((src|tools|bin|docs)/[^)\s]+\)"""
  # The `(?![\w])` guards keep the extension alternation from partially
  # matching a longer one: without it a reference to `*.nims` (e.g.
  # `src/gate/config.nims`) resolves as `*.nim` and is reported as a
  # missing target. `.nims` is outside this validator's vocabulary, so the
  # correct behaviour is "not extracted", not "extracted wrongly".
  BacktickPatternStr = """`(src|tools|bin|docs)/[\w.\-]+\.(nim|json|md)(?![\w])`"""
  ProsePatternStr = """(?:src|tools|bin|docs)/[\w/\-\.]+\.(?:nim|json|md)(?![\w])"""

let
  LinkPattern    = re(LinkPatternStr)
  BacktickPattern = re(BacktickPatternStr)
  ProsePattern   = re(ProsePatternStr)

proc extractPaths(content: string): seq[(string, PatternType)] =
  ## Extracts file-path references from content via three patterns.
  ## Returns (bareURL, patternType) tuples so the caller knows the severity.
  ## Priority: link > backtick > prose — first match wins for dedup.
  var seen: seq[string] = @[]        # set of bare URLs already captured
  var order: seq[(string, PatternType)] = @[]

  proc tryAdd(bare: string; pt: PatternType) =
    if bare.len > 0 and bare notin seen:
      seen.add(bare)
      order.add((bare, pt))

  # --- L (link) -----------------------------------------------------------
  for m in content.findAll(LinkPattern):
    let parenOpen = m.rfind('(') + 1
    let parenClose = m.rfind(')')
    if parenOpen > 0 and parenClose > parenOpen:
      tryAdd(m[parenOpen .. parenClose - 1], PTLink)

  # --- B (backtick) -------------------------------------------------------
  for m in content.findAll(BacktickPattern):
    tryAdd(m[1 .. m.len - 2], PTBacktick)   # strip surrounding backticks

  # --- P (prose) ----------------------------------------------------------
  for m in content.findAll(ProsePattern):
    tryAdd(m, PTProse)

  result = order

proc collectRealPaths(repoRoot: string): seq[string] =
  for dir in ["src", "tools", "docs", "bin"]:
    let dirPath = repoRoot / dir
    if dirExists(dirPath):
      try:
        for realPath in walkDirRec(dirPath):
          result.add(realPath.relativePath(repoRoot).toLowerAscii())
      except OSError:
        discard

proc findClosestPath(stalePath: string, realPaths: seq[string]): tuple[path: string, dist: int] =
  var bestDist = int.high
  var bestPath = ""
  let staleLower = stalePath.toLowerAscii()
  for relPath in realPaths:
    let dist = editDistance(staleLower, relPath)
    if dist < bestDist:
      bestDist = dist
      bestPath = relPath
  if bestDist <= 3:
    result = (bestPath, bestDist)
  else:
    result = ("", int.high)

# --- Whitelist ---------------------------------------------------------------

type WhitelistConfig = object
  paths: seq[string]  # exact-match entries

proc loadWhitelist(repoRoot: string): WhitelistConfig =
  ## Loads tools/ci/doc_path_whitelist.json if present.
  ## Returns empty config if file does not exist.
  let wlPath = repoRoot / "tools" / "ci" / "doc_path_whitelist.json"
  if not fileExists(wlPath):
    return WhitelistConfig(paths: @[])
  try:
    let raw = readFile(wlPath)
    let j = parseJson(raw)
    if j.kind == JArray:
      for node in j:
        if node.kind == JString:
          let p = node.str.strip()
          if p.len > 0:
            result.paths.add(p)
  except:
    discard

const RegexMetaChars = {'.', '^', '$', '+', '?', '(', ')', '[', ']', '{', '}', '|', '\\'}

proc globToRegex(pattern: string): Option[string] =
  ## Translates a glob pattern (with `*` and `**`) into an anchored regex.
  ## Semantics:
  ##   `*`   matches a single path segment ([^/]*)
  ##   `**/` matches zero or more path segments (including none)
  ##   `**`  elsewhere matches any characters (across segments)
  ## Returns none(string) for degenerate patterns that must NEVER match
  ## anything (bare `**` / `**/`) so a sloppy entry cannot silently disable
  ## validation (AGENTS.md §0.9 theater/dead-gate prevention).
  let pat = pattern.strip().replace('\\', '/')
  if pat.len == 0 or pat == "**" or pat == "**/":
    return none(string)
  var buf: string
  var i = 0
  while i < pat.len:
    let c = pat[i]
    if c == '*':
      if i + 1 < pat.len and pat[i + 1] == '*':
        if i + 2 < pat.len and pat[i + 2] == '/':
          buf.add("(?:.*/)?")   # `**/` spans zero or more directories
          inc(i, 3)
        else:
          buf.add(".*")         # `**` elsewhere spans any characters
          inc(i, 2)
      else:
        buf.add("[^/]*")        # `*` spans a single path segment
        inc(i)
    else:
      if c in RegexMetaChars:
        buf.add('\\')
      buf.add(c)
      inc(i)
  result = some("^" & buf & "$")

proc matchesGlob(path, entry: string): bool =
  ## Matches *path* (relative, "/" separated) against *entry*.
  ## Supports exact files, directory prefixes (trailing '/'), `*` single-segment
  ## globs, and `**` multi-segment globs. Bare `**`/`**/` entries match nothing.
  let normalized = path.strip().replace('\\', '/')
  let e = entry.strip().replace('\\', '/')
  if e.len == 0:
    return false
  if e == "**" or e == "**/":
    return false
  if normalized == e:
    return true
  if e.endsWith('/'):
    return normalized.startsWith(e)
  if "**" notin e and "*" notin e:
    return false
  let rgx = globToRegex(e)
  if rgx.isNone:
    return false
  match(normalized, re(rgx.get))

proc isWhitelisted(path: string, wl: WhitelistConfig): bool =
  ## Checks whether *path* (relative, e.g. "docs/evidence/foo.md") is covered
  ## by the whitelist. Supports exact match, directory prefixes, and glob-like
  ## patterns (*, **) via matchesGlob.
  for entry in wl.paths:
    if matchesGlob(path, entry):
      return true
  return false

# --- Skip config (DEBT#403) -------------------------------------------------

type SkipConfig = object
  entries: seq[string]  # directory prefixes, exact files, or glob entries

proc loadSkipConfig(cfgPath: string): SkipConfig =
  ## Loads tools/ci/archived_docs.json listing scopes to skip entirely
  ## during validation. Supports two config keys: "archived" (retrospective
  ## docs) and "skippedDocs" (forward-plan scopes such as docs/design/).
  ## Returns empty config if the file is absent or unparseable.
  if not fileExists(cfgPath):
    return SkipConfig(entries: @[])
  try:
    let j = parseJson(readFile(cfgPath))
    for key in @["archived", "skippedDocs"]:
      if j.hasKey(key) and j[key].kind == JArray:
        for node in j[key]:
          if node.kind == JString:
            let e = node.str.strip()
            if e.len > 0:
              result.entries.add(e)
  except:
    discard

proc isSkippedDoc(relPath: string, cfg: SkipConfig): bool =
  ## True when *relPath* (relative, e.g. "docs/design/foo.md") falls under
  ## a skipped scope. Reuses the SAME glob semantics as the whitelist matcher.
  for entry in cfg.entries:
    if matchesGlob(relPath, entry):
      return true
  return false

# --- Reference policy (docs/spec/document_reference_contract.md) ---------------
#
# The decision logic (value types, manifest parsing, per-path lookup, absence
# resolution, path canonicalization, unused-entry detection) lives in the PURE
# module `tools/ci/doc_path_validator_core.nim`. This section keeps only the
# IMPURE I/O adapters: reading the manifest file and probing a canonical reproducer
# target via the native `make -n` subprocess. The decisions themselves are pure.

proc loadReferencePolicy(path: string): ReferencePolicyConfig =
  ## Impure I/O: reads the manifest file and delegates parsing to the pure core.
  ## A missing manifest file is an EMPTY config (no carve-outs → all MUST_EXIST),
  ## never a failure; a PRESENT-but-malformed manifest is a hard FAIL via the
  ## core's `malformed` flag. Unclassified references default to MUST_EXIST.
  if not fileExists(path):
    return ReferencePolicyConfig()
  result = parseReferencePolicyConfig(readFile(path))

proc probeMakeTarget*(repoRoot: string, target: string): TargetProbe =
  ## Native `make -n <target>` tri-state probe — replaces the old Makefile string
  ## grep (`line.startsWith(name & ":")`). Execution contract: GNU Make 4.3, locale
  ## pinned to `LC_ALL=C` so "No rule to make target '<x>'" is locale-independent.
  ##   EXIT=0                                                     → tpExists
  ##   EXIT=2 AND stderr names exactly the REQUESTED target        → tpAbsent
  ##   anything else (missing prerequisite naming a DIFFERENT target,
  ##   EXIT=1, parse error, missing make, timeout, non-"make <t>" identity)
  ##                                                              → tpProbeError
  ## A probe failure is NEVER collapsed into tpAbsent/tpExists (fail-closed).
  let parts = target.splitWhitespace()
  if parts.len != 2 or parts[0] != "make" or parts[1].len == 0:
    return tpProbeError
  let name = parts[1]
  let probeEnv = newStringTable({"LC_ALL": "C", "LANG": "C"})
  var p: Process
  try:
    p = startProcess("make", workingDir = repoRoot, args = ["-n", name],
                     env = probeEnv, options = {poUsePath, poStdErrToStdOut})
  except:
    return tpProbeError
  let outStr = p.outputStream.readAll()
  discard p.waitForExit()
  let code = p.peekExitCode()
  p.close()
  if code == 0:
    return tpExists
  if code == 2:
    # ABSENT ONLY when the missing name is the requested target itself. A missing
    # prerequisite names a DIFFERENT target in the same message → tpProbeError.
    if ("No rule to make target '" & name & "'") in outStr:
      return tpAbsent
  return tpProbeError

# --- Report helpers ----------------------------------------------------------

type FindingKind = enum FKError, FKWarning

proc severityLabel(kind: FindingKind): string =
  case kind
  of FKError: "ERROR"
  of FKWarning: "WARNING"

# --- Validation                                                              ----

proc validateDocPaths(repoRoot: string, fixMode: bool, whitelist: WhitelistConfig,
                      skipCfg: SkipConfig, policyCfg: ReferencePolicyConfig):
    tuple[ok: bool, report: string, staleEntries: seq[StaleEntry], errorCount: int, warningCount: int] =
  var errorCount = 0
  var warningCount = 0
  var staleEntries: seq[StaleEntry] = @[]
  var realPaths: seq[string]
  var referencedPaths: seq[string] = @[]   # S8: canonicalized paths actually referenced by active docs
  if fixMode:
    realPaths = collectRealPaths(repoRoot)

  # Memoized native `make -n` probe per distinct reproducer target: avoids
  # spawning a subprocess once per reference that shares the same target.
  var probeCache: Table[string, TargetProbe]
  proc probeFor(target: string): TargetProbe =
    if not probeCache.hasKey(target):
      probeCache[target] = probeMakeTarget(repoRoot, target)
    probeCache[target]

  proc processDoc(docFile: string, content: string) =
    for (path, ptype) in extractPaths(content):
      # S8: every extracted reference (regardless of whitelist) contributes to the
      # referenced-path set used to detect dead policy entries. Whitelisted paths
      # are still referenced in the doc; they just are not validated here.
      referencedPaths.add(path)

      # Skip whitelisted paths
      if isWhitelisted(path, whitelist):
        continue

      let fullPath = repoRoot / path

      # Handle .agents/ gracefully: warn instead of error if dir absent
      if path.startsWith(".agents/") and not dirExists(repoRoot / ".agents"):
        case ptype
        of PTLink: warningCount.inc
        of PTBacktick: warningCount.inc
        of PTProse: warningCount.inc
        staleEntries.add(StaleEntry(docFile: docFile, stalePath: path,
                                    suggestedPath: "", distance: 0, patternType: ptype))
        continue

      if not fileExists(fullPath):
        # Reference resolution policy (docs/spec/document_reference_contract.md):
        # absence is permitted ONLY by an explicit HISTORICAL_ALLOWED /
        # EXTERNAL_ALLOWED carve-out, or a GENERATED_ALLOWED carve-out backed by a
        # CONFIRMED-EXISTING canonical reproducer target (native make -n probe).
        # Unclassified = MUST_EXIST (fail-closed). A malformed manifest is handled
        # at load. The decision is delegated to the PURE core resolver.
        let pol = referencePolicyFor(policyCfg, path)
        var probe = tpExists   # sentinel; only GENERATED_ALLOWED consumes the probe
        if pol.policy == rpGeneratedAllowed:
          probe = probeFor(pol.reproducerTarget)
        let (allowed, reason) = resolveReferencePolicy(pol, probe)
        if allowed:
          continue
        let parentDir = repoRoot / path.parentDir()
        if not dirExists(parentDir):
          case ptype
          of PTLink: errorCount.inc
          of PTBacktick: warningCount.inc
          of PTProse: warningCount.inc
          staleEntries.add(StaleEntry(docFile: docFile, stalePath: path,
                                      suggestedPath: "", distance: 0, patternType: ptype,
                                      resolveReason: reasonText(reason)))
          if fixMode:
            let (suggested, dist) = findClosestPath(path, realPaths)
            staleEntries[staleEntries.high].suggestedPath = suggested
            staleEntries[staleEntries.high].distance = dist
          continue

        var found = false
        var realPath = ""
        let targetName = path.extractFilename().toLowerAscii()
        for candidate in walkDirRec(parentDir):
          if candidate.extractFilename().toLowerAscii() == targetName:
            found = true
            realPath = path.parentDir() / candidate.extractFilename()
            break
        if not found:
          case ptype
          of PTLink: errorCount.inc
          of PTBacktick: warningCount.inc
          of PTProse: warningCount.inc
          staleEntries.add(StaleEntry(docFile: docFile, stalePath: path,
                                      suggestedPath: "", distance: 0, patternType: ptype,
                                      resolveReason: reasonText(reason)))
          if fixMode:
            let (suggested, dist) = findClosestPath(path, realPaths)
            staleEntries[staleEntries.high].suggestedPath = suggested
            staleEntries[staleEntries.high].distance = dist
        elif realPath != path:
          case ptype
          of PTLink: errorCount.inc
          of PTBacktick: warningCount.inc
          of PTProse: warningCount.inc
          staleEntries.add(StaleEntry(docFile: docFile, stalePath: path,
                                      suggestedPath: realPath, distance: 0, patternType: ptype,
                                      resolveReason: reasonText(reason)))

  # Scan docs/**/*.md
  let docsDir = repoRoot / "docs"
  if dirExists(docsDir):
    for mdFile in walkDirRec(docsDir):
      if not mdFile.endsWith(".md"):
        continue
      let relDoc = mdFile.relativePath(repoRoot)
      # Skipped/forward-plan docs are excluded entirely (DEBT#403): their
      # refs — whether historical or normative future-path references — are
      # neither extracted nor counted.
      if isSkippedDoc(relDoc, skipCfg):
        continue
      let content = readFile(mdFile)
      processDoc(mdFile, content)

  # Scan AGENTS.md
  let agentsPath = repoRoot / "AGENTS.md"
  if fileExists(agentsPath):
    let agentsContent = readFile(agentsPath)
    processDoc("AGENTS.md", agentsContent)

  # S8 — unused policy entries (INVARIANT: a declared carve-out that no active doc
  # reference uses is a DEAD exception → FAIL, preventing silent drift). The cross
  # check runs on the canonicalized referenced set (case-/slash-/shape-normalized).
  let unusedPolicies = findUnusedPolicyEntries(policyCfg, referencedPaths)

  # Build report
  var lines: seq[string] = @[]
  if errorCount + warningCount > 0:
    result.ok = false
    lines.add("[DOC-PATH-VALIDATOR] " & $errorCount & " error(s), " & $warningCount & " warning(s) found:")
    for entry in staleEntries:
      let sev = severityLabel(if entry.patternType == PTLink: FKError else: FKWarning)
      let hint = if entry.suggestedPath.len > 0: " (did you mean '" & entry.suggestedPath & "'?)" else: ""
      let why = if entry.resolveReason.len > 0: " — " & entry.resolveReason else: ""
      lines.add("  [" & sev & "] " & entry.docFile & ": '" & entry.stalePath & "'" & hint & why)
  if unusedPolicies.len > 0:
    result.ok = false
    lines.add("[DOC-PATH-VALIDATOR] " & $unusedPolicies.len &
              " unused reference-policy entr" & (if unusedPolicies.len == 1: "y" else: "ies") &
              " (declared but never referenced by any active doc):")
    for key in unusedPolicies:
      lines.add("  [ERROR] unused policy entry: '" & key & "' — " &
                reasonText(rrUnusedPolicy))
  if errorCount + warningCount > 0 or unusedPolicies.len > 0:
    lines.add("")
    lines.add("수정 제안: 위 경로를 실제 존재하는 파일로 변경·삭제하거나, 사용하지 않는 정책 entry를 제거하십시오.")
    result.report = lines.join("\n")
  else:
    result.ok = true
    result.report = "[DOC-PATH-VALIDATOR] 모든 문서 경로가 유효합니다."

  result.errorCount = errorCount
  result.warningCount = warningCount

# --- Main --------------------------------------------------------------------

proc main() =
  let repoRoot = if paramCount() >= 1: paramStr(1) else: getCurrentDir()
  var useJson = false
  var fixMode = false
  var archivedPath = ""
  var policyPath = ""
  var i = 2
  while i <= paramCount():
    case paramStr(i)
    of "--json": useJson = true
    of "--fix": fixMode = true
    of "--archived":
      if i < paramCount():
        inc(i)
        archivedPath = paramStr(i)
    of "--policy":
      if i < paramCount():
        inc(i)
        policyPath = paramStr(i)
    else: discard
    inc(i)

  let whitelist = loadWhitelist(repoRoot)
  let skipFile =
    if archivedPath.len > 0: archivedPath
    else: repoRoot / "tools" / "ci" / "archived_docs.json"
  let skipCfg = loadSkipConfig(skipFile)
  let policyFile =
    if policyPath.len > 0: policyPath
    else: repoRoot / "tools" / "ci" / "doc_reference_policy.json"
  let policyCfg = loadReferencePolicy(policyFile)
  if policyCfg.malformed:
    echo "[DOC-PATH-VALIDATOR] FAIL: malformed reference policy manifest: " &
         policyCfg.malformedReason
    quit(1)
  let (ok, report, staleEntries, errorCount, warningCount) =
    validateDocPaths(repoRoot, fixMode, whitelist, skipCfg, policyCfg)

  if fixMode and staleEntries.len > 0:
    echo "[DOC-PATH-VALIDATOR] Suggested fixes:"
    for entry in staleEntries:
      if entry.suggestedPath.len > 0:
        echo "  " & entry.docFile & ": " & entry.stalePath & " → " &
             entry.suggestedPath & " (distance: " & $entry.distance & ")"
      else:
        echo "  " & entry.docFile & ": " & entry.stalePath & " → (no close match found)"

  if useJson:
    var fixes: seq[JsonNode] = @[]
    for entry in staleEntries:
      fixes.add(%* {
        "docFile": entry.docFile,
        "stalePath": entry.stalePath,
        "suggestedPath": entry.suggestedPath,
        "distance": entry.distance,
        "patternType": case entry.patternType
                       of PTLink: "link"
                       of PTBacktick: "backtick"
                       of PTProse: "prose"
      })
    let j = %* {"ok": ok, "report": report, "fixes": fixes,
                "errors": errorCount, "warnings": warningCount}
    echo j.pretty()
    # INVARIANT: `ok` is the sole exit authority in both --json and default
    # output modes. A non-ok result must yield a non-zero exit regardless of
    # output format (fail-closed); otherwise a stale/missing doc reference
    # would pass CI silently via --json.
    if not ok:
      quit(1)
  else:
    if not fixMode:
      echo report
    if not ok:
      quit(1)

when isMainModule:
  main()
