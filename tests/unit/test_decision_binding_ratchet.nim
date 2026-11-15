## Contract tests — decision-binding ratchet kernel.
##
## The defect under test: 249 file-scoped waivers. With them active the check
## reported 50 files / 213 reasons at 5ae980f4; with the array emptied and
## nothing else changed, 253 files / 679 reasons. So the waivers were not
## inert — they kept 203 of the 253 violating files out of the count entirely —
## and all 249 shared one expiry (2026-12-31) floored through a
## `daysRemaining < 30` test into a hard build FAIL.
##
## The contract under test: growth of the measured count FAILs; a date only
## WARNs; an unusable baseline FAILs closed; a re-anchor may only lower.
##
## Every case injects `today`, so the verdict is a pure function of its inputs.
## No clock is read here or inside the judge, which is what makes the boundary
## dates testable at all.

import std/[strutils, unittest]
import ../../tools/decision_binding_judge

proc baseline(files = 253, reasons = 679): RatchetBaseline =
  RatchetBaseline(
    baselineVersion: JudgeBaselineVersion,
    gate: JudgeGateId,
    scope: "src",
    owner: "@Archright/architect",
    rationale: "measured acceptance of the pre-existing pragma debt",
    reviewBy: "2027-06-30",
    measuredAt: "2026-11-15T03:56:05Z",
    sourceCommit: "5ae980f447f531e0ee8a63ca635aab8846c2d667",
    checkerVersion: JudgeCheckerVersion,
    policyHash: JudgePolicyHash,
    filesWithViolations: files,
    totalReasons: reasons)

suite "decision-binding ratchet":
  test "at baseline is PASS and not overdue":
    let v = judgeDecisionBinding(253, 679, baseline(), "2026-11-15")
    check v.state == jsPass
    check v.exitCode == 0
    check not v.reviewOverdue

  test "one more file carrying a violation fails":
    let v = judgeDecisionBinding(254, 679, baseline(), "2026-11-15")
    check v.state == jsRatchetViolation
    check v.exitCode == 1

  test "one more reason fails even when the file count is unchanged":
    let v = judgeDecisionBinding(253, 680, baseline(), "2026-11-15")
    check v.state == jsRatchetViolation
    check v.exitCode == 1

  test "a fall below baseline passes and reports headroom":
    let v = judgeDecisionBinding(252, 679, baseline(), "2026-11-15")
    check v.state == jsPass
    check v.exitCode == 0
    check v.messages.len == 1
    check "headroom" in v.messages[0]

  test "the old defect's dates cannot stop a build at baseline":
    for day in ["2026-11-15", "2026-11-30", "2026-12-01", "2026-12-31",
                "2027-01-01", "2027-01-31", "2027-06-30", "2027-07-01"]:
      let v = judgeDecisionBinding(253, 679, baseline(), day)
      check v.state == jsPass
      check v.exitCode == 0

  test "reviewBy day itself is not overdue; the next day is":
    check not judgeDecisionBinding(253, 679, baseline(), "2027-06-30").reviewOverdue
    check judgeDecisionBinding(253, 679, baseline(), "2027-07-01").reviewOverdue

  test "an overdue review warns and never fails":
    let v = judgeDecisionBinding(253, 679, baseline(), "2030-01-01")
    check v.state == jsPass
    check v.exitCode == 0
    check v.reviewOverdue
    check v.messages.len == 1
    check "review overdue" in v.messages[0]

  test "an overdue review does not mask a ratchet violation":
    let v = judgeDecisionBinding(300, 700, baseline(), "2030-01-01")
    check v.state == jsRatchetViolation
    check v.exitCode == 1

  test "a baseline with no owner is invalid — a count is not a risk acceptance":
    var b = baseline()
    b.owner = ""
    let v = judgeDecisionBinding(253, 679, b, "2026-11-15")
    check v.state == jsInvalidBaseline
    check v.exitCode == 1

  test "a baseline with no rationale is invalid":
    var b = baseline()
    b.rationale = "   "
    check judgeDecisionBinding(253, 679, b, "2026-11-15").state == jsInvalidBaseline

  test "a malformed review date is invalid":
    var b = baseline()
    b.reviewBy = "2027-6-30"
    check judgeDecisionBinding(253, 679, b, "2026-11-15").state == jsInvalidBaseline

  test "a baseline measured under another policy is refused":
    var b = baseline()
    b.policyHash = "0".repeat(64)
    let v = judgeDecisionBinding(253, 679, b, "2026-11-15")
    check v.state == jsInvalidBaseline
    check v.exitCode == 1

  test "a baseline for another gate is refused":
    var b = baseline()
    b.gate = "core_purity"
    check judgeDecisionBinding(253, 679, b, "2026-11-15").state == jsInvalidBaseline

  test "negative counts are refused":
    var b = baseline()
    b.filesWithViolations = -1
    check judgeDecisionBinding(253, 679, b, "2026-11-15").state == jsInvalidBaseline

  test "the verdict is deterministic for identical inputs":
    let a = judgeDecisionBinding(253, 679, baseline(), "2026-11-15")
    let b = judgeDecisionBinding(253, 679, baseline(), "2026-11-15")
    check a.state == b.state
    check a.exitCode == b.exitCode
    check a.reviewOverdue == b.reviewOverdue
    check a.messages == b.messages

suite "iso date shape":
  test "accepts the canonical shape":
    check isIsoDate("2027-06-30")

  test "rejects anything else":
    check not isIsoDate("2027-6-30")
    check not isIsoDate("2027/06/30")
    check not isIsoDate("2027-06-3x")
    check not isIsoDate("2027-06-300")
    check not isIsoDate("")

suite "re-anchoring may only lower the ratchet":
  ## A tool that can raise the number it is measured against has no threshold.
  ## `--update-baseline` is that tool, so the refusal lives in the kernel.

  test "lowering both counts is allowed":
    check reanchorProblem(200, 500, baseline()) == ""

  test "lowering one count while the other holds is allowed":
    check reanchorProblem(200, 679, baseline()) == ""
    check reanchorProblem(253, 500, baseline()) == ""

  test "holding both counts is allowed":
    check reanchorProblem(253, 679, baseline()) == ""

  test "raising either count is refused":
    check reanchorProblem(254, 679, baseline()).len > 0
    check reanchorProblem(253, 680, baseline()).len > 0
    check reanchorProblem(254, 680, baseline()).len > 0

  test "the refusal names the measurement and the accepted debt":
    let msg = reanchorProblem(300, 900, baseline())
    check "300" in msg
    check "253" in msg
    check "900" in msg
    check "679" in msg

  test "a baseline with no review contract cannot be re-anchored at all":
    var b = baseline()
    b.owner = "  "
    check reanchorProblem(100, 100, b).len > 0
