import std/[options, os, strutils]
import core/crypto/hash_kernel
import core/results
import core/deterministic_cas_key
import core/trusted/axiom_ir
import core/trusted/semantic_fact_types
import ../../tools/ci/check_evidence_id_contract
import infrastructure/evidence_artifact_io
import infrastructure/external_ir_materializer
import verification/obligation/canonical_verification
import verification/obligation/golden_fixture_ir
import verification/obligation/kernel_acceptance_authority

## evidenceId contract PROBE — the real-chain leg of the B-owned independent
## contract check (the fixture battery lives in the checker tool,
## tools/ci/check_evidence_id_contract.nim --self-check).
##
## This file executes the REAL canonical chain on the golden sub fixture
## through the WORKSPACE source — in the GO-critical lane that is the
## OVERLAID CANDIDATE (M) src/ — and hands the observed raw CLE components
## to the checker's `checkContract` (the authority: its own H(c1..c6[|digest])
## preimage). The candidate's claimed evidenceId is only the comparison
## target; the observation is never the judgment.
##
## B-owned: this file is never overlaid from the candidate (the lane overlays
## only candidate src/ + the four explicit GO-critical test files), so the
## check always runs B's contract against M's implementation.
##
## The lane consumes this as the EXECUTED contract check: exit 0 = PASS,
## exit 1 = FAIL (fail-closed — the lane's aggregate refuses any other
## outcome). No CAS surface: this check is never REUSED.

var failures = 0

proc expect(cond: bool; msg: string) =
  if cond:
    echo "  [PASS] " & msg
  else:
    inc failures
    echo "  FAIL: " & msg

proc probeComponents(): Result[EvidenceIdComponents, string] {.
    raises: [CatchableError, OSError, Exception]} =
  let fd = gfSubPostcondition()
  let sourcePath = "tests/golden/sub_postcondition.nim"
  if not fileExists(sourcePath):
    return err("probe fixture missing (fail-closed): " & sourcePath)
  # The test-boundary materializer role (the s1a suite's setup): the strict
  # completeness component must be measurable for the internal fixture.
  let key = computeDeterministicCasKey(serializeIRFuncDef(fd))
  let evidence = CompletenessEvidence(
    translationLossFree: true,
    bindingUniverseComplete: true,
    opaqueExpansionStatus: "none",
    sourceBindingCount: 1,
    irBindingCount: 1)
  saveEvidenceArtifact(key, evidence)
  var source = ""
  try:
    source = readFile(sourcePath)
  except CatchableError as e:
    return err("probe fixture unreadable (fail-closed): " & sourcePath & ": " & e.msg)
  let capture = measureCompletenessSourceCapture("", sourcePath, source,
    contentCarried = false)
  if not saveCompletenessEvidenceDual(key, fd, capture, evidence):
    return err("strict completeness dual-write refused (unmeasured capture) — " &
      "probe cannot proceed (fail-closed)")
  let parseBound = measureParseBoundComponents(source, "subPostcondition")
  let r = executeCanonicalVerification(fd, sourcePath, "subPostcondition",
    parseBound = parseBound)
  if not r.success:
    return err("probe chain did not verify (success=false, sealError='" &
      r.sealError & "') — no components to check (fail-closed)")
  if not r.canonicalEvidence.isSome:
    return err("probe chain produced no canonicalEvidence (fail-closed)")
  let e = r.canonicalEvidence.get()
  # Internal binding re-verification (observation must be self-consistent):
  # a component that does not hash its own raw content is corrupt evidence.
  if sha256Hex(e.cleProposition) != e.clePropositionHash:
    return err("propositionHash does not bind the observed proposition (fail-closed)")
  if sha256Hex(e.cleLeanSource) != e.cleLeanSourceHash:
    return err("leanSourceHash does not bind the observed Lean source (fail-closed)")
  if sha256Hex(e.cleCanonicalKaaJson) != e.cleKaaDigest:
    return err("kaaDigest does not bind the observed canonical KAA projection (fail-closed)")
  # The checker's own structural gate (missing/non-64-hex rejection) runs
  # inside checkContract — the observation is handed over unmodified.
  var c = EvidenceIdComponents(
    obligationId: e.cleObligationId,
    propositionHash: e.clePropositionHash,
    leanSourceHash: e.cleLeanSourceHash,
    kaaDigest: e.cleKaaDigest,
    toolchainFingerprint: e.cleToolchainFingerprint,
    executionContractDigest: e.cleExecutionContractDigest,
    completenessBindingDigest: e.cleCompletenessBindingDigest,
    claimedEvidenceId: e.evidenceId)
  if e.cleCompletenessBindingDigest.len > 0:
    c.completenessContract = CompletenessContractStrictV1
  ok(c)

proc main(): int {.
    raises: [CatchableError, OSError, Exception]} =
  echo "[evidence-id-contract] probe EXECUTED — real canonical chain (workspace src)"
  let got = probeComponents()
  if got.isErr:
    echo "[evidence-id-contract] FAIL — probe: " & got.error
    return 1
  let verdict = checkContract(got.get)
  if verdict.len > 0:
    echo "[evidence-id-contract] FAIL — " & verdict
    return 1
  let formula = "H(c1..c6" &
    (if got.get.completenessBindingDigest.len > 0: "|completenessBindingDigest)" else: ")")
  echo "  [PASS] evidenceId contract — formula=" & formula & " contract=" &
    EvidenceIdContractVersion
  echo "  [PASS] recomputed (B-owned preimage) == claimed (candidate) — evidenceId=" &
    got.get.claimedEvidenceId[0 ..< 16] & "…"
  if failures > 0:
    echo "[evidence-id-contract] FAIL — " & $failures & " failure(s)"
    return 1
  echo "[evidence-id-contract] PASS — probe (EXECUTED, never REUSED — the lane's " &
    "independent contract check)"
  0

# The probe is a standalone program: the GO-critical lane runs it through
# `make test-fast-one T=tests/unit/test_evidence_id_contract_probe.nim`
# (nim c -r) and the unit-test orchestrator compiles every tests/unit/*.nim
# as its own main program. It is imported by no module, so the entry point is
# invoked unconditionally — the same shape as its sibling
# tests/unit/test_judgment_execution_records.nim. `quit(main())` keeps the
# fail-closed exit code (1 = contract check FAILED).
quit(main())
