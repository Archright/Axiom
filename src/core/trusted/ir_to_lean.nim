import core/trusted/layer_declaration
axiomLayer "trusted.core.ir-to-lean"

{.push raises: [].}
## Axiom Core IR → Lean 4 Source Code Converter
##
## Pure-functional: every function is `func` with `{.raises: [].}`.
## Converts Axiom Core IR into syntactically valid Lean 4 source code,
## with automatic termination handling for recursive functions.
##
## Termination strategies:
##   1. Structural descent (list recursion) — Lean auto-detects.
##   2. Numeric descent (integer recursion) — `termination_by n` + `decreasing_by omega`.
##   3. Fallback — `partial def` with `termination_by sorry`.

import std/options
import std/strutils
import std/tables
import core/types/results
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/axiom_pragmas
import core/trusted/lean_goal
import core/trusted/theorem_writer
import verification/obligation/obligation_ir

# ---------------------------------------------------------------------------
# Type mapping: IRType → Lean 4 type string
# ---------------------------------------------------------------------------

func irTypeToLean*(t: IRType): string {.raises: [], axiomImpl.} =
  ## Map an IRType to its Lean 4 representation.
  case t.kind
  of irtBitVec64:
    "BitVec 64"
  of irtBool:
    "Bool"
  of irtList:
    "List (" & irTypeToLean(t.elemType) & ")"
  of irtString:
    "String"
  of irtEnum:
    "Nat"
  of irtVariant:
    "Nat"

# ---------------------------------------------------------------------------
# Binary operator mapping: BinOpKind → Lean 4 operator
# ---------------------------------------------------------------------------

func irBinOpToLean*(op: BinOpKind): string {.raises: [], axiomImpl.} =
  ## Map a binary operator to its Lean 4 symbol.
  ## div/rem/remU map to BitVec function names (prefix application), not
  ## operators: Lean core (4.33) has no /ₛ %ₛ %ᵤ notations, and the toolchain
  ## pin is the only elaboration target.
  case op
  of boAdd: "+"
  of boSub: "-"
  of boMul: "*"
  of boDiv: "BitVec.sdiv"
  of boRem: "BitVec.srem"
  of boRemU: "BitVec.umod"     ## unsigned remainder (bvurem)
  of boShl: "UNSUPPORTED"
  of boShr: "UNSUPPORTED"
  of boUnsupported: "UNSUPPORTED"
  of boLt: "<"
  of boLe: "≤"
  of boGt: ">"
  of boGe: "≥"
  of boAnd: "&&"
  of boOr: "||"
  of boEq: "=="
  of boLtU: "BitVec.ult"

func leanBvSlt(lhs, rhs: string): string {.raises: [].} =
  ## Emit the signed-order BitVec comparison `BitVec.slt` — the ONE emission
  ## rule for strict comparison propositions. `BitVec.slt` is by definition
  ## equal to the Int-order comparison of `BitVec.toInt` operands (Nim's
  ## signed order), and it stays inside the `bv_decide` fragment: the former
  ## `(x : BitVec 64).toInt` projection emission is an Int goal that NO
  ## available tactic discharges (measured 2026-10-09, lean 4.33.0: omega
  ## cannot fold `BitVec.toInt` literals — `(1 : BitVec 64).toInt ≥ 1` is
  ## unprovable; `bv_decide` rejects Int goals outright) so the kernel check
  ## exited 1 and the certificate stalled at certZ3Candidate. Raw signed
  ## BitVec + `bv_decide` is kernel-clean (exit 0, no axioms).
  "(BitVec.slt " & lhs & " " & rhs & ")"

func leanBvSle(lhs, rhs: string): string {.raises: [].} =
  ## Non-strict companion of `leanBvSlt` — same signed-order fragment rule.
  "(BitVec.sle " & lhs & " " & rhs & ")"

func leanBvUlt(lhs, rhs: string): string {.raises: [].} =
  ## Emit the unsigned-order BitVec comparison `BitVec.ult` — the ONE
  ## emission rule for unsigned strict comparisons (boLtU, operator-resident
  ## signedness). `BitVec.ult` is the unsigned bit order by definition; the
  ## u64-domain premise [0, 2^64) (aoTypeDerived range premise —
  ## rust_certified_subset.md §4 boLtU note) makes the Int-order denotation
  ## and the unsigned order coincide on that domain. Kernel-clean (measured
  ## 2026-11-02, lean 4.33.0): raw BitVec + `bv_decide` closes with
  ## `#print axioms` = `[propext]` ⊆ the INV-6 allowlist — strictly cleaner
  ## than the slt form ([propext, Classical.choice, Quot.sound]). No Int
  ## fallback: the fallback guard requires a kernel-verified ult ↔
  ## unsigned-order equivalence first (contract).
  "(BitVec.ult " & lhs & " " & rhs & ")"

