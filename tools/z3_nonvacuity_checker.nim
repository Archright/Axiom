import std/[os, strutils, sequtils, options]
import core/gate/gate_to_smt
import core/ir/ir_types

proc isIdentChar*(ch: char): bool {.raises: [].} =
  ch.isAlphaNumeric or ch == '_'

proc allCharsAreDigits*(s: string): bool {.raises: [].} =
  for ch in s:
    if not ch.isDigit:
      return false
  true

proc allCharsAreIdent*(s: string): bool {.raises: [].} =
  for ch in s:
    if not isIdentChar(ch):
      return false
  true

proc stripComment(line: string): string {.raises: [].} =
  var inString = false
  for ch in line:
    if ch == '"' and (result.len == 0 or result[^1] != '\\'):
      inString = not inString
    elif ch == '#' and not inString:
      break
    else:
      result.add(ch)

proc findMatchingParen(text: string; openIdx: int): int {.raises: [].} =
  var depth = 0
  for i in openIdx ..< text.len:
    if text[i] == '(':
      inc depth
    elif text[i] == ')':
      dec depth
      if depth == 0:
        return i
    else:
      discard
  -1

proc splitTopLevelCommas(text: string): seq[string] {.raises: [].} =
  var start = 0
  var parenDepth = 0
  var bracketDepth = 0
  var braceDepth = 0
  for i, ch in text:
    if ch == '(':
      inc parenDepth
    elif ch == ')':
      dec parenDepth
    elif ch == '[':
      inc bracketDepth
    elif ch == ']':
      dec bracketDepth
    elif ch == '{':
      inc braceDepth
    elif ch == '}':
      dec braceDepth
    elif ch == ',' and parenDepth == 0 and bracketDepth == 0 and braceDepth == 0:
      result.add(text[start ..< i].strip())
      start = i + 1
  if text.len > 0 and start < text.len:
    result.add(text[start ..< text.len].strip())

proc splitTopLevel(text: string; op: string): tuple[ok: bool, left: string, right: string] {.raises: [].} =
  if op.len == 0:
    return (ok: false, left: "", right: "")
  var parenDepth = 0
  var bracketDepth = 0
  var braceDepth = 0
  for i in 0 ..< text.len - op.len + 1:
    let ch = text[i]
    if ch == '(':
      inc parenDepth
    elif ch == ')':
      dec parenDepth
    elif ch == '[':
      inc bracketDepth
    elif ch == ']':
      dec bracketDepth
    elif ch == '{':
      inc braceDepth
    elif ch == '}':
      dec braceDepth
    else:
      discard
    if parenDepth == 0 and bracketDepth == 0 and braceDepth == 0 and
       i + op.len <= text.len and text[i ..< i + op.len] == op:
      let beforeOk = i == 0 or not isIdentChar(text[i - 1])
      let after = i + op.len
      let afterOk = after >= text.len or not isIdentChar(text[after])
      if beforeOk and afterOk:
        return (ok: true, left: text[0 ..< i].strip(), right: text[after ..< text.len].strip())
  (ok: false, left: "", right: "")

proc splitTopLevelKeyword(text: string; op: string): tuple[ok: bool, left: string, right: string] {.raises: [].} =
  if op == "and" or op == "or":
    result = splitTopLevel(text, " " & op & " ")
  else:
    result = splitTopLevel(text, op)

proc stripOuterParens(text: string): string {.raises: [].} =
  var s = text.strip()
  while s.len >= 2 and s[0] == '(' and s[^1] == ')' and
        findMatchingParen(s, 0) == s.len - 1:
    s = s[1 .. ^2].strip()
  s

proc parseExpression(expr: string): IRExpr {.raises: [].} =
  let s = stripOuterParens(expr)
  if s.len == 0:
    return IRExpr(kind: ieConst, val: "true")

  let lower = s.toLowerAscii()
  if lower == "true":
    return IRExpr(kind: ieConst, val: "true")
  if lower == "false":
    return IRExpr(kind: ieConst, val: "false")
  if s == "0" or s == "1" or (s.startsWith("-") and allCharsAreDigits(s[1 ..< s.len])):
    return IRExpr(kind: ieConst, val: s)

  for op in [" and ", " or ", ">=", "<=", "==", "!=", ">", "<", "+", "-", "*", "/", "div", "mod"]:
    let split = if op.len == 3: splitTopLevelKeyword(s, $op[1])
                else: splitTopLevel(s, op)
    if split.ok and split.left.len > 0 and split.right.len > 0:
      return IRExpr(kind: ieBinaryOp,
        left: parseExpression(split.left),
        right: parseExpression(split.right),
        op: $op[1])

  if s.len > 0 and (allCharsAreIdent(s) or allCharsAreDigits(s)):
    return IRExpr(kind: ieVar, varName: s)
  return IRExpr(kind: ieConst, val: s)

proc parseParamNameAndType(part: string): tuple[name: string, typeStr: string] {.raises: [].} =
  let trimmed = part.strip()
  if trimmed.len == 0:
    return ("", "")
  let colonIdx = trimmed.find(':')
  if colonIdx >= 0:
    (trimmed[0 ..< colonIdx].strip(), trimmed[(colonIdx + 1) ..< trimmed.len].strip())
  else:
    (trimmed, "")

