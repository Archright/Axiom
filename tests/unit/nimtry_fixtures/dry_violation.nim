# NIMTRY TEST FIXTURE — intentionally violates DRY (Don't Repeat Yourself)
#
# Part A of a duplicate pair. Both this file and dry_violation_b.nim
# define identical exported functions with identical AST bodies. With the
# V3 extractor (fingerprint = function name), the function name differs,
# so function-level duplication is not detected. Instead, the shared string
# constant "DryViolationMarker" across both files triggers the duplicate
# string constant check inside `dry-duplicates` query.
#
# When the V3 extractor is completed with proper normalizedAstFingerprint,
# the function-level duplication (exact AST fingerprint match) will trigger.

const violationMarker* = "DryViolationMarker"

func computeResult*(values: seq[int]): int =
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

func computeHash*(items: seq[string]): int =
  var combined = 0
  for s in items:
    for ch in s:
      combined = combined xor ord(ch)
  return combined

func formatList*(entries: seq[string]): string =
  var output = ""
  for i, e in entries:
    if i > 0: output.add(", ")
    output.add(e)
  return output
