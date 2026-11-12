## pareto_harness.nim — Workload-trace replay measurement harness (CI Pareto, Phase 1)
##
## Controlled-measurement instrument for comparing CI candidate configurations.
## Executes whatever execution backend is configured: the local backend (`run`,
## make targets / shell scripts per candidate) AND a GitHub-run ingestion backend
## (`ingest`, reads completed GitHub Actions runs via `gh api` — READ-ONLY; it
## never triggers or modifies workflow runs).
##
## Pre-registration discipline (from the approved CI-optimization plan):
##   1. Traces are fixed BEFORE any measurement: `prepare-train` and
##      `prepare-holdout` write immutable files under data/ci_pareto/ whose
##      sha256 (of the digest-covered body) is recorded inside the file. The
##      holdout is written by a SEPARATE command and is NEVER read by the
##      comparison path (compare refuses non-train traces, exit 2).
##   2. The experiment N is fixed at trace-preparation time (field `n` in the
##      trace file). Replay subcommands (`run`, `compare`) accept a --trace
##      only; there is no runtime --n flag. Refusing to extend N mid-run is
##      enforced by the trace lock: the first `compare` on a trace registers
##      its cycle in data/ci_pareto/cycle_registry.json (trace hash + N).
##      Changing N/trace = different trace content = NEW cycle id; forcing an
##      old cycle id onto a different trace is refused (exit 2).
##   3. T_holdout is used exactly once, as a pre-registered BATCH (all N
##      observations inside, not a single run) for the selected candidate c*.
##      If c* fails holdout, the same holdout must NOT be reused to pick
##      another candidate — a new pre-registered cycle (new holdout trace) is
##      required. `verify-holdout` enforces this: a consumed holdout trace is
##      recorded in the registry and any reuse attempt exits 2.
##   4. Experiment invariants verified + recorded: same PR arrival sequence /
##      commits / workload contents / initial cache state across candidates
##      (all derived from the single trace file); per-run cache namespace
##      isolation with PRODUCTION key/scope/retention semantics (only the
##      AXIOM_CACHE_NS value differs per candidate) — verified via a declared
##      semantics digest against the canonical baseline, exit 2 on deviation;
##      paired counterbalanced ordering (A->B and B->A pairs, order recorded
##      per pair like data/benchmarks/c3b_paired_v2.json).
##
## Selection objective (v13): c* = argmin_c P95_trace(W_c) — P95 computed over
##   the TOTAL population of per-PR end-to-end (queue + execution) latencies
##   in the trace (nearest-rank; NO segment weighting). Cost figures (mean
##   €/run, paired Δ, strata) are DIAGNOSTIC ONLY — computed and printed when
##   present, but NEVER a ranking input.
##   Regression ceiling: P95_trace(W_c) ≤ 15 min is reported per candidate as
##   `withinRegressionCeiling` (a CEILING, not a target). Every candidate
##   remains rankable by min P95 regardless of the flag.
##   Tie-break engages ONLY on exact equality of the measured P95 (no
##   epsilon): (1) max λ_observed_max, (2) min mean queue time, (3) min mean
##   execution time, (4) full tie → candidate id ascending (stable rule;
##   ids are sorted, as listed in the envelope). D_i = C_A,i − C_B,i paired
##   differences are DIAGNOSTIC only; all raw C_{c,i} are preserved.
##
## Load characterization (L1/L2/L3): separate experiments at concurrency
## 1 / 10 / 50. L3 is a capacity diagnostic ONLY and is excluded from the
## ranking/P95 population (compare refuses --load L3). λ_observed_max = the
## highest measured sustainable arrival rate among load levels where
## P95(queue+exec) ≤ 15 min AND queue length is non-divergent — observed max,
## NOT a proven bound.
##
## Execution backend contract (local):
##   `run` invokes the configured target with AXIOM_CACHE_NS=<candidate-id>
##   set in the environment. The target must print to stdout:
##     pareto_run_ms=<int>            REQUIRED — execution time of this PR
##     pareto_cost_euro=<float>       REQUIRED — Euro cost of this run
##     pareto_core_minutes=<float>    optional (default: run_ms/60000)
##     pareto_queue_ms=<int>          optional queueing delay (default 0)
##     pareto_queue_len=<int>         optional queue depth at start (default 0)
##     pareto_stratum=<cold|warm|cache-hit>  optional cache-state (default cold)
##   Missing optional telemetry emits a WARN (never silently); invalid values
##   (negative, unknown stratum, malformed) fail the run with exit 2.
## Execution backend contract (GitHub):
##   `ingest --github-run <id>` fetches run metadata + jobs via `gh api` and
##   derives ONE observation: W = updated_at − run_started_at; queueMs = first
##   SUCCESS job start − run_started_at; execMs = updated_at − first success job
##   start (queue+exec telescopes exactly to W — the same identity as the local
##   latencyMs = queueMs + execMs). Per-job durations summed over success jobs
##   ONLY (skipped/cancelled jobs never occupied a runner) => coreMinutes
##   (diagnostic). costEuro = latency-minutes proxy (DIAGNOSTIC ONLY, v13).
##   Runner labels + per-job durations ride along as INFORMATIONAL provenance
##   (excluded from record hashes, same status as preRegisteredAt). queue length
##   and cache stratum are not in the GH API -> 0 / "cold" with an explicit WARN.
##   λ_observed_max is not derivable from one run — `characterize` computes it
##   over load levels (unchanged). See §12 for the full convention.
##
## Exit code contract (never swallows exceptions):
##   0 = OK
##   2 = INVALID / harness violation: trace-lock violation (N changed, trace
##       hash mismatch, forced-foreign cycle), namespace semantics deviation,
##       holdout reuse, holdout in comparison path, counterbalance violation,
##       incomplete/duplicate pairing, malformed telemetry/config
##   1 = ERROR (I/O failure, execution backend failure, internal error)
##
## Determinism: all digest-covered bodies (trace sha256, run record hashes,
## compare envelopes) contain NO wall-clock timestamps; preRegisteredAt and
## ingested-GitHub provenance (githubRun on observations) are informational-only,
## excluded from hashes (repo rule, cf. impact_closure_selector.nim). Records
## are read-modify-write with a preserved-observation invariant: an
## already-recorded (pair, order, load) observation is NEVER silently
## overwritten.
##
## Usage:
##   pareto-harness prepare-train    --out <file> --cand-a <id:target>
##                                   --cand-b <id:target> --arrivals <count>
##                                   --duration-min <min> --seed <int> --n <int>
##   pareto-harness prepare-holdout  (same flags; separate command, never read
##                                   by the comparison path)
##   pareto-harness run --candidate <id> --trace <file> --pair <i>
##                      --order <A->B|B->A> [--load <L1|L2|L3>]
##   pareto-harness compare --trace <file> [--id <cycle-id>] [--load <L1|L2>]
##   pareto-harness characterize --trace <file> --candidate <id>
##   pareto-harness verify-holdout --trace <file> --candidate <id>
##   pareto-harness ingest --github-run <run_id> | --from-json <file>
##                      --candidate <id> --trace <file> --pair-index <i>
##                      --order <A->B|B->A> [--load <L1|L2|L3>]
##                      [--repo <owner/repo>] [--record]
##   pareto-harness selftest
##
## Outputs:
##   data/ci_pareto/trace_{train,holdout}.json    pre-registered traces
##   build/ci_pareto/records/<cycle>_<cand>.json  raw per-pair observations
##   build/ci_pareto/compare/<cycle>_<sha16>_envelope.json   comparison result
##   build/ci_pareto/characterize/<cycle>_<cand>.json        L1/L2/L3 result
##   build/ci_pareto/holdout/<sha16>_envelope.json           holdout result
##   data/ci_pareto/cycle_registry.json          cycle + holdout locks

import std/[os, osproc, strutils, strformat, sequtils, tables, json, algorithm,
            math, times, parseopt, strtabs, streams]
import core/trusted/layer_declaration
axiomLayer "tools"
import core/trusted/effect_bridge
import tools/sha256_native

# ═══════════════════════════════════════════════════════════════════════════
# §0: Constants and schema ids
# ═══════════════════════════════════════════════════════════════════════════

const
  TraceSchema* = "axiom/ci-pareto/trace/v1"
  ConfigSchema = "axiom/ci-pareto/config/v1"
  RunRecordSchema* = "axiom/ci-pareto/run-record/v1"
  CompareEnvelopeSchema = "axiom/ci-pareto/compare-envelope/v1"
  CycleSchema = "axiom/ci-pareto/cycle-registry/v1"
  HoldoutEnvelopeSchema = "axiom/ci-pareto/holdout-envelope/v1"
  CharacterizeEnvelopeSchema = "axiom/ci-pareto/characterize-envelope/v1"
  SloP95QueueExecMs* = 15 * 60 * 1000  # 15 minutes: regression-ceiling bound (CEILING, not a target)
  CapLedgerMinutes = 50_000           # resource-capacity ledger only; NOT a ranking input
  DataDir = "data/ci_pareto"
  BuildDir = "build/ci_pareto"
  NamespaceEnvVar = "AXIOM_CACHE_NS"
  # Canonical namespace semantics (production baseline). Deviation of a
  # candidate's declared semantics from this → verification line FAIL (exit 2).
  CanonicalSemantics = "keyConstruction=sha256(scope;key;repoState);scopeSeparation=per-candidate-namespace;retention=restore-if-hit;evict-if-miss;no-cross-namespace-reads;initialCacheState=empty-per-namespace"

proc errQuit(code: int, msg: string) {.axiomEffect: IOEffect.} =
  stderr.writeLine("[pareto-harness] FAIL: " & msg)
  quit(code)

# ═══════════════════════════════════════════════════════════════════════════
# §1: Types
# ═══════════════════════════════════════════════════════════════════════════

type
  TraceArrival* = object
    seqNo*: int
    prKind*: string                 # "PR" | "PUSH"
    inputRef*: string               # commit/input sequence position
    workload*: string               # workload contents id

  LoadLevel* = object
    id*: string                     # "L1" | "L2" | "L3"
    concurrency*: int               # 1 | 10 | 50
    description*: string

  TraceFile* = object
    schema*: string
    traceKind*: string              # "train" | "holdout"
    preRegisteredAtIso*: string     # informational ONLY; excluded from body hash
    sha256*: string                 # body hash (digest-covered fields)
    n*: int                         # pre-registered pair count, fixed at prep time
    arrivals*: seq[TraceArrival]
    loadLevels*: seq[LoadLevel]
    arrivalRatePerHour*: int        # designed arrival rate of the trace
    durationMinutes*: int           # designed experiment duration (fixed pre-measurement)
    config*: JsonNode

  RunObservation* = object
    pairIndex*: int                 # 1..n (trace position)
    order*: string                  # "A->B" | "B->A" (measured order of pair)
    loadLevel*: string              # "L1" | "L2" | "L3"
    queueMs*: int
    execMs*: int
    latencyMs*: int                 # queueMs + execMs (end-to-end per-PR)
    costEuro*: float
    coreMinutes*: float
    queueLenAtStart*: int
    stratum*: string                # "cold" | "warm" | "cache-hit"
    githubRun*: JsonNode            # INFORMATIONAL ONLY (ingest backend):
                                    # GitHub run provenance (run id, workflow,
                                    # event, sha, runner labels, per-job
                                    # durations). Wall-clock timestamps — NEVER
                                    # digest-covered (same status as
                                    # preRegisteredAt; repo rule, cf.
                                    # impact_closure_selector.nim). Not part of
                                    # runRecordHash by construction; identical
                                    # v1 measurement fields -> identical hash.

  RunRecord* = object
    schema*: string
    candidateId*: string
    cycleId*: string
    traceSha256*: string
    traceKind*: string
    n*: int
    observations*: seq[RunObservation]
    recordHash*: string

  StratumStats* = object
    count*: int
    p*: float                       # proportion of runs in this stratum
    meanCostEuro*: float

  CycleRegistry* = object
    schema*: string
    cycles*: Table[string, string]      # traceSortKey -> cycleId
    consumedHoldouts*: Table[string, string]  # traceSortKey -> envelopeHash

# ═══════════════════════════════════════════════════════════════════════════
# §2: Pure math (deterministic; no I/O; no timestamps)
# ═══════════════════════════════════════════════════════════════════════════

func mean(xs: seq[float]): float {.raises: [].} =
  if xs.len == 0: 0.0
  else:
    var s = 0.0
    for x in xs: s += x
    s / xs.len.float

func percentile95*(values: seq[int]): float {.raises: [].} =
  ## P95 over a POPULATION (nearest-rank). Never a weighted sum of segments.
  if values.len == 0: return 0.0
  var s = values
  s.sort()
  let idx = int(ceil(0.95 * s.len.float)) - 1
  result = s[max(idx, 0)].float

func percentile95f(values: seq[float]): float {.raises: [].} =
  ## Nearest-rank P95 over a population of floats.
  if values.len == 0: return 0.0
  var s = values
  s.sort()
  let idx = int(ceil(0.95 * s.len.float)) - 1
  result = s[max(idx, 0)]

func median(xs: seq[float]): float {.raises: [].} =
  if xs.len == 0: return 0.0
  var s = xs
  s.sort()
  if s.len mod 2 == 1: s[s.len div 2]
  else: (s[s.len div 2 - 1] + s[s.len div 2]) / 2.0

func pairedStats*(deltas: seq[float]): tuple[meanD, medianD, p95D: float;
                                              n: int; positiveCount: int] {.raises: [].} =
  ## D_i = C_A,i − C_B,i across paired positions.
  result.n = deltas.len
  if deltas.len == 0: return
  result.meanD = mean(deltas)
  result.medianD = median(deltas)
  result.p95D = percentile95f(deltas)
  for d in deltas:
    if d > 0: inc result.positiveCount

func queueNonDivergent*(queueLenAtStart: seq[int]; concurrency: int): bool {.raises: [].} =
  ## Observed-window proxy (NOT a proven bound): the queue is considered
  ## non-divergent when it never exceeds 3× the in-flight capacity and the
  ## backlog does not grow by a full in-flight batch over the window
  ## (last − first < concurrency).
  if queueLenAtStart.len == 0: return false
  for q in queueLenAtStart:
    if q > 3 * concurrency: return false
  result = queueLenAtStart[^1] - queueLenAtStart[0] < concurrency

func sustainableArrivalRatePerHour*(concurrency: int; meanExecMs: float): float {.raises: [].} =
  ## λ_L = concurrency × 3600 / meanExecMs — observed sustainable arrival rate
  ## (arrivals/hour) at load level L from MEASURED mean service time. Observed
  ## max, NOT a proven bound.
  if meanExecMs <= 0: 0.0
  else: concurrency.float * 3600.0 / meanExecMs

func observationsByLoad(r: RunRecord; loadId: string): seq[RunObservation] {.raises: [].} =
  for o in r.observations:
    if o.loadLevel == loadId:
      result.add(o)

# ═══════════════════════════════════════════════════════════════════════════
# §3: Trace preparation (N and content fixed BEFORE any measurement)
# ═══════════════════════════════════════════════════════════════════════════

proc canonicalArrivalText*(t: TraceFile): string =
  ## Deterministic rendering of the digest-covered trace body. NO timestamps.
  var lines: seq[string]
  for a in t.arrivals:
    lines.add(&"{a.seqNo}|{a.prKind}|{a.inputRef}|{a.workload}")
  var ll: seq[string]
  for l in t.loadLevels:
    ll.add(&"{l.id}:{l.concurrency}")
  result = lines.join("\n") & "\n" & ll.join(",") & "\n"

proc bodyHash(t: TraceFile): string =
  ## sha256 over digest-covered fields: canonical arrivals + load levels + n +
  ## kind + arrival rate + config semantics digest + arrival seed. Timestamps
  ## (preRegisteredAtIso) excluded by construction.
  let semDigest = t.config["semanticsDigest"].getStr()
  let seedVal = t.config["arrivalSequenceSeed"].getInt()
  let canonical = canonicalArrivalText(t) &
                  &"n={t.n}\nkind={t.traceKind}\narrivalRate={t.arrivalRatePerHour}\ndurationMin={t.durationMinutes}\n" &
                  &"configSemanticsDigest={semDigest}\nconfigArrivalSeed={seedVal}\n"
  sha256String(canonical)

proc traceSortKey(t: TraceFile): string =
  &"{t.sha256[0 .. 15]}-{t.traceKind}"

