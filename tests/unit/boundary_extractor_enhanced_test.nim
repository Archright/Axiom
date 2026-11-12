import std/unittest
import core/parser_utils
import core/boundary/boundary_extractor

suite "Boundary Extractor SSA Enhancements":
  test "findNodesMultiTag matches multiple tags":
    let ast = parseStringAST("""
      proc f(): int =
        let x = g()
        let y = h()
        result = x + y
    """)
    let result = findNodesMultiTag(ast, ["call", "assignment"])
    check result.len == 3  # 2 calls (g(), h()) + 1 assignment (result = x + y)

  test "findNodesMultiTag returns empty for no match":
    let ast = parseStringAST("""
      proc f(): int =
        let x = 1
        result = x
    """)
    let result = findNodesMultiTag(ast, ["for_statement", "while_statement"])
    check result.len == 0

  test "findNodesMultiTag works with single tag":
    let ast = parseStringAST("""
      proc f(): int =
        let x = g()
        result = x
    """)
    let result = findNodesMultiTag(ast, ["call"])
    check result.len == 1

  test "findNodesMultiTag handles deeply nested nodes":
    let ast = parseStringAST("""
      proc f(): int =
        if true:
          let x = assertCheck(true)
          doAssert(x > 0)
    """)
    let result = findNodesMultiTag(ast, ["call"])
    check result.len == 2  # assertCheck(true) + doAssert(x > 0)

  test "findNodesMultiTag does not duplicate nodes matching multiple tags":
    let ast = parseStringAST("""
      proc f(): int =
        let x = g()
        result = x
    """)
    let result = findNodesMultiTag(ast, ["call", "assignment"])
    check result.len == 2  # 1 call + 1 assignment, no duplicates
