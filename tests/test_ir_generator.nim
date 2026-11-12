import std/[unittest, strutils, strformat, options]
import core/ir/ir_types
import core/ir/ir_to_lean

suite "IR Generator — Refinement Type & Subtype":

  test "renderIRExpr — ieVar":
    let e = IRExpr(kind: ieVar, varName: "x")
    check renderIRExpr(e) == "x"

  test "renderIRExpr — keyword ieVar":
    let e = IRExpr(kind: ieVar, varName: "result")
    check renderIRExpr(e) == "«result»"

  test "renderIRExpr — ieConst":
    let e = IRExpr(kind: ieConst, val: "42")
    check renderIRExpr(e) == "42"

  test "renderIRExpr — ieBinaryOp":
    let e = IRExpr(kind: ieBinaryOp,
      left: IRExpr(kind: ieVar, varName: "a"),
      op: "+",
      right: IRExpr(kind: ieConst, val: "1"))
    check renderIRExpr(e) == "(a + 1)"

  test "renderIRExpr — ieApp":
    let e = IRExpr(kind: ieApp, fnName: "f",
      args: @[IRExpr(kind: ieVar, varName: "x")])
    check renderIRExpr(e) == "f x"

  test "renderIRExpr — ieRefinement":
    let pred = IRExpr(kind: ieBinaryOp,
      left: IRExpr(kind: ieVar, varName: "x"),
      op: ">",
      right: IRExpr(kind: ieConst, val: "0"))
    let e = IRExpr(kind: ieRefinement,
      refVarName: "x", refBaseType: "Nat", predicate: pred)
    check renderIRExpr(e) == "{x : Nat // (x > 0)}"

  test "irToLeanDefinition — plain params (simp)":
    let ir = AxiomIRNode(
      kind: irCall, name: "add",
      params: @[
        AxiomParam(name: "a", typeStr: "Nat",
          refinement: none(IRExpr),
          isInductive: false),
        AxiomParam(name: "b", typeStr: "Nat",
          refinement: none(IRExpr),
          isInductive: false)
      ])
    let lean = irToLeanDefinition(ir)
    check lean.contains("theorem add_auto")
    check lean.contains("(a : Nat) (b : Nat)")
    check lean.contains("by simp")

  test "irToLeanDefinition — refinement param (subtype)":
    let pred = IRExpr(kind: ieBinaryOp,
      left: IRExpr(kind: ieVar, varName: "x"),
      op: ">",
      right: IRExpr(kind: ieConst, val: "0"))
    let ir = AxiomIRNode(
      kind: irCall, name: "positive",
      params: @[
        AxiomParam(name: "x", typeStr: "Nat",
          refinement: some(IRExpr(kind: ieRefinement,
            refVarName: "x", refBaseType: "Nat", predicate: pred)))
      ])
    let lean = irToLeanDefinition(ir)
    check lean.contains("theorem positive_auto")
    check lean.contains("{x : Nat // (x > 0)}")
    check lean.contains("by simp")

  test "irToLeanRefinedDefinition — preconditions as hypotheses":
    let pred = IRExpr(kind: ieBinaryOp,
      left: IRExpr(kind: ieVar, varName: "n"),
      op: ">=",
      right: IRExpr(kind: ieConst, val: "0"))
    let ir = AxiomIRNode(
      kind: irCall, name: "bound",
      params: @[AxiomParam(name: "n", typeStr: "Nat", refinement: none(IRExpr),
        isInductive: false)],
      preConditions: @[pred],
      postCondition: some(IRExpr(kind: ieBinaryOp,
        left: IRExpr(kind: ieVar, varName: "n"),
        op: ">=",
        right: IRExpr(kind: ieConst, val: "0"))))
    let lean = irToLeanRefinedDefinition(ir).get("")
    check lean.contains("theorem bound_spec")
    check lean.contains("(n : Nat) (h_pre0 : (n >= 0))")
    check lean.contains(": (n >= 0)")
    check lean.contains("intros")
    check lean.contains("simp [*]")

  test "irToLeanRefinedDefinition — keyword param escaping":
    let pred = IRExpr(kind: ieBinaryOp,
      left: IRExpr(kind: ieVar, varName: "type"),
      op: ">",
      right: IRExpr(kind: ieConst, val: "0"))
    let ir = AxiomIRNode(
      kind: irCall, name: "keywordParam",
      params: @[
        AxiomParam(name: "type", typeStr: "Nat",
          refinement: some(IRExpr(kind: ieRefinement,
            refVarName: "type", refBaseType: "Nat", predicate: pred)))
      ])
    let lean = irToLeanRefinedDefinition(ir).get("")
    check lean.contains("«type» : {«type» : Nat // {«type» : Nat // («type» > 0)}}")
    check lean.contains("simp [*]")

  test "irToLeanDefinition — List param (induction)":
    let ir = AxiomIRNode(
      kind: irCall, name: "rev",
      params: @[
        AxiomParam(name: "xs", typeStr: "List Nat", refinement: none(IRExpr),
        isInductive: false)
      ])
    let lean = irToLeanDefinition(ir)
    check lean.contains("theorem rev_auto")
    check lean.contains("induction xs")
    check lean.contains("simp [ih]")

  test "renderIRExpr — complex refinement chain":
    let inner = IRExpr(kind: ieRefinement,
      refVarName: "y", refBaseType: "Int",
      predicate: IRExpr(kind: ieBinaryOp,
        left: IRExpr(kind: ieVar, varName: "y"),
        op: "!=",
        right: IRExpr(kind: ieConst, val: "0")))
    let outer = IRExpr(kind: ieRefinement,
      refVarName: "x", refBaseType: "Nat",
      predicate: IRExpr(kind: ieBinaryOp,
        left: IRExpr(kind: ieConst, val: "0"),
        op: "<",
        right: IRExpr(kind: ieVar, varName: "x")))
    check renderIRExpr(inner) == "{y : Int // (y != 0)}"
    check renderIRExpr(outer) == "{x : Nat // (0 < x)}"
