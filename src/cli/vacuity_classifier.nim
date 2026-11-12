import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [].}
import std/strutils

type
  TrivialPattern* = enum
    tpNone              ## Not trivial — normal verification
    tpIdentityReturn    ## return x — returns parameter directly
    tpConstantFactory   ## Only literals/empty constructors returned
    tpPassthroughDelegation ## Single call forwarding, no conditionals

# ---------------------------------------------------------------------------
# Internal helpers (all pure, text-based)
# ---------------------------------------------------------------------------

func extractFirstParam(sourceCode, functionName: string): string =
  ## Extract the first parameter name from a function signature.
  ## Handles `proc foo(x: int): int =` and `func foo(x, y: int): int =`.
  result = ""
  # Find the function name
  let nameIdx = sourceCode.find(functionName)
  if nameIdx < 0:
    return
  # Find opening paren after function name
  var i = nameIdx + functionName.len
  while i < sourceCode.len and sourceCode[i] != '(':
    inc i
  if i >= sourceCode.len:
    return
  inc i # skip '('
  # Now read until first ':' or ')'
  var paramName = ""
  while i < sourceCode.len:
    let c = sourceCode[i]
    if c == ':' or c == ')':
      break
    if c == ',':
      break
    if c notin {' ', '\t', '\n', '\r'}:
      paramName.add(c)
    inc i
  result = paramName.strip()

func extractBody(sourceCode, functionName: string): string =
  ## Extract the body after `=` for the named function.
  ## Finds `functionName(...): RetType =` then returns everything after.
  result = ""
  let nameIdx = sourceCode.find(functionName)
  if nameIdx < 0:
    return
  # Find closing paren of parameter list
  var depth = 0
  var i = nameIdx
  while i < sourceCode.len:
    let c = sourceCode[i]
    if c == '(':
      inc depth
    elif c == ')':
      dec depth
      if depth == 0:
        inc i
        break
    inc i
  # Skip return type annotation: `: RetType`
  while i < sourceCode.len and sourceCode[i] != '=':
    inc i
  if i >= sourceCode.len:
    return
  inc i # skip '='
  # Collect rest (the body), trimming trailing whitespace
  var body = ""
  while i < sourceCode.len:
    body.add(sourceCode[i])
    inc i
  result = body.strip()

func hasControlFlow(body: string): bool =
  ## Returns true if body contains any control flow keywords.
  let keywords = ["if ", "if\t", "case ", "case\t", "while ", "while\t",
                  "for ", "for\t", "of ", "else:", "elif "]
  for kw in keywords:
    if body.contains(kw):
      return true
  # Also check for `of` on its own line (case/of pattern)
  for line in body.splitLines():
    let stripped = line.strip()
    if stripped.startsWith("of "):
      return true
  false

func isLiteralOrConstructor(token: string): bool =
  ## Check if a token is a literal, empty constructor, or default().
  let t = token.strip()
  if t.len == 0:
    return false
  # Boolean / nil literals
  if t in ["true", "false", "nil"]:
    return true
  # Numeric literal (integer or float, optionally negative)
  var startIdx = 0
  if t[0] == '-':
    startIdx = 1
  if startIdx < t.len and t[startIdx].isDigit:
    var isNum = true
    for j in startIdx ..< t.len:
      if not (t[j].isDigit or t[j] == '.'):
        isNum = false
        break
    if isNum:
      return true
  # Empty string literal
  if t == "\"\"":
    return true
  # Empty constructors: `newSeq[type]()`, `initTable()`, `default(type)`,
  # `SomeType()`, `@[]`, `@{}`
  if t == "@[]" or t == "@{}":
    return true
  if t.endsWith("()"):
    return true
  if t.startsWith("default(") and t.endsWith(")"):
    return true
  # `Type()` pattern (object constructor)
  if t.endsWith("()") and t[0].isUpperAscii():
    return true
  false

