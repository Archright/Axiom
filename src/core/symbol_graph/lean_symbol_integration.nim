import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import core/symbolic/global_symbol_graph_types
import verification/lean_lsp_protocol
import std/tables

## Map a Lean LSP SymbolKind string to our SymbolKind enum value.
func leanSymbolKindToAxiom*(kindStr: string): SymbolKind {.raises: [].} =
  case kindStr
  of "class":             result = skLeanClass
  of "constant":          result = skLeanDef
  of "definition":        result = skLeanDef
  of "theorem":           result = skLeanTheorem
  of "abbrev":            result = skLeanAbbrev
  of "macro":             result = skLeanMacro
  of "inductive":         result = skLeanInductive
  of "structure":         result = skLeanStructure
  of "opaque":            result = skLeanOpaque
  of "example":           result = skLeanExample
  of "meta":              result = skLeanMeta
  else:                   result = skLeanDef

## Convert a single Lean LSP DocumentSymbol into an Axiom SymbolNode.
func leanSymbolToNode*(sym: LeanDocumentSymbol; modulePath: string): SymbolNode {.raises: [].} =
  let qn = qualifiedName(modulePath, sym.name)
  result = SymbolNode(
    qualifiedName: qn,
    kind: leanSymbolKindToAxiom($sym.kind),
    modulePath: modulePath,
    astNode: nil,
    visibility: if sym.detail.len > 0: "public" else: "internal"
  )
  # Recursively convert children for hierarchical symbols (e.g. structure fields)
  for child in sym.children:
    let childNode = leanSymbolToNode(child, modulePath)
    # Child qualified name becomes parent qualified name + "." + child name
    result.modulePath = modulePath  # ensure consistent module path

## Add a flat list of Lean symbols to the global symbol table.
proc addLeanSymbolsToTable*(
  table: var Table[string, SymbolNode],
  modulePath: string,
  symbols: seq[LeanDocumentSymbol]
) {.raises: [].} =
  for sym in symbols:
    let node = leanSymbolToNode(sym, modulePath)
    if not table.hasKey(node.qualifiedName):
      table[node.qualifiedName] = node
    # Register children recursively
    addLeanSymbolsToTable(table, modulePath, sym.children)

## Add Lean symbols as a ModuleGraphContribution for incremental cache.
proc leanSymbolsToCacheEntry*(
  fileHash: string,
  modulePath: string,
  symbols: seq[LeanDocumentSymbol]
): ModuleGraphContribution {.raises: [].} =
  var syms: seq[SymbolNode] = @[]
  for sym in symbols:
    let node = leanSymbolToNode(sym, modulePath)
    syms.add(node)
    for child in sym.children:
      let childNode = leanSymbolToNode(child, modulePath)
      syms.add(childNode)
  result = ModuleGraphContribution(
    fileHash: fileHash,
    symbols: syms,
    edges: @[]
  )
