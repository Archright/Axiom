import std/unittest
import std/sets
import std/tables
import core/results
import verification/ast_extractor

suite "ast_extractor Result types":
  test "collectModuleFunctions returns Result with empty source":
    let res = collectModuleFunctions("")
    check res.isOk()
    check res.get().len == 0

  test "collectGlobalSymbols returns Result with empty source":
    let res = collectGlobalSymbols("")
    check res.isOk()
    check res.get().len == 0

  test "extractFunctionBody returns Result with empty source":
    let res = extractFunctionBody("", "nonexistent")
    check res.isOk()
    check not res.get().found

  test "getCachedFunctionNodeIndex returns Result with empty source":
    let res = getCachedFunctionNodeIndex("")
    check res.isOk()
    let idx = res.get()
    check len(idx) == 0

  test "getCachedNimAst returns Result with empty source":
    let res = getCachedNimAst("")
    check res.isOk()