func isIdentifierOrTypeConv(token: string): bool =
  ## Check if token is a bare identifier or TypeConv(ident).
  let t = token.strip()
  if t.len == 0:
    return false
  # Bare identifier: starts with letter/underscore, rest alphanumeric
  if t[0] in IdentStartChars:
    var allIdent = true
    for j in 1 ..< t.len:
      if t[j] notin IdentChars:
        allIdent = false
        break
    if allIdent:
      return true
  # TypeConv(ident) e.g. `int(x)`, `float(y)`
  if t.endsWith(")"):
    let openIdx = t.find('(')
    if openIdx > 0 and openIdx < t.len - 2:
      let convName = t[0 ..< openIdx]
      let inner = t[(openIdx + 1) .. ^2]
      if convName.len > 0 and convName[0] in IdentStartChars:
        # Check inner is identifier
        if inner.len > 0 and inner[0] in IdentStartChars:
          var innerOk = true
          for j in 1 ..< inner.len:
            if inner[j] notin IdentChars:
              innerOk = false
              break
          if innerOk:
            return true
  false

func extractCallArgs(callBody: string): seq[string] =
  ## Given something like `someFunc(x, y)` or `return someFunc(x, y)`,
  ## extract the argument tokens.
  result = @[]
  var s = callBody.strip()
  # Strip leading `return ` or `result = `
  if s.startsWith("return "):
    s = s[7 .. ^1].strip()
  elif s.startsWith("result"):
    # Find '='
    let eqIdx = s.find('=')
    if eqIdx >= 0:
      s = s[(eqIdx + 1) .. ^1].strip()
  # Now s should be like `someFunc(x, y)`
  let parenOpen = s.find('(')
  let parenClose = s.rfind(')')
  if parenOpen < 0 or parenClose < 0 or parenClose <= parenOpen:
    return
  let argsStr = s[(parenOpen + 1) ..< parenClose].strip()
  if argsStr.len == 0:
    return
  # Split by comma (naive but sufficient for identifiers)
  for arg in argsStr.split(','):
    result.add(arg.strip())

# ---------------------------------------------------------------------------
# Public classifier
# ---------------------------------------------------------------------------

func classifyTriviality*(sourceCode: string; functionName: string): TrivialPattern =
  ## Classify a Nim function as trivial by design using text-based pattern matching.
  ## Returns tpNone for any parsing failure or non-trivial function.
  {.cast(noSideEffect).}:
    try:
      if sourceCode.len == 0 or functionName.len == 0:
        return tpNone
      let body = extractBody(sourceCode, functionName)
      if body.len == 0:
        return tpNone
      # If control flow is present, not trivial
      if hasControlFlow(body):
        return tpNone
      # Normalize: strip `return` / `result =` prefix for analysis
      var expr = body.strip()
      if expr.startsWith("return "):
        expr = expr[7 .. ^1].strip()
      elif expr.startsWith("result"):
        let eqIdx = expr.find('=')
        if eqIdx >= 0:
          expr = expr[(eqIdx + 1) .. ^1].strip()
      # Pattern 1: tpIdentityReturn — body is just the first param name
      let firstParam = extractFirstParam(sourceCode, functionName)
      if firstParam.len > 0 and expr == firstParam:
        return tpIdentityReturn
      # Pattern 2: tpConstantFactory — only literals/constructors
      if isLiteralOrConstructor(expr):
        return tpConstantFactory
      # Pattern 3: tpPassthroughDelegation — single function call with id/typeconv args
      if expr.endsWith(")"):
        let openParen = expr.find('(')
        if openParen > 0:
          let args = extractCallArgs(expr)
          if args.len > 0:
            var allIds = true
            for arg in args:
              if not isIdentifierOrTypeConv(arg):
                allIds = false
                break
            if allIds:
              return tpPassthroughDelegation
      tpNone
    except CatchableError:
      tpNone

