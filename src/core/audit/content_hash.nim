{.push raises: [].}
import core/trusted/layer_declaration
axiomLayer "domain"

import std/strutils
import core/crypto/hash_kernel

func normalizePathSeparators*(path: string): string {.raises: [].} =
  path.replace('\\', '/')

func lineStartOffsets*(source: string): seq[int] {.raises: [].} =
  result.add(0)
  var i = 0
  while i < source.len:
    if source[i] == '\n':
      result.add(i + 1)
    inc i

func strippedComment(line: string): string {.raises: [].} =
  var inString = false
  var inChar = false
  var escape = false
  var i = 0
  while i < line.len:
    let c = line[i]
    if escape:
      escape = false
      inc i
      continue
    if c == '\\' and (inString or inChar):
      escape = true
      inc i
      continue
    if c == '"' and not inChar:
      inString = not inString
    elif c == '\'' and not inString:
      inChar = not inChar
    elif c == '/' and i + 1 < line.len and line[i + 1] == '/' and not inString and not inChar:
      return line[0 ..< i]
    inc i
  line

func isWhitespace(c: char): bool {.raises: [].} =
  c == ' ' or c == '\t' or c == '\r' or c == '\n'

func nextWordAfter(line: string; startIdx: int): string {.raises: [].} =
  var i = startIdx
  while i < line.len and isWhitespace(line[i]):
    inc i
  let start = i
  while i < line.len and (line[i].isAlphaNumeric or line[i] in {'_', '.'}):
    inc i
  if start < i:
    result = line[start ..< i]

func isProcKeyword(line: string; idx: int): bool {.raises: [].} =
  idx + 4 <= line.len and line[idx ..< idx + 4] == "proc"

func procName(line: string): string {.raises: [].} =
  var i = 0
  while i < line.len:
    if isProcKeyword(line, i):
      return nextWordAfter(line, i + 4)
    inc i
  ""

func findProcLineIndex*(source: string; symbol: string): int {.raises: [].} =
  let offsets = lineStartOffsets(source)
  for lineIdx in 0 ..< offsets.len:
    let lineStart = offsets[lineIdx]
    let lineEnd = if lineIdx + 1 < offsets.len: offsets[lineIdx + 1] else: source.len
    let line = source[lineStart ..< lineEnd].strip()
    let text = strippedComment(line).strip()
    if text.startsWith("proc "):
      let name = procName(text)
      if name == symbol:
        return lineIdx
  -1

func findNextProcLineIndex*(source: string; startLineIndex: int): int {.raises: [].} =
  let offsets = lineStartOffsets(source)
  for lineIdx in startLineIndex + 1 ..< offsets.len:
    let lineStart = offsets[lineIdx]
    let lineEnd = if lineIdx + 1 < offsets.len: offsets[lineIdx + 1] else: source.len
    let line = source[lineStart ..< lineEnd].strip()
    let text = strippedComment(line).strip()
    if text.startsWith("proc "):
      return lineIdx
  offsets.len

func extractProcText*(source: string; symbol: string): string {.raises: [].} =
  let startLine = findProcLineIndex(source, symbol)
  if startLine < 0:
    return ""
  let offsets = lineStartOffsets(source)
  let startOffset = offsets[startLine]
  let endLine = findNextProcLineIndex(source, startLine)
  let endOffset = if endLine < offsets.len: offsets[endLine] else: source.len
  result = source[startOffset ..< endOffset].strip()

proc computeProcHash*(file: string; symbol: string): string =
  try:
    let source = readFile(file)
    let procText = extractProcText(source, symbol)
    result = "sha256:" & hash_kernel.sha256Hex(procText)
  except CatchableError:
    result = "sha256:"
