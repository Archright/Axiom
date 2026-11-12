## tools/wp15_scope_projection.nim — Minimal runtime ScopeProjection
##
## Reusable by the wp1_ingress_probe. NOT wired into the engine
## (caller-side work is next WP).

import core/context/run_context
import core/parser_utils
import core/parsers/pnode_nav
import compiler/ast
import std/[os, strutils, tables]

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  SymbolOrigin* = enum
    soAxiomSupport     ## Symbol lives inside Axiom's kernel scope
    soExternalSubject  ## Symbol lives in the subject under test, outside Axiom's kernel

  ScopedSymbol* = object
    qualifiedName*: string  ## "<moduleRelPath>::<name>" e.g. "endians2.nim::swapBytesNim"
    origin*: SymbolOrigin

  ScopeProjection* = object
    support*: seq[string]        ## keys from Axiom's verification_scope.lock (kernelSymbols)
    subjectSymbols*: seq[ScopedSymbol]  ## derived: D1 fileset → per-file parse → top-level proc/func names

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc getProcName*(nameNode: PNode): string =
  ## Extract proc name from a name node, handling nnkPostfix (export marker).
  if nameNode == nil: return ""
  case nameNode.kind
  of nkPostfix:
    if nameNode.len > 1: pNodeText(nameNode[1]) else: ""
  of nkIdent: pNodeText(nameNode)
  else: ""

# ---------------------------------------------------------------------------
# buildSubjectSymbols
# ---------------------------------------------------------------------------

proc buildSubjectSymbols*(subjectRoot: string): (seq[ScopedSymbol], int, int) =
  ## For each .nim/.nims relpath in collectSubjectFileSet,
  ## parseFileAST(subjectRoot / rel), walk top-level nkFuncDef/nkProcDef
  ## (root.len loop, skip comments/pragmas), capture name via n[0]
  ## ident/postfix-name — produce qualifiedName = relPosix & "::" & name.
  ## Deterministic order = collectSubjectFileSet order (already sorted).
  ## Skip parse failures (nil) but COUNT them.
  ## Returns (symbols, parsedOkCount, parseFailCount).
  var symbols: seq[ScopedSymbol] = @[]
  var parsedOk = 0
  var parsedFail = 0

  let fileSet = collectSubjectFileSet(subjectRoot)
  for relPath in fileSet.paths:
    let absPath = subjectRoot / relPath
    let ast = parseFileAST(absPath)
    if ast.isNil:
      parsedFail.inc
      continue
    parsedOk.inc
    # Walk top-level nodes only (root.len loop)
    for i in 0 ..< ast.len:
      let node = ast[i]
      if node.isNil: continue
      case node.kind
      of nkCommentStmt, nkPragma:
        discard  # skip comments and pragmas
      of nkProcDef, nkFuncDef:
        if node.len > 0 and not node[0].isNil:
          let name = getProcName(node[0])
          if name.len > 0:
            let qname = relPath.replace("\\", "/") & "::" & name
            symbols.add ScopedSymbol(qualifiedName: qname, origin: soExternalSubject)
      else:
        discard  # skip non-proc/func top-level nodes

  (symbols, parsedOk, parsedFail)

# ---------------------------------------------------------------------------
# admits
# ---------------------------------------------------------------------------

proc admits*(p: ScopeProjection; q: ScopedSymbol): bool =
  ## Membership by qualifiedName+origin.
  for sym in p.subjectSymbols:
    if sym.qualifiedName == q.qualifiedName and sym.origin == q.origin:
      return true
  false
