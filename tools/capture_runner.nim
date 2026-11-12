import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}

## capture_runner.nim — Deterministic I/O Trace Capture Runner
##
## Phase B of Single-Leaf Twin Bootstrapping (Issue B).
## Captures stdout/stderr of a target module's `when isMainModule` block,
## normalizes the trace, and writes a deterministic recording.
##
## Context7-verified: Nim startProcess + outputStream for subprocess stdout
## capture (Nim stdlib osproc.nim).  AGENTS.md §0.6a: startProcess with
## bounded concurrency for external programs.
##
## Usage:
##   nim c -r tools/capture_runner.nim \
##       --module=core/trace_normalizer \
##       --out=tests/recordings/trace_normalizer.json

import shared_types/analysis_bridge
import std/[os, osproc, streams, strutils, json]

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Compiler output filtering
# ---------------------------------------------------------------------------

proc filterCompilerOutput(raw: string): string {.raises: [].} =
  ## Remove non-deterministic compiler output (CC lines, timing, memory stats)
  ## so that re-runs produce identical traces.
  var filtered: seq[string]
  for line in raw.splitLines():
    let stripped = line.strip()
    if stripped.startsWith("CC: "):
      continue
    if " lines; " in stripped and "s; " in stripped and "MiB peakmem" in stripped:
      filtered.add("{{COMPILER_STATS}}")
      continue
    if stripped.startsWith("Hint: mm: orc;"):
      continue
    filtered.add(line)
  result = filtered.join("\n")

# ---------------------------------------------------------------------------
# Core capture logic (proc — I/O boundary)
# ---------------------------------------------------------------------------

proc captureTrace*(modulePath, outPath: string): bool {.raises: [OSError, IOError, ValueError].} =
  ## Capture stdout of `nim c -r src/core/<modulePath>.nim` for the target module,
  ## normalize the trace, and write JSON recording.
  ## Returns true on success.

  let sourceFile = "src/core/" & modulePath & ".nim"

  # Compile + run directly so that `when isMainModule` block executes.
  let p = startProcess("nim", args = ["c", "-r", sourceFile],
                       options = {poStdErrToStdOut, poUsePath})
  defer: p.close()

  # Capture merged stdout+stderr
  let outputStream = p.outputStream
  var rawOutput = ""
  while not outputStream.atEnd:
    rawOutput.add(outputStream.readLine() & "\n")

  let exitCode = p.waitForExit()
  if exitCode != 0:
    stderr.writeLine("[capture] Warning: process exited with code ", exitCode)

  # Filter non-deterministic compiler noise before normalization
  let filteredOutput = filterCompilerOutput(rawOutput)

  # Normalize trace
  let projectRoot = detectProjectRoot()
  let normalized = normalizeTrace(RawTrace(filteredOutput), projectRoot)

  # Ensure output directory exists
  createDir(parentDir(outPath))

  # Write deterministic recording
  let recording = %* {
    "module": modulePath,
    "trace": $normalized,
    "exitCode": exitCode,
    "capturedAt": "{{TIMESTAMP}}"
  }
  writeFile(outPath, recording.pretty())

  echo "[capture] Wrote recording: ", outPath
  echo "[capture] Exit code: ", exitCode
  echo "[capture] Trace length: ", ($normalized).len, " chars"
  result = true

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

proc main() {.raises: [OSError, IOError, ValueError].} =
  var modulePath = ""
  var outPath = ""

  for i in 1..paramCount():
    let arg = paramStr(i)
    if arg.startsWith("--module="):
      modulePath = arg[9..^1]
    elif arg.startsWith("--out="):
      outPath = arg[6..^1]

  if modulePath.len == 0 or outPath.len == 0:
    echo "Usage: capture_runner --module=<module_path> --out=<output.json>"
    echo "  module_path: relative to src/core/ (e.g., trace/trace_normalizer)"
    quit(1)

  discard captureTrace(modulePath, outPath)

when isMainModule:
  main()
