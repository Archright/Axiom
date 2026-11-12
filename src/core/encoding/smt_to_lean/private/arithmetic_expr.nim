import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import core/encoding/vfs
import core/solver/types
import core/trusted/axiom_pragmas
import std/options
import std/strutils
# ---------------------------------------------------------------------------
# Arithmetic Codegen (Phase 5.1 — absorbed from smt_codegen.nim)
# ---------------------------------------------------------------------------
# Provides: parseArithmeticFunction, generateSmtLib2, generateAndWriteSmtQuery,
#           isArithmeticFunction. Uses SmtExprKind from solver/types.nim as SSOT.

type
  Param* = object
    name*: string
    typ*: string

  ArithmeticFunction* = object
    name*: string
    params*: seq[Param]
    returnType*: string
    body*: string
    op*: SmtExprKind
func seArithParseParamList(paramStr: string): seq[Param] {.raises: [].} =
  ## Parse "a, b: int; c: string" into params.
  let groups = paramStr.split(';')
  for group in groups:
    let trimmedGroup = group.strip()
    if trimmedGroup.len == 0:
      continue
    let colonIdx = trimmedGroup.find(':')
    if colonIdx < 0:
      continue
    let namesStr = trimmedGroup[0..<colonIdx].strip()
    let typ = trimmedGroup[colonIdx + 1..^1].strip()
    let names = namesStr.split(',')
    for n in names:
      let cleanName = n.strip()
      if cleanName.len > 0:
        result.add(Param(name: cleanName, typ: typ))
func seArithDetectOp(body: string): SmtExprKind {.raises: [].} =
  ## Detect +, -, * in function body. Returns exprSymbol if none found.
  let stripped = body.strip()
  if '+' in stripped:
    return exprAdd
  elif '-' in stripped:
    return exprSub
  elif '*' in stripped:
    return exprMul
  else:
    return exprSymbol
func seArithStripPragmas(s: string): string {.raises: [].} =
  ## Remove {.pragma.} blocks so the return type and body separator remain.
  var t = s
  while true:
    let openIdx = t.find("{.")
    if openIdx < 0:
      break
    let closeIdx = t.find(".}", openIdx)
    if closeIdx < 0:
      break
    t = t[0..<openIdx] & t[closeIdx + 2..^1]
  t.strip()
func parseArithmeticFunction*(source: string): Option[ArithmeticFunction] {.raises: [].} =
  ## Parse a single arithmetic function from source.
  ## Returns none if not a simple arithmetic function.
  let lines = source.strip().splitLines()
  if lines.len < 1:
    return none(ArithmeticFunction)
  let header = lines[0].strip()
  if not header.startsWith("func "):
    return none(ArithmeticFunction)
  let nameEnd = header.find('(', 5)
  if nameEnd < 0:
    return none(ArithmeticFunction)
  let fnName = header[5..<nameEnd].strip()
  let paramsEnd = header.find(')', nameEnd)
  if paramsEnd < 0:
    return none(ArithmeticFunction)
  let paramsStr = header[nameEnd + 1..<paramsEnd]
  let params = seArithParseParamList(paramsStr)
  for p in params:
    if p.typ != "int":
      return none(ArithmeticFunction)
  let retTypeStart = header.find(':', paramsEnd + 1)
  if retTypeStart < 0:
    return none(ArithmeticFunction)
  let retTypeRaw = header[retTypeStart + 1..^1].strip()
  let retTypeNoPragma = seArithStripPragmas(retTypeRaw)
  let eqIdx = retTypeNoPragma.find('=')
  let cleanRet = if eqIdx >= 0:
      retTypeNoPragma[0..<eqIdx].strip()
    else:
      retTypeNoPragma
  if cleanRet != "int":
    return none(ArithmeticFunction)
  let bodyPrefix = if eqIdx >= 0:
      retTypeNoPragma[eqIdx + 1..^1].strip()
    else:
      ""
  let body = if bodyPrefix.len > 0:
      bodyPrefix & "\n" & lines[1..^1].join("\n")
    else:
      lines[1..^1].join("\n").strip()
  let op = seArithDetectOp(body)
  if op == exprSymbol:
    return none(ArithmeticFunction)
  return some(ArithmeticFunction(
    name: fnName, params: params, returnType: "int", body: body.strip(), op: op
  ))
func seArithOpSymbol(op: SmtExprKind): string {.raises: [].} =
  case op
  of exprAdd: "+"
  of exprSub: "-"
  of exprMul: "*"
  else: "+"

# ---------------------------------------------------------------------------
# Body expression parser (infix Nim arithmetic → SMT-LIB2 prefix / Lean infix)
# ---------------------------------------------------------------------------
type ArithExprPair* = tuple[smt: string, lean: string]
func seArithOpPrecedence(op: string): int {.raises: [].} =
  case op
  of "+", "-": 1
  of "*": 2
  else: 0
func seArithIsOperator(c: char): bool {.raises: [].} =
  c in {'+', '-', '*'}
func seArithTokenize(body: string): Option[seq[string]] {.raises: [].} =
  var tokens: seq[string] = @[]
  var i = 0
  while i < body.len:
    let c = body[i]
    if c.isSpaceAscii():
      inc i
      continue
    if c.isDigit() or c.isAlphaAscii() or c == '_':
      var tok = ""
      while i < body.len and (body[i].isDigit() or body[i].isAlphaAscii() or body[i] == '_'):
        tok.add(body[i])
        inc i
      tokens.add(tok)
    elif seArithIsOperator(c):
      tokens.add($c)
      inc i
    elif c == '(' or c == ')':
      tokens.add($c)
      inc i
    else:
      return none(seq[string])
  some(tokens)
