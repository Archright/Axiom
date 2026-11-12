import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Semantic Hint Types — SSOT for inference strategy and hint data.
## Extracted from core/judge/smart_search to resolve SOC-leaf-module-imports
## violation in core/types/heal_types.nim.
##
## ParamTypeInfo lives in param_type_info_hub.nim (carries RefinementType dep).
## This module re-exports it so consumers are unaffected.

import core/types/hubs/param_type_info_hub
export param_type_info_hub

type
  InferenceStrategy* = enum
    isHintComment
    isIntervalAbstraction
    isStructuralInduction
    isPatternMatching
    isTautologyProof  ## Wave D: type-system tautology proof (e.g., str.len >= 0)

  BottleneckCause* = enum
    bcNoHintComment
    bcComplexRecursion
    bcNonLinearArithmetic
    bcExternalIO
    bcComplexControlFlow
    bcClosureSemantics
    bcLargeFunctionBody
    bcHighComplexity   ## ACI > 70: blocked from pipeline
    bcHighCoupling     ## SRP violation: >8 external symbol dependencies
    bcUnknown

  SemanticHint* = object
    leanProposition*: string
    smtConstraint*: string
    sourceReference*: string
    confidence*: float
    strategy*: InferenceStrategy
    retryCount*: int
    paramTypes*: seq[ParamTypeInfo]  ## Parameter type mapping for Lean code generation
    informationGain*: float  ## Phase 3: entropy-based proof quality score

{.pop.}
