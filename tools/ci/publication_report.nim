## publication_report.nim — the single verdict aggregation of the
## publication-integrity gate.
##
## Runs as the `publication-integrity` job (the check-run context that the
## ruleset binds). It consumes:
##   - the sub-job RESULTS (GitHub `needs.<job>.result`, passed as
##     `--job <name>=<result>` — success / failure / cancelled / skipped);
##   - each sub-job's dimension report (path + expected dimension name,
##     `--report <dimension>=<path.json>`);
##   - the binding facts: commit SHA, tree SHA, policy file sha256 revisions.
##
## Adjudication (fail-closed):
##   - every sub-job result must be EXACTLY `success` (a skipped or
##     cancelled sub-job is a missing verdict → UNKNOWN → BLOCK — a skipped
##     required check reports success at the platform level, so this job
##     must never be skipped itself and must treat every non-success
##     sub-result as a blocker);
##   - every dimension report must exist, parse, and carry verdict == PASS;
##   - any unreadable/unparsable report or missing input → UNKNOWN → BLOCK.
##
## The report binds: commit SHA, tree SHA (`git rev-parse HEAD^{tree}`),
## sha256 of each policy file (policy revision), the scanner versions, and
## per-dimension verdicts. `publicationReadiness` is PASS only when every
## dimension is PASS with zero unresolved UNKNOWNs.
##
## Exit: 0 = PASS, 1 = FAIL, 2 = UNKNOWN.
##
## Part of the publication-integrity gate (docs/spec/publication_integrity_gate.md).

import std/[json, os, parseopt, strutils]
import core/trusted/layer_declaration
import core/crypto/hash_kernel
import core/results

axiomLayer "tools"

const
  ToolName = "publication_report"
  ExitPass = 0
  ExitFail = 1
  ExitUnknown = 2
  Dimensions = ["secret-scan", "license-scan", "dependency-scan",
                "provenance", "sbom"]

type
  Inputs = object
    outPath: string
    headSha: string
    treeSha: string
    jobs: seq[tuple[name, result: string]]
    reports: seq[tuple[dimension, path: string]]
    policyFiles: seq[string]

proc parseArgs(): Result[Inputs, string] =
  ## Repo CLI idiom: explicit `p.next()` loop; space-separated option
  ## values consume the next cmdArgument token.
  var inputs = Inputs(jobs: @[], reports: @[], policyFiles: @[])
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
      of "out": inputs.outPath = val
      of "head-sha": inputs.headSha = val
      of "tree-sha": inputs.treeSha = val
      of "job":
        let sp = val.split('=', 1)
        if sp.len != 2:
          return err("--job expects <name>=<result>")
        inputs.jobs.add((sp[0], sp[1]))
      of "report":
        let sp = val.split('=', 1)
        if sp.len != 2:
          return err("--report expects <dimension>=<path>")
        inputs.reports.add((sp[0], sp[1]))
      of "policy-file": inputs.policyFiles.add(val)
      else: return err("unknown option: --" & key)
    of cmdArgument:
      return err("unexpected argument '" & p.key & "'")
  if inputs.outPath.len == 0:
    return err("--out is required")
  if inputs.headSha.len == 0 or inputs.treeSha.len == 0:
    return err("--head-sha and --tree-sha are required")
  ok(inputs)

proc fileSha256(path: string): string =
  try:
    sha256Hex(readFile(path))
  except CatchableError:
    ""

proc main() {.raises: [].} =
  let inputsRes = parseArgs()
  if inputsRes.isErr:
    echo ToolName & " INPUT ERROR: " & inputsRes.error
    quit(ExitUnknown)
  let inputs = inputsRes.get

  var
    blockers: seq[string] = @[]
    unknowns: seq[string] = @[]
    dimensionVerdicts: seq[JsonNode] = @[]

  # every sub-job result must be exactly success
  for d in Dimensions:
    var found = false
    for j in inputs.jobs:
      if j.name == d:
        found = true
        if j.result != "success":
          if j.result in ["cancelled", "skipped"]:
            unknowns.add("job " & d & " result=" & j.result &
              " (a skipped/cancelled sub-job is a MISSING verdict, never a pass)")
          else:
            blockers.add("job " & d & " result=" & j.result)
    if not found:
      unknowns.add("job " & d & " result NOT REPORTED")

  # every dimension report must exist, parse, and be PASS
  for d in Dimensions:
    var reportPath = ""
    for r in inputs.reports:
      if r.dimension == d:
        reportPath = r.path
    if reportPath.len == 0:
      unknowns.add("dimension " & d & " report path not supplied")
      continue
    var node: JsonNode = nil
    try:
      node = parseJson(readFile(reportPath))
    except CatchableError as e:
      unknowns.add("dimension " & d & " report unreadable: " & e.msg)
      continue
    let v = node{"verdict"}.getStr("")
    if v.len == 0:
      unknowns.add("dimension " & d & " report has no verdict field")
    elif v == "PASS":
      dimensionVerdicts.add(%*{"dimension": d, "verdict": v})
    elif v == "UNKNOWN":
      unknowns.add("dimension " & d & " verdict=UNKNOWN")
    else:
      blockers.add("dimension " & d & " verdict=" & v)

  # policy revisions
  var policyRevisions: seq[JsonNode] = @[]
  for pf in inputs.policyFiles:
    let h = fileSha256(pf)
    if h.len == 0:
      unknowns.add("policy file unreadable: " & pf)
    else:
      policyRevisions.add(%*{"file": pf, "sha256": h})

  let verdict =
    if unknowns.len > 0: "UNKNOWN"
    elif blockers.len > 0: "FAIL"
    else: "PASS"
  let report = %*{
    "schemaVersion": 1,
    "gate": "publication-integrity",
    "verdict": verdict,
    "verdictSemantics": {
      "PASS": "every dimension PASS, zero unresolved UNKNOWN",
      "FAIL": "an observed blocker",
      "UNKNOWN": "a verdict could not be established — BLOCKING (fail-closed), never a pass"
    },
    "binding": {
      "commitSha": inputs.headSha,
      "treeSha": inputs.treeSha,
      "policyRevisions": policyRevisions,
    },
    "dimensions": dimensionVerdicts,
    "blockers": blockers,
    "unresolvedUnknowns": unknowns,
    "unresolvedUnknownCount": unknowns.len,
  }
  try:
    writeFile(inputs.outPath, report.pretty() & "\n")
  except CatchableError as e:
    echo ToolName & " OUTPUT ERROR: " & e.msg
    quit(ExitUnknown)
  echo ToolName & ": " & verdict
  for b in blockers:
    echo "  BLOCKER: " & b
  for u in unknowns:
    echo "  UNKNOWN: " & u
  quit(case verdict
       of "PASS": ExitPass
       of "FAIL": ExitFail
       else: ExitUnknown)

when isMainModule:
  main()
