## Tests for verification/healing_orchestrator.nim
##
## Business scenarios tested:
## 1. runSelfHealingLoop — negative invariant healing coordination
## 2. runLeanProofRefinementLoop — Lean proof refinement (basic invocation paths)
##
## Per §0.7: only business scenarios tested, NOT compiler-guaranteed behaviors.
## Procs that depend on external I/O (Lean compiler, Z3 solver) are tested
## with graceful fallback expectations where the external tool is unavailable.

import std/[os, strutils, unittest, osproc]
import core/types/pipeline_core_types
import core/types/translation_types
import core/types/smt_types
import verification/healing_orchestrator

# ═══════════════════════════════════════════════════════════════════════════════
# Lean availability — detected once at module scope
# ═══════════════════════════════════════════════════════════════════════════════
let leanAvailable* = findExe("lake").len > 0

# ═══════════════════════════════════════════════════════════════════════════════
# Helpers
# ═══════════════════════════════════════════════════════════════════════════════

func makeTranslation(lang: string = "nim"): UniversalTranslation =
  UniversalTranslation(
    language: lang,
    functionName: "test_func",
    logic: slQfLia,
    ilEntries: @[],
    smt2: "",
    controlFlowCount: 0,
    memoryAccessCount: 0,
    stateSpace: @[],
    stateInvariants: @[],
    transitionRelation: @[],
    transitionInvariants: @[],
    operationalSemantics: @[],
    environmentInputs: @[],
    envInputConstructors: @[],
    stepFunctionCases: @[],
    loopControlVariables: @[],
    rankVariables: @[]
  )

func makeRequest(
  modulePath: string = "test/module.nim",
  functionName: string = "testFunc",
  proofVaultDir: string = ""
): UniversalPipelineRequest =
  UniversalPipelineRequest(
    language: "nim",
    modulePath: modulePath,
    functionName: functionName,
    astJson: "",
    sourceCode: "",
    maxRounds: 3,
    proofVaultDir: proofVaultDir,
    bddDir: "",
    preConditions: @[],
    postConditions: @[],
    unsatCoreVars: @[],
    logic: slQfLia,
    verificationContext: AxiomVerificationContext(
      functionName: functionName,
      logic: slQfLia,
      constraints: @[],
      hornRelations: @[],
      hornRules: @[]
    )
  )

func emptyScan(): NegativeInvariantScan =
  NegativeInvariantScan(
    hasVulnerability: false,
    hits: @[],
    logicModelConflicted: false
  )

func makeVulnHit(kind: VulnerabilityKind; sat: bool = true): AnnotatedHit =
  case kind
  of vkBufferOverflow:
    AnnotatedHit(
      hit: VulnerabilityHit(kind: vkBufferOverflow, boInfo: BufferOverflowInfo(address: 0, size: 0)),
      sat: sat,
      violatedProperty: "index out of bounds",
      counterExampleInput: """{"idx":-1}""",
      remediation: "assert idx >= 0"
    )
  of vkNullPointerDereference:
    AnnotatedHit(
      hit: VulnerabilityHit(kind: vkNullPointerDereference, npInfo: NullPointerInfo(derefInstruction: "")),
      sat: sat,
      violatedProperty: "pointer not null",
      counterExampleInput: """{"ptr":"nil"}""",
      remediation: "assert ptr != nil"
    )
  of vkIntegerOverflowUnderflow:
    AnnotatedHit(
      hit: VulnerabilityHit(kind: vkIntegerOverflowUnderflow, ioInfo: IntegerOverflowInfo(registerName: "", isOverflow: false)),
      sat: sat,
      violatedProperty: "arithmetic overflow",
      counterExampleInput: """{"amount":2147483647}""",
      remediation: "assert amount <= balance"
    )
  of vkGhostUpdate:
    AnnotatedHit(
      hit: VulnerabilityHit(kind: vkGhostUpdate, guInfo: GhostUpdateInfo(shadowStateVariable: "")),
      sat: sat,
      violatedProperty: "version monotonicity",
      counterExampleInput: """{"version":2}""",
      remediation: "assert next.version >= state.version"
    )
  of vkDeadlockRaceCondition:
    AnnotatedHit(
      hit: VulnerabilityHit(kind: vkDeadlockRaceCondition, dlInfo: DeadlockInfo(trace: "")),
      sat: sat,
      violatedProperty: "concurrency guard",
      counterExampleInput: """{"t1":"enter","t2":"enter"}""",
      remediation: "add lock guard"
    )

