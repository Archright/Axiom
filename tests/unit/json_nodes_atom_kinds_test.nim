## tests/unit/json_nodes_atom_kinds_test.nim
## `collectNodesFromStatement` walks a statement subtree with `stmt.len` /
## `stmt[i]`. Those accessors raise FieldDefect on the TNode variant kinds that
## store their payload in a field rather than in `sons` (compiler/ast.nim).
##
## `nkRStrLit` was missing from the module's atom-kind set — the only module in
## src/ whose set omitted it — so a raw string literal reached the statement
## collector and crashed on `stmt.len` in the dispatch's fallback arm. The crash
## only became reachable once candidates actually reached proof, because nothing
## before that walked a subject containing one.
##
## The fixtures go through the public entry point and each one also produces a
## node, so a collector that quietly stopped walking would fail here rather than
## pass a vacuously-empty result.

import std/[json, unittest]
import compiler/ast
import core/translator/nim_ast_to_json_nodes

proc withAssign(literal: string): string =
  ## `v = <literal>` — the assignment arm recurses into the right-hand side
  ## directly, so the atom lands in `collectNodesFromStatement` with no wrapper
  ## expression that could absorb it, and the assign node proves the statement
  ## really was walked.
  "proc atomProbe(a: int): int =\n" &
  "  var v = a\n" &
  "  v = " & literal & "\n" &
  "  v\n"

const AtomLiterals: seq[tuple[kind: TNodeKind, literal: string]] = @[
  (nkIdent,        "someIdent"),
  (nkCharLit,      "'x'"),
  (nkIntLit,       "42"),
  (nkInt8Lit,      "8'i8"),
  (nkUIntLit,      "7'u"),
  (nkFloatLit,     "1.5"),
  (nkFloat32Lit,   "2.5'f32"),
  (nkStrLit,       "\"plain\""),
  (nkRStrLit,      "r\"raw\""),
  (nkTripleStrLit, "\"\"\"triple\"\"\""),
  (nkNilLit,       "nil")
]
## The literal families the compiler can produce as a bare value. nkSym is
## absent because it has no source spelling that parses as a standalone
## expression; nkEmpty and nkCommentStmt are not expressions at all.

suite "nim_ast_to_json_nodes: atom node kinds never reach the son walk":

  test "an assignment to an atom yields its assign node without a crash":
    let plain = sourceCodeToJsonNodes(withAssign("\"plain\""), "atomProbe")
    check plain.kind == JArray
    check plain.len == 1

  test "every atom literal family is walked without a FieldDefect":
    for fixture in AtomLiterals:
      let kind = fixture.kind
      let literal = fixture.literal
      let nodes = sourceCodeToJsonNodes(withAssign(literal), "atomProbe")
      check nodes.kind == JArray
      check nodes.len == 1

  test "a raw string literal alone is the regression that crashed":
    # `nkRStrLit` was absent from LiteralPNodeKinds, so this one value fell
    # through to the fallback arm, where `stmt.len` on an atom raises.
    let nodes = sourceCodeToJsonNodes(withAssign("r\"raw\""), "atomProbe")
    check nodes.kind == JArray
    check nodes.len == 1

  test "an atom as a discarded statement's operand is not a crash either":
    # `discard <atom>` has no dedicated arm, so it arrives through the
    # fallback the guard now protects.
    let nodes = sourceCodeToJsonNodes(
      "proc discarded(a: int): int =\n" &
      "  discard r\"raw\"\n" &
      "  a\n", "discarded")
    check nodes.kind == JArray

  test "an atom as a call argument is not a crash either":
    let nodes = sourceCodeToJsonNodes(
      "proc asArg(a: int): int =\n" &
      "  echo \"x\", r\"raw\"\n" &
      "  a\n", "asArg")
    check nodes.kind == JArray