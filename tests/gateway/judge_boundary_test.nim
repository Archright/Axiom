{.push raises: [CatchableError].}
import std/unittest
import std/strutils
import std/os

proc judgeImportsOnlyBoundary(): bool =
  let content = readFile("src/personas/judge.nim")
  for line in content.splitLines:
    let stripped = line.strip()
    if stripped.startsWith("import core/") and "boundary" notin stripped:
      return false
    if stripped.startsWith("from core/") and "boundary" notin stripped:
      return false
  return true

suite "judge boundary":
  test "judge imports core only through boundary":
    check judgeImportsOnlyBoundary()
{.pop.}