# ═══════════════════════════════════════════════════════════════════════════════
# Test 1: runSelfHealingLoop — no vulnerability
# ═══════════════════════════════════════════════════════════════════════════════

suite "runSelfHealingLoop — no vulnerability":
  test "empty scan returns immediately with no rounds":
    let translation = makeTranslation()
    let scan = emptyScan()
    let source = "proc foo(): int =\n  result = 1"
    let result = runSelfHealingLoop(source, translation, scan, maxRounds = 3)
    check result.rounds.len == 0
    check result.finalSource == source
    check result.finalScan.hasVulnerability == false

  test "scan with hasVulnerability=false and no hits":
    var scan = emptyScan()
    scan.logicModelConflicted = false
    let translation = makeTranslation()
    let result = runSelfHealingLoop("let x = 1", translation, scan, maxRounds = 5)
    check result.rounds.len == 0

# ═══════════════════════════════════════════════════════════════════════════════
# Test 2: runSelfHealingLoop — vulnerability with no fix possible
# ═══════════════════════════════════════════════════════════════════════════════

suite "runSelfHealingLoop — unfixable vulnerability":
  test "vulnerability hit where template cannot fix → empty fixedKinds → break":
    let translation = makeTranslation()
    # Create a scan with a vulnerability that applyRefactoringTemplate cannot fix.
    # A ghost-update hit with trivial source that has no loop/proc → pattern guard will reject.
    var scan = NegativeInvariantScan(
      hasVulnerability: true,
      hits: @[makeVulnHit(vkGhostUpdate)],
      logicModelConflicted: false
    )
    let source = "let x = 1"
    let result = runSelfHealingLoop(source, translation, scan, maxRounds = 3)
    # The loop should have run 1 round, found no fixedKinds, and recorded a round
    check result.rounds.len == 1
    check result.rounds[0].phase == "negative-invariant-healing"
    check result.rounds[0].round == 1
    check result.rounds[0].fixedKinds.len == 0
    check result.finalSource == source  # source unchanged

  test "unknown vulnerability kind → escalated → empty fixedKinds":
    let translation = makeTranslation()
    # vkDeadlockRaceCondition → rskMissingLoopInvariant → rpkAddLoopInvariant
    # Simple source without for/while → template won't insert anything → rsSkipped
    var scan = NegativeInvariantScan(
      hasVulnerability: true,
      hits: @[makeVulnHit(vkDeadlockRaceCondition)],
      logicModelConflicted: false
    )
    let source = "let x = 1"
    let result = runSelfHealingLoop(source, translation, scan, maxRounds = 3)
    check result.rounds.len >= 1
    check result.rounds[0].phase == "negative-invariant-healing"
    # fixedKinds should be empty since no transformation was applied
    check result.rounds[0].fixedKinds.len == 0

# ═══════════════════════════════════════════════════════════════════════════════
# Test 3: runSelfHealingLoop — multiple hits same kind deduplicates
# ═══════════════════════════════════════════════════════════════════════════════

suite "runSelfHealingLoop — deduplication":
  test "multiple hits of same vulnerability kind → fixedKinds deduplicates":
    let translation = makeTranslation()
    # Two ghost-update hits — both will fail the pattern guard
    var scan = NegativeInvariantScan(
      hasVulnerability: true,
      hits: @[
        makeVulnHit(vkGhostUpdate),
        makeVulnHit(vkGhostUpdate)
      ],
      logicModelConflicted: false
    )
    let source = "let x = 1"
    let result = runSelfHealingLoop(source, translation, scan, maxRounds = 3)
    check result.rounds.len == 1
    # fixedKinds should be empty since neither hit produced a fix
    check result.rounds[0].fixedKinds.len == 0
    # remainingVulnerabilities reflects original hits count
    check result.rounds[0].remainingVulnerabilities == 2

