import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
#.push noSideEffect.}

import std/tables
import std/sequtils
import std/strutils
import std/options
import std/algorithm
import compiler/ast
import core/parsers/pnode_nav
import ../../core/trusted/axiom_pragmas

type
  SymbolKind* = enum
    skProc, skFunc, skType, skField, skVar, skLet, skConst, skGenericParam
    ## Lean-specific symbol kinds — cross-language symbol graph integration
    skLeanTheorem, skLeanDef, skLeanMacro, skLeanAbbrev, skLeanInductive,
    skLeanStructure, skLeanClass, skLeanOpaque, skLeanExample, skLeanMeta

  SymbolNode* = object
    qualifiedName*: string
    kind*: SymbolKind
    modulePath*: string
    astNode*: PNode
    visibility*: string

  ReferenceKind* = enum
    rkCall, rkTypeUse, rkFieldAccess, rkMutates, rkReads

  ReferenceEdge* = object
    source*: string
    target*: string
    kind*: ReferenceKind
    line*: int
    column*: int

  GlobalSymbolGraph* = object
    symbols*: Table[string, SymbolNode]
    edges*: seq[ReferenceEdge]
    byTarget*: Table[string, seq[ReferenceEdge]]

  ModuleGraphContribution* = object
    fileHash*: string
    symbols*: seq[SymbolNode]
    edges*: seq[ReferenceEdge]

func referenceEdgeCmp*(left, right: ReferenceEdge): int {.raises: [].} =
  result = cmp(left.source, right.source)
  if result != 0:
    return result
  result = cmp(left.target, right.target)
  if result != 0:
    return result
  result = cmp($left.kind, $right.kind)
  if result != 0:
    return result
  result = cmp(left.line, right.line)
  if result != 0:
    return result
  result = cmp(left.column, right.column)

func symbolNodeCmp*(left, right: SymbolNode): int {.raises: [].} =
  result = cmp(left.qualifiedName, right.qualifiedName)
  if result != 0:
    return result
  result = cmp(left.modulePath, right.modulePath)

func sortedSymbolKeys*(symbols: Table[string, SymbolNode]): seq[string] {.raises: [].} =
  result = symbols.keys.toSeq()
  result.sort(cmp[string])

func canonicalizeGlobalSymbolGraph*(graph: var GlobalSymbolGraph) {.raises: [].} =
  graph.edges.sort(referenceEdgeCmp)
  graph.byTarget = initTable[string, seq[ReferenceEdge]]()
  for edge in graph.edges:
    graph.byTarget.mgetOrPut(edge.target, @[]).add(edge)

## Module Name From Path.
func moduleNameFromPath*(modulePath: string): string {.inline, axiom: ["(assert (and (>= (str.len modulePath) 0) (>= result 0)))", "modulePath.length ≥ 0 ∧ (result ≥ 0)"].} =
  let parts = modulePath.split({'/', '\\'})
  result = parts[^1]
  let dotIdx = result.rfind(".")
  if dotIdx >= 0:
    result = result[0 ..< dotIdx]

## Qualified Name.
func qualifiedName*(modulePath, symbolName: string): string {.inline, axiom: ["(assert (and (= (str.len stem) 0) symbolName (=> (= (str.len stem) 0) (= result symbolName))))", "stem.length = 0 ∧ symbolName ∧ stem.length = 0 → result = symbolName"].} =
  let stem = moduleNameFromPath(modulePath)
  if stem.len == 0:
    return symbolName
  result = stem & "." & symbolName

## Index Declarations In Ast (PNode).
  ## axiom-smt: (assert (and (= (option.isNone nameOpt) true) (= (str.len name) 0) (= (option.isNone fieldNameOpt) true) (= (str.len fieldName) 0) (>= sectionTags 0) (>= typeTags 0) (>= procTags 0) (>= table 0)))
  ## axiom-lean: nameOpt.isNone = true ∧ name.length = 0 ∧ fieldNameOpt.isNone = true ∧ fieldName.length = 0 ∧ (sectionTags ≥ 0) ∧ (typeTags ≥ 0) ∧ (procTags ≥ 0) ∧ (table ≥ 0)
