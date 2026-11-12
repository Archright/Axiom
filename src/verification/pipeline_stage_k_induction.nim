import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import core/boundary/cfg_builder
import core/axiom_pragmas
import core/bmc/bmc_types
import core/bmc/transition_adapter
import core/judge/lean_replay
import core/orchestration/pipeline_config
import core/proof/proof_budget
import core/solver/encoding_validity
import core/solver/solver_bridge
import core/trusted/trust_commit
import core/crypto/hash_kernel
import core/trusted/scope_identity
import core/json/json_utils
import std/json
import std/options
import std/os
import std/strutils
import verification/cegar_engine
import verification/inductive_proof_emitter
import verification/spacer_chc_router
import infrastructure/process_utils
# axiomIoBoundary

type
  VerificationPath* = enum
    vpDirectValidity  ## DAG → direct VC unsat check
    vpChcSpacer       ## Reducible → CHC/Spacer invariant synthesis
    vpIncrementalK    ## Irreducible → incremental k-induction (push/pop)

  SpacerFallbackReason* = enum
    sfrUnknown       ## Spacer returned unexpected result
    sfrSat           ## Spacer found counterexample (not a fallback candidate)
    sfrTimeout       ## Spacer timed out → try k-induction
    sfrWorkerFailed  ## Spacer process crashed → return error
