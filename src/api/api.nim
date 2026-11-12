import core/trusted/layer_declaration
axiomLayer "presentation"
import core/boundary/axiom_pragmas_boundary
import core/orchestrator/cfg_builder
import core/orchestrator/orchestrator_types
import core/sorter/sorter_core
import core/types/results
import core/symbolic/symbolic_types_expr
import verification/cegar_engine
import verification/orchestrator
type
  VerificationLoopPlan* = object
    initialState*: SorterState
    requests*: seq[OrchestrationProofRequest]
    vaultDir*: string

## Init Verification Sorter Node Id.
# @axiom-hint: lean="modulePath.length ≥ 0 ∧ functionName.length ≥ 0 ∧ dependencyIds.size ≥ 0" smt="(assert (and (>= (str.len modulePath) 0) (>= (str.len functionName) 0) (>= (seq.len dependencyIds) 0)))"
# @axiom-hint: lean="raw.length ≥ 0" smt="(assert (and (>= (str.len raw) 0)))"
func initVerificationSorterNodeId*(raw: string): SorterNodeId {.inline.} =
  sorterNodeId(raw)

## Verification Sorter Node Id String.
# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
func verificationSorterNodeIdString*(nodeId: SorterNodeId): string {.inline.} =
  sorterNodeIdString(nodeId)

## Init Verification Sorter Node.
func initVerificationSorterNode*(
  modulePath: string;
  functionName: string;
  nodeId: SorterNodeId;
  dependencyIds: seq[SorterNodeId]
): SorterNode {.inline.} =
  makeSorterNode(modulePath, functionName, nodeId, dependencyIds)

## Init Verification Sorter State.
# @axiom-hint: lean="nodes.size ≥ 0 ∧ vaultEntries.size ≥ 0 ∧ vaultIntegrityBlocks.size ≥ 0" smt="(assert (and (>= (seq.len nodes) 0) (>= (seq.len vaultEntries) 0) (>= (seq.len vaultIntegrityBlocks) 0)))"
func initVerificationSorterState*(
  nodes: seq[SorterNode];
  vaultEntries: seq[VaultEntry] = @[];
  vaultIntegrityBlocks: seq[VaultIntegrityBlock] = @[]
): SorterState {.inline.} =
  initSorterState(nodes, vaultEntries, vaultIntegrityBlocks)

## Init Verification Proof Request.
# @axiom-hint: lean="(∀ (solverArgsIdx : Fin solverArgs.size), (solverArgs.get solverArgsIdx).length ≥ 0) ∧ injectContradiction = true ∨ injectContradiction = false" smt="(assert (and (forall ((solverArgsIdx Int)) (=> (and (>= solverArgsIdx 0) (< solverArgsIdx (seq.len solverArgs))) (>= (str.len (seq.nth solverArgs solverArgsIdx)) 0))) (or (= injectContradiction true) (= injectContradiction false))))"
func initVerificationProofRequest*(
  nodeId: SorterNodeId;
  sourceCode: string;
  stateValue: int;
  inputDelta: int;
  expectedSmtlib2: string = "";
  currentFingerprint: string = "";
  timeoutMs: int = 0;
  solverCommand: string = "";
  solverArgs: seq[string] = @[];
  injectContradiction: bool = false
): OrchestrationProofRequest {.inline.} =
  initOrchestrationProofRequest(
    nodeId = nodeId,
    sourceCode = sourceCode,
    stateValue = stateValue,
    inputDelta = inputDelta,
    expectedSmtlib2 = expectedSmtlib2,
    currentFingerprint = currentFingerprint,
    timeoutMs = timeoutMs,
    solverCommand = solverCommand,
    solverArgs = solverArgs,
    injectContradiction = injectContradiction
  )

## Init Verification Loop Plan.
# @axiom-hint: lean="requests.size ≥ 0 ∧ vaultDir.length ≥ 0" smt="(assert (and (>= (seq.len requests) 0) (>= (str.len vaultDir) 0)))"
func initVerificationLoopPlan*(
  initialState: SorterState;
  requests: seq[OrchestrationProofRequest];
  vaultDir: string
): VerificationLoopPlan {.inline.} =
  VerificationLoopPlan(
    initialState: initialState,
    requests: requests,
    vaultDir: vaultDir
  )

proc runVerificationLoop*(
  plan: VerificationLoopPlan;
  progressSink: OrchestrationProgressSink = nil
): Result[OrchestrationReport, string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    let ctx = OrchestrationContext(
      cegarEngine: proc(cfg: ControlFlowGraph; headerId: int; z3Check: proc(query: string): bool {.closure, gcsafe, raises: [CatchableError].}; budgetMs: int64): CegarEngineResult {.raises: [CatchableError], gcsafe.} =
        runCegarLoop(cfg, headerId, z3Check, maxIterations = 20, budgetMs = budgetMs),
      encodeSmtlib2: proc(invariants: seq[SymSExpr]): string {.raises: [], gcsafe.} = "",
      progressSink: progressSink
    )
    let loopReport = runAxiomOrchestrationLoop(
      plan.initialState,
      plan.requests,
      plan.vaultDir,
      ctx
    )
    Result[OrchestrationReport, string](ok: true, value: loopReport)
  except CatchableError:
    Result[OrchestrationReport, string](
      ok: false,
      err: "verification loop failed: " & getCurrentExceptionMsg()
    )
