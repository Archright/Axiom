## decision_binding_checker.nim — Native Binary for Decision Binding Audit
##
## Scans Nim source files for missing {.axiomDecision.} pragmas on decision-point
## functions. Used by hermetic_build.nim during pre-build checks.
##
## Usage:
##   decision_binding_checker --staged-only --scope <file>       # Strict mode
##   decision_binding_checker --audit-mode --scope <file>        # Warning only
##   decision_binding_checker --audit-mode                       # Full audit
##   decision_binding_checker --staged-only                      # Strict, all staged
##
## The judgment itself is a count ratchet and lives in
## `tools/decision_binding_judge.nim` — the single policy kernel shared with
## the build-time hook. There is no expiry threshold here: a calendar must not
## be able to stop a build.
##
## Exit codes:
##   0 — Clean, or at or below the ratchet baseline, or audit mode
##   1 — The ratchet grew, or the baseline is absent/malformed/drifted
##       (fail-closed), or the canonical waiver set could not be loaded
##       (fail-closed), or a waiver entry references a file absent from the
##       repository tree (stale waiver — fail-closed)

import std/[algorithm, json, os, osproc, strutils, times]
import decision_binding_judge

# ── Deterministic Root Resolution ────────────────────────────────────────────
proc findProjectRoot(): string =
  var dir = getCurrentDir()
  while true:
    if fileExists(dir / ".axiom_root"):
      return dir
    let parent = dir.parentDir()
    if parent == dir:
      break
    dir = parent
  quit("ERROR: .axiom_root not found. Run from Axiom project directory.")

let projectRoot = findProjectRoot()

# ── Decision Point Detection (string scanning) ───────────────────────────────

func hasResultOrOptionReturn*(sig: string): bool =
  let lower = sig.toLowerAscii()
  "result[" in lower or "option[" in lower

func hasEarlyReturns*(body: string): bool =
  var returns = 0
  var guarded = 0
  let lines = body.split("\n")
  for line in lines:
    let s = line.strip()
    if s.startsWith("return") and s.len > 6:
      inc returns
      let idx = lines.find(line)
      for j in countdown(max(0, idx - 5), max(0, idx - 1)):
        let prev = lines[j].strip().toLowerAscii()
        if prev.startsWith("if ") or prev.startsWith("elif ") or
           prev.startsWith("when ") or prev.startsWith("guard "):
          inc guarded
          break
  returns >= 2 and guarded > 0

func hasValidation*(body: string): bool =
  for line in body.split("\n"):
    let s = line.strip()
    if s.startsWith("assert(") or s.startsWith("check(") or s.startsWith("guard "):
      return true
  return false

func isExemptedPath*(path: string): bool =
  for pat in ["/generated/", "/nimcache/", "_test.nim", "_feature_test.nim", "/tests/", "mock_", "stubs/"]:
    if pat in path:
      return true
  return false

# ── Waiver Loading ───────────────────────────────────────────────────────────
##
## config/decision_binding.waiver.json is the runtime-canonical waiver set and
## the only format this checker reads. There is deliberately no second format
## and no partial fallback: a waiver set that cannot be obtained in full is a
## hard fail-closed outcome. An exemption list that silently degrades to empty
## — or, worse, to a list of junk paths — under-reports violations, and an
## under-reported audit is indistinguishable from a clean one.
##
## Stale-waiver invariant: a grandfather entry whose `file` target no longer
## exists in the repository tree is a dead exemption — it can never match a
## scanned path, silently shrinks the waiver set, and outlives the file it
## once covered. Loading fails closed until the stale entry is removed; the
## entry must not be carried by the audit.

type
  WaiverEntry = object
    filePath: string
    reason: string
    expiresAt: string

  WaiverConfig = object
    exemptFiles: seq[string]
    exemptModules: seq[string]
    entries: seq[WaiverEntry]

  WaiverLoad = object
    config: WaiverConfig
    loaded: bool
    errorMsg: string

proc findStaleWaiverFiles(files: seq[string], repoRoot: string): seq[string] =
  ## Stale-waiver invariant probe: returns the repo-root-relative paths in
  ## `files` whose target does not exist in the repository tree, deduplicated,
  ## in file order. Callers fail closed on any hit — a waiver whose target is
  ## gone must be removed from the waiver file, not carried.
  var stale: seq[string] = @[]
  for f in files:
    if not fileExists(repoRoot / f) and f notin stale:
      stale.add(f)
  stale

