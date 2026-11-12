import std/[json, os, osproc, strutils, times]

## Canonical performance measurement tool — ONE implementation of the
## run-5x + aggregate(min) policy, applied to BOTH sides of the gate
## (a-priori aggregation parity). Min-of-N is the interference-robust
## standard: under this host's bimodal kernel timing (252.4ms / 302.8ms
## clusters) min lands on the interference-free cluster, so a residual
## flip between two min-of-5 values indicates a real sustained
## environment shift — exactly what the gate should flag.
##
##   nim c -r tools/perf_measure.nim latest     # perf-check stage 1
##   nim c -r tools/perf_measure.nim baseline   # EXPLICIT-ONLY (make perf-baseline)
##
## `baseline` mode must never be wired into any automatic path: an
## auto-refreshed baseline would silently launder real regressions (§0.9).
##
## `latest` writes an execution artifact (data/benchmarks/perf_latest.json,
## gitignored — never tracked): every run overwrites it in place and a fresh
## checkout has none until the first run. Only approved baselines
## (perf_baseline.json / perf_budget.json) are versioned, so the fresh
## measurement can never sweep churn into unrelated commits (the documented
## `git add -u` staging-sweep trap). The path itself is unchanged — the gate
## (tools/perf_checker.nim) reads the same ignored location and still fails
## closed when the artifact is absent.

const
  Repetitions = 5
  MetricKey = "LeanKernelVerification"
  SchemaVersion = 2
  Aggregation = "min"
  LatestPath = "data" / "benchmarks" / "perf_latest.json"
  BaselinePath = "data" / "benchmarks" / "perf_baseline.json"
  HarnessSource = "tests/test_vc_complete.nim"
  HarnessBinary = "build" / "perf_vc_harness"
  EnvFields = ["nim", "lean", "profileMode", "cacheState"]

proc fail(msg: string) {.noreturn.} =
  echo "[perf-measure] FAIL: " & msg
  quit(1)

proc aggregateMin*(samples: seq[int64]): int64 {.raises: [].} =
  ## The gate's a-priori aggregation, identical on both sides. Empty input
  ## yields 0; the measurement modes fail hard before aggregating on empty
  ## samples, so 0 never reaches the gate from this tool.
  if samples.len == 0:
    return 0
  result = samples[0]
  for sample in samples:
    if sample < result:
      result = sample

proc runOk(command, what: string) =
  let code = execCmd(command)
  if code != 0:
    fail(what & " failed (exit " & $code & "): " & command)

proc headCommit(required: bool): string =
  var (outp, code) = ("", 1)
  try:
    (outp, code) = execCmdEx("git rev-parse HEAD")
  except CatchableError: # axiom:best-effort(latest provenance is informational; baseline mode re-checks below)
    discard
  if code != 0:
    if required:
      fail("git rev-parse HEAD failed — provenance.commit is mandatory for a baseline")
    return ""
  return outp.strip()

proc loadLatest(): tuple[env: JsonNode, us: int64] =
  var root: JsonNode
  var readErr = ""
  try:
    root = parseJson(readFile(LatestPath))
  except CatchableError as e:
    readErr = e.msg
  if readErr.len > 0:
    fail("harness produced unreadable " & LatestPath & ": " & readErr)
  if root.kind != JObject or not root.hasKey("schemaVersion") or
      root["schemaVersion"].kind != JInt or
      root["schemaVersion"].getInt() != SchemaVersion:
    fail(LatestPath & " is not schema v2 — profiler emit is broken")
  if not root.hasKey("environment") or root["environment"].kind != JObject:
    fail(LatestPath & " has no environment block — profiler emit is broken")
  for field in EnvFields:
    if not root["environment"].hasKey(field) or
        root["environment"][field].kind != JString or
        root["environment"][field].getStr().len == 0:
      fail(LatestPath & " environment." & field &
        " missing/empty — profiler emit is broken")
  if not root.hasKey("measurements") or root["measurements"].kind != JObject or
      not root["measurements"].hasKey(MetricKey):
    fail(LatestPath & " lacks measurements." & MetricKey &
      " — harness did not profile the kernel step")
  let entry = root["measurements"][MetricKey]
  if entry.kind != JObject or not entry.hasKey("duration_us") or
      entry["duration_us"].kind != JInt or entry["duration_us"].getInt() <= 0:
    fail("measurements." & MetricKey &
      ".duration_us invalid — harness did not profile the kernel step")
  return (root["environment"], entry["duration_us"].getInt().int64)

