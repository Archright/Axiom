{.push raises: [].}
## theater_linter.nim
##
## Runtime AST scanner for Theater Signature detection (S3/S4/S5).
## `scanTheaterSource` is the production-used detection engine — imported by tests.
##
## `lintTheaterPatterns` is a compile-time macro library utility intended for
## module-level opt-in use. It is NOT wired into config.nims or any production
## build path (DEBT#396 tracks wiring). Tests import it directly to verify
## macro behavior. Do not remove; DEBT#396 resolution will determine final fate.

import core/trusted/layer_declaration
axiomLayer "domain"

import std/[macros, os, strutils]

type
  TheaterPattern* = enum
    tpSwallowedFailure
    tpHardcodedTrueReturn
    tpAlwaysTrueCondition
    tpEmptyExceptBlock

  TheaterFinding* = object
    pattern*: TheaterPattern
    path*: string
    line*: int
    symbol*: string
    message*: string

const TheaterPatternNames* = [
  "swallowed-failure",
  "hardcoded-true-return",
  "always-true-condition",
  "empty-except-block"
]

func normalize*(value: string): string =
  value.toLowerAscii

func isVerificationProcName*(name: string): bool =
  let normalized = name.toLowerAscii
  normalized.contains("verify") or normalized.contains("check")

func stripLineComment*(line: string): string =
  var inString = false
  var inChar = false
  for i, ch in line:
    if inString:
      if ch == '"':
        if i + 2 < line.len and line[i + 1] == '"' and line[i + 2] == '"':
          continue
        inString = false
    elif inChar:
      if ch == '\'':
        inChar = false
    else:
      if ch == '"':
        inString = true
      elif ch == '\'':
        inChar = true
      elif ch == '#':
        return line[0 ..< i].strip
  line.strip

func extractProcName*(header: string): string =
  let trimmed = header.strip
  let prefixLen =
    if trimmed.startsWith("proc "): 5
    elif trimmed.startsWith("func "): 5
    else: -1
  if prefixLen < 0:
    return ""

  var rest = trimmed[prefixLen .. ^1]
  let openIdx = rest.find("(")
  if openIdx >= 0:
    result = rest[0 ..< openIdx].strip
  else:
    let colonIdx = rest.find(":")
    if colonIdx >= 0:
      result = rest[0 ..< colonIdx].strip
    else:
      result = rest.strip
  if result.endsWith("="):
    result = result[0 ..< result.len - 1].strip
  result = result.strip()

func isExceptCatchableLine*(line: string): bool =
  let trimmed = line.strip.toLowerAscii
  trimmed.startsWith("except catchableerror") and trimmed.contains(":")

func exceptBodyAfterColon(line: string): string =
  let idx = line.find(":")
  if idx < 0 or idx + 1 >= line.len:
    return ""
  line[idx + 1 .. ^1].strip

func isExceptBlockBoundary*(line: string): bool =
  let trimmed = line.strip.toLowerAscii
  trimmed.startsWith("except ") or
  trimmed.startsWith("except:") or
  trimmed.startsWith("else ") or
  trimmed.startsWith("else:") or
  trimmed.startsWith("else") or
  trimmed.startsWith("finally ") or
  trimmed.startsWith("finally:") or
  trimmed.startsWith("finally")

func isExceptBlockEmpty*(lines: openArray[string]; startIndex: int): bool =
  var j = startIndex
  var sawBody = false
  while j < lines.len:
    let bodyLine = stripLineComment(lines[j]).strip
    if bodyLine.len == 0:
      inc j
      continue
    if isExceptBlockBoundary(bodyLine):
      return sawBody
    sawBody = true
    inc j
  false

func addTheaterFinding*(findings: var seq[TheaterFinding]; path: string; line: int; pattern: TheaterPattern; symbol: string; message: string) =
  findings.add(TheaterFinding(
    pattern: pattern,
    path: path,
    line: line,
    symbol: symbol,
    message: message
  ))

func scanTheaterSource*(source: string; path: string = ""): seq[TheaterFinding] =
  let lines = source.splitLines()
  var findings: seq[TheaterFinding] = @[]
  var currentProcName = ""
  var inProcHeader = false

  var i = 0
  while i < lines.len:
    let rawLine = lines[i]
    let line = stripLineComment(rawLine)
    let trimmed = line.strip

    if isExceptCatchableLine(line):
      let afterColon = exceptBodyAfterColon(line)
      if afterColon == "discard":
        addTheaterFinding(findings, path, i + 1, tpSwallowedFailure, currentProcName, "swallowed CatchableError failure: discard in except CatchableError handler")
      elif afterColon.len == 0 and i + 1 < lines.len:
        let firstBody = stripLineComment(lines[i + 1]).strip
        if firstBody == "discard":
          addTheaterFinding(findings, path, i + 1, tpSwallowedFailure, currentProcName, "swallowed CatchableError failure: discard in except CatchableError handler")
        elif isExceptBlockEmpty(lines, i + 1):
          addTheaterFinding(findings, path, i + 1, tpEmptyExceptBlock, currentProcName, "empty except CatchableError block")
      inc i
      continue

    if trimmed.startsWith("except") and trimmed.endsWith(":"):
      if isExceptBlockEmpty(lines, i + 1):
        addTheaterFinding(findings, path, i + 1, tpEmptyExceptBlock, currentProcName, "empty except block")
      inc i
      continue

    if trimmed == "return true" and (currentProcName.contains("verify") or currentProcName.contains("check")):
      addTheaterFinding(findings, path, i + 1, tpHardcodedTrueReturn, currentProcName, "hardcoded true return in verification procedure")

    if trimmed.startsWith("if true:") or trimmed.startsWith("when true:"):
      addTheaterFinding(findings, path, i + 1, tpAlwaysTrueCondition, currentProcName, "always-true condition: use runtime logic instead of true")

    if (trimmed.startsWith("proc ") or trimmed.startsWith("func ")) and not trimmed.startsWith("proc("):
      currentProcName = extractProcName(trimmed)
      inProcHeader = true
    elif inProcHeader and currentProcName.len > 0:
      if trimmed.len > 0 and trimmed.contains("="):
        inProcHeader = false

    inc i

  findings

## DEBT#396: NOT wired into production builds (config.nims). Opt-in library utility only.
macro lintTheaterPatterns*(sourcePath: static string): untyped =
  let resolvedPath = if sourcePath.startsWith("/"): sourcePath else: currentSourcePath().parentDir() / sourcePath
  let source = staticRead(resolvedPath)
  let findings = scanTheaterSource(source, sourcePath)
  for finding in findings:
    warning(finding.message, nil)
  result = newEmptyNode()
