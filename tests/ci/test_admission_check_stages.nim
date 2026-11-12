## test_admission_check_stages.nim — admission-check stage-dispatch contract
##
## The callee is invoked TWICE by the org gate (attest then verdict, ordered by
## the caller's `needs:`). Both invocations run the SAME pinned file, so nothing
## outside this file distinguishes the two halves except the `stage` input and
## the step-level `if:` conjuncts. Those conjuncts are the contract:
##
##   * witness production (`ax cert attest --witness-only`) and the witness
##     upload must be reachable ONLY under `stage: attest` — a witness produced
##     inside the verdict invocation could never reach the mint, which runs
##     before the verdict in the trust order;
##   * the certificate handoff and `ax merge --dry-run --json` must be reachable
##     ONLY under `stage: verdict` — this is the half that consumes the
##     certificate the mint published earlier in the same run;
##   * the provisioning preamble (B checkout, slice engine, toolchain, base
##     artifact download + `build_sha == B` verification) stays ungated, so both
##     stages see the same base-built verifier.
##
## The failure this file pins is the one measured on 2026-10-04: with both
## halves in one invocation the verdict necessarily ran before the mint, so
## `certRequired` could not be satisfied and every PR needed a second attempt
## (17 runs, ~202 minutes). A stage conjunct that is quietly dropped restores
## exactly that loop, and nothing else in the tree observes it.
##
## L3 split (work/l3-go-split-2026-11-04, prereg
## docs/evidence/l3_go_prereg_2026-11-03.md): the GO-independent steps
## (Core purity gate / Re-derive admission identity / Stage D9 evidence /
## Register subject) moved to a THIRD callee job, `admission-independents`,
## which re-pays the same provisioning preamble and runs parallel to the GO
## lane. The stage semantics do not change — every moved step keeps its
## byte-identical guard, the witness stays in `admission-check` behind the GO
## results, and the occurrence counts below are re-pinned for the three-job
## topology (preamble steps 3x, slice engine 4x, candidate-H checkout 2x).
##
## Structural, fail-closed text assertions over the workflow source — no YAML
## parser is available to the toolchain, and a missing file, a renamed step, or
## a vanished conjunct all fail here rather than degrade to a partial match.

import std/[unittest, os, strutils]

const
  WorkflowRel = ".github/workflows/admission-check.yml"

proc repoRoot(): string =
  result = absolutePath(currentSourcePath())
  for _ in 0 ..< 3:
    result = result.parentDir()

proc stepBlocks(src: string, nameSubstring: string): seq[string] =
  ## Raw text of every step whose `- name:` line contains `nameSubstring`. Some
  ## steps exist in both jobs by design (the slice engine runs in each), so the
  ## plural form is the primitive and the accessors below assert on it.
  ## A block ends at ANY top-level `- ` step item, not only `- name:`: the
  ## setup-axiom-toolchain steps are declared as bare `- uses:` (no `name:`),
  ## and bounding only on `- name:` would absorb the nameless step's `if:` —
  ## e.g. its legitimate stage gate — into the preceding step's guard.
  let lines = src.splitLines()
  for start, line in lines:
    if not (line.startsWith("      - name:") and nameSubstring in line):
      continue
    var body = @[line]
    for i in start + 1 ..< lines.len:
      if lines[i].startsWith("      - "):
        break
      body.add(lines[i])
    result.add(body.join("\n"))

proc stepIfs(src: string, nameSubstring: string): seq[string] =
  ## The `if:` expression of every matching step ("" for a step that carries
  ## none) — the first `if:` line inside the step's own block, so an attribute
  ## of a LATER step can never be read as this step's guard.
  for body in stepBlocks(src, nameSubstring):
    var guard = ""
    for line in body.splitLines():
      if line.startsWith("        if: "):
        guard = line["        if: ".len .. ^1]
        break
    result.add(guard)

proc stepIf(src: string, nameSubstring: string): string =
  ## The `if:` of the ONE step named `nameSubstring`, or "" when it carries
  ## none. A missing or duplicated step raises: a renamed, removed, or cloned
  ## step must never read as "ungated", which would make every conjunct
  ## assertion below pass vacuously.
  let guards = stepIfs(src, nameSubstring)
  if guards.len == 0:
    raise newException(ValueError,
      "step '" & nameSubstring & "' not found in " & WorkflowRel)
  if guards.len > 1:
    raise newException(ValueError,
      "step '" & nameSubstring & "' occurs " & $guards.len &
      " times in " & WorkflowRel & " — the assertion below is ambiguous")
  guards[0]

