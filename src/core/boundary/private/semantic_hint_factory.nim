import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [], tags: [].}

import std/options
import core/types/hubs/semantic_hint_hub
import core/types/hubs/param_type_info_hub
# axiomIoBoundary

func buildSemanticHint*(
  leanProp, smtConstraint, sourceRef: string,
  confidence: float, strategy: InferenceStrategy,
  params: seq[ParamTypeInfo], ig: float = 0.0
): Option[SemanticHint] {.inline, raises: [].} =
  ## Generic factory for SemanticHint — consolidates 3 duplicated creation patterns.
  some(SemanticHint(
    leanProposition: leanProp,
    smtConstraint: smtConstraint,
    sourceReference: sourceRef,
    confidence: confidence,
    strategy: strategy,
    retryCount: 0,
    paramTypes: params,
    informationGain: ig
  ))

func buildTautologyHint*(nodeId: string, smt, lean: string,
    params: seq[ParamTypeInfo]): Option[SemanticHint] {.inline, raises: [].} =
  ## Build a tautology-proof hint (Wave D/K pattern).
  buildSemanticHint(
    lean, smt,
    "BoundaryExtractor[tautology] for " & nodeId,
    0.99, isTautologyProof, params, 0.0
  )

func buildZeroParamHint*(nodeId: string): Option[SemanticHint] {.inline, raises: [].} =
  ## Build a zero-parameter tautology hint.
  buildSemanticHint(
    "depth >= 0",
    "(assert (>= depth 0))",
    "BoundaryExtractor[bcComplete:zero-param] for " & nodeId,
    0.5, isIntervalAbstraction, @[], 0.0
  )

func buildGateHint*(nodeId, gateName, gateSmt, sourceRef: string,
    confidence: float): Option[SemanticHint] {.inline, raises: [].} =
  ## Build a SOLID gate / guard hint (ACI critical, Wave X, Wave R patterns).
  buildSemanticHint(
    gateName, gateSmt, sourceRef,
    confidence, isIntervalAbstraction, @[], 0.0
  )

{.pop.}
