import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Abstract Provider Types — Pure type definitions for interval analysis.
##
## Extracted from abstract_provider.nim to enforce Layer Boundary policy:
## core/ modules may only import pure type modules from verification/.

import std/options
import std/tables
import core/symbolic_types_expr
# axiomIoBoundary

type
  Interval* = object
    lo*: Option[int]   ## none = -∞
    hi*: Option[int]   ## none = +∞

  AbstractContext* = object
    intervals*: Table[string, Interval]
    loopCondition*: Option[SymSExpr]
    inductionVars*: seq[string]
    candidateInvariants*: seq[SymSExpr]

{.pop.}
