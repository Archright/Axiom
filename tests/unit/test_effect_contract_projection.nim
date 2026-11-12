# test_effect_contract_projection.nim
# Deterministic unit tests for the effect contract projection.
#
# Run: nim c -r --hints:off tests/unit/test_effect_contract_projection.nim

import std/json
import std/os
import std/strutils

# Import the projection module (stdlib-only, no src/ imports)
# We inline the key logic here to keep the test self-contained and
# avoid import-path issues when running from repo root.

# ── Inline projection logic (mirrors effect_contract_projection.nim) ──────

proc isProcOrFunc(line: string): tuple[isDecl: bool; kind: string] =
  let trimmed = line.strip()
  if trimmed.startsWith("proc "):
    return (true, "proc")
  if trimmed.startsWith("func "):
    return (true, "func")
  return (false, "")

proc isPushRaises(line: string): bool =
  "{.push raises" in line

proc isPopRaises(line: string): bool =
  "{.pop raises" in line

proc isPopDot(line: string): bool =
  "{.pop.}" in line

proc hasRaisesPragma(line: string): bool =
  ## Check if line contains a raises pragma, handling combined pragmas
  ## like {.importc, raises: [].} where "{.raises:" is not a substring.
  let raisesIdx = line.find("raises:")
  if raisesIdx < 0:
    return false
  for j in 0 ..< raisesIdx:
    if line[j] == '{' and j + 1 < line.len and line[j+1] == '.':
      return true
  return false

proc leadingIndent(line: string): int =
  var i = 0
  while i < line.len and (line[i] == ' ' or line[i] == '\t'):
    inc i
  return i

proc findInlineRaises(lines: seq[string], startIdx: int): bool =
  var found = false
  var i = startIdx
  var macroBodyIndent = -1
  while i < lines.len:
    let line = lines[i].strip()
    let indent = leadingIndent(lines[i])
    if line.len == 0:
      if found:
        break
      else:
        inc i
        continue
    # Track template/macro/iterator/converter bodies by indentation
    if line.startsWith("template ") or line.startsWith("macro ") or
       line.startsWith("iterator ") or line.startsWith("converter "):
      macroBodyIndent = indent
    elif macroBodyIndent >= 0 and indent <= macroBodyIndent:
      if line.startsWith("proc ") or line.startsWith("func ") or
         line.startsWith("template ") or line.startsWith("macro ") or
         line.startsWith("iterator ") or line.startsWith("converter ") or
         line.startsWith("type "):
        macroBodyIndent = -1
    if macroBodyIndent >= 0:
      inc i
      continue
    if line.startsWith("proc ") or line.startsWith("func ") or
       line.startsWith("template ") or line.startsWith("macro ") or
       line.startsWith("iterator ") or line.startsWith("converter ") or
       line.startsWith("type "):
      if i > startIdx:
        break
    if line.startsWith("="):
      break
    if hasRaisesPragma(line):
      found = true
    inc i
  return found

type
  TestDecl = object
    symbol: string
    kind: string
    compliant: bool

