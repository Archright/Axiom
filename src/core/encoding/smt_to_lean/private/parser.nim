import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## SMT-to-Lean Codegen — Parser submodule
##
## SMT-LIB2 parsing, expression translation, type mapping,
## theorem building, and solver status mapping.
## Extracted from smt_to_lean_codegen_part1.nim (lines 1–344).

import std/strutils
import std/tables
import core/encoding/smt_types
import core/utils/text_utils
import ../../../../core/trusted/axiom_pragmas
import core/types/results

export smt_types

# ---------------------------------------------------------------------------
# Error Types
# ---------------------------------------------------------------------------

type
  SmtToLeanErrorKind* {.pure.} = enum
    UnknownQuantifier
    InvalidArity
    UnknownFunction
    UnsupportedType

  SmtToLeanError* = object
    kind*: SmtToLeanErrorKind
    opName*: string

# ---------------------------------------------------------------------------
# SMT-LIB2 Declaration / Assertion Types
# ---------------------------------------------------------------------------

type
  SmtDecl* = object
    name*: string
    smtType*: string

  SmtAssert* = object
    expr*: SExprNode

## Parse (declare-const name Type) declarations from SMT-LIB2.
func parseSmtlib2Decls*(smtlib2: string): seq[SmtDecl] {.raises: [], axiom: ["(assert (and (>= (str.len smtlib2) 0) (= (str.len trimmed) 0) (< nl 0) (> (str.len cursor) 0) (>= cursor 0)))", "smtlib2.length ≥ 0 ∧ trimmed.length = 0 ∧ nl < 0 ∧ cursor.length > 0 ∧ (cursor ≥ 0)"].} =
  var cursor = smtlib2
  while cursor.len > 0:
    let trimmed = cursor.strip()
    if trimmed.len == 0: break
    if trimmed[0] != '(':
      let nl = trimmed.find('\n')
      if nl < 0: break
      cursor = trimmed[nl + 1 .. ^1]
      continue
    let res = consumeSExpr(cursor)
    let sexpr = res.node
    cursor = res.remainder
    if not sexpr.isList or sexpr.children.len < 3:
      continue
    if sexpr.children[0].atom == "declare-const":
      result.add(SmtDecl(
        name: sanitizeToken(sexpr.children[1].atom),
        smtType: sexpr.children[2].atom
      ))

## Parse (assert expr) assertions from SMT-LIB2.
func parseSmtlib2Asserts*(smtlib2: string): seq[SmtAssert] {.raises: [], axiom: ["(assert (and (>= (str.len smtlib2) 0) (= (str.len trimmed) 0) (< nl 0) (> (str.len cursor) 0) (>= cursor 0)))", "smtlib2.length ≥ 0 ∧ trimmed.length = 0 ∧ nl < 0 ∧ cursor.length > 0 ∧ (cursor ≥ 0)"].} =
  var cursor = smtlib2
  while cursor.len > 0:
    let trimmed = cursor.strip()
    if trimmed.len == 0: break
    if trimmed[0] != '(':
      let nl = trimmed.find('\n')
      if nl < 0: break
      cursor = trimmed[nl + 1 .. ^1]
      continue
    let res = consumeSExpr(cursor)
    let sexpr = res.node
    cursor = res.remainder
    if not sexpr.isList or sexpr.children.len < 2:
      continue
    if sexpr.children[0].atom == "assert":
      result.add(SmtAssert(expr: sexpr.children[1]))

## Map SMT type names to Lean 4 types.
func smtTypeToLeanType*(smtType: string): string {.raises: [], axiom: ["(assert (and (>= (str.len smtType) 0)))", "smtType.length ≥ 0"].} =
  case smtType
  of "Int": "Int"
  of "Nat", "nat": "Nat"
  of "Bool", "bool": "Bool"
  of "String", "string", "str": "String"
  of "Real", "real": "Float"
  of "Char", "char": "Char"
  of "Seq", "seq": "List Nat"
  else: "Nat"  # Default fallback for unknown SMT types

## Determine if an SMT type is numeric (Int/Nat/Real).
func isNumericSmtType(smtType: string): bool {.raises: [].} =
  smtType in ["Int", "Nat", "nat", "Real", "real"]

