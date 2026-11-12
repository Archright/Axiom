## Synthetic child fixture for output-capture deadlock tests.
##
## Emits output patterns designed to trip a `readLine`-based drain (which
## blocks until LF on a partial line) while a byte-oriented drain must
## complete. Invoked as: <bin> <mode>
##   interleave — 4096 rounds of 256B stdout + 256B stderr, alternating.
##   partial    — partial chunks (no newline) with short sleeps; never emits LF.
##   bigchunk   — a single 64KB chunk (OS pipe buffer boundary).
##
## All modes flush after every write so the pipe is never starved of data.

import std/os
import std/strutils

proc emitInterleave() =
  for i in 0 ..< 4096:
    stdout.write("A" & $i & ":" & repeat("x", 256))
    stdout.flushFile()
    stderr.write("B" & $i & ":" & repeat("y", 256))
    stderr.flushFile()

proc emitPartial() =
  for i in 0 ..< 200:
    stdout.write("partial-" & $i & "-")
    stdout.flushFile()
    sleep(10)
  stdout.write("done-no-newline")
  stdout.flushFile()

proc emitBigChunk() =
  stdout.write(repeat("z", 64 * 1024))
  stdout.flushFile()

let mode = if paramCount() >= 1: paramStr(1) else: "interleave"
case mode
of "interleave":
  emitInterleave()
of "partial":
  emitPartial()
of "bigchunk":
  emitBigChunk()
else:
  stderr.writeLine("unknown mode: " & mode)
  quit(2)
