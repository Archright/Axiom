## S1-C Negative Fixture — negative-dividend rem (truncated-remainder claims).
##
## Real Nim source. `remBody` takes a remainder (boRem). boRem IS in the
## certified subset since the rem denotation landed (Denotation.lean:
## Int.emod + BitVec.srem; renderer `%` with the
## `rem=lean-emod/nim-mod/coincident-nonneg-dividend-domain` identity), and
## the nonneg-dividend VERIFIED path is pinned positively by
## tests/golden/rem_body.nim. This fixture pins the OTHER direction: claims
## that depend on Nim's truncated `mod` range over negative dividends
## (Nim: -2 ≤ x mod 3 ≤ 0; Lean emod: 0 ≤ x % 3 ≤ 2) are NOT provable under
## the emod semantics — omega rejects them, so the canonical chain stays
## fail-closed (lean_kernel_rejected) and never Verified. The file exists so
## the §6a input identity is the sha256 of REAL subject bytes, never a
## path-derived digest.
import core/axiom_pragmas
{.push raises: [].}
func remBody(x: int): int {.
  axiomImpl
.} =
  x mod 3
{.pop.}
