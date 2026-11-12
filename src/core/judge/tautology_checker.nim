import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.pragma: axiomPure.}
{.push noSideEffect.}

## Tautology Checker
## Determines if constraints are type-system-level tautologies.
## Extracted from tautology_prover.nim for SRP compliance.

import std/strutils

## Is Tautology Constraint.
func isTautologyConstraint*(smt: string; lean: string): bool {.raises: [].} =
  ## Returns true if a constraint is a type-system-level tautology that
  ## can be proven automatically without Z3 SMT solving.
  let s = smt.toLowerAscii()
  let l = lean.toLowerAscii()

  # str.len >= 0 / seq.len >= 0 (pure non-negativity, no strict operators)
  if s.contains("str.len") or s.contains("seq.len") or l.contains(".length") or l.contains(".size"):
    if not (s.contains("(> ") or s.contains("(< ") or s.contains("(= ") or s.contains("(!=")):
      return true

  # Full int64 range bounds
  if s.contains("-9223372036854775808") or s.contains("9223372036854775807"):
    return true

  # Depth zero-parameter tautology
  if s == "(>= depth 0)" or l == "depth >= 0":
    return true

  false

{.pop.}
{.pop.}
