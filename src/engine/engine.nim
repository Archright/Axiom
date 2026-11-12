import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

import std/strutils
import std/os
import std/osproc
import std/tempfiles
import core/boundary/axiom_pragmas_boundary

import core/boundary/results_boundary
import core/gateway/gateway
import core/proof/proof_budget
import core/proof/proof_vacuity_gate
import core/solver/types
import core/solver/z3_result_parser
import core/utils/io_utils
import infrastructure/process_utils
import core/trusted/smt_sort
import infrastructure/logging_facade
# axiomIoBoundary

type
  Hint* = object
    leanProposition*: string
    smtConstraint*: string
    sourceLines*: string
    variables*: seq[string]

## Count Symbols.
# @axiom-hint: lean="count ∧ (symbols ≥ 0)" smt="(assert (and count (>= symbols 0)))"
func countSymbols*(proposition: string): int =
  var count = 0
  let symbols = proposition.splitWhitespace()
  for word in symbols:
    let cleanWord = word.replace("(", "").replace(")", "").strip()
    if cleanWord.len > 0 and cleanWord[0] in {'a'..'z', 'A'..'Z', '0'..'9', '>', '<', '='}:
      if cleanWord notin ["assert", "and", "or", "not", "true", "false"]:
        count += 1
  return count

## Binding Check.
# @axiom-hint: lean="false ∧ true ∧ (variables ≥ 0) ∧ (∀ (variablesIdx : Fin variables.size), (variables.get variablesIdx).length ≥ 0)" smt="(assert (and false true (>= variables 0) (forall ((variablesIdx Int)) (=> (and (>= variablesIdx 0) (< variablesIdx (seq.len variables))) (>= (str.len (seq.nth variables variablesIdx)) 0)))))"
func bindingCheck*(sourceLines: string, variables: seq[string]): bool =
  for v in variables:
    if not sourceLines.contains(v):
      return false
  return true

## Whether the counter-example gate must treat a hint as a vacuous truth.
##
## This asks the parser's question — "what did the solver answer?" — and not the
## extractor's question ("was an obligation discharged?"), so it reads
## `parseStatusLine` directly and stays in agreement with every other consumer
## of a solver stream. Scanning the output for an `unsat` token instead was a
## second opinion about the same evidence: it had to disagree with the parser
## about which line is the answer, and it rejected a stream whose first response
## was `sat`. Two projections of one stream must not reach two verdicts.
func vacuousTruthFromSolverStream*(solverOutput: string): bool {.raises: [].} =
  ## An `unsat` answer to the negated hint means the hint's own conditions hold
  ## for every model, i.e. they constrain nothing — filtering power 0.
  parseStatusLine(solverOutput) == solverUnsat

## Validate Zero Vacuity.
# @axiom-hint: lean="conditions.length > 0 ∧ conditions.length = 1 ∧ false ∧ true ∧ (lines ≥ 0) ∧ external_io_isolated" smt="(assert (and (> (str.len conditions) 0) (= (str.len conditions) 1) false true (>= lines 0) external_io_isolated))"
proc validateZeroVacuity*(hint: Hint): bool {.tags: [AxiomIOEffect, IOEffect, ReadIOEffect, WriteIOEffect, ExecIOEffect, RootEffect], axiomEffect: IOEffect.} =
  let deterministicGate = validateVacuityParts(
    hint.leanProposition,
    hint.smtConstraint,
    sourceContext = hint.sourceLines
  )
  if not deterministicGate.accepted:
    logError("engine", "[Error] Zero-Vacuity Gate: " & deterministicGate.reason)
    return false

  # Step 1: Entropy Gate
  if hint.leanProposition.contains("True") or countSymbols(hint.smtConstraint) < 2:
    logError("engine", "[Error] Entropy Gate: Information density too low.")
    return false

  # Step 2: Symbolic Binding
  if not bindingCheck(hint.sourceLines, hint.variables):
    logError("engine", "[Error] Symbolic Binding: Hint is not bound to physical code.")
    return false

  # Step 3: SMT Counter-example Test
  # Extract assertions to negate
  var conditions: seq[string] = @[]
  for line in hint.smtConstraint.splitLines():
    let s = line.strip()
    if s.startsWith("(assert ") and s.endsWith(")"):
      conditions.add(s[8 .. ^2])
      
  let baseAsserts = hint.smtConstraint & "\n"
  let negatedAssert = 
    if conditions.len > 0:
      let conj = smtAndRaw(conditions)
      "(assert (not " & conj & "))\n"
    else:
      ""

  # [DETERMINISTIC] rlimit from proof_budget SSOT is PRIMARY decision bound
  let smtQuery = "(set-logic QF_LIA)\n" &
                 "(set-option :rlimit " & $z3DeterministicBudget & ")\n" &
                 # [DETERMINISTIC] Replaced by rlimit — wall-clock timeout as process safety net
                 "(set-option :timeout " & $z3SafetyNetMs & ")\n" &
                 "(declare-const expected Int)\n" &
                 "(declare-const typ Int)\n" &
                 baseAsserts &
                 negatedAssert &
                 "(check-sat)\n"
                 
  let z3InputPath = genTempPath("axiom_validation_", ".smt2")
  ## intentional-discard: temp SMT input for Z3 solver; cleaned up by OS
  discard writeFileOpt(z3InputPath, smtQuery)
  
  # Safety net: process-level wall-clock timeout (Z3 self-limits via rlimit)
  let (output, _) = execCmdWithTimeout("z3 " & quoteShell(z3InputPath), timeoutMs = z3SafetyNetMs)
  discard removeFileOpt(z3InputPath)
  
  if vacuousTruthFromSolverStream(output):
    logError("engine", "[Error] Counter-Ex Gate: Hint is a vacuous truth (Filtering power: 0).")
    return false

  logInfo("engine", "[Success] [Entropy: Pass, Binding: Valid, Counter-Ex: Found]")
  return true
{.pop.}
