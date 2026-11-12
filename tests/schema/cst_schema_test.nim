## cst_schema_test.nim — Tests for src/core/schema/cst_schema.
##
## Verifies type construction, concept satisfaction, computed properties,
## and JSON serialization round-trips for all schema types.

import std/[unittest, json]
import core/schema/cst_schema
import core/types/results

# ---------------------------------------------------------------------------
# FilePath
# ---------------------------------------------------------------------------

suite "FilePath":

  test "initFilePath and $":
    let p = initFilePath("/test/file.nim")
    check $p == "/test/file.nim"

  test "equality":
    let a = initFilePath("/a")
    let b = initFilePath("/a")
    let c = initFilePath("/b")
    check a == b
    check not (a == c)

  test "empty path":
    let p = initFilePath("")
    check $p == ""

# ---------------------------------------------------------------------------
# CstSpan
# ---------------------------------------------------------------------------

suite "CstSpan":

  test "initCstSpan fields":
    let s = initCstSpan(0, 10)
    check s.start == 0
    check s.endPos == 10

  test "spanLen":
    check initCstSpan(5, 15).spanLen == 10
    check initCstSpan(0, 0).spanLen == 0

  test "contains":
    let s = initCstSpan(5, 15)
    check s.contains(5)     # start inclusive
    check s.contains(10)    # interior
    check not s.contains(4) # before start
    check not s.contains(15) # end exclusive

  test "$ representation":
    check $initCstSpan(0, 100) == "(0..100)"

  test "toJson round-trip":
    let span = initCstSpan(10, 20)
    let j = toJson(span)
    check j["start"].getInt() == 10
    check j["endPos"].getInt() == 20
    let restored = fromJson(j, CstSpan)
    check restored.isOk()
    let r = restored.get()
    check r.start == 10
    check r.endPos == 20

# ---------------------------------------------------------------------------
# CstNodeKind
# ---------------------------------------------------------------------------

suite "CstNodeKind":

  test "enum values distinct":
    check cstUnknown != cstLeaf
    check cstLeaf != cstInternal
    check cstInternal != cstError

# ---------------------------------------------------------------------------
# ConcreteCstNode
# ---------------------------------------------------------------------------

suite "ConcreteCstNode":

  test "nil node $":
    let node: ConcreteCstNode = nil
    check $node == "<nil>"

  test "named leaf node $":
    let node = ConcreteCstNode(
      name: "x", kind: cstLeaf, detail: ndIdent,
      span: initCstSpan(0, 1), isNamed: true
    )
    check $node == "(ndIdent x)"

  test "unnamed internal node $":
    let node = ConcreteCstNode(
      kind: cstInternal, detail: ndStmtList,
      span: initCstSpan(0, 10)
    )
    check $node == "(ndStmtList)"

  test "node with children":
    let child1 = ConcreteCstNode(
      name: "a", kind: cstLeaf, detail: ndIdent,
      span: initCstSpan(0, 1), isNamed: true
    )
    let child2 = ConcreteCstNode(
      name: "b", kind: cstLeaf, detail: ndIdent,
      span: initCstSpan(2, 3), isNamed: true
    )
    let parent = ConcreteCstNode(
      kind: cstInternal, detail: ndCall,
      span: initCstSpan(0, 3),
      children: @[child1, child2], isNamed: true
    )
    check parent.children.len == 2
    check parent.children[0].name == "a"
    check parent.children[1].name == "b"

  test "toJson serialization":
    let node = ConcreteCstNode(
      name: "hello", kind: cstLeaf, detail: ndIdent,
      span: initCstSpan(0, 5), isNamed: true
    )
    let j = toJson(node)
    check j["name"].getStr() == "hello"
    check j["kind"].getStr() == "cstLeaf"
    check j["detail"].getStr() == "ndIdent"
    check j["isNamed"].getBool() == true
    check j["span"]["start"].getInt() == 0
    check j["span"]["endPos"].getInt() == 5
    check j["children"].len == 0

  test "toJson nil node":
    let j = toJson(nil)
    check j.kind == JNull

  test "toJson with children":
    let child = ConcreteCstNode(
      name: "c", kind: cstLeaf, detail: ndLitInt,
      span: initCstSpan(0, 1), isNamed: true
    )
    let parent = ConcreteCstNode(
      kind: cstInternal, detail: ndCall,
      span: initCstSpan(0, 1),
      children: @[child], isNamed: true
    )
    let j = toJson(parent)
    check j["children"].len == 1
    check j["children"][0]["name"].getStr() == "c"

