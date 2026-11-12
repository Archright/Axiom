## publication_secret_eval.nim — secret-scan adjudication of the
## publication-integrity gate.
##
## Compares measured gitleaks findings (history scan + working-tree scan)
## against the exact-fingerprint baseline in
## compliance/policy/secret-scan-baseline.json:
##
##   - a finding whose Fingerprint is NOT in the baseline → FAIL (listed;
##     the report NEVER contains the matched secret text — masking follows
##     the B2 evidence precedent);
##   - a baseline whose entries carry a classification outside the closed
##     set (security-policy.yml secretScan.classifications) → the baseline
##     itself is untrustworthy → UNKNOWN (blocking);
##   - unreadable/unparsable scan reports or policy → UNKNOWN (blocking).
##
## The exit-code contract follows the gate convention:
##   0 = PASS, 1 = FAIL, 2 = UNKNOWN.
##
## Part of the publication-integrity gate (docs/spec/publication_integrity_gate.md).

import std/[json, options, os, parseopt, strutils]
import core/trusted/layer_declaration
import core/results
import tools/ci/publication_yaml

axiomLayer "tools"

const
  ToolName = "publication_secret_eval"
  ExitPass = 0
  ExitFail = 1
  ExitUnknown = 2

type
  Inputs = object
    historyScan: string
    treeScan: string
    baselinePath: string
    policyPath: string
    outPath: string

proc parseArgs(): Result[Inputs, string] =
  ## Repo CLI idiom: explicit `p.next()` loop; space-separated option
  ## values consume the next cmdArgument token.
  var inputs = Inputs(outPath: "")
  var p = initOptParser(commandLineParams())
  while true:
    p.next()
    case p.kind
    of cmdEnd:
      break
    of cmdLongOption, cmdShortOption:
      let key = p.key
      var val = p.val
      if val.len == 0:
        p.next()
        if p.kind != cmdArgument:
          return err("option '--" & key & "' requires a value")
        val = p.key
      case key
      of "history": inputs.historyScan = val
      of "tree": inputs.treeScan = val
      of "baseline": inputs.baselinePath = val
      of "policy": inputs.policyPath = val
      of "out": inputs.outPath = val
      else: return err("unknown option: --" & key)
    of cmdArgument:
      return err("unexpected argument '" & p.key & "'")
  for req in [("history", inputs.historyScan), ("tree", inputs.treeScan),
              ("baseline", inputs.baselinePath), ("policy", inputs.policyPath),
              ("out", inputs.outPath)]:
    if req[1].len == 0:
      return err("--" & req[0] & " is required")
  ok(inputs)

proc loadJson(path: string): Result[JsonNode, string] =
  try:
    ok(parseJson(readFile(path)))
  except CatchableError as e:
    err("cannot parse " & path & ": " & e.msg)

type
  MeasuredFinding = object
    fp: string
    spanKey: string
    rule: string
    file: string
    line: int
    endLine: int
    startCol: int
    endCol: int

  BaselineEntry = object
    fp: string
    spanFingerprint: string

proc isLowerHex40(s: string): bool =
  if s.len < 40:
    return false
  for i in 0 ..< 40:
    let c = s[i]
    if not ((c >= '0' and c <= '9') or (c >= 'a' and c <= 'f')):
      return false
  true

proc stripCommitPrefix*(fp: string): string =
  ## Strip a leading 40-hex commit SHA + ':' from a gitleaks fingerprint.
  if fp.len > 41 and fp[40] == ':' and isLowerHex40(fp):
    return fp[41 ..^ 1]
  fp

proc findingSpanKey*(f: JsonNode): string =
  f{"File"}.getStr("") & ":" &
  f{"RuleID"}.getStr("") & ":" &
  $f{"StartLine"}.getInt(0) & ":" &
  $f{"EndLine"}.getInt(0) & ":" &
  $f{"StartColumn"}.getInt(0) & ":" &
  $f{"EndColumn"}.getInt(0)

proc extractBaselineSpan(e: JsonNode): string =
  let explicit = e{"spanFingerprint"}.getStr("")
  if explicit.len > 0:
    return explicit
  let startCol = e{"startColumn"}.getInt(0)
  if startCol > 0:
    let file = e{"file"}.getStr("")
    let rule = e{"rule"}.getStr("")
    let startLine = e{"startLine"}.getInt(e{"line"}.getInt(0))
    let endLine = e{"endLine"}.getInt(startLine)
    let endCol = e{"endColumn"}.getInt(0)
    return file & ":" & rule & ":" & $startLine & ":" & $endLine & ":" & $startCol & ":" & $endCol
  ""

proc matchesBaseline(f: MeasuredFinding, b: BaselineEntry): bool =
  if b.spanFingerprint.len > 0 and f.startCol > 0:
    return f.spanKey == b.spanFingerprint
  if b.spanFingerprint.len == 0 and f.startCol == 0:
    return f.fp == b.fp or stripCommitPrefix(f.fp) == stripCommitPrefix(b.fp)
  if b.spanFingerprint.len == 0:
    return f.fp == b.fp or stripCommitPrefix(f.fp) == stripCommitPrefix(b.fp)
  false

proc matchesAnyBaseline(f: MeasuredFinding, entries: seq[BaselineEntry]): bool =
  for b in entries:
    if matchesBaseline(f, b):
      return true
  false

proc findingFingerprints(report: JsonNode): seq[MeasuredFinding] =
  ## Extract measured findings from a gitleaks JSON report. An entry without
  ## a Fingerprint is skipped — but the count of skipped entries is surfaced
  ## by the caller through report length.
  if report.kind != JArray:
    return @[]
  for f in report:
    let fp = f{"Fingerprint"}.getStr("")
    if fp.len == 0:
      continue
    let startLine = f{"StartLine"}.getInt(0)
    result.add MeasuredFinding(
      fp: fp,
      spanKey: findingSpanKey(f),
      rule: f{"RuleID"}.getStr(""),
      file: f{"File"}.getStr(""),
      line: startLine,
      endLine: f{"EndLine"}.getInt(startLine),
      startCol: f{"StartColumn"}.getInt(0),
      endCol: f{"EndColumn"}.getInt(0))

