# NIMTRY TEST FIXTURE — Canonical DRY violation (Part B)
#
# This fixture defines an exported function that is semantically equivalent
# to the one in canonical_dry_violation_a.nim, but uses different syntax:
#   - Uses `not (a > b)` instead of `a > b` with swapped branches
#   - Uses `b + a` and `a + b` in swapped order
#
# After canonical normalization (commutative operator sorting and
# not-branch normalization), the AST fingerprints should match,
# triggering a cross-file DRY violation.

func calculateTotal*(a, b: int): int =
  let x = a
  let y = b
  let z = a
  let sum = a + b
  let prod = a * b
  if not (a > b):
    return b + a
  else:
    return a + b
