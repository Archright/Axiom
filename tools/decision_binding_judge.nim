## decision_binding_judge.nim — the single decision-binding judgment kernel.
##
## One policy, two adapters: `tools/decision_binding_checker.nim` (standalone,
## the canonical entry point) and `bin/hermetic_build` (build-time hook) both
## delegate here. Neither reimplements the rule, and neither owns a threshold.
##
## The rule is a COUNT RATCHET, not a calendar.
##
## The defect this replaces: 249 file-scoped "grandfather" waivers. They failed
## in two ways at once.
##
##   1. They hid the debt they were meant to track. Measured on canonical main
##      (5ae980f4) with the waivers active, the check reported 50 files / 213
##      reasons. With the array emptied and nothing else changed, the same scan
##      reported 253 files / 679 reasons: the 249 filenames exempted 203 of the
##      253 violating files (466 of 679 reasons) from ever being counted. The
##      number the gate printed was not the debt — it was the debt the waivers
##      had not reached.
##   2. All 249 shared one expiry (2026-12-31) and floored a
##      `daysRemaining < 30` test into a hard build FAIL from 2026-12-01. From
##      that instant a calendar, not the code, would have stopped the build.
##
## A filename exemption is a permanent, unmeasured exception. A count baseline
## is a measured, reviewable acceptance. This kernel keeps the second and drops
## the first:
##
##   growth of the violation count     → FAIL   (a new violation is a decision)
##   review date passed                → WARN   (visibility, never a gate)
##   baseline absent or malformed      → FAIL   (fail-closed)
##   a re-anchor that raises the count → FAIL   (a tool may not lift its own bar)
##
## The review date deliberately does not fail the build: a calendar must never
## be able to stop correct work, and the ratchet already fails on the thing that
## matters. An overdue review is reported on every run so it cannot be forgotten.

import std/strutils

const
  JudgeBaselineVersion* = 1
  JudgeGateId* = "decision_binding"
  JudgeCheckerVersion* = "2.0.0"

  JudgePolicyDescriptor* =
    "decision_binding/v1|scope=src|unit_files=files|unit_reasons=reasons|" &
    "reason=returns_result_or_option|reason=multiple_returns|reason=validation_logic"

  JudgePolicyHash* =
    "f6b34fe05a90e1110d610ac9d3b9c5ae670bc5209e2a0d1b9f72f82e424455e9"
    ## sha256 of `JudgePolicyDescriptor`, computed at authoring time. Changing
    ## the descriptor without re-anchoring the baseline is a policy drift the
    ## judge refuses (a measurement taken under another rule is not comparable).

type
  ReasonCount* = object
    reason*: string
    count*: int

  RatchetBaseline* = object
    ## Provenance is part of the baseline, not decoration: a count with no
    ## source commit cannot be re-derived, and a count with no owner is an
    ## unattributed risk acceptance.
    baselineVersion*: int
    gate*: string
    scope*: string
    owner*: string
    rationale*: string
    reviewBy*: string        ## ISO yyyy-MM-dd; advisory only
    measuredAt*: string      ## ISO 8601 UTC instant of the measurement
    sourceCommit*: string    ## git SHA the count was measured at
    checkerVersion*: string
    policyHash*: string
    filesWithViolations*: int
    totalReasons*: int
    perReason*: seq[ReasonCount]

  JudgeState* = enum
    jsPass
    jsRatchetViolation
    jsInvalidBaseline

  Verdict* = object
    state*: JudgeState
    exitCode*: int
    reviewOverdue*: bool
    messages*: seq[string]

func stateTag*(s: JudgeState): string {.raises: [].} =
  case s
  of jsPass: "PASS"
  of jsRatchetViolation: "RATCHET_VIOLATION"
  of jsInvalidBaseline: "INVALID_BASELINE"

func isIsoDate*(s: string): bool {.raises: [].} =
  ## Shape check only — exactly `yyyy-MM-dd` with '-'-separated digit runs.
  ## Calendar validity is deliberately not judged: a typo in a review date must
  ## not be able to stop a build (that is the defect this replaces).
  if s.len != 10:
    return false
  for i, ch in s:
    if i == 4 or i == 7:
      if ch != '-':
        return false
    elif ch notin {'0'..'9'}:
      return false
  true

