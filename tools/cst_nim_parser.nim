## tools/cst_nim_parser.nim — CST-based Nim Source Parser (Pure Nim).
##
## Extracts structural elements from Nim source files: imports, exports,
## proc/func/type/const/var declarations, and module metadata.
##
## Port of: tools/cst_nim_parser.py
## Note: The Python version depends on tree-sitter (C extension via Python bindings).
##       This Nim version uses structural pattern matching — simpler but covers
##       the core functionality of identifying Nim constructs without external deps.
##       For full grammar-guaranteed parsing, use the tree-sitter C API via FFI
##       or the project's existing Nim parser infrastructure.
##
## Usage:
##   nim c -r tools/cst_nim_parser.nim <file.nim>
##   nim c -r tools/cst_nim_parser.nim --smoke-test
##   nim c -r tools/cst_nim_parser.nim --sexp <file.nim>

import core/trusted/layer_declaration
axiomLayer "tools"
import api/tools_facade
import shared_types/shared_types
import std/[os, strutils, json, algorithm]
import std/[os, strutils, json, re, algorithm, tables]
import std/os
import std/strutils
type
  NimNodeKind = enum
    nkModule, nkImport, nkExport, nkProc, nkFunc, nkMethod,
    nkType, nkConst, nkVar, nkLet, nkEnum, nkObject,
    nkTemplate, nkMacro, nkIterator, nkConverter, nkPragma,
    nkWhen, nkIf, nkWhile, nkFor, nkBlock, nkCase, nkTry

  NimNode = object
    kind: NimNodeKind
    name: string
    line: int
    col: int
    exported: bool    ## Has * (export marker)
    signature: string ## Full line text

  ParseResult = object
    fileName: string
    moduleName: string
    nodes: seq[NimNode]
const
  TopLevelKinds = {nkImport, nkExport, nkProc, nkFunc, nkMethod,
                   nkType, nkConst, nkVar, nkLet, nkTemplate,
                   nkMacro, nkIterator, nkConverter, nkPragma}
func kindName*(kind: NimNodeKind): string =
  ## Map a NimNodeKind to its string representation.
  result = case kind
    of nkImport: "import"
    of nkExport: "export"
    of nkProc: "proc"
    of nkFunc: "func"
    of nkMethod: "method"
    of nkType: "type"
    of nkConst: "const"
    of nkVar: "var"
    of nkLet: "let"
    of nkTemplate: "template"
    of nkMacro: "macro"
    of nkIterator: "iterator"
    of nkConverter: "converter"
    of nkPragma: "pragma"
    of nkWhen: "when"
    of nkIf: "if"
    of nkWhile: "while"
    of nkFor: "for"
    of nkBlock: "block"
    of nkCase: "case"
    of nkTry: "try"
    of nkModule: "module"
    of nkEnum: "enum"
    of nkObject: "object"
func classifyLine(line: string): NimNodeKind =
  ## Classify a top-level line into a node kind.
  let s = line.strip()
  if s.len == 0 or s.startsWith("#"):
    return nkModule  # sentinel for "not a declaration"
  if s.startsWith("import ") or (s.startsWith("from ") and "import" in s):
    return nkImport
  if s.startsWith("export ") or (s.startsWith("from ") and "export" in s):
    return nkExport
  if s.startsWith("proc ") or s.startsWith("proc\t"):
    return nkProc
  if s.startsWith("func ") or s.startsWith("func\t"):
    return nkFunc
  if s.startsWith("method ") or s.startsWith("method\t"):
    return nkMethod
  if s.startsWith("type"):
    return nkType
  if s.startsWith("const "):
    return nkConst
  if s.startsWith("var "):
    return nkVar
  if s.startsWith("let "):
    return nkLet
  if s.startsWith("template ") or s.startsWith("template\t"):
    return nkTemplate
  if s.startsWith("macro ") or s.startsWith("macro\t"):
    return nkMacro
  if s.startsWith("iterator ") or s.startsWith("iterator\t"):
    return nkIterator
  if s.startsWith("converter ") or s.startsWith("converter\t"):
    return nkConverter
  if s.startsWith("{.") or s.startsWith("}"):
    return nkPragma
  result = nkModule  # not a top-level declaration
func extractName(declLine: string): string =
  ## Extract the identifier name from a declaration line.
  let s = declLine.strip()
  # Skip keyword prefix
  var start = 0
  for kw in ["proc ", "func ", "method ", "template ", "macro ",
             "iterator ", "converter ", "const ", "var ", "let "]:
    if s.startsWith(kw):
      start = kw.len
      break
  if start == 0:
    return ""

  # Read identifier chars (including `*` export marker)
  var name = ""
  for i in start ..< s.len:
    let c = s[i]
    if c in Letters or c in Digits or c == '_' or c == '*':
      name.add(c)
    else:
      break
  result = name
