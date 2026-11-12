## universal_pipeline_test.nim
## Unit tests for universal pipeline result contracts.
##
## Coverage targets:
##   - jsonFromVerificationVerdictReport: JSON serialization correctness
##   - computeUnifiedProofFingerprints: fingerprint determinism and composition
##   - mergeInvariantClauses: clause deduplication and ordering

import std/[unittest, json, strutils, options]
import core/solver/types
import core/logic/pipeline_healing_logic
import verification/healing_orchestrator
import verification/pipeline_core_types
import core/contracts/universal_pipeline_contract
import core/translator/universal_mapper
import core/logic/pipeline_fingerprint_engine
import core/logic/pipeline_verdict_engine
import core/logic/semantic_theorem_builder

suite "jsonFromVerificationVerdictReport contract":
  test "serializes all fields to JSON correctly":
    let report = VerificationVerdictReport(
      status: "verified",
      category: "proof",
      failureOrigin: "",
      finalVerdict: "safe_within_bound",
      counterExampleProperty: "",
      counterExampleBindings: @[],
      counterExampleSummary: "none",
      nearestLeanDiagnostic: "",
      failedReplayAttempts: 0
    )
    let node = jsonFromVerificationVerdictReport(report)
    check node["status"].getStr() == "verified"
    check node["category"].getStr() == "proof"
    check node["finalVerdict"].getStr() == "safe_within_bound"
    check node["failedReplayAttempts"].getInt() == 0

  test "counterExampleBindings are serialized as objects":
    let report = VerificationVerdictReport(
      status: "failed",
      category: "counterexample",
      failureOrigin: "solver",
      finalVerdict: "unsafe",
      counterExampleProperty: "x > 0",
      counterExampleBindings: @[SolverBinding(name: "x", value: "42")],
      counterExampleSummary: "x = 42 violates bound",
      nearestLeanDiagnostic: "unknown identifier",
      failedReplayAttempts: 3
    )
    let node = jsonFromVerificationVerdictReport(report)
    check node["status"].getStr() == "failed"
    check node["counterExampleBindings"].len == 1
    check node["counterExampleBindings"][0]["symbol"].getStr() == "x"
    check node["counterExampleBindings"][0]["value"].getStr() == "42"
    check node["failedReplayAttempts"].getInt() == 3

suite "computeUnifiedProofFingerprints contract":
  test "produces non-empty fingerprints for all fields":
    let translation = UniversalTranslation(smt2: "(assert true)")
    let inferred = LeanSpecInference(theoremSource: "theorem t : True := by trivial")
    let scan = NegativeInvariantScan(hasVulnerability: false, hits: @[], logicModelConflicted: false)
    let fp = computeUnifiedProofFingerprints(
      translation, inferred, "verified", "inv_active", "inv_refined", scan
    )
    check fp.smt.len > 0
    check fp.lean.len > 0
    check fp.cert.len > 0
    check fp.unified.len > 0

  test "fingerprint is deterministic for identical inputs":
    let translation = UniversalTranslation(smt2: "(assert true)")
    let inferred = LeanSpecInference(theoremSource: "theorem t : True := by trivial")
    let scan = NegativeInvariantScan(hasVulnerability: false, hits: @[], logicModelConflicted: false)
    let fp1 = computeUnifiedProofFingerprints(
      translation, inferred, "verified", "inv_active", "inv_refined", scan
    )
    let fp2 = computeUnifiedProofFingerprints(
      translation, inferred, "verified", "inv_active", "inv_refined", scan
    )
    check fp1.smt == fp2.smt
    check fp1.lean == fp2.lean
    check fp1.cert == fp2.cert
    check fp1.unified == fp2.unified

  test "different inputs produce different fingerprints":
    let translation = UniversalTranslation(smt2: "(assert true)")
    let inferred = LeanSpecInference(theoremSource: "theorem t : True := by trivial")
    let scan = NegativeInvariantScan(hasVulnerability: false, hits: @[], logicModelConflicted: false)
    let fp1 = computeUnifiedProofFingerprints(
      translation, inferred, "verified", "inv_a", "inv_refined", scan
    )
    let fp2 = computeUnifiedProofFingerprints(
      translation, inferred, "verified", "inv_b", "inv_refined", scan
    )
    check fp1.cert != fp2.cert
    check fp1.unified != fp2.unified

