## publication_dependency_eval.nim — dependency-scan adjudication of the
## publication-integrity gate.
##
## Adjudicates an osv-scanner (pinned release binary) run against the
## exit-code + report semantics DECLARED in compliance/policy/security-policy.yml
## (dependencyScan.exitCodeAdjudication, measured on osv-scanner v2.7.1):
##
##   exit 0   — scan completed: parse the report; any matched vulnerability
##              is a FAIL; zero findings is a PASS.
##   exit 100 — vulnerabilities found: FAIL (report parsed for the listing
##              when available).
##   exit 128 — "No package sources found": a COMPLETED scan over a repo
##              whose lockfiles are all outside OSV-indexed ecosystems —
##              PASS with the DECLARED coverage limitations recorded
##              (declaredCoverageLimitations, honesty not weakening).
##   other    — UNKNOWN (blocking, never a pass — fail-closed).
##   exit 0/100 with a missing or unparsable report — UNKNOWN.
##
## Verdicts (closed set): PASS / FAIL / UNKNOWN. Exit: 0/1/2.
##
## Part of the publication-integrity gate (docs/spec/publication_integrity_gate.md).

import std/[json, options, os, parseopt, strutils]
import core/trusted/layer_declaration
import core/results
import tools/ci/publication_yaml

axiomLayer "tools"

const
  ToolName = "publication_dependency_eval"
  ExitPass = 0
  ExitFail = 1
  ExitUnknown = 2

type
  Inputs = object
    exitCode: int
    reportPath: string
    policyPath: string
    outPath: string

proc parseArgs(): Result[Inputs, string] =
  ## Repo CLI idiom: explicit `p.next()` loop.
  var inputs = Inputs(exitCode: -1)
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
      of "exit-code":
        try:
          inputs.exitCode = parseInt(val)
        except CatchableError:
          return err("--exit-code is not an integer: " & val)
      of "report": inputs.reportPath = val
      of "policy": inputs.policyPath = val
      of "out": inputs.outPath = val
      else: return err("unknown option: --" & key)
    of cmdArgument:
      return err("unexpected argument '" & p.key & "'")
  for req in [("report", inputs.reportPath), ("policy", inputs.policyPath),
              ("out", inputs.outPath)]:
    if req[1].len == 0:
      return err("--" & req[0] & " is required")
  if inputs.exitCode < 0:
    return err("--exit-code is required (the osv-scanner exit status)")
  ok(inputs)

proc readFileOrErr(path: string): Result[string, string] =
  try:
    ok(readFile(path))
  except CatchableError as e:
    err("cannot read " & path & ": " & e.msg)

proc loadJson(path: string): Result[JsonNode, string] =
  try:
    ok(parseJson(readFile(path)))
  except CatchableError as e:
    err("cannot parse " & path & ": " & e.msg)

proc osvVulnerabilities(report: JsonNode): seq[JsonNode] =
  ## Flatten osv-scanner v2 JSON: results[].packages[].vulnerabilities[].
  result = @[]
  let results = report{"results"}
  if results == nil or results.kind != JArray:
    return
  for r in results:
    let pkgs = r{"packages"}
    if pkgs == nil or pkgs.kind != JArray:
      continue
    for pkg in pkgs:
      let vulns = pkg{"vulnerabilities"}
      if vulns == nil or vulns.kind != JArray:
        continue
      for v in vulns:
        result.add(%*{
          "id": v{"id"}.getStr(""),
          "package": pkg{"package"}{"name"}.getStr(""),
          "ecosystem": pkg{"package"}{"ecosystem"}.getStr("")})

proc main() {.raises: [].} =
  let inputsRes = parseArgs()
  if inputsRes.isErr:
    echo ToolName & " INPUT ERROR: " & inputsRes.error
    quit(ExitUnknown)
  let inputs = inputsRes.get

  # ── policy: pins + declared limitations must parse ───────────────────
  let policyText = readFileOrErr(inputs.policyPath)
  if policyText.isErr:
    echo ToolName & " UNKNOWN: " & policyText.error; quit(ExitUnknown)
  let policyNode = parseRestrictedYaml(policyText.get)
  if policyNode.isErr:
    echo ToolName & " UNKNOWN: security-policy.yml: " & policyNode.error
    quit(ExitUnknown)
  let depScan = policyNode.get.yGet("dependencyScan")
  if depScan.isNone or depScan.get.kind != yMap:
    echo ToolName & " UNKNOWN: security-policy.yml has no dependencyScan section"
    quit(ExitUnknown)
  let pinned = depScan.get.yStr("pinnedVersion")
  if pinned.len == 0:
    echo ToolName & " UNKNOWN: dependencyScan.pinnedVersion missing"
    quit(ExitUnknown)
  let limitations = depScan.get.yListStrs("declaredCoverageLimitations")

  # ── adjudication by DECLARED exit-code semantics ──────────────────────
  var verdict: string
  var vulns: seq[JsonNode] = @[]
  var cause = ""
  case inputs.exitCode
  of 0, 100:
    let report = loadJson(inputs.reportPath)
    if report.isErr:
      verdict = "UNKNOWN"
      cause = "exit " & $inputs.exitCode & " but report unusable: " & report.error
    else:
      vulns = osvVulnerabilities(report.get)
      if inputs.exitCode == 100 or vulns.len > 0:
        verdict = "FAIL"
        cause = "known vulnerabilities matched in an OSV-indexed ecosystem"
      else:
        verdict = "PASS"
  of 128:
    # Completed scan; every lockfile is outside OSV ecosystems (measured
    # for this repository: nimble.lock + lake-manifest.json only).
    verdict = "PASS"
    cause = "no package sources found (exit 128) — all lockfiles outside OSV ecosystems; declared limitations recorded"
  else:
    verdict = "UNKNOWN"
    cause = "unmapped osv-scanner exit code: " & $inputs.exitCode

  let report = %*{
    "dimension": "dependency-scan",
    "verdict": verdict,
    "tool": ToolName,
    "scanner": "osv-scanner " & pinned,
    "exitCode": inputs.exitCode,
    "vulnerabilities": vulns,
    "cause": cause,
    "declaredCoverageLimitations": limitations,
  }
  try:
    writeFile(inputs.outPath, report.pretty() & "\n")
  except CatchableError as e:
    echo ToolName & " OUTPUT ERROR: " & e.msg
    quit(ExitUnknown)
  echo ToolName & ": " & verdict & " (exitCode=" & $inputs.exitCode &
    " vulnerabilities=" & $vulns.len & ")"
  for v in vulns:
    echo "  VULNERABILITY: " & v{"id"}.getStr & " " &
      v{"package"}.getStr & " (" & v{"ecosystem"}.getStr & ")"
  if cause.len > 0 and verdict != "PASS":
    echo "  CAUSE: " & cause
  quit(case verdict
       of "PASS": ExitPass
       of "FAIL": ExitFail
       else: ExitUnknown)

when isMainModule:
  main()