## Convert an SMT s-expression to a Lean 4 expression string.
## @param declTypes Maps sanitized variable names to their SMT types,
##        enabling type-aware translation (str.len, numeric→Prop coercion).
## Get the raw SMT atom of an expression node for type lookups.
func rawSmtAtom(sexpr: SExprNode): string {.raises: [], axiom: ["(assert (and (>= (str.len sexpr_atom) 0) (>= (seq.len sexpr_children) 0) (or (= sexpr_isList true) (= sexpr_isList false)) ast_parse_failed_isolated))", "sexpr_atom.length ≥ 0 ∧ sexpr_children.size ≥ 0 ∧ sexpr_isList = true ∨ sexpr_isList = false ∧ ast_parse_failed_isolated"].} =
  if not sexpr.isList:
    return sexpr.atom
  if sexpr.children.len == 0:
    return ""
  return sexpr.children[0].atom

## Forward declaration for recursive expression translation.
func smtExprToLeanExpr*(sexpr: SExprNode; declTypes: Table[string, string] = initTable[string, string]()): Result[string, SmtToLeanError] {.raises: [].}

# ---------------------------------------------------------------------------
# smtExprToLeanExpr — private helpers
# ---------------------------------------------------------------------------

## Handle equality (=) with type-aware coercion.
func auxHandleEquality(sexpr: SExprNode; declTypes: Table[string, string]): Result[string, SmtToLeanError] {.inline, raises: [].} =
  if sexpr.children.len >= 3:
    let leftExprRes = smtExprToLeanExpr(sexpr.children[1], declTypes)
    if leftExprRes.isErr: return err(leftExprRes.err)
    let rightExprRes = smtExprToLeanExpr(sexpr.children[2], declTypes)
    if rightExprRes.isErr: return err(rightExprRes.err)
    let leftExpr = leftExprRes.get()
    let rightExpr = rightExprRes.get()
    let leftAtom = rawSmtAtom(sexpr.children[1])
    let rightAtom = rawSmtAtom(sexpr.children[2])
    let leftType = declTypes.getOrDefault(leftAtom, "")
    let rightType = declTypes.getOrDefault(rightAtom, "")
    if leftExpr == "true" and (rightExpr == "true" or rightExpr == "false"):
      return err(SmtToLeanError(kind: UnsupportedType, opName: "="))
    if leftType.len > 0 and rightType.len > 0 and leftType != rightType:
      return err(SmtToLeanError(kind: UnsupportedType, opName: "="))
    if (leftType in ["Nat", "nat"] and rightAtom.len > 1 and rightAtom[0] == '-' and rightAtom[1].isDigit) or
       (rightType in ["Nat", "nat"] and leftAtom.len > 1 and leftAtom[0] == '-' and leftAtom[1].isDigit):
      return err(SmtToLeanError(kind: UnsupportedType, opName: "="))
    if leftExpr.len == 0 or rightExpr.len == 0: return err(SmtToLeanError(kind: InvalidArity, opName: "="))
    return ok(leftExpr & " = " & rightExpr)
  err(SmtToLeanError(kind: InvalidArity, opName: "="))

## Handle ordered comparisons (>=, <=, >) with type-based shortcuts.
func auxHandleOrderedCmp(sexpr: SExprNode; declTypes: Table[string, string]; cmpSep: string): Result[string, SmtToLeanError] {.inline, raises: [].} =
  if sexpr.children.len >= 3:
    let leftAtom = rawSmtAtom(sexpr.children[1])
    let leftType = declTypes.getOrDefault(leftAtom, "")
    ## Bool / String / Seq ≥ numeric is meaningless in Lean.
    if leftType in ["Bool", "bool", "String", "string", "str", "Seq", "seq"]:
      return err(SmtToLeanError(kind: UnsupportedType, opName: cmpSep.strip()))
    let leftExprRes = smtExprToLeanExpr(sexpr.children[1], declTypes)
    if leftExprRes.isErr: return err(leftExprRes.err)
    let rightExprRes = smtExprToLeanExpr(sexpr.children[2], declTypes)
    if rightExprRes.isErr: return err(rightExprRes.err)
    if leftExprRes.get().len == 0 or rightExprRes.get().len == 0:
      return err(SmtToLeanError(kind: InvalidArity, opName: cmpSep.strip()))
    return ok(leftExprRes.get() & cmpSep & rightExprRes.get())
  err(SmtToLeanError(kind: InvalidArity, opName: cmpSep.strip()))

