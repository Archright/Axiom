import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

import std/tables
import compiler/[ast, idents]
import gate/architecture_ast_facts
import gate/nimtry/nimtry_extract_types
from core/trusted/axiom_pragmas_lite import axiomEffect, AxiomEffectKind, IOEffect, Pure
from core/trusted/effect_bridge import AxiomIOEffect

func isExportMarker*(n: PNode): bool {.raises: [].} =
  n.kind == nkPostfix and n.safeLen >= 2 and
    n[0].kind == nkIdent and n[0].ident.s == "*"

func extractName*(n: PNode): string {.raises: [].} =
  if n.isNil: return ""
  if n.kind == nkPostfix and n.safeLen >= 2: result = extractName(n[1])
  elif n.kind == nkIdent: result = n.ident.s
  elif n.kind == nkAccQuoted and n.safeLen >= 1: result = extractName(n[0])
  elif n.kind in {nkStrLit..nkTripleStrLit}: result = n.strVal
  elif n.kind == nkSym: result = n.sym.name.s
  else: result = ""

func calleeName*(n: PNode): string {.raises: [].} =
  ## Extract the simple (unqualified) callee name from a call expression.
  if n.isNil: return ""
  if n.kind == nkIdent: result = n.ident.s
  elif n.kind == nkSym: result = n.sym.name.s
  elif n.kind == nkDotExpr and n.safeLen >= 2: result = calleeName(n[1])
  elif n.kind == nkAccQuoted and n.safeLen >= 1: result = calleeName(n[0])
  else: result = ""

func qualifiedCalleeRec*(n: PNode): string {.raises: [].} =
  ## Extract the full qualified callee name (e.g., "foo.bar").
  if n.isNil: return ""
  if n.kind == nkIdent: result = n.ident.s
  elif n.kind == nkSym: result = n.sym.name.s
  elif n.kind == nkDotExpr and n.safeLen >= 2:
    result = qualifiedCalleeRec(n[0]) & "." & qualifiedCalleeRec(n[1])
  elif n.kind == nkAccQuoted and n.safeLen >= 1: result = qualifiedCalleeRec(n[0])
  else: result = ""

func recNodeCount*(n: PNode): int {.raises: [].} =
  ## Recursive count of all PNode children in a subtree.
  if n.isNil: return 0
  result = 1
  var i = 0
  while i < n.safeLen:
    result += recNodeCount(n[i])
    inc i

func fingerprintNode*(n: PNode): string {.raises: [].} =
  ## Canonical serialization of a PNode subtree: "Kind:Child1:Child2:..."
  if n.isNil: return "nil"
  result = $n.kind
  var i = 0
  while i < n.safeLen:
    result.add(":")
    result.add(fingerprintNode(n[i]))
    inc i

func nodeToString*(n: PNode): string {.raises: [].} =
  ## Convert a PNode subtree to a simple human-readable string.
  if n.isNil: return "nil"
  if n.safeLen == 0:
    case n.kind
    of nkIdent: result = n.ident.s
    of nkSym: result = n.sym.name.s
    of nkStrLit..nkTripleStrLit: result = "\"" & n.strVal & "\""
    of nkIntLit..nkInt64Lit: result = $n.intVal
    of nkFloatLit..nkFloat64Lit: result = $n.floatVal
    of nkNilLit: result = "nil"
    of nkCharLit: result = "'" & ($(n.intVal.chr)) & "'"
    else: result = $n.kind
  else:
    result = $n.kind & "("
    var i = 0
    while i < n.safeLen:
      if i > 0: result.add(", ")
      result.add(nodeToString(n[i]))
      inc i
    result.add(")")

