## CstAdapter Feature Test.
## See tests/features/cst_adapter.feature for the specification.
##
## Validates the CST schema types (CstSpan, CstNodeKind, ConcreteCstNode,
## SyntaxStats) exposed by core/schema/cst_schema. The tree-sitter parser is
## NOT vendored in this build, so only the pure schema API (which does not
## depend on the tree-sitter FFI) is exercised — matching the "graceful
## degradation" scenario of the feature spec.

{.push raises: [].}

import core/schema/cst_schema
import core/types/results
import std/[unittest, strutils]

const FuncDeclLen = uint32("proc hello*(x: int): string =\n  discard".len)

suite "CstSpan — byte offset tracking":
  test "initCstSpan stores start and endPos":
    let sp = initCstSpan(0'u32, 17'u32)
    check sp.start == 0'u32
    check sp.endPos == 17'u32

  test "span start begins at byte 0":
    let sp = initCstSpan(0'u32, FuncDeclLen)
    check sp.start == 0'u32

  test "span endPos matches source length":
    let sp = initCstSpan(0'u32, FuncDeclLen)
    check sp.endPos == FuncDeclLen

  test "child spans are within root span":
    let root = initCstSpan(0'u32, 100'u32)
    let child = initCstSpan(10'u32, 40'u32)
    check child.start >= root.start
    check child.endPos <= root.endPos

  test "span JSON round-trip preserves values":
    let sp = initCstSpan(4'u32, 9'u32)
    let js = toJson(sp)
    let back = fromJson(js, CstSpan).get
    check back.start == sp.start
    check back.endPos == sp.endPos

suite "CstNodeKind & ConcreteCstNode — node classification":
  test "newCstNode defaults to cstUnknown":
    let node = newCstNode()
    check node.kind == cstUnknown
    check node.children.len == 0

  test "newCstNode records kind and detail":
    let node = newCstNode(nodeName = "root", nodeKind = cstInternal)
    check node.kind == cstInternal
    check node.name == "root"

  test "childCount equals children length":
    let child = newCstNode(nodeName = "kid")
    let parent = newCstNode(nodeName = "parent",
                            nodeChildren = @[child])
    check parent.children.len == 1

  test "isNamed reflects node flag":
    let node = newCstNode(nodeName = "n", nodeIsNamed = true)
    check node.isNamed

  test "leaf vs internal kinds are distinguishable":
    let leaf = newCstNode(nodeKind = cstLeaf)
    let internal = newCstNode(nodeKind = cstInternal)
    check leaf.kind != internal.kind

  test "node span is a valid slice boundary":
    let node = newCstNode(nodeName = "x",
                          nodeSpan = initCstSpan(0'u32, 5'u32))
    check node.span.endPos <= 5'u32

suite "SyntaxStats — parse statistics":
  test "totalParses sums success and failure":
    var stats = SyntaxStats()
    stats.parseSuccessCount = 3'u32
    stats.parseFailCount = 1'u32
    check totalParses(stats) == 4'u32

  test "successRate is computed as a ratio":
    var stats = SyntaxStats()
    stats.parseSuccessCount = 3'u32
    stats.parseFailCount = 1'u32
    check successRate(stats) == 0.75

  test "empty stats yield zero rate":
    var stats = SyntaxStats()
    check successRate(stats) == 0.0

suite "ParsedFile — parse result container":
  test "initParsedFile keeps source":
    let pf = initParsedFile(initFilePath("test.nim"), "proc foo() = discard")
    check string(pf.path) == "test.nim"
    check pf.source == "proc foo() = discard"
    check pf.errorCount == 0

{.pop.}