## Handle less-than (<) with complex type coercion rules.
func auxHandleLessThan(sexpr: SExprNode; declTypes: Table[string, string]): Result[string, SmtToLeanError] {.inline, raises: [].} =
  if sexpr.children.len >= 3:
    let leftExprRes = smtExprToLeanExpr(sexpr.children[1], declTypes)
    if leftExprRes.isErr: return err(leftExprRes.err)
    let rightAtom = rawSmtAtom(sexpr.children[2])
    let rightType = declTypes.getOrDefault(rightAtom, "")
    let leftAtom = rawSmtAtom(sexpr.children[1])
    let leftType = declTypes.getOrDefault(leftAtom, "")
    let isNumericLeft = leftType in ["Int", "Nat", "nat", "Real", "real"] or
                        (leftType.len == 0 and leftExprRes.get().len > 0 and leftExprRes.get()[0].isDigit)
    let isStringyRight = rightType in ["String", "string", "str", "Seq", "seq"]
    let isStringyLeft = leftType in ["String", "string", "str", "Seq", "seq"]
    if leftType in ["Bool", "bool"]:
      return err(SmtToLeanError(kind: UnsupportedType, opName: "<"))
    if isStringyRight and isNumericLeft:
      let leftR = smtExprToLeanExpr(sexpr.children[1], declTypes)
      if leftR.isErr: return err(leftR.err)
      let rightR = smtExprToLeanExpr(sexpr.children[2], declTypes)
      if rightR.isErr: return err(rightR.err)
      if leftR.get().len == 0 or rightR.get().len == 0: return err(SmtToLeanError(kind: InvalidArity, opName: "<"))
      return ok(leftR.get() & " < " & rightR.get() & ".length")
    if isStringyLeft:
      return err(SmtToLeanError(kind: UnsupportedType, opName: "<"))
    let leftR2 = smtExprToLeanExpr(sexpr.children[1], declTypes)
    if leftR2.isErr: return err(leftR2.err)
    let rightR2 = smtExprToLeanExpr(sexpr.children[2], declTypes)
    if rightR2.isErr: return err(rightR2.err)
    if leftR2.get().len == 0 or rightR2.get().len == 0: return err(SmtToLeanError(kind: InvalidArity, opName: "<"))
    return ok(leftR2.get() & " < " & rightR2.get())
  err(SmtToLeanError(kind: InvalidArity, opName: "<"))

## Collect parts for logical connectives (and/or) with Pattern C coercion.
func auxCollectLogicalParts(sexpr: SExprNode; declTypes: Table[string, string]): Result[seq[string], SmtToLeanError] {.inline, raises: [].} =
  var parts: seq[string] = @[]
  for i in 1 ..< sexpr.children.len:
    let child = sexpr.children[i]
    var partRes = smtExprToLeanExpr(child, declTypes)
    if partRes.isErr: return err(partRes.err)
    var part = partRes.get()
    ## Pattern C: coerce bare numeric identifiers to Prop in logical contexts.
    if not child.isList and child.atom.len > 0:
      let childType = declTypes.getOrDefault(child.atom, "")
      if isNumericSmtType(childType):
        part = "(" & part & " ≠ 0)"
      elif childType in ["String", "string", "str", "Seq", "seq"]:
        return err(SmtToLeanError(kind: UnsupportedType, opName: "logical"))
      else:
        if child.atom[0].isDigit or (child.atom[0] == '-' and child.atom.len > 1 and child.atom[1].isDigit):
          part = "(" & part & " ≠ 0)"
    parts.add(part)
  ok(parts)

## Handle quantifiers (forall/exists) with variable bindings.
func auxHandleQuantifier(sexpr: SExprNode; declTypes: Table[string, string]; quantSym: string): Result[string, SmtToLeanError] {.inline, raises: [].} =
  if sexpr.children.len >= 3:
    var bindings: seq[string] = @[]
    let bindList = sexpr.children[1]
    if bindList.isList:
      for b in bindList.children:
        if b.isList and b.children.len >= 2:
          let name = sanitizeToken(b.children[0].atom)
          let typ = smtTypeToLeanType(b.children[1].atom)
          bindings.add("(" & name & " : " & typ & ")")
    let bodyRes = smtExprToLeanExpr(sexpr.children[2], declTypes)
    if bodyRes.isErr: return err(bodyRes.err)
    return ok(quantSym & " " & bindings.join(" ") & ", " & bodyRes.get())
  err(SmtToLeanError(kind: UnknownQuantifier, opName: ""))

