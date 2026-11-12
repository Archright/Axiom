import gate/daemon/content_hash
import std/strutils

func countEffectiveSLOC*(lines: seq[string]; startLine, endLine: int): int =
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