proc extractSignatureParams(line: string): seq[AxiomParam] {.raises: [].} =
  let lower = line.toLowerAscii()
  let procIdx = lower.find("proc ")
  let funcIdx = lower.find("func ")
  let start = if procIdx >= 0: procIdx elif funcIdx >= 0: funcIdx else: -1
  if start < 0:
    return

  let raw = line[start .. ^1].strip()
  let openIdx = raw.find('(')
  if openIdx < 0:
    return

  let closeIdx = findMatchingParen(raw, openIdx)
  if closeIdx < 0:
    return

  for paramText in splitTopLevelCommas(raw[openIdx + 1 ..< closeIdx]):
    let (name, typeStr) = parseParamNameAndType(paramText)
    if name.len > 0:
      result.add(AxiomParam(name: name, typeStr: typeStr, refinement: none(IRExpr), isInductive: false))

proc extractRequireExpr(line: string): string {.raises: [].} =
  let raw = line.strip()[8 .. ^1].strip()
  if raw.len == 0:
    return ""
  if raw[0] == '(':
    let closeIdx = findMatchingParen(raw, 0)
    if closeIdx >= 0:
      return raw[1 ..< closeIdx].strip()
  else:
    let stopAt = min([raw.find(':'), raw.find('{')].filterIt(it >= 0))
    if stopAt >= 0:
      return raw[0 ..< stopAt].strip()
    return raw

proc extractIfCondition(line: string): string {.raises: [].} =
  let raw = line.strip()[2 .. ^1].strip()
  if raw.len == 0:
    return ""
  if raw[0] == '(':
    let closeIdx = findMatchingParen(raw, 0)
    if closeIdx >= 0:
      return raw[1 ..< closeIdx].strip()
  else:
    let stopAt = min([raw.find(':'), raw.find('{')].filterIt(it >= 0))
    if stopAt >= 0:
      return raw[0 ..< stopAt].strip()
    return raw

proc hasNumericRelational(expr: string): bool {.raises: [].} =
  let s = stripOuterParens(expr)
  if '"' in s or '\'' in s:
    return false
  for op in [">=", "<=", "==", "!=", ">", "<"]:
    if op in s:
      return true
  for op in ["and", "or"]:
    let split = splitTopLevelKeyword(s, op)
    if split.ok and (hasNumericRelational(split.left) or hasNumericRelational(split.right)):
      return true
  false

proc resultExprFromNimResult(expr: string): IRExpr {.raises: [].} =
  let s = stripOuterParens(expr)
  if s.len == 0:
    return IRExpr(kind: ieConst, val: "true")
  if s == "false":
    return IRExpr(kind: ieConst, val: "0")
  if s == "true":
    return IRExpr(kind: ieConst, val: "1")
  parseExpression(s)

proc extractResultExpr(line: string): string {.raises: [].} =
  let raw = line.strip()
  if raw.startsWith("return "):
    let rest = raw[7 .. ^1].strip()
    let stopAt = min([rest.find(':'), rest.find('{')].filterIt(it >= 0))
    if stopAt >= 0:
      return rest[0 ..< stopAt].strip()
    return rest
  if raw.startsWith("result ="):
    return raw[8 .. ^1].strip()
  ""

proc parseGateToIR(content: string): AxiomIRNode {.raises: [].} =
  result = AxiomIRNode(
    name: "gate",
    params: @[],
    returnType: "Bool",
    preConditions: @[],
    postCondition: none(IRExpr),
    children: @[],
    body: nil
  )
  var hasPass = false
  var hasFail = false

  for line in content.splitLines():
    let clean = stripComment(line)
    let lower = clean.toLowerAscii()
    if lower.startsWith("proc ") or lower.startsWith("func "):
      result.params = extractSignatureParams(clean)
    elif lower.startsWith("require"):
      let expr = extractRequireExpr(clean)
      if expr.len > 0 and hasNumericRelational(expr):
        result.preConditions.add(parseExpression(expr))
    elif lower.startsWith("assert"):
      let expr = extractRequireExpr(clean)
      if expr.len > 0 and hasNumericRelational(expr):
        result.preConditions.add(parseExpression(expr))
    elif lower.startsWith("if"):
      let expr = extractIfCondition(clean)
      if expr.len > 0 and hasNumericRelational(expr):
        result.preConditions.add(parseExpression(expr))
    elif clean.startsWith("return ") or clean.startsWith("result ="):
      let expr = extractResultExpr(clean)
      if expr.len > 0:
        let exprValue = resultExprFromNimResult(expr)
        if hasPass or hasFail:
          result.body = nil
        else:
          result.body = exprValue
    elif "ctx.fail" in lower:
      if hasPass:
        result.body = nil
      else:
        result.body = IRExpr(kind: ieConst, val: "0")
      hasFail = true
    elif "ctx.pass" in lower:
      if hasFail:
        result.body = nil
      else:
        result.body = IRExpr(kind: ieConst, val: "1")
      hasPass = true

proc checkGateNonVacuity*(gateFile: string): bool {.raises: [IOError].} =
  let content = readFile(gateFile)
  if "withGate" in content:
    echo "[NON-VACUITY] Gate uses withGate pattern - structurally valid"

  let ir = parseGateToIR(content)
  return verifyNonVacuity(ir)

when isMainModule:
  let gateFile = paramStr(1)
  if checkGateNonVacuity(gateFile):
    echo "Gate is non-vacuous (valid)"
    quit(0)
  else:
    echo "Gate is vacuous (always-pass theater detected)"
    quit(1)