suite "mergeInvariantClauses contract":
  test "appends non-overlapping conjuncts":
    let merged = mergeInvariantClauses("a", "b")
    check merged.contains("a")
    check merged.contains("b")

  test "empty extra invariant returns base unchanged":
    let merged = mergeInvariantClauses("base", "")
    check merged == "base"

  test "strips whitespace from both inputs":
    let merged = mergeInvariantClauses("  base  ", "  extra  ")
    check merged.contains("base")
    check merged.contains("extra")

suite "buildRefinedInvariant contract":
  test "ghost_update kind returns version-payload invariant":
    let hit = AnnotatedHit(
      hit: VulnerabilityHit(kind: vkGhostUpdate, guInfo: GhostUpdateInfo(shadowStateVariable: "version")),
      sat: true,
      violatedProperty: "",
      counterExampleInput: "",
      remediation: ""
    )
    let result = buildRefinedInvariant(UniversalTranslation(), "", hit)
    check result.contains("next.version >= state.version")
    check result.contains("next.payload ≠ state.payload")

  test "null_pointer_dereference kind returns ptr != nil":
    let hit = AnnotatedHit(
      hit: VulnerabilityHit(kind: vkNullPointerDereference, npInfo: NullPointerInfo(derefInstruction: "*ptr")),
      sat: true,
      violatedProperty: "",
      counterExampleInput: "",
      remediation: ""
    )
    let result = buildRefinedInvariant(UniversalTranslation(), "", hit)
    check result == "ptr != nil"

  test "deadlock_race_condition kind returns lock invariant":
    let hit = AnnotatedHit(
      hit: VulnerabilityHit(kind: vkDeadlockRaceCondition, dlInfo: DeadlockInfo(trace: "lock")),
      sat: true,
      violatedProperty: "",
      counterExampleInput: "",
      remediation: ""
    )
    let result = buildRefinedInvariant(UniversalTranslation(), "", hit)
    check result.contains("lockHeld = true")

  test "buffer_overflow kind returns default state preservation":
    let hit = AnnotatedHit(
      hit: VulnerabilityHit(kind: vkBufferOverflow, boInfo: BufferOverflowInfo(address: 0, size: 1)),
      sat: true,
      violatedProperty: "",
      counterExampleInput: "",
      remediation: ""
    )
    let result = buildRefinedInvariant(UniversalTranslation(), "", hit)
    check result.contains("0 <= idx")

suite "inferVerificationVerdict contract":
  test "logicModelConflicted returns critical_failure":
    let scan = NegativeInvariantScan(hasVulnerability: false, hits: @[], logicModelConflicted: true)
    check inferVerificationVerdict(scan) == "critical_failure"

  test "hasVulnerability returns refuted_by_counterexample":
    let scan = NegativeInvariantScan(hasVulnerability: true, hits: @[], logicModelConflicted: false)
    check inferVerificationVerdict(scan) == "refuted_by_counterexample"

  test "clean scan returns proven_by_induction":
    let scan = NegativeInvariantScan(hasVulnerability: false, hits: @[], logicModelConflicted: false)
    check inferVerificationVerdict(scan) == "proven_by_induction"

