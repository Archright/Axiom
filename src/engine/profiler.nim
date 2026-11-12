import std/[monotimes, times, strformat, json, os, strutils]

import infrastructure/perf_provenance_io

## Deterministic stable metric key derived from a human-readable step name:
## "Lean 4 Kernel Verification (file.lean)" -> "LeanKernelVerification".
## Strips the parenthesized suffix, then concatenates the alphanumeric
## content of each space-separated token that contains a letter
## (digit-only tokens such as the "4" in "Lean 4" are dropped).
func stableMetricKey*(stepName: string): string =
  var name = stepName
  let suffix = name.find(" (")
  if suffix > 0:
    name = name[0 ..< suffix]
  for token in name.split(' '):
    var cleaned = ""
    var hasLetter = false
    for ch in token:
      if ch.isAlphaAscii or ch.isDigit:
        cleaned.add ch
        if ch.isAlphaAscii:
          hasLetter = true
    if hasLetter:
      result.add cleaned

template emitProfileData*(stepName: string, maxMs: int, duration: untyped) =
  let ms = duration.inMilliseconds
  let us = duration.inMicroseconds
  echo "[PERF] ", stepName, " completed in ", ms, " ms"
  if maxMs > 0 and ms > maxMs:
    echo "[WARN] Performance regression: ", ms, " ms > ", maxMs, " ms threshold"
  let perfDir = "data" / "benchmarks"
  var measurements = existingMeasurements(perfDir / "perf_latest.json")
  measurements[stableMetricKey(stepName)] = %*{"duration_us": us}
  let perfData = %*{
    "schemaVersion": 2,
    "environment": {
      "nim": NimVersion,
      "lean": leanToolchainRef(),
      "profileMode": "axiomProfile",
      "cacheState": "warm"
    },
    "provenance": {
      "commit": gitHeadCommit(),
      "generatedAt": format(now().utc, "yyyy-MM-dd'T'HH:mm:ss'Z'"),
      "repetitions": 1,
      "aggregation": "single"
    },
    "measurements": measurements
  }
  try:
    if not dirExists(perfDir): createDir(perfDir)
  except OSError: # axiom:best-effort(perf directory creation is non-fatal)
    discard
  except IOError: # axiom:best-effort(perf directory creation is non-fatal)
    discard
  # Best-effort write, deliberately kept: a failed write must not crash
  # proofs, and it cannot fake a pass — the gate fails closed on a missing
  # or schema-stale latest file (tools/perf_checker.nim path ② / ④).
  try:
    writeFile(perfDir / "perf_latest.json", perfData.pretty())
  except IOError:
    discard

template profileBlockImpl(stepName: string, maxMs: int, body: untyped): untyped =
  when compiles((let res = body)):
    when defined(axiomProfile):
      block:
        let startMono = getMonoTime()
        defer:
          let duration = getMonoTime() - startMono
          emitProfileData(stepName, maxMs, duration)
        let res = body
        res
    else:
      let res = body
      res
  else:
    when defined(axiomProfile):
      block:
        let startMono = getMonoTime()
        defer:
          let duration = getMonoTime() - startMono
          emitProfileData(stepName, maxMs, duration)
        body
    else:
      body

template profileBlock*(stepName: string; body: untyped): untyped =
  profileBlockImpl(stepName, 0, body)

template profileBlock*(stepName: string, maxMs: int; body: untyped): untyped =
  profileBlockImpl(stepName, maxMs, body)