# ---------------------------------------------------------------------------
# ParsedFile
# ---------------------------------------------------------------------------

suite "ParsedFile":

  test "initParsedFile":
    let pf = initParsedFile(initFilePath("/test.nim"), "code")
    check $pf.path == "/test.nim"
    check pf.source == "code"
    check pf.parseMs == 0.0
    check pf.errorCount == 0

  test "hasErrors false":
    let pf = initParsedFile(initFilePath("/ok.nim"), "ok")
    check not pf.hasErrors()

  test "hasErrors true":
    var pf = initParsedFile(initFilePath("/err.nim"), "bad")
    pf.errorCount = 3
    check pf.hasErrors()

  test "toJson serialization":
    var pf = initParsedFile(initFilePath("/x.nim"), "let x = 1")
    pf.parseMs = 2.5
    pf.errorCount = 0
    let j = toJson(pf)
    check j["path"].getStr() == "/x.nim"
    check j["source"].getStr() == "let x = 1"
    check j["parseMs"].getFloat() == 2.5
    check j["errorCount"].getInt() == 0
    check j["errors"].len == 0

  test "toJson with errors":
    var pf = initParsedFile(initFilePath("/e.nim"), "bad code")
    pf.errorCount = 1
    pf.errors.add(ParseError(line: 1, column: 5, byteOffset: 4, message: "unexpected"))
    let j = toJson(pf)
    check j["errorCount"].getInt() == 1
    check j["errors"].len == 1
    check j["errors"][0]["line"].getInt() == 1
    check j["errors"][0]["message"].getStr() == "unexpected"

  test "fromJson round-trip":
    var pf = initParsedFile(initFilePath("/rt.nim"), "source code")
    pf.parseMs = 1.23
    pf.errorCount = 1
    pf.errors.add(ParseError(line: 2, column: 3, byteOffset: 10, message: "err"))
    let j = toJson(pf)
    let restored = fromJson(j, ParsedFile)
    check restored.isOk()
    let r = restored.get()
    check $r.path == "/rt.nim"
    check r.source == "source code"
    check r.parseMs == 1.23
    check r.errorCount == 1
    check r.errors.len == 1
    check r.errors[0].line == 2
    check r.errors[0].message == "err"

# ---------------------------------------------------------------------------
# SyntaxStats
# ---------------------------------------------------------------------------

suite "SyntaxStats":

  test "default values":
    let s = SyntaxStats()
    check s.parseSuccessCount == 0
    check s.parseFailCount == 0
    check s.avgParseMs == 0.0

  test "totalParses":
    let s = SyntaxStats(parseSuccessCount: 10, parseFailCount: 2)
    check s.totalParses == 12

  test "successRate":
    let s = SyntaxStats(parseSuccessCount: 10, parseFailCount: 2)
    check s.successRate == 10.0 / 12.0

  test "successRate all success":
    let s = SyntaxStats(parseSuccessCount: 5, parseFailCount: 0)
    check s.successRate == 1.0

  test "successRate all fail":
    let s = SyntaxStats(parseSuccessCount: 0, parseFailCount: 5)
    check s.successRate == 0.0

  test "successRate empty":
    let s = SyntaxStats()
    check s.successRate == 0.0

  test "toJson round-trip":
    let stats = SyntaxStats(
      parseSuccessCount: 5, parseFailCount: 1, avgParseMs: 3.14
    )
    let j = toJson(stats)
    check j["parseSuccessCount"].getInt() == 5
    check j["parseFailCount"].getInt() == 1
    check j["avgParseMs"].getFloat() == 3.14
    let restored = fromJson(j, SyntaxStats)
    check restored.isOk()
    let r = restored.get()
    check r.parseSuccessCount == 5
    check r.parseFailCount == 1
    check r.avgParseMs == 3.14

  test "fromJson error handling":
    let bad = parseJson("""{"parseSuccessCount": "not_a_number"}""")
    let result = fromJson(bad, SyntaxStats)
    check result.isErr()
