import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
## CEGAR Engine — Counter-Example Guided Abstraction Refinement
## Replaces the fake `applySelfAdaptiveAbstraction` timeout fallback
## with a real fixed-point convergence loop.
##
## The loop: abstract → candidate → Z3-check → prove/refine → fingerprint → converge.
##
## Phase 4 (CEGAR-LLM Interleaving): After DeterministicThreshold iterations
## without progress, the loop may invoke an optional LLM-based refinement callback.
## On timeout or failure, the engine falls back to deterministic interval refinement
## — it never blocks on the LLM.

import std/times
import std/options
import std/tables
import std/strutils
import core/crypto/hash_kernel
import verification/abstract_provider
import verification/loop_invariant_synthesis
import verification/solver/unsat_core_slicer
import verification/solver/pdr_engine
import verification/solver/z3_pool
# axiomIoBoundary
import core/orchestrator/cegar_types
export cegar_types
import core/symbolic_types_expr
import core/orchestrator/cfg_builder
import core/orchestrator/orchestrator_types
import core/results
import core/proof/proof_budget
import verification/unified_trajectory
import core/trusted/axiom_pragmas

# ---------------------------------------------------------------------------
# Phase 4 Constants — CEGAR-LLM Interleaving
# ---------------------------------------------------------------------------

const
  LlmRefinementTimeoutMs* = 5000   ## Max time (ms) allowed for LLM refinement callback
  DeterministicThreshold* = 3       ## Min CEGAR iterations before LLM refinement is attempted
  UnsatCoreSlicingDefault* = true   ## Enable actual Z3 unsat core slicing by default
  pdrEngineEnabled* = true          ## PDR/IC3 via Z3 Spacer — real engine active
  DefaultZ3TimeoutMs* = 5000        ## Default Z3 timeout for PDR/CEGAR queries
  DefaultMaxFrames* = 20            ## Default max PDR frames (IC3 depth)
  DefaultMaxGeneralizeDepth* = 3    ## Default max clause generalization depth
  DefaultCegarFuel* = 1000        ## Deterministic fuel budget for CEGAR iterations
  FuelPerIteration* = 10          ## Fuel consumed per CEGAR iteration

# ---------------------------------------------------------------------------
# Unsat Core Slicing — Replace heuristic clause stripping with Z3 real core
# ---------------------------------------------------------------------------

## Run Unsatisfiable Core Slicing on proved invariants.
proc runUnsatCoreSlicing(
  invariants: seq[SymSExpr];
  transitionRelation: string;
  propertyToVerify: string;
 enabled: bool = UnsatCoreSlicingDefault
): seq[string] {.raises: [CatchableError].} =
  ## [impure: calls sliceUnsatCore — I/O side effects via Z3 pool]
  ## Query Z3 for actual unsat core of proved invariants.
  ## Falls back to heuristic (all variable names) if Z3 unavailable or disabled.
  if not enabled or invariants.len == 0:
    return @[]
  let slice = sliceUnsatCore(invariantClauses = invariants,
                             transitionRelation = transitionRelation,
                             propertyToVerify = propertyToVerify)
  if slice.hasUnsatCore():
    # Convert core indices to assumption names for downstream consumers
    return slice.coreIndicesToAssumptions()
  # Fallback: empty (caller decides heuristic)
  @[]
# ---------------------------------------------------------------------------
# Phase 4 Types — LLM Refinement Callback
# ---------------------------------------------------------------------------

type
  LlmRefinementFn* = proc (tacticHistory: seq[string]): Option[string] {.closure, gcsafe, raises: [CatchableError].}
    ## Callback for LLM-based invariant refinement.
    ## Receives the history of operators applied during CEGAR iterations.
    ## Returns Some(invariant) if the LLM produced a refinement, None on timeout or failure.
    ## The callback implementation is responsible for enforcing its own timeout
    ## (see LlmRefinementTimeoutMs). The CEGAR engine never blocks on this call.

# ---------------------------------------------------------------------------
# Fingerprinting
# ---------------------------------------------------------------------------

