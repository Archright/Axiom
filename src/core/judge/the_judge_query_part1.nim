import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import core/judge/smart_search
import core/judge/the_judge_lean
import std/strutils
func extractVariables*(prop: string): seq[string] {.noSideEffect.} =
  for usage in extractVariableUsages(prop):
    if usage.name notin result:
      result.add(usage.name)
type
  LeanTokenKind* = enum
    tkIdent, tkLParen, tkRParen, tkComma, tkSpace, tkOther

  LeanToken* = object
    kind*: LeanTokenKind
    text*: string
# @axiom-hint: lean="prop.length ≥ 0 ∧ ast_parse_failed_isolated" smt="(assert (and (>= (str.len prop) 0) ast_parse_failed_isolated))"
# @axiom-hint: lean="prop.length ≥ 0" smt="(assert (and (>= (str.len prop) 0)))"
func tokenizeLeanProp*(prop: string): seq[LeanToken] {.noSideEffect.} =
  ## Tokenizes a Lean proposition string into discrete tokens for safe transformation.
  ## Handles ASCII identifiers, parentheses, commas, spaces, and Unicode operators.
  var tokens: seq[LeanToken] = @[]
  var i = 0
  while i < prop.len:
    let c = prop[i]
    if c == ' ' or c == '\t' or c == '\n' or c == '\r':
      tokens.add(LeanToken(kind: tkSpace, text: " "))
      i += 1
    elif c == '(':
      tokens.add(LeanToken(kind: tkLParen, text: "("))
      i += 1
    elif c == ')':
      tokens.add(LeanToken(kind: tkRParen, text: ")"))
      i += 1
    elif c == ',':
      tokens.add(LeanToken(kind: tkComma, text: ","))
      i += 1
    elif c.isAlphaAscii or c == '_' or c.isDigit:
      var ident = ""
      while i < prop.len and (prop[i].isAlphaAscii or prop[i].isDigit or prop[i] == '_'):
        ident.add(prop[i])
        i += 1
      tokens.add(LeanToken(kind: tkIdent, text: ident))
    else:
      # Unicode operators treated as single-char tokens
      tokens.add(LeanToken(kind: tkOther, text: $c))
      i += 1
  tokens
func normalizeLeanTokens*(tokens: seq[LeanToken]): seq[LeanToken] {.noSideEffect.} =
  var stage1: seq[LeanToken] = @[]
  var prevNonSpace: LeanToken = LeanToken(kind: tkSpace, text: " ")
  for tok in tokens:
    if tok.kind == tkComma:
      if prevNonSpace.kind == tkRParen:
        stage1.add(tok)
      else:
        stage1.add(LeanToken(kind: tkSpace, text: " "))
    else:
      stage1.add(tok)
      if tok.kind != tkSpace:
        prevNonSpace = tok
  var stage2: seq[LeanToken] = @[]
  var i = 0
  while i < stage1.len:
    if i + 2 < stage1.len and stage1[i].kind == tkIdent and stage1[i+1].kind == tkLParen:
      var j = i + 2
      var depth = 1
      var isSimple = true
      var innerTokens: seq[LeanToken] = @[]
      while j < stage1.len and depth > 0:
        if stage1[j].kind == tkLParen:
          depth += 1
          isSimple = false
        elif stage1[j].kind == tkRParen:
          depth -= 1
        elif stage1[j].kind == tkSpace and depth == 1:
          isSimple = false
        if depth > 0:
          innerTokens.add(stage1[j])
        j += 1
      let rparenIdx = j - 1
      if isSimple and innerTokens.len == 1 and innerTokens[0].kind == tkIdent:
        stage2.add(stage1[i])
        stage2.add(LeanToken(kind: tkSpace, text: " "))
        stage2.add(innerTokens[0])
        i = rparenIdx + 1
        continue
      else:
        stage2.add(stage1[i])
        stage2.add(LeanToken(kind: tkSpace, text: " "))
        stage2.add(stage1[i+1])
        let innerNormalized = normalizeLeanTokens(innerTokens)
        for t in innerNormalized:
          stage2.add(t)
        stage2.add(stage1[rparenIdx])
        i = rparenIdx + 1
        continue
    else:
      stage2.add(stage1[i])
    i += 1
  var stage3: seq[LeanToken] = @[]
  var lastWasSpace = false
  for tok in stage2:
    if tok.kind == tkSpace:
      if not lastWasSpace:
        stage3.add(tok)
      lastWasSpace = true
    else:
      stage3.add(tok)
      lastWasSpace = false
  stage3