proc canonicalizeNode*(n: PNode): PNode {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Transform a PNode subtree into canonical form (deep copy, original unchanged).
  ## Rules:
  ## 1. Commutative operator sorting: for nkInfix with `+`, `*`, `==`, `and`, `or`,
  ##    sort the two operands by their nodeToString representation lexicographically.
  ## 2. `not` branch normalization: for nkIfStmt where an nkElifBranch condition
  ##    is nkPrefix(not, x), swap the then/else bodies and replace condition with x.
  if n.isNil: return nil
  try:
    result = copyTree(n)
  except CatchableError:
    return nil

  # Recursively canonicalize children first
  var i = 0
  while i < result.safeLen:
    result[i] = canonicalizeNode(result[i])
    inc i

  # Rule 1: Commutative operator sorting
  if result.kind == nkInfix and result.safeLen >= 3:
    let op = result[0]
    if op.kind == nkIdent and op.ident.s in @["+", "*", "==", "and", "or"]:
      let leftStr = nodeToString(result[1])
      let rightStr = nodeToString(result[2])
      if leftStr > rightStr:
        swap(result[1], result[2])

  # Rule 2: `not` branch normalization
  if result.kind == nkIfStmt:
    i = 0
    while i < result.safeLen:
      let branch = result[i]
      if branch.kind == nkElifBranch and branch.safeLen >= 2:
        let cond = branch[0]
        if cond.kind == nkPrefix and cond.safeLen >= 1:
          let opIdent = cond[0]
          if opIdent.kind == nkIdent and opIdent.ident.s == "not" and
              cond.safeLen >= 2:
            # Replace "not x" with "x", unwrapping nkPar from parentheses if present
            var replacement = cond[1]
            if replacement.kind == nkPar and replacement.safeLen >= 1:
              replacement = replacement[0]
            branch[0] = replacement
            # Swap bodies with next branch if it's an else branch
            let nextIdx = i + 1
            if nextIdx < result.safeLen:
              let nextBranch = result[nextIdx]
              if nextBranch.kind == nkElse and nextBranch.safeLen >= 1:
                let currentBody = branch[1]
                let elseBody = nextBranch[0]
                branch[1] = elseBody
                nextBranch[0] = currentBody
      inc i

func collectIdents*(n: PNode): seq[string] {.raises: [].} =
  ## Collect all nkIdent names from a PNode subtree.
  if n.isNil: return
  var refs: seq[string] = @[]
  proc walk(m: PNode) =
    if m.isNil: return
    case m.kind
    of nkIdent:
      refs.add(m.ident.s)
    of nkSym:
      refs.add(m.sym.name.s)
    else:
      var i = 0
      while i < m.safeLen:
        walk(m[i])
        inc i
  walk(n)
  refs

# ---------------------------------------------------------------------------
# Symbol Table Builder
# ---------------------------------------------------------------------------

func addSymbol*(st: SymbolTable; name: string; kind: DeclKind; exported: bool;
    loc: SourceLocation) {.raises: [].} =
  let entry = SymbolEntry(kind: kind, exported: exported, location: loc)
  st.symbols.mgetOrPut(name, @[]).add(entry)

func collectImportPath*(n: PNode): string {.raises: [].} =
  ## Build a flat path string from an import node.
  if n.isNil: return ""
  case n.kind
  of nkIdent: result = n.ident.s
  of nkSym: result = n.sym.name.s
  of nkDotExpr:
    result = collectImportPath(n[0]) & "." & collectImportPath(n[1])
  of nkAccQuoted: result = collectImportPath(n[0])
  of nkInfix:
    ## handles "std / strutils" style
    if n.safeLen >= 3 and extractName(n[0]) == "/":
      result = collectImportPath(n[1]) & "/" & collectImportPath(n[2])
    else:
      result = nodeToString(n)
  else: result = nodeToString(n)

func buildSymbolTable*(root: PNode; path: string): SymbolTable {.raises: [].} =
  ## First pass: walk top-level nodes to collect all declarations and imports.
  var st = SymbolTable(
    symbols: initTable[string, seq[SymbolEntry]](),
    imports: @[]
  )

  proc walk(n: PNode) =
    if n.isNil: return
    case n.kind
    of nkProcDef, nkFuncDef, nkMethodDef:
      if n.safeLen >= 1:
        let nameNode = n[0]
        let name = extractName(nameNode)
        let exported = isExportMarker(nameNode)
        if name.len > 0:
          let dk = case n.kind
            of nkProcDef: dkProc
            of nkFuncDef: dkFunc
            of nkMethodDef: dkMethod
            else: dkProc
          addSymbol(st, name, dk, exported,
            SourceLocation(path: path, line: n.info.line.int,
                column: n.info.col.int + 1))

    of nkIteratorDef:
      if n.safeLen >= 1:
        let name = extractName(n[0])
        if name.len > 0:
          addSymbol(st, name, dkProc, isExportMarker(n[0]),
            SourceLocation(path: path, line: n.info.line.int,
                column: n.info.col.int + 1))

    of nkVarSection, nkLetSection, nkConstSection:
      var i = 0
      while i < n.safeLen:
        let child = n[i]
        if child.kind == nkIdentDefs and child.safeLen >= 1:
          let declName = extractName(child[0])
          if declName.len > 0:
            let dk = case n.kind
              of nkVarSection: dkVar
              of nkLetSection: dkLet
              of nkConstSection: dkConst
              else: dkVar
            addSymbol(st, declName, dk, false,
              SourceLocation(path: path, line: child.info.line.int,
                  column: child.info.col.int + 1))
        inc i

    of nkTypeSection:
      var i = 0
      while i < n.safeLen:
        let child = n[i]
        if child.kind == nkTypeDef and child.safeLen >= 1:
          let typeName = extractName(child[0])
          if typeName.len > 0:
            let exported = child.safeLen >= 1 and isExportMarker(child[0])
            addSymbol(st, typeName, dkType, exported,
              SourceLocation(path: path, line: child.info.line.int,
                  column: child.info.col.int + 1))
        inc i

    of nkImportStmt:
      var i = 0
      while i < n.safeLen:
        let importPath = collectImportPath(n[i])
        if importPath.len > 0:
          st.imports.add(importPath)
        inc i

    of nkFromStmt:
      if n.safeLen >= 1:
        let modulePath = collectImportPath(n[0])
        if modulePath.len > 0:
          st.imports.add(modulePath)

    of nkImportExceptStmt:
      if n.safeLen >= 1:
        let modulePath = collectImportPath(n[0])
        if modulePath.len > 0:
          st.imports.add(modulePath)

    of nkIncludeStmt:
      # include is like import but merges; treat similarly
      var i = 0
      while i < n.safeLen:
        let includePath = collectImportPath(n[i])
        if includePath.len > 0:
          st.imports.add(includePath)
        inc i

    else:
      discard

    # Recurse into non-function top-level stmts to find nested declarations
    if n.kind notin {nkProcDef, nkFuncDef, nkMethodDef, nkIteratorDef}:
      var i = 0
      while i < n.safeLen:
        walk(n[i])
        inc i

  walk(root)
  result = st

# ---------------------------------------------------------------------------
# Callee classification
# ---------------------------------------------------------------------------

{.pop.}
