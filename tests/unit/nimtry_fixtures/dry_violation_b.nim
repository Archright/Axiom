# NIMTRY TEST FIXTURE — intentionally violates DRY (Don't Repeat Yourself)
#
# Part B of a duplicate pair. Shares the string constant "DryViolationMarker"
# with dry_violation.nim, triggering the duplicate string constant check.
# Also defines identical exported functions with AST bodies identical to
# those in dry_violation.nim — these would trigger exact-AST-fingerprint
# DRY when the V3 extractor properly computes normalizedAstFingerprint.
#
# Verification: bin/nimtry tests/unit/nimtry_fixtures/dry_violation.nim \
#                   tests/unit/nimtry_fixtures/dry_violation_b.nim
# Expected: FAILED with at least one [DRY] or [SSOT] violation

const violationMarker* = "DryViolationMarker"

func computeResults*(values: seq[int]): int =
  var total = 0
  for v in values:
    total = total + v
  if total > 100:
    total = total div 2
  elif total < 0:
    total = 0
  else:
    discard
  return total

func computeHashes*(items: seq[string]): int =
  var combined = 0
  for s in items:
    for ch in s:
      combined = combined xor ord(ch)
  return combined

func formatItems*(entries: seq[string]): string =
  var output = ""
  for i, e in entries:
    if i > 0: output.add(", ")
    output.add(e)
  return output