proc loadWaiver(repoRoot: string): WaiverLoad =
  ## Loads the canonical waiver set. Every rejection path returns
  ## `loaded = false` with a diagnostic naming the offending file/entry, so a
  ## missing or malformed authority is reported deliberately rather than
  ## surfacing as an incidental exception mid-audit.
  let path = repoRoot / "config" / "decision_binding.waiver.json"

  if not fileExists(path):
    result.errorMsg = "canonical waiver file not found: " & path
    return

  var content: string
  try:
    content = readFile(path)
  except CatchableError as e:
    result.errorMsg = "canonical waiver file unreadable: " & path & " (" & e.msg & ")"
    return

  var root: JsonNode
  try:
    root = parseJson(content)
  except CatchableError as e:
    result.errorMsg = "canonical waiver file is not valid JSON: " & path & " (" & e.msg & ")"
    return

  if root.kind != JObject or not root.hasKey("grandfather") or
      root["grandfather"].kind != JArray:
    result.errorMsg = "canonical waiver file has no \"grandfather\" array: " & path
    return

  let today = utc(now()).format("yyyy-MM-dd")

  # Every grandfather `file` target, expired or not — the stale-waiver
  # invariant applies to the whole array, not just the active subset.
  var grandfatherFiles: seq[string] = @[]

  # Index-based: `for i, entry in <JsonNode JArray>` resolves to json.pairs(),
  # which asserts JObject and aborts the whole audit on a well-formed file.
  for i in 0 ..< root["grandfather"].len:
    let entry = root["grandfather"][i]
    if entry.kind != JObject or not entry.hasKey("file") or
        entry["file"].kind != JString:
      result.errorMsg = "canonical waiver entry " & $i &
        " has no string \"file\" field: " & path
      return
    let filePath = entry["file"].getStr()
    grandfatherFiles.add(filePath)
    let reason = if entry.hasKey("reason") and entry["reason"].kind == JString:
                   entry["reason"].getStr()
                 else:
                   ""
    let expires = if entry.hasKey("expires") and entry["expires"].kind == JString:
                    entry["expires"].getStr()
                  else:
                    ""
    if expires.len > 0:
      try:
        discard parse(expires, "yyyy-MM-dd")
      except CatchableError:
        result.errorMsg = "canonical waiver entry " & $i &
          " has an unparsable \"expires\" value (" & expires & "): " & path
        return

    if expires.len > 0 and expires < today:
      echo "[decision-binding] WAIVER EXPIRED: " & filePath & " (expired " & expires & ")"
    elif filePath notin result.config.exemptFiles:
      result.config.exemptFiles.add(filePath)
      result.config.entries.add(
        WaiverEntry(filePath: filePath, reason: reason, expiresAt: expires))

  # Stale-waiver invariant (fail-closed): every grandfather entry's `file`
  # must resolve to a file in the repository tree. A missing target makes the
  # entry a stale waiver — it can never match a scanned path, silently shrinks
  # the exemption set, and outlives the file it once covered. The entry must
  # be removed from the waiver file, not carried by the audit.
  let staleFiles = findStaleWaiverFiles(grandfatherFiles, repoRoot)
  if staleFiles.len > 0:
    result.errorMsg = "stale waiver(s) — grandfather entries whose file is absent from the repository tree:\n  " &
      staleFiles.join("\n  ") &
      "\n  (remove these stale entries from " & path & ")"
    return

  result.loaded = true
  echo "[decision-binding] Loaded " & $result.config.entries.len &
    " active waiver(s) from decision_binding.waiver.json"

func isFileExempt*(filePath: string, config: WaiverConfig): bool =
  for f in config.exemptFiles:
    if filePath.endsWith(f) or filePath == f:
      return true
  return false

func isModuleExempt*(moduleName: string, config: WaiverConfig): bool =
  for m in config.exemptModules:
    if moduleName.startsWith(m) or m in moduleName:
      return true
  return false

# ── Single File Scan ─────────────────────────────────────────────────────────

