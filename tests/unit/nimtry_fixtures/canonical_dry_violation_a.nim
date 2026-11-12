# NIMTRY TEST FIXTURE — Canonical DRY violation (Part A)
#
# This fixture defines an exported function that is semantically equivalent
# to the one in canonical_dry_violation_b.nim. After canonical normalization
# (commutative operator sorting and not-branch normalization), the AST
# fingerprints should match, triggering a DRY violation.
#
# Verification:
#   After PNode canonicalization, bin/nimtry should detect an exact AST
#   fingerprint duplicate between this file and canonical_dry_violation_b.nim.

func computeSum*(a, b: int): int =
  let x = a
  let y = b
  let z = a
  let sum = a + b
  let prod = a * b
  if a > b:
    return a + b
  else:
    return b + a
