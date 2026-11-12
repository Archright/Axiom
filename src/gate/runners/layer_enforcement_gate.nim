import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## Layer Enforcement Gate — Runtime layer import validator
##
## Recursively enumerates all .nim files under src/ and tools/,
## computes each file's layer via inferLayer(), scans import/from lines,
## and checks each import target against LayerRules via isAllowedImport().
##
## RL-14.4 pair exceptions (S3): the per-(source file, import target) registry
## in src/gate/architecture_policy.lock (`core_to_verification_pairs`) is
## parsed at startup and INJECTED into isAllowedImport as its `approved`
## parameter. The judging function (core/trusted/layer_rules.nim) consumes the
## data — this gate never re-codes the rule (decision doc
## docs/history/debt/rl14-4-crossing-decision-2026-10-11.md §4).
##
## Verdicts are distinct so falsification tests can assert the exact outcome:
##   [rejected]  import parsed, denied by LayerRules (no approved pair covers it)
##   [unparsed]  import target yields no canonical path — denied fail-closed
##
## CLI modes:
##   --report-only  Print violations, exit 0
##   --strict       Print violations, exit 1 if any (default)

import std/[os, strutils, tables, algorithm, times, options]
import core/trusted/layer_enforcement
import core/trusted/layer_rules
import core/trusted/axiom_pragmas
import core/utils/repo_root
import infrastructure/logging_facade



const GateTag = "[layer-enforcement-gate]"
const PolicyLockPath = "src/gate/architecture_policy.lock"
const PairRegistryKey = "core_to_verification_pairs"

type
  LayerViolationKind* = enum
    vkForbiddenImport   ## a classified file imports a forbidden/unallowed target
    vkUnknownLayer      ## a file whose path maps to no registered layer (fail-closed)

  ViolationVerdict = enum
    vvRejected   ## parsed import denied by the layer rules
    vvUnparsed   ## target yields no canonical path — fail-closed denial

  Violation = object
    kind: LayerViolationKind = vkForbiddenImport
    file: string
    line: int          ## 0 for vkUnknownLayer (file-level record)
    target: string     ## "" for vkUnknownLayer
    srcLayer: string
    targetLayer: string
    verdict: ViolationVerdict = vvRejected

proc extractQuotedEntries(value: string): seq[string] =
  ## Extract the double-quoted elements of a single-line "[...]" array value.
  result = @[]
  let v = value.strip()
  if not (v.startsWith("[") and v.endsWith("]")):
    return
  var current = ""
  var inString = false
  for i in 1 ..< v.len - 1:
    let ch = v[i]
    if inString:
      if ch == '"':
        result.add(current)
        current = ""
        inString = false
      else:
        current.add(ch)
    elif ch == '"':
      inString = true

func isDateFormExpiry(expires: string): bool =
  expires.len == 10 and expires.count('-') == 2

