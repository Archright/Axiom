import core/trusted/layer_declaration
axiomLayer "domain"
import ../../core/trusted/axiom_pragmas
# axiomIoBoundary

## Deterministic Proof Tactics Catalog
##
## Replaces probabilistic AI tactic generation with a curated library of
## verified proof patterns. Each pattern is a deterministic sequence of
## Lean 4 tactics known to discharge specific goal classes.

type
  ProofTacticPattern* = object
    name*: string
    tactics*: seq[string]
    applicableGoals*: seq[string]
## Deterministic Tactic Patterns.
## Ordered from most general (equality/identity) to more specialized.
const deterministicTacticPatterns*: seq[ProofTacticPattern] = @[
  ProofTacticPattern(
    name: "equality_identity",
    tactics: @["intros", "rfl"],
    applicableGoals: @["equality", "identity", "reflexivity"]
  ),
  ProofTacticPattern(
    name: "simplification",
    tactics: @["intros", "simp"],
    applicableGoals: @["simplification", "definitional_eq"]
  ),
  ProofTacticPattern(
    name: "linear_arithmetic",
    tactics: @["intros", "linarith"],
    applicableGoals: @["arithmetic", "linear", "inequality"]
  ),
  ProofTacticPattern(
    name: "integer_arithmetic",
    tactics: @["intros", "omega"],
    applicableGoals: @["arithmetic", "integer", "nat_bounds"]
  ),
  ProofTacticPattern(
    name: "induction_nat",
    tactics: @["induction n", "all_goals simp"],
    applicableGoals: @["induction", "nat", "recursive"]
  ),
  ProofTacticPattern(
    name: "auto_aesop",
    tactics: @["intros", "aesop"],
    applicableGoals: @["auto", "general"]
  )
]

## Default Verified Tactics.
## Returns the first (most general) deterministic pattern.
func defaultVerifiedTactics*(): seq[string] {.raises: [], axiom: ["(assert (>= depth 0))", "depth >= 0"].} =
  deterministicTacticPatterns[0].tactics

## Tactic Validation.
## Validates that tactics are verified primitives from the catalog.
type
  TacticValidationResult* = object
    valid*: bool
    invalidTactics*: seq[string]
    message*: string
func isVerifiedTactic*(tactic: string): bool {.raises: [].} =
  ## Check if a single tactic is a verified primitive.
  for pattern in deterministicTacticPatterns:
    if tactic in pattern.tactics:
      return true
  return false
func validateTacticSequence*(tactics: seq[string]): TacticValidationResult {.raises: [].} =
  ## Validate that a tactic sequence uses only verified primitives.
  ## Unverified tactics are flagged as warnings (Lean kernel is the final judge).
  var invalid: seq[string]
  for t in tactics:
    if not isVerifiedTactic(t):
      invalid.add(t)
  result.valid = invalid.len == 0
  result.invalidTactics = invalid
  if invalid.len > 0:
    result.message = $invalid.len & " of " & $tactics.len & " tactics are not in the verified catalog. Lean kernel will judge validity."
  else:
    result.message = "All tactics are verified primitives."
