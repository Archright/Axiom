{.push raises: [].}

import std/unittest
import core/symbol_graph/global_symbol_graph_builder_part1

suite "extractSymbolsFromSourceFallback":
  test "finds proc, func, method, iterator, converter symbols":
    let testSource = """
proc hello(x: int): int =
  result = x + 1

func safeAdd(a, b: int): int =
  return a + b

method greet(self: Obj) =


iterator items(s: seq[int]): int =
  for x in s:
    yield x

converter toInt(s: string): int =
  safeParseInt(s).get
"""
    let syms = extractSymbolsFromSourceFallback(testSource, "test_module.nim")
    var foundNames: seq[string] = @[]
    for sym in syms:
      foundNames.add(sym.qualifiedName)
    check "test_module.hello" in foundNames
    check "test_module.safeAdd" in foundNames
    check "test_module.greet" in foundNames
    check "test_module.items" in foundNames
    check "test_module.toInt" in foundNames
