## publication_report.nim — the single verdict aggregation of the
## publication-integrity gate.
##
## Runs as the `publication-integrity` job (the check-run context that the
## ruleset binds) on EVERY venue. It consumes:
##   - the VENUE (`--venue <github.event_name>` — required, closed enum);
##   - the sub-job RESULTS (GitHub `needs.<job>.result`, passed as
##     `--job <name>=<result>` — success / failure / cancelled / skipped);
##   - each sub-job's dimension report (path + expected dimension name,
##     `--report <dimension>=<path.json>`);
##   - the binding facts: commit SHA, tree SHA, policy file sha256 revisions.
##
## VENUE CONTRACT (ADR-0032 (a),(b) extended to the job layer):
##
##   pull_request                              → preflight → {secret-scan}
##   merge_group | schedule | workflow_dispatch → landing   → all 5 dimensions
##   anything else                             → FAIL (no venue → no verdict)
##
## The landing venue is the SOLE canonical verdict. The preflight venue is an
## early-warning lane, never a landing credential: its PASS line says so.
##
## Adjudication (fail-closed), applied to the venue's REQUIRED set only:
##   - every required sub-job result must be EXACTLY `success` (a skipped or
##     cancelled sub-job is a missing verdict → UNKNOWN → BLOCK — a skipped
##     required check reports success at the platform level, so this job must
##     never be skipped itself and must treat every non-success sub-result as
##     a blocker);
##   - a `success` for a dimension the venue does NOT require is a BLOCKER,
##     never a pass — a workflow may not earn credit for a check it did not
##     intend to run (retired/renamed job ids included);
##   - every required dimension report must exist, parse, and carry
##     verdict == PASS;
##   - any unreadable/unparsable report or missing input → UNKNOWN → BLOCK.
##
## The report binds: venue, the required set it was judged against, commit SHA,
## tree SHA (`git rev-parse HEAD^{tree}`), sha256 of each policy file (policy
## revision), and per-dimension verdicts. `publicationReadiness` is PASS only
## when every REQUIRED dimension is PASS with zero unresolved UNKNOWNs.
##
## Exit: 0 = PASS, 1 = FAIL, 2 = UNKNOWN. An unknown/unrecognised venue is 1,
## not 2 — it is a rejected input, never an absent observation.
##
## Part of the publication-integrity gate (docs/spec/publication_integrity_gate.md).

import std/[json, os, parseopt, strutils, sequtils]
import core/trusted/layer_declaration
import core/crypto/hash_kernel
import core/results

axiomLayer "tools"

const
  ToolName = "publication_report"
  ExitPass = 0
  ExitFail = 1
  ExitUnknown = 2
  ## The full dimension set — every dimension the gate can ever judge.
  Dimensions = ["secret-scan", "license-scan", "dependency-scan",
                "provenance", "sbom"]
  ## The closed venue→required-set enum. Adding a venue or moving a dimension
  ## between venues is a CONTRACT change (docs/spec/publication_integrity_gate.md
  ## §3), never a local edit.
  LandingEvents = ["merge_group", "schedule", "workflow_dispatch"]
  PreflightEvents = ["pull_request"]
  PreflightDimensions = ["secret-scan"]

type
  Inputs = object
    venue: string
    outPath: string
    headSha: string
    treeSha: string
    jobs: seq[tuple[name, result: string]]
    reports: seq[tuple[dimension, path: string]]
    policyFiles: seq[string]

proc requiredDimensions(venue: string): seq[string] =
  ## Venue → required set. A closed enum: the caller (main) has already
  ## rejected anything not listed here.
  if venue in PreflightEvents: @PreflightDimensions
  elif venue in LandingEvents: @Dimensions
  else: @[]

proc knownVenue(venue: string): bool =
  venue in PreflightEvents or venue in LandingEvents

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
      of "venue": inputs.venue = val
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
  if inputs.venue.len == 0:
    return err("--venue is required (the GitHub event name: " &
      (@PreflightEvents & @LandingEvents).join("|") & ")")
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

  # ── venue gate: an unrecognised event is a rejected input, never a pass ──
  if not knownVenue(inputs.venue):
    echo ToolName & " VENUE UNDETERMINED: '" & inputs.venue &
      "' is not a recognised venue (preflight: " & PreflightEvents.join("|") &
      "; landing: " & LandingEvents.join("|") & ")"
    quit(ExitFail)
  let required = requiredDimensions(inputs.venue)
  let optional = Dimensions.filterIt(it notin required)

  var
    blockers: seq[string] = @[]
    unknowns: seq[string] = @[]
    dimensionVerdicts: seq[JsonNode] = @[]

  # every REQUIRED sub-job result must be exactly success
  for d in required:
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

  # a success for a dimension this venue does not require is NOT credit:
  # the workflow is running or being credited for something it did not intend
  # to run (retired/renamed job ids included).
  for d in optional:
    for j in inputs.jobs:
      if j.name == d and j.result == "success":
        blockers.add("job " & d & " reported success but is NOT required at venue '" &
          inputs.venue & "' — a non-required dimension may never contribute credit")

  # every REQUIRED dimension report must exist, parse, and be PASS
  for d in required:
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

  # an out-of-venue dimension report is gating drift: the workflow and the
  # venue contract disagree about what this venue runs. Ignoring it silently
  # would let a stale/renamed dimension ride along unobserved.
  for r in inputs.reports:
    if r.dimension notin required:
      unknowns.add("report supplied for '" & r.dimension &
        "' which venue '" & inputs.venue & "' does not require (gating drift)")

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
    "schemaVersion": 2,
    "gate": "publication-integrity",
    "venue": inputs.venue,
    "canonicalLandingVerdict": inputs.venue in LandingEvents,
    "requiredDimensions": required,
    "notRequiredDimensions": optional,
    "verdict": verdict,
    "verdictSemantics": {
      "PASS": "every dimension PASS, zero unresolved UNKNOWN",
      "FAIL": "an observed blocker",
      "UNKNOWN": "a verdict could not be established — BLOCKING (fail-closed), never a pass"
    },
    "venueSemantics": {
      "preflight": "only the preflight set is required; PASS here is NOT a landing credential",
      "landing": "all five dimensions are required; this is the canonical landing verdict"
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
  # The preflight line must never be readable as a landing credential.
  if inputs.venue in PreflightEvents:
    echo "PREFLIGHT " & verdict &
      " — venue=preflight; full publication verification is the merge_group venue"
  else:
    echo ToolName & ": " & verdict & " (venue=landing, canonical)"
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
