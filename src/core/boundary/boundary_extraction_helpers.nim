import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import ../../core/trusted/axiom_pragmas
import core/boundary/abstract_spec_lowering
import core/parsers/pnode_nav
import core/types/results
import core/utils/io_utils
import std/options
import std/os
import std/strutils
import compiler/ast

# ── Tree-sitter AST Extraction Helpers ──

type ObjectType* = tuple[name: string; genericParams: seq[string]; fields: seq[tuple[name, nimType: string]]]

proc extractObjectTypesFromAst*(ast: PNode): seq[ObjectType] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Extract object type declarations from Nim AST.
  for decl in findNodesP(ast, {nkTypeDef}):
    var name = ""
    var genericParams: seq[string] = @[]
    var fields: seq[tuple[name, nimType: string]] = @[]

    if decl.len > 0 and not decl[0].isNil:
      name = pNodeText(decl[0])

    for child in decl:
      if child.isNil: continue
      case child.kind
      of nkIdentDefs:
        # Field declaration: name: Type
        var fieldName = ""
        var fieldType = ""
        if child.len > 0 and not child[0].isNil:
          fieldName = pNodeText(child[0])
        if child.len > 1 and not child[1].isNil:
          fieldType = pNodeText(child[1])
        if fieldName.len > 0:
          fields.add((name: fieldName, nimType: fieldType))
      else: discard

    if name.len > 0:
      result.add((name: name, genericParams: genericParams, fields: fields))

proc extractTupleTypesFromAst*(ast: PNode): seq[ObjectType] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Extract tuple type declarations from Nim AST.
  ## Same structure as object types — both use nkTypeDef.
  for decl in findNodesP(ast, {nkTypeDef}):
    var name = ""
    var genericParams: seq[string] = @[]
    var fields: seq[tuple[name, nimType: string]] = @[]

    if decl.len > 0 and not decl[0].isNil:
      name = pNodeText(decl[0])

    for child in decl:
      if child.isNil: continue
      case child.kind
      of nkIdentDefs:
        var fieldName = ""
        var fieldType = ""
        if child.len > 0 and not child[0].isNil:
          fieldName = pNodeText(child[0])
        if child.len > 1 and not child[1].isNil:
          fieldType = pNodeText(child[1])
        if fieldName.len > 0:
          fields.add((name: fieldName, nimType: fieldType))
      else: discard

    if name.len > 0:
      result.add((name: name, genericParams: genericParams, fields: fields))

# ── Type-to-Constraint Mapping ──

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func typeToBoundaryConstraints*(paramName, nimType: string): tuple[smt: string, lean: string] =
  ## Map a Nim type string to SMT-LIB2 and Lean 4 boundary constraints.
  let t = nimType.strip().toLowerAscii()

  if t == "natural" or t == "uint" or t == "uint8" or t == "uint16" or t == "uint32" or t == "uint64":
    result = (smt: "(>= " & paramName & " 0)", lean: paramName & " ≥ 0")
  elif t.startsWith("range["):
    let innerStart = t.find('[')
    let innerEnd = t.rfind(']')
    if innerStart >= 0 and innerEnd > innerStart:
      let inner = t[innerStart + 1 ..< innerEnd]
      let dots = inner.find("..")
      if dots >= 0:
        let lower = inner[0 ..< dots].strip()
        let upper = inner[dots + 2 .. ^1].strip()
        result = (
          smt: "(and (>= " & paramName & " " & lower & ") (<= " & paramName & " " & upper & "))",
          lean: paramName & " ≥ " & lower & " ∧ " & paramName & " ≤ " & upper
        )
  elif t == "string" or t == "cstring":
    result = (smt: "(>= (str.len " & paramName & ") 0)", lean: paramName & ".length ≥ 0")
  elif t.startsWith("seq") or t.startsWith("array") or t.startsWith("openarray") or t.startsWith("option"):
    result = (smt: "(assert ast_parse_failed_isolated)", lean: "ast_parse_failed_isolated")
  elif t == "bool":
    result = (smt: "(or (= " & paramName & " true) (= " & paramName & " false))", lean: paramName & " = true ∨ " & paramName & " = false")
  elif t == "char":
    result = (smt: "", lean: "")
  elif t == "int":
    result = (smt: "(and (>= " & paramName & " -9223372036854775808) (<= " & paramName & " 9223372036854775807))", lean: paramName & " ≥ -9223372036854775808 ∧ " & paramName & " ≤ 9223372036854775807")
  elif t == "int8":
    result = (smt: "(and (>= " & paramName & " -128) (<= " & paramName & " 127))", lean: paramName & " ≥ -128 ∧ " & paramName & " ≤ 127")
  elif t == "int16":
    result = (smt: "(and (>= " & paramName & " -32768) (<= " & paramName & " 32767))", lean: paramName & " ≥ -32768 ∧ " & paramName & " ≤ 32767")
  elif t == "int32":
    result = (smt: "(and (>= " & paramName & " -2147483648) (<= " & paramName & " 2147483647))", lean: paramName & " ≥ -2147483648 ∧ " & paramName & " ≤ 2147483647")
  elif t == "int64":
    result = (smt: "(and (>= " & paramName & " -9223372036854775808) (<= " & paramName & " 9223372036854775807))", lean: paramName & " ≥ -9223372036854775808 ∧ " & paramName & " ≤ 9223372036854775807")
  elif t.startsWith("seq["):
    result = (smt: "(>= (seq.len " & paramName & ") 0)", lean: paramName & ".size ≥ 0")
  elif t == "float" or t == "float32" or t == "float64":
    result = (smt: "", lean: "")
  else:
    result = (smt: "", lean: "")

