## PipelineTypes — Zero-cost distinct phantom types for verification pipeline.
##
## ProofState[S] uses distinct SharedProofContext to achieve:
## - Compile-time stage enforcement (type mismatch on wrong stage)
## - Zero runtime overhead (distinct = same memory layout)
## - ORC-safe mutation via pointer cast (no refcount corruption)
##
## This replaces the 6-value-type chain in pipeline_state_types.nim
## which had deep copy overhead and dead types (RaidedState, CertifiedState, VerifiedState).

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
# axiomIoBoundary

type
  ## Phantom type stage tags (zero-cost, 1 byte each)
  StageInput* = object
  StageDetected* = object
  StageLegislated* = object
  StageVerified* = object

  ## Deterministic solver trace — accumulated across refinement rounds
  SolverTrace* = object
    unsatCoreVars*: seq[string]
    cxHistory*: seq[string]
    cegarCounterexample*: bool
    kInductionVerdict*: string

  ## Shared proof context — single source of truth for pipeline state
  SharedProofContext* = object
    functionName*: string
    modulePath*: string
    sourceCode*: string
    currentInvariant*: string
    priorInvariant*: string
    trace*: SolverTrace

  ## Distinct phantom type wrapper — compile-time stage enforcement
  ## with zero runtime overhead (same memory layout as SharedProofContext)
  ProofState*[S] = distinct SharedProofContext

## Immutable access — template to prevent accidental deep copy on let binding.
## Usage: state.getCtx.fieldName (direct field access only)
template getCtx*(self: ProofState): SharedProofContext =
  SharedProofContext(self)

## Mutable access — pointer cast for zero-copy in-place mutation.
func getCtxMut*(self: var ProofState): var SharedProofContext {.inline.} =
  cast[ptr SharedProofContext](addr self)[]

## Compile-time stage transition — zero-cost type reinterpretation.
## For proc arguments: pass directly (no let binding) to avoid copy.
func toStage*[S1, S2](self: ProofState[S1], T: typedesc[S2]): ProofState[S2] {.inline.} =
  ProofState[S2](SharedProofContext(self))

## Zero-copy view for proc argument passing (template inline expansion).
## Use this when passing to a proc without intermediate let binding.
template toStageView*[S1, S2](self: ProofState[S1], T: typedesc[S2]): untyped =
  cast[ptr ProofState[S2]](unsafeAddr self)[]
{.pop.}
