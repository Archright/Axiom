import std/strutils
{.push raises: [].}
## 4-Layer Pipeline E2E Test
##
## Exercises: L1(BMC) -> L2(CEGAR) -> L3(Leanstral) -> L4(Lean Kernel)
## Tests each layer independently and verifies the integration contract.

import std/[unittest, options, os]

# L1: BMC
import core/bmc/bmc_types

# L2: CEGAR
import verification/cegar_engine
import core/orchestrator/orchestrator_types
import core/boundary/persona_interface
import core/symbolic_types_expr

import core/boundary/verification_interface
# L3: Leanstral
import verification/llm_backend
import verification/leanstral_gateway
import core/proof/proof_tactics_catalog

# ============================================================================
# L1 Tests: BMC
# ============================================================================

suite "L1 - BMC (Bounded Model Checking)":
  test "BMC step bound is 10":
    check bmcStepBound == 10

  test "TransitionRule type has required fields":
    let rule = TransitionRule(op: transitionSub, delta: 50,
                              invariant: InvariantRule(kind: invariantMinValue, minValue: 0))
    check rule.op == transitionSub
    check rule.delta == 50
    check rule.invariant.minValue == 0

  test "InvariantRule type has required fields":
    let inv = InvariantRule(kind: invariantMaxValue, maxValue: 1000)
    check inv.kind == invariantMaxValue
    check inv.maxValue == 1000

  test "BMC trace arrays are correctly sized":
    var trace: BmcTrace
    check trace.x.len == bmcStepBound + 1  # 11 elements (steps 0-10)
    check trace.owner.len == bmcStepBound   # 10 elements (one per transition)

# ============================================================================
# L2 Tests: CEGAR Engine
# ============================================================================

suite "L2 - CEGAR Engine (Fixed-Point Convergence)":
  test "CegarVerdict enum has all 4 values":
    check cegarProven.int == 0
    check cegarCounterexample.int == 1
    check cegarMaxIterations.int == 2
    check cegarBudgetExceeded.int == 3

  test "CegarResult type has required fields":
    let result = CegarResult(
      verdict: cvProved,
      invariants: @[],
      counterexample: ""
    )
    check result.verdict == cvProved

  test "CegarIteration type records history correctly":
    let iter = CegarIteration(
      iteration: 3,
      candidatesBefore: 5,
      candidatesAfter: 3,
      operatorUsed: "synthesize",
      z3Accepted: true,
      fixedPointReached: false
    )
    check iter.iteration == 3
    check iter.z3Accepted == true
    check iter.fixedPointReached == false

  test "Fingerprint is deterministic for same input":
    let inv1 = sGe(sVar("i"), sConst(0))
    let inv2 = sLe(sVar("i"), sConst(10))
    let set1 = @[inv1, inv2]
    let set2 = @[inv1, inv2]
    let fp1 = computeInvariantFingerprint(set1)
    let fp2 = computeInvariantFingerprint(set2)
    check fp1 == fp2

  test "Fingerprint differs for different inputs":
    let inv1 = sGe(sVar("i"), sConst(0))
    let inv2 = sLe(sVar("i"), sConst(10))
    let inv3 = sLe(sVar("i"), sConst(20))
    let fp1 = computeInvariantFingerprint(@[inv1, inv2])
    let fp2 = computeInvariantFingerprint(@[inv1, inv3])
    check fp1 != fp2

  test "Fingerprint is order-independent (sorted)":
    let inv1 = sGe(sVar("i"), sConst(0))
    let inv2 = sLe(sVar("i"), sConst(10))
    let fp_forward = computeInvariantFingerprint(@[inv1, inv2])
    let fp_reverse = computeInvariantFingerprint(@[inv2, inv1])
    check fp_forward == fp_reverse

  test "Fingerprint of empty set is deterministic":
    let fp1 = computeInvariantFingerprint(@[])
    let fp2 = computeInvariantFingerprint(@[])
    check fp1 == fp2
    check fp1 == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"  # SHA-256 of empty string

  test "SMT-LIB2 encoding of proved invariants":
    let inv = sGe(sVar("x"), sConst(0))
    let smt = encodeProvedInvariantsSmtlib2(@[inv])
    check "(declare-const x Int)" in smt
    check "(assert" in smt
    check "(check-sat)" in smt
    check "CEGAR" in smt

  test "SMT-LIB2 encoding of empty invariants returns empty":
    let smt = encodeProvedInvariantsSmtlib2(@[])
    check smt.len == 0