proc stepBlock(src: string, nameSubstring: string): string =
  ## Raw text of the ONE step named `nameSubstring`; raises when absent or
  ## duplicated, for the same reason `stepIf` does.
  let blocks = stepBlocks(src, nameSubstring)
  if blocks.len != 1:
    raise newException(ValueError,
      "step '" & nameSubstring & "' occurs " & $blocks.len & " time(s) in " &
      WorkflowRel & " — expected exactly one")
  blocks[0]

proc jobIf(src: string, jobName: string): string =
  let lines = src.splitLines()
  var start = -1
  for i, line in lines:
    if line.startsWith("  " & jobName & ":"):
      if start >= 0:
        raise newException(ValueError,
          "ambiguous job match '" & jobName & "' in " & WorkflowRel)
      start = i
  if start < 0:
    raise newException(ValueError,
      "job '" & jobName & "' not found in " & WorkflowRel)
  for i in start + 1 ..< lines.len:
    let line = lines[i]
    if line.startsWith("  ") and not line.startsWith("    "):
      break
    if not line.startsWith("    if: "):
      continue
    var value = line["    if: ".len .. ^1].strip()
    if value notin [">", ">-", "|", "|-"]:
      return value
    # Folded/literal block scalar — the expression lives on the following,
    # more-indented lines. Rejoined with spaces: the guard is a boolean
    # expression, so its line breaks carry no meaning.
    for j in i + 1 ..< lines.len:
      if not lines[j].startsWith("      "):
        break
      value.add(" " & lines[j].strip())
    return value
  ""