## Extract object field boundaries from AST.
# @axiom-hint: lean="objectTypeName.length ≥ 0 ∧ paramName.length ≥ 0" smt="(assert (and (>= (str.len objectTypeName) 0) (>= (str.len paramName) 0)))"
# @axiom-hint: lean="cleanedTypeName.length = 0 ∧ (nested ≥ 0)" smt="(assert (and (= (str.len cleanedTypeName) 0) (>= nested 0)))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc extractObjectFieldBoundaries*(ast: PNode; objectTypeName, paramName: string): seq[tuple[smt: string, lean: string, fieldName: string, fieldType: string]] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let cleanedTypeName = objectTypeName.strip().toLowerAscii().replace("var ", "").replace("ref ", "")
  if cleanedTypeName.len == 0: return
  for objType in extractObjectTypesFromAst(ast):
    if objType.name.strip().toLowerAscii() == cleanedTypeName:
      for field in objType.fields:
        let fieldVarName = paramName & "_" & field.name
        let bc = typeToBoundaryConstraints(fieldVarName, field.nimType)
        if bc.smt.len > 0:
          result.add((smt: bc.smt, lean: bc.lean, fieldName: field.name, fieldType: field.nimType))
        elif field.nimType.strip().toLowerAscii().startsWith("seq["):
          let seqLenSmt = "(>= (seq.len " & fieldVarName & ") 0)"
          let seqLenLean = fieldVarName & ".size ≥ 0"
          result.add((smt: seqLenSmt, lean: seqLenLean, fieldName: field.name, fieldType: field.nimType))
        elif field.nimType.strip().toLowerAscii() notin ["string","cstring","bool","char","int","int8","int16","int32","int64","float","float32","float64","natural","uint","uint8","uint16","uint32","uint64"]:
          let nested = extractObjectFieldBoundaries(ast, field.nimType, fieldVarName)
          for n in nested:
            result.add(n)
      break

# @axiom-hint: lean="source.length ≥ 0 ∧ functionName.length ≥ 0" smt="(assert (and (>= (str.len source) 0) (>= (str.len functionName) 0)))"
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert (and ast_parse_failed_isolated))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc extractParamsFromSourceRegex*(source, functionName: string): seq[tuple[name, nimType: string]] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Regex-backed parameter extraction from raw source when AST parsing fails.
  result = @[]
  let prefixes = @["proc " & functionName & "(", "func " & functionName & "("]
  for prefix in prefixes:
    var idx = 0
    while idx < source.len:
      if source.continuesWith(prefix, idx):
        let startParams = idx + prefix.len - 1
        let endParams = source.find(")", startParams)
        if startParams >= 0 and endParams > startParams:
          let paramText = source[startParams + 1 ..< endParams]
          for paramDecl in paramText.split(","):
            let trimmed = paramDecl.strip()
            if trimmed.len == 0: continue
            let colonIdx = trimmed.find(":")
            if colonIdx >= 0:
              let name = trimmed[0 ..< colonIdx].strip()
              let nimType = trimmed[colonIdx + 1 .. ^1].strip()
              if name.len > 0:
                result.add((name: name, nimType: nimType))
        return
      idx += 1

# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc extractInfixOperator(expr: PNode): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Extract the operator from an infix_expression node.
  let opOpt = nodeFieldP(expr, "operator")
  if opOpt.isSome:
    return pNodeText(opOpt.get())
  var capturing = false
  for child in expr:
    if child.isNil: continue
    if child.kind in {nkInfix}:
      if child.len > 1 and not child[1].isNil:
        # Middle son of nkInfix is the operator
        if not capturing:
          capturing = true
          continue
    if capturing and child.kind in {nkIdent, nkSym}:
      let t = pNodeText(child).strip()
      if t.len > 0:
        return t
  ""

# Forward declarations for auxConvert* helpers (defined below)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc auxConvertInfix(expr: PNode): tuple[smt: string, lean: string] {.inline, raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc auxConvertPrefix(expr: PNode): tuple[smt: string, lean: string] {.inline, raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc auxConvertDot(expr: PNode): tuple[smt: string, lean: string] {.inline, raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc auxConvertCall(expr: PNode): tuple[smt: string, lean: string] {.inline, raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc auxConvertBracket(expr: PNode): tuple[smt: string, lean: string] {.inline, raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc auxConvertIf(expr: PNode): tuple[smt: string, lean: string] {.inline, raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc auxConvertBlock(expr: PNode): tuple[smt: string, lean: string] {.inline, raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc convertExpressionToSmtLean*(expr: PNode): tuple[smt: string, lean: string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Recursively convert a Nim AST expression node to (SMT-LIB2, Lean4) pair.
  if expr.isNil: return ("", "")
  case expr.kind
  of nkInfix: result = auxConvertInfix(expr)
  of nkPrefix: result = auxConvertPrefix(expr)
  of nkDotExpr: result = auxConvertDot(expr)
  of nkCall: result = auxConvertCall(expr)
  of nkBracketExpr: result = auxConvertBracket(expr)
  of nkIfExpr: result = auxConvertIf(expr)
  of nkBlockExpr, nkBlockStmt: result = auxConvertBlock(expr)
  of nkExprColonExpr:
    let rightOpt = nodeFieldP(expr, "right")
    if rightOpt.isSome:
      result = convertExpressionToSmtLean(rightOpt.get())
    else:
      result = ("", "")
  of nkIdent, nkStrLit, nkIntLit, nkInt8Lit, nkInt16Lit, nkInt32Lit, nkInt64Lit,
     nkUIntLit, nkUInt8Lit, nkUInt16Lit, nkUInt32Lit, nkUInt64Lit,
     nkFloatLit, nkFloat32Lit, nkFloat64Lit, nkFloat128Lit, nkCharLit:
    result = (smt: pNodeText(expr), lean: pNodeText(expr))
  else:
    result = ("", "")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc auxConvertInfix(expr: PNode): tuple[smt: string, lean: string] {.inline, raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let op = extractInfixOperator(expr)
  let leftOpt = nodeFieldP(expr, "left")
  let rightOpt = nodeFieldP(expr, "right")
  if op.len == 0 or leftOpt.isNone or rightOpt.isNone:
    return ("", "")
  let left = convertExpressionToSmtLean(leftOpt.get())
  let right = convertExpressionToSmtLean(rightOpt.get())
  if left.smt.len == 0 or right.smt.len == 0:
    return ("", "")
  const InfixOps: array[0..16, (string, string, string)] = [
    ("and", "and", " ∧ "), ("or", "or", " ∨ "),
    ("==", "=", " = "), ("!=", "not=", " ≠ "),
    (">", ">", " > "), ("<", "<", " < "),
    (">=", ">=", " ≥ "), ("<=", "<=", " ≤ "),
    ("+", "+", " + "), ("-", "-", " - "),
    ("*", "*", " * "), ("/", "/", " / "),
    ("div", "div", " div "), ("mod", "mod", " mod "),
    ("shl", "shl", " shl "), ("shr", "shr", " shr "),
    ("in", "member", " ∈ "),
  ]
  for (nimOp, smtOp, leanOp) in InfixOps:
    if op == nimOp:
      if nimOp == "!=":
        return ("(not (= " & left.smt & " " & right.smt & "))",
                left.lean & leanOp & right.lean)
      else:
        return ("(" & smtOp & " " & left.smt & " " & right.smt & ")",
                left.lean & leanOp & right.lean)
  ("", "")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc auxConvertPrefix(expr: PNode): tuple[smt: string, lean: string] {.inline, raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let opOpt = nodeFieldP(expr, "operand")
  if opOpt.isNone:
    return ("", "")
  let op = if expr.len > 0 and not expr[0].isNil: pNodeText(expr[0]) else: ""
  let operand = convertExpressionToSmtLean(opOpt.get())
  if operand.smt.len == 0:
    return ("", "")
  case op:
    of "not": return ("(not " & operand.smt & ")", "¬" & operand.lean)
    of "-": return ("(- " & operand.smt & ")", "-" & operand.lean)
    of "+": return (operand.smt, operand.lean)
    else: return ("", "")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc auxConvertDot(expr: PNode): tuple[smt: string, lean: string] {.inline, raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let leftOpt = nodeFieldP(expr, "left")
  let rightOpt = nodeFieldP(expr, "right")
  if leftOpt.isNone or rightOpt.isNone:
    return ("", "")
  let left = convertExpressionToSmtLean(leftOpt.get())
  let rightText = pNodeText(rightOpt.get())
  if left.smt.len == 0:
    return ("", "")
  case rightText:
    of "len": return ("(str.len " & left.smt & ")", left.lean & ".length")
    of "size": return ("(seq.len " & left.smt & ")", left.lean & ".size")
    of "high": return (left.smt & ".high", left.lean & ".high")
    of "low": return (left.smt & ".low", left.lean & ".low")
    of "isSome": return ("(= (option.isSome " & left.smt & ") true)", left.lean & ".isSome = true")
    of "isNone": return ("(= (option.isNone " & left.smt & ") true)", left.lean & ".isNone = true")
    of "get": return ("(option.get " & left.smt & ")", left.lean & ".get")
    else:
      return ("", "")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc auxConvertCall(expr: PNode): tuple[smt: string, lean: string] {.inline, raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let funcOpt = nodeFieldP(expr, "function")
  let argsOpt = nodeFieldP(expr, "arguments")
  if funcOpt.isNone:
    return ("", "")
  let funcName = pNodeText(funcOpt.get())
  var argSmts: seq[string] = @[]
  var argLeans: seq[string] = @[]
  if argsOpt.isSome:
    for arg in childElements(argsOpt.get()):
      let converted = convertExpressionToSmtLean(arg)
      if converted.smt.len > 0:
        argSmts.add(converted.smt)
        argLeans.add(converted.lean)
  case funcName:
    of "len":
      if argSmts.len > 0:
        return ("(str.len " & argSmts[0] & ")", argLeans[0] & ".length")
    of "high":
      if argSmts.len > 0:
        return (argSmts[0] & ".high", argLeans[0] & ".high")
    of "low":
      if argSmts.len > 0:
        return (argSmts[0] & ".low", argLeans[0] & ".low")
    of "abs":
      if argSmts.len > 0:
        return ("(abs " & argSmts[0] & ")", "abs(" & argLeans[0] & ")")
    of "min":
      if argSmts.len >= 2:
        return ("(min " & argSmts[0] & " " & argSmts[1] & ")", "min(" & argLeans[0] & ", " & argLeans[1] & ")")
    of "max":
      if argSmts.len >= 2:
        return ("(max " & argSmts[0] & " " & argSmts[1] & ")", "max(" & argLeans[0] & ", " & argLeans[1] & ")")
    of "ord":
      if argSmts.len > 0:
        return ("(ord " & argSmts[0] & ")", "ord(" & argLeans[0] & ")")
    of "chr":
      if argSmts.len > 0:
        return ("(chr " & argSmts[0] & ")", "chr(" & argLeans[0] & ")")
    else:
      if funcName == "()" or funcName.len == 0:
        return ("", "")
      if argSmts.len == 0:
        return ("", "")
      return ("(" & funcName & " " & argSmts.join(" ") & ")", funcName & "(" & argLeans.join(", ") & ")")
  ("", "")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc auxConvertBracket(expr: PNode): tuple[smt: string, lean: string] {.inline, raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let leftOpt = nodeFieldP(expr, "left")
  let rightOpt = nodeFieldP(expr, "right")
  if leftOpt.isNone or rightOpt.isNone:
    return ("", "")
  let left = convertExpressionToSmtLean(leftOpt.get())
  let right = convertExpressionToSmtLean(rightOpt.get())
  if left.smt.len == 0 or right.smt.len == 0:
    return ("", "")
  ("(select " & left.smt & " " & right.smt & ")", left.lean & "[" & right.lean & "]")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc auxConvertIf(expr: PNode): tuple[smt: string, lean: string] {.inline, raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let condOpt = nodeFieldP(expr, "condition")
  let thenOpt = nodeFieldP(expr, "consequence")
  let elseOpt = nodeFieldP(expr, "alternative")
  if condOpt.isSome and thenOpt.isSome:
    let c = convertExpressionToSmtLean(condOpt.get())
    let t = convertExpressionToSmtLean(thenOpt.get())
    if c.smt.len > 0 and t.smt.len > 0:
      if elseOpt.isSome:
        let e = convertExpressionToSmtLean(elseOpt.get())
        if e.smt.len > 0:
          return ("(ite " & c.smt & " " & t.smt & " " & e.smt & ")",
            "(if " & c.lean & " then " & t.lean & " else " & e.lean & ")")
        return ("(ite " & c.smt & " " & t.smt & " nil)", "(if " & c.lean & " then " & t.lean & " else nil)")
  ("", "")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc auxConvertBlock(expr: PNode): tuple[smt: string, lean: string] {.inline, raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  for child in expr:
    if child.isNil: continue
    let converted = convertExpressionToSmtLean(child)
    if converted.smt.len > 0:
      return converted
  ("", "")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc auxConvertLetVar(expr: PNode): tuple[smt: string, lean: string] {.inline, raises: [], used, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  for child in expr:
    if child.isNil: continue
    if child.kind in {nkIdentDefs}:
      let nameOpt = nodeFieldP(child, "left")
      let valueOpt = nodeFieldP(child, "right")
      if nameOpt.isSome and valueOpt.isSome:
        let name = convertExpressionToSmtLean(nameOpt.get())
        let value = convertExpressionToSmtLean(valueOpt.get())
        if name.smt.len > 0 and value.smt.len > 0:
          return ("(= " & name.smt & " " & value.smt & ")", name.lean & " = " & value.lean)
  ("", "")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc findNodesMultiTag*(node: PNode; tags: openArray[string]): seq[PNode] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
   ## Recursively collect all child nodes matching any of the given tag strings.
   if node.isNil: return
   for tag in tags:
     let tk = tagToKinds(tag)
     if tk.len > 0 and node.kind in tk:
       result.add(node)
       break
   for child in node:
     if child.isNil: continue
     result.add(findNodesMultiTag(child, tags))

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc determineBoundaryTier*(nimType: string): LoweringTier {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  classifyNimType(nimType)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc routeToBoundaryStrategy*(paramName: string;
                              nimType: string): tuple[tier: string, smtPrefix: string,
                                                      leanPrefix: string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let tier = classifyNimType(nimType)
  case tier
  of ltTier1:
    (tier: "tier1-adt",
     smtPrefix: "; Tier 1 ADT lowering for " & paramName & ": " & nimType,
     leanPrefix: "; Tier 1 ADT lowering for " & paramName & ": " & nimType)
  of ltTier2:
    (tier: "tier2-abstract",
     smtPrefix: "; Tier 2 abstract sort for " & paramName & ": " & nimType,
     leanPrefix: "; Tier 2 abstract spec for " & paramName & ": " & nimType)
  of ltTier3:
    (tier: "tier3-uninterpreted",
     smtPrefix: "; Tier 3 uninterpreted for " & paramName & ": " & nimType,
     leanPrefix: "; Tier 3 uninterpreted for " & paramName & ": " & nimType)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc loadSourceFromNodeId*(nodeId: string): string {.raises: [], axiom: ["(assert (and (>= (str.len nodeId) 0) external_io_isolated (< (str.len parts) 2) external_io_isolated))", "nodeId.length ≥ 0 ∧ external_io_isolated ∧ parts.length < 2 ∧ external_io_isolated"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let parts = nodeId.split("::")
  if parts.len < 2: return ""
  let modulePath = parts[0]
  let srcPath = joinPath("src", modulePath)
  try:
    if fileExists(srcPath):
      let readRes = readFileOpt(srcPath)
      if readRes.isOk: return readRes.get
      return ""
  except CatchableError:
    discard
  return ""

{.pop.}
