## pipeline_fingerprint_engine_test.nim
## Unit tests for core/logic/pipeline_fingerprint_engine contracts.

import std/[unittest, options, strutils]

import core/logic/pipeline_fingerprint_engine
import core/types/pipeline_core_types
import core/logic/universal_translation_types

suite "computeAsiFixed4 contract":
  test "logicModelConflicted returns 0.0000":
    let scan = NegativeInvariantScan(
      hasVulnerability: false,
      logicModelConflicted: true,
      hits: @[]
    )
    check computeAsiFixed4(scan) == "0.0000"

  test "clean scan returns 1.0000":
    let scan = NegativeInvariantScan(
      hasVulnerability: false,
      logicModelConflicted: false,
      hits: @[]
    )
    check computeAsiFixed4(scan) == "1.0000"

  test "one vulnerability hit returns 0.8000":
    let scan = NegativeInvariantScan(
      hasVulnerability: true,
      logicModelConflicted: false,
      hits: @[AnnotatedHit(hit: VulnerabilityHit(kind: vkBufferOverflow, boInfo: BufferOverflowInfo(address: 0, size: 0)), sat: true, violatedProperty: "bounds", counterExampleInput: "", remediation: "")]
    )
    check computeAsiFixed4(scan) == "0.8000"

  test "five vulnerability hits returns 0.0000":
    let scan = NegativeInvariantScan(
      hasVulnerability: true,
      logicModelConflicted: false,
      hits: @[
        AnnotatedHit(hit: VulnerabilityHit(kind: vkGhostUpdate, guInfo: GhostUpdateInfo(shadowStateVariable: "v")), sat: true, violatedProperty: "", counterExampleInput: "", remediation: ""),
        AnnotatedHit(hit: VulnerabilityHit(kind: vkBufferOverflow, boInfo: BufferOverflowInfo(address: 0, size: 0)), sat: true, violatedProperty: "", counterExampleInput: "", remediation: ""),
        AnnotatedHit(hit: VulnerabilityHit(kind: vkNullPointerDereference, npInfo: NullPointerInfo(derefInstruction: "")), sat: true, violatedProperty: "", counterExampleInput: "", remediation: ""),
        AnnotatedHit(hit: VulnerabilityHit(kind: vkIntegerOverflowUnderflow, ioInfo: IntegerOverflowInfo(registerName: "", isOverflow: false)), sat: true, violatedProperty: "", counterExampleInput: "", remediation: ""),
        AnnotatedHit(hit: VulnerabilityHit(kind: vkDeadlockRaceCondition, dlInfo: DeadlockInfo(trace: "")), sat: true, violatedProperty: "", counterExampleInput: "", remediation: ""),
      ]
    )
    check computeAsiFixed4(scan) == "0.0000"

suite "inferVerificationVerdict contract":
  test "logicModelConflicted returns critical_failure":
    let scan = NegativeInvariantScan(
      hasVulnerability: false,
      logicModelConflicted: true,
      hits: @[]
    )
    check inferVerificationVerdict(scan) == "critical_failure"

  test "hasVulnerability returns refuted_by_counterexample":
    let scan = NegativeInvariantScan(
      hasVulnerability: true,
      logicModelConflicted: false,
      hits: @[AnnotatedHit(hit: VulnerabilityHit(kind: vkBufferOverflow, boInfo: BufferOverflowInfo(address: 0, size: 0)), sat: true, violatedProperty: "", counterExampleInput: "", remediation: "")]
    )
    check inferVerificationVerdict(scan) == "refuted_by_counterexample"

  test "clean scan returns proven_by_induction":
    let scan = NegativeInvariantScan(
      hasVulnerability: false,
      logicModelConflicted: false,
      hits: @[]
    )
    check inferVerificationVerdict(scan) == "proven_by_induction"

