## tools/pbt_seed_parser.nim — PBT Seed Parser (Pure Nim, zero Python dependency).
##
## Parses structured [PBT-SEED] and [PBT-FAILED] output from stdin,
## extracts seed/test/status tuples, writes JSON log to data/pbt_seed_log.json,
## and prints a summary to stderr.
##
## Port of: tools/ci/pbt_seed_parser.py
##
## Exit codes:
##   0 — all seeds succeeded
##   1 — at least one failure detected
##
## Usage:
##   ./bin/my_pbt_test --seed:12345 | nim c -r tools/pbt_seed_parser.nim
##   cat test_output.txt | nim c -r tools/pbt_seed_parser.nim
##   nim c -r tools/pbt_seed_parser.nim --input test_output.txt

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, json, re, times, tables, algorithm]

const
  DefaultOutputPath = "data/pbt_seed_log.json"

  SeedPattern = r"\[PBT-SEED\]\s+seed=(\d+)\s+test=(\S+)"
  FailPattern = r"\[PBT-FAILED\]\s+seed=(\d+)\s+test=(\S+)"

type
  RunInfo = object
    seed: int
    test: string
    status: string  ## "ok" or "failed"

  CliOptions = object
    inputFile: string   ## If set, read from file instead of stdin
    outputPath: string  ## Output JSON path
    verbose: bool

proc parseCli(): CliOptions =
  result = CliOptions(
    inputFile: "",
    outputPath: DefaultOutputPath,
    verbose: false,
  )

  var i = 1
  while i <= paramCount():
    let arg = paramStr(i)
    case arg
    of "--input", "-i":
      inc i
      if i <= paramCount(): result.inputFile = paramStr(i)
    of "--output", "-o":
      inc i
      if i <= paramCount(): result.outputPath = paramStr(i)
    of "--verbose", "-v":
      result.verbose = true
    of "--help", "-h":
      echo "Usage: pbt_seed_parser [OPTIONS]"
      echo ""
      echo "Parse [PBT-SEED] and [PBT-FAILED] output and write JSON log."
      echo ""
      echo "Options:"
      echo "  --input, -i FILE   Read from file instead of stdin"
      echo "  --output, -o FILE  Output JSON path (default: data/pbt_seed_log.json)"
      echo "  --verbose, -v      Print each parsed line"
      echo "  --help, -h         Show this help"
      quit(0)
    else:
      stderr.writeLine("Unknown option: ", arg, " (use --help for usage)")
      quit(1)
    inc i

proc parseLines(lines: seq[string]): TableRef[string, RunInfo] =
  ## Parse lines for [PBT-SEED] and [PBT-FAILED] patterns.
  result = newTable[string, RunInfo]()

  let seedRe = re(SeedPattern)
  let failRe = re(FailPattern)

  for line in lines:
    var matches: array[2, string]
    if line.find(seedRe, matches) >= 0:
      let seedStr = matches[0]
      let test = matches[1]
      if seedStr notin result:
        result[seedStr] = RunInfo(
          seed: parseInt(seedStr),
          test: test,
          status: "ok",
        )
      continue

    if line.find(failRe, matches) >= 0:
      let seedStr = matches[0]
      let test = matches[1]
      result[seedStr] = RunInfo(
        seed: parseInt(seedStr),
        test: test,
        status: "failed",
      )

proc main() =
  let opts = parseCli()

  # Read input lines
  var lines: seq[string]
  if opts.inputFile.len > 0:
    if not fileExists(opts.inputFile):
      stderr.writeLine("Error: input file not found: ", opts.inputFile)
      quit(1)
    for line in readFile(opts.inputFile).splitLines():
      if line.len > 0:
        lines.add(line)
  else:
    # Read from stdin
    while not endOfFile(stdin):
      let line = readLine(stdin)
      lines.add(line)

  if opts.verbose:
    stderr.writeLine("Read ", lines.len, " lines from input")

  # Parse
  let runs = parseLines(lines)

  # Collect failed seeds
  var failedSeeds: seq[int]
  for key, run in runs:
    if run.status == "failed":
      failedSeeds.add(run.seed)
  failedSeeds.sort()

  # Build JSON output
  let timestamp = now().utc().format("yyyy-MM-dd'T'HH:mm:ss'Z'")

  var runsArray = newJArray()
  for key, run in runs:
    let runObj = %*{
      "seed": run.seed,
      "test": run.test,
      "status": run.status,
    }
    runsArray.add(runObj)

  var failedArray = newJArray()
  for s in failedSeeds:
    failedArray.add(%($s))

  let output = %*{
    "timestamp": timestamp,
    "runs": runsArray,
    "failed_seeds": failedArray,
  }

  # Write JSON log
  let outputDir = opts.outputPath.parentDir()
  if outputDir.len > 0 and not dirExists(outputDir):
    createDir(outputDir)
  writeFile(opts.outputPath, pretty(output) & "\n")

  # Summary to stderr
  let total = runs.len
  let failed = failedSeeds.len
  let passed = total - failed
  stderr.writeLine("PBT Seed Log: ", total, " runs, ", passed, " passed, ",
                    failed, " failed")
  if failedSeeds.len > 0:
    stderr.writeLine("Failed seeds: ", failedSeeds.join(", "))
    for s in failedSeeds:
      let sStr = $s
      if sStr in runs:
        stderr.writeLine("  Replay: --seed:", s, " (", runs[sStr].test, ")")

  # Exit code
  if failed > 0:
    quit(1)
  else:
    quit(0)

when isMainModule:
  main()