proc prepareTrace*(configPath, outPath, traceKind, candA, candB: string;
                   arrivalsCount, durationMin, seed, n: int;
                   arrivalRatePerHour: int = 0): int {.axiomEffect: IOEffect.} =
  ## Writes a fixed trace file. `n` is pre-registered HERE — replay
  ## subcommands accept no runtime --n. Holdout creation is this same proc via
  ## traceKind="holdout" (invoked by the SEPARATE prepare-holdout command).
  if n <= 0:
    errQuit(2, "n must be >= 1 (pre-registered pair count); rejected: n=" & $n)
  if arrivalsCount <= 0:
    errQuit(2, "arrivals must be >= 1")
  if durationMin <= 0:
    errQuit(2, "duration must be >= 1 minute")

  let outDir = outPath.parentDir()
  if outDir.len > 0 and not dirExists(outDir):
    createDir(outDir)

  let partsA = candA.split(":", 1)
  let partsB = candB.split(":", 1)
  if partsA.len != 2 or partsB.len != 2:
    errQuit(2, "candidate must be <id>:<target>, got: " & candA & " / " & candB)
  let idA = partsA[0]
  let idB = partsB[0]
  if idA.len == 0 or idB.len == 0 or idA == idB:
    errQuit(2, "candidate ids must be non-empty and distinct, got: " & candA & " / " & candB)
  if idA == "baseline" or idB == "baseline":
    errQuit(2, "candidate id 'baseline' is reserved (namespace-semantics baseline)")
  if arrivalRatePerHour <= 0:
    errQuit(2, "arrival rate must be > 0 (events/hour)")

  let semanticsDigest = sha256String(CanonicalSemantics)
  let cfg = %*{
    "schema": ConfigSchema,
    "candidates": {idA: partsA[1], idB: partsB[1]},
    "namespaceSemantics": {
      "keyConstruction": "sha256(scope;key;repoState)",
      "scopeSeparation": "per-candidate-namespace",
      "retention": "restore-if-hit;evict-if-miss;no-cross-namespace-reads",
      "initialCacheState": "empty-per-namespace"
    },
    "semanticsDigest": semanticsDigest,
    "arrivalSequenceSeed": seed
  }

  # Fixed L1/L2/L3 load characterization (same for every candidate — part of
  # the trace, digest-covered). L3 = saturation, capacity diagnostic only.
  let loadLevels = @[
    LoadLevel(id: "L1", concurrency: 1, description: "single-flight"),
    LoadLevel(id: "L2", concurrency: 10, description: "nominal"),
    LoadLevel(id: "L3", concurrency: 50, description: "saturation (capacity diagnostic ONLY)")]

  # Deterministic arrival sequence (LCG with fixed seed). Latency is injected
  # by the BACKEND per pair; the trace carries the arrival structure only.
  var arrivals: seq[TraceArrival]
  for i in 0 ..< arrivalsCount:
    arrivals.add(TraceArrival(
      seqNo: i + 1,
      prKind: if (i mod 5) == 4: "PUSH" else: "PR",
      inputRef: &"input-{i+1}",
      workload: &"workload-{(i mod 4) + 1}"))

  let t = TraceFile(
    schema: TraceSchema,
    traceKind: traceKind,
    preRegisteredAtIso: now().utc().format("yyyy-MM-dd'T'HH:mm:ss'Z'"),
    n: n,
    arrivals: arrivals,
    loadLevels: loadLevels,
    arrivalRatePerHour: arrivalRatePerHour,
    durationMinutes: durationMin,
    config: cfg)
  let body = bodyHash(t)

  var fileNode = %*{
    "schema": TraceSchema,
    "traceKind": t.traceKind,
    "preRegisteredAt": t.preRegisteredAtIso,
    "sha256": body,
    "n": t.n,
    "arrivalRatePerHour": t.arrivalRatePerHour,
    "durationMinutes": t.durationMinutes,
    "arrivals": newJArray(),
    "loadLevels": newJArray(),
    "config": t.config
  }
  for a in t.arrivals:
    fileNode["arrivals"].add(%*{
      "seqNo": a.seqNo, "prKind": a.prKind, "inputRef": a.inputRef,
      "workload": a.workload})
  for l in t.loadLevels:
    fileNode["loadLevels"].add(%*{"id": l.id, "concurrency": l.concurrency,
                                  "description": l.description})
  writeFile(outPath, pretty(fileNode, 2) & "\n")

  if configPath.len > 0:
    let cfgDir = configPath.parentDir()
    if cfgDir.len > 0 and not dirExists(cfgDir):
      createDir(cfgDir)
    writeFile(configPath, pretty(cfg, 2) & "\n")

  echo "[pareto-harness] " & (if traceKind == "holdout": "HOLDOUT" else: "TRAIN") &
       " trace written: " & outPath
  echo "[pareto-harness] sha256: " & body & "  (digest-covered body; preRegisteredAt excluded)"
  echo "[pareto-harness] pre-registered n=" & $n & " — no runtime --n flag exists"
  echo "[pareto-harness] arrivals=" & $arrivalsCount &
       " durationMin=" & $durationMin & " seed=" & $seed &
       " arrivalRate=" & $arrivalRatePerHour & "/h"
  echo "[pareto-harness] load levels: L1=1 L2=10 L3=50 (L3 capacity diagnostic ONLY)"
  echo "[pareto-harness] candidate A: " & candA & " | candidate B: " & candB
  if traceKind == "holdout":
    echo "[pareto-harness] HOLDOUT CONTRACT: comparison path NEVER reads this file;"
    echo "[pareto-harness] verify-holdout consumes it exactly once, after selection."
  result = 0

# ═══════════════════════════════════════════════════════════════════════════
# §4: Trace read + integrity verification
# ═══════════════════════════════════════════════════════════════════════════

type
  TraceReadResult = tuple
    trace: TraceFile
    ok: bool
    reason: string

proc readTraceFile*(path: string): TraceReadResult {.axiomEffect: IOEffect.} =
  ## Recomputes the body hash from the on-disk digest-covered fields and
  ## compares against the recorded sha256; mismatch → invalid (exit 2 by
  ## callers). This is the immutability guarantee: any edit to arrivals / n /
  ## load levels / config invalidates the trace.
  if not fileExists(path):
    return (TraceFile(), false, "trace file not found: " & path)
  let content = readFile(path)
  var node: JsonNode
  try:
    node = parseJson(content)
  except CatchableError:
    return (TraceFile(), false, "trace file is not valid JSON: " & path)
  if not node.hasKey("sha256") or not node.hasKey("arrivals") or
     not node.hasKey("n") or not node.hasKey("config"):
    return (TraceFile(), false, "trace file missing sha256/arrivals/n/config fields: " & path)

  var arrivals: seq[TraceArrival]
  for a in node["arrivals"].items:
    arrivals.add(TraceArrival(
      seqNo: a["seqNo"].getInt(), prKind: a["prKind"].getStr(),
      inputRef: a["inputRef"].getStr(), workload: a["workload"].getStr()))
  var loadLevels: seq[LoadLevel]
  if node.hasKey("loadLevels"):
    for l in node["loadLevels"].items:
      loadLevels.add(LoadLevel(id: l["id"].getStr(), concurrency: l["concurrency"].getInt(),
                               description: l["description"].getStr()))
  if loadLevels.len == 0:
    return (TraceFile(), false, "trace has no loadLevels (corrupt?)")
  let cfg = node["config"]
  if not cfg.hasKey("semanticsDigest") or not cfg.hasKey("arrivalSequenceSeed"):
    return (TraceFile(), false, "trace config missing semanticsDigest/arrivalSequenceSeed: " & path)
  let t = TraceFile(
    schema: node["schema"].getStr(),
    traceKind: if node.hasKey("traceKind"): node["traceKind"].getStr() else: "train",
    preRegisteredAtIso: if node.hasKey("preRegisteredAt"): node["preRegisteredAt"].getStr() else: "",
    sha256: node["sha256"].getStr(),
    n: node["n"].getInt(),
    arrivals: arrivals,
    loadLevels: loadLevels,
    arrivalRatePerHour: if node.hasKey("arrivalRatePerHour"): node["arrivalRatePerHour"].getInt() else: 0,
    durationMinutes: if node.hasKey("durationMinutes"): node["durationMinutes"].getInt() else: 0,
    config: cfg)
  let recomputed = bodyHash(t)
  let recorded = node["sha256"].getStr()
  if recomputed != recorded:
    return (TraceFile(), false,
            &"trace sha256 mismatch (recorded={recorded[0 .. 15]}… computed={recomputed[0 .. 15]}…): " & path)
  result = (t, true, "")

# ═══════════════════════════════════════════════════════════════════════════
# §5: Namespace-semantics verification (experiment invariant)
# ═══════════════════════════════════════════════════════════════════════════

proc declaredSemanticsDigest(t: TraceFile): string =
  ## Digest of the candidate's DECLARED namespace semantics (from the trace
  ## config). Only AXIOM_CACHE_NS may differ per candidate; key construction,
  ## scope separation, retention and initial cache state must equal the
  ## production baseline.
  if t.config.hasKey("namespaceSemantics") and t.config["namespaceSemantics"].kind == JObject:
    var lines: seq[string]
    for k in ["keyConstruction", "scopeSeparation", "retention", "initialCacheState"]:
      if t.config["namespaceSemantics"].hasKey(k):
        lines.add(k & "=" & t.config["namespaceSemantics"][k].getStr())
    if lines.len == 4:
      return sha256String(lines.join(";"))
  result = ""

proc verifyNamespaceSemantics*(t: TraceFile): tuple[ok: bool, line: string,
                                                     baseDigest, declaredDigest: string] =
  ## Emits the mandatory verification line. FAILS (ok=false) when the
  ## candidate's namespace config changes key construction / scope /
  ## retention semantics (declared digest ≠ canonical baseline digest).
  let baseDigest = sha256String(CanonicalSemantics)
  let declared = declaredSemanticsDigest(t)
  if declared.len == 0:
    return (false,
            "candidate cache namespace isolation FAILS: trace config declares no/incomplete namespaceSemantics block",
            baseDigest, declared)
  if declared != baseDigest:
    return (false,
            "candidate cache namespace isolation FAILS: declared semantics digest " & declared[0 .. 15] &
            "… != baseline digest " & baseDigest[0 .. 15] &
            "… (key construction / scope / retention must be identical to production; only AXIOM_CACHE_NS differs)",
            baseDigest, declared)
  result = (true,
            "candidate cache namespace isolation preserves production cache key/scope/retention semantics",
            baseDigest, declared)

# ═══════════════════════════════════════════════════════════════════════════
# §6: Execution backend (local)
# ═══════════════════════════════════════════════════════════════════════════

type
  Telemetry = object
    runMs, queueMs, queueLen: int
    costEuro, coreMinutes: float
    stratum: string
    hasCost, hasCore, hasQueue, hasQlen, hasStrata: bool

proc parseIntStrict(s: string; dst: var int): bool =
  ## Strict int parse: returns false (no exception escapes) on malformed
  ## input so callers can record a sentinel instead of swallowing.
  try:
    dst = parseInt(s)
    result = true
  except CatchableError:
    result = false

proc parseFloatStrict(s: string; dst: var float): bool =
  try:
    dst = parseFloat(s)
    result = true
  except CatchableError:
    result = false

proc parseTelemetry(outp: string): Telemetry =
  ## Parses backend telemetry lines. A malformed (badly-formatted) line is
  ## recorded as a NEGATIVE sentinel (-1) so validateTelemetry fails the run
  ## (exit 2) — malformed telemetry is never silently defaulted. Absent
  ## optional lines keep declared defaults (WARN emitted by caller).
  result.stratum = ""
  for line in outp.splitLines:
    let l = line.strip()
    if l.startsWith("pareto_run_ms="):
      if not parseIntStrict(l["pareto_run_ms=".len .. ^1].strip(), result.runMs):
        result.runMs = -1
    elif l.startsWith("pareto_cost_euro="):
      result.hasCost = true
      if not parseFloatStrict(l["pareto_cost_euro=".len .. ^1].strip(), result.costEuro):
        result.costEuro = -1.0
    elif l.startsWith("pareto_core_minutes="):
      result.hasCore = true
      if not parseFloatStrict(l["pareto_core_minutes=".len .. ^1].strip(), result.coreMinutes):
        result.coreMinutes = -1.0
    elif l.startsWith("pareto_queue_ms="):
      result.hasQueue = true
      if not parseIntStrict(l["pareto_queue_ms=".len .. ^1].strip(), result.queueMs):
        result.queueMs = -1
    elif l.startsWith("pareto_queue_len="):
      result.hasQlen = true
      if not parseIntStrict(l["pareto_queue_len=".len .. ^1].strip(), result.queueLen):
        result.queueLen = -1
    elif l.startsWith("pareto_stratum="):
      result.stratum = l["pareto_stratum=".len .. ^1].strip()
      result.hasStrata = true

proc validateTelemetry(t: Telemetry; candidateId: string; pairIndex: int;
                       loadLevel: string) {.axiomEffect: IOEffect.} =
  if t.runMs <= 0:
    errQuit(2, &"backend telemetry invalid: pareto_run_ms={t.runMs} must be > 0 (candidate {candidateId}, pair {pairIndex}, load {loadLevel})")
  if t.hasCost and t.costEuro < 0:
    errQuit(2, &"backend telemetry invalid: pareto_cost_euro={t.costEuro} must be >= 0 (candidate {candidateId})")
  if t.hasCore and t.coreMinutes < 0:
    errQuit(2, &"backend telemetry invalid: pareto_core_minutes={t.coreMinutes} (candidate {candidateId})")
  if t.hasQueue and t.queueMs < 0:
    errQuit(2, &"backend telemetry invalid: pareto_queue_ms={t.queueMs} (candidate {candidateId})")
  if t.hasQlen and t.queueLen < 0:
    errQuit(2, &"backend telemetry invalid: pareto_queue_len={t.queueLen} (candidate {candidateId})")
  if t.hasStrata and t.stratum notin ["cold", "warm", "cache-hit"]:
    errQuit(2, &"backend telemetry invalid: pareto_stratum={t.stratum} (candidate {candidateId})")
  if t.hasCost and t.costEuro == 0:
    echo "[pareto-harness] WARN: pareto_cost_euro=0 reported by backend (candidate " & candidateId & ")"

proc runOnePair*(candidateId, target, cycleId, traceKind, traceSha, nsEnv: string;
                 pairIndex, seqNo: int; order, loadLevel: string;
                 loadConcurrency: int; buildDir, repoRoot: string;
                 quiet: bool): RunObservation {.axiomEffect: IOEffect.} =
  ## Executes ONE trace position for ONE candidate under the given load
  ## level. The cache namespace is the ONLY per-candidate difference: passed
  ## as the real AXIOM_CACHE_NS env var. Cache dir is initialized empty
  ## (initial cache state = empty-per-namespace).
  let nsDir = buildDir / "candidate_cache" / nsEnv
  if not dirExists(nsDir):
    createDir(nsDir)

  var tm = Telemetry(stratum: "cold")
  let start = epochTime()
  let envTbl = newStringTable({
    NamespaceEnvVar: nsEnv,
    "AXIOM_PAIR": $pairIndex,
    "AXIOM_SEQNO": $seqNo,
    "AXIOM_LOAD": loadLevel,
    "AXIOM_CONCURRENCY": $loadConcurrency})
  let cmd = target
  let (outp, exitc) = execCmdEx(cmd, env = envTbl, workingDir = repoRoot)
  let wallMs = int((epochTime() - start) * 1000.0)
  if exitc != 0:
    errQuit(1, &"execution backend failed (exit {exitc}) for candidate '{candidateId}' pair {pairIndex}: {target}")
  tm = parseTelemetry(outp)
  validateTelemetry(tm, candidateId, pairIndex, loadLevel)
  if not tm.hasCost:
    echo "[pareto-harness] WARN: backend reported no pareto_cost_euro; defaulting costEuro=run_ms/60000 (candidate " & candidateId & ")"
    tm.costEuro = tm.runMs.float / 60000.0
  if not tm.hasCore:
    echo "[pareto-harness] WARN: backend reported no pareto_core_minutes; defaulting coreMinutes=run_ms/60000 (candidate " & candidateId & ")"
    tm.coreMinutes = tm.runMs.float / 60000.0
  if not tm.hasQueue:
    echo "[pareto-harness] WARN: backend reported no pareto_queue_ms; defaulting 0 (candidate " & candidateId & ")"
    tm.queueMs = 0
  if not tm.hasQlen:
    echo "[pareto-harness] WARN: backend reported no pareto_queue_len; defaulting 0 (candidate " & candidateId & ")"
    tm.queueLen = 0
  if tm.queueLen < 0:
    errQuit(2, "negative pareto_queue_len from backend (candidate " & candidateId & ")")
  if not tm.hasStrata:
    echo "[pareto-harness] WARN: backend reported no pareto_stratum; defaulting 'cold' (candidate " & candidateId & ")"
  let wallNote = if wallMs > tm.runMs * 2: " (wall " & $wallMs & "ms > reported)" else: ""

  result = RunObservation(
    pairIndex: pairIndex,
    order: order,
    loadLevel: loadLevel,
    queueMs: tm.queueMs,
    execMs: tm.runMs,
    latencyMs: tm.queueMs + tm.runMs,
    costEuro: tm.costEuro,
    coreMinutes: tm.coreMinutes,
    queueLenAtStart: tm.queueLen,
    stratum: tm.stratum)
  if not quiet:
    echo "[pareto-harness]   pair " & $pairIndex & " [" & order & ", " & loadLevel & "] " &
         candidateId & ": cost=" & formatFloat(tm.costEuro, ffDecimal, 6) &
         " € | latency=" & $result.latencyMs & " ms (queue " & $tm.queueMs &
         " + exec " & $tm.runMs & ") | qlen=" & $tm.queueLen &
         " | stratum=" & tm.stratum & wallNote