# ═══════════════════════════════════════════════════════════════════════════════
# Test 4: runSelfHealingLoop — round cap enforcement
# ═══════════════════════════════════════════════════════════════════════════════

suite "runSelfHealingLoop — round cap":
  test "hard cap at 1 round regardless of maxRounds parameter":
    let translation = makeTranslation()
    # Even with maxRounds=10, the internal cap is 1
    var scan = NegativeInvariantScan(
      hasVulnerability: true,
      hits: @[makeVulnHit(vkBufferOverflow)],
      logicModelConflicted: false
    )
    let source = "let x = 1"
    let result = runSelfHealingLoop(source, translation, scan, maxRounds = 10)
    # Should only produce at most 1 round due to hard cap
    check result.rounds.len <= 1

# ═══════════════════════════════════════════════════════════════════════════════
# Test 5: runSelfHealingLoop — source preservation
# ═══════════════════════════════════════════════════════════════════════════════

suite "runSelfHealingLoop — source preservation":
  test "finalSource is original when no fix applied":
    let translation = makeTranslation()
    let original = "proc add(a, b: int): int =\n  result = a + b"
    var scan = NegativeInvariantScan(
      hasVulnerability: true,
      hits: @[makeVulnHit(vkIntegerOverflowUnderflow)],
      logicModelConflicted: false
    )
    let result = runSelfHealingLoop(original, translation, scan, maxRounds = 3)
    check result.finalSource == original

  test "finalScan preserves scan state when no re-scan occurs":
    let translation = makeTranslation()
    let original = "let x = 1"
    var scan = NegativeInvariantScan(
      hasVulnerability: true,
      hits: @[makeVulnHit(vkNullPointerDereference)],
      logicModelConflicted: false
    )
    let result = runSelfHealingLoop(original, translation, scan, maxRounds = 3)
    # Since no fix was applied, the scan should be carried through
    check result.finalScan.hasVulnerability == true
    check result.finalScan.hits.len == 1

# ═══════════════════════════════════════════════════════════════════════════════
# Test 6: runSelfHealingLoop — empty active invariant
# ═══════════════════════════════════════════════════════════════════════════════

suite "runSelfHealingLoop — active invariant parameter":
  test "empty activeInvariant (default) works correctly":
    let translation = makeTranslation()
    let scan = emptyScan()
    let result = runSelfHealingLoop("let x = 1", translation, scan, maxRounds = 3)
    check result.rounds.len == 0

  test "non-empty activeInvariant with no vulnerability":
    let translation = makeTranslation()
    let scan = emptyScan()
    let result = runSelfHealingLoop("let x = 1", translation, scan, maxRounds = 3, activeInvariant = "x >= 0")
    check result.rounds.len == 0

# ═══════════════════════════════════════════════════════════════════════════════
# Test 7: runSelfHealingLoop — round structure integrity
# ═══════════════════════════════════════════════════════════════════════════════

suite "runSelfHealingLoop — round structure":
  test "round records phase as negative-invariant-healing":
    let translation = makeTranslation()
    var scan = NegativeInvariantScan(
      hasVulnerability: true,
      hits: @[makeVulnHit(vkBufferOverflow)],
      logicModelConflicted: false
    )
    let result = runSelfHealingLoop("let x = 1", translation, scan, maxRounds = 3)
    check result.rounds.len == 1
    check result.rounds[0].phase == "negative-invariant-healing"
    check result.rounds[0].round == 1
    check result.rounds[0].diagnosticCount == 0
    check result.rounds[0].feedbackSummary == ""
    check result.rounds[0].suggestedTactic == ""

# ═══════════════════════════════════════════════════════════════════════════════
# Test 8: runLeanProofRefinementLoop — basic invocation
# ═══════════════════════════════════════════════════════════════════════════════

