## Solver-Assisted Triviality Filter
##
## Replaces the heuristic pre-sieve (E >= 0.5 energy score) with a logical
## discriminator: a verification condition is handed to Z3, and only goals
## that are genuinely non-trivial and valid are promoted to the proof pipeline.
##
## The filter does **not** decide validity by text matching.  It calls the
## solver, interprets the result, and rejects:
##   - `sat`       → counter-example exists (property is false)
##   - `unknown`   → solver cannot decide
##   - errors/timeouts → pipeline cannot obtain evidence
## Only `unsat` means the negated VC is unsatisfiable, i.e. the property is
## valid and worth a real proof attempt.

import core/trusted/layer_declaration
axiomLayer "infrastructure"
import std/strutils
import core/results
import core/solver/types
import core/axiom_pragmas
import core/encoding/smt_to_lean_translate
import verification/solver/z3_pool
# axiomIoBoundary

type
  TrivialityVerdict* = enum
    tvTrivial      ## Goal is trivially true / false / vacuous — do not prove
    tvNonTrivial   ## Goal is valid and non-trivial — proceed to proof
    tvUnknown      ## Solver could not decide — skip this node
    tvError        ## Solver error or malformed query — skip this node

  ValidityCheckResult* = object
    verdict*: TrivialityVerdict
    solverStatus*: SolverStatus
    z3Output*: string
    errorMessage*: string

const TrivialityTimeoutMs = 10_000

func detectVacuousContradiction(smt2: string): bool {.raises: [].} =
  ## Fast syntactic guard against the old bug where both `P` and `not P`
  ## were asserted, making the query trivially contradictory.
  let stripped = smt2.strip().toLowerAscii()
  if "(assert (= result " in stripped and "(assert (not (= result " in stripped:
    return true
  false

proc checkSmtValidity*(smt2: string): ValidityCheckResult {.raises: [], axiomEffect: IOEffect, tags: [RootEffect, TimeEffect, AxiomIOEffect, IOEffect].} =
  ## Run Z3 on `smt2` and classify the verification condition.
  if smt2.len == 0:
    return ValidityCheckResult(verdict: tvError, solverStatus: solverUnknown,
                               z3Output: "", errorMessage: "empty smt2 query")
  if detectVacuousContradiction(smt2):
    return ValidityCheckResult(verdict: tvTrivial, solverStatus: solverUnknown,
                               z3Output: "", errorMessage: "vacuous contradiction detected")

  var cd, td: string
  let z3res = z3ExecPersistent(smt2, TrivialityTimeoutMs, desiredWorkers = 1,
                               queryType = "triviality_filter",
                               canonicalEnvelopeDigest = cd, transportPayloadDigest = td)
  if z3res.isErr():
    return ValidityCheckResult(verdict: tvError, solverStatus: solverUnknown,
                               z3Output: "", errorMessage: z3res.error())

  let output = z3res.get()
  let status = z3OutputToSolverStatus(output)
  case status
  of solverUnsat:
    ValidityCheckResult(verdict: tvNonTrivial, solverStatus: status, z3Output: output)
  of solverSat:
    ValidityCheckResult(verdict: tvTrivial, solverStatus: status, z3Output: output,
                        errorMessage: "counter-example exists")
  of solverTimeout:
    ValidityCheckResult(verdict: tvUnknown, solverStatus: status, z3Output: output,
                        errorMessage: "solver timeout")
  else:
    ValidityCheckResult(verdict: tvUnknown, solverStatus: status, z3Output: output,
                        errorMessage: "solver returned " & $status)