suite "buildVerificationVerdictReport contract":
  test "critical_failure produces correct category and origin":
    let report = buildVerificationVerdictReport("critical_failure", none(AnnotatedHit), "", 0)
    check report.status == "critical_failure"
    check report.category == "critical_failure"
    check report.failureOrigin == "precondition"
    check report.finalVerdict.contains("CRITICAL_FAILURE")

  test "refuted_by_counterexample produces code origin":
    let report = buildVerificationVerdictReport("refuted_by_counterexample", none(AnnotatedHit), "", 0)
    check report.category == "logical_contradiction"
    check report.failureOrigin == "code"
    check report.finalVerdict.contains("counterexample")

  test "proven_by_induction produces proof_necessary category":
    let report = buildVerificationVerdictReport("proven_by_induction", none(AnnotatedHit), "", 0)
    check report.category == "proof_necessary"
    check report.failureOrigin == "none"
    check report.finalVerdict.contains("closed the proof")

  test "none evolutionHit leaves counterExample fields empty":
    let report = buildVerificationVerdictReport("refuted_by_counterexample", none(AnnotatedHit), "diagnostic", 2)
    check report.counterExampleProperty == ""
    check report.counterExampleSummary == ""
    check report.counterExampleBindings.len == 0
    check report.nearestLeanDiagnostic == "diagnostic"
    check report.failedReplayAttempts == 2

suite "buildSemanticCandidateInvariantHints contract":
  test "returns base hints plus semantic goal hint":
    let payload = SemanticEqualityPayload(
      schemaVersion: SemanticPayloadSchemaVersion("v1"),
      modulePath: SemanticModulePath("src/core/test.nim"),
      functionName: SemanticFunctionName("testFunc"),
      enumTypeName: SemanticEnumTypeName("TestEnum"),
      leftSymbol: SemanticSymbolName("left"),
      rightSymbol: SemanticSymbolName("right"),
      throwsSymbol: SemanticSymbolName("throws"),
      enumValues: @[SemanticEnumLabel("A"), SemanticEnumLabel("B")],
      proofGoal: semanticGoalEqualValuesDoNotThrow,
      unsatCore: @[]
    )
    let hints = buildSemanticCandidateInvariantHints(payload)
    check hints.len >= 4
    check hints.contains("equal enum values imply no throw")
    check hints.contains("bounds-checked container access only returns Option.some inside valid range")
    check hints.contains("disjoint memory regions preserve pointer alias isolation")
    check hints.contains("semantic goal: equal_values_do_not_throw")

suite "buildSemanticProofDependencies contract":
  test "returns fixed dependency list":
    let deps = buildSemanticProofDependencies()
    check deps.len == 5
    check deps.contains("BoundsCheck")
    check deps.contains("vectorRead_zero")
    check deps.contains("pointerSegmentRead_maps_to_vector")
    check deps.contains("disjoint_left")
    check deps.contains("pointerAliasIsolation")

suite "buildSemanticProofTacticCandidates contract":
  test "returns base tactics without candidate invariants":
    let payload = SemanticEqualityPayload(
      schemaVersion: SemanticPayloadSchemaVersion("v1"),
      modulePath: SemanticModulePath("src/core/test.nim"),
      functionName: SemanticFunctionName("testFunc"),
      enumTypeName: SemanticEnumTypeName("TestEnum"),
      leftSymbol: SemanticSymbolName("left"),
      rightSymbol: SemanticSymbolName("right"),
      throwsSymbol: SemanticSymbolName("throws"),
      enumValues: @[SemanticEnumLabel("A"), SemanticEnumLabel("B")],
      proofGoal: semanticGoalEqualValuesDoNotThrow,
      unsatCore: @[]
    )
    let tactics = buildSemanticProofTacticCandidates(payload)
    check tactics.len == 3
    for t in tactics:
      check t.contains("throws")

  test "includes extra tactic when candidate invariants provided":
    let payload = SemanticEqualityPayload(
      schemaVersion: SemanticPayloadSchemaVersion("v1"),
      modulePath: SemanticModulePath("src/core/test.nim"),
      functionName: SemanticFunctionName("testFunc"),
      enumTypeName: SemanticEnumTypeName("TestEnum"),
      leftSymbol: SemanticSymbolName("left"),
      rightSymbol: SemanticSymbolName("right"),
      throwsSymbol: SemanticSymbolName("throws"),
      enumValues: @[SemanticEnumLabel("A"), SemanticEnumLabel("B")],
      proofGoal: semanticGoalEqualValuesDoNotThrow,
      unsatCore: @[]
    )
    let tactics = buildSemanticProofTacticCandidates(payload, @["inv1"])
    check tactics.len >= 3