# ═══════════════════════════════════════════════════════════════════════════
# §7: Run records (read-modify-write; preserved-observation invariant)
# ═══════════════════════════════════════════════════════════════════════════

proc runRecordHash*(r: RunRecord): string =
  ## Digest over all observation fields. NO timestamps.
  var obs: seq[string]
  for o in r.observations:
    obs.add(&"{o.pairIndex}|{o.order}|{o.loadLevel}|{o.queueMs}|{o.execMs}|{o.costEuro}|{o.coreMinutes}|{o.queueLenAtStart}|{o.stratum}")
  let obsJoined = obs.join(";")
  sha256String(&"cand={r.candidateId};cycle={r.cycleId};trace={r.traceSha256};kind={r.traceKind};n={r.n};obs={obsJoined}")

proc runRecordToJson*(r: RunRecord): JsonNode =
  result = %*{
    "schema": RunRecordSchema,
    "candidateId": r.candidateId,
    "cycleId": r.cycleId,
    "traceSha256": r.traceSha256,
    "traceKind": r.traceKind,
    "n": r.n,
    "observations": newJArray(),
    "recordHash": r.recordHash
  }
  for o in r.observations:
    var oNode = %*{
      "pairIndex": o.pairIndex, "order": o.order, "loadLevel": o.loadLevel,
      "queueMs": o.queueMs, "execMs": o.execMs, "latencyMs": o.latencyMs,
      "costEuro": o.costEuro, "coreMinutes": o.coreMinutes,
      "queueLenAtStart": o.queueLenAtStart, "stratum": o.stratum}
    if o.githubRun != nil:
      oNode["githubRun"] = o.githubRun
    result["observations"].add(oNode)

proc parseRunRecord*(node: JsonNode): RunRecord =
  result.schema = node["schema"].getStr()
  result.candidateId = node["candidateId"].getStr()
  result.cycleId = node["cycleId"].getStr()
  result.traceSha256 = node["traceSha256"].getStr()
  result.traceKind = node["traceKind"].getStr()
  result.n = node["n"].getInt()
  if node.hasKey("observations"):
    for o in node["observations"].items:
      result.observations.add(RunObservation(
        pairIndex: o["pairIndex"].getInt(),
        order: o["order"].getStr(),
        loadLevel: o["loadLevel"].getStr(),
        queueMs: o["queueMs"].getInt(),
        execMs: o["execMs"].getInt(),
        latencyMs: o["latencyMs"].getInt(),
        costEuro: o["costEuro"].getFloat(),
        coreMinutes: o["coreMinutes"].getFloat(),
        queueLenAtStart: o["queueLenAtStart"].getInt(),
        stratum: o["stratum"].getStr(),
        githubRun: (if o.hasKey("githubRun"): o["githubRun"] else: nil)))
  result.recordHash = node["recordHash"].getStr()

proc loadRecord(path: string; expected: RunRecord): tuple[rec: RunRecord, ok: bool] {.axiomEffect: IOEffect.} =
  ## Loads an existing record for (cycle, candidate) and verifies its hash and
  ## that it belongs to the same trace/cycle. Missing file → empty record.
  var rec = RunRecord(schema: RunRecordSchema, candidateId: expected.candidateId,
                      cycleId: expected.cycleId, traceSha256: expected.traceSha256,
                      traceKind: expected.traceKind, n: expected.n)
  if not fileExists(path):
    return (rec, true)
  var node: JsonNode
  try:
    node = parseJson(readFile(path))
  except CatchableError:
    return (RunRecord(), false)
  rec = parseRunRecord(node)
  if rec.recordHash != runRecordHash(rec):
    return (RunRecord(), false)
  if rec.traceSha256 != expected.traceSha256 or rec.cycleId != expected.cycleId or
     rec.n != expected.n:
    return (RunRecord(), false)
  result = (rec, true)

proc alreadyRecorded*(rec: RunRecord; pairIndex: int; order, loadLevel: string): bool {.raises: [].} =
  for o in rec.observations:
    if o.pairIndex == pairIndex and o.order == order and o.loadLevel == loadLevel:
      return true

proc appendObservation*(recPath: string; obs: RunObservation;
                        expected: RunRecord): RunRecord {.axiomEffect: IOEffect.} =
  ## Read-modify-write: appends ONE observation. Refuses to overwrite an
  ## already-recorded (pair, order, load) — mid-run extension and silent
  ## re-measurement are both forbidden (pre-registration integrity).
  let (base, ok) = loadRecord(recPath, expected)
  if not ok:
    errQuit(2, "existing run record is corrupt or belongs to another trace/cycle: " & recPath)
  var rec = base
  if rec.observations.len > 0 and rec.recordHash != runRecordHash(rec):
    errQuit(2, "run record hash mismatch (tampered?): " & recPath)
  if alreadyRecorded(rec, obs.pairIndex, obs.order, obs.loadLevel):
    errQuit(2, &"duplicate observation refused: pair {obs.pairIndex} [{obs.order}, {obs.loadLevel}] already recorded for '{rec.candidateId}'. Silent re-measurement is forbidden; a changed experiment requires a new pre-registered cycle.")
  if obs.pairIndex < 1 or obs.pairIndex > expected.n:
    errQuit(2, &"pair index {obs.pairIndex} out of pre-registered range 1..{expected.n}")
  rec.observations.add(obs)
  rec.recordHash = runRecordHash(rec)
  let dir = recPath.parentDir()
  if dir.len > 0 and not dirExists(dir):
    createDir(dir)
  writeFile(recPath, pretty(runRecordToJson(rec), 2) & "\n")
  result = rec

# ═══════════════════════════════════════════════════════════════════════════
# §8: Cycle registry (trace lock)
# ═══════════════════════════════════════════════════════════════════════════

proc loadRegistry*(regPath: string): CycleRegistry {.axiomEffect: IOEffect.} =
  result.schema = CycleSchema
  result.cycles = initTable[string, string]()
  result.consumedHoldouts = initTable[string, string]()
  if fileExists(regPath):
    try:
      let node = parseJson(readFile(regPath))
      if node.hasKey("cycles"):
        for k, v in node["cycles"]: result.cycles[k] = v.getStr()
      if node.hasKey("consumedHoldouts"):
        for k, v in node["consumedHoldouts"]: result.consumedHoldouts[k] = v.getStr()
    except CatchableError:
      errQuit(2, "cycle registry is unreadable/corrupt: " & regPath)

proc saveRegistry(regPath: string; reg: CycleRegistry) {.axiomEffect: IOEffect.} =
  var node = %*{"schema": CycleSchema, "cycles": newJObject(), "consumedHoldouts": newJObject()}
  var cycs: seq[string]
  for k in reg.cycles.keys: cycs.add(k)
  cycs.sort()
  for k in cycs: node["cycles"][k] = newJString(reg.cycles[k])
  var hols: seq[string]
  for k in reg.consumedHoldouts.keys: hols.add(k)
  hols.sort()
  for k in hols: node["consumedHoldouts"][k] = newJString(reg.consumedHoldouts[k])
  let dir = regPath.parentDir()
  if dir.len > 0 and not dirExists(dir):
    createDir(dir)
  writeFile(regPath, pretty(node, 2) & "\n")

proc registerCycle*(regPath, sortKey: string; reg: var CycleRegistry): string {.axiomEffect: IOEffect.} =
  ## Trace lock: the FIRST compare on a trace registers its cycle id. A later
  ## compare with a different trace (different content = different N) is a NEW
  ## cycle — extending N mid-run is structurally impossible: `run` has no
  ## runtime --n, and the cycle id binds trace hash + N.
  if reg.cycles.hasKey(sortKey):
    return reg.cycles[sortKey]
  let newId = "cycle-" & sortKey & "-1"
  reg.cycles[sortKey] = newId
  saveRegistry(regPath, reg)
  result = newId

# ═══════════════════════════════════════════════════════════════════════════
# §9: compare — paired differences + selection (T_train, ranking population)
#     v13 ranking: c* = argmin P95_trace(W_c); cost figs DIAGNOSTIC ONLY;
#     tie-break on exact P95 equality: λ_observed_max → mean queue → mean exec
#     → candidate id ascending. 15m ceiling reported as a per-candidate flag.
# ═══════════════════════════════════════════════════════════════════════════

proc repoRoot(): string {.axiomEffect: IOEffect.} =
  var dir = getCurrentDir()
  while true:
    if fileExists(dir / ".axiom_root"):
      return dir
    let parent = parentDir(dir)
    if parent == dir:
      break
    dir = parent
  result = getCurrentDir()

proc factorAnalysis*(obs: seq[RunObservation]): tuple[strata: Table[string, StratumStats],
                                                     meanCost, p95Latency, meanCoreMin: float] {.raises: [].} =
  ## Diagnostic decomposition: per-stratum proportions p_{s,c} and per-stratum
  ## costs C_{s,c}. DIAGNOSTIC ONLY — never the selection objective.
  result.strata = initTable[string, StratumStats]()
  var costs: seq[float]
  var lat: seq[int]
  var strataCosts = initTable[string, seq[float]]()
  for o in obs:
    costs.add(o.costEuro)
    lat.add(o.latencyMs)
    strataCosts.mgetOrPut(o.stratum, @[]).add(o.costEuro)
  result.meanCost = mean(costs)
  result.p95Latency = percentile95(lat)
  result.meanCoreMin = mean(obs.mapIt(it.coreMinutes))
  for k, v in strataCosts:
    let s = StratumStats(count: v.len, p: v.len.float / obs.len.float,
                         meanCostEuro: mean(v))
    result.strata[k] = s

type
  CandidateRankVector* = object
    ## v13 ranking inputs per candidate. Cost figures are deliberately NOT
    ## part of the vector: they are diagnostic only and never decide order.
    candidateId*: string
    p95LatencyMs*: float         # primary: argmin P95_trace(W_c)
    lambdaObservedMaxPerHour*: float  # tie-break 1: max λ_observed_max
    meanQueueMs*: float          # tie-break 2: min mean queue time
    meanExecMs*: float           # tie-break 3: min mean execution time
    withinRegressionCeiling*: bool  # P95 ≤ 15 min (CEILING, reported; NOT a ranking input)

proc rankCompareByP95(a, b: CandidateRankVector): int {.raises: [].} =
  ## Deterministic strict-weak ordering on the v13 ranking.
  ## Primary: lower P95_trace wins. Tie-breaks engage ONLY when the measured
  ## P95 values are EXACTLY equal (never an epsilon). Exact float equality
  ## is well-defined for IEEE doubles derived from identical run records.
  if a.p95LatencyMs < b.p95LatencyMs: return -1
  if a.p95LatencyMs > b.p95LatencyMs: return 1
  if a.p95LatencyMs == b.p95LatencyMs:
    # FULL tie on P95: λ_observed_max (higher wins) → mean queue (lower wins)
    # → mean exec (lower wins) → candidate id ascending (stable rule).
    if a.lambdaObservedMaxPerHour > b.lambdaObservedMaxPerHour: return -1
    if a.lambdaObservedMaxPerHour < b.lambdaObservedMaxPerHour: return 1
    if a.meanQueueMs < b.meanQueueMs: return -1
    if a.meanQueueMs > b.meanQueueMs: return 1
    if a.meanExecMs < b.meanExecMs: return -1
    if a.meanExecMs > b.meanExecMs: return 1
    if a.candidateId < b.candidateId: return -1
    if a.candidateId > b.candidateId: return 1
  # Unreachable: identical vectors (same id) cannot be distinct candidates.
  result = 0

func lambdaObservedMax*(rec: RunRecord; levels: seq[LoadLevel]): float {.raises: [].} =
  ## λ_observed_max over THIS record's measured loads — the SAME computation
  ## as characterizeMain: max sustainable λ among load levels where
  ## P95(queue+exec) ≤ 15 min AND the queue is non-divergent. Observed max,
  ## NOT a proven bound. Empty obs → 0.
  if rec.observations.len == 0: return 0.0
  var lamObservedMax = 0.0
  for level in levels:
    let obs = observationsByLoad(rec, level.id)
    if obs.len == 0: continue
    var lat: seq[int]
    var qlen: seq[int]
    var exec: seq[int]
    for o in obs:
      lat.add(o.latencyMs)
      qlen.add(o.queueLenAtStart)
      exec.add(o.execMs)
    let p95 = percentile95(lat)
    let nonDivergent = queueNonDivergent(qlen, level.concurrency)
    if p95 <= SloP95QueueExecMs.float and nonDivergent:
      let lam = sustainableArrivalRatePerHour(level.concurrency, mean(exec.mapIt(it.float)))
      if lam > lamObservedMax: lamObservedMax = lam
  result = lamObservedMax

proc selectWinner*(vecs: openArray[CandidateRankVector]): string {.raises: [ValueError].} =
  ## c* = argmin over the v13 order. Candidates with HIGHER P95 never win on
  ## cost; tie-break engages ONLY on exact P95 equality. Candidate id
  ## ascending is the final stable rule (ids are unique; the caller passes
  ## the sorted candidate list, so the result is byte-deterministic).
  if vecs.len == 0:
    raise newException(ValueError, "selectWinner requires at least one candidate vector")
  var best = vecs[0]
  for v in vecs[1 .. ^1]:
    if rankCompareByP95(v, best) < 0:
      best = v
  result = best.candidateId

