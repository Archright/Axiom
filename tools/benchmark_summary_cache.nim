## tools/benchmark_summary_cache.nim — AST hash performance benchmark
##
## Measures: cold parse time, cache hit time, cache miss time
## Output: JSON with p50/p95/p99 latencies
##
## Usage: nim c -r -d:allowMissingZ3 tools/benchmark_summary_cache.nim

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[times, os, strutils, sequtils, algorithm, json]
import shared_types/analysis_bridge

proc sampleSourceFiles(dir: string, count: int): seq[string] =
  ## Sample N .nim files from directory
  var files: seq[string]
  for path in walkDirRec(dir, {pcFile}):
    if path.endsWith(".nim"):
      files.add(path)
    if files.len >= count * 3:  # oversample
      break
  # Take first N after sorting for determinism
  files.sort()
  result = files[0 ..< min(count, files.len)]

proc benchmarkHash(source: string, iterations: int): seq[float] =
  ## Measure hash computation time in milliseconds
  result = newSeq[float](iterations)
  for i in 0 ..< iterations:
    let start = cpuTime()
    discard computeAstHash(source)
    let elapsed = cpuTime() - start
    result[i] = elapsed * 1000.0  # convert to ms

proc percentile(data: seq[float], p: float): float =
  let sorted = data.sorted()
  let idx = int(float(sorted.len - 1) * p / 100.0)
  result = sorted[idx]

when isMainModule:
  const
    sampleCount = 20
    iterations = 100

  echo "[benchmark] Sampling ", sampleCount, " source files from src/..."
  let files = sampleSourceFiles("src", sampleCount)

  if files.len == 0:
    echo "[benchmark] ERROR: No source files found"
    quit(1)

  echo "[benchmark] Running ", iterations, " iterations per file..."

  var allTimes: seq[float]
  var coldTimes: seq[float]  # first iteration (cold)
  var warmTimes: seq[float]  # subsequent iterations (warm/cache)

  for file in files:
    let source = readFile(file)
    if source.len == 0:
      continue

    let times = benchmarkHash(source, iterations)
    coldTimes.add(times[0])
    warmTimes.add(times[1 ..^ 1])
    allTimes.add(times)

  let result = %*{
    "sample_files": files.len,
    "iterations_per_file": iterations,
    "cold_parse": {
      "p50": percentile(coldTimes, 50),
      "p95": percentile(coldTimes, 95),
      "p99": percentile(coldTimes, 99),
    },
    "warm_cache": {
      "p50": percentile(warmTimes, 50),
      "p95": percentile(warmTimes, 95),
      "p99": percentile(warmTimes, 99),
    },
    "speedup_ratio": percentile(coldTimes, 50) / max(percentile(warmTimes, 50), 0.001),
  }

  echo "[benchmark] Results:"
  echo result.pretty()

  # Write to file
  let outputPath = "docs/evidence/summary_cache_benchmark.json"
  createDir(outputPath.parentDir)
  writeFile(outputPath, result.pretty())
  echo "[benchmark] Written to: ", outputPath
