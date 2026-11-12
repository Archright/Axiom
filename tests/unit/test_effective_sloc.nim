import std/[unittest, strutils]
import gate/daemon/content_hash

func countEffectiveSLOC(lines: seq[string]; startLine, endLine: int): int =
  if startLine > endLine or endLine < 1 or lines.len == 0:
    return 0
  if startLine > lines.len:
    return 0
  let hi = min(endLine, lines.len)
  var extracted: string
  for i in startLine - 1 ..< hi:
    if i == startLine - 1:
      extracted.add(lines[i])
    else:
      extracted.add("\n")
      extracted.add(lines[i])
  let stripped = stripComments(extracted)
  var count = 0
  for line in stripped.splitLines():
    if line.strip().len > 0:
      inc count
  count

suite "effectiveSLOC invariant - comment-only change":
  test "comment-only change does not affect effectiveSLOC":
    let base = "proc f() =\n  ## doc\n  result = 1"
    let withC = "proc f() =\n  ## doument better\n  result = 1"
    let baseLines = base.splitLines()
    let withCLines = withC.splitLines()
    check countEffectiveSLOC(baseLines, 1, baseLines.len) ==
           countEffectiveSLOC(withCLines, 1, withCLines.len)

suite "effectiveSLOC invariant - blank-line-only change":
  test "blank-line-only change does not affect effectiveSLOC":
    let base = "proc f() =\n  result = 1"
    let withBlank = "proc f() =\n\n  result = 1"
    let baseLines = base.splitLines()
    let withBlankLines = withBlank.splitLines()
    check countEffectiveSLOC(baseLines, 1, baseLines.len) ==
           countEffectiveSLOC(withBlankLines, 1, withBlankLines.len)

suite "effectiveSLOC invariant - code-line addition":
  test "adding a code line increases effectiveSLOC by 1":
    let base = "proc f() =\n  result = 1"
    let withExtra = "proc f() =\n  result = 1\n  result = 2"
    let baseLines = base.splitLines()
    let withExtraLines = withExtra.splitLines()
    check countEffectiveSLOC(withExtraLines, 1, withExtraLines.len) ==
           countEffectiveSLOC(baseLines, 1, baseLines.len) + 1

suite "effectiveSLOC invariant - multiline expression":
  test "multiline expression counts each active token line":
    let code = "proc f() =\n  foo(\n    a,\n    b\n  )"
    let lines = code.splitLines()
    check countEffectiveSLOC(lines, 1, lines.len) == 5

suite "effectiveSLOC invariant - string internal comment preservation":
  test "stripComments preserves ## inside string literal":
    let src = "let x = \"## not comment\""
    let stripped = stripComments(src)
    check "##" in stripped

  test "string-internal ## is counted as a code line by effectiveSLOC":
    let src = "let x = \"## not comment\""
    let lines = src.splitLines()
    check countEffectiveSLOC(lines, 1, lines.len) == 1

suite "effectiveSLOC invariant - block comment removal with nesting":
  test "nested block comments are removed from effectiveSLOC count":
    let code = "proc f() =\n  #[ #[ nested ]# ]#\n  result = 1"
    let lines = code.splitLines()
    let sloc = countEffectiveSLOC(lines, 1, lines.len)
    check sloc == 1

  test "block comment lines are not counted":
    let code = "proc f() =\n  #[ this is a block comment ]#\n  result = 1"
    let lines = code.splitLines()
    let sloc = countEffectiveSLOC(lines, 1, lines.len)
    check sloc == 1