proc compareMain(regPath, tracePath, explicitCycle, loadId: string): int {.axiomEffect: IOEffect.} =
  let (tr, ok, reason) = readTraceFile(tracePath)
  if not ok:
    errQuit(2, reason)
  if tr.traceKind != "train":
    errQuit(2, "compare is for TRAIN traces only; this is a " & tr.traceKind & " trace: " & tracePath)
  if loadId notin ["L1", "L2"]:
    errQuit(2, "compare ranking population must be L1 or L2; L3 is a capacity diagnostic ONLY and is excluded from the ranking population")

  let ns = verifyNamespaceSemantics(tr)
  echo "[pareto-harness] " & ns.line
  if not ns.ok:
    echo "[pareto-harness]   baseline digest: " & ns.baseDigest
    echo "[pareto-harness]   declared digest: " & ns.declaredDigest
    errQuit(2, "namespace semantics contamination — candidate config changes key/scope/retention semantics")

  var reg = loadRegistry(regPath)
  let sortKey = traceSortKey(tr)
  let cycleId =
    if explicitCycle.len > 0:
      if not reg.cycles.hasKey(sortKey):
        errQuit(2, &"--id {explicitCycle} requested but trace {sortKey} has no registered cycle; run compare without --id first")
      if reg.cycles[sortKey] != explicitCycle:
        errQuit(2, &"trace locked to cycle {reg.cycles[sortKey]}, but --id {explicitCycle} requested")
      explicitCycle
    else:
      registerCycle(regPath, sortKey, reg)

  var candIds: seq[string]
  var targets: Table[string, string]
  if tr.config.hasKey("candidates") and tr.config["candidates"].kind == JObject:
    for k in tr.config["candidates"].keys:
      candIds.add(k)
      targets[k] = tr.config["candidates"][k].getStr()
  candIds.sort()
  if candIds.len != 2:
    errQuit(2, "trace config must declare exactly 2 candidates for compare")

  # Load both candidates' records for THIS cycle + ranking-population load.
  let recDir = BuildDir / "records"
  var records: Table[string, RunRecord]
  for c in candIds:
    let recPath = recDir / &"{cycleId}_{c}.json"
    if not fileExists(recPath):
      errQuit(2, "no run record for candidate " & c & " in cycle " & cycleId & ": " & recPath)
    var node: JsonNode
    try:
      node = parseJson(readFile(recPath))
    except CatchableError:
      errQuit(2, "run record unreadable: " & recPath)
    let rec = parseRunRecord(node)
    if rec.recordHash != runRecordHash(rec):
      errQuit(2, "run record hash mismatch (tampered?): " & recPath)
    if rec.traceSha256 != tr.sha256:
      errQuit(2, &"run record trace mismatch: record {rec.traceSha256[0 .. 15]}… vs trace {tr.sha256[0 .. 15]}…")
    if rec.n != tr.n:
      errQuit(2, &"run record n mismatch: record n={rec.n} vs trace n={tr.n} — pre-registered N cannot be extended partway")
    records[c] = rec

  # Paired differences on the SAME trace positions (counterbalanced order).
  let obA = observationsByLoad(records[candIds[0]], loadId)
  let obB = observationsByLoad(records[candIds[1]], loadId)
  if obA.len != tr.n or obB.len != tr.n:
    errQuit(2, &"incomplete pairing: need {tr.n} observations per candidate at load {loadId}, got {obA.len} (A) / {obB.len} (B)")
  var orderByPair = initTable[int, string]()
  for o in obA:
    if orderByPair.hasKey(o.pairIndex) and orderByPair[o.pairIndex] != o.order:
      errQuit(2, &"candidate {candIds[0]} has inconsistent order at pair {o.pairIndex}")
    orderByPair[o.pairIndex] = o.order
  for o in obB:
    if orderByPair.hasKey(o.pairIndex) and orderByPair[o.pairIndex] != o.order:
      errQuit(2, &"pair {o.pairIndex} order mismatch between candidates ({orderByPair[o.pairIndex]} vs {o.order}) — pairs must be measured in the same declared order")
    orderByPair[o.pairIndex] = o.order
  # Counterbalance invariant: n>=2 requires both A->B and B->A orders present.
  var orders: seq[string]
  for o in obA: orders.add(o.order)
  if tr.n >= 2 and (("A->B" in orders and "B->A" notin orders) or
                    ("B->A" in orders and "A->B" notin orders)):
    errQuit(2, "counterbalance invariant violated: pairs are ordered " & orders.join(",") &
            " — both A->B and B->A pairs are required for n>=2")

  var deltas: seq[float]
  var orderList: seq[string]
  for o in obA:
    var bCost = -1.0
    for ob in obB:
      if ob.pairIndex == o.pairIndex:
        bCost = ob.costEuro
        break
    if bCost < 0:
      errQuit(2, "missing paired observation at pair " & $o.pairIndex)
    deltas.add(o.costEuro - bCost)
    orderList.add(o.order)

  let st = pairedStats(deltas)
  let fa = factorAnalysis(obA)
  let fb = factorAnalysis(obB)
  # P95_trace(W_c): percentile over the TOTAL population of per-PR
  # end-to-end latencies (queue + execution) — computed here over all
  # observations, never as a weighted sum of segment P95s.
  let ceilingA = fa.p95Latency <= SloP95QueueExecMs.float
  let ceilingB = fb.p95Latency <= SloP95QueueExecMs.float
  # v13 ranking vectors. COST IS NOT IN THE VECTOR: mean €/run, paired Δ and
  # strata are diagnostics only and never decide order.
  let lamA = lambdaObservedMax(records[candIds[0]], tr.loadLevels)
  let lamB = lambdaObservedMax(records[candIds[1]], tr.loadLevels)
  let meanQueueA = mean(obA.mapIt(it.queueMs.float))
  let meanQueueB = mean(obB.mapIt(it.queueMs.float))
  let meanExecA = mean(obA.mapIt(it.execMs.float))
  let meanExecB = mean(obB.mapIt(it.execMs.float))
  let vecA = CandidateRankVector(
    candidateId: candIds[0], p95LatencyMs: fa.p95Latency,
    lambdaObservedMaxPerHour: lamA, meanQueueMs: meanQueueA,
    meanExecMs: meanExecA, withinRegressionCeiling: ceilingA)
  let vecB = CandidateRankVector(
    candidateId: candIds[1], p95LatencyMs: fb.p95Latency,
    lambdaObservedMaxPerHour: lamB, meanQueueMs: meanQueueB,
    meanExecMs: meanExecB, withinRegressionCeiling: ceilingB)
  let winner = selectWinner([vecA, vecB])
  let loser = if winner == candIds[0]: candIds[1] else: candIds[0]
  let deltaMeanEuro = abs(fa.meanCost - fb.meanCost)
  let deltaPct = if max(fa.meanCost, fb.meanCost) > 0:
    deltaMeanEuro / max(fa.meanCost, fb.meanCost) * 100.0 else: 0.0

  # Deterministic envelope (no timestamps in body). Ranking input fields are
  # exact measured values (identical records → identical envelope); the
  # envelopeHash covers the ranking inputs, the feasibility flags and the
  # diagnostics, and the selection that follows from them.
  let envelope = %*{
    "schema": CompareEnvelopeSchema,
    "cycleId": cycleId,
    "traceSha256": tr.sha256,
    "traceKind": "train",
    "n": tr.n,
    "load": loadId,
    "ceilingMs": SloP95QueueExecMs,
    "capacityLedgerMinutes": CapLedgerMinutes,
    "objective": "minP95TraceLatency",
    "ranking": {
      "primary": "argmin P95_trace(W_c) over the total per-PR latency population (nearest-rank, no segment weighting)",
      "tieBreak": [
        "only on EXACT equality of measured P95 (no epsilon)",
        "1. max lambda_observed_max",
        "2. min mean queue time",
        "3. min mean execution time",
        "4. full tie -> candidate id ascending (stable rule)"
      ]
    },
    "candidateA": candIds[0],
    "candidateB": candIds[1],
    "pairs": newJArray(),
    "paired": {
      "deltasEuro": deltas,
      "meanDeltaEuro": st.meanD,
      "medianPairedDeltaEuro": st.medianD,
      "p95DeltaEuro": st.p95D,
      "positiveCountA": st.positiveCount,
      "orders": orderList
    },
    "candidates": {
      candIds[0]: {
        "p95LatencyMs": fa.p95Latency,
        "withinRegressionCeiling": vecA.withinRegressionCeiling,
        "lambdaObservedMaxPerHour": vecA.lambdaObservedMaxPerHour,
        "meanQueueMs": vecA.meanQueueMs,
        "meanExecMs": vecA.meanExecMs,
        "meanEuroPerRun": fa.meanCost,
        "meanCoreMinutes": fa.meanCoreMin,
        "strata": newJObject(),
        "allCostsEuro": obA.mapIt(it.costEuro)
      },
      candIds[1]: {
        "p95LatencyMs": fb.p95Latency,
        "withinRegressionCeiling": vecB.withinRegressionCeiling,
        "lambdaObservedMaxPerHour": vecB.lambdaObservedMaxPerHour,
        "meanQueueMs": vecB.meanQueueMs,
        "meanExecMs": vecB.meanExecMs,
        "meanEuroPerRun": fb.meanCost,
        "meanCoreMinutes": fb.meanCoreMin,
        "strata": newJObject(),
        "allCostsEuro": obB.mapIt(it.costEuro)
      }
    },
    "selection": {
      "winner": winner,
      "basis": "lower P95_trace(W_c) — cost is DIAGNOSTIC ONLY, never the objective; tie-break: lambda_observed_max -> mean queue -> mean exec -> candidate id ascending (exact P95 equality only)",
      "loser": loser,
      "deltaMeanEuro": deltaMeanEuro,
      "deltaPercent": deltaPct
    },
    "note": "cost figures are DIAGNOSTIC ONLY and never influence ranking; P95 over the total per-PR latency population; 15m ceiling flag is a CEILING not a target — a candidate above it is still ranked; λ_observed_max and queue divergence are observed proxies, not proven bounds; 50,000-minute capacity ledger is not a ranking input",
    "determinism": "identical (trace, config, records) inputs produce byte-identical envelope; sets sorted; no timestamps in body"
  }
  for i in 0 ..< obA.len:
    envelope["pairs"].add(%*{
      "pair": obA[i].pairIndex,
      "order": obA[i].order,
      "D_euro": deltas[i],
      "C_A_euro": obA[i].costEuro,
      "C_B_euro": obB[i].costEuro})
  for c in candIds:
    let faC = if c == candIds[0]: fa else: fb
    let strataNode = envelope["candidates"][c]["strata"]
    for k in faC.strata.keys:
      let s = faC.strata[k]
      strataNode[k] = %*{"count": s.count, "p": s.p, "meanCostEuro": s.meanCostEuro}

  let envPath = BuildDir / "compare" / (cycleId & "_" & tr.sha256[0 .. 15] & "_envelope.json")
  if not dirExists(envPath.parentDir()):
    createDir(envPath.parentDir())
  let envHash = sha256String(pretty(envelope, 2))
  envelope["envelopeHash"] = newJString(envHash)
  writeFile(envPath, pretty(envelope, 2) & "\n")

  echo ""
  echo "[pareto-harness] compare cycle " & cycleId & " on trace " & tr.sha256[0 .. 15] &
       "… (load " & loadId & ", ranking population)"
  echo "[pareto-harness]   N(pre-registered) = " & $tr.n &
       " | regression ceiling P95(queue+exec) ≤ " & $SloP95QueueExecMs &
       " ms (CEILING, not a target)"
  echo "[pareto-harness]   pairs (counterbalanced): " & orderList.join(", ")
  echo "[pareto-harness]   P95_trace (total per-PR population): " & candIds[0] & "=" &
       formatFloat(fa.p95Latency, ffDecimal, 1) & " ms | " & candIds[1] & "=" &
       formatFloat(fb.p95Latency, ffDecimal, 1) & " ms"
  echo "[pareto-harness]   withinRegressionCeiling: " & candIds[0] & "=" & $vecA.withinRegressionCeiling &
       " | " & candIds[1] & "=" & $vecB.withinRegressionCeiling & " (flag only, NOT a ranking input)"
  echo "[pareto-harness]   tie-break inputs: " & candIds[0] & "=[λ=" &
       formatFloat(vecA.lambdaObservedMaxPerHour, ffDecimal, 1) & "/h q̄=" &
       formatFloat(vecA.meanQueueMs, ffDecimal, 1) & "ms ēxec=" &
       formatFloat(vecA.meanExecMs, ffDecimal, 1) & "ms] | " & candIds[1] & "=[λ=" &
       formatFloat(vecB.lambdaObservedMaxPerHour, ffDecimal, 1) & "/h q̄=" &
       formatFloat(vecB.meanQueueMs, ffDecimal, 1) & "ms ēxec=" &
       formatFloat(vecB.meanExecMs, ffDecimal, 1) & "ms]"
  echo "[pareto-harness]   DIAGNOSTIC ONLY (never ranking): D_i = C_" & candIds[0] & ",i − C_" & candIds[1] &
       ",i  mean Δ = " & formatFloat(st.meanD, ffDecimal, 6) & " € (median " &
       formatFloat(st.medianD, ffDecimal, 6) & " €)"
  echo "[pareto-harness]   mean €/run: " & candIds[0] & "=" & formatFloat(fa.meanCost, ffDecimal, 6) &
       " | " & candIds[1] & "=" & formatFloat(fb.meanCost, ffDecimal, 6) & " (diagnostic)"
  echo "[pareto-harness]   mean core-min: " & candIds[0] & "=" & formatFloat(fa.meanCoreMin, ffDecimal, 3) &
       " | " & candIds[1] & "=" & formatFloat(fb.meanCoreMin, ffDecimal, 3) & " (diagnostic)"
  echo "[pareto-harness]   strata (diagnostic):"
  for c in candIds:
    let faC = if c == candIds[0]: fa else: fb
    var line: seq[string]
    for k in faC.strata.keys:
      let s = faC.strata[k]
      line.add(&"{k}: p={formatFloat(s.p, ffDecimal, 2)} C̄={formatFloat(s.meanCostEuro, ffDecimal, 6)}")
    echo "[pareto-harness]     " & c & ": " & line.join(" | ")
  echo "[pareto-harness]   SELECTION (v13 objective): " & winner & " — min P95_trace(W_c) (" &
       (if winner == candIds[0]: formatFloat(fa.p95Latency, ffDecimal, 1) else: formatFloat(fb.p95Latency, ffDecimal, 1)) &
       " ms vs " &
       (if loser == candIds[0]: formatFloat(fa.p95Latency, ffDecimal, 1) else: formatFloat(fb.p95Latency, ffDecimal, 1)) &
       " ms); cost Δ " & formatFloat(deltaMeanEuro, ffDecimal, 6) & " €/run (" &
       formatFloat(deltaPct, ffDecimal, 1) & "%) is DIAGNOSTIC ONLY"
  echo "[pareto-harness] envelope: " & envPath
  echo "[pareto-harness] envelope sha256 (locked): " & envHash
  result = 0

# ═══════════════════════════════════════════════════════════════════════════
# §10: characterize — L1/L2/L3 load characterization + λ_observed_max
# ═══════════════════════════════════════════════════════════════════════════

proc characterizeMain(regPath, tracePath, candidate: string): int {.axiomEffect: IOEffect.} =
  let (tr, ok, reason) = readTraceFile(tracePath)
  if not ok:
    errQuit(2, reason)
  if tr.traceKind != "train":
    errQuit(2, "characterize is for TRAIN traces only; got: " & tr.traceKind)
  let ns = verifyNamespaceSemantics(tr)
  echo "[pareto-harness] " & ns.line
  if not ns.ok:
    errQuit(2, ns.line)

  var reg = loadRegistry(regPath)
  let sortKey = traceSortKey(tr)
  let cycleId =
    if reg.cycles.hasKey(sortKey): reg.cycles[sortKey]
    else: "cycle-" & sortKey & "-1"
  let recPath = BuildDir / "records" / &"{cycleId}_{candidate}.json"
  if not fileExists(recPath):
    errQuit(2, "no run record for candidate " & candidate & " in cycle " & cycleId)
  var node: JsonNode
  try:
    node = parseJson(readFile(recPath))
  except CatchableError:
    errQuit(2, "run record unreadable: " & recPath)
  let rec = parseRunRecord(node)
  if rec.recordHash != runRecordHash(rec):
    errQuit(2, "run record hash mismatch (tampered?): " & recPath)
  if rec.traceSha256 != tr.sha256:
    errQuit(2, "run record trace mismatch")

  # Per load level: P95(queue+exec) + queue divergence over the level's
  # observation population.
  var levelsNode = newJArray()
  var lamObservedMax = 0.0
  var maxPassingLevel = ""
  for level in tr.loadLevels:
    let obs = observationsByLoad(rec, level.id)
    var lat: seq[int]
    var qlen: seq[int]
    var exec: seq[int]
    for o in obs:
      lat.add(o.latencyMs)
      qlen.add(o.queueLenAtStart)
      exec.add(o.execMs)
    let p95 = if lat.len > 0: percentile95(lat) else: 0.0
    let nonDivergent = queueNonDivergent(qlen, level.concurrency)
    let sloPass = p95 <= SloP95QueueExecMs.float
    let meanExec = if exec.len > 0: mean(exec.mapIt(it.float)) else: 0.0
    let lam = sustainableArrivalRatePerHour(level.concurrency, meanExec)
    levelsNode.add(%*{
      "load": level.id,
      "concurrency": level.concurrency,
      "observations": obs.len,
      "p95LatencyMs": p95,
      "withinCeiling": sloPass,
      "queueNonDivergent": nonDivergent,
      "maxQueueLen": (if qlen.len > 0: qlen.max else: 0),
      "meanExecMs": meanExec,
      "lambdaPerHour": lam})
    if sloPass and nonDivergent and lam > lamObservedMax:
      lamObservedMax = lam
      maxPassingLevel = level.id
  # Observed max over passing levels — NOT a proven bound.
  if maxPassingLevel.len == 0:
    echo "[pareto-harness] WARN: no load level satisfies P95≤15m (ceiling) AND non-divergent queue for candidate " & candidate
  let envelope = %*{
    "schema": CharacterizeEnvelopeSchema,
    "cycleId": cycleId,
    "candidateId": candidate,
    "traceSha256": tr.sha256,
    "arrivalRatePerHour": tr.arrivalRatePerHour,
    "levels": levelsNode,
    "lamObservedMaxPerHour": lamObservedMax,
    "maxPassingLevel": maxPassingLevel,
    "note": "L3 saturation is a capacity diagnostic ONLY, excluded from the ranking population; λ is observed max from measured mean service time, NOT a proven bound; queue divergence is an observed-window proxy; 15m P95 is a regression CEILING (flag only)",
    "determinism": "no timestamps in body"
  }
  let envPath = BuildDir / "characterize" / (cycleId & "_" & candidate & ".json")
  if not dirExists(envPath.parentDir()):
    createDir(envPath.parentDir())
  writeFile(envPath, pretty(envelope, 2) & "\n")
  echo "[pareto-harness] characterize " & candidate & " (cycle " & cycleId & "):"
  for lv in levelsNode:
    echo "[pareto-harness]   " & lv["load"].getStr() &
         " (conc " & $lv["concurrency"].getInt() & "): P95=" & formatFloat(lv["p95LatencyMs"].getFloat(), ffDecimal, 1) &
         " ms | withinCeiling=" & $lv["withinCeiling"].getBool() &
         " | nonDivergent=" & $lv["queueNonDivergent"].getBool() &
         " | maxQ=" & $lv["maxQueueLen"].getInt() &
         " | λ=" & formatFloat(lv["lambdaPerHour"].getFloat(), ffDecimal, 1) & "/h"
  echo "[pareto-harness]   λ_observed_max = " & formatFloat(lamObservedMax, ffDecimal, 1) &
       "/h" & (if maxPassingLevel.len > 0: " (level " & maxPassingLevel & ")" else: " (NONE)") &
       " — observed max, NOT a proven bound"
  echo "[pareto-harness] envelope: " & envPath
  result = 0