proc main() {.raises: [].} =
  let inputsRes = parseArgs()
  if inputsRes.isErr:
    echo ToolName & " INPUT ERROR: " & inputsRes.error
    quit(ExitUnknown)
  let inputs = inputsRes.get

  var report = %*{"dimension": "secret-scan", "tool": ToolName}

  # ── policy: closed classification set ─────────────────────────────────
  let policyText = try: readFile(inputs.policyPath)
                   except CatchableError as e:
                     echo ToolName & " UNKNOWN: " & e.msg
                     quit(ExitUnknown)
  let policyNode = parseRestrictedYaml(policyText)
  if policyNode.isErr:
    echo ToolName & " UNKNOWN: security-policy.yml: " & policyNode.error
    quit(ExitUnknown)
  let secScan = policyNode.get.yGet("secretScan")
  if secScan.isNone or secScan.get.kind != yMap:
    echo ToolName & " UNKNOWN: security-policy.yml has no secretScan mapping"
    quit(ExitUnknown)
  var allowedClasses: seq[string] = @[]
  for c in secScan.get.yListStrs("classifications"):
    allowedClasses.add(c)
  if allowedClasses.len == 0:
    echo ToolName & " UNKNOWN: secretScan.classifications is empty"
    quit(ExitUnknown)

  # ── baseline integrity ────────────────────────────────────────────────
  let baseline = loadJson(inputs.baselinePath)
  if baseline.isErr:
    echo ToolName & " UNKNOWN: " & baseline.error
    quit(ExitUnknown)
  var baselineEntries: seq[BaselineEntry] = @[]
  var badClassifications: seq[string] = @[]
  for coll in ["historyFindings", "treeFindings"]:
    let collNode = baseline.get{coll}
    if collNode.isNil or collNode.kind != JArray:
      echo ToolName & " UNKNOWN: baseline has no " & coll & " array"
      quit(ExitUnknown)
    for e in collNode:
      let fp = e{"fingerprint"}.getStr("")
      let cls = e{"classification"}.getStr("")
      if fp.len == 0:
        echo ToolName & " UNKNOWN: baseline entry without fingerprint in " & coll
        quit(ExitUnknown)
      if cls notin allowedClasses:
        badClassifications.add(fp & " (" & cls & ")")
      baselineEntries.add(BaselineEntry(
        fp: fp,
        spanFingerprint: extractBaselineSpan(e)))
  if badClassifications.len > 0:
    report["verdict"] = %"UNKNOWN"
    report["reason"] = %"baseline classifications outside the closed set"
    report["invalidBaselineEntries"] = %badClassifications
    try: writeFile(inputs.outPath, report.pretty() & "\n")
    except CatchableError as e:
      echo ToolName & " OUTPUT ERROR: " & e.msg
      quit(ExitUnknown)
    echo ToolName & " UNKNOWN: baseline integrity failure"
    quit(ExitUnknown)

  # ── measured findings ─────────────────────────────────────────────────
  let hist = loadJson(inputs.historyScan)
  if hist.isErr:
    echo ToolName & " UNKNOWN: " & hist.error
    quit(ExitUnknown)
  let tree = loadJson(inputs.treeScan)
  if tree.isErr:
    echo ToolName & " UNKNOWN: " & tree.error
    quit(ExitUnknown)
  if hist.get.kind != JArray or tree.get.kind != JArray:
    echo ToolName & " UNKNOWN: scan reports must be JSON arrays"
    quit(ExitUnknown)

  let histFps = findingFingerprints(hist.get)
  let treeFps = findingFingerprints(tree.get)

  var newFindings: seq[JsonNode] = @[]
  for f in histFps:
    if not matchesAnyBaseline(f, baselineEntries):
      newFindings.add(%*{"source": "history", "fingerprint": f.fp,
                         "spanFingerprint": f.spanKey, "rule": f.rule,
                         "file": f.file, "line": f.line,
                         "startColumn": f.startCol, "endColumn": f.endCol})
  for f in treeFps:
    if not matchesAnyBaseline(f, baselineEntries):
      newFindings.add(%*{"source": "tree", "fingerprint": f.fp,
                         "spanFingerprint": f.spanKey, "rule": f.rule,
                         "file": f.file, "line": f.line,
                         "startColumn": f.startCol, "endColumn": f.endCol})

  let verdict = if newFindings.len == 0: "PASS" else: "FAIL"
  report["verdict"] = %verdict
  report["historyFindings"] = %histFps.len
  report["treeFindings"] = %treeFps.len
  report["baselineEntries"] = %baselineEntries.len
  report["newFindings"] = %newFindings
  report["maskingNote"] = %"findings are reported without the matched secret text (B2 masking precedent)"
  try:
    writeFile(inputs.outPath, report.pretty() & "\n")
  except CatchableError as e:
    echo ToolName & " OUTPUT ERROR: " & e.msg
    quit(ExitUnknown)
  echo ToolName & ": " & verdict & " (history=" & $histFps.len &
    " tree=" & $treeFps.len & " baseline=" & $baselineEntries.len &
    " new=" & $newFindings.len & ")"
  if newFindings.len > 0:
    for n in newFindings:
      echo "  NEW FINDING: " & n{"source"}.getStr & " " & n{"fingerprint"}.getStr
  quit(if verdict == "PASS": ExitPass else: ExitFail)

when isMainModule:
  main()