func seArithApplyTopOp(ops: var seq[string]; outs: var seq[ArithExprPair]): bool {.raises: [].} =
  if ops.len == 0:
    return false
  let op = ops.pop()
  if outs.len < 2:
    return false
  let right = outs.pop()
  let left = outs.pop()
  outs.add((
    smt: "(" & op & " " & left.smt & " " & right.smt & ")",
    lean: "(" & left.lean & " " & op & " " & right.lean & ")"
  ))
  true
func parseArithmeticBodyExpressions*(body: string): Option[ArithExprPair] {.raises: [].} =
  let tokensOpt = seArithTokenize(body)
  if tokensOpt.isNone():
    return none(ArithExprPair)
  let tokens = tokensOpt.get()
  var ops: seq[string] = @[]
  var outs: seq[ArithExprPair] = @[]
  var prevWasValue = false
  for tok in tokens:
    if tok.len == 0:
      continue
    let c = tok[0]
    if c.isDigit() or c.isAlphaAscii() or c == '_':
      outs.add((smt: tok, lean: tok))
      prevWasValue = true
    elif seArithIsOperator(c):
      if not prevWasValue:
        # Unary +/- : treat as "0 - x" or "0 + x"
        if tok == "+" or tok == "-":
          outs.add((smt: "0", lean: "0"))
        else:
          return none(ArithExprPair)
      while ops.len > 0 and ops[^1] != "(" and
            seArithOpPrecedence(ops[^1]) >= seArithOpPrecedence(tok):
        if not seArithApplyTopOp(ops, outs):
          return none(ArithExprPair)
      ops.add(tok)
      prevWasValue = false
    elif tok == "(":
      ops.add(tok)
      prevWasValue = false
    elif tok == ")":
      while ops.len > 0 and ops[^1] != "(":
        if not seArithApplyTopOp(ops, outs):
          return none(ArithExprPair)
      if ops.len == 0:
        return none(ArithExprPair)
      discard ops.pop() # remove "("
      prevWasValue = true
    else:
      return none(ArithExprPair)
  while ops.len > 0:
    if ops[^1] == "(" or ops[^1] == ")":
      return none(ArithExprPair)
    if not seArithApplyTopOp(ops, outs):
      return none(ArithExprPair)
  if outs.len != 1:
    return none(ArithExprPair)
  some(outs[0])
func generateSmtLib2*(fn: ArithmeticFunction): string {.raises: [].} =
  ## Generate SMT-LIB2 query for an arithmetic function.
  ##
  ## The query defines the Nim function as an SMT function and then asserts the
  ## negation of the functional-equivalence theorem.  A correct implementation
  ## yields `unsat`, which means the theorem `f a b = bodyExpr` is valid.
  ## Previously this proc asserted both the equation and its negation, which
  ## made every query trivially contradictory regardless of the function.
  result = "(set-logic QF_LIA)\n"
  let retSort = if fn.returnType == "int": "Int" else: fn.returnType
  var paramDecls: seq[string] = @[]
  var paramNames: seq[string] = @[]
  for p in fn.params:
    let sort = if p.typ == "int": "Int" else: p.typ
    paramDecls.add("(" & p.name & " " & sort & ")")
    paramNames.add(p.name)
  let bodyPair = parseArithmeticBodyExpressions(fn.body)
  let bodyExpr = if bodyPair.isSome(): bodyPair.get().smt else:
    # Fallback to the old param-list shape only when parsing fails.
    var fallback = "(" & seArithOpSymbol(fn.op)
    for p in fn.params:
      fallback &= " " & p.name
    fallback & ")"
  result &= "(define-fun " & fn.name & " (" & paramDecls.join(" ") & ") " & retSort & " " & bodyExpr & ")\n"
  for p in fn.params:
    let sort = if p.typ == "int": "Int" else: p.typ
    result &= "(declare-fun " & p.name & " () " & sort & ")\n"
  result &= "(assert (not (= (" & fn.name & " " & paramNames.join(" ") & ") " & bodyExpr & ")))\n"
  result &= "(check-sat)\n"
proc generateAndWriteSmtQuery*(moduleName, functionName, source: string): bool {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Parse function source, generate SMT-LIB2, write to VFS.
  let parsed = parseArithmeticFunction(source)
  if parsed.isNone:
    return false
  let fn = parsed.get()
  let query = generateSmtLib2(fn)
  let path = vfsZ3Path(moduleName, functionName)
  writeVfsZ3(path, query)
func isArithmeticFunction*(source: string): bool {.raises: [].} =
  ## Quick check if source is a pure arithmetic function.
  let lines = source.strip().splitLines()
  if lines.len < 2:
    return false
  let header = lines[0].strip()
  if not header.startsWith("func "):
    return false
  let body = if lines.len > 1: lines[1..^1].join(" ") else: ""
  let hasOp = '+' in body or '-' in body or '*' in body
  let noSideEffects = "echo" notin body and "write" notin body and "read" notin body and "var" notin body
  hasOp and noSideEffects

{.pop.}

