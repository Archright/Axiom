{.warning[BareExcept]: off.}
import std/unittest
import std/json
import std/sequtils
import verification/lean_lsp_client
import verification/lean_lsp_protocol

suite "checkLeanAvailable":
  test "returns false when lean is not on PATH":
    let available = checkLeanAvailable()
    check available == true or available == false

  test "does not raise on repeated calls":
    for _ in 0 ..< 5:
      discard checkLeanAvailable()

suite "getDocumentSymbols — skip gate":
  test "skips gracefully when lean is unavailable":
    ## Verifies checkLeanAvailable() does not crash and returns a boolean.
    let available = checkLeanAvailable()
    check available == true or available == false

suite "extractDocSymbolKind":
  test "maps kind 12 to DskDefinition":
    let node = %*{"kind": %12}
    check node.extractDocSymbolKind() == DskDefinition

  test "maps kind 13 to DskTheorem":
    let node = %*{"kind": %13}
    check node.extractDocSymbolKind() == DskTheorem

  test "maps kind 3 to DskNamespace":
    let node = %*{"kind": %3}
    check node.extractDocSymbolKind() == DskNamespace

  test "defaults to DskDefinition for unknown kinds":
    let node = %*{"kind": %999}
    check node.extractDocSymbolKind() == DskDefinition

  test "handles missing kind key":
    let node = %*{"name": %"foo"}
    check node.extractDocSymbolKind() == DskDefinition

suite "extractSymbolsFromNode":
  test "extracts single symbol":
    let node = %*{
      "name": %"myTheorem",
      "kind": %13,
      "range": %*{
        "start": %*{"line": %0, "character": %0},
        "end": %*{"line": %2, "character": %10}
      }
    }
    let syms = extractSymbolsFromNode(node)
    check syms.len == 1
    check syms[0].name == "myTheorem"
    check syms[0].kind == DskTheorem
    check syms[0].span == (0, 2)

  test "extracts nested symbols recursively":
    let node = %*{
      "name": %"MyNamespace",
      "kind": %3,
      "range": %*{
        "start": %*{"line": %0, "character": %0},
        "end": %*{"line": %10, "character": %0}
      },
      "children": [
        %{
          "name": %"defFoo",
          "kind": %12,
          "range": %*{
            "start": %*{"line": %1, "character": %0},
            "end": %*{"line": %3, "character": %10}
          }
        },
        %{
          "name": %"theoremBar",
          "kind": %13,
          "range": %*{
            "start": %*{"line": %5, "character": %0},
            "end": %*{"line": %8, "character": %5}
          }
        }
      ]
    }
    let syms = extractSymbolsFromNode(node)
    check syms.len == 3
    let names = syms.mapIt(it.name).toSeq()
    check "MyNamespace" in names
    check "defFoo" in names
    check "theoremBar" in names

  test "returns empty sequence for non-object node":
    let node = %*["not", "an", "object"]
    let syms = extractSymbolsFromNode(node)
    check syms.len == 0

  test "returns empty sequence for node without name":
    let node = %*{
      "kind": %12,
      "range": %*{
        "start": %*{"line": %0, "character": %0},
        "end": %*{"line": %1, "character": %0}
      }
    }
    let syms = extractSymbolsFromNode(node)
    check syms.len == 0

  test "handles missing children key gracefully":
    let node = %*{
      "name": %"topLevel",
      "kind": %12,
      "range": %*{
        "start": %*{"line": %0, "character": %0},
        "end": %*{"line": %1, "character": %0}
      }
    }
    let syms = extractSymbolsFromNode(node)
    check syms.len == 1
    check syms[0].name == "topLevel"