proc scanFile(filePath: string, waiver: WaiverConfig): tuple[violations: bool, reasons: seq[string]] =
  result = (false, @[])
  if not filePath.endsWith(".nim"):
    return
  if isExemptedPath(filePath):
    return
  if isFileExempt(filePath, waiver):
    return

  try:
    let content = readFile(filePath)
    let lines = content.split("\n")
    var i = 0
    while i < lines.len:
      let line = lines[i]
      let stripped = line.strip()

      if stripped.startsWith("#") or stripped.startsWith("##"):
        inc i
        continue

      if stripped.startsWith("proc ") or stripped.startsWith("func "):
        # Skip nested (indented) procs — internal helpers, exempt per R3
        if line.len > 0 and line[0] in {' ', '\t'}:
          inc i
          continue
        # Skip private (no export *) procs — exempt per R3
        let procTail = if stripped.startsWith("proc "): stripped[5..^1] else: stripped[5..^1]
        if '*' notin procTail:
          inc i
          continue

        # Check if already has axiomDecision pragma (any placement in the pragma
        # list — standalone {.axiomDecision.} or comma-separated {.raises: [], axiomDecision.})
        let hasPragma = "axiomDecision" in stripped or
                        "axiomDecision" in line

        if not hasPragma:
          # Collect proc signature (may span multiple lines)
          var sig = stripped
          var braceDepth = 0
          for ch in stripped:
            if ch == '{': inc braceDepth
            elif ch == '}': dec braceDepth

          var j = i + 1
          while braceDepth > 0 and j < lines.len and j < i + 20:
            let contLine = lines[j].strip()
            if contLine.startsWith("#"):
              inc j
              continue
            sig &= " " & contLine
            for ch in contLine:
              if ch == '{': inc braceDepth
              elif ch == '}': dec braceDepth
            inc j

          # Also collect a pragma block that follows the signature on the
          # next line (Nim allows: proc sig\n  {.pragma...}. =)
          if "axiomDecision" notin sig and j < lines.len:
            let nextLine = lines[j].strip()
            if nextLine.startsWith("{."):
              var pragmaDepth = 0
              for ch in nextLine:
                if ch == '{': inc pragmaDepth
                elif ch == '}': dec pragmaDepth
              sig &= " " & nextLine
              inc j
              while pragmaDepth > 0 and j < lines.len and j < i + 25:
                let pl = lines[j].strip()
                if pl.startsWith("#"):
                  inc j
                  continue
                sig &= " " & pl
                for ch in pl:
                  if ch == '{': inc pragmaDepth
                  elif ch == '}': dec pragmaDepth
                inc j

          # The pragma may be declared on continuation lines of a multi-line
          # signature ({.raises: [],\n   axiomDecision(...).}) — re-scan the
          # collected signature before flagging a violation.
          if "axiomDecision" in sig:
            inc i
            continue

          # Extract name
          let afterKw = if sig.startsWith("proc "): sig[5..^1] else: sig[5..^1]
          let nameEnd = min(
            if '(' in afterKw: afterKw.find('(') else: high(int),
            if '*' in afterKw: afterKw.find('*') else: high(int)
          )
          let procName = if nameEnd < afterKw.len: afterKw[0..<nameEnd].strip() else: afterKw.strip()

          # Collect body until next proc/func or EOF
          var bodyLines: seq[string] = @[]
          var bodyStarted = false
          var k = j
          while k < lines.len:
            let bodyLine = lines[k].strip()
            if (bodyLine.startsWith("proc ") or bodyLine.startsWith("func ")) and bodyStarted:
              break
            if bodyLine.len > 0 and not bodyLine.startsWith("#"):
              bodyStarted = true
            if bodyStarted:
              bodyLines.add(lines[k])
            inc k

          let body = bodyLines.join("\n")

          # Check decision point indicators
          let returnTypeCheck = hasResultOrOptionReturn(sig)
          let earlyReturns = hasEarlyReturns(body)
          let validation = hasValidation(body)

          if returnTypeCheck or earlyReturns or validation:
            var reasons: seq[string] = @[]
            if returnTypeCheck:
              reasons.add("returns Result/Option without axiomDecision")
            if earlyReturns:
              reasons.add("multiple returns without axiomDecision")
            if validation:
              reasons.add("validation logic without axiomDecision")

            let msg = procName & " (" & filePath & ":" & $(i+1) & ") " & reasons.join("; ")
            result.violations = true
            result.reasons.add(msg)

      inc i
  except CatchableError:
    discard  # axiom:best-effort(unreadable-source-file: skip file, continue scanning remaining files)

# ── Walk Files ───────────────────────────────────────────────────────────────

