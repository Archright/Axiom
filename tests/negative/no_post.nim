## S1-C Negative Fixture — no postcondition (nothing to prove).
##
## Real Nim source in the bounded subset. `noPost` carries NO axiom post
## annotation, mirroring the s1c fixture funcDef: renderLeanForFuncDef must
## return "" (fail-closed) and executeCanonicalVerification must report
## inconclusive — never Verified. The file exists so the §6a input identity
## is the sha256 of REAL subject bytes, never a path-derived digest.
import core/axiom_pragmas
{.push raises: [].}
func noPost(x: int): int {.
  axiomImpl
.} =
  x
{.pop.}
