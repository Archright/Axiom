## S1-C Positive control — identity postcondition (kernel ACCEPTS).
##
## Real Nim source in the bounded subset, same shape as the s1c fixture
## funcDef (body = x, post = result == x): the genuine kernel ACCEPT path
## must produce vdVerified with a fully measured §2.1a subject binding.
import core/axiom_pragmas
{.push raises: [].}
func okIdentity(x: int): int {.
  axiomImpl,
  axiom: [post: (result == x)]
.} =
  x
{.pop.}
