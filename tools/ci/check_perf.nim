import std/[json, os, strutils]

## Budget validator for the performance regression track (issue #350).
##
## FAIL-CLOSED. Every degenerate input is an explicit failure, never a skip:
##   ① latest artifact missing        ② budget missing
##   ③ unreadable/invalid JSON       ④ budget or measurements block not an object
##   ⑤ no budget metric measured at all (vacuous pass blocked)
##
## The v1 shape of this tool read `budget.pairs` against the ROOT of
## perf_latest.json. The artifact produced by tools/perf_measure.nim is schema
## v2 and nests timings under measurements.<key>.duration_us, so the root lookup
## never matched: every budget key fell through to "Unmonitored metric" and the
## tool exited 0 even for a 330x regression. Presence checks alone would not
## have fixed that, so the real schema is read here.
##
## A budget key that the harness does not measure is reported by name (it is a
## coverage gap, not a pass) — but if NO budget key is measured, that is ⑤.
##
## Exit 0 iff every measured metric is within budget. `make perf-check` runs
## the fail-closed gate (tools/perf_checker.nim); this validator adds the
## independent budget ceiling (data/benchmarks/perf_budget.json).

const
  LatestFile = "data/benchmarks/perf_latest.json"
  BudgetFile = "data/benchmarks/perf_budget.json"

proc parseCliPath(option, defaultValue: string): string =
  result = defaultValue
  let prefix = "--" & option
  for i in 1 .. paramCount():
    let value = paramStr(i)
    if value.startsWith(prefix):
      let separator = if value.startsWith(prefix & "="): '=' else: ':'
      if separator != '\0':
        result = value[prefix.len + 1 ..^ 1]

proc loadJson(path, role: string; ok: var bool): JsonNode =
  ## Presence + parse are both explicit failures: a missing input can never
  ## mean "nothing to validate" (§0.9 fail-open).
  result = newJObject()
  if not fileExists(path):
    echo "[PERF FAIL] ", role, " missing (", path, ")"
    ok = false
    return
  try:
    result = parseJson(readFile(path))
  except CatchableError as e:
    echo "[PERF FAIL] ", role, " unreadable (", path, "): ", e.msg
    ok = false

let
  latestFile = parseCliPath("latest", LatestFile)
  budgetFile = parseCliPath("budget", BudgetFile)

var loadOk = true
let latest = loadJson(latestFile, "latest artifact", loadOk)
let budget = loadJson(budgetFile, "budget", loadOk)

if not loadOk:
  quit(1)

if latest.kind != JObject:
  echo "[PERF FAIL] latest artifact is not a JSON object (", latestFile, ")"
  quit(1)
if budget.kind != JObject:
  echo "[PERF FAIL] budget is not a JSON object (", budgetFile, ")"
  quit(1)

# Schema v2: measurements.<key>.duration_us. Accept a bare number per key so a
# flat artifact is still validated rather than silently skipped.
var measurements = newJObject()
if latest.hasKey("measurements"):
  if latest["measurements"].kind != JObject:
    echo "[PERF FAIL] latest artifact measurements block is not an object (", latestFile, ")"
    quit(1)
  measurements = latest["measurements"]

echo "[PERF] budget: latest=", latestFile, " budget=", budgetFile

var hasRegression = false
var measured = 0
var unmeasured: seq[string] = @[]

for key, spec in budget.pairs:
  if spec.kind != JObject or not spec.hasKey("budget_us") or
      not spec.hasKey("max_allowed_regression_pct"):
    echo "[PERF FAIL] ", key, ": budget entry malformed (budget_us / max_allowed_regression_pct required)"
    hasRegression = true
    continue

  let
    budgetUs = spec["budget_us"].getFloat()
    maxPct = spec["max_allowed_regression_pct"].getFloat()
    limitUs = budgetUs * (1.0 + maxPct / 100.0)

  var actualUs = -1.0
  var entryOk = false
  if measurements.hasKey(key):
    let entry = measurements[key]
    if entry.kind == JObject and entry.hasKey("duration_us") and
        entry["duration_us"].kind == JInt:
      actualUs = entry["duration_us"].getInt().float
      entryOk = true
    elif entry.kind == JInt:
      actualUs = entry.getInt().float
      entryOk = true
    elif entry.kind == JFloat:
      actualUs = entry.getFloat()
      entryOk = true

  if not entryOk:
    unmeasured.add key
    continue

  inc measured
  if actualUs > limitUs:
    echo "[PERF FAIL] ", key, ": ", int(actualUs), "us exceeded budget limit ",
      int(limitUs), "us (+", maxPct, "%)"
    hasRegression = true
  else:
    echo "[PERF PASS] ", key, ": ", int(actualUs), "us (Budget: ", int(budgetUs),
      "us, limit ", int(limitUs), "us)"

for key in unmeasured:
  echo "[PERF GAP] ", key, ": no measurement in ", latestFile,
    " — budget entry has no evidence this run (coverage gap, NOT a pass)"

if measured == 0:
  echo "[PERF FAIL] vacuous pass blocked — no budget metric was measured in ", latestFile
  quit(1)

if hasRegression:
  quit(1)

echo "[PERF] budget check passed for ", measured, " metric(s)"