proc walkSourceFiles(srcDir: string): seq[string] =
  var files: seq[string] = @[]
  proc walkRec(dir: string) =
    for kind, path in walkDir(dir):
      if kind == pcFile and path.endsWith(".nim"):
        files.add(path)
      elif kind == pcDir:
        walkRec(path)
  if dirExists(srcDir):
    walkRec(srcDir)
  return files

# ── Ratchet Baseline I/O ─────────────────────────────────────────────────────

proc loadBaseline(path: string): tuple[ok: bool, baseline: RatchetBaseline,
                                       error: string] =
  result = (false, RatchetBaseline(), "")
  if not fileExists(path):
    result.error = "ratchet baseline not found: " & path &
      " — fail-closed; author it, or re-anchor an existing one with --update-baseline"
    return
  var root: JsonNode
  try:
    root = parseJson(readFile(path))
  except CatchableError as e:
    result.error = "ratchet baseline is not valid JSON: " & path & " (" & e.msg & ")"
    return
  if root.kind != JObject:
    result.error = "ratchet baseline is not a JSON object: " & path
    return
  var b = RatchetBaseline()
  template strField(key: string): string =
    (if root.hasKey(key) and root[key].kind == JString: root[key].getStr() else: "")
  template intField(key: string): int =
    (if root.hasKey(key) and root[key].kind == JInt: root[key].getInt() else: -1)
  b.baselineVersion = intField("baselineVersion")
  b.gate = strField("gate")
  b.scope = strField("scope")
  b.owner = strField("owner")
  b.rationale = strField("rationale")
  b.reviewBy = strField("reviewBy")
  b.measuredAt = strField("measuredAt")
  b.sourceCommit = strField("sourceCommit")
  b.checkerVersion = strField("checkerVersion")
  b.policyHash = strField("policyHash")
  b.filesWithViolations = intField("filesWithViolations")
  b.totalReasons = intField("totalReasons")
  if root.hasKey("perReason") and root["perReason"].kind == JArray:
    for item in root["perReason"]:
      if item.kind == JObject and item.hasKey("reason") and item.hasKey("count") and
          item["reason"].kind == JString and item["count"].kind == JInt:
        b.perReason.add(ReasonCount(reason: item["reason"].getStr(),
                                    count: item["count"].getInt()))
  result = (true, b, "")

proc reasonHistogram(reasons: seq[string]): seq[ReasonCount] =
  for r in reasons:
    var hit = false
    for i in 0 ..< result.len:
      if result[i].reason == r:
        inc result[i].count
        hit = true
        break
    if not hit:
      result.add(ReasonCount(reason: r, count: 1))
  result.sort(proc (a, b: ReasonCount): int = cmp(a.reason, b.reason))

proc writeBaseline(path: string, files: int, reasons: seq[string],
                   measuredAt: string): string =
  ## Re-anchors the COUNTS only. The review contract (scope/owner/rationale/
  ## reviewBy) is authored by a human and is never regenerated here — a machine
  ## may measure the debt, it may not accept the risk.
  let prior = loadBaseline(path)
  if not prior.ok:
    return "cannot re-anchor: " & prior.error
  let b = prior.baseline
  let mayAnchor = reanchorProblem(files, reasons.len, b)
  if mayAnchor.len > 0:
    return mayAnchor
  var commit = "unknown"
  let rev = execCmdEx("git rev-parse HEAD")
  if rev.exitCode == 0 and rev.output.strip().len == 40:
    commit = rev.output.strip()
  var per = newJArray()
  for rc in reasonHistogram(reasons):
    per.add(%*{"reason": rc.reason, "count": rc.count})
  let node = %*{
    "baselineVersion": JudgeBaselineVersion,
    "gate": JudgeGateId,
    "scope": b.scope,
    "owner": b.owner,
    "rationale": b.rationale,
    "reviewBy": b.reviewBy,
    "measuredAt": measuredAt,
    "sourceCommit": commit,
    "checkerVersion": JudgeCheckerVersion,
    "policyHash": JudgePolicyHash,
    "filesWithViolations": files,
    "totalReasons": reasons.len,
    "perReason": per
  }
  try:
    writeFile(path, pretty(node) & "\n")
  except CatchableError as e:
    return "cannot write " & path & ": " & e.msg
  ""

# ── Main ─────────────────────────────────────────────────────────────────────