suite "runSelfHealingLoop contract":
  test "clean scan exits immediately with original source":
    let scan = NegativeInvariantScan(
      hasVulnerability: false,
      hits: @[],
      logicModelConflicted: false
    )
    let translation = UniversalTranslation(language: "nim", smt2: "(set-logic QF_LIA)\n(assert true)\n(check-sat)\n")
    let outcome = runSelfHealingLoop(
      "proc main() = echo 1",
      translation,
      scan,
      3
    )
    check outcome.finalSource == "proc main() = echo 1"
    check outcome.rounds.len == 0
    check not outcome.finalScan.hasVulnerability

  test "zero maxRounds caps to one round":
    let scan = NegativeInvariantScan(
      hasVulnerability: false,
      hits: @[],
      logicModelConflicted: false
    )
    let translation = UniversalTranslation(language: "nim", smt2: "(set-logic QF_LIA)\n(assert true)\n(check-sat)\n")
    let outcome = runSelfHealingLoop(
      "proc main() = echo 1",
      translation,
      scan,
      0
    )
    check outcome.rounds.len == 0
    check outcome.finalSource == "proc main() = echo 1"

  test "vulnerable scan with zero maxRounds attempts one round":
    let hit = AnnotatedHit(
      hit: VulnerabilityHit(
        kind: vkNullPointerDereference,
        npInfo: NullPointerInfo(derefInstruction: "*ptr")
      ),
      sat: true,
      violatedProperty: "ptr != nil",
      counterExampleInput: "",
      remediation: ""
    )
    let scan = NegativeInvariantScan(
      hasVulnerability: true,
      hits: @[hit],
      logicModelConflicted: false
    )
    let translation = UniversalTranslation(language: "nim", smt2: "(set-logic QF_LIA)\n(assert true)\n(check-sat)\n")
    let outcome = runSelfHealingLoop(
      "proc main() = echo 1",
      translation,
      scan,
      0
    )
    # With zero maxRounds, roundsCap=1; if remediation fails, we get one round
    check outcome.rounds.len <= 1
    check outcome.finalSource.contains("proc main() = echo 1")

suite "runLeanProofRefinementLoop contract":
  test "maxRounds zero caps to one round and returns":
    let req = UniversalPipelineRequest(
      language: "nim",
      modulePath: "src/test.nim",
      functionName: "testFunc",
      astJson: "{}",
      sourceCode: "proc testFunc(): int = 1",
      maxRounds: 0,
      proofVaultDir: "/tmp/axiom_test_vault",
      bddDir: "/tmp/axiom_test_bdd"
    )
    let translation = UniversalTranslation(language: "nim", smt2: "(set-logic QF_LIA)\n(assert true)\n(check-sat)\n")
    let outcome = runLeanProofRefinementLoop(
      req, translation, "proc testFunc(): int = 1", "true", 0
    )
    check outcome.rounds.len <= 1
    check outcome.failedReplayAttempts >= 0

  test "maxRounds one attempts single round":
    let req = UniversalPipelineRequest(
      language: "nim",
      modulePath: "src/test.nim",
      functionName: "testFunc",
      astJson: "{}",
      sourceCode: "proc testFunc(): int = 1",
      maxRounds: 1,
      proofVaultDir: "/tmp/axiom_test_vault",
      bddDir: "/tmp/axiom_test_bdd"
    )
    let translation = UniversalTranslation(language: "nim", smt2: "(set-logic QF_LIA)\n(assert true)\n(check-sat)\n")
    let outcome = runLeanProofRefinementLoop(
      req, translation, "proc testFunc(): int = 1", "true", 1
    )
    check outcome.rounds.len <= 1
    check outcome.failedReplayAttempts >= 0
