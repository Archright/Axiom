import std/macros
import core/gate/gate_context
import shared/canonical_ast

template bestEffortInitGateContext*(name: string): GateContext =
  initGateContext(name)

template bestEffortCtxIsVerified*(ctx: GateContext): bool =
  ctx.isVerified()

const bestEffortGrPass* = grPass
const bestEffortGrFail* = grFail

template bestEffort*(reason: static string) {.pragma.}

macro bestEffort*(reason: static string, procDef: untyped): untyped =
  # Validate kind via canonical adapter surface
  let c = toCanon(procDef)
  if getNodeKind(c) notin {ckProcDef, ckFuncDef, ckMethodDef}:
    error("bestEffort expects a proc definition, got " & $getNodeKind(c), procDef)

  var reasonText = $reason
  while reasonText.len > 0 and reasonText[reasonText.high] in {' ', '\t', '\n', '\r'}:
    reasonText = reasonText[0..<reasonText.high]
  while reasonText.len > 0 and reasonText[0] in {' ', '\t', '\n', '\r'}:
    reasonText = reasonText[1..^1]
  if reasonText.len < 5:
    error("bestEffort requires reason string with at least 5 characters, got: " & reasonText, procDef)

  # Pragma manipulation stays on NimNode (CanonNode is read-only value).
  # Canonical adapter is used only for kind validation above.
  let pragma = procDef[4]
  case pragma.kind
  of nnkEmpty:
    procDef[4] = newNimNode(nnkPragma).add(newTree(nnkExprColonExpr, ident"bestEffort", newStrLitNode(reasonText)))
  of nnkPragma:
    var newPragmas = newNimNode(nnkPragma)
    var hasBestEffort = false
    for p in pragma:
      if p.kind == nnkIdent and p.strVal == "bestEffort":
        hasBestEffort = true
      newPragmas.add(p)
    if not hasBestEffort:
      newPragmas.add(newTree(nnkExprColonExpr, ident"bestEffort", newStrLitNode(reasonText)))
    procDef[4] = newPragmas
  else:
    discard
  procDef