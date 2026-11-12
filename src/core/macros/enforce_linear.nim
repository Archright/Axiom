{.push raises: [].}
import std/macros
import std/strutils
import shared/canonical_ast

# ── NimNode → CanonNode helpers (compile-time boundary) ────────────────
# These bridge raw NimNode API into the canonical adapter surface.
# All downstream logic operates on CanonNode only — no direct NimNode kind
# comparisons beyond the initial conversion.

func toCanonNNK(nk: NimNodeKind): CanonKind = nimKindToCanon(nk)

func wrapNimNode(n: NimNode): CanonNode = toCanon(n)

# ── hasConsumeCall: walk CanonNode tree looking for consume(tokenName) ──

proc hasConsumeCall(node: CanonNode, tokenName: string): bool {.noSideEffect.} =
  case getNodeKind(node)
  of ckCommand, ckCall:
    if getChildCount(node) > 1:
      let callee = getChild(node, 0)
      let arg = getChild(node, 1)
      if getNodeKind(callee) == ckIdent and getStringValue(callee) == "consume" and
          getNodeKind(arg) == ckIdent and getStringValue(arg) == tokenName:
        return true
  else:
    discard

  for child in getChildren(node):
    if hasConsumeCall(child, tokenName):
      return true
  result = false

# ── branchBody: extract body from control-flow branches ──

proc branchBody(node: CanonNode): CanonNode =
  case getNodeKind(node)
  of ckElifBranch:
    if getChildCount(node) > 1: getChild(node, 1) else: newNode(ckEmpty)
  of ckElse, ckOfBranch:
    if getChildCount(node) > 0: getChild(node, 0) else: newNode(ckEmpty)
  else:
    node

# ── analyzeNode: depth-first traversal tracking must-consume state ──

proc analyzeNode(node: CanonNode, tokenName: string, currentMust: bool, paths: var seq[CanonNode]): bool {.noSideEffect.} =
  case getNodeKind(node)
  of ckReturnStmt:
    let consumed = hasConsumeCall(node, tokenName)
    if not currentMust and not consumed:
      paths.add(node)
    return currentMust or consumed
  of ckIfStmt, ckWhenStmt, ckCaseStmt:
    result = currentMust
    for child in getChildren(node):
      result = result and analyzeNode(branchBody(child), tokenName, currentMust, paths)
    return result
  of ckStmtList, ckBlockStmt:
    result = currentMust
    for child in getChildren(node):
      if getNodeKind(child) == ckReturnStmt:
        return analyzeNode(child, tokenName, result, paths)
      result = analyzeNode(child, tokenName, result, paths)
    return result
  else:
    if hasConsumeCall(node, tokenName):
      return true
    return currentMust

proc findReturnPaths(node: CanonNode, tokenName: string, paths: var seq[CanonNode]) {.noSideEffect.} =
  var currentMust = false
  discard analyzeNode(node, tokenName, currentMust, paths)

# ── Token/type detection ───────────────────────────────────────────────

proc isProofTokenName(name: string): bool {.noSideEffect.} =
  let lowered = name.toLowerAscii()
  lowered == "prooftoken" or lowered.startsWith("proof") or lowered.endsWith("token") or
      (lowered.contains("proof") and lowered.contains("token"))

proc isProofTokenType(typeNode: CanonNode): bool {.noSideEffect.} =
  case getNodeKind(typeNode)
  of ckIdent, ckSym:
    result = isProofTokenName(getStringValue(typeNode))
  else:
    discard

  for child in getChildren(typeNode):
    if isProofTokenType(child):
      return true
  result = false

proc collectTokenNames(node: CanonNode, tokenNames: var seq[string]) {.noSideEffect.} =
  case getNodeKind(node)
  of ckVarSection:
    for decl in getChildren(node):
      if getNodeKind(decl) == ckIdentDefs:
        let varName = if getChildCount(decl) > 0: getChild(decl, 0).name else: ""
        let hasTypeName = getChildCount(decl) > 2 and isProofTokenType(getChild(decl, 2))
        if (hasTypeName or isProofTokenName(varName)) and varName notin tokenNames:
          tokenNames.add(varName)
  else:
    discard

  for child in getChildren(node):
    collectTokenNames(child, tokenNames)

# ── Proc definition helpers ────────────────────────────────────────────

proc procDefBody(procDef: CanonNode): CanonNode =
  let cc = getChildCount(procDef)
  if cc >= 7: getChild(procDef, 6)
  elif cc >= 6: getChild(procDef, 5)
  else:
    newNode(ckUnknown)

proc hasBestEffortPragma(procDef: CanonNode): bool {.noSideEffect.} =
  if getNodeKind(procDef) notin {ckProcDef, ckFuncDef}:
    return false

  # Pragma is typically stored as a child node in the canonical model
  let children = getChildren(procDef)
  if children.len == 0:
    return false

  # In canonical model, pragma info may be embedded differently.
  # We scan all children for bestEffort identifier.
  for child in children:
    if getNodeKind(child) == ckIdent and getStringValue(child) == "bestEffort":
      return true
    if getNodeKind(child) == ckExprEqExpr or getNodeKind(child) == ckExprColonExpr:
      if getChildCount(child) > 0 and getNodeKind(getChild(child, 0)) == ckIdent and
          getStringValue(getChild(child, 0)) == "bestEffort":
        return true

  result = false

# ── Macro entry point ──────────────────────────────────────────────────

macro enforceLinear*(procDef: untyped): untyped =
  expectKind(procDef, nnkProcDef)

  let c = wrapNimNode(procDef)

  if hasBestEffortPragma(c):
    result = procDef
    return

  let body = procDefBody(c)
  if getNodeKind(body) == ckUnknown:
    error("Expected nnkProcDef with body", procDef)

  var tokenNames: seq[string] = @[]
  collectTokenNames(body, tokenNames)

  for tokenName in tokenNames:
    var badPaths: seq[CanonNode] = @[]
    findReturnPaths(body, tokenName, badPaths)

    if badPaths.len > 0:
      error("Unchecked ProofToken '" & tokenName & "' - must call consume() before return", procDef)

  procDef
