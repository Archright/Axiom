## publication_attestor.nim — out-of-tree SHA-bound publication attestation
## issuer and verifier.
##
## Eliminates the in-tree self-referential hash cycle where
## compliance/reports/publication-readiness.json inside tree(S) attempted to
## bind targetCommitSha = S and targetTreeSha = tree(S).
##
## Modes:
##   --mode issue
##     --commit <40-hex-sha>
##     --tree <40-hex-sha>
##     --gate-report <publication-integrity-report.json>
##     [--checks-json <check-runs.json>]
##     [--require-check <name>=<conclusion> ...]
##     [--runner-evidence <runner-execution-evidence.json>]
##     --out <attestation.json>
##
##   --mode verify
##     --attestation <attestation.json>
##     --expected-commit <40-hex-sha>
##     --expected-tree <40-hex-sha>
##     [--runner-evidence <runner-execution-evidence.json>]
##
## Exit codes:
##   0 = ELIGIBLE (verified PASS)
##   1 = BLOCKED (policy/check/SHA mismatch failure)
##   2 = UNKNOWN (input error or unparsable artifact)

import std/[json, os, parseopt, strutils, tables]
import core/trusted/layer_declaration
import core/crypto/hash_kernel
import core/results

axiomLayer "tools"

const
  ToolName = "publication_attestor"
  ExitEligible = 0
  ExitBlocked = 1
  ExitUnknown = 2
  StorageLocation = "out-of-tree (refs/heads/axiom/attestations)"
  RequiredDimensions = [
    "secret-scan",
    "license-scan",
    "dependency-scan",
    "provenance",
    "sbom",
  ]
  RequiredChecks = [
    "admission-check",
    "axiom-operational-slice",
    "bsec-integrity",
    "debt-registry-gate",
    "generation-acceptance",
    "publication-integrity",
  ]
  AllowedHostedLabels = [
    "ubuntu-24.04",
    "ubuntu-slim",
    "ubuntu-24.04-arm",
    "ubuntu-latest",
  ]

type
  Mode = enum
    mNone
    mIssue
    mVerify

  Inputs = object
    mode: Mode
    commitSha: string
    treeSha: string
    gateReportPath: string
    checksJsonPath: string
    requireChecks: seq[tuple[name, conclusion: string]]
    runnerEvidencePath: string
    outPath: string
    attestationPath: string
    expectedCommit: string
    expectedTree: string

proc isLowerHex40(s: string): bool =
  if s.len != 40:
    return false
  for c in s:
    if not ((c >= '0' and c <= '9') or (c >= 'a' and c <= 'f')):
      return false
  true

proc parseArgs(): Result[Inputs, string] =
  var inputs = Inputs(mode: mNone, requireChecks: @[])
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
      of "mode":
        case val
        of "issue": inputs.mode = mIssue
        of "verify": inputs.mode = mVerify
        else: return err("invalid --mode '" & val & "' (expected issue or verify)")
      of "commit": inputs.commitSha = val
      of "tree": inputs.treeSha = val
      of "gate-report": inputs.gateReportPath = val
      of "checks-json": inputs.checksJsonPath = val
      of "require-check":
        let sp = val.split('=', 1)
        if sp.len != 2 or sp[0].len == 0 or sp[1].len == 0:
          return err("--require-check expects <name>=<conclusion>")
        inputs.requireChecks.add((sp[0], sp[1]))
      of "runner-evidence": inputs.runnerEvidencePath = val
      of "out": inputs.outPath = val
      of "attestation": inputs.attestationPath = val
      of "expected-commit": inputs.expectedCommit = val
      of "expected-tree": inputs.expectedTree = val
      else:
        return err("unknown option: --" & key)
    of cmdArgument:
      return err("unexpected argument '" & p.key & "'")

  case inputs.mode
  of mNone:
    return err("--mode <issue|verify> is required")
  of mIssue:
    if inputs.commitSha.len == 0 or inputs.treeSha.len == 0 or
       inputs.gateReportPath.len == 0 or inputs.outPath.len == 0:
      return err("--mode issue requires --commit, --tree, --gate-report, and --out")
    if not isLowerHex40(inputs.commitSha):
      return err("--commit must be a 40-char lowercase hex SHA")
    if not isLowerHex40(inputs.treeSha):
      return err("--tree must be a 40-char lowercase hex SHA")
  of mVerify:
    if inputs.attestationPath.len == 0 or
       inputs.expectedCommit.len == 0 or
       inputs.expectedTree.len == 0:
      return err("--mode verify requires --attestation, --expected-commit, and --expected-tree")
    if not isLowerHex40(inputs.expectedCommit):
      return err("--expected-commit must be a 40-char lowercase hex SHA")
    if not isLowerHex40(inputs.expectedTree):
      return err("--expected-tree must be a 40-char lowercase hex SHA")
  ok(inputs)

