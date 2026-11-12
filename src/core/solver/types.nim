import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

## Solver Type Re-exports + Serialization Bridge
##
## This module re-exports bare_types (the type-only layer) and
## provides backward-compatible access to serialization functions.
## Per AGENTS.md §0.6: Static First Enforcement.

import core/solver/bare_types
export bare_types

# Re-export serialization functions for backward compatibility
from core/solver/type_serialize import solverStatusString, logicKindString
export solverStatusString
export logicKindString

{.pop.}

{.pop.}
