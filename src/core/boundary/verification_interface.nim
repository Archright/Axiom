import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import core/bmc/bmc_generic
import core/boundary/coverage_bridge
import core/boundary/persona_interface
import core/solver/solver_bridge
import core/types/domain_types
import core/types/lean_lsp_types
import core/types/pipeline_core_types
## Layer-crossing authority: UNDECLARED. This boundary facade re-exports pure
## types from verification/ (facade convention per architecture §1.19), but no
## ADR covers the core→verification crossing itself; the exception set is
## pending architect decision (data/debt_registry.json DEBT#483,
## resolution: DEFERRED_PENDING_ARCHITECT_DECISION).
## The formerly cited DEBT#244 has no entry in data/debt_registry.json —
## ghost reference removed 2026-10-11.
## These imports provide types consumed by the entire Domain layer.
import verification/abstract_provider_types
import verification/pipeline_state_types
import verification/solver/fixedpoint_types
import verification/unified_trajectory_types
export domain_types
export pipeline_core_types
export persona_interface
export lean_lsp_types
export solver_bridge

# ─── Re-exported pure types from verification/ ─────────────────────────
# Side-effectful operations declared as proc types.
# The I/O boundary (CLI layer) injects concrete implementations.

type
  LeanstralResult* = object
    ## Result from Leanstral LLM call.
    ## Canonical type exported via core/application/persona_context for the Presentation layer.
    success*: bool
    proof*: string
    theoremSource*: string
    tacticTrace*: seq[string]
    premises*: seq[string]
    diagnostics*: string
    rawOutput*: string
    timedOut*: bool
    confidence*: float
    error*: string

  Layer1BmcVerdict* = enum
    lbvProven
    lbvBugFound
    lbvInconclusive

  Layer1BmcResult* = object
    verdict*: Layer1BmcVerdict
    provenLayer*: ProvenLayerKind
    witnessTrace*: GenericBmcTrace
    elapsedMs*: int64

  CegarVerdict* = enum
    cvProved
    cvCounterexample
    cvTimeout
    cvError

  CegarResult* = object
    verdict*: CegarVerdict
    invariants*: seq[string]
    counterexample*: string

  # AbstractContext, Interval, and FixedpointResult are re-exported from
  # verification/abstract_provider_types and verification/solver/fixedpoint_types
  # via pure type module exports above. Do not define duplicates here.

  Z3CheckFn* = proc(smt2: string; timeoutMs: int = 5000): string {.gcsafe, raises: [].}
export coverage_bridge
export pipeline_state_types
export unified_trajectory_types
export abstract_provider_types
export fixedpoint_types

{.pop.}
