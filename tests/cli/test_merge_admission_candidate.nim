{.push raises: [CatchableError].}

## Unit tests for the ADR-0020 Phase 5 admission predicate extension:
## candidate run↔identity binding (Pass 2.95) — merge_admission_controller.md
## v9 §2b. (The workflow-identity binding Pass 2.6 was removed with the P12
## GitHub delegation — check evidence is the ruleset's authority at merge
## time; fixtures below keep the record schema they construct.)
##
## Re-registration (v1.7.0, 2026-09-24): the single required validation is
## admission-check @ workflowId 365692388 (policy SSOT); fixtures pin it.

import std/[unittest, options, strutils, sets]

import cli/merge_cli
import core/policy/change_graph_facts

const okCheck = CheckStatus(name: "admission-check", conclusion: "success")

func normalRotation(): RotationAdjudication {.raises: [].} =
  ## NORMAL rotation adjudication (closure equal) — the ordinary
  ## qualification, so the candidate-pass assertions stay scoped to Pass 2.95
  ## and the UNSPECIFIED fail-closed deny (Pass 2.97) does not pre-empt them.
  var s = initHashSet[string]()
  s.incl("100644 blob a1\tci/checker.mk")
  adjudicateRotation(s, s, some(s), some(s), @[])

func boundFacts(headSha: string; workflowIdAdmission: int = 365692388): AdmissionFacts =
  ## Fixture facts — validation entry retained as record schema only.
  ## Rotation NORMAL attached: Pass 2.97 fail-closes on UNSPECIFIED
  ## (DEBT#501), and this suite scopes its assertions to the candidate
  ## binding pass (2.95), not to the rotation pass.
  var f = AdmissionFacts(
    headSha: headSha, baseSha: "current-main",
    validations: @[
      ValidationAttempt(jobName: "admission-check", workflowId: workflowIdAdmission, runId: 10, attempt: 1, conclusion: "success")],
    prFileCount: 3, listingComplete: true,
    trustSurfaceHits: @[],
    changeGraph: ChangeGraphStatus(valid: true, nodeCount: 1),
    mergeableState: "clean")
  f.rotation = some(normalRotation())
  f

func boundRecord(headSha: string; candidate: Option[CandidateBinding]): VerificationRecord =
  VerificationRecord(
    headSha: headSha, baseSha: "current-main",
    requiredChecks: @[okCheck],
    admission: some(boundFacts(headSha)),
    candidate: candidate)

suite "Admission contract — candidate run↔identity binding (v9 §2b)":

  test "candidate present but binding unverified → BINDING_MISMATCH (missing ≠ valid empty)":
    let rec = boundRecord("h", some(CandidateBinding(
      candidateTreeDigest: "tree12345678", queueEpoch: 17, position: 2,
      predecessor: "pred", predecessorStatus: "ADMISSIBLE",
      bindingVerified: false, bindingReadPath: "")))
    let outcome = MergeAdmissible(rec, "current-main")
    check outcome.result == mergeAborted
    check outcome.reasonCode == "BINDING_MISMATCH"
    check outcome.reason.contains("not verified")

  test "candidate with verified binding continues to base freshness":
    let rec = boundRecord("h", some(CandidateBinding(
      candidateTreeDigest: "tree12345678", queueEpoch: 17, position: 2,
      predecessor: "pred", predecessorStatus: "ADMISSIBLE",
      bindingVerified: true, bindingReadPath: "api:/repos/o/r/commits/x")))
    let outcome = MergeAdmissible(rec, "current-main")
    check outcome.result == mergeGo
    check outcome.reasonCode == "GO"

  test "candidate without binding is denied even when all checks pass":
    # A bound-but-unverified candidate must not slip through on green checks.
    let rec = boundRecord("h", some(CandidateBinding(
      candidateTreeDigest: "t", queueEpoch: 1, position: 1,
      predecessor: "", predecessorStatus: "",
      bindingVerified: false, bindingReadPath: "")))
    let outcome = MergeAdmissible(rec, "current-main")
    check outcome.reasonCode == "BINDING_MISMATCH"

  test "plain PR record (no candidate) is unaffected by the candidate pass":
    let rec = VerificationRecord(
      headSha: "h", baseSha: "current-main",
      requiredChecks: @[okCheck],
      admission: some(boundFacts("h")),
      candidate: none(CandidateBinding))
    let outcome = MergeAdmissible(rec, "current-main")
    check outcome.result == mergeGo

  test "bound candidate with a base older than main → STALE_BASE":
    # Freshness is asserted before the candidate pass: a verified binding on a
    # stale base never reaches GO.
    var rec = boundRecord("h", some(CandidateBinding(
      candidateTreeDigest: "tree12345678", queueEpoch: 17, position: 2,
      predecessor: "pred", predecessorStatus: "ADMISSIBLE",
      bindingVerified: true, bindingReadPath: "api:/repos/o/r/commits/x")))
    rec.baseSha = "older-main"
    let outcome = MergeAdmissible(rec, "current-main")
    check outcome.result == mergeAborted
    check outcome.reasonCode == "STALE_BASE"
