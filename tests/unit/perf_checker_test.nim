# perf_checker_test.nim
# Permanent regression net for the fail-closed performance gate
# (tools/perf_checker.nim). Exercises all failure paths plus the OK path
# through the factored runPerfCheck decision core — the same proc the
# `perf-check` target (make test) executes. Fixtures live under getTempDir;
# the committed baseline is never touched.
#
# Run: nim c -r --hints:off tests/unit/perf_checker_test.nim

import std/[unittest, os, json, strutils]
import perf_checker
import engine/profiler  # stableMetricKey — the producer-side key derivation
import perf_measure     # aggregateMin — the a-priori both-sides aggregation

let tmpDir = getTempDir() / "axiom_perf_checker_test_" & $getCurrentProcessId()
createDir(tmpDir)

proc defaultEnv(): JsonNode =
  %*{"nim": "2.2.10", "lean": "leanprover/lean4:v4.33.0",
     "profileMode": "axiomProfile", "cacheState": "warm"}

proc writeDoc(name: string, doc: JsonNode) =
  writeFile(tmpDir / name, doc.pretty())

proc v2Doc(measurements: JsonNode; env: JsonNode = defaultEnv();
    schemaVersion: int = 2; commit = "cafebabe";
    dropEnvironment = false; dropMeasurements = false): JsonNode =
  var doc = %*{
    "schemaVersion": schemaVersion,
    "provenance": {
      "commit": commit,
      "generatedAt": "2026-10-15T00:00:00Z",
      "repetitions": 5,
      "aggregation": "median"
    },
    "measurements": measurements
  }
  if not dropEnvironment:
    doc["environment"] = env
  if dropMeasurements:
    doc.delete("measurements")
  doc

proc meas(key: string; us: int64): JsonNode =
  %*{key: {"duration_us": us}}

proc text(r: tuple[ok: bool, messages: seq[string]]): string =
  join(r.messages, "\n")

const MaxRegression = 5.0