proc loadJsonOrErr(path: string): Result[JsonNode, string] =
  try:
    ok(parseJson(readFile(path)))
  except CatchableError as e:
    err("cannot parse " & path & ": " & e.msg)

proc loadRawAndJsonOrErr(path: string): Result[tuple[raw: string, node: JsonNode], string] =
  try:
    let raw = readFile(path)
    let node = parseJson(raw)
    ok((raw, node))
  except CatchableError as e:
    err("cannot parse " & path & ": " & e.msg)

proc validateRunnerEvidence(evidence: JsonNode, expectedCommitSha: string): seq[string] =
  result = @[]
  let evCommit = evidence{"targetCommitSha"}.getStr("")
  if evCommit != expectedCommitSha:
    result.add("runner evidence targetCommitSha mismatch: expected " &
      expectedCommitSha & ", got " & (if evCommit.len > 0: evCommit else: "MISSING"))

  let runsNode = evidence{"runs"}
  if runsNode.isNil or runsNode.kind != JArray or runsNode.len == 0:
    result.add("runner evidence runs must be a non-empty array")
    return

  var runIdx = -1
  for run in runsNode:
    inc runIdx
    if run.kind != JObject:
      result.add("runner evidence run[" & $runIdx & "] is not a JSON object")
      continue
    let runLabel = block:
      let n = run{"name"}.getStr(run{"workflowName"}.getStr(""))
      if n.len > 0: n
      elif not run{"id"}.isNil and run{"id"}.kind == JString and run{"id"}.getStr("").len > 0:
        run{"id"}.getStr("")
      elif not run{"id"}.isNil and run{"id"}.kind == JInt:
        $run{"id"}.getInt(0)
      else:
        "run#" & $runIdx

    let headSha = run{"headSha"}.getStr("")
    if headSha != expectedCommitSha:
      result.add("run " & runLabel & " headSha mismatch: expected " &
        expectedCommitSha & ", got " & (if headSha.len > 0: headSha else: "MISSING"))

    let runConcl = run{"conclusion"}.getStr("")
    if runConcl != "success":
      result.add("run " & runLabel & " conclusion=" &
        (if runConcl.len > 0: runConcl else: "MISSING"))

    let jobsNode = run{"jobs"}
    if jobsNode.isNil or jobsNode.kind != JArray or jobsNode.len == 0:
      result.add("run " & runLabel & " jobs must be a non-empty array")
      continue

    var jobIdx = -1
    for job in jobsNode:
      inc jobIdx
      if job.kind != JObject:
        result.add("job " & runLabel & "/job#" & $jobIdx & " is not a JSON object")
        continue
      let jobName = block:
        let jn = job{"name"}.getStr("")
        if jn.len > 0: jn
        elif not job{"id"}.isNil and job{"id"}.kind == JInt: $job{"id"}.getInt(0)
        else: "job#" & $jobIdx
      let jobRef = runLabel & "/" & jobName
      let jobConcl = job{"conclusion"}.getStr("")
      if jobConcl == "skipped":
        continue
      if jobConcl != "success":
        result.add("job " & jobRef & " conclusion=" &
          (if jobConcl.len > 0: jobConcl else: "MISSING"))

      let rgIdNode = job{"runner_group_id"}
      if rgIdNode.isNil or rgIdNode.kind != JInt or rgIdNode.getInt(-1) != 0:
        let rgIdStr = if rgIdNode.isNil: "MISSING" else: $rgIdNode
        result.add("job " & jobRef & " non-GitHub-hosted runner (runner_group_id=" & rgIdStr & ")")

      let rgName = job{"runner_group_name"}.getStr("")
      if rgName != "GitHub Actions":
        result.add("job " & jobRef & " non-GitHub-hosted runner (runner_group_name=" &
          (if rgName.len > 0: rgName else: "MISSING") & ")")

      let rIdNode = job{"runner_id"}
      if rIdNode.isNil or rIdNode.kind != JInt or rIdNode.getInt(0) <= 0:
        let rIdStr = if rIdNode.isNil: "MISSING" else: $rIdNode
        result.add("job " & jobRef & " invalid runner_id (runner_id=" & rIdStr & ")")

      let labelsNode = job{"labels"}
      if labelsNode.isNil or labelsNode.kind != JArray or labelsNode.len == 0:
        result.add("job " & jobRef & " labels must be a non-empty array")
      else:
        for lblNode in labelsNode:
          if lblNode.kind != JString:
            result.add("job " & jobRef & " non-string runner label: " & $lblNode)
            continue
          let lbl = lblNode.getStr("")
          let lblLower = lbl.toLowerAscii()
          if lblLower.contains("self-hosted") or lblLower.contains("ubicloud") or
             lblLower.contains("axiom-control") or lbl notin AllowedHostedLabels:
            result.add("job " & jobRef & " non-GitHub-hosted runner label (label=" & lbl & ")")

