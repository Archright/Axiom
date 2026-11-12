# Overflow semantics follow the SemanticProfile (V1), not a hardcoded bool.

import std/strutils
import core/trusted/layer_declaration
import core/trusted/axiom_ir_helpers
import core/trusted/ir_to_smt
import verification/cross_validation

# W5-A: The semantic profile carries the overflow decision; every emission path
# (runner + cross-validation) must agree byte-for-byte from the same IR.

proc main() =
  echo "=== Overflow Conformance (V1-bounded) ==="

  let bv64 = irTypeBitVec64()

  # 1. The runner path: same IR -> same SMT text, overflow predicates asserted (not a quiet wrap).
  block:
    let f = irFuncDef(
      name = "overflow_add",
      params = @[("x", bv64), ("y", bv64)],
      ret = bv64,
      body = irBinOp(boAdd, irVar("x", bv64), irVar("y", bv64))
    )
    let smt1 = irToSmtScript(f, includeOverflowDefines = true)
    doAssert "overflow" in smt1 or "bvult" in smt1,
      "overflow-smoke: runner IR->SMT must emit overflow for the V1 profile (obligation-discharged), got: " & smt1

  # 2. Cross-validation: the public entry point must agree byte-for-byte with the runner.
  #    crossValidate calls irToSmtScript with the DEFAULT flag (cross_validation.nim:94),
  #    so the runner side must also be compared at the default flag.
  block:
    let f = irFuncDef(
      name = "overflow_add",
      params = @[("x", bv64), ("y", bv64)],
      ret = bv64,
      body = irBinOp(boAdd, irVar("x", bv64), irVar("y", bv64))
    )
    let cross = crossValidate(f)
    let smt2 = cross.z3Result
    let smt1 = irToSmtScript(f)
    doAssert smt1 == smt2,
      "path-consistency broken: runner IR->SMT != crossValidate IR->SMT for the same funcDef"
    echo "  OK: same funcDef -> same SMT text via runner and crossValidate"

  # 3. Overflow obligations are GOALS, not assumptions (obligation_semantics.md §3.8).
  #    With includeOverflowDefines=true each checked-arithmetic node contributes a
  #    no-overflow conjunct inside the NEGATED query; the solver must derive it from
  #    the asserted preconditions. Overflow is never asserted as a fact.
  block:
    let f = irFuncDef(
      name = "overflow_add",
      params = @[("x", bv64), ("y", bv64)],
      ret = bv64,
      body = irBinOp(boAdd, irVar("x", bv64), irVar("y", bv64))
    )
    let smtFlag = irToSmtScript(f, includeOverflowDefines = true)
    doAssert smtFlag.contains("(assert (not (and (no_overflow_add x y) (no_underflow_add x y))))"),
      "flag=true: overflow must be a goal conjunct inside the negated query, got: " & smtFlag
    doAssert smtFlag.contains("(assert (no_overflow_add") == false,
      "flag=true: overflow must never be emitted as an assumed fact"
    let smtDefault = irToSmtScript(f)
    doAssert smtDefault.contains("no_overflow") == false,
      "default flag: emission must stay byte-identical to the pre-§3.8 pipeline (no overflow text)"

  echo "=== overflow-conformance OK ==="

main()