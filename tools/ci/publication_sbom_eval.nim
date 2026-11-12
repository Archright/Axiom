## publication_sbom_eval.nim — sbom-validate adjudication of the
## publication-integrity gate.
##
## Validates a syft (pinned release binary) SPDX-JSON SBOM against the
## semantics DECLARED in compliance/policy/security-policy.yml (sbom):
##
##   PASS   — SPDX JSON produced, schema-validated (SPDX-2.x fields
##            present: spdxVersion, name, non-empty packages or files),
##            non-vacuous, sha256 of the emitted artifact recorded.
##   FAIL   — SPDX fields missing/invalid, or a vacuous SBOM (zero
##            packages AND zero files).
##   UNKNOWN — tool output missing or unparsable — blocking, never a pass
##            (fail-closed).
##
## The sha256 binds the emitted artifact (reproducibility claim: same tree
## + same syft version → identical SBOM modulo creationInfo.created —
## cf. ADR-0037 §5, determinismNote in the policy).
##
## DECLARED limitation (recorded in every report): syft has no Nim
## package-manager cataloger — nimble.lock dependencies appear as file
## entries, not as SPDX package records.
##
## Verdicts (closed set): PASS / FAIL / UNKNOWN. Exit: 0/1/2.
##
## Part of the publication-integrity gate (docs/spec/publication_integrity_gate.md).

import std/[json, options, os, parseopt, strutils]
import core/trusted/layer_declaration
import core/crypto/hash_kernel
import core/results
import tools/ci/publication_yaml

axiomLayer "tools"

const
  ToolName = "publication_sbom_eval"
  ExitPass = 0
  ExitFail = 1
  ExitUnknown = 2

type
  Inputs = object
    reportPath: string
    policyPath: string
    outPath: string

proc parseArgs(): Result[Inputs, string] =
  ## Repo CLI idiom: explicit `p.next()` loop.
  var inputs = Inputs()
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

proc arrLen(node: JsonNode, key: string): int =
  let v = node{key}
  if v != nil and v.kind == JArray:
    return v.len
  0

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
  let sbom = policyNode.get.yGet("sbom")
  if sbom.isNone or sbom.get.kind != yMap:
    echo ToolName & " UNKNOWN: security-policy.yml has no sbom section"
    quit(ExitUnknown)
  let pinned = sbom.get.yStr("pinnedVersion")
  if pinned.len == 0:
    echo ToolName & " UNKNOWN: sbom.pinnedVersion missing"
    quit(ExitUnknown)
  let limitations = sbom.get.yListStrs("declaredCoverageLimitations")

  # ── SPDX validation ───────────────────────────────────────────────────
  let report = loadJson(inputs.reportPath)
  if report.isErr:
    echo ToolName & " UNKNOWN: " & report.error
    quit(ExitUnknown)
  let doc = report.get
  let spdxVersion = doc{"spdxVersion"}.getStr("")
  let docName = doc{"name"}.getStr("")
  let packages = arrLen(doc, "packages")
  let files = arrLen(doc, "files")
  var verdict = "PASS"
  var problems: seq[string] = @[]
  if not spdxVersion.startsWith("SPDX-2"):
    problems.add("spdxVersion missing or not SPDX-2.x: '" & spdxVersion & "'")
  if docName.len == 0:
    problems.add("name (document name) missing")
  if packages == 0 and files == 0:
    problems.add("vacuous SBOM: zero packages and zero files")
  if problems.len > 0:
    verdict = "FAIL"

  let artifactText = readFileOrErr(inputs.reportPath)
  var artifactSha = ""
  if artifactText.isOk:
    artifactSha = sha256Hex(artifactText.get)

  let outReport = %*{
    "dimension": "sbom",
    "verdict": verdict,
    "tool": ToolName,
    "scanner": "syft " & pinned,
    "spdxVersion": spdxVersion,
    "documentName": docName,
    "packages": packages,
    "files": files,
    "artifactSha256": artifactSha,
    "problems": problems,
    "declaredCoverageLimitations": limitations,
  }
  try:
    writeFile(inputs.outPath, outReport.pretty() & "\n")
  except CatchableError as e:
    echo ToolName & " OUTPUT ERROR: " & e.msg
    quit(ExitUnknown)
  echo ToolName & ": " & verdict & " (spdx=" & spdxVersion &
    " packages=" & $packages & " files=" & $files & ")"
  for pb in problems:
    echo "  PROBLEM: " & pb
  quit(if verdict == "PASS": ExitPass else: ExitFail)

when isMainModule:
  main()