suite "admission-check — stage dispatch is selectable":
  setup:
    let src = readFile(repoRoot() / WorkflowRel)

  test "the callee declares stage as a REQUIRED workflow_call input":
    check "workflow_call:" in src
    check "stage:" in src
    let inputsAt = src.find("workflow_call:")
    check inputsAt >= 0
    let tail = src[inputsAt .. min(inputsAt + 700, src.high)]
    check "required: true" in tail

  test "both stages are accepted by the admission-check job guard":
    let guard = jobIf(src, "admission-check")
    check "inputs.stage == 'attest'" in guard
    check "inputs.stage == 'verdict'" in guard
    ## L3 prereg §2.4: `always()` was REPLACED by `!cancelled()`. A skipped
    ## need is reported as Success at the check level, so an `always()`-free
    ## job whose needs silently skipped could turn a dead dependency into a
    ## masked green; `!cancelled()` keeps this job running past a failed or
    ## skipped need so the [guard] needs-result step can make the dependency
    ## state an explicit red. Pinning `always()` OUT is part of the contract.
    check "!cancelled()" in guard
    check "always()" notin guard

  test "the B build belongs to the attest stage":
    let guard = jobIf(src, "build-base-artifacts")
    check guard == "inputs.stage == 'attest'"

  test "witness production and the witness upload are attest-only":
    ## L3 split: Register subject / Stage D9 evidence / Re-derive admission
    ## identity moved to `admission-independents` — each still occurs exactly
    ## once (now on the producer side) and must stay attest-only, because the
    ## values they export feed the mint-ordered attest half. "Checkout
    ## candidate = H" legitimately occurs TWICE now (admission-check +
    ## admission-independents), so its guard is asserted per occurrence.
    for step in ["Attest witness-only", "Register subject", "Stage D9 evidence",
                 "Re-derive admission identity"]:
      check stepIf(src, step).contains("inputs.stage == 'attest'")
      check not stepIf(src, step).contains("inputs.stage == 'verdict'")
    let hGuards = stepIfs(src, "Checkout candidate = H")
    check hGuards.len == 2
    for guard in hGuards:
      check guard.contains("inputs.stage == 'attest'")
      check not guard.contains("inputs.stage == 'verdict'")

  test "the witness upload keeps its always() edge":
    let guard = stepIf(src, "Upload admission records")
    check guard.contains("always()")
    check guard.contains("inputs.stage == 'attest'")

  test "certificate consumption and the predicate are verdict-only":
    for step in ["Admission predicate evaluation", "Fetch subject-certificate artifact",
                 "Load derived-closure sets"]:
      check stepIf(src, step).contains("inputs.stage == 'verdict'")
      check not stepIf(src, step).contains("inputs.stage == 'attest'")

  test "the provisioning preamble carries no stage conjunct":
    ## Both stages run the same provisioning: the B checkout has no guard at
    ## all, and the base-artifact download / manifest verification stay under
    ## the slice-engine scope conjunct they have always carried. What must NOT
    ## appear here is `inputs.stage` — a stage-scoped preamble would starve one
    ## half of the pipeline of its verifier.
    ##
    ## Occurrence-count provenance (G2 generation, 2026-10-16): the
    ## go-critical-lane matrix job re-derives the same preamble the
    ## admission-check job performs ("Each lane re-derives the same
    ## provisioning this job performs (B checkout, slice engine, toolchain,
    ## base-artifact manifest verify)" — workflow header). L3 split
    ## (2026-11-04) adds the third payer: `admission-independents` re-pays
    ## the same preamble, so each preamble step now occurs THREE times
    ## (admission-check + go-critical-lane + admission-independents) and the
    ## slice engine FOUR times (build-base-artifacts too).
    ## The exact counts pin that topology — a renamed/vanished step reads as
    ## 0 and an unexpected clone inflates the count, both failing here — and
    ## EVERY occurrence must stay free of `inputs.stage`.
    for step in ["Checkout executor tree = B", "Verify artifact manifest",
                 "Download base-built artifacts"]:
      let guards = stepIfs(src, step)
      check guards.len == 3
      for guard in guards:
        check "inputs.stage" notin guard
    let engines = stepIfs(src, "Load epoch manifest implementedSlices")
    check engines.len == 4
    for guard in engines:
      check "inputs.stage" notin guard

  test "no step is gated to both stages (dispatch stays exclusive)":
    for step in ["Attest witness-only", "Admission predicate evaluation",
                 "Register subject", "Fetch subject-certificate artifact",
                 "Upload admission records", "Load derived-closure sets"]:
      let guard = stepIf(src, step)
      check not (guard.contains("inputs.stage == 'attest'") and
                 guard.contains("inputs.stage == 'verdict'"))

  test "artifact identity and attempt scoping are unchanged":
    check "name: admission-check-${{ github.event.pull_request.head.sha || github.event.merge_group.head_sha || github.sha }}-${{ github.run_attempt }}" in src
    check "name: admission-check-${{ github.event.pull_request.head.sha || github.event.merge_group.head_sha || github.sha }}" in src
    check "name: subject-certificate-${{ github.run_attempt }}" in src
    ## Anchored on the exact uncommented line: a substring search would still
    ## pass if the injection were commented out (which would leave the verdict
    ## evaluating against the live PR-API base — the Phase 1 freshness anchor's
    ## input).
    ## Provenance (Stage 2 run-scoped anchor B* — the workflow_call `baseSha`
    ## input, "Consumed FIRST on the pull_request venue; the event payload
    ## remains the fallback so callers that do not pass it behave exactly as
    ## before"): the line legitimately gained the `inputs.baseSha ||` prefix
    ## term — evaluation identical for legacy callers, and merge_group stays
    ## event-frozen (baseSha defaults to empty, ADR-0027 P4). The
    ## Phase-2a-era expectation (`github.event...base_sha` alone) is stale; the
    ## anchor below pins the Stage 2 line, preserving the anti-commenting
    ## property the exact match exists for.
    check "\n          AXIOM_MAIN_SHA: ${{ inputs.baseSha || github.event.pull_request.base.sha || github.event.merge_group.base_sha }}\n" in src

  test "the base-artifact payload keeps its stable overwrite contract":
    ## Scoped to THIS step's block on purpose: a whole-file search would be
    ## satisfied by any `overwrite: true` anywhere in the file, and this flag is
    ## what keeps the mint's exactly-one lookup on `admission-check-base-artifacts`
    ## from failing closed with "found 2" across re-runs of one run_id — the
    ## artifact the verdict stage consumes is the attest stage's upload.
    let upload = stepBlock(src, "Upload base-built artifacts")
    check "name: admission-check-base-artifacts" in upload
    check "overwrite: true" in upload