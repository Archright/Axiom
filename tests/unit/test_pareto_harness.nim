## Unit tests for the CI Pareto measurement harness (Phase 1 / v13 ranking).
## Uses the repo's custom main() pattern (no unittest framework), matching
## e.g. tests/unit/test_experiment_replay.nim. Exercises the digest/trace-lock,
## paired-difference, P95, namespace-semantics, queue/λ math and the v13
## ranking/tie-break rules WITHOUT spawning the execution backend (that is the
## harness's own `selftest`).

import std/[os, strutils, math, tables, json]
import tools/sha256_native
import tools/ci/pareto_harness

proc main() =
  var passed = 0
  var failed = 0

  template check(name: string; body: untyped) =
    block:
      try:
        body
        inc passed
        echo "  PASS: " & name
      except CatchableError:
        inc failed
        echo "  FAIL: " & name & " - " & getCurrentExceptionMsg()

  echo "=== sha256 determinism ==="
  check "sha256 empty known vector":
    doAssert sha256String("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  check "sha256 deterministic":
    doAssert sha256String("trace") == sha256String("trace")

  echo "=== trace lock: N fixed at prep time, different N => different hash ==="
  let tmpDir = getTempDir() / ("pareto_harness_unit_" & $getCurrentProcessId())
  if dirExists(tmpDir): removeDir(tmpDir)
  createDir(tmpDir)
  let trA = tmpDir / "trainA.json"
  check "prepare train n=3 returns 0":
    doAssert prepareTrace(tmpDir / "cfgA.json", trA, "train", "fast:t", "slow:t", 5, 10, 7, 3, 24) == 0
  let (t1, ok1, _) = readTraceFile(trA)
  check "trace reads with valid hash":
    doAssert ok1
  check "trace kind train":
    doAssert t1.traceKind == "train"
  check "trace n pre-registered = 3":
    doAssert t1.n == 3
  check "trace carries L1/L2/L3":
    doAssert t1.loadLevels.len == 3
  check "trace body hash excludes preRegisteredAt (no timestamp in digest)":
    doAssert sha256String(canonicalArrivalText(t1)) == sha256String(canonicalArrivalText(t1))

  let trB = tmpDir / "trainB.json"
  check "prepare train n=4 returns 0":
    doAssert prepareTrace(tmpDir / "cfgB.json", trB, "train", "fast:t", "slow:t", 5, 10, 7, 4, 24) == 0
  let (t2, ok2, _) = readTraceFile(trB)
  check "traceB reads ok":
    doAssert ok2
  check "different N => different trace sha256 (new cycle required)":
    doAssert t1.sha256 != t2.sha256

  echo "=== namespace semantics: canonical must pass, deviation must fail ==="
  let v1 = verifyNamespaceSemantics(t1)
  check "namespace verification PASS":
    doAssert v1.ok
  check "namespace verification line text exact":
    doAssert v1.line == "candidate cache namespace isolation preserves production cache key/scope/retention semantics"
  let badCfg = %*{
    "namespaceSemantics": {
      "keyConstruction": "sha256(scope;key;repoState)",
      "scopeSeparation": "SHARED-NAMESPACE-ACROSS-CANDIDATES",
      "retention": "restore-if-hit;evict-if-miss;no-cross-namespace-reads",
      "initialCacheState": "empty-per-namespace"
    }
  }
  let tBad = TraceFile(schema: TraceSchema, traceKind: "train", n: 2,
                       arrivals: @[TraceArrival(seqNo: 1, prKind: "PR", inputRef: "i1", workload: "w1"),
                                   TraceArrival(seqNo: 2, prKind: "PR", inputRef: "i2", workload: "w2")],
                       config: badCfg)
  let vBad = verifyNamespaceSemantics(tBad)
  check "semantics-changing config FAILS verification":
    doAssert not vBad.ok
  check "violation reports declared digest":
    doAssert vBad.declaredDigest.len == 64

  echo "=== paired-difference math (D_i = C_A - C_B) ==="
  let st = pairedStats(@[10.0, -5.0, 40.0])
  check "paired mean delta = 15":
    doAssert abs(st.meanD - 15.0) < 0.000001
  check "paired median delta = 10":
    doAssert abs(st.medianD - 10.0) < 0.000001
  check "paired positive count = 2":
    doAssert st.positiveCount == 2
  check "paired n = 3":
    doAssert st.n == 3

  echo "=== P95: total population, nearest-rank (never segment-weighted) ==="
  var lat: seq[int]
  for i in 1 .. 100: lat.add(i)
  check "p95 of 1..100 = 95":
    doAssert abs(percentile95(lat) - 95.0) < 0.000001
  check "p95 of [1000,1100,1200] = 1200":
    doAssert abs(percentile95(@[1000, 1100, 1200]) - 1200.0) < 0.000001
  check "p95 of [] = 0":
    doAssert percentile95(@[]) == 0.0

  echo "=== queue divergence + λ (capacity diagnostic math) ==="
  check "flat-at-capacity queue is non-divergent":
    doAssert queueNonDivergent(@[1, 2, 1, 2, 1], 10)
  check "backlog growing by a full batch is divergent":
    doAssert not queueNonDivergent(@[1, 2, 5, 8, 11], 10)
  check "queue exceeding 3x capacity is divergent":
    doAssert not queueNonDivergent(@[31, 2, 1, 1, 1], 10)
  check "lambda = c*3600/meanExec":
    doAssert abs(sustainableArrivalRatePerHour(10, 1000.0) - 36.0) < 0.000001

  echo "=== v13 ranking: c* = argmin P95_trace(W_c); cost is diagnostic only ==="
  check "cheaper-but-slower must NOT win (guards the old cost objective)":
    doAssert selectWinner([
      CandidateRankVector(candidateId: "cheap-slow", p95LatencyMs: 1000.0,
                          lambdaObservedMaxPerHour: 0.0, meanQueueMs: 10.0,
                          meanExecMs: 990.0, withinRegressionCeiling: true),
      CandidateRankVector(candidateId: "fast-pricy", p95LatencyMs: 500.0,
                          lambdaObservedMaxPerHour: 0.0, meanQueueMs: 10.0,
                          meanExecMs: 480.0, withinRegressionCeiling: true)]) == "fast-pricy"
  check "higher lambda wins ONLY when P95 exactly equal (tie-break 1)":
    doAssert selectWinner([
      CandidateRankVector(candidateId: "lamlo", p95LatencyMs: 500.0,
                          lambdaObservedMaxPerHour: 10.0, meanQueueMs: 5.0,
                          meanExecMs: 100.0, withinRegressionCeiling: true),
      CandidateRankVector(candidateId: "lamhi", p95LatencyMs: 500.0,
                          lambdaObservedMaxPerHour: 50.0, meanQueueMs: 20.0,
                          meanExecMs: 300.0, withinRegressionCeiling: true)]) == "lamhi"
  check "P95 unequal -> tie-break does NOT engage (min P95 wins despite worse lambda/queue/exec)":
    doAssert selectWinner([
      CandidateRankVector(candidateId: "lowp95", p95LatencyMs: 400.0,
                          lambdaObservedMaxPerHour: 5.0, meanQueueMs: 50.0,
                          meanExecMs: 100.0, withinRegressionCeiling: true),
      CandidateRankVector(candidateId: "highp95", p95LatencyMs: 600.0,
                          lambdaObservedMaxPerHour: 999.0, meanQueueMs: 1.0,
                          meanExecMs: 10.0, withinRegressionCeiling: true)]) == "lowp95"
  check "tie chain: equal P95 -> lambda decides":
    doAssert selectWinner([
      CandidateRankVector(candidateId: "lamlo", p95LatencyMs: 500.0,
                          lambdaObservedMaxPerHour: 10.0, meanQueueMs: 5.0,
                          meanExecMs: 100.0, withinRegressionCeiling: true),
      CandidateRankVector(candidateId: "lamhi", p95LatencyMs: 500.0,
                          lambdaObservedMaxPerHour: 50.0, meanQueueMs: 20.0,
                          meanExecMs: 300.0, withinRegressionCeiling: true)]) == "lamhi"
  check "tie chain: equal P95+lambda -> mean queue decides":
    doAssert selectWinner([
      CandidateRankVector(candidateId: "queuelo", p95LatencyMs: 500.0,
                          lambdaObservedMaxPerHour: 10.0, meanQueueMs: 50.0,
                          meanExecMs: 500.0, withinRegressionCeiling: true),
      CandidateRankVector(candidateId: "queuehi", p95LatencyMs: 500.0,
                          lambdaObservedMaxPerHour: 10.0, meanQueueMs: 120.0,
                          meanExecMs: 200.0, withinRegressionCeiling: true)]) == "queuelo"
  check "tie chain: equal P95+lambda+queue -> mean exec decides":
    doAssert selectWinner([
      CandidateRankVector(candidateId: "execlo", p95LatencyMs: 500.0,
                          lambdaObservedMaxPerHour: 10.0, meanQueueMs: 100.0,
                          meanExecMs: 300.0, withinRegressionCeiling: true),
      CandidateRankVector(candidateId: "exechi", p95LatencyMs: 500.0,
                          lambdaObservedMaxPerHour: 10.0, meanQueueMs: 100.0,
                          meanExecMs: 900.0, withinRegressionCeiling: true)]) == "execlo"
  check "tie chain: all four equal -> candidate id ascending (stable rule)":
    doAssert selectWinner([
      CandidateRankVector(candidateId: "zeta", p95LatencyMs: 500.0,
                          lambdaObservedMaxPerHour: 10.0, meanQueueMs: 100.0,
                          meanExecMs: 300.0, withinRegressionCeiling: true),
      CandidateRankVector(candidateId: "alpha", p95LatencyMs: 500.0,
                          lambdaObservedMaxPerHour: 10.0, meanQueueMs: 100.0,
                          meanExecMs: 300.0, withinRegressionCeiling: true)]) == "alpha"
  check "regression ceiling flag: P95 > 15m flagged false (still ranked, flag only)":
    let over = CandidateRankVector(candidateId: "over", p95LatencyMs: SloP95QueueExecMs.float + 60_000.0,
                                   lambdaObservedMaxPerHour: 3.0, meanQueueMs: 10.0,
                                   meanExecMs: 100.0, withinRegressionCeiling: false)
    let wayOver = CandidateRankVector(candidateId: "way-over", p95LatencyMs: SloP95QueueExecMs.float + 600_000.0,
                                      lambdaObservedMaxPerHour: 3.0, meanQueueMs: 10.0,
                                      meanExecMs: 100.0, withinRegressionCeiling: false)
    doAssert not over.withinRegressionCeiling
    doAssert not wayOver.withinRegressionCeiling
    doAssert selectWinner([over, wayOver]) == "over"
  check "regression ceiling is inclusive at exactly 15m":
    doAssert SloP95QueueExecMs.float <= SloP95QueueExecMs.float
    doAssert not ((SloP95QueueExecMs.float + 1.0) <= SloP95QueueExecMs.float)

  echo "=== lambda_observed_max helper (compare/characterize shared computation) ==="
  var lamRec = RunRecord(schema: RunRecordSchema, candidateId: "fast", cycleId: "cycle-x-1",
                         traceSha256: "abc", traceKind: "train", n: 3)
  for i in 1 .. 3:
    lamRec.observations.add(RunObservation(
      pairIndex: i, order: (if i mod 2 == 1: "A->B" else: "B->A"),
      loadLevel: "L2", queueMs: 0, execMs: 5000, latencyMs: 5000,
      costEuro: 0.01, coreMinutes: 0.1, queueLenAtStart: 1, stratum: "warm"))
  lamRec.observations.add(RunObservation(
    pairIndex: 1, order: "A->B", loadLevel: "L1", queueMs: 0, execMs: 1000,
    latencyMs: 1000, costEuro: 0.01, coreMinutes: 0.1, queueLenAtStart: 1,
    stratum: "cold"))
  lamRec.observations.add(RunObservation(
    pairIndex: 1, order: "A->B", loadLevel: "L3", queueMs: 950000, execMs: 5000,
    latencyMs: 955000, costEuro: 0.01, coreMinutes: 0.1, queueLenAtStart: 5,
    stratum: "cache-hit"))
  check "lambda_observed_max = max over passing loads (L3 excluded, P95>15m)":
    doAssert abs(lambdaObservedMax(lamRec, t1.loadLevels) - 7.2) < 0.000001
  let emptyRec = RunRecord(schema: RunRecordSchema, candidateId: "fast", cycleId: "cycle-x-1",
                           traceSha256: "abc", traceKind: "train", n: 0)
  check "lambda_observed_max of empty record is 0":
    doAssert lambdaObservedMax(emptyRec, t1.loadLevels) == 0.0

  echo "=== cycle registry: first compare locks, foreign cycle refused ==="
  let regPath = tmpDir / "registry.json"
  var reg = loadRegistry(regPath)
  let id1 = registerCycle(regPath, "abc-123-train", reg)
  check "cycle registered":
    doAssert id1 == "cycle-abc-123-train-1"
  var reg2 = loadRegistry(regPath)
  let id2 = registerCycle(regPath, "abc-123-train", reg2)
  check "cycle id stable across registry reload":
    doAssert id1 == id2
  var reg3 = loadRegistry(regPath)
  check "different trace => different cycle (new cycle)":
    doAssert id1 != registerCycle(regPath, "abd-124-train", reg3)

  echo "=== record duplicate predicate (pre-registration integrity) ==="
  var exp = RunRecord(schema: RunRecordSchema, candidateId: "fast", cycleId: "cycle-x-1",
                      traceSha256: "abc", traceKind: "train", n: 3)
  check "pair not recorded initially":
    doAssert not alreadyRecorded(exp, 1, "A->B", "L2")
  var rec = exp
  rec.observations.add(RunObservation(
    pairIndex: 1, order: "A->B", loadLevel: "L2", queueMs: 10, execMs: 130,
    latencyMs: 140, costEuro: 0.0012, coreMinutes: 0.002, queueLenAtStart: 1,
    stratum: "warm"))
  rec.recordHash = runRecordHash(rec)
  check "pair recorded after append":
    doAssert alreadyRecorded(rec, 1, "A->B", "L2")
  check "different order is NOT a duplicate":
    doAssert not alreadyRecorded(rec, 1, "B->A", "L2")
  check "different load is NOT a duplicate":
    doAssert not alreadyRecorded(rec, 1, "A->B", "L1")

  echo "=== factorAnalysis (strata diagnostic) ==="
  let fa = factorAnalysis(@[
    RunObservation(pairIndex: 1, order: "A->B", loadLevel: "L2", queueMs: 0, execMs: 100,
                   latencyMs: 100, costEuro: 0.010, coreMinutes: 0.1, queueLenAtStart: 0, stratum: "cold"),
    RunObservation(pairIndex: 2, order: "B->A", loadLevel: "L2", queueMs: 0, execMs: 200,
                   latencyMs: 200, costEuro: 0.020, coreMinutes: 0.2, queueLenAtStart: 0, stratum: "warm"),
    RunObservation(pairIndex: 3, order: "A->B", loadLevel: "L2", queueMs: 0, execMs: 300,
                   latencyMs: 300, costEuro: 0.030, coreMinutes: 0.3, queueLenAtStart: 0, stratum: "cache-hit")])
  check "factorAnalysis mean cost = 0.02":
    doAssert abs(fa.meanCost - 0.020) < 0.000001
  check "factorAnalysis p95 latency (population) = 300":
    doAssert abs(fa.p95Latency - 300.0) < 0.000001
  check "factorAnalysis 3 strata":
    doAssert fa.strata.len == 3
  check "stratum proportion p=1/3":
    doAssert abs(fa.strata["cold"].p - 1.0/3.0) < 0.000001
  check "per-stratum mean cost":
    doAssert abs(fa.strata["warm"].meanCostEuro - 0.020) < 0.000001

  echo "=== github-run ingestion: ISO parsing (strict zone, sentinel -1) ==="
  check "ISO Z-suffix -> epoch ms":
    doAssert parseGitHubIsoMs("2026-09-25T06:53:39Z") == 1790319219000
  check "ISO +00:00 offset -> same instant":
    doAssert parseGitHubIsoMs("2026-09-25T06:53:39+00:00") == 1790319219000
  check "ISO +02:00 offset -> shifted instant":
    doAssert parseGitHubIsoMs("2026-09-25T06:53:39+02:00") == 1790312019000
  check "ISO zone required (bare datetime is malformed)":
    doAssert parseGitHubIsoMs("2026-09-25T06:53:39") == -1
  check "ISO malformed -> -1":
    doAssert parseGitHubIsoMs("yesterday") == -1

  echo "=== github-run ingestion: payload parse + derivation (real parser) ==="
  var ghRun = %*{
    "id": 36104951644, "name": "hardware-falsification-smoke",
    "event": "push", "status": "completed", "conclusion": "success",
    "head_branch": "optimize/ci-pareto", "head_sha": "efa24c38534c263d938813db6f2a3e7ff36360f9",
    "workflow_id": 366714812, "run_attempt": 1,
    "run_started_at": "2026-09-25T06:53:39Z", "updated_at": "2026-09-25T06:57:14Z"}
  var ghJobs = %*{"total_count": 2, "jobs": @[
    %*{"id": 107975310181, "name": "arm-falsification", "status": "completed",
       "conclusion": "success", "started_at": "2026-09-25T06:53:45Z",
       "completed_at": "2026-09-25T06:57:13Z", "labels": @["ubuntu-24.04-arm"]},
    %*{"id": 107975311557, "name": "slim-light-falsification", "status": "completed",
       "conclusion": "skipped", "started_at": "2026-09-25T06:53:41Z",
       "completed_at": "2026-09-25T06:53:40Z", "labels": @["ubuntu-slim"]}]}
  let (gr, gok, _) = parseGitHubPayload(ghRun, ghJobs)
  check "payload parses (real shape, success + skipped job)":
    doAssert gok
  check "skipped job timestamps not required (never occupied a runner)":
    doAssert gr.jobs.len == 2 and gr.jobs[1].startedMs == -1
  let gd = deriveIngestObservation(gr)
  check "derivation ok":
    doAssert gd.ok
  check "queue=6000 (first success job start - run_started_at)":
    doAssert gd.queueMs == 6000
  check "exec=209000 (updated_at - first success job start)":
    doAssert gd.execMs == 209000
  check "latency=215000 (queue+exec telescopes to updated_at - run_started_at)":
    doAssert gd.latencyMs == 215000
  check "coreMinutes=3.4667 (sum of success-job durations only)":
    doAssert abs(gd.coreMinutes - 3.466666666666667) < 0.000001
  check "per-job duration (arm 208000 ms) parsed":
    doAssert gr.jobs[0].durationMs == 208000
  check "costEuro proxy = latency-minutes (diagnostic)":
    doAssert abs(gd.latencyMs.float / 60000.0 - 3.5833333333333335) < 0.000001

  var ghFail = %*{"id": 36104951645, "name": "w", "event": "push", "status": "completed",
                  "conclusion": "failure", "head_branch": "b", "head_sha": "s",
                  "run_attempt": 1, "run_started_at": "2026-09-25T06:53:39Z",
                  "updated_at": "2026-09-25T06:57:14Z"}
  var ghFailJobs = %*{"jobs": @[%*{"name": "j", "conclusion": "success",
      "started_at": "2026-09-25T06:53:45Z", "completed_at": "2026-09-25T06:57:13Z", "labels": @[]}]}
  let (grf, _, _) = parseGitHubPayload(ghFail, ghFailJobs)
  let df = deriveIngestObservation(grf)
  check "conclusion != success rejected (exit 2 at CLI) with reason":
    doAssert not df.ok and "conclusion" in df.reason

  var ghLive = %*{"id": 36104951646, "name": "w", "event": "push", "status": "in_progress",
                  "conclusion": "", "head_branch": "b", "head_sha": "s",
                  "run_started_at": "2026-09-25T06:53:39Z", "updated_at": "2026-09-25T06:57:14Z"}
  let (grl, _, _) = parseGitHubPayload(ghLive, ghFailJobs)
  check "in_progress run rejected (not completed)":
    doAssert not deriveIngestObservation(grl).ok

  var ghNoSucc = %*{"jobs": @[%*{"name": "j", "conclusion": "skipped",
      "started_at": "2026-09-25T06:53:45Z", "completed_at": "2026-09-25T06:57:13Z", "labels": @[]}]}
  let (grn, _, _) = parseGitHubPayload(ghRun, ghNoSucc)
  check "no success job rejected":
    doAssert not deriveIngestObservation(grn).ok

  var ghNeg = %*{"id": 36104951647, "name": "w", "event": "push", "status": "completed",
                 "conclusion": "success", "head_branch": "b", "head_sha": "s",
                 "run_attempt": 1, "run_started_at": "2026-09-25T06:53:50Z",
                 "updated_at": "2026-09-25T06:57:14Z"}
  let (grq, _, _) = parseGitHubPayload(ghNeg, ghFailJobs)  # job starts 06:53:45 < run start
  check "negative queue rejected":
    doAssert not deriveIngestObservation(grq).ok

  check "payload without jobs array rejected at parse":
    doAssert not parseGitHubPayload(ghRun, %*{"total_count": 0}).ok

  echo "=== github-run provenance: informational, excluded from recordHash ==="
  var recPlain = RunRecord(schema: RunRecordSchema, candidateId: "fast",
                           cycleId: "cycle-x-1", traceSha256: "abc", traceKind: "train", n: 1)
  var recWith = RunRecord(schema: RunRecordSchema, candidateId: "fast",
                          cycleId: "cycle-x-1", traceSha256: "abc", traceKind: "train", n: 1)
  let obsV1 = RunObservation(
    pairIndex: 1, order: "A->B", loadLevel: "L2", queueMs: 6000, execMs: 209000,
    latencyMs: 215000, costEuro: 3.58, coreMinutes: 3.4667, queueLenAtStart: 0,
    stratum: "cold")
  recPlain.observations.add(obsV1)
  recWith.observations.add(RunObservation(
    pairIndex: 1, order: "A->B", loadLevel: "L2", queueMs: 6000, execMs: 209000,
    latencyMs: 215000, costEuro: 3.58, coreMinutes: 3.4667, queueLenAtStart: 0,
    stratum: "cold", githubRun: %*{"runId": "36104951644", "runnerLabels": @["ubuntu-24.04-arm"]}))
  recPlain.recordHash = runRecordHash(recPlain)
  recWith.recordHash = runRecordHash(recWith)
  check "identical v1 fields -> identical recordHash (provenance excluded)":
    doAssert recPlain.recordHash == recWith.recordHash
  let back = parseRunRecord(runRecordToJson(recWith))
  check "provenance round-trips through record JSON":
    doAssert back.observations[0].githubRun != nil
    doAssert back.observations[0].githubRun["runId"].getStr() == "36104951644"
  let backPlain = parseRunRecord(runRecordToJson(recPlain))
  check "provenance absent -> nil (old records still parse)":
    doAssert backPlain.observations[0].githubRun == nil

  removeDir(tmpDir)

  echo ""
  echo "=== summary: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0:
    quit(1)

main()