proc computeCapsuleDigest(
  schemaVersion: int,
  storageLocation: string,
  targetCommitSha: string,
  targetTreeSha: string,
  verdict: string,
  dimensions: JsonNode,
  requiredChecks: JsonNode,
  blockers: JsonNode,
  unresolvedUnknowns: JsonNode,
  unresolvedUnknownCount: int,
  runnerIdentityVerified: bool = false,
  runnerEvidenceDigest: string = ""
): string =
  var canonical = %*{
    "schemaVersion": schemaVersion,
    "storageLocation": storageLocation,
    "targetCommitSha": targetCommitSha,
    "targetTreeSha": targetTreeSha,
    "verdict": verdict,
    "dimensions": dimensions,
    "requiredChecks": requiredChecks,
    "blockers": blockers,
    "unresolvedUnknowns": unresolvedUnknowns,
    "unresolvedUnknownCount": unresolvedUnknownCount,
  }
  if runnerEvidenceDigest.len > 0:
    canonical["runnerIdentityVerified"] = %runnerIdentityVerified
    canonical["runnerEvidenceDigestSha256"] = %runnerEvidenceDigest
  sha256Hex($canonical)

proc extractDimensions(gateNode: JsonNode): Table[string, string] =
  result = initTable[string, string]()
  let dims = gateNode{"dimensions"}
  if dims.isNil:
    return
  if dims.kind == JArray:
    for item in dims:
      if item.kind == JObject:
        let dName = item{"dimension"}.getStr("")
        let dVerdict = item{"verdict"}.getStr("")
        if dName.len > 0:
          result[dName] = dVerdict
  elif dims.kind == JObject:
    for k, v in dims:
      if v.kind == JString:
        result[k] = v.getStr("")
      elif v.kind == JObject:
        result[k] = v{"verdict"}.getStr("")