proc measureMinOfN(): tuple[samples: seq[int64], env: JsonNode] =
  ## Compile the -d:axiomProfile harness once, run it Repetitions times,
  ## validate every run's emit, enforce environment identity across runs.
  echo "[perf-measure] compiling profiling harness (" & $Repetitions &
    "-run " & Aggregation & ")..."
  createDir("build")
  createDir("data" / "benchmarks")
  runOk("nim c -d:axiomProfile -o:" & HarnessBinary & " " & HarnessSource,
    "harness compilation")
  # Clean slate so each sample is exactly one harness run, never a stale
  # or legacy-schema leftover.
  try:
    removeFile(LatestPath)
  except OSError, IOError: # axiom:best-effort(absent latest on a fresh checkout raises; every sample is rewritten and schema-validated after each harness run)
    discard

  var samples: seq[int64]
  var env: JsonNode = nil
  for i in 1 .. Repetitions:
    echo "[perf-measure] harness run " & $i & "/" & $Repetitions & "..."
    runOk(HarnessBinary, "harness run " & $i)
    let (runEnv, us) = loadLatest()
    if env != nil and $env != $runEnv:
      fail("measurement environment changed between runs — samples are not " &
        "comparable:\n  run n-1: " & $env & "\n  run n:   " & $runEnv)
    env = runEnv
    samples.add us
    echo "[perf-measure]   sample " & $i & ": " & $us & "us"
  return (samples, env)

proc writeDoc(path: string; env: JsonNode; us: int64; commit: string) =
  let doc = %*{
    "schemaVersion": SchemaVersion,
    "environment": env,
    "provenance": {
      "commit": commit,
      "generatedAt": format(now().utc, "yyyy-MM-dd'T'HH:mm:ss'Z'"),
      "repetitions": Repetitions,
      "aggregation": Aggregation
    },
    "measurements": {
      MetricKey: {"duration_us": us}
    }
  }
  writeFile(path, doc.pretty() & "\n")

proc report(path: string; samples: seq[int64]; agg: int64; env: JsonNode) =
  echo "[perf-measure] OK: wrote " & path
  echo "[perf-measure]   samples(us): " & $samples
  echo "[perf-measure]   " & Aggregation & ": " & $agg & "us  repetitions: " &
    $Repetitions & "  aggregation: " & Aggregation
  echo "[perf-measure]   environment: nim=" & env["nim"].getStr() &
    " lean=" & env["lean"].getStr() & " profileMode=" &
    env["profileMode"].getStr() & " cacheState=" & env["cacheState"].getStr()

proc main(mode: string) =
  case mode
  of "latest":
    let (samples, env) = measureMinOfN()
    let agg = aggregateMin(samples)
    writeDoc(LatestPath, env, agg, headCommit(required = false))
    report(LatestPath, samples, agg, env)
  of "baseline":
    echo "[perf-measure] EXPLICIT-ONLY mode: baseline is regenerated by deliberate " &
      "human action, never automatically (an auto-refreshed baseline launders regressions)."
    let (samples, env) = measureMinOfN()
    let agg = aggregateMin(samples)
    writeDoc(BaselinePath, env, agg, headCommit(required = true))
    report(BaselinePath, samples, agg, env)
  else:
    fail("usage: perf_measure [latest|baseline]")

when isMainModule:
  if paramCount() < 1:
    fail("usage: perf_measure [latest|baseline]")
  main(paramStr(1))