func tokensToString*(tokens: seq[LeanToken]): string {.noSideEffect.} =
  for tok in tokens:
    result.add(tok.text)
func sanitizeLean4AppSyntax*(prop: string): string {.noSideEffect.} =
  let tokens = tokenizeLeanProp(prop)
  let normalized = normalizeLeanTokens(tokens)
  tokensToString(normalized)
func sanitizeLeanIdentifiers*(prop: string): string {.noSideEffect.} =
  let tokens = tokenizeLeanProp(prop)
  for tok in tokens:
    if tok.kind == tkIdent and hasLeanKeywordPrefix(tok.text):
      result.add(sanitizeLeanIdentifierName(tok.text))
    else:
      result.add(tok.text)
func sanitizeLean4Forall*(prop: string): string {.noSideEffect.} =
  result = prop
  let forallMarker = "∀ "
  var i = 0
  while i < result.len:
    let idx = result.find(forallMarker, i)
    if idx < 0:
      break
    let afterStart = idx + forallMarker.len
    if afterStart >= result.len:
      break
    var boundVar = ""
    for j in afterStart ..< result.len:
      let c = prop[j]
      if c.isAlphaNumeric or c == '_':
        boundVar.add(c)
      else:
        break
    if boundVar.len > 0:
      let commaIdx = afterStart + boundVar.len
      if commaIdx < result.len and result[commaIdx] == ',':
        result = result[0 .. commaIdx - 1] & " : α)" & result[commaIdx .. ^1]
        result = result[0 .. idx + forallMarker.len - 1] & "(" & result[idx + forallMarker.len .. ^1]
        i = commaIdx + 10
        continue
    i = idx + 1
func generateUniqueSignature*(nodeId: string, hint: SemanticHint): string {.noSideEffect.} =
  let raw = nodeId & "|" & hint.leanProposition
  var h: uint64 = 0
  for c in raw:
    h = h * 31'u64 + uint64(ord(c))
  let s = $h
  if s.len > 8:
    result = s[0 .. 7]
  else:
    result = s
func negateLeanProposition*(prop: string): string {.noSideEffect.} =
  result = "¬(" & prop & ")"
func nimTypeToLeanType*(nimType: string): string {.noSideEffect.} =
  let t = nimType.strip().toLowerAscii()
  if t == "int" or t == "int8" or t == "int16" or t == "int32" or t == "int64":
    return "Int"
  elif t == "natural" or t.startsWith("uint"):
    return "Nat"
  elif t == "string" or t == "cstring":
    return "String"
  elif t == "bool":
    return "Bool"
  elif t == "char":
    return "Char"
  elif t.startsWith("seq[") and t.endsWith("]"):
    let inner = nimType.strip()[4 .. ^2]
    let innerLean = nimTypeToLeanType(inner)
    let leanArg =
      if innerLean.contains(" ") and not (innerLean.startsWith("(") and innerLean.endsWith(")")):
        "(" & innerLean & ")"
      else:
        innerLean
    return "NimSeq " & leanArg
  elif t.startsWith("range["):
    return "Int"
  else:
    return "α"
func usageHasField*(usage: LeanVariableUsage; field: string): bool {.raises: [].} =
  field in usage.fields
{.pop.}