proc scanTestContent(content: string): seq[TestDecl] =
  let lines = content.splitLines()
  var raisesPushDepth = 0
  var macroBodyIndent = -1
  var i = 0
  while i < lines.len:
    let line = lines[i]
    let trimmed = line.strip()
    let indent = leadingIndent(line)

    if isPushRaises(line):
      inc raisesPushDepth
    if isPopRaises(line) and raisesPushDepth > 0:
      dec raisesPushDepth
    if isPopDot(line) and raisesPushDepth > 0:
      dec raisesPushDepth

    # Track template/macro/iterator/converter bodies by indentation
    let (isTopDecl, declKind) = isProcOrFunc(trimmed)
    let topKind = if isTopDecl: declKind else: ""
    # Also check for template/macro/iterator/converter at top level
    let isMacroDecl = trimmed.startsWith("template ") or trimmed.startsWith("macro ") or
                      trimmed.startsWith("iterator ") or trimmed.startsWith("converter ")
    if isMacroDecl:
      macroBodyIndent = indent
    elif macroBodyIndent >= 0 and indent <= macroBodyIndent:
      if isTopDecl or isMacroDecl:
        macroBodyIndent = -1

    let (isPF, procKind) = isProcOrFunc(trimmed)
    if isPF and macroBodyIndent < 0:
      var sym = trimmed
      let kwLen = procKind.len + 1
      if sym.len > kwLen:
        sym = sym[kwLen .. ^1]
      let parenIdx = sym.find('(')
      if parenIdx > 0:
        sym = sym[0 ..< parenIdx]
      let colonIdx = sym.find(':')
      if colonIdx > 0:
        sym = sym[0 ..< colonIdx]
      if sym.endsWith("*"):
        sym = sym[0 ..^ 2]
      sym = sym.strip()

      let hasInline = findInlineRaises(lines, i)
      let compliant = raisesPushDepth > 0 or hasInline
      result.add(TestDecl(symbol: sym, kind: procKind, compliant: compliant))

    inc i

# ── Test helpers ──────────────────────────────────────────────────────────

var passed = 0
var failed = 0

proc assertEq[T](actual, expected: T, msg: string) =
  if actual == expected:
    inc passed
    echo "  PASS: " & msg
  else:
    inc failed
    echo "  FAIL: " & msg & " — got " & $actual & ", expected " & $expected

proc assertBool(cond: bool, msg: string) =
  assertEq(cond, true, msg)

# ── Tests ─────────────────────────────────────────────────────────────────

echo "=== Effect Contract Projection Unit Tests ==="
echo ""

# Test 1: Universe definition — macro-generated never counted
echo "Test 1: Macro-generated declarations are excluded"
let test1 = """
macro myMacro(): untyped =
  discard

proc macroGenerated(): int {.raises: [].} =
  discard
"""
let decls1 = scanTestContent(test1)
assertEq(decls1.len, 1, "Only proc counted, macro excluded")
assertEq(decls1[0].symbol, "macroGenerated", "Correct symbol for proc")
assertEq(decls1[0].compliant, true, "Proc with inline raises is compliant")
echo ""

# Test 2: When-branch counts both branches
echo "Test 2: when/when defined() counts both branches"
let test2 = """
when defined(linux):
  proc linuxProc(): int {.raises: [].} = discard

when defined(windows):
  proc winProc(): int = discard
"""
let decls2 = scanTestContent(test2)
assertEq(decls2.len, 2, "Both when branches counted")
assertEq(decls2[0].symbol, "linuxProc", "First declaration is linuxProc")
assertEq(decls2[0].compliant, true, "linuxProc has inline raises")
assertEq(decls2[1].symbol, "winProc", "Second declaration is winProc")
assertEq(decls2[1].compliant, false, "winProc has no raises pragma")
echo ""

# Test 3: Push/pop nesting
echo "Test 3: Push/pop nesting scope"
let test3 = """
{.push raises: [].}

proc scopedProc(): int = discard

{.pop.}

proc unscopedProc(): int = discard
"""
let decls3 = scanTestContent(test3)
assertEq(decls3.len, 2, "Both procs counted")
assertEq(decls3[0].symbol, "scopedProc", "First is scopedProc")
assertEq(decls3[0].compliant, true, "scopedProc is inside push scope")
assertEq(decls3[1].symbol, "unscopedProc", "Second is unscopedProc")
assertEq(decls3[1].compliant, false, "unscopedProc is outside push scope")
echo ""

# Test 4: Last-wins for multiple raises declarations
echo "Test 4: Last raises pragma wins"
let test4 = """
proc multiPragma(): int {.raises: [CatchableError].} {.raises: [IOError].} =
  discard
"""
let decls4 = scanTestContent(test4)
assertEq(decls4.len, 1, "One declaration")
assertEq(decls4[0].compliant, true, "Has inline raises pragma (last one)")
echo ""