proc extractChecksFromJson(node: JsonNode, tab: var Table[string, string]) =
  if node.isNil:
    return
  if node.kind == JArray:
    for item in node:
      if item.kind == JObject:
        let name = item{"name"}.getStr(item{"context"}.getStr(""))
        let concl = item{"conclusion"}.getStr(item{"state"}.getStr(""))
        if name.len > 0:
          tab[name] = concl
  elif node.kind == JObject:
    let checkRuns = node{"check_runs"}
    let conclusions = node{"conclusions"}
    if not checkRuns.isNil and checkRuns.kind == JArray:
      extractChecksFromJson(checkRuns, tab)
    elif not conclusions.isNil and conclusions.kind == JObject:
      extractChecksFromJson(conclusions, tab)
    else:
      for k, v in node:
        if v.kind == JString:
          tab[k] = v.getStr("")
        elif v.kind == JObject:
          tab[k] = v{"conclusion"}.getStr(v{"verdict"}.getStr(""))

proc runIssue(inputs: Inputs): int =
  let gateRes = loadJsonOrErr(inputs.gateReportPath)
  if gateRes.isErr:
    echo ToolName & " UNKNOWN: " & gateRes.error
    return ExitUnknown
  let gate = gateRes.get
  if gate.kind != JObject:
    echo ToolName & " UNKNOWN: gate report is not a JSON object"
    return ExitUnknown

  var checkMap = initTable[string, string]()
  if inputs.checksJsonPath.len > 0:
    let checksRes = loadJsonOrErr(inputs.checksJsonPath)
    if checksRes.isErr:
      echo ToolName & " UNKNOWN: " & checksRes.error
      return ExitUnknown
    extractChecksFromJson(checksRes.get, checkMap)
  for rc in inputs.requireChecks:
    checkMap[rc.name] = rc.conclusion

  var
    blockers: seq[string] = @[]
    unknowns: seq[string] = @[]
    runnerEvidenceDigest = ""
    runnerIdentityVerified = false

  if inputs.runnerEvidencePath.len > 0:
    let evRes = loadRawAndJsonOrErr(inputs.runnerEvidencePath)
    if evRes.isErr:
      echo ToolName & " UNKNOWN: " & evRes.error
      return ExitUnknown
    let (rawEvidence, evNode) = evRes.get
    if evNode.kind != JObject:
      echo ToolName & " UNKNOWN: runner evidence is not a JSON object"
      return ExitUnknown
    let runnerBlockers = validateRunnerEvidence(evNode, inputs.commitSha)
    for rb in runnerBlockers:
      blockers.add(rb)
    runnerEvidenceDigest = sha256Hex(rawEvidence)
    runnerIdentityVerified = (runnerBlockers.len == 0)

  let gateUnknownsNode = gate{"unresolvedUnknowns"}
  if not gateUnknownsNode.isNil and gateUnknownsNode.kind == JArray:
    for u in gateUnknownsNode:
      let us = u.getStr("")
      if us.len > 0:
        unknowns.add(us)
  let gateUnknownCount = gate{"unresolvedUnknownCount"}.getInt(unknowns.len)
  if gateUnknownCount != 0 or unknowns.len > 0:
    blockers.add("gate report has unresolvedUnknownCount=" & $gateUnknownCount)

  let gateVerdict = gate{"verdict"}.getStr("")
  if gateVerdict != "PASS":
    blockers.add("gate report verdict=" & (if gateVerdict.len > 0: gateVerdict else: "MISSING"))

  let boundCommit = gate{"binding", "commitSha"}.getStr("")
  let boundTree = gate{"binding", "treeSha"}.getStr("")
  if boundCommit != inputs.commitSha:
    blockers.add("gate report binding.commitSha mismatch: expected " &
      inputs.commitSha & ", got " & boundCommit)
  if boundTree != inputs.treeSha:
    blockers.add("gate report binding.treeSha mismatch: expected " &
      inputs.treeSha & ", got " & boundTree)

  let dimTable = extractDimensions(gate)
  var dimsJson = newJObject()
  for d in RequiredDimensions:
    let dv = dimTable.getOrDefault(d, "")
    dimsJson[d] = %(if dv.len > 0: dv else: "MISSING")
    if dv != "PASS":
      blockers.add("dimension " & d & " verdict=" & (if dv.len > 0: dv else: "MISSING"))

  var checksJson = newJObject()
  for c in RequiredChecks:
    let cv = checkMap.getOrDefault(c, "")
    let norm = cv.toUpperAscii()
    checksJson[c] = %(if norm.len > 0: norm else: "MISSING")
    if norm != "SUCCESS":
      blockers.add("required check " & c & " conclusion=" & (if cv.len > 0: cv else: "MISSING"))

  let
    verdict = if blockers.len == 0 and unknowns.len == 0: "ELIGIBLE" else: "BLOCKED"
    blockersJson = %blockers
    unknownsJson = %unknowns
    unknownCount = max(gateUnknownCount, unknowns.len)
    digest = computeCapsuleDigest(
      schemaVersion = 2,
      storageLocation = StorageLocation,
      targetCommitSha = inputs.commitSha,
      targetTreeSha = inputs.treeSha,
      verdict = verdict,
      dimensions = dimsJson,
      requiredChecks = checksJson,
      blockers = blockersJson,
      unresolvedUnknowns = unknownsJson,
      unresolvedUnknownCount = unknownCount,
      runnerIdentityVerified = runnerIdentityVerified,
      runnerEvidenceDigest = runnerEvidenceDigest)

  var capsule = %*{
    "schemaVersion": 2,
    "storageLocation": StorageLocation,
    "targetCommitSha": inputs.commitSha,
    "targetTreeSha": inputs.treeSha,
    "verdict": verdict,
    "publicationEligible": verdict == "ELIGIBLE",
    "capsuleDigestSha256": digest,
    "dimensions": dimsJson,
    "requiredChecks": checksJson,
    "blockers": blockersJson,
    "unresolvedUnknowns": unknownsJson,
    "unresolvedUnknownCount": unknownCount,
  }
  if runnerEvidenceDigest.len > 0:
    capsule["runnerIdentityVerified"] = %runnerIdentityVerified
    capsule["runnerEvidenceDigestSha256"] = %runnerEvidenceDigest

  try:
    if inputs.outPath.parentDir().len > 0:
      createDir(inputs.outPath.parentDir())
    writeFile(inputs.outPath, capsule.pretty() & "\n")
  except CatchableError as e:
    echo ToolName & " OUTPUT ERROR: " & e.msg
    return ExitUnknown

  echo ToolName & " issue: " & verdict & " (commit=" & inputs.commitSha &
    " tree=" & inputs.treeSha & ")"
  for b in blockers:
    echo "  BLOCKER: " & b
  if verdict == "ELIGIBLE": ExitEligible else: ExitBlocked

