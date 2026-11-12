import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

## Solver Contract — Facade exposing only pure types and functions.
##
## This module is the SSOT for cross-domain access to solver internals.
## I/O procs are excluded — callers must go through the I/O boundary directly.
##
## Constraints:
##   - zero I/O (all symbols are pure)
##   - zero CLI-layer imports

from core/solver/types import nil
export types

{.pop.}
{.pop.}