func indexDeclarationsInAstP*(
  ast: PNode;
  modulePath: string;
  table: var Table[string, SymbolNode]
) {.axiomTryImpl.} =
  ## First pass: index all top-level declarations in a module AST (PNode version).
  const procKinds = {nkProcDef, nkFuncDef, nkMethodDef, nkIteratorDef, nkConverterDef, nkMacroDef, nkTemplateDef}

  for node in findNodesP(ast, procKinds):
    if node.len > 0 and not node[0].isNil:
      let nameNodeOpt = findFirstNodeP(node[0], {nkIdent})
      if nameNodeOpt.isSome():
        let nmNode = get(nameNodeOpt)
        let name = if nmNode.kind == nkIdent: nmNode.ident.s elif nmNode.kind == nkSym: nmNode.sym.name.s else: ""
        if name.len == 0: continue
        let qn = qualifiedName(modulePath, name)
        if not table.hasKey(qn):
          let kind = if node.kind == nkFuncDef: skFunc else: skProc
          table[qn] = SymbolNode(
            qualifiedName: qn,
            kind: kind,
            modulePath: modulePath,
            astNode: node,
            visibility: "public"
          )

  # Index type declarations
  for typeDef in findNodesP(ast, {nkTypeDef}):
    if typeDef.len > 0 and not typeDef[0].isNil:
      let nameNodeOpt = findFirstNodeP(typeDef[0], {nkIdent})
      if nameNodeOpt.isSome():
        let nmNode = get(nameNodeOpt)
        let name = if nmNode.kind == nkIdent: nmNode.ident.s elif nmNode.kind == nkSym: nmNode.sym.name.s else: ""
        if name.len == 0: continue
        let qn = qualifiedName(modulePath, name)
        if not table.hasKey(qn):
          table[qn] = SymbolNode(
            qualifiedName: qn,
            kind: skType,
            modulePath: modulePath,
            astNode: typeDef,
            visibility: "public"
          )
        # Index fields inside object/tuple declarations
        if typeDef.len > 1 and not typeDef[1].isNil:
          let typeBody = typeDef[1]
          for child in typeBody:
            if not child.isNil and child.kind in {nkIdentDefs, nkVarSection}:
              for identDef in findNodesP(child, {nkIdentDefs}):
                if identDef.len > 0 and identDef[0].kind == nkIdent:
                  let fieldName = identDef[0].ident.s
                  let fieldQn = qn & "." & fieldName
                  if not table.hasKey(fieldQn):
                    table[fieldQn] = SymbolNode(
                      qualifiedName: fieldQn,
                      kind: skField,
                      modulePath: modulePath,
                      astNode: identDef,
                      visibility: "public"
                    )

  # Index top-level vars/lets/consts
  for section in findNodesP(ast, {nkVarSection, nkLetSection, nkConstSection}):
    for identDef in findNodesP(section, {nkIdentDefs}):
      if identDef.len > 0 and identDef[0].kind == nkIdent:
        let name = identDef[0].ident.s
        let qn = qualifiedName(modulePath, name)
        if not table.hasKey(qn):
          let kind = case section.kind
            of nkLetSection: skLet
            of nkConstSection: skConst
            else: skVar
          table[qn] = SymbolNode(
            qualifiedName: qn,
            kind: kind,
            modulePath: modulePath,
            astNode: identDef,
            visibility: "public"
          )

## Collect References In Ast (PNode).
func collectReferencesInAstP*(
  ast: PNode;
  sourceSymbol: string;
  modulePath: string;
  symbolTable: Table[string, SymbolNode]
): seq[ReferenceEdge] {.axiomTryImpl.} =
  ## axiom-smt: (assert ast_parse_failed_isolated)
  ## axiom-lean: ast_parse_failed_isolated
  ## Second pass: collect all references inside a single AST (PNode version).
  # Collect calls
  for callNode in findNodesP(ast, {nkCall}):
    if callNode.len > 0 and not callNode[0].isNil:
      let nameText = pNodeText(callNode[0])
      if nameText.len > 0:
        let qn = qualifiedName(modulePath, nameText)
        let target = if symbolTable.hasKey(qn): qn else: nameText
        result.add(ReferenceEdge(
          source: sourceSymbol,
          target: target,
          kind: rkCall,
          line: 0,
          column: 0
        ))

  # Collect type expressions
  for typeDef in findNodesP(ast, {nkTypeDef}):
    for ident in findNodesP(typeDef, {nkIdent}):
      let name = ident.ident.s
      if name.len > 0:
        let qn = qualifiedName(modulePath, name)
        let target = if symbolTable.hasKey(qn): qn else: name
        result.add(ReferenceEdge(
          source: sourceSymbol,
          target: target,
          kind: rkTypeUse,
          line: 0,
          column: 0
        ))

  # Collect dot expressions (field access)
  for dotNode in findNodesP(ast, {nkDotExpr}):
    if dotNode.len > 0 and not dotNode[0].isNil:
      let base = dotNode[0]
      if base.kind == nkIdent:
        let name = base.ident.s
        if name.len > 0:
          result.add(ReferenceEdge(
            source: sourceSymbol,
            target: name,
            kind: rkFieldAccess,
            line: 0,
            column: 0
          ))

  # Collect assignments (mutations)
  for asgnNode in findNodesP(ast, {nkAsgn}):
    if asgnNode.len > 0 and not asgnNode[0].isNil:
      let idents = findNodesP(asgnNode[0], {nkIdent})
      if idents.len > 0:
        let name = idents[0].ident.s
        if name.len > 0:
          let qn = qualifiedName(modulePath, name)
          let target = if symbolTable.hasKey(qn): qn else: name
          result.add(ReferenceEdge(
            source: sourceSymbol,
            target: target,
            kind: rkMutates,
            line: 0,
             column: 0
           ))

