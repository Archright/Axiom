## Contract tests for Z3 result parser (z3_result_parser.nim).
##
## Tests the public I/O contracts:
##   - parseStatusLine: raw stdout → SolverStatus
##   - normalizeBindingValue: raw Z3 value → normalized string
##   - parseModelBindings: raw model block → seq[SolverBinding]
##   - parseUnsatCore: raw unsat-core s-expression → seq[string]
##   - parseSolverStdout: full stdout → Result[SolverBridgeResult, SymbolicFailure]
##
## DEBT#012 — solver/analyzer test coverage.

import std/unittest
import std/options
import core/types/domain_types
import core/types/results
import core/solver/types
import core/solver/z3_result_parser

# ─── parseStatusLine contracts ────────────────────────────────────────────

suite "parseStatusLine contract":
  test "single 'sat' line returns solverSat":
    check parseStatusLine("sat\n") == solverSat

  test "single 'unsat' line returns solverUnsat":
    check parseStatusLine("unsat\n") == solverUnsat

  test "single 'unknown' line returns solverUnknown":
    check parseStatusLine("unknown\n") == solverUnknown

  test "empty output returns solverUnknown":
    check parseStatusLine("") == solverUnknown

  test "whitespace-only returns solverUnknown":
    check parseStatusLine("   \n  \n  ") == solverUnknown

  test "sat with surrounding text extracts correctly":
    check parseStatusLine("some preamble\nsat\n(model ...)\n") == solverSat

  test "two status lines: the FIRST response wins (unsat then sat)":
    check parseStatusLine("unsat\nsat\n") == solverUnsat

  test "two status lines: the FIRST response wins (unsat then unsat)":
    check parseStatusLine("unsat\nunsat\n") == solverUnsat

  test "two status lines: the FIRST response wins (sat then unsat)":
    check parseStatusLine("sat\nunsat\n") == solverSat

  test "two status lines: the FIRST response wins (sat then sat)":
    check parseStatusLine("sat\nsat\n") == solverSat

# ─── normalizeBindingValue contracts ──────────────────────────────────────

suite "normalizeBindingValue contract":
  test "empty string returns empty":
    check normalizeBindingValue("") == ""

  test "integer literal preserved":
    check normalizeBindingValue("42") == "42"

  test "negative integer preserved":
    check normalizeBindingValue("(- 5)") == "-5"

  test "boolean true preserved":
    check normalizeBindingValue("true") == "true"

  test "boolean false preserved":
    check normalizeBindingValue("false") == "false"

  test "bitvector (_ bv10 32) extracts to decimal 10":
    check normalizeBindingValue("(_ bv10 32)") == "10"

  test "bitvector (_ bv0 8) extracts to 0":
    check normalizeBindingValue("(_ bv0 8)") == "0"

  test "negative parenthesized with nested parens extracts":
    check normalizeBindingValue("(- 123)") == "-123"

# ─── parseModelBindings contracts ─────────────────────────────────────────

suite "parseModelBindings contract":
  test "single define-fun block extracted":
    let raw = "(define-fun x () Int\n  42)"
    let bindings = parseModelBindings(raw)
    check bindings.len == 1
    check bindings[0].name == "x"
    check bindings[0].value == "42"

  test "two define-fun blocks extracted":
    let raw = "(define-fun x () Int\n  10)\n(define-fun y () Int\n  20)"
    let bindings = parseModelBindings(raw)
    check bindings.len == 2
    check bindings[0].name == "x"
    check bindings[0].value == "10"
    check bindings[1].name == "y"
    check bindings[1].value == "20"

  test "empty input returns empty bindings":
    let bindings = parseModelBindings("")
    check bindings.len == 0

  test "non-model text returns empty bindings":
    let bindings = parseModelBindings("sat\nunsat\n")
    check bindings.len == 0

# ─── parseUnsatCore contracts ─────────────────────────────────────────────

suite "parseUnsatCore contract":
  test "single s-expression with items extracts names":
    let raw = "unsat\n(assumption1 assumption2)"
    let core = parseUnsatCore(raw)
    check core.len == 2
    check core[0] == "assumption1"
    check core[1] == "assumption2"

  test "no s-expression at end returns empty":
    let raw = "unsat\n"
    let core = parseUnsatCore(raw)
    check core.len == 0

  test "model block is skipped":
    let raw = "unsat\n(model (define-fun x () Int 0))"
    let core = parseUnsatCore(raw)
    check core.len == 0

# ─── parseSolverStdout contracts ──────────────────────────────────────────

suite "parseSolverStdout contract":
  test "unsat returns ok with unsat evidence":
    let raw = "unsat\n"
    let result = parseSolverStdout(raw, "(set-logic QF_LIA)")
    check result.isOk
    check result.get().evidence.status == solverUnsat
    check result.get().evidence.solverName == "z3"

  test "empty stdout returns err parse failure":
    let result = parseSolverStdout("", "(set-logic QF_LIA)")
    check result.isErr
    check result.error().code == axiomErrSolverParseFailure

  test "sat with model returns err with counter-example":
    let raw = "sat\n(define-fun x () Int\n  42)"
    let result = parseSolverStdout(raw, "(set-logic QF_LIA)")
    check result.isErr
    check result.error().code == axiomErrSolverSatCounterExample
    check result.error().counterExample.isSome
    check result.error().counterExample.get().bindings.len > 0

  test "unknown returns err":
    let raw = "unknown\n"
    let result = parseSolverStdout(raw, "(set-logic QF_LIA)")
    check result.isErr
    check result.error().code == axiomErrSolverUnknown

  test "unsat then sat is one invocation's first response, not a vacuity signal":
    let raw = "unsat\nsat\n"
    let result = parseSolverStdout(raw, "(set-logic QF_LIA)")
    check result.isOk
    check result.get().evidence.status == solverUnsat