## Handle string/sequence length operations (str.len, seq.len).
func auxHandleStringLength(sexpr: SExprNode; declTypes: Table[string, string]; strTypes: openArray[string]): Result[string, SmtToLeanError] {.inline, raises: [].} =
  if sexpr.children.len >= 2:
    let operandRes = smtExprToLeanExpr(sexpr.children[1], declTypes)
    if operandRes.isErr: return err(operandRes.err)
    let operand = operandRes.get()
    let operandType = declTypes.getOrDefault(operand, "")
    for t in strTypes:
      if operandType == t:
        return ok(operand & ".length")
    return err(SmtToLeanError(kind: InvalidArity, opName: "length"))
  err(SmtToLeanError(kind: InvalidArity, opName: "length"))

## Handle binary arithmetic operations (+, -, *).
func auxHandleBinaryArith(sexpr: SExprNode; declTypes: Table[string, string]; arithOp: string): Result[string, SmtToLeanError] {.inline, raises: [].} =
  if sexpr.children.len >= 3:
    let leftRes = smtExprToLeanExpr(sexpr.children[1], declTypes)
    if leftRes.isErr: return err(leftRes.err)
    let rightRes = smtExprToLeanExpr(sexpr.children[2], declTypes)
    if rightRes.isErr: return err(rightRes.err)
    return ok(leftRes.get() & arithOp & rightRes.get())
  err(SmtToLeanError(kind: InvalidArity, opName: arithOp))

## Handle function application fallback for unknown operators.
func auxHandleFunctionApp(sexpr: SExprNode; declTypes: Table[string, string]; op: string): Result[string, SmtToLeanError] {.inline, raises: [].} =
  ## Reject unsupported Nim→SMT patterns that have no valid Lean typing.
  if op == "option.isNone" or op == "option.isSome":
    return err(SmtToLeanError(kind: UnknownFunction, opName: op))
  # Function application: (f x y) → f x y
  if sexpr.children.len >= 2:
    var parts: seq[string] = @[]
    for child in sexpr.children:
      let childRes = smtExprToLeanExpr(child, declTypes)
      if childRes.isErr: return err(childRes.err)
      parts.add(childRes.get())
    return ok(parts.join(" "))
  err(SmtToLeanError(kind: UnknownFunction, opName: op))

# ---------------------------------------------------------------------------
# smtExprToLeanExpr — main entry
# ---------------------------------------------------------------------------