func classifyAndRoute*(
    sourceCode: string;
    transitionRule: Option[TransitionRule];
    invariantRule: Option[InvariantRule]
): VerificationPath {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Classify CFG topology and select optimal verification path.
  ##
  ## Decision matrix:
  ##   topoDag         → vpDirectValidity
  ##   topoReducible   → vpChcSpacer (if available) or vpDirectValidity
  ##   topoIrreducible → vpIncrementalK
  let topo = classifyFunction(sourceCode)
  case topo.kind
  of topoDag:
    return vpDirectValidity
  of topoReducible:
    # CHC/Spacer is the correct path for reducible CFGs with loops
    return vpChcSpacer
  of topoIrreducible:
    return vpIncrementalK
proc runDirectValidityCheck*(
    invariantRule: InvariantRule;
 functionName: string = ""
): KInductionResult {.raises: [CatchableError].} =
  ## Direct validity check for DAG (acyclic) functions.
  ##
  ## Instead of k-induction, directly encode the VC as:
  ##   (assert (not property)) → unsat = proved
  ##
  ## This is instant for simple invariants.
  result = KInductionResult(
    verdict: kivError, k: 1,
    baseCaseUnsat: false, stepCaseUnsat: false,
    baseCaseTimeMs: 0, stepCaseTimeMs: 0,
    uniquenessConstraints: 0, useLocallyShortest: false,
    baseCaseOutput: "", stepCaseOutput: "",
    leanProofScript: ""
  )

  let payload = buildValidityFromInvariant(
    declarations = @["x"],
    invariantRule = invariantRule,
    variableSymbol = "x",
    functionName = functionName
  )

  let z3Check = z3CheckViaProcess("z3", @["-smt2", "-in"])
  let isUnsat = z3Check(payload.smt2)

  if isUnsat:
    result.verdict = kivProved
    result.k = 1
    result.baseCaseUnsat = true
    result.stepCaseUnsat = true
  else:
    result.verdict = kivCounterexample
    result.k = 1
    result.baseCaseUnsat = false
proc runIncrementalKCheck*(
    payload: KInductionPayload;
    maxK: int
): KInductionResult {.raises: [CatchableError], axiomEffect: IOEffect, tags: [RootEffect, TimeEffect, AxiomIOEffect, IOEffect].} =
  ## Incremental k-induction routed through the Z3 persistent pool.
  ##
  ## User refinement (Plan v5): "Progressive k-Induction (Incremental Solving)
  ## k=2→4→8→16까지 z3ExecPersistent로 점진적 확장"
  let z3Check = z3CheckViaProcess("z3", @["-smt2", "-in"])
  runIncrementalKInduction(payload, maxK, z3Check, 30_000)
proc runKInductionStage*(
  config: PipelineConfig;
 transitionRule: Option[TransitionRule] = none(TransitionRule);
  invariantRule: Option[InvariantRule] = none(InvariantRule)
): KInductionResult {.registerStage, raises: [], axiomEffect: IOEffect, tags: [RootEffect, TimeEffect, AxiomIOEffect, IOEffect].} =
  ## Triple-Path verification router.
  ##
  ## 1. Fail-fast if rules missing
  ## 2. Classify CFG topology
  ## 3. Route to optimal solver:
  ##    - DAG → Direct Validity Query
  ##    - Reducible → CHC/Spacer (via trySpacerInvariantSynthesis)
  ##    - Irreducible → Incremental k-Induction (push/pop)
  ## 4. Write evidence JSON
  ## 5. If proved, emit Lean proof script

  result = KInductionResult(
    verdict: kivError, k: 0,
    baseCaseUnsat: false, stepCaseUnsat: false,
    baseCaseTimeMs: 0, stepCaseTimeMs: 0,
    uniquenessConstraints: 0, useLocallyShortest: false,
    baseCaseOutput: "", stepCaseOutput: "",
    leanProofScript: ""
  )

  # Phase 1: fail-fast when semantic extractor provides no rules.
  if transitionRule.isNone or invariantRule.isNone:
    return result

  let priorInvariant = config.priorPromotion.invariant
  let activeRule = transitionRule.get()
  let activeInvariant = invariantRule.get()

  # Classify CFG topology and select verification path
  # Source code lives in the pipeline request; cfg_builder parses it
  # to detect control-flow structure (if/while/for/case → loops).
  let sourceCode = config.req.sourceCode
  let vPath = classifyAndRoute(sourceCode, transitionRule, invariantRule)

  try:
    case vPath
    of vpDirectValidity:
      # DAG path: direct validity check (fastest)
      result = runDirectValidityCheck(activeInvariant, config.guardNodeId)

    of vpChcSpacer:
      # CHC/Spacer path: invariant synthesis with feedback loop
      # sat → counterexample (immediate return)
      # unsat → proved (invariant found)
      # unknown/timeout → cascade to k-induction
      # workerFailed → error
      let bmcTransitions = encodeTransitionsAsBmc(@[activeRule], "x")
      let spacerResult = trySpacerInvariantSynthesis(
        transitions = bmcTransitions,
        initialState = @[("x", "Int")],
        violationCondition = "(> x " & $activeInvariant.maxValue & ")",
        timeoutMs = 10_000
      )
      if spacerResult.success:
        # Spacer proved the property
        result.verdict = kivProved
        result.k = 1
        result.baseCaseUnsat = true
        result.stepCaseUnsat = true
      elif spacerResult.status == "sat":
        # Spacer found a counterexample — no point trying k-induction
        result.verdict = kivCounterexample
        result.k = 1
        result.baseCaseUnsat = false
      else:
        # unknown/timeout → cascade to k-induction
        let maxK = estimateMaxK(0.5, 2, 0)
        if maxK >= 2:
          let kPayload = buildKInductionPayload(maxK, 0, activeRule)
          result = runIncrementalKCheck(kPayload, maxK)

    of vpIncrementalK:
      # Incremental k-induction path (for irreducible CFGs)
      let maxK = estimateMaxK(0.5, 2, 0)
      if maxK >= 2:
        let kPayload = buildKInductionPayload(maxK, 0, activeRule)
        result = runIncrementalKCheck(kPayload, maxK)

    # Write evidence JSON
    try:
      createDir("logs/evidence")
      let evidencePath = "logs/evidence/" &
        config.guardNodeId.replace("/", "_").replace("::", "_") &
        "_k_induction.json"
      let evidenceJson = %*{
        "k": result.k,
        "verdict": $result.verdict,
        "baseCaseUnsat": result.baseCaseUnsat,
        "stepCaseUnsat": result.stepCaseUnsat,
        "baseCaseTimeMs": result.baseCaseTimeMs,
        "stepCaseTimeMs": result.stepCaseTimeMs,
        "uniquenessConstraints": result.uniquenessConstraints,
        "useLocallyShortest": result.useLocallyShortest,
        "verificationPath": $vPath
      }
      writeFile(evidencePath, pretty(evidenceJson) & "\n")
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
    # Non-authoritative cache: the raw evidence file is a derived cache artifact.
    # The authoritative state is the TrustCommit journal record written below.
    try:
      let claim = renderJsonMultiline(%*{
        "k": result.k,
        "verdict": $result.verdict,
        "baseCaseUnsat": result.baseCaseUnsat,
        "stepCaseUnsat": result.stepCaseUnsat,
        "baseCaseTimeMs": result.baseCaseTimeMs,
        "stepCaseTimeMs": result.stepCaseTimeMs,
        "uniquenessConstraints": result.uniquenessConstraints,
        "useLocallyShortest": result.useLocallyShortest,
        "verificationPath": $vPath
      })
      let certificateDigest = sha256Hex(claim)
      let solverInvocation = "k-induction"
      let evidenceId = computeEvidenceId(claim, solverInvocation, certificateDigest)
      let scopeDigest = certificateScopeDigestForPair("src/verification/pipeline_stage_k_induction.nim", "runKInductionStage")
      let configDigest = certificateConfigDigestForPair("src/verification/pipeline_stage_k_induction.nim", "runKInductionStage", "k-induction", "", "", "SPV1")
      let c = TrustCommit(
        kind: tcVerifiedProof,
        evidenceId: evidenceId,
        claim: claim,
        solverInvocation: solverInvocation,
        attestation: "K-induction evidence captured in TrustCommit journal",
        certificateDigest: certificateDigest,
        scopeDigest: scopeDigest,
        configDigest: configDigest,
        parentCommit: none(string)
      )
      let journalBase = repoRootForPath(".")
      let baseDir = if journalBase.len > 0: journalBase else: "."
      discard commitVerification(baseDir, c)  # axiom:best-effort(TrustCommit journal is advisory; failures re-checked by reconcilePass)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch) — TrustCommit failure must not block evidence write

    # Emit and verify Lean proof script if proved
    if result.verdict == kivProved:
      try:
        let leanScript = emitLeanInductionProof(
          config.guardNodeId,
          priorInvariant,
          result.k, ""
        )
        if leanScript.len > 0:
          let proofPath = ".axiom/vault/" &
            config.guardNodeId.replace("/", "_").replace("::", "_") &
            "_k_induction_lean.lean"
          try:
            sanitizeAndWriteLeanSource(proofPath, leanScript)
            let (_, exitCode) = execCmdWithTimeout("lean " & proofPath, timeoutMs = 120_000)
            if exitCode == 0:
              result.leanProofScript = leanScript
          except CatchableError:
            discard  # axiom:best-effort(ioboundary catch)
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

{.pop.}
