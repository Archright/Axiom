## S1-A Golden Fixture — mul/div body (Certified subset, genuine ACCEPT).
##
## Real Nim source in the bounded subset WITH multiplication and fixed-divisor
## division: `mulDivRoundtrip` computes (x * 6) div 2 and declares the
## postcondition `result == (x * 6) div 2`. The generic Lean renderer lowers
## boMul → `*` and boDiv → Lean `/` (floor) — on this postcondition both sides
## unfold to the same expression, so the real kernel ACCEPTs and the full
## canonical chain yields vdVerified with a measured §2.1a binding.
import core/axiom_pragmas
{.push raises: [].}
func mulDivRoundtrip(x: int): int {.
  axiomImpl,
  axiom: [post: (result == (x * 6) div 2)]
.} =
  (x * 6) div 2
{.pop.}