func hasExportMarker(declLine: string): bool =
  ## Check if a declaration has the `*` export marker.
  result = '*' in declLine
func extractImports(content: string): seq[NimNode] =
  ## Extract all import statements.
  result = @[]
  var inImportBlock = false
  var lineIdx = 0
  for line in content.splitLines():
    let s = line.strip()
    if s.startsWith("import ") or (s.startsWith("from ") and "import" in s):
      result.add(NimNode(
        kind: nkImport,
        name: s,
        line: lineIdx + 1,
        col: 0,
        exported: false,
        signature: s
      ))
      inImportBlock = false
    elif s == "import":
      inImportBlock = true
    elif inImportBlock and s.len > 0 and not s.startsWith("#"):
      # Continuation of multi-line import
      result.add(NimNode(
        kind: nkImport,
        name: s,
        line: lineIdx + 1,
        col: 0,
        exported: false,
        signature: s
      ))
      if not s.endsWith(","):
        inImportBlock = false
    inc lineIdx
func parseNimSource(source, fileName: string): ParseResult =
  ## Parse Nim source code into a structured result.
  result.fileName = fileName
  result.moduleName = fileName.splitFile().name
  result.nodes = @[]

  var lineIdx = 0
  for line in source.splitLines():
    let kind = classifyLine(line)
    if kind == nkModule:
      inc lineIdx
      continue

    let name = extractName(line)
    let exported = hasExportMarker(line)
    result.nodes.add(NimNode(
      kind: kind,
      name: name,
      line: lineIdx + 1,
      col: 0,
      exported: exported,
      signature: line.strip()
    ))
    inc lineIdx

  # Also extract imports specially
  let imports = extractImports(source)
  for imp in imports:
    # Avoid duplicates
    var found = false
    for existing in result.nodes:
      if existing.kind == nkImport and existing.line == imp.line:
        found = true
        break
    if not found:
      result.nodes.add(imp)

  # Sort by line number for determinism
  result.nodes.sort(proc(a, b: NimNode): int = cmp(a.line, b.line))
func toSexp(node: NimNode): string =
  ## Convert a NimNode to a minimal s-expression.
  let exported = if node.exported: "*" else: ""
  result = "(" & node.kind.kindName() & " " & node.name & exported &
           " :line " & $node.line & ")"
func toJson(pr: ParseResult): JsonNode =
  ## Convert ParseResult to JSON.
  var nodesArr = newJArray()
  for node in pr.nodes:
    nodesArr.add(%*{
      "kind": node.kind.kindName(),
      "name": node.name,
      "line": node.line,
      "exported": node.exported,
      "signature": node.signature,
    })

  result = %*{
    "fileName": pr.fileName,
    "moduleName": pr.moduleName,
    "nodeCount": pr.nodes.len,
    "nodes": nodesArr,
  }
proc runSmokeTest() {.axiomEffect: IoEffect, raises: [CatchableError].} =
  ## Quick smoke test with a sample Nim source.
  let sample = """proc foo*(x: int): int =
  result = x + 1
func bar(a, b: string): bool =
  a == b
type
  Point = object
    x, y: int
"""
  let parsed = parseNimSource(sample, "<smoke_test>")
  echo "=== Smoke Test: CST-like Nim Parser ==="
  echo "Nodes found: ", parsed.nodes.len
  echo ""
  echo "S-expression output:"
  for node in parsed.nodes:
    echo "  ", toSexp(node)
  echo ""
  echo "JSON output:"
  echo pretty(toJson(parsed), indent = 2)

proc main() {.axiomEffect: IoEffect, raises: [CatchableError].} =
  let params = commandLineParams()

  if params.len == 0:
    echo "Usage: cst_nim_parser <file.nim>"
    echo "       cst_nim_parser --smoke-test"
    echo "       cst_nim_parser --sexp <file.nim>"
    echo ""
    echo "Extracts structural elements from Nim source files."
    echo "Output: JSON to stdout (default) or s-expression with --sexp."
    quit(0)

  if params[0] == "--smoke-test":
    runSmokeTest()
    quit(0)

  var sexpMode = false
  var filePath = params[0]
  if params[0] == "--sexp" and params.len > 1:
    sexpMode = true
    filePath = params[1]

  if not fileExists(filePath):
    stderr.writeLine("ERROR: File not found: ", filePath)
    quit(1)

  let source = readFile(filePath)
  let parsed = parseNimSource(source, filePath)

  if sexpMode:
    echo "(module " & parsed.moduleName & " :nodes " & $parsed.nodes.len & ")"
    for node in parsed.nodes:
      echo "  ", toSexp(node)
  else:
    echo pretty(toJson(parsed), indent = 2)

when isMainModule:
  main()

when isMainModule:
  main()