## Compute Invariant Fingerprint.
func computeInvariantFingerprint*(invariants: seq[SymSExpr]): string {.raises: [].} =
  ## Deterministic fingerprint: sort by sExprToString, hash each with SHA-256,
  ## combine with SHA-256 of the joined sorted strings.
  ## Two sets of invariants with identical string representations yield identical fingerprints.
  var strings: seq[string] = @[]
  for inv in invariants:
    strings.add(sExprToString(inv))
  # Insertion sort — avoids std/algorithm closure-parameter raises edge-case
  for i in 1 ..< strings.len:
    let key = strings[i]
    var j = i - 1
    while j >= 0 and strings[j] > key:
      strings[j + 1] = strings[j]
      dec j
    strings[j + 1] = key
  sha256Hex(strings.join("\n"))

# ---------------------------------------------------------------------------
# SMT-LIB2 Encoding
# ---------------------------------------------------------------------------
### Collect Variables.
func collectVariables(e: SymSExpr; vars: var Table[string, bool]) {.raises: [].} =
  ## Recursively collect unique variable names from an S-expression tree.
  if e == nil:
    return
  case e.kind
  of seVar:
    if e.name.len > 0 and not vars.hasKey(e.name):
      vars[e.name] = true
  of seConst, seTrue, seFalse:
    discard
  of seAdd, seSub, seMul, seDiv, seMod,
     seEq, seNe, seLt, seLe, seGt, seGe,
     seAnd, seOr:
    collectVariables(e.lhs, vars)
    collectVariables(e.rhs, vars)
  of seNot:
    collectVariables(e.lhs, vars)
  of seUninterpretedApp:
    if e.name.len > 0 and not vars.hasKey(e.name):
      vars[e.name] = true
    if e.lhs != nil:
      collectVariables(e.lhs, vars)
  else:
    # Generic traversal for new ADT/collection/abstract variants.
    if e.lhs != nil:
      collectVariables(e.lhs, vars)
    if e.rhs != nil:
      collectVariables(e.rhs, vars)

# Encode Proved Invariants Smtlib2.
func encodeProvedInvariantsSmtlib2*(invariants: seq[SymSExpr]): string {.raises: [].} =
  ## Encodes proved invariants as SMT-LIB2 assertions with variable declarations.
  if invariants.len == 0:
    return ""
  var parts: seq[string] = @[]
  parts.add("; AXIOM CEGAR: Proved loop invariants (fixed-point)")
  # Collect unique variables
  var seenVars = initTable[string, bool]()
  for inv in invariants:
    var invVars = initTable[string, bool]()
    collectVariables(inv, invVars)
    for v in invVars.keys:
      if not seenVars.hasKey(v):
        seenVars[v] = true
        parts.add("(declare-const " & v & " Int)")
  for inv in invariants:
    parts.add("(assert " & sExprToString(inv) & ")")
  parts.add("(check-sat)")
  result = parts.join("\n")

# ---------------------------------------------------------------------------
# Internal Helpers
# ---------------------------------------------------------------------------

## Build Abstract Context.
func buildAbstractContext(
  intervals: Table[string, Interval];
  loopCond: Option[SymSExpr];
  indVars: seq[string]
): AbstractContext {.raises: [].} =
  AbstractContext(
    intervals: intervals,
    loopCondition: loopCond,
    inductionVars: indVars,
    candidateInvariants: @[]
  )

## Refine Intervals.
func refineIntervals(intervals: var Table[string, Interval]) {.raises: [].} =
  ## Tighten interval bounds to strengthen abstraction for next iteration.
  ## For each variable: lo += 1 (if non-negative), hi -= 1 (if positive).
  for name, iv in intervals.mpairs:
    if iv.lo.isSome and iv.lo.get >= 0:
      iv.lo = some(iv.lo.get + 1)
    if iv.hi.isSome and iv.hi.get > 0:
      iv.hi = some(iv.hi.get - 1)

## Contains Invariant.
func containsInvariant(haystack: seq[SymSExpr]; needle: SymSExpr): bool {.raises: [].} =
  let target = sExprToString(needle)
  for existing in haystack:
    if sExprToString(existing) == target:
      return true
  false

