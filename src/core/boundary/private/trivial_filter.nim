import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [], tags: [].}

import std/strutils
{.push raises: [].}
# axiomIoBoundary

func isTrivialConstraint*(smt, lean: string): bool {.raises: [].} =
  ## Determine if a constraint pair is a trivial tautology with no semantic value.
  ## Extracted from extractBoundaries for reuse and testability.
  let s = smt.toLowerAscii()
  let l = lean.toLowerAscii()
  # Non-trivial: depth guard (used for zero-param tautologies)
  if s == "(>= depth 0)" or l == "depth >= 0":
    return false
  # Trivial: integer overflow bounds
  if s.contains("-9223372036854775808") or s.contains("9223372036854775807"):
    return true
  # Trivial: Nim-specific field accesses not valid in Lean 4
  if l.contains(".kind") or l.contains(".tag") or l.contains(".type") or l.contains(".value"):
    return true
  # Trivial: empty call expression generates invalid Lean syntax
  if l.contains(".()"):
    return true
  # Trivial: for-loop iteration conditions (type-system membership)
  if l.contains(" ∈ "):
    return true
  # Trivial: custom function calls with no recognized Lean semantics
  if l.endsWith(")") and l.contains("(") and not l.contains("∧") and
     not l.contains("∨") and not l.contains("¬") and not l.contains("=") and
     not s.contains(" > ") and not s.contains(" < ") and not s.contains(" = "):
    return true
  # Length/size constraints: trivial unless strict operators present
  if s.contains("str.len") or s.contains("seq.len") or l.contains(".length") or l.contains(".size"):
    if s.contains("(> ") or s.contains("(< ") or s.contains("(= ") or s.contains("(!=") or
       l.contains(" > ") or l.contains(" < ") or l.contains(" = ") or l.contains(" ≠ "):
      return false
    return true
  # Trivial: boolean literal tautologies
  if s == "true" or s == "false":
    return true
  false

func countNonTrivial*(smtParts, leanParts: seq[string]): int {.raises: [].} =
  ## Count non-trivial constraint pairs.
  for i in 0 ..< min(smtParts.len, leanParts.len):
    if not isTrivialConstraint(smtParts[i], leanParts[i]):
      inc result

func filterNonTrivialParts*(smtParts, leanParts: seq[string]):
    tuple[nonTrivialSmt, nonTrivialLean: seq[string]] {.raises: [].} =
  ## Filter out trivial constraints, keeping only semantically meaningful ones.
  var s: seq[string] = @[]
  var l: seq[string] = @[]
  for i in 0 ..< min(smtParts.len, leanParts.len):
    if not isTrivialConstraint(smtParts[i], leanParts[i]):
      s.add(smtParts[i])
      l.add(leanParts[i])
  (s, l)

{.pop.}

{.pop}
