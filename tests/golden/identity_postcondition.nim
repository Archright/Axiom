## S1-B Golden Fixture — identity postcondition regression control.
##
## This is a REAL Nim source file in the bounded S1-A subset (Int params,
## +, -, comparisons, if-then-else, single postcondition on `result`).
## It is the durable input that the canonical product execution core
## (IR extraction → obligation → generic I6 body lowering → real Lean
## kernel ACCEPT → KAA → vdVerified) must genuinely prove.
##
## This is a REGRESSION CONTROL proving the canonical execution core works
## end-to-end. It is NOT, by itself, productization GO evidence: GO evidence
## (S1-D) must come from a normal release build of the real product code
## selecting a real production symbol, not from a fixture.
##
## (Candidate: `normalizeMaxWorkers` in
##  src/core/orchestrator/orchestrator_api.nim:34 is the real production
##  symbol with this exact shape; a release-build target-selection acceptance
##  re-proves it there without relying on this fixture.)

## Bounded-subset identity postcondition: result == x.
import core/axiom_pragmas
{.push raises: [].}
func identityPostcondition(x: int): int {.
  axiomImpl,
  axiom: [post: (result == x)]
.} =
  x
{.pop.}
