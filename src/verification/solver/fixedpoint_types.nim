import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
# axiomIoBoundary

## Fixedpoint Types — Pure type definitions for CHC/Fixedpoint engine.
##
## Extracted from fixedpoint_engine.nim to enforce Layer Boundary policy:
## core/ modules may only import pure type modules from verification/.

type
  HornClause* = object
    name*: string
    body*: string      # SMT-LIB2 boolean expression (premise)
    head*: string      # SMT-LIB2 atom (conclusion)

  FixedpointResult* = object
    sat*: bool           # true = property violated (SAT), false = safe (UNSAT)
    invariant*: string   # Generated inductive invariant (when safe)
    counterexample*: string  # Model / counterexample trace (when violated)
    rawOutput*: string

{.pop.}