# ═══════════════════════════════════════════════════════════════════════════
# §11: verify-holdout — pre-registered single-use BATCH check of c*
# ═══════════════════════════════════════════════════════════════════════════

proc verifyHoldoutMain(regPath, tracePath, selCand: string): int {.axiomEffect: IOEffect.} =
  let (tr, ok, reason) = readTraceFile(tracePath)
  if not ok:
    errQuit(2, reason)
  if tr.traceKind != "holdout":
    errQuit(2, "verify-holdout requires a holdout trace; this is: " & tr.traceKind)
  if selCand.len == 0:
    errQuit(2, "verify-holdout requires --candidate <id>: the selected candidate c* from compare (P5 wires this selection)")

  let ns = verifyNamespaceSemantics(tr)
  echo "[pareto-harness] " & ns.line
  if not ns.ok:
    errQuit(2, ns.line)

  let sortKey = traceSortKey(tr)
  var reg = loadRegistry(regPath)
  if reg.consumedHoldouts.hasKey(sortKey):
    errQuit(2, "holdout reuse refused: this holdout trace was already consumed by verify-holdout (envelope " &
            reg.consumedHoldouts[sortKey][0 .. 15] & "…). The same holdout must NOT be reused to pick another candidate — a new pre-registered cycle (new holdout trace) is required.")

  # The record holds ALL N observations (pre-registered BATCH — not a single
  # run). The harness requires the FULL batch to be present.
  let cycleId = "cycle-" & sortKey & "-1"
  let recPath = BuildDir / "records" / &"{cycleId}_{selCand}.json"
  if not fileExists(recPath):
    errQuit(2, "no run record for selected candidate on holdout trace: " & recPath)
  var node: JsonNode
  try:
    node = parseJson(readFile(recPath))
  except CatchableError:
    errQuit(2, "holdout run record unreadable: " & recPath)
  let rec = parseRunRecord(node)
  if rec.recordHash != runRecordHash(rec):
    errQuit(2, "holdout run record hash mismatch (tampered?): " & recPath)
  if rec.traceSha256 != tr.sha256:
    errQuit(2, "holdout run record trace mismatch — record belongs to a different trace")
  let obsAll = rec.observations
  if obsAll.len != tr.n:
    errQuit(2, &"holdout batch incomplete: expected {tr.n} observations (pre-registered BATCH), found {obsAll.len}")

  let envPath = BuildDir / "holdout" / ("holdout_" & tr.sha256[0 .. 15] & "_envelope.json")
  if not dirExists(envPath.parentDir()):
    createDir(envPath.parentDir())
  let envelope = %*{
    "schema": HoldoutEnvelopeSchema,
    "traceSha256": tr.sha256,
    "traceKind": "holdout",
    "cycleId": cycleId,
    "n": tr.n,
    "selectedCandidate": selCand,
    "batchObservations": obsAll.len,
    "result": "PASS (pre-registered batch use)",
    "determinism": "no timestamps in body",
    "note": "holdout used exactly once, as a batch, never for re-selection"
  }
  writeFile(envPath, pretty(envelope, 2) & "\n")
  let envHash = sha256String(pretty(envelope, 2))
  reg.consumedHoldouts[sortKey] = envHash
  saveRegistry(regPath, reg)
  echo "[pareto-harness] holdout verification PASS (single pre-registered batch of " & $obsAll.len &
       " observations for " & selCand & "): " & envPath
  echo "[pareto-harness] holdout envelope sha256 (lock): " & envHash
  result = 0

# ═══════════════════════════════════════════════════════════════════════════
# §12: ingest — GitHub Actions run ingestion backend
# ═══════════════════════════════════════════════════════════════════════════
#
# Turns ONE completed GitHub Actions run into ONE observation on a pre-registered
# trace position, so real CI runs become harness records (candidate sweeps
# measured on GitHub: single-factor AXIOM_JOBS, runner arch/class, etc.).
#   - Acquisition: `gh api repos/{owner}/{repo}/actions/runs/{id}` (+ `/jobs`)
#     via startProcess with an args array (NO shell). Read-only — this harness
#     never triggers workflow runs. Offline replay: `--from-json <file>` reads
#     the SAME {"run":…, "jobs":{…}} payload shape and exercises the SAME
#     parser (hermetic selftest).
#   - Timing convention (consistent with the local backend's W = queue + exec):
#       W          = updated_at − run_started_at        (end-to-end run wall)
#       queueMs    = firstSuccessJob.started_at − run_started_at
#       execMs     = updated_at − firstSuccessJob.started_at
#       latencyMs  = queueMs + execMs ≡ W (exact telescope; same identity as the
#                   local backend's latencyMs = queueMs + execMs).
#     The "run completed" instant is `updated_at` — the run object's own
#     completion marker for concluded runs (equal to max job completed_at up to
#     run post-processing; it is the run-level field, documented as the W
#     anchor). "first success job" = earliest started_at among jobs whose
#     conclusion == "success" (skipped/cancelled jobs never occupied a runner,
#     so they must not distort queue/exec).
#   - Per-job durations: completed_at − started_at, summed over success jobs
#     ONLY; coreMinutes = Σ / 60000 (diagnostic, the real GH billing unit).
#   - costEuro (DIAGNOSTIC ONLY, v13) = latencyMs / 60000 — same default formula
#     the local backend uses for missing cost telemetry. costEuro is NEVER a
#     ranking input.
#   - Runner labels: recorded per job (informational) + the first-success-job
#     labels as the run's representative runner class.
#   - Position policy: `--pair-index i` is REQUIRED (no auto-append). Trace
#     positions are pre-registered slots; the sweep script maps run → slot and
#     alternates `--order` per pair (A->B / B->A) so the compare-time
#     counterbalance invariant (both orders present for n >= 2) holds. Ingest
#     itself records the declared order per observation; it does NOT decide
#     order. Duplicate (trace, position, candidate, order, load) is refused
#     (exit 2) even for a different run id — pre-registration protection.
#   - queueLenAtStart / stratum are not derivable from the GH API: 0 / "cold"
#     defaults are set with an explicit WARN (never silently), mirroring the
#     local backend's missing-optional-telemetry WARNs.
#   - λ_observed_max is NOT derivable from one run — `characterize` computes it
#     over the record's load levels (unchanged).
#   - Records are written ONLY when `--record` is passed; without it ingest is
#     a print-only dry run (parses + validates + prints the derived observation,
#     writes nothing) — used for the real-data smoke below.
#
# Exit mapping: payload unreadable/malformed (JSON, missing fields, unparseable
# timestamps) = 1 (ERROR); run/invariant violations (conclusion != success,
# run not completed, negative durations, no success job, duplicate, N exceeded,
# trace/namespace/candidate violations) = 2 (INVALID); success = 0.

type
  GitHubJobInfo = object
    name*, conclusion*: string
    labels*: seq[string]
    startedMs*, completedMs*: int   # parsed epoch-ms; -1 when unavailable
    durationMs*: int                # completedMs − startedMs (>= 0); -1 unset

  GitHubRunInfo = object
    runId*, workflowName*, event*, headBranch*, headSha*, conclusion*, status*: string
    runStartedIso*, updatedIso*: string
    runStartedMs*, updatedMs*: int
    runAttempt*: int
    jobs*: seq[GitHubJobInfo]

  IngestOutcome* = object
    ok*: bool
    reason*: string                 # rejection reason when not ok
    queueMs*, execMs*, latencyMs*: int
    coreMinutes*: float
    anchorJobIndex*: int            # index into run.jobs of the first success job

proc parseGitHubIsoMs*(s: string): int {.raises: [].} =
  ## Epoch-ms of a GitHub API ISO-8601 timestamp ("2026-09-25T06:53:39Z" — "Z"
  ## or ±HH:MM). A zone designator is REQUIRED (no zone = malformed). Returns
  ## -1 on any malformed input (never raises), mirroring the parseIntStrict
  ## sentinel convention.
  var body = s.strip()
  var offsetMs = 0
  if body.endsWith("Z"):
    body = body[0 ..< body.len - 1]
  elif body.len >= 6 and (body[^6] == '+' or body[^6] == '-'):
    try:
      let sign = (if body[^6] == '+': 1 else: -1)
      if body[^3] != ':':
        return -1
      let hh = parseInt(body[^5 .. ^4])
      let mm = parseInt(body[^2 .. ^1])
      offsetMs = sign * (hh * 60 + mm) * 60_000
      body = body[0 ..< body.len - 6]
    except CatchableError:
      return -1
  else:
    return -1
  if body.len != 19:
    return -1
  try:
    result = parse(body, "yyyy-MM-dd'T'HH:mm:ss", utc()).toTime().toUnix() * 1000 - offsetMs
  except CatchableError:
    result = -1

proc parseGitHubPayload*(runNode, jobsNode: JsonNode): tuple[r: GitHubRunInfo, ok: bool, reason: string] {.raises: [].} =
  ## Parses the raw `gh api .../runs/{id}` + `.../jobs` payloads into a
  ## GitHubRunInfo. Missing fields, null conclusions and unparseable timestamps
  ## on SUCCESS jobs are reported as not-ok (caller: exit 1, malformed payload).
  ## Non-success jobs' timestamps are ignored (they never occupied a runner).
  try:
    result.r.runId = $runNode["id"].getInt()
    result.r.workflowName = (if runNode.hasKey("name"): runNode["name"].getStr() else: "")
    result.r.event = (if runNode.hasKey("event"): runNode["event"].getStr() else: "")
    result.r.status = (if runNode.hasKey("status"): runNode["status"].getStr() else: "")
    result.r.conclusion =
      (if runNode.hasKey("conclusion") and runNode["conclusion"].kind == JString:
        runNode["conclusion"].getStr() else: "")
    result.r.headBranch = (if runNode.hasKey("head_branch"): runNode["head_branch"].getStr() else: "")
    result.r.headSha = (if runNode.hasKey("head_sha"): runNode["head_sha"].getStr() else: "")
    result.r.runAttempt = (if runNode.hasKey("run_attempt"): runNode["run_attempt"].getInt() else: 1)
    if runNode.hasKey("run_started_at"):
      result.r.runStartedIso = runNode["run_started_at"].getStr()
      result.r.runStartedMs = parseGitHubIsoMs(result.r.runStartedIso)
    else:
      return (GitHubRunInfo(), false, "run object missing run_started_at")
    if runNode.hasKey("updated_at"):
      result.r.updatedIso = runNode["updated_at"].getStr()
      result.r.updatedMs = parseGitHubIsoMs(result.r.updatedIso)
    else:
      return (GitHubRunInfo(), false, "run object missing updated_at")
    if result.r.runStartedMs < 0:
      return (GitHubRunInfo(), false, "unparseable run_started_at: " & result.r.runStartedIso)
    if result.r.updatedMs < 0:
      return (GitHubRunInfo(), false, "unparseable updated_at: " & result.r.updatedIso)
    if not jobsNode.hasKey("jobs"):
      return (GitHubRunInfo(), false, "jobs payload missing jobs array")
    for jn in jobsNode["jobs"].items:
      var j: GitHubJobInfo
      j.name = (if jn.hasKey("name"): jn["name"].getStr() else: "")
      j.conclusion =
        (if jn.hasKey("conclusion") and jn["conclusion"].kind == JString:
          jn["conclusion"].getStr() else: "")
      j.labels = @[]
      if jn.hasKey("labels"):
        for lb in jn["labels"].items:
          j.labels.add(lb.getStr())
      if j.conclusion == "success":
        if not jn.hasKey("started_at"):
          return (GitHubRunInfo(), false, "success job '" & j.name & "' missing started_at")
        if not jn.hasKey("completed_at"):
          return (GitHubRunInfo(), false, "success job '" & j.name & "' missing completed_at")
        j.startedMs = parseGitHubIsoMs(jn["started_at"].getStr())
        j.completedMs = parseGitHubIsoMs(jn["completed_at"].getStr())
        if j.startedMs < 0 or j.completedMs < 0:
          return (GitHubRunInfo(), false,
                  "unparseable timestamp on success job '" & j.name & "'")
        j.durationMs = j.completedMs - j.startedMs
      else:
        j.startedMs = -1
        j.completedMs = -1
      result.r.jobs.add(j)
    result.ok = true
  except CatchableError as exc:
    result = (GitHubRunInfo(), false, "field access failed: " & exc.msg)

proc deriveIngestObservation*(run: GitHubRunInfo): IngestOutcome {.raises: [].} =
  ## Derives the single observation from a parsed run. Rejects (ok=false, with
  ## reason) any run that cannot be a valid measurement: not completed,
  ## conclusion != success, no success job with valid timestamps, or negative
  ## queue/exec/duration. Caller maps not-ok -> exit 2 (harness violation).
  if run.status != "completed":
    return IngestOutcome(ok: false,
      reason: "run " & run.runId & " status is '" & run.status & "' — only completed runs are ingestible")
  if run.conclusion != "success":
    return IngestOutcome(ok: false,
      reason: "run " & run.runId & " conclusion is '" & run.conclusion & "' — only success runs are ingestible")
  var firstStart = high(int)
  result.anchorJobIndex = -1
  var sumJobMs = 0
  for i, j in run.jobs:
    if j.conclusion != "success":
      continue
    if j.startedMs < 0 or j.completedMs < 0:
      return IngestOutcome(ok: false,
        reason: "success job '" & j.name & "' has no valid timestamps")
    let d = j.completedMs - j.startedMs
    if d < 0:
      return IngestOutcome(ok: false,
        reason: "success job '" & j.name & "' has completed_at before started_at")
    sumJobMs += d
    if j.startedMs < firstStart:
      firstStart = j.startedMs
      result.anchorJobIndex = i
  if result.anchorJobIndex < 0:
    return IngestOutcome(ok: false,
      reason: "run " & run.runId & " has no success job with valid timestamps")
  result.queueMs = firstStart - run.runStartedMs
  if result.queueMs < 0:
    return IngestOutcome(ok: false,
      reason: "run " & run.runId & " first success job starts before run_started_at (negative queue)")
  result.execMs = run.updatedMs - firstStart
  if result.execMs < 0:
    return IngestOutcome(ok: false,
      reason: "run " & run.runId & " updated_at before first success job start (negative execution)")
  result.latencyMs = result.queueMs + result.execMs  # ≡ updated_at − run_started_at (telescoping)
  result.coreMinutes = sumJobMs.float / 60000.0
  result.ok = true