var stagedOnly = false
var auditMode = false
var scopeFile: string = ""
var baselineRel = "data/decision_binding_baseline.json"
var updateBaseline = false

var i = 1
while i <= paramCount():
  let arg = paramStr(i)
  case arg
  of "--staged-only":
    stagedOnly = true
  of "--audit-mode":
    auditMode = true
  of "--scope":
    if i + 1 <= paramCount():
      scopeFile = paramStr(i + 1)
      i += 1
  of "--baseline":
    if i + 1 <= paramCount():
      baselineRel = paramStr(i + 1)
      i += 1
    else:
      echo "[decision-binding] --baseline requires a path"
      quit(1)
  of "--update-baseline":
    updateBaseline = true
  of "--help", "-h":
    echo "Usage: decision_binding_checker [options]"
    echo ""
    echo "Options:"
    echo "  --staged-only              Only check staged files (requires git)"
    echo "  --audit-mode               Warn only, exit 0 even with violations"
    echo "  --baseline <path>          Ratchet baseline (default: data/decision_binding_baseline.json)"
    echo "  --update-baseline          Re-anchor the baseline to the current measurement"
    echo "  --scope <file>             Check a single file"
    echo "  --help, -h                 Show this help"
    quit(0)
  else:
    echo "Unknown option: " & arg
    quit(1)
  i += 1

let waiverLoad = loadWaiver(projectRoot)
if not waiverLoad.loaded:
  echo "[decision-binding] FAIL: " & waiverLoad.errorMsg
  echo "[decision-binding] FAIL: audit is fail-closed — it will not run against a missing, partial, malformed, or stale canonical waiver set"
  quit(1)
let waiver = waiverLoad.config
var violationCount = 0
var violations: seq[string] = @[]

if scopeFile.len > 0:
  # Single file mode
  let scanResult = scanFile(scopeFile, waiver)
  if scanResult.violations:
    inc violationCount
    for v in scanResult.reasons:
      violations.add(v)
elif stagedOnly:
  # Staged files mode
  let (output, exitCode) = execCmdEx("git diff --cached --name-only --diff-filter=ACMR 2>/dev/null")
  if exitCode != 0:
    echo "WARNING: git diff failed, skipping staged check"
  else:
    for line in output.strip().split("\n"):
      let f = line.strip()
      if f.len > 0 and f.endsWith(".nim"):
        let fullpath = projectRoot / f
        let scanResult = scanFile(fullpath, waiver)
        if scanResult.violations:
          inc violationCount
          for v in scanResult.reasons:
            violations.add(v)
else:
  # Full scan mode
  let srcDir = projectRoot / "src"
  for f in walkSourceFiles(srcDir):
    if isFileExempt(f, waiver):
      continue
    let relPath = f.replace(projectRoot & "/", "")
    if isModuleExempt(relPath, waiver):
      continue
    let scanResult = scanFile(f, waiver)
    if scanResult.violations:
      inc violationCount
      for v in scanResult.reasons:
        violations.add(v)

# Output results — a count of files is a count of files, never of "functions".
echo "[decision-binding] " & $violationCount & " file(s) / " & $violations.len &
  " reason(s) carry a missing {.axiomDecision.}"
for v in violations:
  echo "  " & v

if auditMode:
  echo "[decision-binding] Audit mode — no failures reported"
  quit(0)

let today = utc(now()).format("yyyy-MM-dd")
let measuredAt = utc(now()).format("yyyy-MM-dd") & "T" &
                 utc(now()).format("HH:mm:ss") & "Z"
let baselinePath = projectRoot / baselineRel

if updateBaseline:
  let err = writeBaseline(baselinePath, violationCount, violations, measuredAt)
  if err.len > 0:
    echo "[decision-binding] FAIL: " & err
    quit(1)
  echo "[decision-binding] baseline re-anchored: " & baselinePath & " (" &
    $violationCount & " files / " & $violations.len & " reasons)"
  quit(0)

let loaded = loadBaseline(baselinePath)
if not loaded.ok:
  echo "[decision-binding] FAIL: " & loaded.error
  quit(1)

let verdict = judgeDecisionBinding(violationCount, violations.len,
                                   loaded.baseline, today)
for m in verdict.messages:
  echo "[decision-binding] " & m
echo "[decision-binding] " & (if verdict.exitCode == 0: "PASS" else: "FAIL") &
  " (" & stateTag(verdict.state) & ")"
quit(verdict.exitCode)