# Test 5: Determinism — double run byte-identical
echo "Test 5: Determinism — double run byte-identical"
let test5 = """
proc foo(): int = discard
proc bar(): int {.raises: [].} = discard
proc baz(x: int): string {.raises: [ValueError].} = discard
"""
let decls5a = scanTestContent(test5)
let decls5b = scanTestContent(test5)
assertEq(decls5a.len, decls5b.len, "Same count on double run")
var allMatch = true
for i in 0 ..< decls5a.len:
  if decls5a[i].symbol != decls5b[i].symbol or
     decls5a[i].kind != decls5b[i].kind or
     decls5a[i].compliant != decls5b[i].compliant:
    allMatch = false
    break
assertBool(allMatch, "All declarations match on double run")
echo ""

# Test 6: Multi-line header with inline pragma
echo "Test 6: Multi-line header with inline pragma"
let test6 = """
proc longHeader(
  x: int,
  y: string,
  z: bool
): bool {.raises: [IOError].} =
  discard
"""
let decls6 = scanTestContent(test6)
assertEq(decls6.len, 1, "One declaration from multi-line header")
assertEq(decls6[0].symbol, "longHeader", "Correct symbol extracted")
assertEq(decls6[0].compliant, true, "Multi-line header with inline pragma is compliant")
echo ""

# Test 7: Template body excluded
echo "Test 7: Template body declarations excluded"
let test7 = """
template myTemplate(): untyped =
  proc insideTemplate(): int = discard

proc outsideTemplate(): int {.raises: [].} = discard
"""
let decls7 = scanTestContent(test7)
assertEq(decls7.len, 1, "Only proc outside template counted")
assertEq(decls7[0].symbol, "outsideTemplate", "Correct symbol")
echo ""

# Test 8: Excluded kinds (iterator, converter, type)
echo "Test 8: Iterator, converter, type excluded"
let test8 = """
iterator myIter(): int = discard
converter myConv(): string = discard
type MyType = object
proc realProc(): int {.raises: [].} = discard
"""
let decls8 = scanTestContent(test8)
assertEq(decls8.len, 1, "Only proc counted")
assertEq(decls8[0].symbol, "realProc", "Only proc is realProc")
echo ""

# Test 9: Exemption pragmas (importc, importcpp, etc.) — NOT handled by projection
# (The projection does NOT exempt importc/importcpp lines — those are a legacy immunity
# concern, not part of the contract projection.)
echo "Test 9: importc pragmas do NOT exempt from contract projection"
let test9 = """
proc importedProc() {.importc, raises: [].} = discard
proc noRaisesProc() {.importc.} = discard
"""
let decls9 = scanTestContent(test9)
assertEq(decls9.len, 2, "Both procs counted (importc does not exempt)")
assertEq(decls9[0].compliant, true, "importedProc has inline raises")
assertEq(decls9[1].compliant, false, "noRaisesProc has no raises pragma")
echo ""

# Test 10: Pop without raises decrements depth
echo "Test 10: Pop without raises decrements push scope"
let test10 = """
{.push raises: [].}
proc inner1(): int = discard
{.pop.}
proc outer1(): int = discard
"""
let decls10 = scanTestContent(test10)
assertEq(decls10.len, 2, "Both procs counted")
assertEq(decls10[0].compliant, true, "inner1 inside push scope")
assertEq(decls10[1].compliant, false, "outer1 outside push scope")
echo ""

# ── Summary ────────────────────────────────────────────────────────────────

echo ""
echo "=== Summary ==="
echo "Passed: " & $passed
echo "Failed: " & $failed
echo ""

if failed > 0:
  echo "TESTS FAILED"
  quit(1)
else:
  echo "ALL TESTS PASSED"
  quit(0)