# ---------------------------------------------------------------------------
# Unary operator mapping: UnaryOpKind → Lean 4 operator
# ---------------------------------------------------------------------------

func irUnaryOpToLean*(op: UnaryOpKind): string {.raises: [], axiomImpl.} =
  ## Map a unary operator to its Lean 4 symbol.
  case op
  of uoNot: "!"
  of uoBvNot: "~~~"
  of uoBvNeg: "-'"

# ---------------------------------------------------------------------------
# Expression conversion: IRExpr → Lean 4 expression string
#
# ACI decomposition: irExprToLean was ~81 ACI (145 lines).
# Extracted 15 sub-functions, each < 20 ACI.
# ---------------------------------------------------------------------------

const leanStringCallMap = {
  "len":      "String.length",
  "substr":   "String.take",
  "charAt":   "String.get",
  "concat":   "String.append",
  "contains": "String.contains",
  "prefix":   "String.isPrefixOf",
  "suffix":   "String.isSuffixOf",
  "indexOf":  "String.indexOf",
}.toTable

# Forward declaration for mutual recursion with sub-handlers.
func irExprToLean*(e: IRExpr, indent: int = 0): string {.raises: [].}
func refinedExprToProp*(e: IRExpr): Result[string, string] {.raises: [].}

# ---------------------------------------------------------------------------
# §A: Leaf / literal handlers (no recursive calls)
# ---------------------------------------------------------------------------