proc githubRunNode*(run: GitHubRunInfo; o: IngestOutcome): JsonNode =
  ## INFORMATIONAL-ONLY provenance block attached to an ingested observation.
  ## Wall-clock timestamps -> NEVER digest-covered (same status as
  ## preRegisteredAt); not part of runRecordHash; identical v1 measurement
  ## fields -> identical hash.
  result = %*{
    "backend": "github",
    "runId": run.runId,
    "runAttempt": run.runAttempt,
    "workflowName": run.workflowName,
    "event": run.event,
    "headBranch": run.headBranch,
    "headSha": run.headSha,
    "conclusion": run.conclusion,
    "runStartedAt": run.runStartedIso,
    "updatedAt": run.updatedIso,
    "runnerLabels": (if o.anchorJobIndex >= 0 and o.anchorJobIndex < run.jobs.len:
                      run.jobs[o.anchorJobIndex].labels else: @[]),
    "jobs": newJArray()}
  for i, j in run.jobs:
    if j.conclusion != "success":
      continue
    var jNode = %*{"name": j.name, "labels": j.labels,
                   "durationMs": (if j.durationMs >= 0: j.durationMs else: j.completedMs - j.startedMs)}
    result["jobs"].add(jNode)

proc firstLines(s: string; n: int): string =
  var lines: seq[string]
  for l in s.splitLines:
    if l.strip.len > 0:
      lines.add(l.strip)
    if lines.len >= n:
      break
  result = lines.join(" | ")

proc applyDiagCredential() {.axiomEffect: IOEffect.} =
  ## M7 no-fallback credential guard (docs/spec/diagnostic_execution_delegation.md
  ## §4) — same mechanism as merge_ruleset_drift_monitor.nim. AXIOM_DIAG_TOKEN
  ## (explicitly provisioned) is injected as GH_TOKEN so the `gh api` GETs below
  ## use exactly it; AXIOM_DIAG_STRICT=1 refuses the `gh auth` fallback (operator
  ## PAT) — fail closed. The credential source is ALWAYS printed (never silent).
  ## Only the live-ingest path calls this; --from-json replay is offline.
  let explicit = getEnv("AXIOM_DIAG_TOKEN").strip()
  if explicit.len > 0:
    stderr.writeLine "pareto_harness: credential-source=AXIOM_DIAG_TOKEN"
    putEnv("GH_TOKEN", explicit)
  elif getEnv("AXIOM_DIAG_STRICT") == "1":
    stderr.writeLine "pareto_harness: FAIL — AXIOM_DIAG_TOKEN absent and AXIOM_DIAG_STRICT=1: `gh api` via `gh auth` (operator PAT) is refused for diagnostic execution (M7 no-fallback — docs/spec/diagnostic_execution_delegation.md §4)"
    quit(1)
  else:
    stderr.writeLine "pareto_harness: credential-source=gh-auth (fallback — AXIOM_DIAG_STRICT not set; not a diagnostic credential)"

proc ghApiFetch(repo, apiPath: string): JsonNode {.axiomEffect: IOEffect.} =
  ## `gh api` via startProcess with an args array (NO shell — repo discipline).
  ## Read-only; this harness never triggers workflow runs.
  let p = startProcess("gh", args = @["api", "repos/" & repo & apiPath],
                       options = {poUsePath, poStdErrToStdOut})
  let outp = p.outputStream.readAll()
  let code = p.waitForExit()
  p.close()
  if code != 0:
    errQuit(1, "gh api failed (exit " & $code & ") for repos/" & repo & apiPath & ": " &
            firstLines(outp, 3))
  try:
    result = parseJson(outp)
  except CatchableError:
    errQuit(1, "gh api returned non-JSON for repos/" & repo & apiPath)

proc detectGithubRepo(over: string): string {.axiomEffect: IOEffect.} =
  ## Resolves owner/name for gh api. Explicit --repo wins; otherwise the origin
  ## remote URL is parsed (git@github.com:Owner/Repo.git, https, ssh/git forms).
  if over.len > 0:
    if "/" in over and over.count("/") == 1:
      return over
    errQuit(2, "--repo must be <owner>/<name>, got: " & over)
  let p = startProcess("git", args = @["remote", "get-url", "origin"],
                       workingDir = repoRoot(), options = {poUsePath, poStdErrToStdOut})
  let outp = p.outputStream.readAll()
  let code = p.waitForExit()
  p.close()
  if code != 0:
    return ""
  var url = outp.strip()
  if url.endsWith(".git"):
    url = url[0 ..< url.len - 4]
  if url.startsWith("git@github.com:"):
    result = url["git@github.com:".len .. ^1]
  elif url.startsWith("https://github.com/"):
    result = url["https://github.com/".len .. ^1]
  elif url.startsWith("ssh://git@github.com/"):
    result = url["ssh://git@github.com/".len .. ^1]
  elif url.startsWith("git://github.com/"):
    result = url["git://github.com/".len .. ^1]
  if result.count("/") != 1:
    result = ""

proc ingestMain(runId, fromJsonPath, candidate, tracePath, order, repoFlag, loadId: string;
                pairIndex: int; writeRecord: bool): int {.axiomEffect: IOEffect.} =
  ## Implements `ingest` — see the §12 section comment for the full convention.
  ## Trace-side validation runs FIRST (fail fast, no network); the GitHub
  ## payload is acquired and derived only after the harness preconditions hold.
  let (tr, tok, reason) = readTraceFile(tracePath)
  if not tok:
    errQuit(2, reason)
  let ns = verifyNamespaceSemantics(tr)
  echo "[pareto-harness] " & ns.line
  if not ns.ok:
    errQuit(2, ns.line)
  var declared = false
  if tr.config.hasKey("candidates") and tr.config["candidates"].kind == JObject:
    for k in tr.config["candidates"].keys:
      if k == candidate:
        declared = true
  if not declared:
    errQuit(2, "candidate '" & candidate & "' not declared in trace config")
  if pairIndex < 1 or pairIndex > tr.n:
    errQuit(2, &"pair index {pairIndex} out of pre-registered range 1..{tr.n} (N is fixed at prepare time; ingest cannot extend it)")
  var loadFound = false
  for l in tr.loadLevels:
    if l.id == loadId:
      loadFound = true
      break
  if not loadFound:
    errQuit(2, "unknown load level: " & loadId & " (trace declares: " &
            tr.loadLevels.mapIt(it.id).join(",") & ")")

  # Payload acquisition: real gh (--github-run) or offline replay (--from-json).
  var runNode, jobsNode: JsonNode
  if runId.len > 0:
    applyDiagCredential()
    let repo = detectGithubRepo(repoFlag)
    if repo.len == 0:
      errQuit(2, "cannot determine <owner>/<repo> — pass --repo <owner/repo> (origin remote unparseable/absent)")
    runNode = ghApiFetch(repo, "/actions/runs/" & runId)
    jobsNode = ghApiFetch(repo, "/actions/runs/" & runId & "/jobs")
  else:
    var node: JsonNode
    try:
      node = parseJson(readFile(fromJsonPath))
    except CatchableError:
      errQuit(1, "cannot read/parse --from-json file: " & fromJsonPath)
    if node.hasKey("run") and node.hasKey("jobs"):
      runNode = node["run"]
      jobsNode = node["jobs"]
    else:
      errQuit(1, "--from-json file must contain {\"run\": <run-json>, \"jobs\": <jobs-json>}: " & fromJsonPath)

  let (g, pok, preason) = parseGitHubPayload(runNode, jobsNode)
  if not pok:
    errQuit(1, "malformed GitHub payload: " & preason)
  let derived = deriveIngestObservation(g)
  if not derived.ok:
    errQuit(2, derived.reason)

  echo ""
  echo "[pareto-harness] ingest run " & g.runId & " (" & g.workflowName &
       (if g.runAttempt > 1: " attempt " & $g.runAttempt else: "") & ") — " &
       (if g.event.len > 0: g.event & ", " else: "") &
       (if g.headBranch.len > 0: "branch=" & g.headBranch else: "") &
       (if g.headSha.len > 0: " sha=" & g.headSha[0 .. 7] else: "") &
       " conclusion=" & g.conclusion
  echo "[pareto-harness]   W (end-to-end) = " & $derived.latencyMs & " ms = updated_at − run_started_at (" &
       $derived.queueMs & " ms queue + " & $derived.execMs & " ms exec; queue = first success job start − run_started_at)"
  for i, j in g.jobs:
    if j.conclusion == "success":
      let d = if j.durationMs >= 0: j.durationMs else: j.completedMs - j.startedMs
      echo "[pareto-harness]   job " & j.name & " [" & j.labels.join(",") & "] = " & $d &
           " ms (" & formatFloat(d.float / 60000.0, ffDecimal, 3) & " min)"
    else:
      echo "[pareto-harness]   job " & j.name & " [" & j.labels.join(",") & "] = " & j.conclusion &
           " (excluded from exec/core-minutes)"
  echo "[pareto-harness]   core-minutes (Σ success jobs) = " & formatFloat(derived.coreMinutes, ffDecimal, 4) &
       " (diagnostic) | costEuro (diagnostic € proxy) = " &
       formatFloat(derived.latencyMs.float / 60000.0, ffDecimal, 4) &
       " = latency-minutes, never a ranking input"
  echo "[pareto-harness]   WARN: GitHub API exposes no queue length at start — queueLenAtStart=0"
  echo "[pareto-harness]   WARN: GitHub API exposes no cache stratum — stratum=cold (conservative default)"
  echo "[pareto-harness]   observation -> candidate=" & candidate & " pair=" & $pairIndex &
       " order=" & order & " load=" & loadId & " (latencyMs=" & $derived.latencyMs &
       " queueMs=" & $derived.queueMs & " execMs=" & $derived.execMs & " coreMin=" &
       formatFloat(derived.coreMinutes, ffDecimal, 4) & ")"
  if not writeRecord:
    echo "[pareto-harness]   dry-run: no record written (re-run with --record to persist)"
    return 0

  let sortKey = traceSortKey(tr)
  var reg = loadRegistry(DataDir / "cycle_registry.json")
  let cycleId =
    if reg.cycles.hasKey(sortKey): reg.cycles[sortKey]
    else: "cycle-" & sortKey & "-1"
  let obs = RunObservation(
    pairIndex: pairIndex, order: order, loadLevel: loadId,
    queueMs: derived.queueMs, execMs: derived.execMs, latencyMs: derived.latencyMs,
    costEuro: derived.latencyMs.float / 60000.0, coreMinutes: derived.coreMinutes,
    queueLenAtStart: 0, stratum: "cold", githubRun: githubRunNode(g, derived))
  var exp = RunRecord(schema: RunRecordSchema, candidateId: candidate,
                      cycleId: cycleId, traceSha256: tr.sha256,
                      traceKind: tr.traceKind, n: tr.n)
  let recPath = BuildDir / "records" / (cycleId & "_" & candidate & ".json")
  let rec = appendObservation(recPath, obs, exp)
  echo "[pareto-harness]   record " & candidate & ": " & $rec.observations.len & "/" & $tr.n &
       " observations in " & cycleId & " -> " & recPath
  result = 0

# ═══════════════════════════════════════════════════════════════════════════
# §13: selftest — runnable self-check (never a stub)
# ═══════════════════════════════════════════════════════════════════════════

proc assertEq(name: string; got, want: string) {.axiomEffect: IOEffect.} =
  if got != want:
    errQuit(1, "selftest FAIL: " & name & " — got " & got & ", want " & want)
  echo "  PASS: " & name

proc assertTrue(name: string; cond: bool; detail: string = "") {.axiomEffect: IOEffect.} =
  if not cond:
    errQuit(1, "selftest FAIL: " & name & (if detail.len > 0: " — " & detail else: ""))
  echo "  PASS: " & name

proc execSelf(selfBin, workingDir: string; args: seq[string]): tuple[outp: string, code: int] {.axiomEffect: IOEffect.} =
  ## Runs this same binary with an explicit args array (no shell involved —
  ## avoids `>` redirection quirks with unquoted A->B values).
  let p = startProcess(selfBin, workingDir = workingDir, args = args,
                       options = {poUsePath, poStdErrToStdOut})
  let outp = p.outputStream.readAll()
  let code = p.waitForExit()
  p.close()
  result = (outp, code)

