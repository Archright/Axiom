## Batch Nim Check — Parallel `nim check` for merged .nim files.
##
## Accepts file paths as command-line arguments, runs ``nim check`` on each
## in parallel via malebolgia, reports ALL failures, exits 0 on success / 1 on failure.
## Designed for the post-merge hook to replace the sequential per-file loop.

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, osproc, strutils, times]
import malebolgia

# ============================================================================
# Types
# ============================================================================

type
  CheckResult = object
    filePath: string
    passed: bool
    output: string

# ============================================================================
# Worker (malebolgia spawn target — gcsafe, value-type args)
# ============================================================================

proc runCheck(filePath: string): CheckResult {.gcsafe.} =
  ## Run ``nim check`` on a single file. Returns result with pass/fail status.
  ## Catches all exceptions so one file never kills the batch.
  result.filePath = filePath
  result.passed = true
  result.output = ""

  if not fileExists(filePath):
    result.passed = false
    result.output = "File not found: " & filePath
    return

  try:
    let (output, exitCode) = execCmdEx(
      "nim check --hints:off --warnings:off " & quoteShell(filePath)
    )
    if exitCode != 0:
      result.passed = false
      result.output = output.strip()
  except CatchableError as e:
    result.passed = false
    result.output = "Exception: " & e.msg

# ============================================================================
# Main
# ============================================================================

proc main() =
  let args = commandLineParams()

  if args.len == 0:
    stderr.write "Usage: batch_nim_check <file1.nim> [file2.nim ...]\n"
    quit(1)

  # Collect valid .nim files that actually exist on disk
  var files: seq[string]
  for arg in args:
    if arg.endsWith(".nim") and fileExists(arg):
      files.add(arg)

  if files.len == 0:
    echo "No valid .nim files to check."
    quit(0)

  let total = files.len
  let maxJobs = max(1, osproc.countProcessors())
  stderr.write "⚡ Checking " & $total & " file(s) with " & $maxJobs & " workers...\n"

  # --- Parallel execution via malebolgia ---
  var results = newSeq[CheckResult](total)

  block parallelChecks:
    var master = createMaster(initDuration(seconds = 60))
    master.awaitAll:
      for i in 0 ..< total:
        master.spawn runCheck(files[i]) -> results[i]

  # --- Collect failures ---
  var failures: seq[CheckResult]
  for r in results:
    if not r.passed:
      failures.add(r)

  # --- Report ---
  if failures.len > 0:
    for f in failures:
      stderr.write "❌ COMPILE FAIL: " & f.filePath & "\n"
      if f.output.len > 0:
        for line in f.output.splitLines():
          if line.len > 0:
            stderr.write "   " & line & "\n"
    stderr.write "\n❌ " & $failures.len & " of " & $total &
                 " file(s) failed compilation.\n"
    quit(1)
  else:
    stderr.write "✅ All " & $total & " file(s) compile clean.\n"
    quit(0)

when isMainModule:
  main()
