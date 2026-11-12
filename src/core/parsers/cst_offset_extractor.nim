## CST offset extractor — start_byte:end_byte span extraction.
##
## Extracts byte-offset spans from tree-sitter nodes.
## NO tree mutation, NO serialization — surgical offset extraction only.
##
## Edge cases guarded:
##   - Forward declaration (bodySpan = none)
##   - Conditional compilation (when/when defined) — depth tracking
##   - Nested type/object — individual type_def separation

import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import std/options
import std/tables

import core/trusted/axiom_pragmas
import tree_sitter/types
import tree_sitter/node
import tree_sitter/nodes

# ── Data Model ────────────────────────────────────────────────────────────────

type
  ByteSpan* = object
    ## A (start, end) pair representing a byte-offset range.
    start*: uint32
    `end`*: uint32

  SymbolSpan* = object
    ## Byte-offset span for a single Nim symbol declaration.
    name*: string
    kind*: string          ## "proc"|"func"|"method"|"template"|"macro"|"type"|"converter"
    fullSpan*: ByteSpan   ## entire declaration
    bodySpan*: Option[ByteSpan]  ## none = forward declaration
    signatureSpan*: ByteSpan     ## signature (before body)
    indentLevel*: int
    depth*: int            ## 0 = top-level, >= 1 = inside when/conditional

# ── Node type → kind mapping ──────────────────────────────────────────────────

const
  nodeTypeKindMap: Table[string, string] = {
    "proc_declaration": "proc",
    "func_declaration": "func",
    "method_declaration": "method",
    "template_declaration": "template",
    "macro_declaration": "macro",
    "converter_declaration": "converter",
  }.toTable

  funcLikeTypes = [
    "proc_declaration", "func_declaration", "method_declaration",
    "template_declaration", "macro_declaration", "converter_declaration",
  ]

# ── Forward declarations ──────────────────────────────────────────────────────

proc extractFuncSpan(node: TSNode; source: string;
                    depth: int; inWhen: bool): Option[SymbolSpan] {.
  raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}
proc extractTypeSpan(node: TSNode; source: string;
                     depth: int; inWhen: bool): Option[SymbolSpan] {.
  raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}
proc findChildAfterEquals(node: TSNode): TSNode {.
  raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}
proc walkChildren(parent: TSNode; spans: var seq[SymbolSpan];
                  source: string; depth: int; inWhen: bool) {.
  raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}
proc processNode(node: TSNode; spans: var seq[SymbolSpan];
                 source: string; depth: int; inWhen: bool) {.
  raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}
proc walkWhen(node: TSNode; spans: var seq[SymbolSpan];
              source: string; depth: int; inWhen: bool) {.
  raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}
proc walkTypeSection(node: TSNode; spans: var seq[SymbolSpan];
                     source: string; depth: int; inWhen: bool) {.
  raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}
func sourceText*(node: TSNode; source: string): string
func calcIndent*(source: string; byteOffset: int): int

# ── Public API ────────────────────────────────────────────────────────────────

