## S1-A Golden Fixture — subtraction postcondition (EA-wire-compatible pair).
##
## Real Nim source in the bounded subset (Int params, -, comparisons, single
## postcondition on `result`) whose body is INSIDE the extraction-agreement
## wire set (no if-statement — see the normalizeMaxWorkers EA_UNSUPPORTED
## finding: the render subset covers if-then-else but the differential wire
## set does not yet). It gives the canonical-chain golden suites a SECOND
## genuine subject distinct from identity_postcondition.nim so splice
## resistance is exercised between two EA-agreeing executions.
import core/axiom_pragmas
{.push raises: [].}
func subPostcondition(x: int): int {.
  axiomImpl,
  axiom: [post: (result == x - 1)]
.} =
  x - 1
{.pop.}
