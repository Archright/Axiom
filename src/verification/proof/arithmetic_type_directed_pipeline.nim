## Arithmetic Type-Directed Proof Pipeline
##
## End-to-end pipeline for pure arithmetic Nim functions:
##   1. Extract the function source span from the AST.
##   2. Parse it into an `ArithmeticFunction` (no text/template guessing).
##   3. Generate a function-specific SMT-LIB2 query and verify with Z3.
##   4. Generate a function-specific Lean 4 theorem and verify with `lean`.
##   5. Return all evidence so the caller can write a deep-verified certificate.

import core/trusted/layer_declaration
axiomLayer "infrastructure"
import std/options
import core/results
import core/proof/function_source_extractor
import core/encoding/smt_to_lean/private/arithmetic_expr
import core/encoding/smt_to_lean_translate
import core/judge/lean_replay
import verification/solver/triviality_filter
import core/axiom_pragmas
# axiomIoBoundary

type
  ArithmeticProofResult* = object
    verified*: bool
    smtlib2*: string
    leanSource*: string
    z3Output*: string
    leanResult*: LeanReplayResult
    reason*: string


proc replayArithmeticLeanProof(
  nodeId, smt2, leanSource, z3Output: string
): Result[ArithmeticProofResult, string] {.raises: [], axiomEffect: IOEffect, tags: [RootEffect, TimeEffect, AxiomIOEffect, IOEffect].} =
  ## Replay an arithmetic theorem through the Lean 4 kernel.
  let leanRes = lean_replay.runLeanReplay(nodeId, leanSource)
  if leanRes.isErr():
    return ok(ArithmeticProofResult(
      verified: false,
      smtlib2: smt2,
      leanSource: leanSource,
      z3Output: z3Output,
      reason: "Lean replay error: " & leanRes.error()
    ))
  let lean = leanRes.get()
  if not lean.isValid:
    return ok(ArithmeticProofResult(
      verified: false,
      smtlib2: smt2,
      leanSource: leanSource,
      z3Output: z3Output,
      leanResult: lean,
      reason: "Lean compiler rejected theorem: " & lean.compilerStderr
    ))
  ok(ArithmeticProofResult(
    verified: true,
    smtlib2: smt2,
    leanSource: leanSource,
    z3Output: z3Output,
    leanResult: lean,
    reason: "Z3 unsat + Lean kernel verified"
  ))

proc runArithmeticTypeDirectedProof*(
  nodeId, sourceCode, modulePath, functionName: string
): Result[ArithmeticProofResult, string] {.raises: [], axiomEffect: IOEffect, tags: [RootEffect, TimeEffect, AxiomIOEffect, IOEffect].} =
  ## Attempt a type-directed proof for a single arithmetic function.
  ## Returns `verified = true` only when both Z3 and Lean confirm the goal.
  let snippetOpt = extractFunctionSource(sourceCode, functionName)
  if snippetOpt.isNone():
    return err("function source not found in AST: " & functionName)
  let snippet = snippetOpt.get()
  if not isArithmeticFunction(snippet):
    return err("not a supported arithmetic function: " & functionName)
  let fnOpt = parseArithmeticFunction(snippet)
  if fnOpt.isNone():
    return err("failed to parse arithmetic function: " & functionName)
  let fn = fnOpt.get()
  let smt2 = generateSmtLib2(fn)
  let validity = checkSmtValidity(smt2)
  if validity.verdict != tvNonTrivial:
    return ok(ArithmeticProofResult(
      verified: false,
      smtlib2: smt2,
      reason: "Z3 triviality/validity check failed: " & validity.errorMessage
    ))
  let leanSource = generateLeanTheorem(fn)
  replayArithmeticLeanProof(nodeId, smt2, leanSource, validity.z3Output)
