import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
## Axiom Core IR → SMT-LIB2 Converter (include-based split)
##
## Forward declarations resolve mutual recursion cycle:
##   {irExprToSmt, buildBmcMatrixFor, buildBmcMatrixWhile}
##
## Chunks:
##   chunk1: [MOVED to core/trusted/ir_tree_ops.nim] tree walkers
##   chunk2: type/literal mapping + irExprToSmt + BMC matrix builders
##   chunk3: function-to-SMT + overflow + script assembly
##
## BMC lowering (recomputeTyp → resolveRecCalls → elaborateSorts) is
## centralized in core/passes/bmc_lower.nim. Emission functions operate
## on already-lowered IR only.
##
## emitSmtModule (proc, outside {.push raises: [].}) stays in this file.

import core/trusted/axiom_ir_helpers
import std/strutils
import std/tables
import core/trusted/axiom_pragmas
import core/trusted/ast_to_ir
import core/trusted/ir_elaborate_sorts
import core/passes/bmc_lower
import core/proof/proof_budget
import core/logic/smt_logic
import verification/obligation/obligation_ir

const irLoopBmcBound* = 10

# Forward declarations for mutual recursion with irExprToSmt
func buildBmcMatrixFor(
    loopVars: seq[string], loopInits: seq[IRExpr],
    loopStep: IRExpr, loopBody: IRExpr,
    k: int, maxBound: int, logic: SmtLogic = slQfBv,
    u64Ctx: bool = false): string

func buildBmcMatrixWhile(
    loopVars: seq[string], loopInits: seq[IRExpr],
    loopCond: IRExpr, loopBody: IRExpr,
    k: int, maxBound: int, logic: SmtLogic = slQfBv,
    u64Ctx: bool = false): string

func irExprToSmt*(e: IRExpr, indent: int = 0, logic: SmtLogic = slQfBv,
                  u64Ctx: bool = false): string

include core/trusted/private/ir_to_smt_chunk1
include core/trusted/private/ir_to_smt_chunk2
include core/trusted/private/ir_to_smt_chunk3

{.pop.}

func emitSmtModule*(module: IRModule): string =
  ## Pure Emitter — IRModule manifest를 SMT-LIB2로 직렬화.
  ## Each function is lowered via lowerToBmc before emission.
  var smt = ""
  for decl in module.externalDeclarations:
    if decl.retType.kind == irtEnum and decl.retType.enumOrdinals.len > 0:
      var maxOrd = decl.retType.enumOrdinals[0]
      for o in decl.retType.enumOrdinals:
        if o > maxOrd: maxOrd = o
      let mask = (1'i64 shl (computeTagBitWidth(maxOrd))) - 1
      smt &= "(define-fun " & decl.name & " ("
      for i, pt in decl.paramTypes:
        if i > 0: smt &= " "
        smt &= "(" & ("_p" & $i) & " " & irTypeToSmt(pt) & ")"
      smt &= ") " & irTypeToSmt(decl.retType)
      smt &= " (bvand _p0 (_ bv" & $mask & " 64)))\n"
    else:
      smt &= "(declare-fun " & decl.name & " ("
      for i, pt in decl.paramTypes:
        if i > 0: smt &= " "
        smt &= irTypeToSmt(pt)
      smt &= ") " & irTypeToSmt(decl.retType) & ")\n"
  for recFn in module.recursiveGroup:
    let lowered = lowerToBmc(recFn)
    smt &= "(define-fun-rec " & lowered.name & " ("
    for i, p in lowered.params:
      if i > 0: smt &= " "
      smt &= "(" & p.name & " " & irTypeToSmt(p.ty) & ")"
    smt &= ") " & irTypeToSmt(lowered.retType) & "\n"
    smt &= "  " & irExprToSmt(lowered.body) & ")\n"
  for fn in module.functions:
    if not fn.isRecursive:
      let lowered = lowerToBmc(fn)
      smt &= "(define-fun " & lowered.name & " ("
      for i, p in lowered.params:
        if i > 0: smt &= " "
        smt &= "(" & p.name & " " & irTypeToSmt(p.ty) & ")"
      smt &= ") " & irTypeToSmt(lowered.retType) & "\n"
      smt &= "  " & irExprToSmt(lowered.body) & ")\n"
  smt