proc parsePairRegistry(lockPath: string): seq[(string, string)]
    {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read the pair-level exception registry from the policy lock.
  ## Entry format: "source.nim|target|reason|expires". Only (source, target)
  ## is injected — that is the judging function's parameter contract (DEBT#495).
  ## Date-form expiries in the past are dropped: an expired exception reverts
  ## to a violation (decision doc §3.2, fail closed). Non-date expiries
  ## (e.g. "v0.5.0") are release-gated and kept.
  ## Absent, unreadable or malformed registry => @[] — no exceptions granted.
  result = @[]
  if not fileExists(lockPath):
    logError("layer_enforcement_gate",
      GateTag & " policy lock not found: " & lockPath & " — no pair exceptions granted")
    return
  let content = readFile(lockPath)
  var found = false
  for line in content.splitLines():
    let stripped = line.strip()
    if stripped.len == 0 or stripped.startsWith("#"):
      continue
    if not (stripped.startsWith(PairRegistryKey) and stripped.contains('=')):
      continue
    found = true
    let eqIdx = stripped.find('=')
    for entry in extractQuotedEntries(stripped[(eqIdx + 1)..^1]):
      let fields = entry.split('|')
      if fields.len != 4:
        logError("layer_enforcement_gate",
          GateTag & " malformed pair entry (expected source|target|reason|expires): " & entry)
        continue
      let expires = fields[3].strip()
      if isDateFormExpiry(expires):
        var expired = false
        try:
          expired = times.parse(expires, "yyyy-MM-dd") < times.now()
        except CatchableError:
          expired = true  # unparseable expiry grants nothing (fail closed)
        if expired:
          logInfo("layer_enforcement_gate",
            GateTag & " expired pair exception dropped: " & fields[0].strip() &
            " -> " & fields[1].strip() & " (expires " & expires & ")")
          continue
      result.add((fields[0].strip(), fields[1].strip()))
    break
  if not found:
    logError("layer_enforcement_gate",
      GateTag & " pair registry '" & PairRegistryKey & "' not found in " & lockPath &
      " — no pair exceptions granted")

proc splitImportList(importPart: string): seq[string] =
  ## Comma-split that respects bracket groups: `std/[a, b]` stays ONE token
  ## so the SSOT's expandImportTargets (contract rule 6) sees the full form.
  result = @[]
  var current = ""
  var depth = 0
  for ch in importPart:
    if ch == '[':
      inc depth
    elif ch == ']' and depth > 0:
      dec depth
    if ch == ',' and depth == 0:
      result.add(current.strip())
      current = ""
    else:
      current.add(ch)
  result.add(current.strip())

func unclosedBrackets(s: string): int =
  result = 0
  for ch in s:
    if ch == '[':
      inc result
    elif ch == ']' and result > 0:
      dec result

proc judgeTarget(filepath: string; lineNum: int; srcLayer, target: string;
                 approved: seq[(string, string)]): Option[Violation] =
  ## Rule 10 / DEBT#495 seam: one import target -> at most one verdict.
  ## Empty resolution is UNPARSED (fail closed), a non-path import is out of
  ## layer scope, and a denied path is REJECTED.
  if target.len == 0:
    return some(Violation(
      file: filepath, line: lineNum,
      target: "<unparsable>", srcLayer: srcLayer,
      targetLayer: "unparsed", verdict: vvUnparsed))
  if not target.contains("/"):
    return none(Violation)  # non-path import (std module, same-dir) — outside layer-path scope
  if resolveImportTarget(filepath, target).len == 0:
    # rule 10 (layer_rules.nim contract): uninterpretable import form —
    # the judge signals it with an empty resolution; report as UNPARSED.
    return some(Violation(
      file: filepath, line: lineNum,
      target: target, srcLayer: srcLayer,
      targetLayer: "unparsed", verdict: vvUnparsed))
  if not isAllowedImport(filepath, target, approved):
    return some(Violation(
      file: filepath, line: lineNum,
      target: target, srcLayer: srcLayer,
      targetLayer: inferLayer(target), verdict: vvRejected))
  none(Violation)

proc scanFile(filepath: string; approved: seq[(string, string)]):
    tuple[violations: seq[Violation], edges: int] =
  result.violations = @[]
  if filepath.contains("/trusted/"):
    return
  let srcLayer = inferLayer(filepath)
  if srcLayer == "unknown":
    # DEBT#287 fail-closed: an unclassified file bypasses every import rule,
    # so "unknown" is itself a violation — never a silent skip.
    result.violations.add(Violation(kind: vkUnknownLayer, file: filepath))
    return
  let content = readFile(filepath)
  let lines = content.splitLines()
  var idx = 0
  while idx < lines.len:
    let lineNum = idx + 1
    let stripped = lines[idx].strip()
    inc idx
    var targets: seq[string] = @[]
    if stripped.startsWith("import "):
      # join continuation lines until the bracket group closes so multi-line
      # `import std/[a, b, ...]` statements are judged as one statement
      var stmt = stripped
      while unclosedBrackets(stmt) > 0 and idx < lines.len:
        stmt.add(" ")
        stmt.add(lines[idx].strip())
        inc idx
      let importPart = stmt[7..^1].strip()
      for tok in splitImportList(importPart):
        # pass the token whole: alias/except stripping and bracket expansion
        # are the SSOT normalizeImportPath/expandImportTargets contract
        targets.add(tok.strip())
    elif stripped.startsWith("from "):
      let parts = stripped.split(" import ")
      if parts.len >= 1:
        let head = parts[0]
        targets.add(if head.len >= 5: head[5..^1].strip() else: "")
    for target in targets:
      if target.len > 0 and target.contains("/"):
        inc result.edges
      let verdict = judgeTarget(filepath, lineNum, srcLayer, target, approved)
      if verdict.isSome:
        result.violations.add(verdict.get)

proc enumerateNimFiles(root: string): seq[string] =
  result = @[]
  for path in walkDirRec(root):
    if path.endsWith(".nim"):
      result.add(path)

func targetLayerEstimate(target: string): string {.raises: [].} =
  ## Display-only target-layer estimate for violation messages. Imports are
  ## written without the src/ prefix (e.g. "mcp/tools") while inferLayer
  ## classifies repo-relative paths (e.g. "src/mcp/tools.nim"), so the raw
  ## target infers "unknown" for every internal target (DEBT#287 evidence,
  ## display-only blind spot). Retry on the canonical repo-relative form;
  ## verdicts still come solely from isAllowedImport.
  let direct = inferLayer(target)
  if direct != "unknown":
    return direct
  let viaSrc = inferLayer("src/" & normalizeImportPath(target))
  if viaSrc != "unknown":
    return viaSrc
  result = "unknown"

func denyTrace(srcLayer, target: string): string {.raises: [].} =
  ## Display-only diagnostic mirroring isAllowedImport's denial paths —
  ## names the consulted rule and the forbidden prefix that denied the
  ## import, or the missing rule (fail-closed). This trace never feeds back
  ## into the verdict; isAllowedImport remains the sole adjudicator.
  let canonical = normalizeImportPath(target)
  for rule in LayerRules:
    if srcLayer == inferLayer(rule.source):
      for forbidden in rule.forbiddenImports:
        if canonical.startsWith(forbidden):
          return "denied by rule " & rule.source &
                 " (forbidden prefix '" & forbidden & "')"
      return "denied by rule " & rule.source & " (no allowed prefix matched)"
  result = "denied: no rule registered for layer '" & srcLayer & "' (fail-closed)"

func unregisteredPrefix(path: string): string {.raises: [].} =
  ## Display-only: the leading two path segments of an unclassified file —
  ## the prefix family that carries no inferLayer rule.
  let normalized = path.replace("\\", "/")
  let segs = normalized.split("/")
  if segs.len >= 2:
    return segs[0] & "/" & segs[1] & "/"
  result = normalized

func jsonEscape(s: string): string {.raises: [].} =
  result = "\""
  for c in s:
    case c
    of '"': result.add("\\\"")
    of '\\': result.add("\\\\")
    of '\n': result.add("\\n")
    of '\r': result.add("\\r")
    of '\t': result.add("\\t")
    else: result.add(c)
  result.add("\"")

func violationVerdictName(v: ViolationVerdict): string {.raises: [].} =
  case v
  of vvRejected: "rejected"
  of vvUnparsed: "unparsed"

proc renderJson(totalFiles, totalEdges: int, layerCounts: CountTable[string],
                allViolations: seq[Violation]): string =
  ## Hand-built JSON with fixed key order — deterministic bytes for identical
  ## input (std/json object fields are hash-ordered, which is not).
  let verdict = if allViolations.len == 0: "PASS" else: "FAIL"
  result = "{"
  result.add("\"gate\": \"layer-enforcement-gate\"")
  result.add(", \"verdict\": " & jsonEscape(verdict))
  result.add(", \"fileCount\": " & $totalFiles)
  result.add(", \"edgeCount\": " & $totalEdges)
  var layers: seq[string] = @[]
  for layer in layerCounts.keys():
    layers.add(layer)
  layers.sort()
  result.add(", \"layerCounts\": {")
  for i, layer in layers:
    if i > 0: result.add(", ")
    result.add(jsonEscape(layer) & ": " & $layerCounts[layer])
  result.add("}")
  result.add(", \"violations\": [")
  for i, v in allViolations:
    if i > 0: result.add(", ")
    case v.kind
    of vkForbiddenImport:
      result.add("{\"kind\": \"forbiddenImport\", \"verdict\": " &
        jsonEscape(violationVerdictName(v.verdict)) &
        ", \"file\": " & jsonEscape(v.file) &
        ", \"line\": " & $v.line &
        ", \"target\": " & jsonEscape(v.target) &
        ", \"srcLayer\": " & jsonEscape(v.srcLayer) &
        ", \"targetLayer\": " & jsonEscape(v.targetLayer) &
        ", \"targetLayerEstimate\": " & jsonEscape(targetLayerEstimate(v.target)) &
        ", \"deniedBy\": " & jsonEscape(denyTrace(v.srcLayer, v.target)) & "}")
    of vkUnknownLayer:
      result.add("{\"kind\": \"unknownLayer\", \"file\": " & jsonEscape(v.file) &
        ", \"unregisteredPrefix\": " & jsonEscape(unregisteredPrefix(v.file)) & "}")
  result.add("]")
  result.add("}")

func renderViolation(v: Violation): string {.raises: [].} =
  ## Single human-readable rendering of a violation (SSOT for the log path).
  ## Diagnostic suffixes are display-only traces (denyTrace /
  ## targetLayerEstimate); verdicts remain isAllowedImport's. The verdict
  ## vocabulary is the RL-14.4 falsification axis: [rejected] = parsed and
  ## denied, [unparsed] = fail-closed no-canonical-path.
  case v.kind
  of vkForbiddenImport:
    case v.verdict
    of vvRejected:
      "LAYER VIOLATION[rejected]: " & v.file & ":" & $v.line &
      " imports '" & v.target & "' (" & targetLayerEstimate(v.target) &
      " from " & v.srcLayer & ") — " & denyTrace(v.srcLayer, v.target)
    of vvUnparsed:
      "LAYER VIOLATION[unparsed]: " & v.file & ":" & $v.line &
      " fail-closed — import target does not resolve to a canonical path ('" & v.target & "')"
  of vkUnknownLayer:
    "LAYER VIOLATION: " & v.file &
    " — unclassified layer (fail-closed, DEBT#287): no inferLayer rule matches this path" &
    " (unregistered prefix '" & unregisteredPrefix(v.file) & "')"

proc main() =
  let args = commandLineParams()
  let reportOnly = args.contains("--report-only")
  let jsonMode = args.contains("--json")
  let strict = args.contains("--strict") or not reportOnly

  let repoRoot = findRepoRoot()
  setCurrentDir(repoRoot)
  # The policy lock is the tool's AUTHORITY, not sandbox input: AXIOM_ROOT scopes
  # which files are scanned (negative fixtures isolate the scan target), but the
  # approved-exception registry must always come from the real repository.
  # Resolve it against the repo root first, then against the binary's install dir
  # (bin/ -> <repo>/src/gate/architecture_policy.lock) so a fixture AXIOM_ROOT
  # cannot silently drop the approved pairs.
  var lockPath = PolicyLockPath
  if not fileExists(lockPath):
    let candidate = getAppDir().parentDir / PolicyLockPath
    if fileExists(candidate):
      lockPath = candidate
  let approvedPairs = parsePairRegistry(lockPath)
  logInfo("layer_enforcement_gate",
    GateTag & " pair registry: " & $approvedPairs.len &
    " active exception pair(s) injected into isAllowedImport")

  var allViolations: seq[Violation] = @[]
  var totalFiles = 0
  var totalEdges = 0
  var layerCounts: CountTable[string] = initCountTable[string]()

  for dir in ["src", "tools"]:
    if dirExists(dir):
      var files = enumerateNimFiles(dir)
      files.sort()  # determinism: identical tree → identical scan order
      for f in files:
        inc totalFiles
        inc(layerCounts, inferLayer(f))
        let (vs, edges) = scanFile(f, approvedPairs)
        inc(totalEdges, edges)
        allViolations.add(vs)

  if jsonMode:
    stdout.writeLine(renderJson(totalFiles, totalEdges, layerCounts, allViolations))

  if allViolations.len == 0:
    logInfo("layer_enforcement_gate", GateTag & " PASS — no layer violations in " & $totalFiles & " files")
    quit(0)

  logError("layer_enforcement_gate", GateTag & " " & $(allViolations.len) & " layer violation(s) in " & $totalFiles & " files:")
  for v in allViolations:
    logError("layer_enforcement_gate", renderViolation(v))

  if strict:
    logError("layer_enforcement_gate", GateTag & " BLOCKED — fix violations or run with --report-only to preview")
    quit(1)
  else:
    logInfo("layer_enforcement_gate", GateTag & " REPORT-ONLY mode — would block " & $(allViolations.len) & " violation(s) in strict mode")
    quit(0)

when isMainModule:
  main()

{.pop.}