func irLitToLean*(e: IRExpr): string {.raises: [].} =
  ## Handle irLit, irFloatLit, irVar, irStringLit — leaf nodes.
  case e.kind
  of irLit:      (if e.litU64 != 0'u64: $e.litU64 else: $e.litVal)
  of irFloatLit: $e.floatVal
  of irVar:      e.varName
  of irStringLit: "\"" & e.stringVal & "\""
  else:          ""

# ---------------------------------------------------------------------------
# §B: Structural expression handlers
# ---------------------------------------------------------------------------

func irLetToLean*(e: IRExpr, indent: int): string {.raises: [].} =
  ## Handle irLet binding.
  let pad1 = "  ".repeat(indent + 1)
  "let " & e.letName & " := " &
    irExprToLean(e.letVal, indent) & "\n" &
    pad1 & irExprToLean(e.letBody, indent)

func irIfToLean*(e: IRExpr, indent: int): string {.raises: [].} =
  ## Handle irIf / then / else.
  let pad = "  ".repeat(indent)
  let pad1 = "  ".repeat(indent + 1)
  "if " & irExprToLean(e.ifCond, indent) & " then\n" &
    pad1 & irExprToLean(e.ifThen, indent + 1) & "\n" &
    pad & "else\n" &
    pad1 & irExprToLean(e.ifElse, indent + 1)

func irCaseToLean*(e: IRExpr, indent: int): string {.raises: [].} =
  ## Handle irCase / match expression.
  let pad1 = "  ".repeat(indent + 1)
  var s = "match " & irExprToLean(e.caseScrutinee, indent) & " with\n"
  for br in e.caseBranches:
    s.add(pad1 & "| " & $br.pattern & " => " &
          irExprToLean(br.body, indent + 1) & "\n")
  if e.caseDefault != nil:
    s.add(pad1 & "| _ => " &
          irExprToLean(e.caseDefault, indent + 1) & "\n")
  s

func irCallToLean*(e: IRExpr, indent: int): string {.raises: [].} =
  ## Handle irCall — named function call with string call map.
  if e.callName == "opCastToBool" and e.callArgs.len == 1:
    # BV64→Lean Bool: true iff argument ≠ 0
    return "(" & irExprToLean(e.callArgs[0], indent) & " != 0)"
  elif e.callName == "opCastToBv64" and e.callArgs.len == 1:
    # Lean Bool→Nat: 1 if true, 0 if false
    return "(if " & irExprToLean(e.callArgs[0], indent) & " then 1 else 0)"
  let mappedName = leanStringCallMap.getOrDefault(e.callName, e.callName)
  var s = mappedName
  for a in e.callArgs:
    s.add(" " & irExprToLean(a, indent))
  s

# ---------------------------------------------------------------------------
# §C: Operator expression handlers
# ---------------------------------------------------------------------------

func irBinExprToLean*(e: IRExpr, indent: int): string {.raises: [].} =
  ## Handle irBinOp — binary operation expression.
  ## Emits Lean 4 infix notation (e.g. "(a + b)") instead of SMT-LIB2 prefix
  ## ("(+ a b)"). Prefix causes Lean compilation failure because Lean 4
  ## parsers treat `<`, `≤`, etc. as infix operators, not prefix functions.
  ##
  ## Signedness constraint: Nim `<`/`<=` on int is signed, while Lean's
  ## `BitVec` order instances (`<`, `≤`) are UNSIGNED (toNat order). Every
  ## comparison therefore lowers to `BitVec.slt`/`BitVec.sle` (signed order,
  ## by definition equal to the `.toInt` projection comparison) — with
  ## operands mirrored for `>`/`≥` — which restores Nim's signed order AND
  ## stays inside the `bv_decide` bitblasting fragment (the former
  ## `(x : BitVec 64).toInt` projection emission produced Int goals outside
  ## every dischargeable fragment; see leanBvSlt).
  ## div/rem lower to the core functions matching SMT bvsdiv/bvsrem/bvurem.
  let lhs = irExprToLean(e.binLhs, indent)
  let rhs = irExprToLean(e.binRhs, indent)
  case e.binOp
  of boAdd:      "(" & lhs & " + " & rhs & ")"
  of boSub:      "(" & lhs & " - " & rhs & ")"
  of boMul:      "(" & lhs & " * " & rhs & ")"
  of boDiv:      "(BitVec.sdiv " & lhs & " " & rhs & ")"
  of boRem:      "(BitVec.srem " & lhs & " " & rhs & ")"
  of boRemU:     "(BitVec.umod " & lhs & " " & rhs & ")"
  of boShl:      "(" & lhs & " << " & rhs & ")"
  of boShr:      "(" & lhs & " >> " & rhs & ")"
  of boUnsupported: "(" & lhs & " UNSUPPORTED " & rhs & ")"
  of boLt:       leanBvSlt(lhs, rhs)
  of boLe:       leanBvSle(lhs, rhs)
  of boGt:       leanBvSlt(rhs, lhs)
  of boGe:       leanBvSle(rhs, lhs)
  of boAnd:      "(" & lhs & " && " & rhs & ")"
  of boOr:       "(" & lhs & " || " & rhs & ")"
  of boEq:       "(" & lhs & " == " & rhs & ")"
  of boLtU:      leanBvUlt(lhs, rhs)

func irUnaryExprToLean*(e: IRExpr, indent: int): string {.raises: [].} =
  ## Handle irUnaryOp — unary operation expression.
  "(" & irUnaryOpToLean(e.unaryOp) & " " &
    irExprToLean(e.unaryArg, indent) & ")"

func irRecCallToLean*(e: IRExpr, indent: int): string {.raises: [].} =
  ## Handle irRecCall — self-recursive call placeholder.
  var s = "__self__"
  for a in e.recArgs:
    s.add(" " & irExprToLean(a, indent))
  s

# ---------------------------------------------------------------------------
# §D: Loop expression — further decomposed into sub-helpers
# ---------------------------------------------------------------------------

func buildLoopParamList(e: IRExpr): string {.raises: [].} =
  ## Build the parameter binder list for the loop helper function.
  ## Each loop variable is its own parenthesized binder — Lean 4 grammar
  ## requires `(x : T) (y : T)`, a single `(x : T y : T)` does not parse.
  let ty = "BitVec 64"
  result = ""
  for i, v in e.loopVars:
    if i > 0: result.add(" ")
    result.add("(" & v & " : " & ty & ")")

func buildLoopRetType(n: int): string {.raises: [].} =
  ## Build return type string — single type or product type.
  let ty = "BitVec 64"
  if n == 1: return ty
  result = ""
  for i in 0..<n:
    if i > 0: result.add(" × ")
    result.add(ty)

func buildLoopRetVals(e: IRExpr): string {.raises: [].} =
  ## Build return value expression for the loop.
  result = ""
  for i, v in e.loopVars:
    if i > 0: result.add(", ")
    result.add(v)
  if e.loopVars.len > 1:
    result = "(" & result & ")"

func buildLoopNextVars(e: IRExpr): seq[string] {.raises: [].} =
  ## Build "next_<varname>" list for state-threading.
  result = newSeq[string](e.loopVars.len)
  for i, v in e.loopVars:
    result[i] = "next_" & v

func buildLoopNextVals(nextVars: seq[string]): string {.raises: [].} =
  ## Build comma-separated next-variable names string.
  result = ""
  for i, v in nextVars:
    if i > 0: result.add(", ")
    result.add(v)

func buildLoopCondGuard(e: IRExpr, indent: int,
                        retVals: string,
                        hasVariant: bool): string {.raises: [].} =
  ## Emit the `if h : cond` or `if ¬(cond)` guard line.
  let pad1 = "  ".repeat(indent + 1)
  result = ""
  if hasVariant:
    result.add(pad1 & "if h : " & irExprToLean(e.loopCond, indent + 1) & " then\n")
  else:
    result.add(pad1 & "if ¬(" & irExprToLean(e.loopCond, indent + 1) & ") then " & retVals & "\n")
    result.add(pad1 & "else\n")

func buildLoopBodyAndRecurse(e: IRExpr, indent: int,
                             retVals, nextVals: string,
                             nextVars: seq[string],
                             hasVariant: bool): string {.raises: [].} =
  ## Emit the loop body + recursive _loop_go call, plus else-branch if proof guard.
  let n = e.loopVars.len
  let pad1 = "  ".repeat(indent + 1)
  let pad2 = "  ".repeat(indent + 2)
  result = ""
  if hasVariant:
    # then-branch: body + recursive call
    if n == 1:
      result.add(pad2 & "let " & nextVals & " := " &
                 irExprToLean(e.loopBody, indent + 1) & "\n")
    else:
      result.add(pad2 & "let (" & nextVals & ") := " &
                 irExprToLean(e.loopBody, indent + 1) & "\n")
    result.add(pad2 & "_loop_go")
    for v in nextVars:
      result.add(" " & v)
    result.add("\n")
    # else-branch: return current values
    result.add(pad1 & "else\n")
    result.add(pad2 & retVals & "\n")
  else:
    # Fallback ordering (no proof guard)
    if n == 1:
      result.add(pad2 & "let " & nextVals & " := " &
                 irExprToLean(e.loopBody, indent + 1) & "\n")
    else:
      result.add(pad2 & "let (" & nextVals & ") := " &
                 irExprToLean(e.loopBody, indent + 1) & "\n")
    result.add(pad2 & "_loop_go")
    for v in nextVars:
      result.add(" " & v)
    result.add("\n")

func buildLoopTermination(e: IRExpr, indent: int): string {.raises: [].} =
  ## Emit termination_by + decreasing_by clauses.
  result = ""
  case e.loopKind
  of lkFor:
    if e.loopCond.kind == irBinOp and e.loopCond.binOp == boLt:
      result.add("termination_by " & irExprToLean(e.loopCond.binRhs, indent) &
                 " - " & irExprToLean(e.loopCond.binLhs, indent) & "\n")
    else:
      result.add("termination_by ?\n")
    result.add("decreasing_by omega\n")
  of lkWhile:
    if e.loopVariant != nil:
      # Loop vars are BitVec 64 — cast to Nat so omega can reason about descent
      result.add("termination_by " & irExprToLean(e.loopVariant, indent) & ".toNat\n")
      result.add("decreasing_by\n")
      result.add("  simp [*] at *\n")
      result.add("  omega\n")
    else:
      result.add("termination_by fuel\n")
      result.add("decreasing_by omega\n")

func buildLoopCallAndDestructure(e: IRExpr, indent: int): string {.raises: [].} =
  ## Emit initial _loop_go call with argument initialization.
  let n = e.loopVars.len
  var resultVars = newSeq[string](n)
  for i, v in e.loopVars:
    resultVars[i] = "r_" & v
  var resultVals = ""
  for i, v in resultVars:
    if i > 0: resultVals.add(", ")
    resultVals.add(v)
  result = ""
  if n == 1:
    result.add("let " & resultVals & " := _loop_go")
  else:
    result.add("let (" & resultVals & ") := _loop_go")
  for init in e.loopInits:
    result.add(" " & irExprToLean(init, indent))

func irLoopToLean*(e: IRExpr, indent: int): string {.raises: [].} =
  ## Handle irLoop — compose sub-helpers for parameter list, body, termination.
  let hasVariant = e.loopVariant != nil
  let params    = buildLoopParamList(e)
  let retType   = buildLoopRetType(e.loopVars.len)
  let retVals   = buildLoopRetVals(e)
  let nextVars  = buildLoopNextVars(e)
  let nextVals  = buildLoopNextVals(nextVars)

  result = "let rec _loop_go " & params & " : " & retType & " :=\n"
  result.add(buildLoopCondGuard(e, indent, retVals, hasVariant))
  result.add(buildLoopBodyAndRecurse(e, indent, retVals, nextVals,
                                     nextVars, hasVariant))
  result.add(buildLoopTermination(e, indent))
  result.add(buildLoopCallAndDestructure(e, indent))

# ---------------------------------------------------------------------------
# §E: Main dispatcher — thin routing to sub-handlers
# ---------------------------------------------------------------------------

func irExprToLean*(e: IRExpr, indent: int = 0): string {.raises: [].} =
  ## Convert an IR expression tree into a Lean 4 expression string.
  ## Dispatcher routes to pattern-specific pure sub-functions.
  case e.kind
  of irLit, irFloatLit, irVar, irStringLit:
    irLitToLean(e)
  of irLet:
    irLetToLean(e, indent)
  of irIf:
    irIfToLean(e, indent)
  of irCase:
    irCaseToLean(e, indent)
  of irCall:
    irCallToLean(e, indent)
  of irBinOp:
    irBinExprToLean(e, indent)
  of irUnaryOp:
    irUnaryExprToLean(e, indent)
  of irRecCall:
    irRecCallToLean(e, indent)
  of irLoop:
    irLoopToLean(e, indent)
  of irCast:
    "(cast " & irExprToLean(e.castExpr, indent) & ")"


# ---------------------------------------------------------------------------
# Helper: extract the name of the variable being pattern-matched on
# ---------------------------------------------------------------------------

func caseScrutineeName*(e: IRExpr): string {.raises: [].} =
  ## If `e` is irCase, return the variable name of its scrutinee.
  if e.kind == irCase:
    if e.caseScrutinee.kind == irVar:
      return e.caseScrutinee.varName
    return "<expr>"
  ""

# ---------------------------------------------------------------------------
# Termination strategy analysis
# ---------------------------------------------------------------------------

type
  TerminationStrategy* = enum
    tsNone
    tsStructural
    tsNumeric
    tsFallback

func detectNumericDecrement*(body: IRExpr, paramName: string): bool {.raises: [].} =
  ## Heuristic: does the body contain a subtraction of 1 from `paramName`?
  case body.kind
  of irLit, irFloatLit, irVar, irStringLit:
    false
  of irLet:
    detectNumericDecrement(body.letVal, paramName) or
      detectNumericDecrement(body.letBody, paramName)
  of irIf:
    detectNumericDecrement(body.ifCond, paramName) or
      detectNumericDecrement(body.ifThen, paramName) or
      detectNumericDecrement(body.ifElse, paramName)
  of irCase:
    var found = false
    for br in body.caseBranches:
      found = found or detectNumericDecrement(br.body, paramName)
    if body.caseDefault != nil:
      found = found or detectNumericDecrement(body.caseDefault, paramName)
    found
  of irBinOp:
    if body.binOp == boSub and body.binLhs.kind == irVar and
       body.binLhs.varName == paramName and body.binRhs.kind == irLit and
       body.binRhs.litVal == 1:
      return true
    detectNumericDecrement(body.binLhs, paramName) or
      detectNumericDecrement(body.binRhs, paramName)
  of irCall:
    for a in body.callArgs:
      if detectNumericDecrement(a, paramName):
        return true
    false
  of irUnaryOp:
    detectNumericDecrement(body.unaryArg, paramName)
  of irRecCall:
    for a in body.recArgs:
      if detectNumericDecrement(a, paramName):
        return true
    false
  of irLoop:
    for init in body.loopInits:
      if detectNumericDecrement(init, paramName): return true
    if detectNumericDecrement(body.loopCond, paramName): return true
    if body.loopStep != nil and detectNumericDecrement(body.loopStep, paramName): return true
    if detectNumericDecrement(body.loopBody, paramName): return true
    for inv in body.loopInvariants:
      if detectNumericDecrement(inv, paramName): return true
    if body.loopVariant != nil and detectNumericDecrement(body.loopVariant, paramName): return true
    false
  of irCast:
    detectNumericDecrement(body.castExpr, paramName)

func detectStructuralRecursion*(body: IRExpr): bool {.raises: [].} =
  ## Heuristic: does the body pattern-match on a list via irCase?
  if body.kind == irCase:
    if body.caseBranches.len >= 1:
      return true
    if body.caseDefault != nil:
      return true
  case body.kind
  of irLet:
    detectStructuralRecursion(body.letBody)
  of irIf:
    detectStructuralRecursion(body.ifThen) or
      detectStructuralRecursion(body.ifElse)
  of irLoop:
    var res = false
    for init in body.loopInits:
      res = res or detectStructuralRecursion(init)
    res = res or detectStructuralRecursion(body.loopCond)
    if body.loopStep != nil:
      res = res or detectStructuralRecursion(body.loopStep)
    res = res or detectStructuralRecursion(body.loopBody)
    for inv in body.loopInvariants:
      res = res or detectStructuralRecursion(inv)
    if body.loopVariant != nil:
      res = res or detectStructuralRecursion(body.loopVariant)
    res
  of irCast:
    false
  else:
    false

func detectTerminationStrategy*(f: IRFuncDef): TerminationStrategy {.raises: [].} =
  ## Analyze a recursive function to determine the best termination strategy.
  if not f.isRecursive:
    return tsNone
  for p in f.params:
    if p.ty.kind == irtList:
      return tsStructural
  for p in f.params:
    if p.ty.kind == irtBitVec64:
      if detectNumericDecrement(f.body, p.name):
        return tsNumeric
  if detectStructuralRecursion(f.body):
    return tsStructural
  tsFallback

# ---------------------------------------------------------------------------
# Resolve recursive call placeholders
# ---------------------------------------------------------------------------

func resolveRecCalls*(body: IRExpr, funcName: string): string {.raises: [].} =
  ## Convert expression to Lean, replacing __self__ with the actual function name.
  let raw = irExprToLean(body)
  raw.replace("__self__", funcName)

# ---------------------------------------------------------------------------
# Internal helpers: build function signature string
# ---------------------------------------------------------------------------

func buildFuncSignature(f: IRFuncDef, keyword: string): string {.raises: [].} =
  ## Build a Lean 4 function signature: "keyword name (p1 : T1) (p2 : T2) : Ret :="
  ## Each parameter binder is its own parenthesized group — Lean 4 grammar
  ## requires `(a : T) (b : U)`, a single `(a : T b : U)` does not parse.
  result = keyword & " " & f.name
  for p in f.params:
    result.add(" (" & p.name & " : " & irTypeToLean(p.ty) & ")")
  result.add(" : " & irTypeToLean(f.retType) & " :=\n")
  result.add("  " & resolveRecCalls(f.body, f.name))

func buildDefWithTermination(f: IRFuncDef, decParam: string): string {.raises: [].} =
  ## Build a Lean 4 def with termination_by clause.
  ## Uses .toNat so omega can handle the BitVec→Nat comparison.
  result = buildFuncSignature(f, "def")
  result.add("\n")
  result.add("termination_by " & decParam & ".toNat\n")
  result.add("decreasing_by omega")

func buildPartialDef(f: IRFuncDef): string {.raises: [].} =
  ## Build a Lean 4 partial def with termination_by sorry.
  result = buildFuncSignature(f, "partial def")
  result.add("\n")
  result.add("termination_by sorry")

func findDecrementParam(f: IRFuncDef): string {.raises: [].} =
  ## Find the BitVec64 parameter that is decremented in the body.
  for p in f.params:
    if p.ty.kind == irtBitVec64:
      if detectNumericDecrement(f.body, p.name):
        return p.name
  ""

# ---------------------------------------------------------------------------
# Function definition → Lean 4 `def` / `partial def`
# ---------------------------------------------------------------------------

func irFuncDefToLean*(f: IRFuncDef): string {.raises: [].} =
  ## Convert a non-recursive IR function definition to a Lean 4 `def`.
  ## Each parameter binder is its own parenthesized group — Lean 4 grammar
  ## requires `(a : T) (b : U)`, a single `(a : T b : U)` does not parse.
  var s = "def " & f.name
  for p in f.params:
    s.add(" (" & p.name & " : " & irTypeToLean(p.ty) & ")")
  s.add(" : " & irTypeToLean(f.retType) & " :=\n")
  s.add("  " & irExprToLean(f.body, 1))
  s

# ---------------------------------------------------------------------------
# Task 50: Theorem generator from postConditions
# ---------------------------------------------------------------------------

func irFuncDefToTheorem*(f: IRFuncDef, enableMathlib: bool = false): string {.raises: [].} =
  ## Generate Lean 4 theorem stubs from postConditions.
  ## Uses theorem_writer tactic dispatcher for deterministic tactic selection.
  ## enableMathlib: when false, nlinarith/aesop fall back to sorry (Soundness Debt).
  if f.postConditions.len == 0:
    return ""
  result = ""
  var tactics: seq[TacticKind] = @[]
  for i, pc in f.postConditions:
    let classifier = classifyPostCondition(pc)
    let tactic = selectTactic(classifier, enableMathlib)
    tactics.add(tactic)
    let tacticStr = tacticToLeanString(tactic)
    let propRes = refinedExprToProp(pc)
    if propRes.isErr:
      continue
    let propStr = propRes.get
    result.add("theorem " & f.name & "_post" & $i & " ")
    for p in f.params:
      result.add("(" & p.name & " : " & irTypeToLean(p.ty) & ") ")
    result.add(":\n  (let result := " & f.name)
    for p in f.params:
      result.add(" " & p.name)
    result.add(";\n    " & propStr & ") :=\n")
    result.add("by\n")
    result.add("  unfold " & f.name & "\n")
    result.add("  " & tacticStr & "\n\n")

func collectTheoremImportNames*(f: IRFuncDef, enableMathlib: bool): seq[string] {.raises: [].} =
  ## Import NAMES (no "import " prefix) required by the theorem tactics of
  ## `f`'s postconditions. The module composer routes these into the header
  ## section so the theorem text itself never emits imports.
  var tactics: seq[TacticKind] = @[]
  for pc in f.postConditions:
    tactics.add(selectTactic(classifyPostCondition(pc), enableMathlib))
  for line in collectRequiredImports(tactics):
    if line.startsWith("import "):
      result.add(line[7 .. ^1])

# ---------------------------------------------------------------------------
# Recursive definition with termination handling
# ---------------------------------------------------------------------------

func emitRecDef*(f: IRFuncDef): string {.raises: [].} =
  ## Convert a recursive IR function definition to Lean 4 with
  ## automatic termination strategy selection.
  let strategy = detectTerminationStrategy(f)
  case strategy
  of tsNone:
    irFuncDefToLean(f)
  of tsStructural:
    buildFuncSignature(f, "def")
  of tsNumeric:
    buildDefWithTermination(f, findDecrementParam(f))
  of tsFallback:
    buildPartialDef(f)

# ---------------------------------------------------------------------------
# Output metadata
# ---------------------------------------------------------------------------

func leanOutputMetadata*(f: IRFuncDef): string {.raises: [].} =
  ## Return JSON-style metadata for the Lean output.
  let strategy = detectTerminationStrategy(f)
  "{\n" &
    "  \"function\": \"" & f.name & "\",\n" &
    "  \"isRecursive\": " & $f.isRecursive & ",\n" &
    "  \"terminationStrategy\": \"" & $strategy & "\",\n" &
    "  \"terminationUnchecked\": " &
    (if strategy == tsFallback: "true" else: "false") & "\n" &
    "}"

# ---------------------------------------------------------------------------
# Module generation
# ---------------------------------------------------------------------------

func irToLeanModule*(f: IRFuncDef,
                      imports: seq[string] = @[],
                      enableMathlib: bool = false): string {.raises: [].} =
  ## Generate a complete Lean 4 source module with imports and definition.
  ## Imports are emitted in exactly ONE place — the header section
  ## (renderHeaderImports in core/trusted/lean_goal.nim) — so a duplicate
  ## `import` can never appear after the def/theorem body (Lean rejects
  ## that with "invalid import command, must be used in the beginning of
  ## the file"). `imports` carries module names WITHOUT the "import " prefix.
  ## enableMathlib: when false, nlinarith/aesop fall back to sorry (Soundness Debt).
  var required = @[leanBvDecideImport]
  for imp in imports:
    required.add(imp)
  for imp in collectTheoremImportNames(f, enableMathlib):
    required.add(imp)
  result = renderHeaderImports(required)
  if f.isRecursive:
    result.add(emitRecDef(f))
  else:
    result.add(irFuncDefToLean(f))
  result.add("\n")
  result.add(irFuncDefToTheorem(f, enableMathlib))
  # Vacuity check removed: ax_vacuity_check : True was trivially provable (no soundness value).
  # Anti-vacuity is now enforced at pipeline level via negative mutation test.
  result.add("#print axioms " & f.name & "\n")

# ---------------------------------------------------------------------------
# P4: Obligation-IR consumer overload — explicit obligations → Lean theorems
# ---------------------------------------------------------------------------

func irToLeanWithObligations*(f: IRFuncDef,
                               obligations: seq[VerificationObligation];
                               enableMathlib: bool = false): string {.raises: [].} =
  ## Generate Lean 4 theorem stubs from an explicit obligation list.
  ## Each obligation becomes a theorem whose statement is the obligation's
  ## predicate (canonicalized string form).  An empty obligations list
  ## returns `""` — the caller (P3 pipeline) routes explicitly.
  if obligations.len == 0:
    return ""
  result = "import Init\n"
  result.add("import Std.Tactic.BVDecide\n")
  for obl in obligations:
    result.add("theorem " & f.name & "_obligation_" & obl.id & " : " &
               obl.predicate & " :=\n")
    result.add("  sorry\n\n")

# ═══════════════════════════════════════════════════════════════
# §2. 패스트 패스: 정제 타입 Lean 코드 생성 (Refinement Typed IR)
# ═══════════════════════════════════════════════════════════════
# 전제조건을 (h : P) 파라미터로 변환 → 본체는 정의상 well-typed.
# §1의 irExprToLean과 독립. §0의 공통 헬퍼만 공유.

func refinedExprToProp*(e: IRExpr): Result[string, string] {.raises: [].} =
  if e == nil:
    return err("nil-expr")
  case e.kind
  of irBinOp:
    let lhsRes = refinedExprToProp(e.binLhs)
    if lhsRes.isErr: return err(lhsRes.error)
    let rhsRes = refinedExprToProp(e.binRhs)
    if rhsRes.isErr: return err(rhsRes.error)
    let lhs = lhsRes.get
    let rhs = rhsRes.get
    case e.binOp
    of boLt:  return ok(leanBvSlt(lhs, rhs))
    of boLe:  return ok(leanBvSle(lhs, rhs))
    of boGt:  return ok(leanBvSlt(rhs, lhs))
    of boGe:  return ok(leanBvSle(rhs, lhs))
    of boEq:  return ok("(" & lhs & " = " & rhs & ")")
    of boLtU: return ok(leanBvUlt(lhs, rhs))
    of boAnd: return ok("(" & lhs & " ∧ " & rhs & ")")
    of boOr:  return ok("(" & lhs & " ∨ " & rhs & ")")
    of boDiv, boRem, boRemU:
      # Lean core has no /ₛ %ₛ %ᵤ infix notations — prefix function application
      return ok("(" & irBinOpToLean(e.binOp) & " " & lhs & " " & rhs & ")")
    else:     return ok("(" & lhs & " " & irBinOpToLean(e.binOp) & " " & rhs & ")")
  of irUnaryOp:
    let argRes = refinedExprToProp(e.unaryArg)
    if argRes.isErr: return err(argRes.error)
    let arg = argRes.get
    case e.unaryOp
    of uoNot: return ok("¬(" & arg & ")")
    else:     return ok("(" & irUnaryOpToLean(e.unaryOp) & " " & arg & ")")
  of irLet:
    let valRes = refinedExprToProp(e.letVal)
    if valRes.isErr: return err(valRes.error)
    let bodyRes = refinedExprToProp(e.letBody)
    if bodyRes.isErr: return err(bodyRes.error)
    return ok("let " & e.letName & " := " & valRes.get & " in " & bodyRes.get)
  of irLit:   return ok(if e.litU64 != 0'u64: $e.litU64 else: $e.litVal)
  of irVar:   return ok(e.varName)
  else:
    return err("unrepresentable-ir: " & $e.kind)

func refinedParamToLean*(p: IRFuncParam): Result[string, string] {.raises: [].} =
  case p.ty.kind
  of irtString:
    result = ok("(" & p.name & " : {s : String // s.length > 0})")
  of irtList:
    let elemLean = irTypeToLean(p.ty.elemType)
    result = ok("(" & p.name & " : {s : List (" & elemLean & ") // s.length > 0})")
  else:
    result = ok("(" & p.name & " : " & irTypeToLean(p.ty) & ")")
  if p.constraint.isSome:
    if result.isOk:
      let propRes = refinedExprToProp(p.constraint.get)
      if propRes.isErr: return err(propRes.error)
      result = ok(result.get & " (h_" & p.name & " : " & propRes.get & ")")

func refinedPrecondToLean*(pc: IRExpr, idx: int): Result[string, string] {.raises: [].} =
  let propRes = refinedExprToProp(pc)
  if propRes.isErr: return err(propRes.error)
  return ok("(h_pre" & $idx & " : " & propRes.get & ")")

func irToLeanRefinedModule*(f: IRFuncDef,
                             imports: seq[string] = @[]): Result[string, string] {.raises: [].} =
  result = ok("import Init\n")
  for imp in imports:
    if result.isOk: result = ok(result.get & "import " & imp & "\n")
  if result.isOk: result = ok(result.get & "\n")
  if result.isOk: result = ok(result.get & "def " & f.name)
  for p in f.params:
    if result.isOk:
      let paramRes = refinedParamToLean(p)
      if paramRes.isErr: return err(paramRes.error)
      result = ok(result.get & " " & paramRes.get)
  for i, pc in f.preConditions:
    if result.isOk:
      let preRes = refinedPrecondToLean(pc, i)
      if preRes.isErr: return err(preRes.error)
      result = ok(result.get & " " & preRes.get)
  if result.isOk:
    result = ok(result.get & " : " & irTypeToLean(f.retType) & " :=")
    result = ok(result.get & "\n  ")
    result = ok(result.get & irExprToLean(f.body, 1))
  # Vacuity check removed: anti-vacuity enforced at pipeline level.

{.pop.}
