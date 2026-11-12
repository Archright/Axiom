## Integration tests for CST offset extractor and surgical editor.
##
## Port of tools/tests/test_cst_surgical.py to Nim.
##
## Build & run:
##   nim c --passL:build/nim.so -r tests/parsers/cst_extractor_test.nim

{.push raises: [].}

import std/unittest
import std/strutils

import core/trusted/axiom_pragmas
import src/core/parsers/tree_sitter/types
import src/core/parsers/tree_sitter/bindings
import src/core/parsers/tree_sitter/node
import src/core/parsers/cst_offset_extractor
import src/core/parsers/cst_surgical_editor

# ── Test helpers ──────────────────────────────────────────────────────────────

proc parseSource(source: string): TSNode =
  ## Parse Nim source and return the root TSNode.
  let lang = tree_sitter_nim()
  let parser = ts_parser_new()
  discard ts_parser_set_language(parser, lang)
  let tree = ts_parser_parse_string(parser, TSTree(nil),
                                    source.cstring, source.len.uint32)
  result = ts_tree_root_node(tree)

# ── Tests ─────────────────────────────────────────────────────────────────────

suite "CST offset extractor":
  test "basic proc extraction":
    let source = """proc foo*(x: int): int =
  result = x + 1

proc bar*(x: int): int =
  result = x * 2
"""
    let root = parseSource(source)
    let spans = extractSymbolSpans(root, source)

    # Should find foo and bar
    var foundFoo = false
    var foundBar = false
    for s in spans:
      if s.name == "foo": foundFoo = true
      if s.name == "bar": foundBar = true
    check foundFoo
    check foundBar

    # Extract foo's full span
    for s in spans:
      if s.name == "foo":
        let extracted = surgicalExtract(source, s.fullSpan)
        check "foo" in extracted
        # Replace foo's body
        check s.bodySpan.isSome
        let modified = surgicalReplaceBody(source, s.bodySpan.get,
                                           "  discard ## moved\n")
        check "discard ## moved" in modified
        check "bar" in modified
        check "x + 1" notin modified

  test "forward declaration":
    let source = """proc foo*(x: int): int

proc bar*(x: int): int =
  result = x + 1
"""
    let root = parseSource(source)
    let spans = extractSymbolSpans(root, source)

    for s in spans:
      if s.name == "foo":
        check s.bodySpan.isNone

  test "type section":
    let source = """type
  Point* = object
    x, y: int

  Color* = enum
    Red, Green, Blue

proc use*(p: Point) =
  discard
"""
    let root = parseSource(source)
    let spans = extractSymbolSpans(root, source)

    var foundUse = false
    for s in spans:
      if s.name == "use": foundUse = true
    check foundUse

  test "multiline preservation":
    let source = """# Header comment
import std/strutils

proc target*(x: int): int =
  ## Docstring
  result = x + 1

proc keep*(s: string): string =
  result = s.toLowerAscii()
"""
    let root = parseSource(source)
    let spans = extractSymbolSpans(root, source)

    for s in spans:
      if s.name == "target":
        check s.bodySpan.isSome
        let modified = surgicalReplaceBody(source, s.bodySpan.get,
                                           "  discard ## moved\n")
        check "# Header comment" in modified
        check "import std/strutils" in modified
        check "proc keep*" in modified
        check "s.toLowerAscii()" in modified

suite "Surgical editor":
  test "surgical_extract":
    let source = "proc foo*(x: int): int =\n  result = x + 1\n"
    let span = ByteSpan(start: 0'u32, `end`: 17'u32)
    let extracted = surgicalExtract(source, span)
    check extracted == "proc foo*(x: int): int"

  test "surgical_replace_body":
    let source = "proc foo*(x: int): int =\n  result = x + 1\n"
    let span = ByteSpan(start: 22'u32, `end`: 38'u32)
    let modified = surgicalReplaceBody(source, span, "  discard\n")
    check "proc foo*(x: int): int =" in modified
    check "discard" in modified
    check "result = x + 1" notin modified

  test "surgical_multi_replace":
    let source = "proc a*() =\n  discard\n\nproc b*() =\n  discard\n"
    let reps = @[
      SpanReplacement(
        span: ByteSpan(start: 12'u32, `end`: 22'u32),
        stub: "  echo \"a\"\n"),
      SpanReplacement(
        span: ByteSpan(start: 30'u32, `end`: 40'u32),
        stub: "  echo \"b\"\n"),
    ]
    let modified = surgicalMultiReplace(source, reps)
    check "echo \"a\"" in modified
    check "echo \"b\"" in modified
    check "proc a*" in modified
    check "proc b*" in modified

when isMainModule:
  discard