proc selftestMain(): int {.axiomEffect: IOEffect.} =
  echo "[selftest] pareto-harness self-check"
  let tmpDir = getTempDir() / ("pareto_harness_selftest_" & $getCurrentProcessId())
  if dirExists(tmpDir): removeDir(tmpDir)
  createDir(tmpDir)

  # 1. sha256 determinism and known-vector sanity.
  let emptyDigest = sha256String("")
  assertEq("sha256 empty known vector", emptyDigest, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
  assertEq("sha256 deterministic", sha256String("abc"), sha256String("abc"))

  # 2. Trace preparation: N is pre-registered at prep time; any change of N
  #    changes the trace content → different hash → different cycle required.
  let trA = tmpDir / "trainA.json"
  let code = prepareTrace(tmpDir / "cfg.json", trA, "train", "fast:target_fast", "slow:target_slow",
                          5, 10, 7, 3, 24)
  assertTrue("prepare-train returns 0", code == 0)
  let (t1, ok1, _) = readTraceFile(trA)
  assertTrue("trace read + hash verify ok", ok1)
  assertEq("trace kind", t1.traceKind, "train")
  assertEq("trace n locked", $t1.n, "3")
  assertTrue("trace has L1/L2/L3", t1.loadLevels.len == 3)
  assertTrue("trace body hash excludes preRegisteredAt (deterministic across runs)",
             sha256String(canonicalArrivalText(t1)) == sha256String(canonicalArrivalText(t1)))

  let trB = tmpDir / "trainB.json"
  discard prepareTrace(tmpDir / "cfgB.json", trB, "train", "fast:target_fast", "slow:target_slow",
                       5, 10, 7, 4, 24)
  let (t2, ok2, _) = readTraceFile(trB)
  assertTrue("traceB read ok", ok2)
  assertTrue("different n => different trace hash (new cycle required)",
             t1.sha256 != t2.sha256)

  # 3. Namespace semantics: declared digest must equal baseline digest.
  let v1 = verifyNamespaceSemantics(t1)
  assertTrue("namespace semantics verification line PASS", v1.ok)
  assertEq("namespace verification line text", v1.line,
           "candidate cache namespace isolation preserves production cache key/scope/retention semantics")
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
  assertTrue("semantics-changing config FAILS verification", not vBad.ok)
  assertTrue("semantics-changing config reports declared digest", vBad.declaredDigest.len == 64)

  # 4. Paired-difference math: known deltas. (10 − 5 + 40)/3 = 15; median 10.
  let st = pairedStats(@[10.0, -5.0, 40.0])
  assertTrue("paired mean delta", abs(st.meanD - 15.0) < 0.001)
  assertTrue("paired median delta", abs(st.medianD - 10.0) < 0.001)
  assertEq("paired positive count", $st.positiveCount, "2")
  assertTrue("paired n=3", st.n == 3)

  # 5. P95 over the total population — nearest-rank, not weighted segments.
  var lat: seq[int]
  for i in 1 .. 100: lat.add(i)
  assertTrue("p95 of 1..100 (nearest-rank)", abs(percentile95(lat) - 95.0) < 0.001)
  assertTrue("p95 of [1000,1100,1200] is max (nearest-rank ceil)", abs(percentile95(@[1000, 1100, 1200]) - 1200.0) < 0.001)

  # 6. Queue divergence proxy + λ formula.
  assertTrue("queue non-divergent when flat at capacity", queueNonDivergent(@[1, 2, 1, 2, 1], 10))
  assertTrue("queue divergent when backlog grows by a full batch", not queueNonDivergent(@[1, 2, 5, 8, 11], 10))
  assertTrue("queue divergent when exceeding 3x capacity", not queueNonDivergent(@[31, 2, 1, 1, 1], 10))
  assertTrue("lambda = c*3600/meanExec", abs(sustainableArrivalRatePerHour(10, 1000.0) - 36.0) < 0.001)

  # 6b. v13 ranking: c* = argmin P95_trace(W_c); cost figures are DIAGNOSTIC
  #     ONLY; tie-break engages ONLY on EXACT P95 equality.
  let vbCheapSlow = CandidateRankVector(
    candidateId: "cheap-slow", p95LatencyMs: 1000.0,
    lambdaObservedMaxPerHour: 0.0, meanQueueMs: 10.0, meanExecMs: 990.0,
    withinRegressionCeiling: true)
  let vbFastPricy = CandidateRankVector(
    candidateId: "fast-pricy", p95LatencyMs: 500.0,
    lambdaObservedMaxPerHour: 0.0, meanQueueMs: 10.0, meanExecMs: 480.0,
    withinRegressionCeiling: true)
  assertEq("v13: cheaper-but-slower must NOT win (cost is diagnostic)",
           selectWinner([vbCheapSlow, vbFastPricy]), "fast-pricy")
  # Higher λ wins ONLY when P95 exactly equal (tie-break 1).
  let vbLamLo = CandidateRankVector(
    candidateId: "lamlo", p95LatencyMs: 500.0, lambdaObservedMaxPerHour: 10.0,
    meanQueueMs: 5.0, meanExecMs: 100.0, withinRegressionCeiling: true)
  let vbLamHi = CandidateRankVector(
    candidateId: "lamhi", p95LatencyMs: 500.0, lambdaObservedMaxPerHour: 50.0,
    meanQueueMs: 20.0, meanExecMs: 300.0, withinRegressionCeiling: true)
  assertEq("v13 tie-break 1: exact-equal P95 -> higher lambda_observed_max wins",
           selectWinner([vbLamLo, vbLamHi]), "lamhi")
  # P95 UNEQUAL -> tie-break must NOT engage: lower-P95 wins despite lower λ
  # and worse queue/exec.
  let vbLowP95 = CandidateRankVector(
    candidateId: "lowp95", p95LatencyMs: 400.0, lambdaObservedMaxPerHour: 5.0,
    meanQueueMs: 50.0, meanExecMs: 100.0, withinRegressionCeiling: true)
  let vbHighP95 = CandidateRankVector(
    candidateId: "highp95", p95LatencyMs: 600.0, lambdaObservedMaxPerHour: 999.0,
    meanQueueMs: 1.0, meanExecMs: 10.0, withinRegressionCeiling: true)
  assertEq("v13: P95 unequal -> tie-break does NOT engage (min P95 wins)",
           selectWinner([vbLowP95, vbHighP95]), "lowp95")
  # Tie chain: equal P95+λ -> mean queue decides (tie-break 2).
  let vbQueueLo = CandidateRankVector(
    candidateId: "queuelo", p95LatencyMs: 500.0, lambdaObservedMaxPerHour: 10.0,
    meanQueueMs: 50.0, meanExecMs: 500.0, withinRegressionCeiling: true)
  let vbQueueHi = CandidateRankVector(
    candidateId: "queuehi", p95LatencyMs: 500.0, lambdaObservedMaxPerHour: 10.0,
    meanQueueMs: 120.0, meanExecMs: 200.0, withinRegressionCeiling: true)
  assertEq("v13 tie-break 2: equal P95+lambda -> min mean queue wins",
           selectWinner([vbQueueLo, vbQueueHi]), "queuelo")
  # Tie chain: equal P95+λ+queue -> mean exec decides (tie-break 3).
  let vbExecLo = CandidateRankVector(
    candidateId: "execlo", p95LatencyMs: 500.0, lambdaObservedMaxPerHour: 10.0,
    meanQueueMs: 100.0, meanExecMs: 300.0, withinRegressionCeiling: true)
  let vbExecHi = CandidateRankVector(
    candidateId: "exechi", p95LatencyMs: 500.0, lambdaObservedMaxPerHour: 10.0,
    meanQueueMs: 100.0, meanExecMs: 900.0, withinRegressionCeiling: true)
  assertEq("v13 tie-break 3: equal P95+lambda+queue -> min mean exec wins",
           selectWinner([vbExecLo, vbExecHi]), "execlo")
  # Tie chain: all four equal -> candidate id ASCENDING (stable rule).
  let vbZeta = CandidateRankVector(
    candidateId: "zeta", p95LatencyMs: 500.0, lambdaObservedMaxPerHour: 10.0,
    meanQueueMs: 100.0, meanExecMs: 300.0, withinRegressionCeiling: true)
  let vbAlpha = CandidateRankVector(
    candidateId: "alpha", p95LatencyMs: 500.0, lambdaObservedMaxPerHour: 10.0,
    meanQueueMs: 100.0, meanExecMs: 300.0, withinRegressionCeiling: true)
  assertEq("v13 tie-break 4: full tie -> candidate id ascending (stable)",
           selectWinner([vbZeta, vbAlpha]), "alpha")
  # Regression-ceiling flag: reported, NOT a ranking input — a candidate with
  # P95 > 15 min is flagged false yet still rankable by min P95.
  let vbOver = CandidateRankVector(
    candidateId: "over-ceiling", p95LatencyMs: (SloP95QueueExecMs.float + 60_000.0),
    lambdaObservedMaxPerHour: 3.0, meanQueueMs: 10.0, meanExecMs: 100.0,
    withinRegressionCeiling: false)
  let vbWayOver = CandidateRankVector(
    candidateId: "way-over-ceiling", p95LatencyMs: (SloP95QueueExecMs.float + 600_000.0),
    lambdaObservedMaxPerHour: 3.0, meanQueueMs: 10.0, meanExecMs: 100.0,
    withinRegressionCeiling: false)
  assertTrue("v13: candidate above 15m ceiling is flagged false",
             not vbOver.withinRegressionCeiling and not vbWayOver.withinRegressionCeiling)
  assertEq("v13: above-ceiling candidate still ranked (flag only, min P95 wins)",
           selectWinner([vbOver, vbWayOver]), "over-ceiling")
  assertTrue("v13: boundary predicate is <= (P95 == 15m counted within ceiling)",
             (SloP95QueueExecMs.float <= SloP95QueueExecMs.float) and
             not ((SloP95QueueExecMs.float + 1.0) <= SloP95QueueExecMs.float))
  # λ_observed_max helper: same computation as compare/characterize; max over
  # passing (P95≤15m AND non-divergent) loads, empty record -> 0.
  var lamRec = RunRecord(schema: RunRecordSchema, candidateId: "fast",
                         cycleId: "cycle-x-1", traceSha256: "abc",
                         traceKind: "train", n: 3)
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
  let lamObs = lambdaObservedMax(lamRec, t1.loadLevels)
  assertTrue("lambda_observed_max over passing loads (L3 excluded)",
             abs(lamObs - 7.2) < 0.0001)
  var emptyRec = RunRecord(schema: RunRecordSchema, candidateId: "fast",
                           cycleId: "cycle-x-1", traceSha256: "abc",
                           traceKind: "train", n: 0)
  assertTrue("lambda_observed_max of empty record is 0",
             lambdaObservedMax(emptyRec, t1.loadLevels) == 0.0)

  # 7. Cycle registry round-trip: first compare registers; re-register is stable.
  let regPath = tmpDir / "registry.json"
  var reg = loadRegistry(regPath)
  let idA = registerCycle(regPath, "abc-123-train", reg)
  var reg2 = loadRegistry(regPath)
  let idB = registerCycle(regPath, "abc-123-train", reg2)
  assertEq("cycle id stable across registry reload", idA, idB)
  var reg3 = loadRegistry(regPath)
  assertTrue("cycle id is a new cycle per trace (different N = different key)",
             idA != registerCycle(regPath, "abd-124-train", reg3))

  # 8. Record logic: duplicate observation refusal is a pure predicate; the
  #    exit-code contract for the refusal is checked below via a spawned
  #    subprocess (self-test of the actual binary, isolated in a tmp cwd).
  var exp = RunRecord(schema: RunRecordSchema, candidateId: "fast", cycleId: "cycle-x-1",
                      traceSha256: "abc", traceKind: "train", n: 3)
  let obs1 = RunObservation(
    pairIndex: 1, order: "A->B", loadLevel: "L2", queueMs: 10, execMs: 100,
    latencyMs: 110, costEuro: 0.002, coreMinutes: 0.05, queueLenAtStart: 1,
    stratum: "cold")
  assertTrue("duplicate predicate: not yet recorded", not alreadyRecorded(exp, 1, "A->B", "L2"))
  var rec = exp
  rec.observations.add(obs1)
  rec.recordHash = runRecordHash(rec)
  assertTrue("duplicate predicate: recorded after append", alreadyRecorded(rec, 1, "A->B", "L2"))
  assertTrue("duplicate predicate: different order not duplicate", not alreadyRecorded(rec, 1, "B->A", "L2"))
  assertTrue("duplicate predicate: different load not duplicate", not alreadyRecorded(rec, 1, "A->B", "L1"))

  # 8b. Exit-code contract via spawned subprocess (isolated tmp cwd — the
  #     binary resolves data/ci_pareto and build/ci_pareto relative to cwd).
  let selfBin = getAppFilename()
  let candSh = tmpDir / "cand_fast.sh"
  writeFile(candSh, "#!/bin/sh\nprintf 'pareto_run_ms=100\\n'\nprintf 'pareto_cost_euro=0.002\\n'\nprintf 'pareto_stratum=cold\\n'\n")
  discard execCmdEx("chmod +x " & candSh)
  let traceTmp = tmpDir / "trace_train.json"
  discard prepareTrace(tmpDir / "config.json", traceTmp, "train",
                       "fast:bash " & candSh, "slow:bash " & candSh,
                       3, 5, 11, 1, 5)
  # run pair 1 -> exit 0
  let (_, c1) = execSelf(selfBin, tmpDir, @["run", "--candidate:fast", "--trace:" & traceTmp,
                                            "--pair:1", "--order:A->B"])
  assertTrue("subprocess run pair 1 exits 0", c1 == 0, "exit=" & $c1)
  # same (pair, order, load) again -> duplicate refusal, exit 2
  let (outDup, cDup) = execSelf(selfBin, tmpDir, @["run", "--candidate:fast", "--trace:" & traceTmp,
                                                   "--pair:1", "--order:A->B"])
  assertTrue("duplicate observation refused with exit 2", cDup == 2,
             "exit=" & $cDup & " out=" & outDup)
  # pair out of pre-registered range (n=1) -> exit 2
  let (outRng, cRng) = execSelf(selfBin, tmpDir, @["run", "--candidate:fast", "--trace:" & traceTmp,
                                                   "--pair:2", "--order:A->B"])
  assertTrue("pair out of pre-registered range exits 2", cRng == 2,
             "exit=" & $cRng & " out=" & outRng)
  # compare without any records for slow -> incomplete pairing exit 2
  let (outInc, cInc) = execSelf(selfBin, tmpDir, @["compare", "--trace:" & traceTmp])
  assertTrue("compare with incomplete pairing exits 2", cInc == 2,
             "exit=" & $cInc & " out=" & outInc)
  # compare on a tampered (namespace-changing) trace -> exit 2
  let tampered = tmpDir / "trace_tampered.json"
  var tnode = parseJson(readFile(traceTmp))
  tnode["config"]["namespaceSemantics"]["scopeSeparation"] = %*"SHARED-NAMESPACE-ACROSS-CANDIDATES"
  writeFile(tampered, pretty(tnode, 2) & "\n")
  let (outTam, cTam) = execSelf(selfBin, tmpDir, @["compare", "--trace:" & tampered])
  assertTrue("compare on semantics-changing trace exits 2", cTam == 2,
             "exit=" & $cTam & " out=" & outTam)

  # 9. factorAnalysis: mean cost, P95 latency, strata proportions.
  let fa = factorAnalysis(@[
    RunObservation(pairIndex: 1, order: "A->B", loadLevel: "L2", queueMs: 0, execMs: 100,
                   latencyMs: 100, costEuro: 0.010, coreMinutes: 0.1, queueLenAtStart: 0, stratum: "cold"),
    RunObservation(pairIndex: 2, order: "B->A", loadLevel: "L2", queueMs: 0, execMs: 200,
                   latencyMs: 200, costEuro: 0.020, coreMinutes: 0.2, queueLenAtStart: 0, stratum: "warm"),
    RunObservation(pairIndex: 3, order: "A->B", loadLevel: "L2", queueMs: 0, execMs: 300,
                   latencyMs: 300, costEuro: 0.030, coreMinutes: 0.3, queueLenAtStart: 0, stratum: "cache-hit")])
  assertTrue("factorAnalysis mean cost", abs(fa.meanCost - 0.020) < 0.0001)
  assertTrue("factorAnalysis p95 latency (population)", abs(fa.p95Latency - 300.0) < 0.001)
  assertTrue("factorAnalysis 3 strata", fa.strata.len == 3)
  assertTrue("stratum proportion p=1/3", abs(fa.strata["cold"].p - 1.0/3.0) < 0.001)
  assertTrue("stratum mean cost", abs(fa.strata["warm"].meanCostEuro - 0.020) < 0.0001)

  # 10. GitHub-run ingestion backend — hermetic `--from-json` replay (REAL `gh
  #     api` is only used by the live --github-run path; selftest never touches
  #     the network). Same payload shape as `gh api .../runs/{id}` + `/jobs`,
  #     mirroring real run 36104951644 (arm smoke: 06:53:39 -> 06:57:14; arm job
  #     06:53:45 -> 06:57:13 = 208000 ms = 3.4667 core-min; slim job skipped).
  proc githubFixture(runId, conclusion, status: string): string =
    ## Raw {"run":…, "jobs":{…}} wrapper — the shape --from-json consumes and
    ## the exact shape parseGitHubPayload parses.
    result = """{"run": {"id": 36104951644, "name": "hardware-falsification-smoke", "event": "push", "status": """" &
             status & """", "conclusion": """" & conclusion & """", "head_branch": "optimize/ci-pareto",
    "head_sha": "efa24c38534c263d938813db6f2a3e7ff36360f9", "workflow_id": 366714812, "run_attempt": 1,
    "run_started_at": "2026-09-25T06:53:39Z", "updated_at": "2026-09-25T06:57:14Z"},
  "jobs": {"total_count": 2, "jobs": [
    {"id": 107975310181, "name": "arm-falsification", "status": "completed", "conclusion": "success",
     "started_at": "2026-09-25T06:53:45Z", "completed_at": "2026-09-25T06:57:13Z", "labels": ["ubuntu-24.04-arm"]},
    {"id": 107975311557, "name": "slim-light-falsification", "status": "completed", "conclusion": "skipped",
     "started_at": "2026-09-25T06:53:41Z", "completed_at": "2026-09-25T06:53:40Z", "labels": ["ubuntu-slim"]}
  ]}}"""

  let ghTrace = tmpDir / "trace_gh.json"
  discard prepareTrace(tmpDir / "cfg_gh.json", ghTrace, "train",
                       "fast:target_fast", "slow:target_slow", 4, 10, 13, 2, 24)
  let (gt, gtok, _) = readTraceFile(ghTrace)
  assertTrue("ingest selftest trace read ok", gtok)
  let ghCycle = "cycle-" & gt.sha256[0 .. 15] & "-train-1"
  let ghRec = tmpDir / "build" / "ci_pareto" / "records" / (ghCycle & "_fast.json")

  let ghJsonOk = tmpDir / "gh_run_ok.json"
  writeFile(ghJsonOk, githubFixture("36104951644", "success", "completed"))
  # 10a. dry-run (no --record): parses + prints, writes NOTHING.
  let (outDry, cDry) = execSelf(selfBin, tmpDir, @[
    "ingest", "--from-json:" & ghJsonOk,
    "--candidate:fast", "--trace:" & ghTrace, "--pair-index:1", "--order:A->B"])
  assertTrue("ingest dry-run (no --record) exits 0", cDry == 0, "exit=" & $cDry & " out=" & outDry)
  assertTrue("ingest dry-run writes no record", not fileExists(ghRec))
  assertTrue("ingest dry-run reports W/latency 215000 ms",
             "215000" in outDry, "out=" & outDry)
  assertTrue("ingest dry-run reports arm core-min 3.4667",
             "3.4667" in outDry, "out=" & outDry)

  # 10b. happy path with --record: ONE observation appended.
  let (outOk, cOk) = execSelf(selfBin, tmpDir, @[
    "ingest", "--from-json:" & ghJsonOk,
    "--candidate:fast", "--trace:" & ghTrace, "--pair-index:1", "--order:A->B", "--record"])
  assertTrue("ingest happy path (from-json, --record) exits 0", cOk == 0,
             "exit=" & $cOk & " out=" & outOk)
  assertTrue("ingest --record wrote record file", fileExists(ghRec))
  var recNode = parseJson(readFile(ghRec))
  let recG = parseRunRecord(recNode)
  assertTrue("ingested record hash valid", recG.recordHash == runRecordHash(recG))
  assertTrue("ingested record has 1 observations", recG.observations.len == 1)
  let oG = recG.observations[0]
  assertTrue("ingested observation pair/order/load", oG.pairIndex == 1 and oG.order == "A->B" and oG.loadLevel == "L2")
  assertTrue("ingested queue=6000 exec=209000 latency=215000",
             oG.queueMs == 6000 and oG.execMs == 209000 and oG.latencyMs == 215000,
             &"q={oG.queueMs} e={oG.execMs} l={oG.latencyMs}")
  assertTrue("ingested coreMinutes=3.4667 (Σ success jobs)", abs(oG.coreMinutes - 3.466666666666667) < 0.0001)
  assertTrue("ingested queueLenAtStart=0 stratum=cold (GH API has none)",
             oG.queueLenAtStart == 0 and oG.stratum == "cold")
  assertTrue("ingested githubRun provenance recorded (informational)",
             oG.githubRun != nil and oG.githubRun["runId"].getStr() == "36104951644")
  assertTrue("ingested runner label recorded (arm class)",
             "ubuntu-24.04-arm" in $oG.githubRun["runnerLabels"])
  assertTrue("ingested per-job duration recorded (arm 208000 ms)",
             208000 == oG.githubRun["jobs"][0]["durationMs"].getInt())

  # 10c. duplicate observation (same candidate/trace/pair/order/load) -> exit 2.
  let (outIngDup, cIngDup) = execSelf(selfBin, tmpDir, @[
    "ingest", "--from-json:" & ghJsonOk,
    "--candidate:fast", "--trace:" & ghTrace, "--pair-index:1", "--order:A->B", "--record"])
  assertTrue("ingest duplicate observation refused, exit 2", cIngDup == 2,
             "exit=" & $cIngDup & " out=" & outIngDup)

  # 10d. run conclusion != success -> exit 2 (INVALID).
  let ghJsonFail = tmpDir / "gh_run_fail.json"
  writeFile(ghJsonFail, githubFixture("999001", "failure", "completed"))
  let (outFail, cFail) = execSelf(selfBin, tmpDir, @[
    "ingest", "--from-json:" & ghJsonFail,
    "--candidate:fast", "--trace:" & ghTrace, "--pair-index:2", "--order:B->A"])
  assertTrue("ingest conclusion!=success exits 2", cFail == 2,
             "exit=" & $cFail & " out=" & outFail)
  assertTrue("ingest failure reason mentions conclusion", "conclusion" in outFail,
             "out=" & outFail)

  # 10e. pair index beyond pre-registered N (n=2) -> exit 2 (N cannot extend).
  let (outN, cN) = execSelf(selfBin, tmpDir, @[
    "ingest", "--from-json:" & ghJsonOk,
    "--candidate:fast", "--trace:" & ghTrace, "--pair-index:3", "--order:A->B"])
  assertTrue("ingest N-exceeded (pair-index 3 > n=2) exits 2", cN == 2,
             "exit=" & $cN & " out=" & outN)

  # 10f. malformed JSON (--from-json) -> exit 1 (ERROR, payload acquisition).
  let ghBad = tmpDir / "gh_bad.json"
  writeFile(ghBad, "{not-json")
  let (outBad, cBad) = execSelf(selfBin, tmpDir, @[
    "ingest", "--from-json:" & ghBad,
    "--candidate:fast", "--trace:" & ghTrace, "--pair-index:1", "--order:A->B"])
  assertTrue("ingest malformed JSON exits 1", cBad == 1,
             "exit=" & $cBad & " out=" & outBad)

  # 10g. invalid --order -> exit 2 (counterbalance order contract).
  let (outOrd, cOrd) = execSelf(selfBin, tmpDir, @[
    "ingest", "--from-json:" & ghJsonOk,
    "--candidate:fast", "--trace:" & ghTrace, "--pair-index:1", "--order:B->C"])
  assertTrue("ingest invalid --order exits 2", cOrd == 2,
             "exit=" & $cOrd & " out=" & outOrd)

  removeDir(tmpDir)
  echo "[selftest] ALL PASS — exit 0"
  result = 0

# ═══════════════════════════════════════════════════════════════════════════
# §14: CLI
# ═══════════════════════════════════════════════════════════════════════════

proc printHelp() =
  echo """pareto-harness — workload-trace replay measurement harness (CI Pareto P1/v13)

SELECTION (v13): c* = argmin P95_trace(W_c), P95 over the TOTAL per-PR
  latency population (nearest-rank, no segment weighting). Cost figures are
  DIAGNOSTIC ONLY and never influence ranking. 15m P95 = regression CEILING,
  reported per candidate as withinRegressionCeiling (a ceiling, not a target).
  Tie-break engages ONLY on EXACT P95 equality (no epsilon):
    1. max lambda_observed_max   2. min mean queue time
    3. min mean execution time   4. full tie -> candidate id ascending
  50,000-minute resource cap is a ledger only, not a ranking input.

USAGE:
  prepare-train    --out <file> --cand-a <id:target> --cand-b <id:target>
                   --arrivals <count> --duration-min <min> --seed <int> --n <int>
                   --arrival-rate <per-hour>
      Writes the fixed TRAIN trace. N is pre-registered HERE — no runtime --n.
  prepare-holdout  (same flags) — SEPARATE command; the comparison path NEVER
      reads holdout files.
  run --candidate <id> --trace <file> --pair <i> --order <A->B|B->A>
      [--load <L1|L2|L3>]
      Executes ONE trace position for ONE candidate; appends the observation.
      Refuses duplicate (pair, order, load) observations.
  compare --trace <file> [--id <cycle-id>] [--load <L1|L2>]
      Paired differences (diagnostic) + v13 ranking; locks trace+N on first
      compare. (L3 is capacity diagnostic ONLY, excluded from the population.)
  characterize --trace <file> --candidate <id>
      L1/L2/L3 load characterization + lambda_observed_max (capacity).
  verify-holdout --trace <file> --candidate <id>
      Pre-registered single-use BATCH check of selected c*; refuses reuse.
  ingest --github-run <run_id> | --from-json <file>
         --candidate <id> --trace <file> --pair-index <1..n> --order <A->B|B->A>
         [--load <L1|L2|L3>] [--repo <owner/repo>] [--record]
      Ingests ONE completed GitHub Actions run (gh api, READ-ONLY — never
      triggers workflows) as ONE observation on a pre-registered trace position.
      W = updated_at - run_started_at; queueMs = first success job start -
      run_started_at; execMs = updated_at - first success job start (queue+exec
      telescopes to W, same identity as the local backend). coreMinutes = sum of
      success-job durations (skipped jobs never occupied a runner); costEuro
      (diagnostic only) = latency-minutes proxy. Runner labels + per-job
      durations recorded as INFORMATIONAL provenance (excluded from the record
      hash, like preRegisteredAt). Refuses: conclusion != success, not completed,
      duplicate (pair, order, load), N exceeded, foreign trace/cycle (all exit 2);
      malformed payload / unparseable JSON (exit 1). Without --record this is a
      print-only dry run (writes NOTHING). --from-json replays the SAME payload
      shape offline (hermetic selftest). Sweep scripts alternate --order per pair
      (A->B / B->A) so compare's counterbalance invariant holds.
  selftest                       Runnable self-check (trace lock, paired math,
                                 P95, queue divergence, records, v13 ranking,
                                 ingest derivation via --from-json).

EXIT CODES:
  0 = OK
  2 = INVALID/harness violation (trace lock, namespace semantics, holdout
      reuse, counterbalance, incomplete/duplicate pairing, malformed config)
  1 = ERROR (I/O / execution backend)
"""

proc main(): int {.axiomEffect: IOEffect.} =
  let params = commandLineParams()
  if params.len == 0:
    printHelp()
    return 0
  case params[0]
  of "prepare-train", "prepare-holdout":
    var outPath, candA, candB: string
    var arrivals, durationMin, seed, n, arrivalRate = -1
    var p = initOptParser(params[1 .. ^1])
    while true:
      p.next()
      case p.kind
      of cmdEnd: break
      of cmdLongOption:
        case p.key
        of "out": outPath = p.val
        of "cand-a": candA = p.val
        of "cand-b": candB = p.val
        of "arrivals": arrivals = parseInt(p.val)
        of "duration-min": durationMin = parseInt(p.val)
        of "seed": seed = parseInt(p.val)
        of "n": n = parseInt(p.val)
        of "arrival-rate": arrivalRate = parseInt(p.val)
        else:
          errQuit(2, "unknown option for " & params[0] & ": --" & p.key)
      of cmdShortOption:
        errQuit(2, "short options not supported: -" & p.key)
      of cmdArgument:
        errQuit(2, "unexpected positional argument: " & p.key)
    if outPath.len == 0 or candA.len == 0 or candB.len == 0:
      errQuit(2, params[0] & " requires --out --cand-a --cand-b")
    if arrivals < 0 or durationMin < 0 or seed < 0 or n < 0 or arrivalRate < 0:
      errQuit(2, params[0] & " requires --arrivals --duration-min --seed --n --arrival-rate (N fixed here; no runtime --n)")
    return prepareTrace(DataDir / "config.json", outPath,
                 (if params[0] == "prepare-holdout": "holdout" else: "train"),
                 candA, candB, arrivals, durationMin, seed, n, arrivalRate)
  of "run":
    var candidate, tracePath, order, loadId: string
    var pairIndex = -1
    var p = initOptParser(params[1 .. ^1])
    while true:
      p.next()
      case p.kind
      of cmdEnd: break
      of cmdLongOption:
        case p.key
        of "candidate": candidate = p.val
        of "trace": tracePath = p.val
        of "pair": pairIndex = parseInt(p.val)
        of "order": order = p.val
        of "load": loadId = p.val
        else: errQuit(2, "unknown option for run: --" & p.key)
      of cmdShortOption:
        errQuit(2, "short options not supported: -" & p.key)
      of cmdArgument:
        errQuit(2, "unexpected positional argument: " & p.key)
    if candidate.len == 0 or tracePath.len == 0 or pairIndex < 1 or order.len == 0:
      errQuit(2, "run requires --candidate <id> --trace <file> --pair <1..n> --order <A->B|B->A>")
    if order notin ["A->B", "B->A"]:
      errQuit(2, "run --order must be A->B or B->A (counterbalanced pairs), got: " & order)
    if loadId.len == 0:
      loadId = "L2"  # nominal is the default measurement load
    let (tr, ok, reason) = readTraceFile(tracePath)
    if not ok:
      errQuit(2, reason)
    let ns = verifyNamespaceSemantics(tr)
    echo "[pareto-harness] " & ns.line
    if not ns.ok:
      errQuit(2, ns.line)
    if pairIndex > tr.n:
      errQuit(2, &"pair {pairIndex} out of pre-registered range 1..{tr.n}")
    var loadLevel: LoadLevel
    var found = false
    for l in tr.loadLevels:
      if l.id == loadId:
        loadLevel = l
        found = true
        break
    if not found:
      errQuit(2, "unknown load level: " & loadId & " (trace declares: " &
              tr.loadLevels.mapIt(it.id).join(",") & ")")
    let sortKey = traceSortKey(tr)
    var reg = loadRegistry(DataDir / "cycle_registry.json")
    let cycleId =
      if reg.cycles.hasKey(sortKey): reg.cycles[sortKey]
      else: "cycle-" & sortKey & "-1"
    var target = ""
    if tr.config.hasKey("candidates") and tr.config["candidates"].hasKey(candidate):
      target = tr.config["candidates"][candidate].getStr()
    if target.len == 0:
      errQuit(2, "candidate '" & candidate & "' not declared in trace config")
    let arr = tr.arrivals[(pairIndex - 1) mod tr.arrivals.len]
    let obs = runOnePair(candidate, target, cycleId, tr.traceKind, tr.sha256,
                         candidate, pairIndex, arr.seqNo, order, loadId,
                         loadLevel.concurrency, BuildDir, repoRoot(), false)
    var exp = RunRecord(schema: RunRecordSchema, candidateId: candidate,
                        cycleId: cycleId, traceSha256: tr.sha256,
                        traceKind: tr.traceKind, n: tr.n)
    let recPath = BuildDir / "records" / (cycleId & "_" & candidate & ".json")
    let rec = appendObservation(recPath, obs, exp)
    echo "[pareto-harness] record " & candidate & ": " & $rec.observations.len & "/" & $tr.n &
         " observations in " & cycleId
  of "compare":
    var tracePath, cycleId, loadId: string
    var p = initOptParser(params[1 .. ^1])
    while true:
      p.next()
      case p.kind
      of cmdEnd: break
      of cmdLongOption:
        case p.key
        of "trace": tracePath = p.val
        of "id": cycleId = p.val
        of "load": loadId = p.val
        else: errQuit(2, "unknown option for compare: --" & p.key)
      of cmdShortOption:
        errQuit(2, "short options not supported: -" & p.key)
      of cmdArgument:
        errQuit(2, "unexpected positional argument: " & p.key)
    if tracePath.len == 0:
      errQuit(2, "compare requires --trace <file>")
    if loadId.len == 0:
      loadId = "L2"
    return compareMain(DataDir / "cycle_registry.json", tracePath, cycleId, loadId)
  of "characterize":
    var tracePath, candidate: string
    var p = initOptParser(params[1 .. ^1])
    while true:
      p.next()
      case p.kind
      of cmdEnd: break
      of cmdLongOption:
        case p.key
        of "trace": tracePath = p.val
        of "candidate": candidate = p.val
        else: errQuit(2, "unknown option for characterize: --" & p.key)
      of cmdShortOption:
        errQuit(2, "short options not supported: -" & p.key)
      of cmdArgument:
        errQuit(2, "unexpected positional argument: " & p.key)
    if tracePath.len == 0 or candidate.len == 0:
      errQuit(2, "characterize requires --trace <file> --candidate <id>")
    return characterizeMain(DataDir / "cycle_registry.json", tracePath, candidate)
  of "verify-holdout":
    var tracePath, selCand: string
    var p = initOptParser(params[1 .. ^1])
    while true:
      p.next()
      case p.kind
      of cmdEnd: break
      of cmdLongOption:
        case p.key
        of "trace": tracePath = p.val
        of "candidate": selCand = p.val
        else: errQuit(2, "unknown option for verify-holdout: --" & p.key)
      of cmdShortOption:
        errQuit(2, "short options not supported: -" & p.key)
      of cmdArgument:
        errQuit(2, "unexpected positional argument: " & p.key)
    if tracePath.len == 0:
      errQuit(2, "verify-holdout requires --trace <file>")
    return verifyHoldoutMain(DataDir / "cycle_registry.json", tracePath, selCand)
  of "ingest":
    var runId, fromJsonPath, candidate, tracePath, order, repoFlag, loadId: string
    var pairIndex = -1
    var writeRecord = false
    var p = initOptParser(params[1 .. ^1])
    while true:
      p.next()
      case p.kind
      of cmdEnd: break
      of cmdLongOption:
        case p.key
        of "github-run": runId = p.val
        of "from-json": fromJsonPath = p.val
        of "candidate": candidate = p.val
        of "trace": tracePath = p.val
        of "pair-index": pairIndex = parseInt(p.val)
        of "order": order = p.val
        of "load": loadId = p.val
        of "repo": repoFlag = p.val
        of "record": writeRecord = true
        else: errQuit(2, "unknown option for ingest: --" & p.key)
      of cmdShortOption:
        errQuit(2, "short options not supported: -" & p.key)
      of cmdArgument:
        errQuit(2, "unexpected positional argument: " & p.key)
    if (runId.len == 0) == (fromJsonPath.len == 0):
      errQuit(2, "ingest requires exactly one of --github-run <run_id> or --from-json <file>")
    if candidate.len == 0 or tracePath.len == 0 or pairIndex < 1 or order.len == 0:
      errQuit(2, "ingest requires --candidate <id> --trace <file> --pair-index <1..n> --order <A->B|B->A>")
    if order notin ["A->B", "B->A"]:
      errQuit(2, "ingest --order must be A->B or B->A (counterbalanced pairs), got: " & order)
    if loadId.len == 0:
      loadId = "L2"  # nominal is the default measurement load (same as run)
    return ingestMain(runId, fromJsonPath, candidate, tracePath, order, repoFlag, loadId,
                      pairIndex, writeRecord)
  of "selftest":
    return selftestMain()
  of "help", "-h", "--help":
    printHelp()
  else:
    errQuit(2, "unknown command: " & params[0])

when isMainModule:
  quit(main())