proc runVerify(inputs: Inputs): int =
  let attRes = loadJsonOrErr(inputs.attestationPath)
  if attRes.isErr:
    echo ToolName & " UNKNOWN: " & attRes.error
    return ExitUnknown
  let att = attRes.get
  if att.kind != JObject:
    echo ToolName & " UNKNOWN: attestation is not a JSON object"
    return ExitUnknown

  let
    schemaVersion = att{"schemaVersion"}.getInt(0)
    storageLocation = att{"storageLocation"}.getStr("")
    targetCommit = att{"targetCommitSha"}.getStr("")
    targetTree = att{"targetTreeSha"}.getStr("")
    verdict = att{"verdict"}.getStr("")
    recordedDigest = att{"capsuleDigestSha256"}.getStr("")
    dimsJson = att{"dimensions"}
    checksJson = att{"requiredChecks"}
    blockersJson = att{"blockers"}
    unknownsJson = att{"unresolvedUnknowns"}
    unknownCount = att{"unresolvedUnknownCount"}.getInt(-1)
    recordedRunnerDigest = att{"runnerEvidenceDigestSha256"}.getStr("")
    recordedRunnerVerified = att{"runnerIdentityVerified"}.getBool(false)

  if targetCommit != inputs.expectedCommit or targetTree != inputs.expectedTree:
    echo ToolName & " verify: STALE_ATTESTATION_SHA_MISMATCH → BLOCKED (expected commit=" &
      inputs.expectedCommit & " tree=" & inputs.expectedTree &
      ", attested commit=" & targetCommit & " tree=" & targetTree & ")"
    return ExitBlocked

  if schemaVersion != 2 or dimsJson.isNil or checksJson.isNil or
     blockersJson.isNil or unknownsJson.isNil or unknownCount < 0:
    echo ToolName & " verify: malformed attestation schema → BLOCKED"
    return ExitBlocked

  let recomputed = computeCapsuleDigest(
    schemaVersion = schemaVersion,
    storageLocation = storageLocation,
    targetCommitSha = targetCommit,
    targetTreeSha = targetTree,
    verdict = verdict,
    dimensions = dimsJson,
    requiredChecks = checksJson,
    blockers = blockersJson,
    unresolvedUnknowns = unknownsJson,
    unresolvedUnknownCount = unknownCount,
    runnerIdentityVerified = recordedRunnerVerified,
    runnerEvidenceDigest = recordedRunnerDigest)

  if recordedDigest.len == 0 or recordedDigest != recomputed:
    echo ToolName & " verify: CAPSULE_DIGEST_MISMATCH → BLOCKED"
    return ExitBlocked

  if recordedRunnerDigest.len > 0 or inputs.runnerEvidencePath.len > 0:
    if not recordedRunnerVerified or recordedRunnerDigest.len == 0:
      echo ToolName & " verify: runnerIdentityVerified is not true → BLOCKED"
      return ExitBlocked
    if inputs.runnerEvidencePath.len > 0:
      let evRes = loadRawAndJsonOrErr(inputs.runnerEvidencePath)
      if evRes.isErr:
        echo ToolName & " UNKNOWN: " & evRes.error
        return ExitUnknown
      let (rawEvidence, evNode) = evRes.get
      if evNode.kind != JObject:
        echo ToolName & " UNKNOWN: runner evidence is not a JSON object"
        return ExitUnknown
      let actualEvidenceDigest = sha256Hex(rawEvidence)
      if actualEvidenceDigest != recordedRunnerDigest:
        echo ToolName & " verify: RUNNER_EVIDENCE_DIGEST_MISMATCH → BLOCKED"
        return ExitBlocked
      let runnerBlockers = validateRunnerEvidence(evNode, inputs.expectedCommit)
      if runnerBlockers.len > 0:
        for b in runnerBlockers:
          echo "  BLOCKER: " & b
        echo ToolName & " verify: runner execution evidence failed policy validation → BLOCKED"
        return ExitBlocked

  if verdict != "ELIGIBLE" or unknownCount != 0 or blockersJson.len > 0 or unknownsJson.len > 0:
    echo ToolName & " verify: attestation verdict is not ELIGIBLE → BLOCKED"
    return ExitBlocked

  for d in RequiredDimensions:
    if dimsJson{d}.getStr("") != "PASS":
      echo ToolName & " verify: dimension " & d & " not PASS → BLOCKED"
      return ExitBlocked

  for c in RequiredChecks:
    if checksJson{c}.getStr("").toUpperAscii() != "SUCCESS":
      echo ToolName & " verify: required check " & c & " not SUCCESS → BLOCKED"
      return ExitBlocked

  echo ToolName & " verify: ELIGIBLE (commit=" & targetCommit & " tree=" & targetTree & ")"
  ExitEligible

proc main() {.raises: [].} =
  let inputsRes = parseArgs()
  if inputsRes.isErr:
    echo ToolName & " INPUT ERROR: " & inputsRes.error
    quit(ExitUnknown)
  let code =
    case inputsRes.get.mode
    of mIssue: runIssue(inputsRes.get)
    of mVerify: runVerify(inputsRes.get)
    of mNone: ExitUnknown
  quit(code)

when isMainModule:
  main()
