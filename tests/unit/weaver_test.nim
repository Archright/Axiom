import std/strutils
import ../../src/frontend/nim/weaver
import std/unittest

proc testFindProcBodyStartLineBasic() =
  let src = "proc foo(x: int) =\n  body"
  check findProcBodyStartLine(src, 0) == 1

proc testFindProcBodyStartLineDefaultParam() =
  let src = "proc foo(x: int = 5) =\n  body"
  check findProcBodyStartLine(src, 0) == 1

proc testFindProcBodyStartLineCommentEquals() =
  let src = "proc foo() # a = b\n  =\n  body"
  check findProcBodyStartLine(src, 0) == 2

proc testFindProcBodyStartLineInlineBody() =
  let src = "proc foo(x: int) = body"
  check findProcBodyStartLine(src, 0) == 0

proc testStripAllGuardBlocksTerminated() =
  let src = "proc foo() =\n  # AxiomGuard:123\n  doAssert true\n  # EndAxiomGuard\n  body"
  let result = stripAllGuardBlocks(src)
  check not result.contains("AxiomGuard")
  check result.contains("body")

proc testStripAllGuardBlocksUnterminatedPreservesSource() =
  let src = "proc foo() =\n  # AxiomGuard:123\n  doAssert true\n  body"
  let result = stripAllGuardBlocks(src)
  check result.contains("AxiomGuard")
  check result.contains("body")

suite "Weaver":
  test "Weaver tests":
    testFindProcBodyStartLineBasic()
    testFindProcBodyStartLineDefaultParam()
    testFindProcBodyStartLineCommentEquals()
    testFindProcBodyStartLineInlineBody()
    testStripAllGuardBlocksTerminated()
    testStripAllGuardBlocksUnterminatedPreservesSource()
