import core/trusted/layer_declaration

## The engine's counter-example gate and the parser must read one stream the
## same way.
##
## `validateZeroVacuity` kept its own second opinion: it scanned every line of
## the solver output for an `unsat` token, and it tested an error code
## (`axiomErrVacuousContradiction`) that `parseSolverStdout` can no longer
## emit. The result was that a stream whose FIRST response is `sat` was
## rejected as a vacuous truth while the parser read it as a counter-example —
## two projections of identical evidence reaching opposite conclusions
## (AGENTS.md §0.9). The gate now derives from `parseStatusLine`, the same rule
## every other consumer of a solver stream uses.

import core/solver/z3_result_parser
import core/types/solver_types
import engine/engine
import std/strutils

proc expect(cond: bool; msg: string) =
  if not cond:
    doAssert false, msg
  echo "  OK: " & msg

block:
  echo "=== 1. the gate agrees with the parser on the decisive streams ==="
  let decisive: seq[tuple[stream: string, label: string, vacuous: bool]] = @[
    (stream: "unsat\nsat\n", label: "unsat-then-sat", vacuous: true),
    (stream: "sat\nunsat\n", label: "sat-then-unsat", vacuous: false),
    (stream: "unsat\nunsat\n", label: "unsat-twice", vacuous: true),
    (stream: "sat\n", label: "sat", vacuous: false),
    (stream: "unknown\n", label: "unknown", vacuous: false),
    (stream: "", label: "empty", vacuous: false)
  ]
  for c in decisive:
    let parserStatus = parseStatusLine(c.stream)
    let vacuous = vacuousTruthFromSolverStream(c.stream)
    expect(vacuous == (parserStatus == solverUnsat),
      c.label & ": the gate reads the stream exactly as the parser does (" &
      $parserStatus & ")")
    expect(vacuous == c.vacuous,
      c.label & ": the gate's decision is the expected one")

block:
  echo "=== 2. the disagreement that existed is gone ==="
  ## `sat\nunsat\n` was rejected as a vacuous truth because the scan found the
  ## `unsat` on the second line. The first response is what the solver answered.
  let contradictory = "sat\nunsat\n"
  expect(parseStatusLine(contradictory) == solverSat,
    "the parser reads the first response")
  expect(not vacuousTruthFromSolverStream(contradictory),
    "the gate no longer rejects a stream the parser read as sat")

  let vacuousTruth = "unsat\nsat\n"
  expect(parseStatusLine(vacuousTruth) == solverUnsat,
    "the parser reads unsat first")
  expect(vacuousTruthFromSolverStream(vacuousTruth),
    "the gate agrees: the hint constrains nothing")

block:
  echo "=== 3. payload text is not a response ==="
  ## A model, an unsat core or an error payload can contain the token; the gate
  ## must not treat it as an answer.
  for payload in [
      "(model\n  (define-fun x () Int 0)\n)\n",
      "(error \"line 5: unknown constant 'unsat'\")\n",
      "s1\ns2\n",
      "(reason-unknown \"timeout\")\n",
      "Z3 version 4.13.3\n",
      "\n\n\n"]:
    expect(not vacuousTruthFromSolverStream(payload),
      "payload with no bare response is not a vacuous truth: " &
      payload.replace("\n", "|"))
    expect(vacuousTruthFromSolverStream(payload) ==
             (parseStatusLine(payload) == solverUnsat),
      "gate and parser agree on the payload: " & payload.replace("\n", "|"))

block:
  echo "=== 4. a single honest unsat is still a vacuous truth ==="
  ## Removing the second scan must not weaken the gate's actual purpose.
  expect(vacuousTruthFromSolverStream("unsat\n"),
    "one honest unsat still marks the hint vacuous")
  expect(vacuousTruthFromSolverStream("unsat\nsat\n"),
    "a contradicting stream whose first answer is unsat is still vacuous")
  expect(not vacuousTruthFromSolverStream("sat\n"),
    "a satisfiable negation is a hint with filtering power")
  expect(not vacuousTruthFromSolverStream(""),
    "an unreadable stream is not converted into a vacuity verdict")