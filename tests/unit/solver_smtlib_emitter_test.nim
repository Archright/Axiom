## Contract tests for SMT-LIB2 emitter (smtlib_emitter.nim).
##
## Verifies the output contract: SolverRequest → valid SMT-LIB2 string.
## Tests that the emitter produces well-formed SMT-LIB2 declarations,
## assertions, and commands matching the request's fields.
##
## DEBT#012 — solver/analyzer test coverage.

import std/unittest
import std/strutils
import core/solver/types
import core/solver/smtlib_emitter
import core/solver/construct_base
import core/solver/construct_arithmetic
import core/solver/construct_logical

# ─── emitSmt2 contracts ──────────────────────────────────────────────────

suite "emitSmt2 output contract":
  test "minimal request emits set-logic and check-sat":
    let req = SolverRequest(
      logic: logicQfLia,
      declarations: @[],
      preconditions: @[],
      assertions: @[],
      finalStateSymbol: "",
      checkSat: true,
      getModel: false,
      getUnsatCore: false
    )
    let output = emitSmt2(req)
    check output.contains("(set-logic QF_LIA)")
    check output.contains("(check-sat)")

  test "declarations emit declare-const for each symbol":
    let req = SolverRequest(
      logic: logicQfLia,
      declarations: @["x_0", "r1_1"],
      preconditions: @[],
      assertions: @[],
      finalStateSymbol: "x_0",
      checkSat: false,
      getModel: false,
      getUnsatCore: false
    )
    let output = emitSmt2(req)
    check output.contains("(declare-const x_0 Int)")
    check output.contains("(declare-const r1_1 Int)")

  test "assertions with arithmetic emit correct SMT-LIB2":
    let req = SolverRequest(
      logic: logicQfLia,
      declarations: @["x"],
      preconditions: @[],
      assertions: @[eq(symInt("x"), intLit(42))],
      finalStateSymbol: "x",
      checkSat: true,
      getModel: true,
      getUnsatCore: false
    )
    let output = emitSmt2(req)
    check output.contains("(assert (= x 42))")
    check output.contains("(get-model)")

  test "preconditions emit before assertions":
    let req = SolverRequest(
      logic: logicQfLia,
      declarations: @["x"],
      preconditions: @[ge(symInt("x"), intLit(0))],
      assertions: @[le(symInt("x"), intLit(100))],
      finalStateSymbol: "x",
      checkSat: true,
      getModel: false,
      getUnsatCore: false
    )
    let output = emitSmt2(req)
    let preconditionPos = output.find("(assert (>= x 0))")
    let assertionPos = output.find("(assert (<= x 100))")
    check preconditionPos >= 0
    check assertionPos >= 0
    check preconditionPos < assertionPos

  test "getUnsatCore flag emits get-unsat-core command":
    let req = SolverRequest(
      logic: logicQfLia,
      declarations: @[],
      preconditions: @[],
      assertions: @[],
      finalStateSymbol: "",
      checkSat: false,
      getModel: false,
      getUnsatCore: true
    )
    let output = emitSmt2(req)
    check output.contains("(get-unsat-core)")

  test "complex expression with ite emits correctly":
    let cond = ge(symInt("x"), intLit(10))
    let thenBranch = sub(symInt("x"), intLit(10))
    let elseBranch = symInt("x")
    let req = SolverRequest(
      logic: logicQfLia,
      declarations: @["x"],
      preconditions: @[],
      assertions: @[eq(symInt("y"), ite(cond, thenBranch, elseBranch))],
      finalStateSymbol: "y",
      checkSat: true,
      getModel: false,
      getUnsatCore: false
    )
    let output = emitSmt2(req)
    check output.contains("(ite (>= x 10) (- x 10) x)")

  test "logical connectives emit correctly":
    let req = SolverRequest(
      logic: logicQfLia,
      declarations: @["a", "b"],
      preconditions: @[],
      assertions: @[andE(@[ge(symInt("a"), intLit(0)), le(symInt("b"), intLit(10))])],
      finalStateSymbol: "a",
      checkSat: true,
      getModel: false,
      getUnsatCore: false
    )
    let output = emitSmt2(req)
    check output.contains("(and (>= a 0) (<= b 10))")