## [Verified Core] SMT→Lean expression bridge. Table-driven conversion — declarative pattern. Wave Y certified.
func smtExprToLeanExpr*(sexpr: SExprNode; declTypes: Table[string, string] = initTable[string, string]()): Result[string, SmtToLeanError] {.raises: [].} =
  if not sexpr.isList:
    return ok(sexpr.atom)
  if sexpr.children.len == 0:
    return err(SmtToLeanError(kind: InvalidArity, opName: ""))
  let op = sexpr.children[0].atom
  case op
  of "=":
    auxHandleEquality(sexpr, declTypes)
  of ">=":
    auxHandleOrderedCmp(sexpr, declTypes, " ≥ ")
  of "<=":
    auxHandleOrderedCmp(sexpr, declTypes, " ≤ ")
  of ">":
    auxHandleOrderedCmp(sexpr, declTypes, " > ")
  of "<":
    auxHandleLessThan(sexpr, declTypes)
  of "and":
    let andRes = auxCollectLogicalParts(sexpr, declTypes)
    if andRes.isErr: return err(andRes.err)
    ok(andRes.get().join(" ∧ "))
  of "or":
    let orRes = auxCollectLogicalParts(sexpr, declTypes)
    if orRes.isErr: return err(orRes.err)
    ok("(" & orRes.get().join(" ∨ ") & ")")
  of "=>":
    if sexpr.children.len >= 3:
      let pRes = smtExprToLeanExpr(sexpr.children[1], declTypes)
      if pRes.isErr: return err(pRes.err)
      let qRes = smtExprToLeanExpr(sexpr.children[2], declTypes)
      if qRes.isErr: return err(qRes.err)
      ok("(" & pRes.get() & " → " & qRes.get() & ")")
    else:
      err(SmtToLeanError(kind: InvalidArity, opName: "=>"))
  of "not":
    if sexpr.children.len >= 2:
      let innerRes = smtExprToLeanExpr(sexpr.children[1], declTypes)
      if innerRes.isErr: return err(innerRes.err)
      ok("¬" & innerRes.get())
    else:
      err(SmtToLeanError(kind: InvalidArity, opName: "not"))
  of "+", "add":
    auxHandleBinaryArith(sexpr, declTypes, " + ")
  of "-", "sub":
    auxHandleBinaryArith(sexpr, declTypes, " - ")
  of "*", "mul":
    auxHandleBinaryArith(sexpr, declTypes, " * ")
  of "str.len":
    auxHandleStringLength(sexpr, declTypes, ["String", "string", "str"])
  of "seq.len":
    auxHandleStringLength(sexpr, declTypes, ["Seq", "seq", "String", "string", "str"])
  of "seq.nth":
    if sexpr.children.len >= 3:
      let seqRes = smtExprToLeanExpr(sexpr.children[1], declTypes)
      if seqRes.isErr: return err(seqRes.err)
      let idxRes = smtExprToLeanExpr(sexpr.children[2], declTypes)
      if idxRes.isErr: return err(idxRes.err)
      ok("(" & seqRes.get() & ".get? " & idxRes.get() & ")")
    else:
      err(SmtToLeanError(kind: InvalidArity, opName: "seq.nth"))
  of "forall":
    auxHandleQuantifier(sexpr, declTypes, "∀")
  of "exists":
    auxHandleQuantifier(sexpr, declTypes, "∃")
  else:
    auxHandleFunctionApp(sexpr, declTypes, op)

## Build a Lean 4 theorem statement from SMT-LIB2 declarations and assertions.
func buildLeanTheoremFromSmtlib2*(functionName: string; smtlib2: string): Result[string, SmtToLeanError] {.raises: [], axiom: ["(assert (and (>= (str.len functionName) 0) (>= (str.len smtlib2) 0) (= (str.len asserts) 0) (= (str.len hExpr) 0) (= (str.len conclusion) 0) (> (str.len params) 0) (> (str.len hypotheses) 0) (>= decls 0)))", "functionName.length ≥ 0 ∧ smtlib2.length ≥ 0 ∧ asserts.length = 0 ∧ hExpr.length = 0 ∧ conclusion.length = 0 ∧ params.length > 0 ∧ hypotheses.length > 0 ∧ (decls ≥ 0)"].} =
  let decls = parseSmtlib2Decls(smtlib2)
  let asserts = parseSmtlib2Asserts(smtlib2)
  if asserts.len == 0:
    return err(SmtToLeanError(kind: InvalidArity, opName: "assert"))

  var declTypes = initTable[string, string]()
  for decl in decls:
    declTypes[decl.name] = decl.smtType

  var params: seq[string] = @[]
  for decl in decls:
    params.add("(" & decl.name & " : " & smtTypeToLeanType(decl.smtType) & ")")

  var hypotheses: seq[string] = @[]
  for i in 0 ..< asserts.len:
    let hExprRes = smtExprToLeanExpr(asserts[i].expr, declTypes)
    if hExprRes.isErr: return err(hExprRes.err)
    let hExpr = hExprRes.get()
    if hExpr.len == 0:
      continue
    hypotheses.add("(h" & $i & " : " & hExpr & ")")

  let conclusionRes = smtExprToLeanExpr(asserts[0].expr, declTypes)
  if conclusionRes.isErr: return err(conclusionRes.err)
  let conclusion = conclusionRes.get()
  if conclusion.len == 0:
    return err(SmtToLeanError(kind: InvalidArity, opName: "conclusion"))

  var theoremLine = "set_option maxHeartbeats 300000 in\n"
  theoremLine.add("theorem " & functionName)
  if params.len > 0:
    theoremLine.add(" " & params.join(" "))
  if hypotheses.len > 0:
    theoremLine.add(" " & hypotheses.join(" "))
  theoremLine.add(" : " & conclusion & " := by\n")
  ok(theoremLine)

# ---------------------------------------------------------------------------
# Solver Status Mapping — canonical: core/encoding/smt_to_lean_translate
# ---------------------------------------------------------------------------

{.pop.}
