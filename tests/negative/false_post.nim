## S1-C Negative Fixture — false postcondition (kernel must REJECT).
##
## Real Nim source in the bounded subset. `falsePost` declares the FALSE
## postcondition `result + 1 == x` over the body `x`: the rendered theorem
## `x + 1 == x` is genuinely rejected by the Lean kernel (omega) — this file
## makes the s1c kernel-reject promotion run against REAL subject bytes with
## a measurable §2.1a binding, never against a nonexistent path.
import core/axiom_pragmas
{.push raises: [].}
func falsePost(x: int): int {.
  axiomImpl,
  axiom: [post: (result + 1 == x)]
.} =
  x
{.pop.}