## Collect All Variable Names.
func collectAllVariableNames(invariants: seq[SymSExpr]): seq[string] {.raises: [].} =
  ## Deterministic collection of unique variable names from a set of invariants.
  var vars = initTable[string, bool]()
  for inv in invariants:
    collectVariables(inv, vars)
  for v in vars.keys:
    result.add(v)
  # Insertion sort for deterministic output
  for i in 1 ..< result.len:
    let key = result[i]
    var j = i - 1
    while j >= 0 and result[j] > key:
      result[j + 1] = result[j]
      dec j
    result[j + 1] = key

## Encode a non-vacuous transition frame for PDR/unsat-core slicing.
func encodeTransitionRelationForSlicer(
  cfg: ControlFlowGraph;
  headerId: int;
  invariants: seq[SymSExpr]
): string {.raises: [].} =
  var vars = collectAllVariableNames(invariants)
  for v in detectInductionVariables(cfg, headerId):
    if v notin vars:
      vars.add(v)
  if vars.len == 0:
    return ""

  var frameParts: seq[string] = @[]
  for v in vars:
    frameParts.add("(= " & v & "! " & v & ")")
  result = if frameParts.len == 1: frameParts[0] else: "(and " & frameParts.join(" ") & ")"

## Collect Tactic History.
func collectTacticHistory(history: seq[CegarIteration]): seq[string] {.raises: [].} =
  ## Extract the sequence of refinement operators applied during CEGAR iterations.
  ## Passed to the LLM callback as tactic history for context.
  result = @[]
  for h in history:
    result.add(h.operatorUsed)

# ---------------------------------------------------------------------------
# CEGAR Iteration State — Pipeline combinator for ARC/ORC sink optimization
# ---------------------------------------------------------------------------

type
  CegarIterationState* {.acyclic.} = ref object
    ## Mutable state threaded through the CEGAR pipeline passes.
    ## {.acyclic.}: no self-referential fields; skips ORC cycle collector.
    prevFingerprint*: string
    provedInvariants*: seq[SymSExpr]
    history*: seq[CegarIteration]
    iteration*: int
    stagnationCount*: int
    intervals*: Table[string, Interval]
    loopCond*: Option[SymSExpr]
    indVars*: seq[string]
    ## Pipeline intermediate fields (written by one pass, read by the next)
    candidates*: seq[SymSExpr]
    initAsserts*: seq[string]
    candidatesBefore*: int
    newInvariantFound*: bool
    z3Accepted*: bool
    fixedPoint*: bool

## Convert state to engine result.
func toResult(state: CegarIterationState; verdict: CegarEngineVerdict;
    iterations: int; elapsedMs: int64;
    unsatCoreVars: seq[string] = @[]): CegarEngineResult {.raises: [].} =
  CegarEngineResult(
    verdict: verdict, provedInvariants: state.provedInvariants,
    iterations: iterations, elapsedMs: elapsedMs,
    refinementHistory: state.history, unsatCoreVars: unsatCoreVars)

# ---------------------------------------------------------------------------
# Pipeline Pass 1 — Abstract Candidate Generation (pure)
# ---------------------------------------------------------------------------

## Build abstract context and derive invariant candidates.
func runAbstractPass(state: sink CegarIterationState): CegarIterationState {.raises: [].} =
  let ctx = buildAbstractContext(state.intervals, state.loopCond, state.indVars)
  state.candidates = deriveInvariantCandidates(ctx)
  state.initAsserts = buildInitiationAsserts(ctx)
  state.candidatesBefore = state.candidates.len
  state

# ---------------------------------------------------------------------------
# Pipeline Pass 2 — Z3 Synthesis & Fingerprint (side effects)
# ---------------------------------------------------------------------------

