## S1-A Golden Fixture — rem body (Certified subset, genuine ACCEPT).
##
## Real Nim source in the bounded subset WITH fixed-divisor remainder:
## `remDomain` computes x mod 3 under the nonneg-dividend domain precondition
## `x >= 0` — exactly the coincidence domain of
## `rem=lean-emod/nim-mod/coincident-nonneg-dividend-domain` (Lean `%` is
## Int.emod, Nim `mod` truncates toward zero; the two agree on nonnegative
## dividends). The generic Lean renderer lowers boRem → Lean `%`, the real
## kernel ACCEPTs the theorem over that semantics, and the full canonical
## chain yields vdVerified with a measured §2.1a binding. The negative
## direction (claims that depend on Nim's negative-dividend truncation) stays
## fail-closed and is pinned by tests/negative/rem_body.nim.
import core/axiom_pragmas
{.push raises: [].}
func remDomain(x: int): int {.
  axiomImpl,
  axiom: [pre: (x >= 0), post: (result >= 0 and result < 3)]
.} =
  x mod 3
{.pop.}
