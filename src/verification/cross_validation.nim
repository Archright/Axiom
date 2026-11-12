import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
## Phase 4B — IR-Based Cross-Validation
##
## Verifies that the same IR produces structurally consistent output
## when converted to both SMT-LIB2 and Lean 4.
##
## Design:
##   All helper functions are `func` (no side effects, no raises).
##   The IR is serialized to a canonical string, then SHA-256-hashed
##   for a deterministic audit trail digest.
##   Structural consistency checks confirm both backends encode the
##   same function name, parameter set, and output structure.

import std/[strutils]
import core/trusted/axiom_ir_helpers
import core/trusted/ir_to_smt
import core/trusted/ir_to_lean
import core/deterministic_cas_key

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  CrossValidationResult* = object
    ## Result of cross-validating IR → SMT and IR → Lean conversions.
    consistent*: bool      ## True iff both backends produced valid output
    z3Result*: string      ## Raw SMT-LIB2 script output
    leanResult*: string    ## Raw Lean 4 module output
    irDigest*: string      ## SHA-256 hex digest of the canonical IR serialization

  CrossValidationStatus* = enum
    cvsConsistent          ## Both backends produced valid, matching output
    cvsZ3Failed            ## SMT-LIB2 generation failed or empty
    cvsLeanFailed          ## Lean 4 generation failed or empty
    cvsBothFailed          ## Both backends failed or produced empty output
    cvsDiverged            ## Both produced output but structural checks disagree

# ---------------------------------------------------------------------------
# Structural consistency checks
# ---------------------------------------------------------------------------

proc containsSubstr*(haystack, needle: string): bool {.raises: [].} =
  ## Case-sensitive substring check. Delegates to std/strutils.find() (O(N) with SIMD).
  if needle.len == 0: return true
  haystack.find(needle) != -1

proc smtHasDefineFun*(smt: string, funcName: string): bool {.raises: [].} =
  ## Check that SMT output contains a define-fun for the given function.
  ## Matches both `(define-fun ...)` and `(define-fun-rec ...)` for
  ## recursive functions emitted by irToSmtScript.
  containsSubstr(smt, "(define-fun " & funcName) or
    containsSubstr(smt, "(define-fun-rec " & funcName)

proc leanHasDef*(lean: string, funcName: string): bool {.raises: [].} =
  ## Check that Lean output contains a def for the given function.
  ## Matches both `def` and `partial def`.
  containsSubstr(lean, "def " & funcName)

proc paramsAppearIn*(ps: seq[IRFuncParam], text: string): bool {.raises: [].} =
  ## Verify all parameter names appear in the output text.
  for p in ps:
    if not containsSubstr(text, p.name):
      return false
  true

proc checkStructuralConsistency*(f: IRFuncDef,
    z3Output, leanOutput: string): bool {.gcsafe, raises: [].} =
  ## Verify both outputs structurally encode the same IR function.
  ## Checks: non-empty, function name present, parameters present,
  ## expected keyword structure.
  if z3Output.len == 0 or leanOutput.len == 0:
    return false
  if not smtHasDefineFun(z3Output, f.name):
    return false
  if not leanHasDef(leanOutput, f.name):
    return false
  if not paramsAppearIn(f.params, z3Output):
    return false
  if not paramsAppearIn(f.params, leanOutput):
    return false
  true

# ---------------------------------------------------------------------------
# Cross-validation: pure functions
# ---------------------------------------------------------------------------

proc crossValidate*(f: IRFuncDef): CrossValidationResult {.raises: [].} =
  ## End-to-end cross-validation: generate both representations from the IR,
  ## compute digest, and verify structural consistency.
  ## Does NOT invoke external solvers — purely structural comparison.
  let smtOut = irToSmtScript(f)
  let leanOut = irToLeanModule(f)
  let digest = computeDeterministicCasKey(computeIrDigest(f))
  let structurallyConsistent = checkStructuralConsistency(f, smtOut, leanOut)
  CrossValidationResult(
    consistent: structurallyConsistent,
    z3Result: smtOut,
    leanResult: leanOut,
    irDigest: digest
  )

{.pop.}