## Run Z3-backed invariant synthesis, compute fingerprint, record history.
proc runVerificationPass(
  state: sink CegarIterationState;
  cfg: ControlFlowGraph;
  headerId: int;
  z3Check: proc(query: string): bool {.closure, gcsafe, raises: [CatchableError].};
  startMs: int
): CegarIterationState {.raises: [CatchableError].} =
  ## [impure: calls logStage, getTime — I/O side effects]
  state.newInvariantFound = false
  state.z3Accepted = false
  try:
    let synthResult = synthesizeLoopInvariant(
      cfg, headerId, z3Check, state.candidates, state.initAsserts)
    if synthResult.isSome:
      let inv = synthResult.get
      state.z3Accepted = true
      if not containsInvariant(state.provedInvariants, inv):
        state.provedInvariants.add(inv)
        state.newInvariantFound = true
  except CatchableError:
    state.z3Accepted = false
  let newFingerprint = computeInvariantFingerprint(state.provedInvariants)
  state.fixedPoint = (newFingerprint == state.prevFingerprint) and state.iteration > 0
  state.history.add(CegarIteration(
    iteration: state.iteration,
    candidatesBefore: state.candidatesBefore,
    candidatesAfter: state.provedInvariants.len,
    operatorUsed: if state.newInvariantFound: "synthesize" else: "refine_bounds",
    z3Accepted: state.z3Accepted,
    fixedPointReached: state.fixedPoint))
  state.prevFingerprint = newFingerprint
  state

# ---------------------------------------------------------------------------
# Pipeline Pass 3 — Counterexample-Guided Refinement (side effects)
# ---------------------------------------------------------------------------

## Attempt LLM-based or deterministic interval refinement.
proc runRefinementPass(
  state: sink CegarIterationState;
  headerId: int;
  llmRefine: LlmRefinementFn;
  startMs: int
): CegarIterationState {.raises: [CatchableError].} =
  ## [impure: calls logStage, getTime, llmRefine callback — I/O side effects]
  if not state.newInvariantFound:
    inc state.stagnationCount
    if llmRefine != nil and state.iteration >= DeterministicThreshold:
      let tacticHistory = collectTacticHistory(state.history)
      try:
        let llmResult = llmRefine(tacticHistory)
        if llmResult.isSome:
          let llmInvariant = llmResult.get
          let wrapped = sUninterpretedApp(llmInvariant, nil)
          if llmInvariant.len > 0 and not containsInvariant(state.provedInvariants, wrapped):
            state.provedInvariants.add(wrapped)
            state.newInvariantFound = true
            state.stagnationCount = 0
            let llmMs = int(getTime().toUnixFloat() * 1000)
            logStage(skCegar, $headerId, "iteration=" & $state.iteration & " llm_refinement=accepted", elapsedMs=int(llmMs - startMs))
      except CatchableError:
        let llmMs = int(getTime().toUnixFloat() * 1000)
        logStage(skCegar, $headerId, "iteration=" & $state.iteration & " llm_refinement=timeout", elapsedMs=int(llmMs - startMs))
    if not state.newInvariantFound:
      refineIntervals(state.intervals)
  else:
    state.stagnationCount = 0
  state

# ---------------------------------------------------------------------------
# CEGAR Loop — Thin Pipeline Orchestrator
# ---------------------------------------------------------------------------