proc extractSymbolSpans*(root: TSNode; source: string): seq[SymbolSpan] {.
  raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Walk the CST and extract byte-offset spans for all symbols.
  ## Uses depth-controlled cursor traversal.
  result = @[]
  walkChildren(root, result, source, depth = 0, inWhen = false)

# ── Internal helpers ─────────────────────────────────────────────────────────

func findFuncName(node: TSNode; source: string): string {.
  raises: [].} =
  ## Extract the function name from a declaration node.
  ## Looks for the first named child that is an identifier.
  let count = tsNodeChildCount(node)
  for i in 0'u32 ..< count:
    let child = tsNodeChild(node, i)
    if child.id == nil: continue
    let ntype = $tsNodeType(child)
    if ntype == "identifier" or ntype == "exported_symbol":
      if ntype == "exported_symbol":
        # Return the inner identifier
        let innerCount = tsNodeChildCount(child)
        for j in 0'u32 ..< innerCount:
          let inner = tsNodeChild(child, j)
          if inner.id != nil and $tsNodeType(inner) == "identifier":
            return sourceText(inner, source)
      else:
        return sourceText(child, source)
  ""

func findUnnamedChildByType(node: TSNode; childType: string): TSNode {.
  raises: [].} =
  ## Find the first unnamed child whose node type matches childType.
  let count = tsNodeChildCount(node)
  for i in 0'u32 ..< count:
    let child = tsNodeChild(node, i)
    if child.id == nil: continue
    if not tsNodeIsNamed(child) and $tsNodeType(child) == childType:
      return child
  TSNode()

func findTypeName(node: TSNode; source: string): string {.
  raises: [].} =
  ## Extract the type name from a type_declaration node.
  let count = tsNodeChildCount(node)
  for i in 0'u32 ..< count:
    let child = tsNodeChild(node, i)
    if child.id == nil: continue
    if $tsNodeType(child) == "type_identifier":
      return sourceText(child, source)
  ""

proc walkChildren(parent: TSNode; spans: var seq[SymbolSpan];
                  source: string; depth: int; inWhen: bool) {.
  raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Walk all named children of a node and process each.
  let count = tsNodeChildCount(parent)
  for i in 0'u32 ..< count:
    let child = tsNodeChild(parent, i)
    if child.id == nil: continue
    processNode(child, spans, source, depth, inWhen)

proc processNode(node: TSNode; spans: var seq[SymbolSpan];
                 source: string; depth: int; inWhen: bool) {.
  raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Process a single CST node — dispatch to type or func extraction.
  let ntype = $tsNodeType(node)
  if ntype in funcLikeTypes:
    let span = extractFuncSpan(node, source, depth, inWhen)
    if span.isSome:
      spans.add(span.get())
  elif ntype == "type_section":
    walkTypeSection(node, spans, source, depth, inWhen)
  elif ntype == "when_statement":
    walkWhen(node, spans, source, depth, inWhen)

proc walkWhen(node: TSNode; spans: var seq[SymbolSpan];
              source: string; depth: int; inWhen: bool) {.
  raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Walk a when_statement — increment depth for nested branches.
  walkChildren(node, spans, source, depth + 1, inWhen = true)

proc walkTypeSection(node: TSNode; spans: var seq[SymbolSpan];
                     source: string; depth: int; inWhen: bool) {.
  raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Walk a type_section — extract each type_declaration.
  let count = tsNodeChildCount(node)
  for i in 0'u32 ..< count:
    let child = tsNodeChild(node, i)
    if child.id == nil: continue
    if $tsNodeType(child) == "type_declaration":
      let span = extractTypeSpan(child, source, depth, inWhen)
      if span.isSome:
        spans.add(span.get())

# ── Function-like declarations ────────────────────────────────────────────────

proc extractFuncSpan(node: TSNode; source: string;
                     depth: int; inWhen: bool): Option[SymbolSpan] {.
  raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Extract a SymbolSpan from a proc/func/method/template/macro/converter.
  ##
  ## Structure (common)::
  ##
  ##     <keyword>
  ##     [exported_symbol → identifier | identifier]  ← name
  ##     parameter_declaration_list
  ##     [: type_expression]                           ← optional return type
  ##     = statement_list                              ← body (absent for forward decl)
  let ntype = $tsNodeType(node)
  if ntype notin nodeTypeKindMap:
    return none(SymbolSpan)
  let kind = nodeTypeKindMap.getOrDefault(ntype, "")

  let name = findFuncName(node, source)
  if name.len == 0:
    return none(SymbolSpan)

  # Locate the '=' token — unnamed leaf, must search ALL children
  let eqNode = findUnnamedChildByType(node, "=")
  # statement_list is a named node
  let bodyNode = getChildByType(node, "statement_list")

  # Forward declaration: no '=' and no statement_list → bodySpan = none
  var bodySpan: Option[ByteSpan]
  if bodyNode.id != nil:
    bodySpan = some(ByteSpan(
      start: tsNodeStartByte(bodyNode),
      `end`: tsNodeEndByte(bodyNode)))

  # Signature = everything from start up to the '=' (or full node if forward decl)
  let sigEnd = if eqNode.id != nil: tsNodeStartByte(eqNode)
               else: tsNodeEndByte(node)

  let indent = calcIndent(source, tsNodeStartByte(node).int)

  some(SymbolSpan(
    name: name,
    kind: kind,
    fullSpan: ByteSpan(
      start: tsNodeStartByte(node),
      `end`: tsNodeEndByte(node)),
    bodySpan: bodySpan,
    signatureSpan: ByteSpan(start: tsNodeStartByte(node), `end`: sigEnd),
    indentLevel: indent,
    depth: depth))

proc extractTypeSpan(node: TSNode; source: string;
                     depth: int; inWhen: bool): Option[SymbolSpan] {.
  raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Extract a SymbolSpan from a type_declaration node.
  none(SymbolSpan)

proc findChildAfterEquals(node: TSNode): TSNode {.
  raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Return the first named child that appears after an '=' token.
  ## Used to find the body/value of a type_declaration.
  var foundEq = false
  let count = tsNodeChildCount(node)
  for i in 0'u32 ..< count:
    let child = tsNodeChild(node, i)
    if child.id == nil:
      continue
    if $tsNodeType(child) == "=":
      foundEq = true
      continue
    if foundEq and tsNodeIsNamed(child):
      return child
  return TSNode()

func sourceText*(node: TSNode; source: string): string {.
  raises: [].} =
  ## Extract the text of a node by slicing the source string using byte offsets.
  let start = tsNodeStartByte(node).int
  let endb = tsNodeEndByte(node).int
  if start < 0 or endb > source.len or start >= endb:
    return ""
  source[start ..< endb]

func calcIndent*(source: string; byteOffset: int): int {.
  raises: [].} =
  ## Compute the indentation level (tab-expanded, 2-space units) at byteOffset.
  ## Scans backward to the preceding newline and counts leading whitespace.
  if byteOffset <= 0 or byteOffset > source.len:
    return 0
  # Walk backward to find the start of the current line
  var pos = byteOffset - 1
  while pos > 0 and source[pos] != '\n':
    dec pos
  let lineStart = if source[pos] == '\n': pos + 1 else: pos

  # Count leading whitespace
  var col = lineStart
  var spaces = 0
  while col < byteOffset:
    let ch = source[col]
    if ch == ' ':
      inc spaces
    elif ch == '\t':
      spaces += 2  # tab = 2 spaces
    else:
      break
    inc col
  result = spaces div 2

{.pop.}

