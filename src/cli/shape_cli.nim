import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}

## Shape CLI — Goal shape coverage analysis from JSONL logs.
##
## Replaces tools/analyze_goal_shapes.sh with integer-only frequency analysis.
## Walks logs/ for .jsonl files, extracts "shape" field, computes frequency
## distribution and percentage coverage using integer arithmetic only.
##
## Usage:
##   ax shape analyze [--dry-run] [--threshold N]
##
## Exit codes:
##   0 — analysis complete (or dry-run)
##   1 — no shape data found, parse error, or unknown subcommand

import core/axiom_pragmas
import std/[algorithm, json, os, strutils, tables]
import core/parsers/safe_parsers
import core/results
import infrastructure/logging_facade

# ---------------------------------------------------------------------------
# Core analysis
# ---------------------------------------------------------------------------

proc analyzeGoalShapes*(threshold: int, dryRun: bool): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Analyze goal shape coverage from JSONL logs.
  ## Integer-only frequency analysis: (count * 100) div total
  let root = getCurrentDir()
  let logsDir = root / "logs"
  if not dirExists(logsDir):
    logInfo("shape_cli", "ax shape: logs/ not found")
    return 1

  var shapeCounts = initTable[string, int]()
  var total = 0

  # Walk logs/ for .jsonl files
  for path in walkDirRec(logsDir):
    if not path.endsWith(".jsonl"):
      continue
    try:
      let content = readFile(path)
      for line in content.splitLines():
        if line.len == 0:
          continue
        try:
          let j = parseJson(line)
          if j.hasKey("shape"):
            let shape = j["shape"].getStr()
            if shape notin shapeCounts:
              shapeCounts[shape] = 0
            inc shapeCounts[shape]
            inc total
        except JsonParsingError:
          continue
    except IOError:
      continue

  if total == 0:
    echo "ax shape: no shape data found in logs"
    return 0

  # Sort by frequency descending
  var entries: seq[(string, int)]
  for shape, count in shapeCounts:
    entries.add((shape, count))
  entries.sort(proc (a, b: (string, int)): int = b[1] - a[1])

  if dryRun:
    echo "ax shape: dry-run — would report " & $entries.len & " shapes from " & $total & " entries"
    return 0

  # Output as JSONL
  echo "{\"total\": " & $total & ", \"threshold\": " & $threshold & "}"
  for entry in entries:
    # Integer-only percentage: (count * 100) div total
    let pct = if total > 0: (entry[1] * 100) div total else: 0
    let status = if pct >= threshold: "OK" else: "BELOW"
    echo "{\"shape\": \"" & entry[0] & "\", \"count\": " & $entry[1] &
         ", \"pct\": " & $pct & ", \"status\": \"" & status & "\"}"

  return 0

# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

proc run*(args: seq[string]) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var dryRun = false
  var subcommand = ""
  var threshold = 10  # Default 10%
  var i = 0
  while i < args.len:
    if args[i] == "--dry-run":
      dryRun = true
    elif args[i] == "--threshold" and i + 1 < args.len:
      let thresholdRes = safeParseInt(args[i + 1])
      if thresholdRes.isErr:
        logInfo("shape_cli", "ax shape: invalid threshold value")
        quit(1)
      threshold = thresholdRes.get
      inc i
    elif args[i] == "analyze":
      subcommand = "analyze"
    inc i

  case subcommand
  of "analyze":
    quit(analyzeGoalShapes(threshold, dryRun))
  else:
    logInfo("shape_cli", "ax shape: unknown subcommand '" & subcommand & "'")
    logInfo("shape_cli", "usage: ax shape analyze [--dry-run] [--threshold N]")
    quit(1)

{.pop.}