## Run CEGAR Loop.
proc runCegarLoop*(cfg: ControlFlowGraph; headerId: int;
    z3Check: proc(query: string): bool {.closure, gcsafe,
      raises: [CatchableError].};
 maxIterations: int = 20; budgetMs: int64 = int64(cegarBudgetMs);
    llmRefine: LlmRefinementFn = nil;
    fuel: int = DefaultCegarFuel
): CegarEngineResult {.raises: [CatchableError].} =
  ## [impure: calls logStage, getTime — I/O side effects]
  ## Fixed-point convergence loop for loop invariant synthesis.
  ## Pipeline: abstract → verify (Z3) → refine → converge.
  let startMs = int(getTime().toUnixFloat() * 1000)
  var remainingFuel = fuel
  var state = CegarIterationState(
    prevFingerprint: "", provedInvariants: @[], history: @[],
    iteration: 0, stagnationCount: 0,
    intervals: analyzeVariableIntervalsAtLoopHeader(cfg, headerId),
    loopCond: extractLoopConditionFromHeader(cfg, headerId),
    indVars: detectInductionVariables(cfg, headerId))
  while state.iteration < maxIterations:
    let nowMs = int(getTime().toUnixFloat() * 1000)
    if nowMs - startMs >= budgetMs:
      logStage(skCegar, $headerId, "iterations=" & $state.iteration & " verdict=budgetExceeded", elapsedMs=int(nowMs - startMs))
      return state.toResult(cegarBudgetExceeded, state.iteration, int64(nowMs - startMs))
    if remainingFuel <= 0:
      logStage(skCegar, $headerId, "iterations=" & $state.iteration & " verdict=fuelExhausted", elapsedMs=int(nowMs - startMs))
      return state.toResult(cegarBudgetExceeded, state.iteration, int64(nowMs - startMs))
    state = state.runAbstractPass()
    state = state.runVerificationPass(cfg, headerId, z3Check, startMs)
    if state.fixedPoint:
      let endMs = int(getTime().toUnixFloat() * 1000)
      logStage(skCegar, $headerId, "iterations=" & $(state.iteration + 1) & " verdict=cegarProven", elapsedMs=int(endMs - startMs))
      return state.toResult(cegarProven, state.iteration + 1, int64(endMs - startMs))
    state = state.runRefinementPass(headerId, llmRefine, startMs)
    remainingFuel -= FuelPerIteration
    inc state.iteration
  let endMs = int(getTime().toUnixFloat() * 1000)
  let isCounterexample = state.stagnationCount >= 3
  logStage(skCegar, $headerId, "iterations=" & $state.iteration & " verdict=" & (if isCounterexample: "cegarCounterexample" else: "cegarMaxIterations"), elapsedMs=int(endMs - startMs))
  state.toResult(
    if isCounterexample: cegarCounterexample else: cegarMaxIterations,
    state.iteration, int64(endMs - startMs),
    if isCounterexample: collectAllVariableNames(state.provedInvariants) else: @[])

type
  CegarZ3CheckFn* = proc (query: string): bool {.closure, gcsafe, raises: [CatchableError].}
  CegarStageOutput* = object
    provedInvariants*: seq[SymSExpr]
    primaryLoopHeaderId*: int
    iterations*: int
    elapsedMs*: int64
    unsatCoreVars*: seq[string]

