## Tests for CstDocument lifecycle + TreeSitterCstNode interface.
##
## Build & run:
##   nim c --path:src --passL:build/nim.so -r tests/parsers/cst_adapter_test.nim
##
## Skips all tests if libtree-sitter is unavailable.

{.push raises: [].}

import std/unittest
import std/strutils

import core/trusted/axiom_pragmas
import core/types/results
import core/schema/cst_schema
import core/parsers/tree_sitter/types
import core/parsers/tree_sitter/bindings
import core/parsers/tree_sitter/node
import core/parsers/tree_sitter/parser
import core/parsers/cst_adapter

# ── Availability check ───────────────────────────────────────────────────────

var treeSitterAvailable {.threadvar.}: bool

proc checkTreeSitter(): bool =
  ## Runtime probe: can we create a parser AND get the Nim grammar?
  if treeSitterAvailable:
    return true
  let p = newNimParser()
  let lang = tree_sitter_nim()
  treeSitterAvailable = (not p.isNil) and (not lang.isNil)
  if not treeSitterAvailable:
    echo "SKIP: libtree-sitter or tree-sitter-nim grammar not available"
  treeSitterAvailable

# ── Tests ────────────────────────────────────────────────────────────────────

suite "CstDocument lifecycle":
  test "create and destroy CstDocument":
    if checkTreeSitter():
      let lang = tree_sitter_nim()
      let src = "proc foo*(x: int): int =\n  result = x + 1\n"
      let doc = newCstDocument(src, lang)
      check doc.isOk
      let d = doc.get
      check not d.isNil
      check d.source == src
      check not d.tree.isNil
      check not d.parser.isNil
    else:
      skip()

  test "rootNode returns valid view":
    if checkTreeSitter():
      let lang = tree_sitter_nim()
      let src = "let x = 42\n"
      let doc = newCstDocument(src, lang).get
      let root = doc.rootNode
      check root.doc == doc
      check ($root).len > 0
    else:
      skip()

  test "parse error returns err":
    if checkTreeSitter():
      let lang = tree_sitter_nim()
      let r = parseSource(nil, lang, "x")
      check r.isErr
    else:
      skip()

  test "GC collects CstDocument cleanly":
    if checkTreeSitter():
      let lang = tree_sitter_nim()
      block:
        let src = "discard\n"
        let doc = newCstDocument(src, lang).get
        let root = doc.rootNode
        discard $root
      GC_fullCollect()
    else:
      skip()

suite "TreeSitterCstNode interface":
  test "kind detection":
    if checkTreeSitter():
      let lang = tree_sitter_nim()
      let src = "let x = 1\n"
      let doc = newCstDocument(src, lang).get
      let root = doc.rootNode
      check root.kind == cstInternal
    else:
      skip()

  test "span extraction":
    if checkTreeSitter():
      let lang = tree_sitter_nim()
      let src = "let x = 1\n"
      let doc = newCstDocument(src, lang).get
      let root = doc.rootNode
      let s = root.span
      check s.start == 0'u32
      check s.endPos > 0'u32
    else:
      skip()

  test "isNamed":
    if checkTreeSitter():
      let lang = tree_sitter_nim()
      let src = "let x = 1\n"
      let doc = newCstDocument(src, lang).get
      let root = doc.rootNode
      check root.isNamed
    else:
      skip()

  test "children iteration":
    if checkTreeSitter():
      let lang = tree_sitter_nim()
      let src = "let x = 1\nlet y = 2\n"
      let doc = newCstDocument(src, lang).get
      let root = doc.rootNode
      let kids = root.children
      check kids.len > 0
      for kid in kids:
        check kid.doc == doc
    else:
      skip()

  test "text extraction":
    if checkTreeSitter():
      let lang = tree_sitter_nim()
      let src = "let x = 42\n"
      let doc = newCstDocument(src, lang).get
      let root = doc.rootNode
      let t = root.text
      check t.len > 0
      check "let" in t or "x" in t
    else:
      skip()

  test "$ string repr":
    if checkTreeSitter():
      let lang = tree_sitter_nim()
      let src = "let x = 1\n"
      let doc = newCstDocument(src, lang).get
      let root = doc.rootNode
      let s = $root
      check s.len > 0
    else:
      skip()

  test "childCount matches children.len":
    if checkTreeSitter():
      let lang = tree_sitter_nim()
      let src = "let a = 1\nlet b = 2\n"
      let doc = newCstDocument(src, lang).get
      let root = doc.rootNode
      check root.childCount == root.children.len.uint32
    else:
      skip()

# ── Direct API smoke test (isolates adapter vs raw FFI) ──────────────────────

suite "Direct tree-sitter API":
  test "raw parse and access root":
    if not checkTreeSitter(): skip()
    else:
      let lang = tree_sitter_nim()
      let parser = ts_parser_new()
      discard ts_parser_set_language(parser, lang)
      let src = "let x = 42\n"
      let tree = ts_parser_parse_string(parser, TSTree(nil),
                                        src.cstring, src.len.uint32)
      check not tree.isNil
      let root = ts_tree_root_node(tree)
      let nodeType = ts_node_type(root)
      let s = $nodeType
      check s.len > 0
      echo "raw root type: ", s

when isMainModule:
  discard