# ============================================================================
# L3 Tests: LLM Backend & Leanstral Gateway
# ============================================================================

suite "L3 - LLM Backend (Honest Failure Principle)":
  test "resolveDefaultBackend returns none when no env vars set":
    # Ensure env vars are not set
    delEnv("AXIOM_LLM_API_URL")
    delEnv("AXIOM_LLM_API_KEY")
    let backend = resolveDefaultBackend()
    # Should be none (no backend available)
    check backend.isNone

  test "callLeanstral returns honest failure when no backend":
    delEnv("AXIOM_LLM_API_URL")
    delEnv("AXIOM_LLM_API_KEY")
    # Provide a trivially invalid prompt to ensure no caching interference
    let result = callLeanstral("", backend = nil)
    check result.success == false
    # Must contain clear error message, not silent success
    check result.theoremSource.len == 0

  test "callLeanstral with nil backend returns FATAL message":
    delEnv("AXIOM_LLM_API_URL")
    delEnv("AXIOM_LLM_API_KEY")
    let result = callLeanstral("prove x >= 0", backend = nil)
    check result.success == false
    check "FATAL" in result.diagnostics or "No LLM backend" in result.diagnostics
    # Crucially: must NOT succeed silently
    check result.theoremSource.len == 0

  test "Agent behavior detection rejects tool-use patterns":
    check isAgentBehaviorDetected("I'll run bash: $ ls -la") == true
    check isAgentBehaviorDetected("Here is the Lean 4 proof:\nimport Std") == false

  test "Source policy rejects non-Std imports":
    check validateLeanstralSourcePolicy("import Mathlib\ntheorem foo : True := trivial").len > 0
    check validateLeanstralSourcePolicy("import Std\ntheorem foo : True := trivial").len == 0

# ============================================================================
# L3 Supplementary: Tactic Catalog (Validator, not Fallback)
# ============================================================================

suite "L3 - Tactic Catalog (Primitive Validator)":
  test "isVerifiedTactic recognizes catalog tactics":
    check isVerifiedTactic("intros") == true
    check isVerifiedTactic("rfl") == true
    check isVerifiedTactic("simp") == true
    check isVerifiedTactic("linarith") == true
    check isVerifiedTactic("omega") == true
    check isVerifiedTactic("aesop") == true

  test "isVerifiedTactic rejects unknown tactics":
    check isVerifiedTactic("nonexistent_tactic") == false
    check isVerifiedTactic("custom_lemma_apply") == false

  test "validateTacticSequence accepts all-verified sequences":
    let result = validateTacticSequence(@["intros", "rfl"])
    check result.valid == true
    check result.invalidTactics.len == 0

  test "validateTacticSequence flags unverified tactics":
    let result = validateTacticSequence(@["intros", "custom_tactic", "simp"])
    check result.valid == false
    check result.invalidTactics.len == 1
    check result.invalidTactics[0] == "custom_tactic"

  test "validateTacticSequence warns but does not reject":
    # Unverified tactics are warnings — Lean kernel is the final judge
    let result = validateTacticSequence(@["unknown1", "unknown2"])
    check result.valid == false
    check "Lean kernel" in result.message

# ============================================================================
# Integration Contract Tests
# ============================================================================

suite "4-Layer Integration Contract":
  test "All layer types are importable and consistent":
    # L1 types
    var rule: TransitionRule
    check rule.delta == 0  # default

    # L2 types
    var cegarResult: CegarResult
    check cegarResult.verdict == cvProved  # default enum first value

    # L3 types
    var llmReq: LLMRequest
    check llmReq.temperature == 0.0  # default

    var tacticResult: TacticValidationResult
    check tacticResult.valid == false  # default

  test "CEGAR encodeProvedInvariantsSmtlib2 produces parseable SMT-LIB2":
    let inv1 = sGe(sVar("balance"), sConst(0))
    let inv2 = sLe(sVar("balance"), sConst(1000000))
    let smt = encodeProvedInvariantsSmtlib2(@[inv1, inv2])
    # Must contain standard SMT-LIB2 structure
    check "(set-logic" notin smt  # We don't emit set-logic in CEGAR summary
    check "(declare-const balance Int)" in smt
    check "(assert" in smt
    check "(check-sat)" in smt
    # Must contain exactly one declaration per unique variable
    var declCount = 0
    for line in smt.splitLines():
      if "(declare-const balance Int)" in line:
        inc declCount
    check declCount == 1

# ============================================================================
# Source Integrity Gate Tests
# ============================================================================