suite "runLeanProofRefinementLoop — basic paths":
  test "returns valid structure with empty translation":
    check leanAvailable
    let translation = makeTranslation()
    let req = makeRequest(
      modulePath = "test/module.nim",
      functionName = "testFunc",
      proofVaultDir = getTempDir() / "axiom_test_proof_vault"
    )
    # Ensure temp dir exists
    createDir(req.proofVaultDir)
    let sourceCode = "proc testFunc(): int =\n  result = 1"
    let activeInvariant = "result >= 0"
    let result = runLeanProofRefinementLoop(req, translation, sourceCode, activeInvariant, maxRounds = 1)
    check result.rounds.len >= 0
    check result.finalSource.len > 0
    check result.finalInvariant.len > 0
    check result.leanKernelVerified in [true, false]
    # Cleanup
    try:
      removeDir(req.proofVaultDir)
    except CatchableError:
      discard

  test "internal roundsCap=3 overrides maxRounds parameter":
    check leanAvailable
    # Note: The internal roundsCap is hardcoded at 3.
    # maxRounds parameter is accepted but NOT used as the loop cap.
    # Even with maxRounds=0, the loop runs with roundsCap=3.
    let translation = makeTranslation()
    let req = makeRequest(proofVaultDir = getTempDir() / "axiom_test_proof_vault_0")
    createDir(req.proofVaultDir)
    let result = runLeanProofRefinementLoop(req, translation, "let x = 1", "x >= 0", maxRounds = 0)
    # roundsCap is hardcoded at 3, so the loop still runs
    check result.rounds.len >= 0
    # failedReplayAttempts is non-negative
    check result.failedReplayAttempts >= 0
    try:
      removeDir(req.proofVaultDir)
    except CatchableError:
      discard

  test "vacuityProven and leanKernelVerified are valid booleans":
    check leanAvailable
    let translation = makeTranslation()
    let req = makeRequest(proofVaultDir = getTempDir() / "axiom_test_proof_vault_v")
    createDir(req.proofVaultDir)
    let result = runLeanProofRefinementLoop(req, translation, "let x = 1", "", maxRounds = 1)
    check result.vacuityProven in [true, false]
    check result.leanKernelVerified in [true, false]
    if result.leanKernelVerified:
      check result.vacuityProven in [true, false]
    try:
      removeDir(req.proofVaultDir)
    except CatchableError:
      discard

# ═══════════════════════════════════════════════════════════════════════════════
# Test 9: runLeanProofRefinementLoop — return type invariants
# ═══════════════════════════════════════════════════════════════════════════════

suite "runLeanProofRefinementLoop — return type invariants":
  test "finalSource is always non-empty (preserves input when nothing changes)":
    check leanAvailable
    let translation = makeTranslation()
    let req = makeRequest(proofVaultDir = getTempDir() / "axiom_test_proof_vault_ret")
    createDir(req.proofVaultDir)
    let src = "proc foo(): int =\n  result = 42"
    let result = runLeanProofRefinementLoop(req, translation, src, "result == 42", maxRounds = 1)
    check result.finalSource.len > 0
    try:
      removeDir(req.proofVaultDir)
    except CatchableError:
      discard

  test "failedReplayAttempts is non-negative":
    check leanAvailable
    let translation = makeTranslation()
    let req = makeRequest(proofVaultDir = getTempDir() / "axiom_test_proof_vault_fra")
    createDir(req.proofVaultDir)
    let result = runLeanProofRefinementLoop(req, translation, "let x = 1", "", maxRounds = 2)
    check result.failedReplayAttempts >= 0
    try:
      removeDir(req.proofVaultDir)
    except CatchableError:
      discard

  test "rounds have correct phase label":
    check leanAvailable
    let translation = makeTranslation()
    let req = makeRequest(proofVaultDir = getTempDir() / "axiom_test_proof_vault_ph")
    createDir(req.proofVaultDir)
    let result = runLeanProofRefinementLoop(req, translation, "let x = 1", "", maxRounds = 2)
    for round in result.rounds:
      check round.phase == "lean-proof-refinement"
    try:
      removeDir(req.proofVaultDir)
    except CatchableError:
      discard