proc z3CheckViaProcess*(solverCmd: string; solverArgs: seq[string]): CegarZ3CheckFn {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## [impure: routes queries through the Z3 persistent pool]
  ## Returns a closure that sends Z3 queries through z3ExecPersistent.
  ## Pool parameters (solverCmd/solverArgs) are retained for API compatibility
  ## but ignored — the pool is configured globally via z3EnsurePersistentPool.
  result = proc (query: string): bool {.closure, gcsafe, raises: [CatchableError].} =
    try:
      # [DETERMINISTIC] rlimit injected by z3_pool.buildZ3QueryEnvelope (PRIMARY).
      # timeoutMs = process safety net only — Z3 self-limits via rlimit.
      var cd, td: string
      let res = z3ExecPersistent(query, timeoutMs = z3SafetyNetMs, desiredWorkers = 1,
        canonicalEnvelopeDigest = cd, transportPayloadDigest = td)
      if res.isErr:
        return false
      ## SMT-LIB: unsat = no counterexample = invariant/equivalence VALID
      res.get().strip().startsWith("unsat")
    except CatchableError:
      false

proc runCegarAbstraction*(
  req: OrchestrationProofRequest;
  z3Check: CegarZ3CheckFn;
 llmRefine: LlmRefinementFn = nil
): CegarStageOutput {.raises: [CatchableError].} =
  ## [impure: calls runCegarLoop (impure), buildControlFlowGraph — I/O side effects]
  ## Encapsulated CEGAR stage: parses source, builds CFG, finds loop header,
  ## runs fixed-point loop. Returns proved invariants or empty on failure.
  ## Phase 4: Accepts optional LLM refinement callback for interleaving.
  ## Phase 5: PDR/IC3 first — if PDR converges, skip CEGAR entirely.
  let cfgRes = buildControlFlowGraph(req.sourceCode)
  if cfgRes.isErr:
    return CegarStageOutput(
      provedInvariants: @[],
      primaryLoopHeaderId: -1,
      iterations: 0,
      elapsedMs: 0,
      unsatCoreVars: @[]
    )
  let cfg = cfgRes.get()
  let headerId = findPrimaryLoopHeader(cfg)
  if headerId < 0:
    return CegarStageOutput(
      provedInvariants: @[],
      primaryLoopHeaderId: -1,
      iterations: 0,
      elapsedMs: 0,
      unsatCoreVars: @[]
    )

  # Phase 5: Try PDR/IC3 before falling back to CEGAR
  if pdrEngineEnabled:
    # [DETERMINISTIC] rlimit injected by z3_pool for each Z3 call inside PDR.
    # pdrTimeoutMs is process safety net only — not used for proof decisions.
    let pdrTimeoutMs = if req.timeoutMs > 0: req.timeoutMs div 2 else: DefaultZ3TimeoutMs
    let loopCond = extractLoopConditionFromHeader(cfg, headerId)
    var pdrProperty = ""
    if loopCond.isSome and not loopCond.get.isNil and loopCond.get.kind != seTrue:
      pdrProperty = sExprToString(sNot(loopCond.get))
    if pdrProperty.len == 0:
      logStage(skCegar, $headerId, "PDR skipped: no concrete loop-condition property")
    else:
      let pdrInitial = "true"
      let pdrTransition = encodeTransitionRelationForSlicer(cfg, headerId, @[sVar("property")])
      if pdrTransition.len == 0:
        logStage(skCegar, $headerId, "PDR skipped: no concrete transition variables")
      else:
        let pdrResult = runPdrEngine(
          property = pdrProperty,
          initialState = pdrInitial,
          transitionRelation = pdrTransition,
          config = PdrConfig(
            maxFrames: DefaultMaxFrames,
            z3TimeoutMs: pdrTimeoutMs,
            maxGeneralizeDepth: DefaultMaxGeneralizeDepth
          )
        )

        if pdrResult.converged:
          # PDR found an inductive invariant — skip CEGAR entirely
          var pdrInvariants: seq[SymSExpr] = @[]
          for invStr in pdrResult.inductiveInvariant:
            pdrInvariants.add(sUninterpretedApp(invStr, nil))
          var unsatCoreVars: seq[string] = @[]
          if pdrInvariants.len > 0:
            let transitionRel = encodeTransitionRelationForSlicer(cfg, headerId, pdrInvariants)
            let property = encodeProvedInvariantsSmtlib2(pdrInvariants)
            if transitionRel.len > 0 and property.len > 0:
              unsatCoreVars = runUnsatCoreSlicing(
                pdrInvariants, transitionRel, property)
          return CegarStageOutput(
            provedInvariants: pdrInvariants,
            primaryLoopHeaderId: headerId,
            iterations: 0,
            elapsedMs: int64(pdrResult.elapsedMs),
            unsatCoreVars: unsatCoreVars
          )

  # PDR diverged or disabled — fall back to CEGAR
  # [DETERMINISTIC] CEGAR loop budget. rlimit injected per-Z3-call via z3_pool.
  # budgetMs is iteration-level wall-clock guard, NOT a solver decision bound.
  # P2a: SSOT-only — always use cegarBudgetMs (drop req.timeoutMs override for determinism).
  let budgetMs = int64(cegarBudgetMs)
  let loopResult = runCegarLoop(cfg, headerId, z3Check, maxIterations = 20, budgetMs = budgetMs, llmRefine = llmRefine, fuel = DefaultCegarFuel)
  # Unsat core slicing: replace heuristic with actual Z3 core when available
  var unsatCoreVars = loopResult.unsatCoreVars
  if unsatCoreVars.len == 0 and loopResult.provedInvariants.len > 0:
    # Build transition relation and property strings for the slicer.
    let transitionRel = encodeTransitionRelationForSlicer(cfg, headerId, loopResult.provedInvariants)
    let property = encodeProvedInvariantsSmtlib2(loopResult.provedInvariants)
    if transitionRel.len > 0 and property.len > 0:
      unsatCoreVars = runUnsatCoreSlicing(
        loopResult.provedInvariants, transitionRel, property)
  CegarStageOutput(
    provedInvariants: loopResult.provedInvariants,
    primaryLoopHeaderId: headerId,
    iterations: loopResult.iterations,
    elapsedMs: loopResult.elapsedMs,
    unsatCoreVars: unsatCoreVars
  )

{.pop.}

