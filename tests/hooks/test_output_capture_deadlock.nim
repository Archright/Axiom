import core/trusted/layer_declaration
axiomLayer "tests"
{.push raises: [CatchableError].}

## test_output_capture_deadlock.nim — deadlock-safety of runBatch captureOutput
##
## Verifies the byte-oriented drain (poll + posix.read) added to
## runner_process_pool.runGateInProcess never blocks on a partial line.
##
## A `readLine`-based drain deadlocks when a child emits a partial line
## (no LF) and pauses: Stream.readLine reads char-by-char up to LF, so it
## blocks inside read() even though the pipe momentarily has data. The
## byte-drain consumes only available bytes and never awaits LF.
##
## Scenarios (Pattern A: poStdErrToStdOut, single merged stream):
##   (a) interleave   — 4096 × (256B stdout + 256B stderr), flushing each.
##   (b) partial      — 200 × partial chunk (no newline) + sleep; the exact
##                      shape that deadlocks readLine drains.
##   (c) bigchunk     — single 64KB write (OS pipe buffer boundary).
##
## Run:  AXIOM_HERMETIC_BUILDING=1 nim c -r tests/hooks/test_output_capture_deadlock.nim
##
## Exit 0 = all scenarios drained fully without deadlock.

import std/os
import std/osproc
import std/strutils
import std/times
import gate/runners/runner_process_pool

const
  FixtureSrc = "tests" / "hooks" / "fixtures" / "output_interleave_child.nim"
  FixtureBin = "tests" / "hooks" / "fixtures" / "output_interleave_child"
  OverallDeadlineSecs = 30  ## Any scenario exceeding this = deadlock.

proc buildChild(): string =
  let (outp, code) = execCmdEx(
    "nim c --hints:off -o:" & FixtureBin & " " & FixtureSrc)
  if code != 0:
    stderr.writeLine("FAILED to build child fixture:\n" & outp)
    quit(1)
  result = FixtureBin

proc runCaptured(mode: string; timeoutMs: int):
    tuple[ok: bool, captured: string, exitCode: int] =
  let spec = cmdSpec(FixtureBin, @[mode], timeoutMs = timeoutMs,
                     captureOutput = true, file = mode)
  let results = runBatch(@[spec], getCurrentDir(), 1)
  result = (ok: results[0].exitCode == 0,
            captured: results[0].stdout,
            exitCode: results[0].exitCode)

var failures = 0

proc check(name: string; cond: bool; detail: string) =
  if cond:
    echo "[PASS] " & name
  else:
    echo "[FAIL] " & name & " — " & detail
    inc failures

let child = buildChild()

block scenarioInterleave:
  let start = getTime()
  let (ok, cap, code) = runCaptured("interleave", 30_000)
  let ms = (getTime() - start).inMilliseconds
  check("interleave completes < " & $OverallDeadlineSecs & "s",
        ms < OverallDeadlineSecs * 1000, "took " & $ms & "ms")
  check("interleave exit 0", ok, "exit=" & $code)
  check("interleave tail preserved (last stdout marker)",
        cap.contains("A4095:"), "cap.len=" & $cap.len)
  check("interleave tail preserved (last stderr marker, merged)",
        cap.contains("B4095:"), "cap.len=" & $cap.len)
  check("interleave volume > 1MB", cap.len > 1_000_000,
        "cap.len=" & $cap.len)

block scenarioPartial:
  let start = getTime()
  let (ok, cap, code) = runCaptured("partial", 30_000)
  let ms = (getTime() - start).inMilliseconds
  check("partial completes < " & $OverallDeadlineSecs & "s (readLine would deadlock here)",
        ms < OverallDeadlineSecs * 1000, "took " & $ms & "ms")
  check("partial exit 0", ok, "exit=" & $code)
  check("partial final marker captured despite no newline",
        cap.endsWith("done-no-newline"), "cap tail='" &
        cap[min(cap.len, 120) .. ^1] & "'")

block scenarioBigChunk:
  let start = getTime()
  let (ok, cap, code) = runCaptured("bigchunk", 30_000)
  let ms = (getTime() - start).inMilliseconds
  check("bigchunk completes < " & $OverallDeadlineSecs & "s",
        ms < OverallDeadlineSecs * 1000, "took " & $ms & "ms")
  check("bigchunk exit 0", ok, "exit=" & $code)
  check("bigchunk captures full 64KB", cap.len == 64 * 1024,
        "cap.len=" & $cap.len)

if failures == 0:
  echo "ALL DEADLOCK-SAFETY OK"
  quit(0)
else:
  echo $failures & " deadlock-safety check(s) failed"
  quit(1)

{.pop.}
