import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.pragma: axiomPure.}
{.push noSideEffect.}

## Tautology Prover
## Wave D: Generates Lean 4 proof scripts for type-system-level tautologies.
## Constraints like str.len >= 0, seq.len >= 0, int-range bounds are
## automatically provable via simpa, omega, or exact tactics.

import std/strutils

# ---------------------------------------------------------------------------
# Tautology Proof Generation
# ---------------------------------------------------------------------------

## Build Tautology Proof.
func buildTautologyProof*(smtParts: seq[string]; leanParts: seq[string]): string {.raises: [].} =
  ## Generate a Lean 4 proof script that proves all tautological constraints.
  ##
  ## Strategy selection (in order of preference):
  ##   1. exact h_sys — when the proposition exactly matches the hypothesis
  ##   2. simpa — when constraints are standard library theorems
  ##   3. omega — when constraints involve linear arithmetic
  ##   4. refine by ... — structured proof with field reasonings
  ##
  ## For tautology proofs, the hypothesis `h_sys` already contains the
  ## conjunction of all trivial constraints. Since they are type-system
  ## guarantees, `simpa` suffices in virtually all cases.
  result = "  simpa using h_sys\n"

## Build Tautology Proof With Hint.
func buildTautologyProofWithHint*(prop: string; smtConstraint: string): string {.raises: [].} =
  ## Generate a Lean 4 proof tailored to the specific constraint type.
  let s = smtConstraint.toLowerAscii()
  let p = prop.toLowerAscii()

  # Trivial range bounds (int >= minInt64 etc.) → simpa
  if s.contains("-9223372036854775808") or s.contains("9223372036854775807"):
    return "  have h_range : (Int.minValue..Int.maxValue : Set Int) := by\n" &
           "    simp [Int.minValue, Int.maxValue]\n" &
           "  simpa [h_range] using h_sys\n"

  # Length/size non-negativity → simpa (Nat guarantees >= 0)
  if s.contains("str.len") or s.contains("seq.len") or p.contains(".length") or p.contains(".size"):
    if not (s.contains("(> ") or s.contains("(< ") or s.contains("(= ") or s.contains("(!=")):
      # Pure non-negativity: str.len >= 0 — Nat property
      return "  simpa using h_sys\n"

  # Depth constraints → simpa
  if s == "(>= depth 0)" or p == "depth >= 0":
    return "  simpa using h_sys\n"

  # Default: simpa works for most simple conjunctions
  "  simpa using h_sys\n"

# Re-export tautology checker for backward compatibility
import core/judge/tautology_checker
export isTautologyConstraint

{.pop.}
{.pop.}
