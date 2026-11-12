## tcb_cast_audit.nim — Detects unauthorized {.cast(noSideEffect).} usage.
##
## GUARDIAN §-1 rule: Only src/core/pure/ may use {.cast(noSideEffect).}.
## This tool scans the entire codebase and FAILs if any other location
## contains the cast pragma.
##
## Part of nimtry gate suite. Run: nim c -r tools/nimtry/tcb_cast_audit.nim

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils]

const
  allowedDir = "src/core/pure/"
  forbiddenPragma = "{.cast(noSideEffect).}"

var violations: seq[string] = @[]

for nimFile in walkDirRec("src/"):
  if not nimFile.endsWith(".nim"): continue
  if nimFile.startsWith(allowedDir): continue

  let content = readFile(nimFile)
  for lineNum, line in content.splitLines().pairs():
    if line.contains("cast(noSideEffect)") or line.contains("{.cast(noSideEffect).}"):
      violations.add(nimFile & ":" & $(lineNum + 1) & ": " & line.strip())

if violations.len > 0:
  echo "FAIL: Unauthorized {.cast(noSideEffect).} usage detected:"
  echo ""
  for v in violations:
    echo "  " & v
  echo ""
  echo "Only " & allowedDir & " may use {.cast(noSideEffect).}."
  echo "See: src/core/pure/README.md for TCB policy."
  quit(1)
else:
  echo "PASS: No unauthorized {.cast(noSideEffect).} usage found."
  quit(0)
