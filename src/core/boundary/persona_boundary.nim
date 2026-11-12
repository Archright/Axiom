import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Persona Boundary — Hexagonal port for Judge persona.
##
## Judge is a Presentation-layer persona. It must not import core/
## implementation modules directly. This facade exposes the minimal
## surface required by judge.nim and delegates to the existing
## verification boundary where types overlap.
##
## Transitive via verification_interface (no explicit import needed):
##   - core/types/lean_lsp_types
##   - core/types/pipeline_core_types
##
## Explicitly imported below:
##   - core/gateway/gateway
##   - core/logic/pipeline_healing_logic
##   - core/logic/pipeline_trace_artifacts

import core/boundary/verification_interface as vi
export vi

import core/boundary/persona_interface
export persona_interface

import core/types/results
export results

import core/translator/universal_mapper
export universal_mapper

import core/judge/lean_replay
export lean_replay

import core/types/verification_unit
export verification_unit

import core/application/verification_orchestration
export verification_orchestration

import core/types/remediation_types
export remediation_types

import core/diagnostics/refactoring_engine
export refactoring_engine

import core/application/persona_context as pc
export pc

import core/application/persona_context_init as pci
export pci

import core/trusted/axiom_pragmas
export axiom_pragmas

from core/proof/proof_artifact import nil
export proof_artifact

import core/gateway/gateway
export gateway

import core/logic/pipeline_healing_logic
export pipeline_healing_logic

import core/logic/pipeline_trace_artifacts
export pipeline_trace_artifacts

{.pop.}