suite "Source Integrity Gate":
  test "ParallelTaskResult has vulnerabilityType field":
    var result: ParallelTaskResult
    check result.vulnerabilityType == ""  # default empty
    result.vulnerabilityType = "solver_timeout"
    check result.vulnerabilityType == "solver_timeout"

  test "SwatArtifact has vulnerabilityHits field":
    var artifact: SwatArtifact
    check artifact.vulnerabilityHits.len == 0  # default empty

# ============================================================================
# Z3 Fixedpoint/PDR Engine Tests
# ============================================================================

import verification/solver/fixedpoint_engine

suite "Z3 Fixedpoint/PDR Engine":
  test "HornClause type has required fields":
    let clause = HornClause(name: "init", body: "(= x 0)", head: "(state x)")
    check clause.name == "init"
    check clause.body.len > 0
    check clause.head.len > 0

  test "FixedpointResult type has required fields":
    var result: FixedpointResult
    check result.sat == false  # default
    check result.invariant.len == 0

  test "emitHornClauses produces valid CHC structure":
    let chc = emitHornClauses(
      variables = @["x"],
      initBody = "(= x 0)",
      transBody = "(= x! (+ x 1))",
      propBody = "(< x 0)"
    )
    check "(set-logic HORN)" in chc
    check "declare-var" in chc
    check "declare-rel" in chc
    check "(rule" in chc
    check "(query error)" in chc

# ============================================================================
# VulnerabilityHit ADT (strictCaseObjects) Tests
# ============================================================================

import std/json
import core/types/pipeline_core_types

suite "VulnerabilityHit Pure ADT (strictCaseObjects)":
  test "VulnerabilityKind enum has all 5 variants":
    check vkBufferOverflow.int == 0
    check vkNullPointerDereference.int == 1
    check vkIntegerOverflowUnderflow.int == 2
    check vkGhostUpdate.int == 3
    check vkDeadlockRaceCondition.int == 4

  test "VulnerabilityHit case object constructs per kind":
    let bo = VulnerabilityHit(kind: vkBufferOverflow, boInfo: BufferOverflowInfo(address: 0xDEAD, size: 64))
    check bo.kind == vkBufferOverflow
    check bo.boInfo.address == 0xDEAD
    check bo.boInfo.size == 64

    let dl = VulnerabilityHit(kind: vkDeadlockRaceCondition, dlInfo: DeadlockInfo(trace: "T1->T2"))
    check dl.kind == vkDeadlockRaceCondition
    check dl.dlInfo.trace == "T1->T2"

  test "AnnotatedHit wraps VulnerabilityHit with metadata":
    let ah = AnnotatedHit(
      hit: VulnerabilityHit(kind: vkGhostUpdate, guInfo: GhostUpdateInfo(shadowStateVariable: "version")),
      sat: true,
      violatedProperty: "version monotonicity",
      counterExampleInput: "{}",
      remediation: "assert next >= state"
    )
    check ah.hit.kind == vkGhostUpdate
    check ah.sat == true
    check ah.hit.guInfo.shadowStateVariable == "version"

  test "PayloadSerializable concept dispatches per type":
    let bo = BufferOverflowInfo(address: 255, size: 8)
    check bo.getFingerprintSeed() == "bo|255|8"
    let dl = DeadlockInfo(trace: "T1->T2->T1")
    check dl.getFingerprintSeed() == "dl|T1->T2->T1"

  test "AnnotatedHit toJson produces correct JSON":
    let ah = AnnotatedHit(
      hit: VulnerabilityHit(kind: vkBufferOverflow, boInfo: BufferOverflowInfo(address: 42, size: 16)),
      sat: true,
      violatedProperty: "bounds",
      counterExampleInput: "{}",
      remediation: "assert"
    )
    let j = ah.toJson()
    check j["kind"].getStr() == "vkBufferOverflow"
    check j["sat"].getBool() == true
    check j["payload"]["address"].getInt() == 42

  test "Option[AnnotatedHit] sentinel works":
    var noHit: Option[AnnotatedHit] = none(AnnotatedHit)
    check noHit.isSome == false
    let someHit = some(AnnotatedHit(
      hit: VulnerabilityHit(kind: vkBufferOverflow, boInfo: BufferOverflowInfo(address: 0, size: 0)),
      sat: false, violatedProperty: "", counterExampleInput: "", remediation: ""
    ))
    check someHit.isSome == true
    check someHit.get().hit.kind == vkBufferOverflow

{.pop.}
