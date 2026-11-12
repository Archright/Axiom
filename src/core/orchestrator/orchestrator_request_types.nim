import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

import std/strutils
import core/sorter/sorter_core
import ../../core/trusted/axiom_pragmas

type
  OrchestrationProofRequest* = object
    nodeId*: SorterNodeId
    sourceCode*: string
    stateValue*: int
    inputDelta*: int
    expectedSmtlib2*: string
    currentFingerprint*: string
    timeoutMs*: int
    solverCommand*: string
    solverArgs*: seq[string]
    injectContradiction*: bool
    cegarInvariants*: seq[string]  ## CEGAR-derived loop invariants (immutable enrichment)
    unsatCoreVars*: seq[string]    ## Z3 unsat core variables from failed CEGAR iteration
    topologyScore*: int            ## Dynamic gas weight (higher = more gas consumed per node)

## Init Orchestration Proof Request.
func initOrchestrationProofRequest*(
  nodeId: SorterNodeId;
  sourceCode: string;
  stateValue: int;
  inputDelta: int;
  expectedSmtlib2: string = "";
  currentFingerprint: string = "";
  timeoutMs: int = 0;
  solverCommand: string = "";
  solverArgs: seq[string] = @[];
  injectContradiction: bool = false;
  topologyScore: int = 0
): OrchestrationProofRequest {.inline, axiom: ["(assert (and req (>= req 0) (forall ((solverArgsIdx Int)) (=> (and (>= solverArgsIdx 0) (< solverArgsIdx (seq.len solverArgs))) (>= (str.len (seq.nth solverArgs solverArgsIdx)) 0))) (or (= injectContradiction true) (= injectContradiction false))))", "req ∧ (req ≥ 0) ∧ (∀ (solverArgsIdx : Fin solverArgs.size), (solverArgs.get solverArgsIdx).length ≥ 0) ∧ injectContradiction = true ∨ injectContradiction = false"].} =
  var req = OrchestrationProofRequest(
    nodeId: nodeId,
    sourceCode: sourceCode,
    stateValue: stateValue,
    inputDelta: inputDelta,
    expectedSmtlib2: expectedSmtlib2.strip(),
    currentFingerprint: currentFingerprint.strip(),
    timeoutMs: timeoutMs,
    solverCommand: solverCommand.strip(),
    solverArgs: solverArgs,
    topologyScore: topologyScore
  )
  when not defined(release):
    req.injectContradiction = injectContradiction
  return req

## Add Unique Node Id.
func addUniqueNodeId*(target: var seq[SorterNodeId]; nodeId: SorterNodeId) {.raises: [], axiom: ["(assert ast_parse_failed_isolated)", "ast_parse_failed_isolated"].} =
  if sorter_core.containsNodeId(target, nodeId):
    return
  target.add(nodeId)

## Immutable enrichment: return a new request with CEGAR invariants injected.
func withCegarInvariants*(req: OrchestrationProofRequest; invariants: seq[string]): OrchestrationProofRequest {.raises: [].} =
  result = req
  result.cegarInvariants = invariants

## Find Request Index.
func findRequestIndex*(
  requests: seq[OrchestrationProofRequest];
  nodeId: SorterNodeId
): int {.raises: [], axiom: ["(assert ast_parse_failed_isolated)", "ast_parse_failed_isolated"].} =
  for idx, request in requests:
    if nodeIdEquals(request.nodeId, nodeId):
      return idx
  -1

## Node Impact Index Lookup type definition.
type NodeImpactIndexLookup* = proc(nodeId: SorterNodeId): int {.noSideEffect, gcsafe, closure, raises: [].}

## To Gateway Dependency Axioms.
func toGatewayDependencyAxioms*(axioms: seq[AxiomFormula]): seq[string] {.raises: [].} =
  result = newSeqOfCap[string](axioms.len)
  for axiom in axioms:
    result.add(axiomFormulaString(axiom))

{.pop.}
{.pop.}
