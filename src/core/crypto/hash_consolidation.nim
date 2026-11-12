import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## Hash Consolidation Guard — Standalone macro for duplicate hash detection.
## Extracted from axiom_pragmas.nim to avoid circular dependency with hash_kernel.
## Only depends on std/macros — no heavy module imports.

import std/macros
import std/strutils

func extractBaseName*(node: NimNode): string =
  var curr = node
  if curr.kind == nnkPostfix: curr = curr[1]
  if curr.kind == nnkBracketExpr: curr = curr[0]
  if curr.kind == nnkDotExpr: curr = curr[^1]
  result = $curr

func isHashForwarderPragma*(p: NimNode): bool =
  if p.kind == nnkIdent and $p == "axiomHashForwarder": return true
  elif p.kind == nnkExprColonExpr: return isHashForwarderPragma(p[0])
  elif p.kind == nnkDotExpr:
    return p[^1].kind == nnkIdent and $p[^1] == "axiomHashForwarder"
  return false

func scanForDuplicateHash*(node: NimNode) =
  if node.kind in {nnkProcDef, nnkFuncDef}:
    var isForwarder = false
    if node.pragma.kind != nnkEmpty:
      for p in node.pragma:
        if isHashForwarderPragma(p):
          isForwarder = true
          break
    if not isForwarder:
      let name = extractBaseName(node[0])
      if name in ["computeHash", "computeContentHash", "sha256Hex", "sha256hex", "sha256String"]:
        let info = node.lineInfoObj
        if "hash_kernel" notin info.filename:
          error("HASH CONSOLIDATION: '" & name & "' in " & info.filename &
                ". Use {.axiomHashForwarder.} if it's a wrapper.", node)
  for child in node:
    scanForDuplicateHash(child)

macro axiomHashConsolidation*(body: untyped): untyped =
  scanForDuplicateHash(body)
  result = body

{.pop.}