func reviewContractProblem*(b: RatchetBaseline): string {.raises: [].} =
  ## The part of the baseline a human authors. A measurement may not supply it.
  if b.owner.strip().len == 0:
    return "owner missing — a count without an owner is an unattributed risk"
  if b.rationale.strip().len == 0:
    return "rationale missing"
  if not isIsoDate(b.reviewBy):
    return "reviewBy=" & (if b.reviewBy.len == 0: "<empty>" else: b.reviewBy) &
      " (expected yyyy-MM-dd)"
  ""

func baselineProblem(b: RatchetBaseline): string {.raises: [].} =
  ## Fail-closed structural check. Returns "" when the baseline is usable.
  if b.baselineVersion != JudgeBaselineVersion:
    return "baselineVersion=" & $b.baselineVersion & " (judge supports " &
      $JudgeBaselineVersion & ")"
  if b.gate != JudgeGateId:
    return "gate=" & (if b.gate.len == 0: "<empty>" else: b.gate) &
      " (expected " & JudgeGateId & ")"
  let contract = reviewContractProblem(b)
  if contract.len > 0:
    return contract
  if b.filesWithViolations < 0 or b.totalReasons < 0:
    return "negative counts (files=" & $b.filesWithViolations &
      ", reasons=" & $b.totalReasons & ")"
  if b.policyHash != JudgePolicyHash:
    return "policyHash=" & b.policyHash & " but the current judge policy is " &
      JudgePolicyHash & " — re-anchor with --update-baseline after review"
  ""

func judgeDecisionBinding*(filesWithViolations, totalReasons: int,
                           b: RatchetBaseline,
                           today: string): Verdict {.raises: [].} =
  ## Pure. `today` is an ISO date supplied by the caller so the verdict is a
  ## function of its inputs and nothing else (no clock read inside).
  result.messages = @[]
  result.reviewOverdue = false
  result.exitCode = 0
  result.state = jsPass

  let problem = baselineProblem(b)
  if problem.len > 0:
    result.state = jsInvalidBaseline
    result.exitCode = 1
    result.messages.add("baseline is invalid: " & problem)
    return

  result.reviewOverdue = today.len > 0 and today > b.reviewBy

  var grew: seq[string] = @[]
  if filesWithViolations > b.filesWithViolations:
    grew.add("files carrying violations " & $filesWithViolations & " > baseline " &
      $b.filesWithViolations)
  if totalReasons > b.totalReasons:
    grew.add("violation reasons " & $totalReasons & " > baseline " & $b.totalReasons)

  if grew.len > 0:
    result.state = jsRatchetViolation
    result.exitCode = 1
    for g in grew:
      result.messages.add("ratchet violation: " & g)
    result.messages.add("the ratchet only falls: annotate the new decision " &
      "point, or remove the code that carries it. Raising the baseline is a " &
      "hand-authored risk acceptance, not a tool invocation")
    return

  if filesWithViolations < b.filesWithViolations or totalReasons < b.totalReasons:
    result.messages.add("ratchet has headroom: measured " & $filesWithViolations &
      " files / " & $totalReasons & " reasons, baseline allows " &
      $b.filesWithViolations & " / " & $b.totalReasons &
      " — lower it with --update-baseline so the gain is locked in")

  if result.reviewOverdue:
    result.messages.add("baseline review overdue: reviewBy=" & b.reviewBy &
      " owner=" & b.owner & " (build continues; the acceptance is stale)")

  result.state = jsPass
  result.exitCode = 0

func reanchorProblem*(filesWithViolations, totalReasons: int,
                      b: RatchetBaseline): string {.raises: [].} =
  ## May a fresh measurement REPLACE this baseline? Lowering is mechanical;
  ## raising is a risk acceptance and cannot be produced by a tool. Without this
  ## the ratchet lifts itself: a developer who adds a decision point runs
  ## `--update-baseline`, the baseline follows the measurement, and the check
  ## that is supposed to fail can never fail. Accepting more debt must appear as
  ## a hand-edited owner/rationale/reviewBy change in review, never as output.
  let contract = reviewContractProblem(b)
  if contract.len > 0:
    return "cannot re-anchor: " & contract & " — that review contract is " &
      "written by a human, not generated here"
  var grew: seq[string] = @[]
  if filesWithViolations > b.filesWithViolations:
    grew.add("files " & $filesWithViolations & " > accepted " & $b.filesWithViolations)
  if totalReasons > b.totalReasons:
    grew.add("reasons " & $totalReasons & " > accepted " & $b.totalReasons)
  if grew.len > 0:
    return "refusing to raise the ratchet (" & grew.join("; ") & ") — to " &
      "accept more debt, edit the baseline file by hand and state the owner, " &
      "rationale and reviewBy, so the increase is an authored decision"
  ""