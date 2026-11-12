import core/trusted/layer_declaration

## First response wins — one `(check-sat)` gets one ⟨check_sat_response⟩.
##
## `parseStatusLine` used to fall through to "last status wins" once a stdout
## carried two of them. A solver that answered `sat` and then printed `unsat`
## anywhere afterwards was therefore read as an obligation that does not hold,
## and the k-induction layer discharged on it. The stdout was never evidence of
## anything; the projection was the claim (AGENTS.md §0.9).

import core/api/axiom_api_verify
import core/solver/z3_result_parser
import core/trusted/solver_invocation
import core/types/domain_types
import core/types/results
import std/strutils

proc expect(cond: bool; msg: string) =
  if not cond:
    doAssert false, msg
  echo "  OK: " & msg

block:
  echo "=== 1. the two byte sequences that used to discharge a refused proof ==="
  ## base=[sat\nunsat\n] step=[unsat\n]: the base answer is `sat`, so the base
  ## obligation HAS a counter-example. Nothing after it can discharge it.
  let case1 = verifyKInductionBySolverOutput(3, 10, 1, "sat\nunsat\n", "unsat\n")
  expect(case1.isErr,
    "base=[sat\\nunsat\\n] step=[unsat\\n] is refused, not discharged")
  expect(case1.isErr() and case1.error().code == axiomErrSolverSatCounterExample,
    "the refusal is the counter-example the `sat` first response carried")

  ## base=[unsat\n] step=[sat\nunsat\n]: the step answer is `sat`.
  let case2 = verifyKInductionBySolverOutput(3, 10, 1, "unsat\n", "sat\nunsat\n")
  expect(case2.isOk() and case2.get().status == "sat",
    "base=[unsat\\n] step=[sat\\nunsat\\n] reports sat, never proved")
  expect(case2.isOk() and not case2.get().inductionProved,
    "base=[unsat\\n] step=[sat\\nunsat\\n] sets inductionProved=false")
  expect(case2.isOk() and case2.get().hasCounterExample,
    "base=[unsat\\n] step=[sat\\nunsat\\n] keeps the counter-example visible")

block:
  echo "=== 2. an observed discharge is still a discharge ==="
  ## The fix is not "suspicious stdout loses its proof": base∧step both answered
  ## `unsat` still discharges, because that is what the responses actually said.
  let genuine = verifyKInductionBySolverOutput(3, 10, 1, "unsat\n", "unsat\n")
  expect(genuine.isOk() and genuine.get().status == "proved",
    "base=[unsat\\n] step=[unsat\\n] still discharges")
  expect(genuine.isOk() and genuine.get().inductionProved,
    "a genuinely unsat conjunction still sets inductionProved=true")

block:
  echo "=== 3. parseStatusLine reads the first top-level response ==="
  expect(parseStatusLine("sat\n") == solverSat, "a bare sat is sat")
  expect(parseStatusLine("unsat\n") == solverUnsat, "a bare unsat is unsat")
  expect(parseStatusLine("unknown\n") == solverUnknown, "a bare unknown is unknown")
  expect(parseStatusLine("") == solverUnknown, "an empty stdout is unknown")
  expect(parseStatusLine("   \n \n") == solverUnknown, "whitespace alone is unknown")
  expect(parseStatusLine("sat\nunsat\n") == solverSat,
    "sat then unsat is sat — first response wins")
  expect(parseStatusLine("unsat\nsat\n") == solverUnsat,
    "unsat then sat is unsat — first response wins")
  expect(parseStatusLine("unsat\nunsat\nunsat\n") == solverUnsat,
    "a repeated unsat is still one unsat")
  expect(parseStatusLine("unknown\nunsat\n") == solverUnknown,
    "unknown then unsat is unknown — first response wins")

block:
  echo "=== 4. elaboration around the answer is not the answer ==="
  expect(parseStatusLine("Z3 version 4.13.3\nsat\nsat\n") == solverSat,
    "a banner line before the response is skipped, and the response is sat")
  expect(parseStatusLine("(set-logic QF_LIA)\nsat\n(model (define-fun x () Int 0))\n") == solverSat,
    "an echoed command and a model payload do not displace the sat response")
  expect(parseStatusLine("(error \"line 5: unexpected token unsat\")\nunsat\n") == solverUnknown,
    "an error form outranks any later verdict: Z3 emits (error …) only alongside a non-zero exit, so a response printed after one is not a decision — the quoted `unsat` is still not itself a response either")
  expect(parseStatusLine("(error \"unsat\")\n") == solverUnknown,
    "an error-only stdout is unknown, never unsat")
  expect(parseStatusLine("(error \"unsat\")\n(:reason-unknown aborted)\n") == solverUnknown,
    "an error plus an unknown reason is unknown, however many times `unsat` is quoted")
  expect(parseStatusLine("unsat\n(unsat-core u1 u2)\n") == solverUnsat,
    "an unsat-core s-expression after the response is elaboration")
  expect(parseStatusLine("unsat\n(\n  unsat\n  (let ((x!1 0)) x!1)\n)\n") == solverUnsat,
    "a bare `unsat` line nested in a (get-proof …) payload is not a response")
  expect(parseStatusLine("(proof\nunsat\n)\nsat\n") == solverSat,
    "a response printed after a multi-line proof payload is still the response")

block:
  echo "=== 5. the parser reuses the shared classifier, it does not re-scan ==="
  ## One verdict rule, one implementation: if the two ever disagreed, a site
  ## could pick whichever suited it.
  expect(parseStatusLine("sat\nunsat\n") == solverSat,
    "z3_result_parser agrees with classifySolverVerdict on sat-then-unsat")
  expect(classifySolverVerdict("sat\nunsat\n") == svSat,
    "the shared classifier's own answer is the first response")
  expect(parseStatusLine("unsat\nsat\n") ==
      (case classifySolverVerdict("unsat\nsat\n")
       of svSat: solverSat
       of svUnsat: solverUnsat
       of svUnknown: solverUnknown),
    "the two classifications cannot drift apart")

block:
  echo "=== 6. no solver stdout can reach a discharge it was not given ==="
  ## `proved` is not in the response grammar; the bridge result carries only
  ## the three words SMT-LIB 2.7 §4.1.7 fixes. None of these stdouts contains an
  ## `unsat` response, so none may produce unsat evidence.
  for hostile in [
      "sat\nunsat\n", "sat\nsat\nunsat\nunsat\n", "sat\nunsat\nunsat\n",
      "(error \"unsat\")\nsat\n", "sat\n(error \"unsat\")\n",
      "sat\n(unsat-core unsat)\n", "sat\n(\n  unsat\n)\n",
      "(error \"line 5: unexpected token unsat\")\nsat\nunsat\n"]:
    let parsed = parseSolverStdout(hostile, "(set-logic QF_LIA)")
    let observed = if parsed.isOk: $parsed.get().evidence.status
                   else: "err " & $parsed.error().code
    expect(parsed.isErr() or parsed.get().evidence.status != solverUnsat,
      "no unsat evidence from: " & hostile.replace("\n", "\\n") &
      " => " & observed)

echo "=== ALL z3_result_parser first-response tests PASSED ==="