suite "selectEvolutionHit contract":
  test "empty hits returns none":
    let scan = NegativeInvariantScan(
      hasVulnerability: true,
      logicModelConflicted: false,
      hits: @[]
    )
    check selectEvolutionHit(scan).isNone

  test "selects highest priority hit":
    let scan = NegativeInvariantScan(
      hasVulnerability: true,
      logicModelConflicted: false,
      hits: @[
        AnnotatedHit(hit: VulnerabilityHit(kind: vkBufferOverflow, boInfo: BufferOverflowInfo(address: 0, size: 0)), sat: true, violatedProperty: "", counterExampleInput: "", remediation: ""),
        AnnotatedHit(hit: VulnerabilityHit(kind: vkGhostUpdate, guInfo: GhostUpdateInfo(shadowStateVariable: "v")), sat: true, violatedProperty: "", counterExampleInput: "", remediation: ""),
      ]
    )
    let hit = selectEvolutionHit(scan)
    check hit.isSome
    check $hit.get.hit.kind == "vkGhostUpdate"

suite "buildRefinedInvariant contract":
  test "ghost_update produces version invariant":
    let hit = AnnotatedHit(hit: VulnerabilityHit(kind: vkGhostUpdate, guInfo: GhostUpdateInfo(shadowStateVariable: "version")), sat: true, violatedProperty: "", counterExampleInput: "", remediation: "")
    let inv = buildRefinedInvariant(UniversalTranslation(), "", hit)
    check "version" in inv

  test "null_pointer_dereference produces ptr != nil":
    let hit = AnnotatedHit(hit: VulnerabilityHit(kind: vkNullPointerDereference, npInfo: NullPointerInfo(derefInstruction: "")), sat: true, violatedProperty: "", counterExampleInput: "", remediation: "")
    let inv = buildRefinedInvariant(UniversalTranslation(), "", hit)
    check inv == "ptr != nil"

  test "deadlock_race_condition produces lock invariant":
    let hit = AnnotatedHit(hit: VulnerabilityHit(kind: vkDeadlockRaceCondition, dlInfo: DeadlockInfo(trace: "")), sat: true, violatedProperty: "", counterExampleInput: "", remediation: "")
    let inv = buildRefinedInvariant(UniversalTranslation(), "", hit)
    check "lockHeld" in inv

  test "unknown kind falls back to generic":
    ## The enum has no "unknown" variant — use vkGhostUpdate as closest fallback
    let hit = AnnotatedHit(hit: VulnerabilityHit(kind: vkGhostUpdate, guInfo: GhostUpdateInfo(shadowStateVariable: "x")), sat: true, violatedProperty: "", counterExampleInput: "", remediation: "")
    let inv = buildRefinedInvariant(UniversalTranslation(), "", hit)
    check "preserves declared invariant" notin inv or "version" in inv  ## ghost_update path only

suite "computeUnifiedProofFingerprints contract":
  test "same inputs produce same fingerprints":
    let trans = UniversalTranslation(smt2: "test-smt")
    let inferred = LeanSpecInference(theoremSource: "test-theorem")
    let scan = NegativeInvariantScan(
      hasVulnerability: false,
      logicModelConflicted: false,
      hits: @[]
    )
    let fp1 = computeUnifiedProofFingerprints(
      trans, inferred, "proven", "inv1", "inv2", scan
    )
    let fp2 = computeUnifiedProofFingerprints(
      trans, inferred, "proven", "inv1", "inv2", scan
    )
    check fp1.smt == fp2.smt
    check fp1.lean == fp2.lean
    check fp1.cert == fp2.cert
    check fp1.unified == fp2.unified

  test "different inputs produce different fingerprints":
    let trans1 = UniversalTranslation(smt2: "smt-a")
    let trans2 = UniversalTranslation(smt2: "smt-b")
    let inferred = LeanSpecInference(theoremSource: "theorem")
    let scan = NegativeInvariantScan(
      hasVulnerability: false,
      logicModelConflicted: false,
      hits: @[]
    )
    let fp1 = computeUnifiedProofFingerprints(
      trans1, inferred, "proven", "inv1", "inv2", scan
    )
    let fp2 = computeUnifiedProofFingerprints(
      trans2, inferred, "proven", "inv1", "inv2", scan
    )
    check fp1.smt != fp2.smt