suite "perf gate — fail-closed decision core":

  test "OK path — matched metric within budget":
    writeDoc("b_ok.json", v2Doc(meas("LeanKernelVerification", 1_000_000)))
    writeDoc("l_ok.json", v2Doc(meas("LeanKernelVerification", 1_030_000)))
    let r = runPerfCheck(tmpDir / "b_ok.json", tmpDir / "l_ok.json", MaxRegression)
    check r.ok
    check text(r).contains("[PERF OK] LeanKernelVerification: 3.0% change")

  test "OK boundary — exactly max regression is not a violation (strictly-greater rule)":
    writeDoc("b_eq.json", v2Doc(meas("LeanKernelVerification", 100_000)))
    writeDoc("l_eq.json", v2Doc(meas("LeanKernelVerification", 105_000)))
    let r = runPerfCheck(tmpDir / "b_eq.json", tmpDir / "l_eq.json", MaxRegression)
    check r.ok

  test "regression above max fails with [PERF REGRESSION]":
    writeDoc("b_reg.json", v2Doc(meas("LeanKernelVerification", 100_000)))
    writeDoc("l_reg.json", v2Doc(meas("LeanKernelVerification", 120_000)))
    let r = runPerfCheck(tmpDir / "b_reg.json", tmpDir / "l_reg.json", MaxRegression)
    check not r.ok
    check text(r).contains(
      "[PERF REGRESSION] LeanKernelVerification: +20.0% (max: 5.0%)")

  test "all regressions reported when multiple metrics violate":
    writeDoc("b_multi.json", v2Doc(%*{
      "K1": {"duration_us": 100_000}, "K2": {"duration_us": 200_000}}))
    writeDoc("l_multi.json", v2Doc(%*{
      "K1": {"duration_us": 300_000}, "K2": {"duration_us": 400_000}}))
    let r = runPerfCheck(tmpDir / "b_multi.json", tmpDir / "l_multi.json", MaxRegression)
    check not r.ok
    check text(r).contains("[PERF REGRESSION] K1: +200.0% (max: 5.0%)")
    check text(r).contains("[PERF REGRESSION] K2: +100.0% (max: 5.0%)")

  test "baseline zero — division-by-zero guard fails explicitly (no Inf/NaN)":
    writeDoc("b_zero.json", v2Doc(meas("LeanKernelVerification", 0)))
    writeDoc("l_zero.json", v2Doc(meas("LeanKernelVerification", 123)))
    let r = runPerfCheck(tmpDir / "b_zero.json", tmpDir / "l_zero.json", MaxRegression)
    check not r.ok
    check text(r).contains("baseline duration must be > 0 (got 0us)")
    check text(r).contains("refusing division by zero")

  test "negative baseline fails explicitly":
    writeDoc("b_neg.json", v2Doc(meas("LeanKernelVerification", -5)))
    writeDoc("l_neg.json", v2Doc(meas("LeanKernelVerification", 100)))
    let r = runPerfCheck(tmpDir / "b_neg.json", tmpDir / "l_neg.json", MaxRegression)
    check not r.ok
    check text(r).contains("baseline duration must be > 0 (got -5us)")

  test "negative latest fails explicitly":
    writeDoc("b_nl.json", v2Doc(meas("LeanKernelVerification", 100)))
    writeDoc("l_nl.json", v2Doc(meas("LeanKernelVerification", -1)))
    let r = runPerfCheck(tmpDir / "b_nl.json", tmpDir / "l_nl.json", MaxRegression)
    check not r.ok
    check text(r).contains("latest duration must be >= 0 (got -1us)")

  test "non-integer measurement fails explicitly":
    writeDoc("b_str.json", v2Doc(meas("LeanKernelVerification", 100)))
    writeDoc("l_str.json", v2Doc(%*{"LeanKernelVerification": {"duration_us": "fast"}}))
    let r = runPerfCheck(tmpDir / "b_str.json", tmpDir / "l_str.json", MaxRegression)
    check not r.ok
    check text(r).contains("invalid latest measurement — duration_us (int) required")

  test "baseline missing — explicit failure with remediation, never a skip":
    writeDoc("l_present.json", v2Doc(meas("LeanKernelVerification", 100)))
    let r = runPerfCheck(tmpDir / "no_such_baseline.json",
      tmpDir / "l_present.json", MaxRegression)
    check not r.ok
    check text(r).contains("baseline missing")
    check text(r).contains("make perf-baseline")
    check text(r).contains("never auto-generated")

  test "latest missing — measurement harness produced no data":
    writeDoc("b_present.json", v2Doc(meas("LeanKernelVerification", 100)))
    let r = runPerfCheck(tmpDir / "b_present.json",
      tmpDir / "no_such_latest.json", MaxRegression)
    check not r.ok
    check text(r).contains("latest missing")
    check text(r).contains("perf-check stage 1")

  test "corrupt baseline JSON fails with parse error, no traceback":
    writeFile(tmpDir / "b_corrupt.json", "{\"schemaVersion\": 2, \"env")
    writeDoc("l_corrupt.json", v2Doc(meas("LeanKernelVerification", 100)))
    let r = runPerfCheck(tmpDir / "b_corrupt.json", tmpDir / "l_corrupt.json", MaxRegression)
    check not r.ok
    check text(r).contains("baseline unparseable JSON")

  test "corrupt latest JSON fails with parse error, no traceback":
    writeDoc("b_corrupt2.json", v2Doc(meas("LeanKernelVerification", 100)))
    writeFile(tmpDir / "l_corrupt.json", "not json at all {{{")
    let r = runPerfCheck(tmpDir / "b_corrupt2.json", tmpDir / "l_corrupt.json", MaxRegression)
    check not r.ok
    check text(r).contains("latest unparseable JSON")

  test "schemaVersion drift fails explicitly":
    writeDoc("b_v1.json", v2Doc(meas("LeanKernelVerification", 100), schemaVersion = 1))
    writeDoc("l_v1.json", v2Doc(meas("LeanKernelVerification", 100)))
    let r = runPerfCheck(tmpDir / "b_v1.json", tmpDir / "l_v1.json", MaxRegression)
    check not r.ok
    check text(r).contains("baseline: invalid schema — schemaVersion must be 2")

  test "missing environment block fails explicitly":
    writeDoc("b_noenv.json", v2Doc(meas("LeanKernelVerification", 100), dropEnvironment = true))
    writeDoc("l_noenv.json", v2Doc(meas("LeanKernelVerification", 100)))
    let r = runPerfCheck(tmpDir / "b_noenv.json", tmpDir / "l_noenv.json", MaxRegression)
    check not r.ok
    check text(r).contains("baseline: invalid schema — environment block missing")

  test "empty environment field fails explicitly":
    let badEnv = %*{"nim": "", "lean": "leanprover/lean4:v4.33.0",
                    "profileMode": "axiomProfile", "cacheState": "warm"}
    writeDoc("b_empty.json", v2Doc(meas("LeanKernelVerification", 100), env = badEnv))
    writeDoc("l_empty.json", v2Doc(meas("LeanKernelVerification", 100)))
    let r = runPerfCheck(tmpDir / "b_empty.json", tmpDir / "l_empty.json", MaxRegression)
    check not r.ok
    check text(r).contains("baseline: invalid schema — environment.nim must be a non-empty string")

  test "missing measurements block fails explicitly":
    writeDoc("b_nomeas.json", v2Doc(meas("LeanKernelVerification", 100), dropMeasurements = true))
    writeDoc("l_nomeas.json", v2Doc(meas("LeanKernelVerification", 100)))
    let r = runPerfCheck(tmpDir / "b_nomeas.json", tmpDir / "l_nomeas.json", MaxRegression)
    check not r.ok
    check text(r).contains("baseline: invalid schema — measurements block must be a JSON object")

  test "environment mismatch fails — comparability fields are enforced":
    let oldLean = %*{"nim": "2.2.10", "lean": "leanprover/lean4:v4.32.0",
                     "profileMode": "axiomProfile", "cacheState": "warm"}
    writeDoc("b_env.json", v2Doc(meas("LeanKernelVerification", 100), env = oldLean))
    writeDoc("l_env.json", v2Doc(meas("LeanKernelVerification", 100)))
    let r = runPerfCheck(tmpDir / "b_env.json", tmpDir / "l_env.json", MaxRegression)
    check not r.ok
    check text(r).contains("measurement environment differs from baseline environment")
    check text(r).contains("lean: baseline=leanprover/lean4:v4.32.0 latest=leanprover/lean4:v4.33.0")

  test "provenance-only difference passes — provenance never affects comparison":
    writeDoc("b_prov.json", %*{
      "schemaVersion": 2, "environment": defaultEnv(),
      "provenance": {"commit": "aaa111", "generatedAt": "2026-10-15T00:00:00Z",
        "repetitions": 5, "aggregation": "min"},
      "measurements": meas("LeanKernelVerification", 100)})
    writeDoc("l_prov.json", %*{
      "schemaVersion": 2, "environment": defaultEnv(),
      "provenance": {"commit": "bbb222", "generatedAt": "2026-10-15T09:99:99Z",
        "repetitions": 1, "aggregation": "single"},
      "measurements": meas("LeanKernelVerification", 100)})
    let r = runPerfCheck(tmpDir / "b_prov.json", tmpDir / "l_prov.json", MaxRegression)
    check r.ok

  test "zero key overlap — vacuous pass blocked":
    writeDoc("b_vac.json", v2Doc(meas("OnlyInBaseline", 100)))
    writeDoc("l_vac.json", v2Doc(meas("OnlyInLatest", 100)))
    let r = runPerfCheck(tmpDir / "b_vac.json", tmpDir / "l_vac.json", MaxRegression)
    check not r.ok
    check text(r).contains("vacuous pass blocked — no metric overlap between baseline and latest")

  test "stable metric key derivation is deterministic":
    check stableMetricKey(
      "Lean 4 Kernel Verification (tests/fixtures/temp_vc_test.lean)") ==
      "LeanKernelVerification"
    check stableMetricKey("Lean 4 Kernel Verification") == "LeanKernelVerification"
    check stableMetricKey("Hybrid Lean+Z3 BMC Verification (f.lean)") ==
      "HybridLeanZ3BMCVerification"
    check stableMetricKey("test expr") == "testexpr"

  test "aggregateMin — interference-robust aggregation, identical on both sides":
    check aggregateMin(@[int64 302565, 252540, 252565, 252590, 302831]) == 252540
    check aggregateMin(@[int64 252565]) == 252565
    check aggregateMin(@[int64 303408, 302596]) == 302596
    check aggregateMin(@[int64 0]) == 0  # tool fails hard before aggregating empty samples
