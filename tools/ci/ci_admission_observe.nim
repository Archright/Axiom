## tools/ci/ci_admission_observe.nim — cross-workflow admission-wall observer.
##
## REPORTER ONLY. No merge authority, no policy mutation, no required-check
## change, no workflow re-run. GET-only `gh api` calls (AGENTS.md §2.4 delegates
## GitHub auth to the native client).
##
## WHY THIS EXISTS (the gap it closes)
##   `docs/spec/ci_acceptance_contract.md` §6 defines the canonical wall as the
##   job span of ONE workflow run, and its entry is the `admission-gate` workflow.
##   The merge authority (ruleset `main`, `config/policy/merge_admission.json`)
##   requires SEVEN contexts produced by SEVEN workflows, so an optimization
##   inside e.g. `publication-integrity` can move the true admission wall while
##   the canonical wall does not move at all. This tool measures the seven
##   contexts on one merge-group candidate and partitions the interval between
##   queue entry and merge.
##
## WHAT IT DOES NOT DO (no duplicate authority)
##   * It does NOT redefine the canonical wall. `docs/spec/ci_critical_path_metric.md`
##     §2.1 cites the acceptance contract; this module cites both and computes a
##     DIFFERENT quantity (cross-workflow admission), never a replacement.
##   * It does NOT re-select the cohort. `--cohort-from <collector report.json>`
##     consumes the entries `ci_acceptance_collect` already selected, so both
##     tools describe the SAME candidates.
##   * Per-context completion instants are an OVERLAY (they may overlap). Only
##     the four phases partition [queue entry, merge].
##
## PHASE MODEL (non-overlapping by construction)
##   T_queue       = first required context started_at - queue entry
##   T_verify      = last general context completed_at - first required context started_at
##   T_publication = max(all 7 completed_at) - last general completed_at
##   T_merge       = merged - max(all 7 completed_at)
##   T_ready       = T_queue + T_verify + T_publication
##   T_admission   = T_ready + T_merge
##   "general" = a required context whose expected producer is the Actions app.
##   The App verdict context (`admission-check`) is reported separately: it is the
##   only context whose producer is an independent App, and it is published
##   WITHOUT an Actions run of its own.
##   `T_exec` is deliberately absent: it equals T_verify + T_publication and
##   summing it again would double-count (measured #420: 436 + 3 = 439).
##
## PERCENTILES
##   p50 is imported from the canonical collector, so it is the same estimator the
##   acceptance contract fixes. p90 uses Hyndman-Fan type 7 on the same sorted
##   integer-second array. Nearest-rank is NOT used: the contract's p50 is exactly
##   R-7 at p = 0.5, and mixing estimator families inside one report would allow
##   p90 < p50 and make the pair uninterpretable.
##
## BINDING (fail-closed; any ambiguity => UNKNOWN, never a guess)
##   Documented facts this relies on (measured against the live API):
##     a. `filter=latest` (the API default) is scoped per CHECK SUITE, not per
##        context, so it returns same-name duplicates across suites. This tool
##        always requests `filter=all`.
##     b. `admission-check` is published by BOTH app 15368 (Actions) and app
##        5795152 (axiom-admission-verifier) on the same SHA. A producer app id
##        is therefore mandatory; `(name, head_sha)` alone is ambiguous.
##     c. One check suite spans EVERY attempt of a run, so `check_suite.id`
##        identifies the RUN but not the producing ATTEMPT. The only documented
##        per-attempt edge is `GET /actions/runs/{id}/attempts/{n}/jobs`, whose
##        jobs carry `check_run_url` ending in the check-run id.
##     d. `GET /check-suites/{id}` does NOT expose `workflow_run_id`.
##     e. `job.run_attempt` / `workflow_run.runAttempt` report the run's CURRENT
##        counter, not the attempt that produced a given check-run — an attempt-1
##        check-run reports runAttempt = 2 after a re-run. Never used here.
##   Therefore a general context is OBSERVED only when its check-run id appears in
##   the attempt-exact job set of the merge-group run whose `path` is the context's
##   declared workflow. The App verdict context is OBSERVED only when its app id
##   matches the expected producer AND its start falls inside the attempt window.
##   Anything else is UNKNOWN with the reason recorded.
##
## DETERMINISM
##   Determinism is "the same observation snapshot yields the same numbers", not
##   "re-fetching yields the same snapshot". The report records the identity of
##   every input (cohort head_sha list, run ids, run_attempt, check-run ids, app
##   ids, queue ref, timestamps), so the computation is replayable from the
##   snapshot. Live GitHub state may gain events afterwards; that is outside the
##   snapshot and is never silently folded in.
##
## Exit: 0 OBSERVED (every candidate bound and reconciled);
##       1 FAILED (policy/ruleset authority mismatch, or a reconciliation failure);
##       2 INCOMPLETE (at least one candidate UNKNOWN, or the cohort unreadable).

import std/[algorithm, json, os, osproc, strutils, tables]

import core/trusted/layer_declaration
import core/trusted/axiom_pragmas_lite
axiomLayer "tools"

from ./ci_acceptance_collect import p50Seconds, parseIsoUtc, meanSeconds,
  formatOneDecimal

const
  ToolName* = "ci_admission_observe"
  SchemaVersion* = "axiom.ci_admission_observe.v1"
  DefaultRepo* = "Archright/Axiom"
  PolicyPath* = "config/policy/merge_admission.json"
  ActionsAppId* = 15368
  DefaultOutDir* = "build" / "ci_admission"
  P90Estimator* = "hyndman-fan-7"
  P50Estimator* = "canonical-collector (== R-7 at p=0.5)"
  MaxPages* = 10

type
  Outcome* = enum
    ocObserved = "OBSERVED"
    ocUnknown = "UNKNOWN"

  CheckState* = object
    context*: string
    workflowPath*: string
    isAppVerdict*: bool
    expectedAppId*: int
    observedAppId*: int
    checkRunId*: string
    suiteId*: string
    runId*: string
    runAttempt*: int
    status*: string
    conclusion*: string
    startedAt*: string
    completedAt*: string
    bound*: bool
    unboundReason*: string

  PhaseSpan* = object
    name*: string
    startAt*: string
    endAt*: string
    seconds*: int

  DagStatus* = enum
    dsMeasured = "MEASURED"
    dsUnknown = "UNKNOWN"          ## an input is unobservable; never a guess
    dsFailed = "FAILED"            ## the observation contradicts the contract

  JobRecord* = object
    ## One job object of GET /actions/runs/{id}/attempts/{n}/jobs.
    ## `createdAt` is NOT part of the documented Jobs REST object. It is observed
    ## in practice; its absence is reported as NO_LOG_SOURCE, never as 0.
    name*: string
    runId*: string
    runAttempt*: int
    headSha*: string
    status*: string
    conclusion*: string
    startedAt*: string
    completedAt*: string
    createdAt*: string

  Bucket* = object
    ## Every record whose name attributes to one declared job id.
    jobId*: string
    members*: int
    skippedMembers*: int
    startedAt*: string             ## min over members that carry one
    completedAt*: string           ## MAX over the bucket — never min, never "any"
    createdAt*: string             ## min over members; "" when none carried one
    allSuccess*: bool
    seconds*: int                  ## max(0, completed - started)

  JobNameDecl* = object
    jobId*: string
    name*: string                  ## a job-level `name:` REPLACES the record name

  WorkflowGraph* = object
    jobs*: seq[string]             ## sorted job ids declared under `jobs:`
    needs*: seq[tuple[jobId, need: string]]
    jobNames*: seq[JobNameDecl]
    blobSha*: string               ## git blob sha of the YAML, recorded in the report
    yamlRef*: string               ## the sha the YAML was read at

  DagResult* = object
    status*: DagStatus
    reason*: string
    workflowPath*: string
    blobSha*: string
    yamlRef*: string
    runId*: string
    runAttempt*: int
    headSha*: string
    recordCount*: int
    declaredJobs*: seq[string]
    buckets*: seq[Bucket]
    criticalPathSeconds*: int
    criticalPath*: seq[string]
    wallSeconds*: int
    shareOfWall*: float            ## criticalPathSeconds / wallSeconds of THIS workflow
    lowerBound*: bool              ## an edge weight was unobservable
    anomalies*: seq[string]
    queue*: QueueReport

  QueueSample* = object
    jobId*: string
    batch*: int
    seconds*: int

  QueueReport* = object
    ## First-batch queueing and dependency handoff are DIFFERENT phenomena and are
    ## never summed together: the first is runner assignment, the second is a
    ## `needs:` edge. `status` is NO_LOG_SOURCE when `created_at` is absent.
    status*: string
    firstBatch*: seq[QueueSample]
    handoff*: seq[QueueSample]
    anomalies*: seq[string]

  Candidate* = object
    prNumber*: int
    headSha*: string
    queueRef*: string
    queueRefSuffixMatched*: bool
    queueEntryAt*: string
    mergedAt*: string
    mergeCommit*: string
    checks*: seq[CheckState]
    phases*: seq[PhaseSpan]
    dags*: seq[DagResult]
    outcome*: Outcome
    unknownReason*: string

  Cohort* = object
    headShas*: seq[string]
    prNumbers*: seq[int]
    source*: string

  ExpectedContext* = object
    job*: string
    workflowPath*: string
    appId*: int
    isAppVerdict*: bool


# ═══════════════════════════════════════════════════════════════════════════
# §1. Pure core — estimator, interval algebra, phase partition, reconciliation
# ═══════════════════════════════════════════════════════════════════════════

func r7Percentile*(values: seq[int]; p: float): float {.raises: [].} =
  ## Hyndman-Fan type 7: h = (n-1)p, linear interpolation between neighbours.
  ## At p = 0.5 this is identical to the canonical collector's p50Seconds.
  if values.len == 0:
    return 0.0
  var v = values
  v.sort()
  if v.len == 1:
    return float(v[0])
  let h = float(v.len - 1) * p
  let lo = int(h)
  let frac = h - float(lo)
  if lo >= v.high:
    return float(v[^1])
  float(v[lo]) + frac * (float(v[lo + 1]) - float(v[lo]))

func epochOf*(s: string): int64 {.raises: [].} =
  let (v, ok) = parseIsoUtc(s)
  if ok: v else: -1'i64

func secsBetween*(later, earlier: string): int {.raises: [].} =
  ## Whole seconds from `earlier` to `later`; -1 when either is unparsable or the
  ## ordering is violated. An interval that cannot exist is never returned as 0.
  let a = epochOf(later)
  let b = epochOf(earlier)
  if a < 0 or b < 0 or a < b:
    return -1
  int(a - b)

func earliestStart*(checks: seq[CheckState]): string {.raises: [].} =
  result = ""
  for c in checks:
    if not c.bound or c.startedAt.len == 0:
      continue
    if result.len == 0 or c.startedAt < result:
      result = c.startedAt

func latestCompletion*(checks: seq[CheckState]): string {.raises: [].} =
  result = ""
  for c in checks:
    if not c.bound or c.completedAt.len == 0:
      continue
    if result.len == 0 or c.completedAt > result:
      result = c.completedAt

func latestGeneralCompletion*(checks: seq[CheckState]): string {.raises: [].} =
  result = ""
  for c in checks:
    if not c.bound or c.isAppVerdict or c.completedAt.len == 0:
      continue
    if result.len == 0 or c.completedAt > result:
      result = c.completedAt

func buildPhases*(queueEntryAt, mergedAt: string;
                  checks: seq[CheckState]): seq[PhaseSpan] {.raises: [].} =
  ## Partitions [queue entry, merged] into four non-overlapping phases. Returns an
  ## empty seq when any required instant is unobservable — a partial partition is
  ## never emitted as if it were complete.
  let firstStart = earliestStart(checks)
  let lastGeneral = latestGeneralCompletion(checks)
  let ready = latestCompletion(checks)
  if queueEntryAt.len == 0 or mergedAt.len == 0 or firstStart.len == 0 or
     lastGeneral.len == 0 or ready.len == 0:
    return @[]
  let q = secsBetween(firstStart, queueEntryAt)
  let v = secsBetween(lastGeneral, firstStart)
  let p = secsBetween(ready, lastGeneral)
  let m = secsBetween(mergedAt, ready)
  if q < 0 or v < 0 or p < 0 or m < 0:
    return @[]
  @[
    PhaseSpan(name: "queue", startAt: queueEntryAt, endAt: firstStart, seconds: q),
    PhaseSpan(name: "verify", startAt: firstStart, endAt: lastGeneral, seconds: v),
    PhaseSpan(name: "publication", startAt: lastGeneral, endAt: ready, seconds: p),
    PhaseSpan(name: "merge", startAt: ready, endAt: mergedAt, seconds: m)]

func phaseSum*(phases: seq[PhaseSpan]): int {.raises: [].} =
  var total = 0
  for p in phases:
    total += p.seconds
  total

func reconcile*(phases: seq[PhaseSpan]; queueEntryAt, mergedAt: string):
    tuple[ok: bool, sumSeconds: int, totalSeconds: int, residue: int] {.raises: [].} =
  ## Fail-closed identity: the four phases must cover the whole interval. A
  ## residue is never absorbed into a phase and never dropped silently.
  if phases.len == 0:
    return (false, 0, 0, 0)
  let total = secsBetween(mergedAt, queueEntryAt)
  if total < 0:
    return (false, 0, 0, 0)
  let s = phaseSum(phases)
  (s == total, s, total, total - s)

func phaseSeconds*(phases: seq[PhaseSpan]; name: string): int {.raises: [].} =
  for p in phases:
    if p.name == name:
      return p.seconds
  -1

func readySeconds*(phases: seq[PhaseSpan]): int {.raises: [].} =
  let q = phaseSeconds(phases, "queue")
  let v = phaseSeconds(phases, "verify")
  let p = phaseSeconds(phases, "publication")
  if q < 0 or v < 0 or p < 0: -1 else: q + v + p

func admissionSeconds*(phases: seq[PhaseSpan]): int {.raises: [].} =
  let r = readySeconds(phases)
  let m = phaseSeconds(phases, "merge")
  if r < 0 or m < 0: -1 else: r + m

func lastFinisher*(checks: seq[CheckState]): string {.raises: [].} =
  ## Which context completed last. Ties break lexicographically on the context
  ## name, so the answer is deterministic and independent of input order.
  result = ""
  var best = ""
  for c in checks:
    if not c.bound or c.completedAt.len == 0:
      continue
    if c.completedAt > best or (c.completedAt == best and c.context < result):
      best = c.completedAt
      result = c.context

func distinctSorted*(values: seq[string]): seq[string] {.raises: [].} =
  var v = values
  v.sort()
  result = @[]
  var prev = ""
  var first = true
  for x in v:
    if first or x != prev:
      result.add x
      prev = x
      first = false

func sameContextSet*(a, b: seq[string]): bool {.raises: [].} =
  if a.len != b.len:
    return false
  distinctSorted(a) == distinctSorted(b)

# ═══════════════════════════════════════════════════════════════════════════
# §2. Policy — the required-context set and its expected producers
# ═══════════════════════════════════════════════════════════════════════════

func at*(n: JsonNode; key: string): JsonNode {.raises: [].} =
  ## Indexing a JsonNode raises KeyError; this returns nil instead, which keeps
  ## every reader in this module inside an empty raises list.
  if n.isNil or n.kind != JObject:
    return nil
  n.getOrDefault(key)

func jsonStr(n: JsonNode; key: string): string {.raises: [].} =
  let v = at(n, key)
  if v.isNil:
    return ""
  case v.kind
  of JString: v.getStr()
  else: ""

func jsonId*(n: JsonNode; key: string): string {.raises: [].} =
  ## GitHub identifiers arrive as JSON NUMBERS (`run.id`, `check_run.id`,
  ## `check_suite.id`, `app.id`) far more often than as strings. Reading them with
  ## jsonStr silently yields "" and produces a URL like `.../runs//attempts/1`,
  ## so every id goes through this reader instead.
  let v = at(n, key)
  if v.isNil:
    return ""
  case v.kind
  of JString: v.getStr()
  of JInt: $v.getInt()
  else: ""

func jsonInt(n: JsonNode; key: string): int {.raises: [].} =
  let v = at(n, key)
  if v.isNil:
    return 0
  case v.kind
  of JInt: v.getInt()
  else: 0

func expectedContextsFromPolicy*(node: JsonNode):
    tuple[contexts: seq[ExpectedContext], err: string] {.raises: [].} =
  ## Derives the required set the way tools/merge_ruleset_drift_monitor.nim does:
  ## requiredValidations[].job UNION requiredWorkflowDetection.verdictJob.
  ## Producer ids come from requiredCheckSources (default + byContext); an absent
  ## map keeps the legacy shape (every context from the Actions app).
  if node.isNil or node.kind != JObject:
    return (@[], "policy is not a JSON object")
  var defaultApp = ActionsAppId
  var byContext = initTable[string, int]()
  let rcs = at(node, "requiredCheckSources")
  if not rcs.isNil and rcs.kind == JObject:
    if rcs.hasKey("default"):
      defaultApp = jsonInt(rcs, "default")
    let perContext = at(rcs, "byContext")
    if not perContext.isNil and perContext.kind == JObject:
      for k, v in pairs(perContext):
        if v.kind == JInt:
          byContext[k] = v.getInt()

  var acc: seq[ExpectedContext] = @[]
  var seen = initTable[string, bool]()

  let validations = at(node, "requiredValidations")
  if not validations.isNil and validations.kind == JArray:
    for e in items(validations):
      if e.kind != JObject or not e.hasKey("job"):
        continue
      let job = jsonStr(e, "job")
      if job.len == 0 or seen.hasKey(job):
        continue
      seen[job] = true
      var app = defaultApp
      if byContext.hasKey(job):
        app = byContext.getOrDefault(job, defaultApp)
      acc.add ExpectedContext(job: job, workflowPath: jsonStr(e, "workflowPath"),
                              appId: app, isAppVerdict: app != ActionsAppId)

  let det = at(node, "requiredWorkflowDetection")
  if not det.isNil and det.kind == JObject:
    let job = jsonStr(det, "verdictJob")
    if job.len > 0 and not seen.hasKey(job):
      # The verdict check-run is published by an independent App, not by the
      # Actions app, and `admission-check` is ALSO published by app 15368 on the
      # same SHA. Defaulting the producer would therefore bind the wrong
      # check-run without any signal, so an absent/contradictory declaration is
      # fail-closed here rather than "legacy shape".
      var app = 0
      var declared = 0
      for k, v in byContext.pairs:
        if k == job:
          app = v
      declared = jsonInt(at(det, "verdictCheckSource"), "appId")
      if app != 0 and declared != 0 and app != declared:
        return (@[], "verdict producer is declared twice with different ids (" &
                    $app & " vs " & $declared & ")")
      if app == 0:
        app = declared
      if app == 0 or app == ActionsAppId:
        return (@[], "verdict job '" & job & "' has no independent App producer; " &
                    "the Actions app also publishes this context name, so the " &
                    "producer must be declared explicitly")
      acc.add ExpectedContext(job: job, workflowPath: jsonStr(det, "workflowPath"),
                              appId: app, isAppVerdict: true)

  if acc.len == 0:
    return (@[], "policy declares no required contexts")
  acc.sort(proc (a, b: ExpectedContext): int = cmp(a.job, b.job))
  (acc, "")

func expectedContextNames*(contexts: seq[ExpectedContext]): seq[string] {.raises: [].} =
  for c in contexts:
    result.add c.job

# ═══════════════════════════════════════════════════════════════════════════
# §3. Check-run binding (fail-closed, attempt-exact)
# ═══════════════════════════════════════════════════════════════════════════

func suiteIdOf*(checkRun: JsonNode): string {.raises: [].} =
  let cs = at(checkRun, "check_suite")
  if cs.isNil or cs.kind != JObject:
    return ""
  let id = at(cs, "id")
  if id.isNil: "" else: $id

func appIdOf*(checkRun: JsonNode): int {.raises: [].} =
  jsonInt(at(checkRun, "app"), "id")

func checkRunIdOfJob*(job: JsonNode): string {.raises: [].} =
  ## `check_run_url` ends in the check-run id; that is the documented per-attempt
  ## discriminator (`/attempts/{n}/jobs`). The id is derived without a text join
  ## so malformed URLs fail closed rather than yielding a bogus id.
  let url = jsonStr(job, "check_run_url")
  if url.len == 0:
    return ""
  var idx = url.rfind('/')
  if idx < 0 or idx >= url.high:
    return ""
  let tail = url[idx + 1 .. ^1]
  if tail.len == 0:
    return ""
  for ch in tail:
    if ch notin {'0'..'9'}:
      return ""
  tail

func attemptCheckRunIds*(jobs: JsonNode): seq[string] {.raises: [].} =
  if jobs.kind != JArray:
    return @[]
  for j in jobs:
    let id = checkRunIdOfJob(j)
    if id.len > 0:
      result.add id
  distinctSorted(result)

func bindGeneralContext*(context: ExpectedContext; checkRuns: JsonNode;
                         attemptCheckRunIds: seq[string]; runId: string;
                         runAttempt: int): CheckState {.raises: [].} =
  ## Selects the check-run whose id is in the attempt-exact job set. Never falls
  ## back to "the newest check-run with this name".
  result = CheckState(context: context.job, workflowPath: context.workflowPath,
                      isAppVerdict: false, expectedAppId: context.appId,
                      runId: runId, runAttempt: runAttempt, bound: false)
  if checkRuns.kind != JArray:
    result.unboundReason = "check-runs payload is not an array"
    return
  if attemptCheckRunIds.len == 0:
    result.unboundReason = "attempt job set carries no check_run_url"
    return

  var best: JsonNode = nil
  for cr in checkRuns:
    if jsonStr(cr, "name") != context.job:
      continue
    let id = jsonId(cr, "id")
    if id.len == 0 or id notin attemptCheckRunIds:
      continue
    if best.isNil:
      best = cr
      continue
    # Deterministic tie-break inside one attempt: later completed_at, then id.
    let bc = jsonStr(best, "completed_at")
    let cc = jsonStr(cr, "completed_at")
    if cc > bc or (cc == bc and id > jsonId(best, "id")):
      best = cr

  if best.isNil:
    result.unboundReason = "no check-run named '" & context.job &
      "' inside this attempt's job set (attempt-exact binding failed)"
    return

  result.observedAppId = appIdOf(best)
  result.checkRunId = jsonId(best, "id")
  result.suiteId = suiteIdOf(best)
  result.status = jsonStr(best, "status")
  result.conclusion = jsonStr(best, "conclusion")
  result.startedAt = jsonStr(best, "started_at")
  result.completedAt = jsonStr(best, "completed_at")
  result.bound = result.startedAt.len > 0 and result.completedAt.len > 0
  if not result.bound:
    result.unboundReason = "selected check-run lacks both timestamps"

func bindAppVerdict*(context: ExpectedContext; checkRuns: JsonNode;
                     windowStartAt, windowEndAt: string): CheckState {.raises: [].} =
  ## The App publishes independently of the Actions run, so there is no
  ## attempt-exact job edge. Its window is therefore the QUEUE CYCLE, not the
  ## Actions run: a measured verdict started 1s BEFORE its run was created
  ## (#416: verdict 14:02:31, run created 14:02:32), so bounding on run creation
  ## would reject the real verdict. An App verdict cannot exist before the
  ## candidate entered the queue, which makes queue entry the correct floor.
  ## Producer identity remains mandatory: the same context name is ALSO
  ## published by app 15368 on the same SHA.
  result = CheckState(context: context.job, workflowPath: context.workflowPath,
                      isAppVerdict: true, expectedAppId: context.appId, bound: false)
  if checkRuns.kind != JArray:
    result.unboundReason = "check-runs payload is not an array"
    return
  var best: JsonNode = nil
  var dupCount = 0
  for cr in checkRuns:
    if jsonStr(cr, "name") != context.job:
      continue
    if appIdOf(cr) != context.appId:
      continue
    let started = jsonStr(cr, "started_at")
    if started.len == 0:
      continue
    if windowStartAt.len > 0 and secsBetween(started, windowStartAt) < 0:
      continue
    if windowEndAt.len > 0 and secsBetween(windowEndAt, started) < 0:
      continue
    inc dupCount
    if best.isNil:
      best = cr
      continue
    let bc = jsonStr(best, "completed_at")
    let cc = jsonStr(cr, "completed_at")
    if cc > bc:
      best = cr
  if best.isNil:
    result.unboundReason = "no check-run from expected app " & $context.appId &
      " started at or after the attempt"
    return
  if dupCount > 1:
    result.unboundReason = "ambiguous: " & $dupCount & " check-runs from app " &
      $context.appId & " for '" & context.job & "' in the attempt window"
    return
  result.observedAppId = appIdOf(best)
  result.checkRunId = jsonId(best, "id")
  result.suiteId = suiteIdOf(best)
  result.status = jsonStr(best, "status")
  result.conclusion = jsonStr(best, "conclusion")
  result.startedAt = jsonStr(best, "started_at")
  result.completedAt = jsonStr(best, "completed_at")
  result.bound = result.startedAt.len > 0 and result.completedAt.len > 0
  if not result.bound:
    result.unboundReason = "selected check-run lacks both timestamps"

func allBound*(checks: seq[CheckState]): tuple[ok: bool, reason: string] {.raises: [].} =
  for c in checks:
    if not c.bound:
      return (false, c.context & ": " & c.unboundReason)
  (true, "")

func authoritySubstitution*(checks: seq[CheckState]): tuple[found: bool, detail: string]
    {.raises: [].} =
  ## A bound context whose observed producer differs from the declared producer
  ## is an authority substitution, never a success.
  for c in checks:
    if not c.bound:
      continue
    if c.observedAppId != 0 and c.observedAppId != c.expectedAppId:
      return (true, c.context & ": expected app " & $c.expectedAppId &
                     ", observed " & $c.observedAppId)
  (false, "")

# ═══════════════════════════════════════════════════════════════════════════
# §4. Statistics
# ═══════════════════════════════════════════════════════════════════════════

type
  Stats* = object
    n*: int
    p50*: float
    p90*: float
    mean*: float
    minSeconds*: int
    maxSeconds*: int

func statsOf*(values: seq[int]): Stats {.raises: [].} =
  if values.len == 0:
    return Stats()
  var v = values
  v.sort()
  Stats(n: v.len, p50: p50Seconds(v), p90: r7Percentile(v, 0.9),
        mean: meanSeconds(v), minSeconds: v[0], maxSeconds: v[^1])

# ═══════════════════════════════════════════════════════════════════════════
# §4b. Workflow DAG — job-id attribution, bucket instants, critical path
#
# The four-phase partition above is a CROSS-WORKFLOW quantity and is untouched
# here. This section measures ONE workflow's own `needs:` graph. The two are
# different objects: `criticalPathShare` is a fraction of that workflow's own
# wall, never a fraction of T_admission.
#
# A reusable-workflow call (`uses:`) expands to the callee's WHOLE declared job
# set, so one caller job id owns several records — including the always-skipped
# half of the callee. Skipped records are therefore retained: dropping them
# would drop graph nodes.
# ═══════════════════════════════════════════════════════════════════════════

const
  DagSchemaVersion* = "axiom.ci_workflow_dag.v1"
  QueueLogSourceMissing* = "NO_LOG_SOURCE"

func ownRecord(jobId, recordName: string): bool {.raises: [].} =
  ## The separator is space-slash-space (matrix instances look like
  ## `"attest / go-critical-lane (0)"`).
  if jobId.len == 0 or recordName.len == 0:
    return false
  recordName == jobId or recordName.startsWith(jobId & " / ") or
    recordName.startsWith(jobId & " (")

func recordNameHead(recordName: string): string {.raises: [].} =
  ## The token before the first ` / ` or ` (`, or "" when the name carries
  ## neither separator. Used ONLY to distinguish "not attributable" (UNKNOWN)
  ## from "attributed to a job id the YAML does not declare" (hard error) — the
  ## value is never used as an attribution.
  var cut = recordName.len
  let slash = recordName.find(" / ")
  if slash >= 0 and slash < cut:
    cut = slash
  let paren = recordName.find(" (")
  if paren >= 0 and paren < cut:
    cut = paren
  if cut == recordName.len:
    return ""
  recordName[0 ..< cut].strip()

func attributeRecord*(jobIds: seq[string]; recordName: string;
                      declaredNames: seq[JobNameDecl] = @[]):
    tuple[jobId: string, reason: string] {.raises: [].} =
  ## The prefix rule, and only the prefix rule. Suffix inversion is forbidden:
  ## `attest / admission-check` and `verdict / admission-check` both end in a
  ## name that is also a top-level job id, so parsing from the right silently
  ## mis-attributes both.
  result = ("", "")
  let ids = distinctSorted(jobIds)
  var matched: seq[string] = @[]
  for id in ids:
    if ownRecord(id, recordName):
      matched.add id
  if matched.len == 1:
    return (matched[0], "")
  if matched.len > 1:
    result.reason = "job record name '" & recordName & "' attributes to " &
      $matched.len & " declared job ids (" & matched.join(", ") &
      "); the naming convention is violated"
    return
  let head = recordNameHead(recordName)
  if head.len > 0 and head notin ids:
    result.reason = "job record name '" & recordName & "' names job id '" & head &
      "', which the workflow YAML at this ref does not declare"
    return
  var renamed = ""
  for d in declaredNames:
    if d.name == recordName:
      renamed = d.jobId
  if renamed.len > 0:
    result.reason = "job record name '" & recordName & "' is the job-level " &
      "`name:` of '" & renamed & "', not a job id; attribution is impossible"
    return
  if declaredNames.len > 0:
    result.reason = "job record name '" & recordName & "' attributes to no " &
      "declared job id, and the workflow renames jobs via job-level `name:`"
    return
  result.reason = "job record name '" & recordName &
    "' attributes to no declared job id under the prefix rule"

func bucketRecords*(graph: WorkflowGraph; records: seq[JobRecord];
                    runId: string; runAttempt: int; runHeadSha: string):
    tuple[status: DagStatus, buckets: seq[Bucket], reason: string,
          anomalies: seq[string]] {.raises: [].} =
  ## Groups records onto declared job ids. Any record that contradicts the run
  ## identity (run id, attempt, head sha) is rejected: the payload would not be
  ## the attempt-exact job set the rest of this tool binds on.
  result = (dsUnknown, @[], "", @[])
  var anomalies: seq[string] = @[]
  for r in records:
    if runId.len > 0 and r.runId.len > 0 and r.runId != runId:
      return (dsFailed, @[], "job record '" & r.name & "' belongs to run " &
              r.runId & ", not to run " & runId, @[])
    if r.runAttempt != runAttempt:
      return (dsFailed, @[], "job record '" & r.name & "' reports run_attempt " &
              $r.runAttempt & ", but the payload is attempt " & $runAttempt, @[])
    if runHeadSha.len > 0 and r.headSha.len > 0 and r.headSha != runHeadSha:
      return (dsFailed, @[], "job record '" & r.name & "' carries head_sha " &
              r.headSha & " but the run carries " & runHeadSha, @[])

  var acc: seq[Bucket] = @[]
  for id in graph.jobs:
    acc.add Bucket(jobId: id, startedAt: "", completedAt: "", createdAt: "",
                   allSuccess: true)
  var indexOf = initTable[string, int]()
  for i, b in acc:
    indexOf[b.jobId] = i

  for r in records:
    let (id, reason) = attributeRecord(graph.jobs, r.name, graph.jobNames)
    if id.len == 0:
      # A name that names an undeclared job id, or a renamed job, means the YAML
      # does not describe this run — that is a contract violation, not a gap.
      let hard = reason.contains("does not declare") or reason.contains("`name:`")
      if hard:
        return (dsFailed, @[], reason, @[])
      return (dsUnknown, @[], reason, @[])
    let k = indexOf.getOrDefault(id, -1)
    if k < 0:
      return (dsFailed, @[], "job record '" & r.name & "' attributes to '" & id &
              "', which is not a bucket", @[])
    inc acc[k].members
    if r.startedAt.len > 0 and
       (acc[k].startedAt.len == 0 or r.startedAt < acc[k].startedAt):
      acc[k].startedAt = r.startedAt
    if r.completedAt.len > 0 and r.completedAt > acc[k].completedAt:
      acc[k].completedAt = r.completedAt
    if r.createdAt.len > 0 and
       (acc[k].createdAt.len == 0 or r.createdAt < acc[k].createdAt):
      acc[k].createdAt = r.createdAt
    let done = r.conclusion == "success"
    if not done:
      acc[k].allSuccess = false
    if r.conclusion == "skipped" or r.conclusion == "cancelled":
      inc acc[k].skippedMembers

  for i in 0 ..< acc.len:
    if acc[i].members == 0:
      return (dsUnknown, @[], "job id '" & acc[i].jobId &
              "' is declared in the workflow but has no job record in attempt " &
              $runAttempt, @[])
    let span = secsBetween(acc[i].completedAt, acc[i].startedAt)
    if span < 0:
      anomalies.add "negative node span '" & acc[i].jobId &
        "' (completed_at < started_at)"
      acc[i].seconds = 0
    else:
      acc[i].seconds = span
    if acc[i].createdAt.len > 0 and acc[i].completedAt.len > 0 and
       epochOf(acc[i].completedAt) < epochOf(acc[i].createdAt):
      anomalies.add "node '" & acc[i].jobId &
        "' completed_at precedes its own created_at"
  result = (dsMeasured, acc, "", distinctSorted(anomalies))

func wallSecondsOf*(records: seq[JobRecord]): int {.raises: [].} =
  ## max(completed_at) - min(started_at) over the run's job records, skipped
  ## included — `docs/spec/ci_critical_path_metric.md` §2.1.
  var lo = ""
  var hi = ""
  for r in records:
    if r.startedAt.len == 0 or r.completedAt.len == 0:
      continue
    if lo.len == 0 or r.startedAt < lo:
      lo = r.startedAt
    if hi.len == 0 or r.completedAt > hi:
      hi = r.completedAt
  if lo.len == 0 or hi.len == 0:
    return -1
  secsBetween(hi, lo)

func gapKind(later, earlier: string): tuple[seconds: int, kind: string]
    {.raises: [].} =
  ## "ok" | "negative" (an impossible ordering that is CLAMPED and recorded) |
  ## "missing" (no usable instant — the weight is unknown, never 0).
  if later.len == 0 or earlier.len == 0:
    return (0, "missing")
  let a = epochOf(later)
  let b = epochOf(earlier)
  if a < 0 or b < 0:
    return (0, "missing")
  if a < b:
    return (0, "negative")
  (int(a - b), "ok")

func criticalPath*(graph: WorkflowGraph; buckets: seq[Bucket]; wallSeconds: int):
    tuple[status: DagStatus, seconds: int, path: seq[string],
          anomalies: seq[string], reason: string, lowerBound: bool] {.raises: [].} =
  ## Longest path through `needs:`. Node weight = bucket duration; edge weight =
  ## consumer bucket `created_at` - producer bucket max `completed_at`.
  result = (dsUnknown, 0, @[], @[], "", false)
  let order = graph.jobs
  if order.len == 0:
    return (dsFailed, 0, @[], @[], "the workflow declares no jobs", false)

  var indexOf = initTable[string, int]()
  for i, id in order:
    indexOf[id] = i
  var bOf = newSeq[Bucket](order.len)
  var haveBucket = newSeq[bool](order.len)
  for b in buckets:
    let k = indexOf.getOrDefault(b.jobId, -1)
    if k >= 0:
      bOf[k] = b
      haveBucket[k] = true

  for i in 0 ..< order.len:
    if not haveBucket[i]:
      return (dsUnknown, 0, @[], @[], "job id '" & order[i] &
              "' has no bucket; the path is unmeasurable", false)
    # A timestamp that is absent must never be substituted as 0. The path is not
    # known in advance, so any node that could carry the path fails it closed.
    if epochOf(bOf[i].startedAt) < 0 or epochOf(bOf[i].completedAt) < 0:
      return (dsUnknown, 0, @[], @[], "job id '" & order[i] &
              "' has no usable started_at/completed_at; the path is unmeasurable", false)

  var succ: seq[seq[int]] = newSeq[seq[int]](order.len)
  var indeg = newSeq[int](order.len)
  for e in graph.needs:
    let p = indexOf.getOrDefault(e.need, -1)
    let c = indexOf.getOrDefault(e.jobId, -1)
    if p < 0 or c < 0:
      return (dsFailed, 0, @[], @[], "needs edge " & e.need & " -> " & e.jobId &
              " names a job the workflow does not declare", false)
    succ[p].add c
    inc indeg[c]
  for s in succ.mitems:
    s.sort()

  var ready: seq[int] = @[]
  for i in 0 ..< order.len:
    if indeg[i] == 0:
      ready.add i
  var topo: seq[int] = @[]
  var qi = 0
  while qi < ready.len:
    let v = ready[qi]
    inc qi
    topo.add v
    for s in succ[v]:
      dec indeg[s]
      if indeg[s] == 0:
        ready.add s
  if topo.len != order.len:
    var cyc: seq[string] = @[]
    for i in 0 ..< order.len:
      if indeg[i] > 0:
        cyc.add order[i]
    return (dsFailed, 0, @[], @[], "the needs graph has a cycle among: " &
            cyc.join(", "), false)

  var dist = newSeq[int](order.len)
  var has = newSeq[bool](order.len)
  var prev = newSeq[int](order.len)
  for i in 0 ..< order.len:
    prev[i] = -1
  var anomalies: seq[string] = @[]
  var lowerBound = false
  for v in topo:
    if not has[v]:
      dist[v] = bOf[v].seconds
      has[v] = true
    for s in succ[v]:
      let g = gapKind(bOf[s].createdAt, bOf[v].completedAt)
      var ew = 0
      case g.kind
      of "ok":
        ew = g.seconds
      of "negative":
        anomalies.add "negative edge '" & order[v] & "' -> '" & order[s] &
          "' (consumer created_at precedes producer completed_at)"
      of "missing":
        lowerBound = true
        anomalies.add QueueLogSourceMissing & " edge '" & order[v] & "' -> '" &
          order[s] & "': created_at absent, weight unknown"
      else:
        discard
      let cand = dist[v] + ew + bOf[s].seconds
      if not has[s] or cand > dist[s] or
         (cand == dist[s] and (prev[s] < 0 or v < prev[s])):
        dist[s] = cand
        has[s] = true
        prev[s] = v

  var best = -1
  for i in 0 ..< order.len:
    if not has[i]:
      continue
    if best < 0 or dist[i] > dist[best] or (dist[i] == dist[best] and i < best):
      best = i
  if best < 0:
    return (dsUnknown, 0, @[], distinctSorted(anomalies),
            "no bucket could be weighted", false)

  var path: seq[string] = @[]
  var cur = best
  while cur >= 0:
    path.add order[cur]
    cur = prev[cur]
  var rev: seq[string] = @[]
  for i in countdown(path.high, 0):
    rev.add path[i]

  if wallSeconds >= 0 and dist[best] > wallSeconds:
    return (dsFailed, dist[best], rev, distinctSorted(anomalies),
            "criticalPathSeconds (" & $dist[best] & ") exceeds wallSeconds (" &
            $wallSeconds & ") for the same run", lowerBound)
  result = (dsMeasured, dist[best], rev, distinctSorted(anomalies), "", lowerBound)
func batchIndexOf*(graph: WorkflowGraph): seq[tuple[jobId: string, batch: int]]
    {.raises: [].} =
  ## Longest-path depth of each job id; batch 0 is the set with no `needs`.
  var indexOf = initTable[string, int]()
  for i, id in graph.jobs:
    indexOf[id] = i
  var depth = newSeq[int](graph.jobs.len)
  var changed = true
  var rounds = 0
  while changed and rounds <= graph.jobs.len:
    changed = false
    inc rounds
    for e in graph.needs:
      let c = indexOf.getOrDefault(e.jobId, -1)
      let p = indexOf.getOrDefault(e.need, -1)
      if c < 0 or p < 0:
        continue
      if depth[c] < depth[p] + 1:
        depth[c] = depth[p] + 1
        changed = true
  for i, id in graph.jobs:
    result.add (jobId: id, batch: depth[i])

func queueReport*(graph: WorkflowGraph; buckets: seq[Bucket]): QueueReport
    {.raises: [].} =
  ## `queuedSeconds` is NOT a single sum: first-batch queueing (runner
  ## assignment) and dependency handoff (a `needs:` edge) are reported as two
  ## separate aggregates over per-batch samples. A bucket without `created_at`
  ## contributes nothing and flips the status to NO_LOG_SOURCE.
  result = QueueReport(status: "MEASURED")
  var batch = initTable[string, int]()
  for e in batchIndexOf(graph):
    batch[e.jobId] = e.batch
  var anomalies: seq[string] = @[]
  for b in buckets:
    let bt = batch.getOrDefault(b.jobId, 0)
    if b.createdAt.len == 0 or epochOf(b.createdAt) < 0 or
       epochOf(b.startedAt) < 0:
      result.status = QueueLogSourceMissing
      anomalies.add QueueLogSourceMissing & " '" & b.jobId &
        "': created_at absent, queue wait unknown"
      continue
    if bt == 0:
      let s = secsBetween(b.startedAt, b.createdAt)
      if s < 0:
        anomalies.add "negative first-batch queue wait '" & b.jobId & "'"
        result.firstBatch.add QueueSample(jobId: b.jobId, batch: bt, seconds: 0)
      else:
        result.firstBatch.add QueueSample(jobId: b.jobId, batch: bt, seconds: s)
  for e in graph.needs:
    var pb: Bucket
    var cb: Bucket
    var haveP = false
    var haveC = false
    for b in buckets:
      if b.jobId == e.need:
        pb = b
        haveP = true
      if b.jobId == e.jobId:
        cb = b
        haveC = true
    if not haveP or not haveC:
      continue
    let bt = batch.getOrDefault(e.jobId, 0)
    if cb.createdAt.len == 0 or epochOf(cb.createdAt) < 0 or
       epochOf(pb.completedAt) < 0:
      result.status = QueueLogSourceMissing
      anomalies.add QueueLogSourceMissing & " handoff '" & e.need & "' -> '" &
        e.jobId & "': created_at absent, handoff unknown"
      continue
    let s = secsBetween(cb.createdAt, pb.completedAt)
    if s < 0:
      anomalies.add "negative handoff '" & e.need & "' -> '" & e.jobId & "'"
      result.handoff.add QueueSample(jobId: e.jobId, batch: bt, seconds: 0)
    else:
      result.handoff.add QueueSample(jobId: e.jobId, batch: bt, seconds: s)
  result.anomalies = distinctSorted(anomalies)

func measureWorkflowDag*(graph: WorkflowGraph; records: seq[JobRecord];
                         workflowPath, runId: string; runAttempt: int;
                         runHeadSha: string): DagResult {.raises: [].} =
  result = DagResult(status: dsUnknown, workflowPath: workflowPath,
                     blobSha: graph.blobSha, yamlRef: graph.yamlRef, runId: runId,
                     runAttempt: runAttempt, headSha: runHeadSha,
                     recordCount: records.len, declaredJobs: graph.jobs)
  let wall = wallSecondsOf(records)
  result.wallSeconds = wall
  let b = bucketRecords(graph, records, runId, runAttempt, runHeadSha)
  if b.status != dsMeasured:
    result.status = b.status
    result.reason = b.reason
    return
  result.buckets = b.buckets
  let cp = criticalPath(graph, b.buckets, wall)
  result.anomalies = distinctSorted(b.anomalies & cp.anomalies)
  result.criticalPathSeconds = cp.seconds
  result.criticalPath = cp.path
  result.lowerBound = cp.lowerBound
  if cp.status != dsMeasured:
    result.status = cp.status
    result.reason = cp.reason
    return
  result.status = dsMeasured
  result.shareOfWall = if wall > 0: float(cp.seconds) / float(wall) else: 0.0
  result.queue = queueReport(graph, result.buckets)

func samplesSeconds*(samples: seq[QueueSample]): seq[int] {.raises: [].} =
  for s in samples:
    result.add s.seconds

# ── workflow YAML: `jobs:` + `needs:` only ────────────────────────────────

const JobIdChars = {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '_', '-'}

func isJobToken(s: string): bool {.raises: [].} =
  if s.len == 0:
    return false
  for ch in s:
    if ch notin JobIdChars:
      return false
  true

func stripYamlComment(line: string): string {.raises: [].} =
  var inQuote = false
  for i, ch in line:
    if ch == '"':
      inQuote = not inQuote
    elif ch == '#' and not inQuote and (i == 0 or line[i - 1] == ' '):
      return line[0 ..< i]
  line

func isNeedsKey(text: string): bool {.raises: [].} =
  if not text.startsWith("needs:"):
    return false
  text.len == 6 or text[6] in {' ', '\t'}

func isNameKey(text: string): bool {.raises: [].} =
  if not text.startsWith("name:"):
    return false
  text.len == 5 or text[5] in {' ', '\t'}

func parseNeedsFlow(v: string): tuple[items: seq[string], err: string]
    {.raises: [].} =
  if v.len == 0:
    return (@[], "empty value")
  if v[0] == '[':
    if v[^1] != ']':
      return (@[], "'[' without a closing ']'")
    for part in v[1 .. ^2].split(','):
      let t = part.strip()
      if not isJobToken(t):
        return (@[], "'" & t & "' is not a job id")
      result.items.add t
    if result.items.len == 0:
      return (@[], "empty flow list")
    return
  if not isJobToken(v):
    return (@[], "'" & v & "' is neither a flow list nor a job id")
  (@[v], "")

func graphValidation*(graph: WorkflowGraph): string {.raises: [].} =
  ## "" when every `needs:` target is a declared job id and the graph is acyclic.
  var ids = distinctSorted(graph.jobs)
  for e in graph.needs:
    if e.jobId notin ids:
      return "needs edge declared on undeclared job '" & e.jobId & "'"
    if e.need notin ids:
      return "needs edge names undeclared job '" & e.need & "'"
    if e.jobId == e.need:
      return "job '" & e.jobId & "' needs itself"
  var indexOf = initTable[string, int]()
  for i, id in ids:
    indexOf[id] = i
  var indeg = newSeq[int](ids.len)
  var succ: seq[seq[int]] = newSeq[seq[int]](ids.len)
  for e in graph.needs:
    let pe = indexOf.getOrDefault(e.need, -1)
    let ce = indexOf.getOrDefault(e.jobId, -1)
    if pe < 0 or ce < 0:
      return "needs edge names an undeclared job"
    succ[pe].add ce
    inc indeg[ce]
  var ready: seq[int] = @[]
  for i in 0 ..< ids.len:
    if indeg[i] == 0:
      ready.add i
  var qi = 0
  var seen = 0
  while qi < ready.len:
    let v = ready[qi]
    inc qi
    inc seen
    for s in succ[v]:
      dec indeg[s]
      if indeg[s] == 0:
        ready.add s
  if seen != ids.len:
    return "the needs graph has a cycle"
  ""

func parseWorkflowJobs*(yaml: string):
    tuple[ok: bool, graph: WorkflowGraph, err: string] {.raises: [].} =
  ## Reads ONLY `jobs:` and each job's `needs:`/`name:`. Job ids live at indent
  ## 2 and job-level keys at indent 4, so `run: |` block content (always deeper
  ## than its own key) can never be mistaken for a job-level key. Anything that
  ## does not match the expected shape is an error, never a skipped line.
  result = (false, WorkflowGraph(), "")
  var lines: seq[tuple[indent: int, text: string, num: int]] = @[]
  var num = 0
  for raw in yaml.splitLines():
    inc num
    var t = stripYamlComment(raw)
    while t.len > 0 and t[^1] in {' ', '\t', '\r'}:
      t.setLen(t.len - 1)
    if t.len == 0:
      continue
    var ind = 0
    while ind < t.len and t[ind] == ' ':
      inc ind
    lines.add (indent: ind, text: t[ind .. ^1], num: num)

  var jobsStart = -1
  for i in 0 ..< lines.len:
    if lines[i].indent == 0 and lines[i].text == "jobs:":
      jobsStart = i
      break
  if jobsStart < 0:
    return (false, WorkflowGraph(), "no top-level 'jobs:' key")

  var g = WorkflowGraph()
  var curJob = ""
  var i = jobsStart + 1
  while i < lines.len:
    let l = lines[i]
    if l.indent == 0:
      break
    if l.indent == 2:
      if not l.text.endsWith(":"):
        return (false, WorkflowGraph(), "line " & $l.num &
                ": a jobs.<id> entry must be '  <id>:' with no inline value")
      let id = l.text[0 ..< l.text.len - 1].strip()
      if not isJobToken(id):
        return (false, WorkflowGraph(), "line " & $l.num & ": '" & id &
                "' is not a job id")
      if id in g.jobs:
        return (false, WorkflowGraph(), "line " & $l.num & ": duplicate job id '" &
                id & "'")
      g.jobs.add id
      curJob = id
      inc i
      continue
    if l.indent == 4:
      if curJob.len == 0:
        return (false, WorkflowGraph(), "line " & $l.num &
                ": job-level key outside any job")
      if isNeedsKey(l.text):
        let v = l.text["needs:".len .. ^1].strip()
        if v.len == 0:
          var j = i + 1
          var found = 0
          while j < lines.len and lines[j].indent > 4:
            if not lines[j].text.startsWith("- "):
              return (false, WorkflowGraph(), "line " & $lines[j].num &
                      ": expected a '- <job id>' needs item")
            let nid = lines[j].text[2 .. ^1].strip()
            if not isJobToken(nid):
              return (false, WorkflowGraph(), "line " & $lines[j].num & ": '" &
                      nid & "' is not a job id")
            g.needs.add (jobId: curJob, need: nid)
            inc found
            inc j
          if found == 0:
            return (false, WorkflowGraph(), "line " & $l.num &
                    ": 'needs:' with no value")
          i = j
          continue
        let f = parseNeedsFlow(v)
        if f.err.len > 0:
          return (false, WorkflowGraph(), "line " & $l.num & ": " & f.err)
        for nid in f.items:
          g.needs.add (jobId: curJob, need: nid)
        inc i
        continue
      if isNameKey(l.text):
        var v = l.text["name:".len .. ^1].strip()
        if v.len >= 2 and v[0] == '"' and v[^1] == '"':
          v = v[1 .. ^2]
        g.jobNames.add JobNameDecl(jobId: curJob, name: v)
        inc i
        continue
      inc i
      continue
    inc i

  if g.jobs.len == 0:
    return (false, WorkflowGraph(), "'jobs:' declares no job")
  g.jobs.sort()
  var normalised: seq[tuple[jobId, need: string]] = @[]
  for e in g.needs:
    normalised.add e
  normalised.sort(proc (a, b: tuple[jobId, need: string]): int =
    result = cmp(a.jobId, b.jobId)
    if result == 0:
      result = cmp(a.need, b.need))
  g.needs = normalised
  g.jobNames.sort(proc (a, b: JobNameDecl): int = cmp(a.jobId, b.jobId))
  let issue = graphValidation(g)
  if issue.len > 0:
    return (false, WorkflowGraph(), issue)
  result = (true, g, "")

# ═══════════════════════════════════════════════════════════════════════════
# §5. I/O boundary — GET only
# ═══════════════════════════════════════════════════════════════════════════

proc firstLine(s: string): string {.raises: [].} =
  let i = s.find('\n')
  if i < 0: s.strip() else: s[0 ..< i].strip()

proc ghGetJson(path: string): tuple[ok: bool, node: JsonNode, err: string]
    {.axiomEffect: IoEffect.} =
  ## GET only: `gh api` without a method flag cannot mutate.
  let (output, code) = execCmdEx("gh api " & quoteShell(path))
  if code != 0:
    return (false, nil, "gh api " & path & " exited " & $code &
                        (if output.strip().len > 0: ": " & firstLine(output) else: ""))
  try:
    (true, parseJson(output), "")
  except CatchableError as e:
    (false, nil, "unparsable JSON from " & path & ": " & e.msg)

proc readFileJson(path: string): tuple[ok: bool, node: JsonNode, err: string]
    {.axiomEffect: IoEffect.} =
  if not fileExists(path):
    return (false, nil, "missing file: " & path)
  try:
    (true, parseJson(readFile(path)), "")
  except CatchableError as e:
    (false, nil, "unparsable JSON in " & path & ": " & e.msg)

type
  QueueCycle* = object
    ## One `added_to_merge_queue` ... `removed_from_merge_queue`/`merged` window.
    ## A PR can enter the queue several times; each cycle has its own head SHA
    ## (the merge-group commit), so the cycle — not the PR — is the candidate.
    enteredAt*: string
    mergedAt*: string
    mergeCommit*: string

proc fetchTimeline(repo: string; pr: int):
    tuple[ok: bool, value: seq[QueueCycle], err: string] {.axiomEffect: IoEffect.} =
  ## `added_to_merge_queue` and `merged` are issue-timeline events. A PR may be
  ## re-queued after being removed, and each queue cycle is a SEPARATE candidate
  ## with its own merge-group SHA. Merging is bound by `commit_id`, never by
  ## "the last merged event": the same PR number can carry several SHAs in one
  ## cohort (measured: 402 and 400 each appear twice post-boundary).
  let (ok, node, err) = ghGetJson("repos/" & repo & "/issues/" & $pr &
                                  "/timeline?per_page=100")
  if not ok:
    return (false, @[], err)
  if node.kind != JArray:
    return (false, @[], "timeline payload is not an array")
  var cycles: seq[QueueCycle] = @[]
  for e in items(node):
    if e.kind != JObject:
      continue
    let kind = jsonStr(e, "event")
    let at = jsonStr(e, "created_at")
    if at.len == 0:
      continue
    case kind
    of "added_to_merge_queue":
      cycles.add QueueCycle(enteredAt: at)
    of "merged":
      let commit = jsonStr(e, "commit_id")
      # Attach the merge to the open cycle it closes. If no cycle is open the
      # event is still recorded so the caller can bind by commit id.
      var closed = false
      if cycles.len > 0 and cycles[^1].mergedAt.len == 0:
        cycles[^1].mergedAt = at
        cycles[^1].mergeCommit = commit
        closed = true
      if not closed:
        cycles.add QueueCycle(mergedAt: at, mergeCommit: commit)
    else:
      discard
  (true, cycles, "")

func selectCycle*(cycles: seq[QueueCycle]; headSha: string):
    tuple[found: bool, cycle: QueueCycle, reason: string] {.raises: [].} =
  ## Binds a candidate to its queue cycle. A merge is identified by
  ## `commit_id == head_sha` (measured: the merge-group commit IS the merge
  ## commit). When two cycles claim the same commit, or a cycle merges a
  ## different commit, the answer is UNKNOWN rather than a best guess.
  if cycles.len == 0:
    return (false, QueueCycle(), "no merge-queue timeline events")
  var matches: seq[QueueCycle] = @[]
  for c in cycles:
    if c.mergedAt.len > 0 and c.mergeCommit == headSha:
      matches.add c
  if matches.len > 1:
    return (false, QueueCycle(), "ambiguous: " & $matches.len &
            " queue cycles merged commit " & headSha)
  if matches.len == 1:
    return (true, matches[0], "")
  # No cycle merged this commit. Report the most recent cycle so the caller can
  # still say whether the candidate is merely still queued.
  var last = cycles[^1]
  for c in cycles:
    if c.enteredAt > last.enteredAt:
      last = c
  if last.mergedAt.len > 0:
    return (false, last, "the PR merged commit " & last.mergeCommit &
            ", not this candidate's head_sha")
  (false, last, "not merged yet (last queue cycle opened at " & last.enteredAt & ")")

type
  AttemptRun* = object
    runId*: string
    runAttempt*: int
    workflowPath*: string
    queueRef*: string
    createdAt*: string

proc fetchMergeGroupRuns(repo: string; headSha: string):
    tuple[ok: bool, runs: seq[AttemptRun], err: string] {.axiomEffect: IoEffect.} =
  ## Candidate runs are identified by `head_sha` (the stable identifier), the
  ## `merge_group` event, and the documented `gh-readonly-queue/` ref prefix.
  ## The `pr-<n>-<base_sha>` suffix is NOT documented and is never required.
  var runs: seq[AttemptRun] = @[]
  for page in 1 .. MaxPages:
    let (ok, node, err) = ghGetJson("repos/" & repo &
      "/actions/runs?event=merge_group&per_page=100&page=" & $page)
    if not ok:
      return (false, @[], err)
    if node.kind != JObject or not node.hasKey("workflow_runs"):
      return (false, @[], "workflow_runs payload missing")
    let chunk = at(node, "workflow_runs")
    if chunk.isNil or chunk.kind != JArray:
      return (false, @[], "workflow_runs is not an array")
    for r in items(chunk):
      if jsonStr(r, "head_sha") != headSha:
        continue
      let branch = jsonStr(r, "head_branch")
      if not branch.startsWith("gh-readonly-queue/"):
        continue
      runs.add AttemptRun(
        runId: jsonId(r, "id"),
        runAttempt: jsonInt(r, "run_attempt"),
        workflowPath: jsonStr(r, "path"),
        queueRef: branch,
        createdAt: jsonStr(r, "created_at"))
    if chunk.len < 100:
      break
  (true, runs, "")

proc selectAttemptRun*(runs: seq[AttemptRun]; workflowPath: string):
    tuple[found: bool, run: AttemptRun, reason: string] {.raises: [].} =
  ## The newest attempt of the context's own workflow. `head_sha` is identical
  ## across attempts, so `(created_at, run_attempt, run_id)` is the ordering —
  ## the same terminal-attempt rule the acceptance contract fixes.
  var cands: seq[AttemptRun] = @[]
  for r in runs:
    if workflowPath.len > 0 and r.workflowPath != workflowPath:
      continue
    cands.add r
  if cands.len == 0:
    return (false, AttemptRun(),
            "no merge_group run of " & (if workflowPath.len > 0: workflowPath else: "any workflow"))
  var best = cands[0]
  for r in cands:
    if r.createdAt > best.createdAt:
      best = r
    elif r.createdAt == best.createdAt:
      if r.runAttempt > best.runAttempt or
         (r.runAttempt == best.runAttempt and r.runId > best.runId):
        best = r
  (true, best, "")

proc fetchAttemptJobCheckRuns(repo: string; run: AttemptRun):
    tuple[ok: bool, ids: seq[string], err: string] {.axiomEffect: IoEffect.} =
  ## The ONLY documented per-attempt edge: the attempt number is in the path and
  ## each job carries `check_run_url`. `run.run_attempt` is never used as the
  ## producing attempt (it reports the run's current counter).
  if run.runAttempt <= 0:
    return (false, @[], "run " & run.runId & " reports no run_attempt")
  var ids: seq[string] = @[]
  for page in 1 .. MaxPages:
    let (ok, node, err) = ghGetJson("repos/" & repo & "/actions/runs/" & run.runId &
      "/attempts/" & $run.runAttempt & "/jobs?per_page=100&page=" & $page)
    if not ok:
      return (false, @[], err)
    if node.kind != JObject or not node.hasKey("jobs"):
      return (false, @[], "jobs payload missing for attempt " & $run.runAttempt)
    let jobs = at(node, "jobs")
    if jobs.isNil or jobs.kind != JArray:
      return (false, @[], "jobs is not an array")
    for id in attemptCheckRunIds(jobs):
      ids.add id
    if jobs.len < 100:
      break
  (true, distinctSorted(ids), "")

func jobRecordOf(j: JsonNode): JobRecord {.raises: [].} =
  ## `created_at` is read here and used ONLY by the DAG section, which reports
  ## its absence as NO_LOG_SOURCE: it is not part of the documented Jobs REST
  ## object even though the live API returns it.
  JobRecord(name: jsonStr(j, "name"), runId: jsonId(j, "run_id"),
            runAttempt: jsonInt(j, "run_attempt"),
            headSha: jsonStr(j, "head_sha"), status: jsonStr(j, "status"),
            conclusion: jsonStr(j, "conclusion"),
            startedAt: jsonStr(j, "started_at"),
            completedAt: jsonStr(j, "completed_at"),
            createdAt: jsonStr(j, "created_at"))

proc fetchAttemptJobRecords(repo: string; run: AttemptRun):
    tuple[ok: bool, records: seq[JobRecord], err: string]
    {.axiomEffect: IoEffect.} =
  ## The unprojected job records of one attempt. The DAG section consumes only
  ## JobRecord fields, so an added field cannot change the measurement.
  if run.runAttempt <= 0:
    return (false, @[], "run " & run.runId & " reports no run_attempt")
  var records: seq[JobRecord] = @[]
  for page in 1 .. MaxPages:
    let (ok, node, err) = ghGetJson("repos/" & repo & "/actions/runs/" & run.runId &
      "/attempts/" & $run.runAttempt & "/jobs?per_page=100&page=" & $page)
    if not ok:
      return (false, @[], err)
    let jobs = at(node, "jobs")
    if jobs.isNil or jobs.kind != JArray:
      return (false, @[], "jobs is not an array")
    for j in items(jobs):
      records.add jobRecordOf(j)
    if jobs.len < 100:
      break
  (true, records, "")

proc fetchBlobSha(repo, atSha, path: string):
    tuple[ok: bool, sha: string, err: string] {.axiomEffect: IoEffect.} =
  ## The git blob sha of the workflow YAML read at `atSha`. Recording it next to
  ## the run id / attempt / head sha makes the `needs:` graph that produced the
  ## numbers identifiable after the fact.
  let (ok, node, err) = ghGetJson("repos/" & repo & "/contents/" & path &
                                  "?ref=" & atSha)
  if not ok:
    return (false, "", err)
  let sha = jsonStr(node, "sha")
  if sha.len == 0:
    return (false, "", "no blob sha for " & path & " at " & atSha)
  (true, sha, "")

proc fetchWorkflowYaml(repo, atSha, path: string):
    tuple[ok: bool, text: string, err: string] {.axiomEffect: IoEffect.} =
  ## `application/vnd.github.raw` returns the file body, not the base64 JSON
  ## envelope, so the text is used verbatim. A response that is still a JSON
  ## envelope has not been decoded and is refused rather than parsed as YAML.
  ## Reading at `atSha` (the candidate sha) is mandatory: the graph must be the
  ## one the run executed, not the branch tip.
  let (output, code) = execCmdEx("gh api -H 'Accept: application/vnd.github.raw' " &
    quoteShell("repos/" & repo & "/contents/" & path & "?ref=" & atSha))
  if code != 0:
    return (false, "", "gh api contents exited " & $code)
  if output.startsWith("{") or output.startsWith("["):
    return (false, "", "the contents response is still a JSON envelope")
  (true, output, "")

proc fetchCheckRuns(repo: string; sha: string):
    tuple[ok: bool, node: JsonNode, err: string] {.axiomEffect: IoEffect.} =
  ## `filter=all` is mandatory: the API default (`latest`) is scoped per check
  ## suite and silently collapses re-runs. The payload is an ENVELOPE
  ## (`{total_count, check_runs}`), not a bare array, and `total_count` can exceed
  ## one page, so the array is accumulated rather than taken from page 1.
  var acc = newJArray()
  for page in 1 .. MaxPages:
    let (ok, node, err) = ghGetJson("repos/" & repo & "/commits/" & sha &
      "/check-runs?per_page=100&filter=all&page=" & $page)
    if not ok:
      return (false, nil, err)
    let chunk = at(node, "check_runs")
    if chunk.isNil or chunk.kind != JArray:
      return (false, nil, "check_runs envelope missing on page " & $page)
    for cr in items(chunk):
      acc.add cr
    if chunk.len < 100:
      break
  (true, acc, "")

proc liveRequiredContexts(repo: string; rulesetId: string):
    tuple[ok: bool, names: seq[string], err: string] {.axiomEffect: IoEffect.} =
  let (ok, node, err) = ghGetJson("repos/" & repo & "/rulesets/" & rulesetId)
  if not ok:
    return (false, @[], err)
  let rules = at(node, "rules")
  if rules.isNil or rules.kind != JArray:
    return (false, @[], "ruleset payload has no rules")
  var names: seq[string] = @[]
  for rule in items(rules):
    if jsonStr(rule, "type") != "required_status_checks":
      continue
    let params = at(rule, "parameters")
    let checks = at(params, "required_status_checks")
    if checks.isNil or checks.kind != JArray:
      continue
    for chk in items(checks):
      let name = jsonStr(chk, "context")
      if name.len > 0:
        names.add name
  if names.len == 0:
    return (false, @[], "ruleset declares no required status checks")
  (true, distinctSorted(names), "")

# ═══════════════════════════════════════════════════════════════════════════
# §6. Report
# ═══════════════════════════════════════════════════════════════════════════

func bucketJson(b: Bucket): JsonNode {.raises: [].} =
  %*{
    "job_id": b.jobId,
    "members": b.members,
    "skipped_members": b.skippedMembers,
    "started_at": b.startedAt,
    "completed_at": b.completedAt,
    "created_at": b.createdAt,
    "all_success": b.allSuccess,
    "seconds": b.seconds
  }

func samplesJson(samples: seq[QueueSample]): JsonNode {.raises: [].} =
  result = newJArray()
  for s in samples:
    result.add %*{"job_id": s.jobId, "batch": s.batch, "seconds": s.seconds}

func dagJson(d: DagResult): JsonNode {.raises: [].} =
  var buckets = newJArray()
  for b in d.buckets:
    buckets.add bucketJson(b)
  var anomalies = newJArray()
  for a in d.anomalies:
    anomalies.add %a
  result = %*{
    "schema_version": DagSchemaVersion,
    "status": $d.status,
    "reason": d.reason,
    "workflow_path": d.workflowPath,
    "workflow_yaml_blob_sha": d.blobSha,
    "workflow_yaml_ref": d.yamlRef,
    "workflow_run_id": d.runId,
    "run_attempt": d.runAttempt,
    "head_sha": d.headSha,
    "record_count": d.recordCount,
    "declared_jobs": %d.declaredJobs,
    "buckets": buckets,
    "critical_path_seconds": d.criticalPathSeconds,
    "critical_path": %d.criticalPath,
    "wall_seconds": d.wallSeconds,
    "critical_path_share": d.shareOfWall,
    "lower_bound": d.lowerBound,
    "anomalies": anomalies
  }
  if d.status == dsMeasured:
    result["queue"] = %*{
      "status": d.queue.status,
      "first_batch": samplesJson(d.queue.firstBatch),
      "handoff": samplesJson(d.queue.handoff),
      "anomalies": %d.queue.anomalies
    }

func checkJson(c: CheckState): JsonNode {.raises: [].} =
  %*{
    "context": c.context,
    "workflow_path": c.workflowPath,
    "is_app_verdict": c.isAppVerdict,
    "expected_app_id": c.expectedAppId,
    "observed_app_id": c.observedAppId,
    "check_run_id": c.checkRunId,
    "check_suite_id": c.suiteId,
    "workflow_run_id": c.runId,
    "run_attempt": c.runAttempt,
    "status": c.status,
    "conclusion": c.conclusion,
    "started_at": c.startedAt,
    "completed_at": c.completedAt,
    "bound": c.bound,
    "unbound_reason": c.unboundReason
  }

func phasesJson(phases: seq[PhaseSpan]): JsonNode {.raises: [].} =
  result = newJArray()
  for p in phases:
    result.add %*{"name": p.name, "start_at": p.startAt,
                  "end_at": p.endAt, "seconds": p.seconds}

func candidateJson(c: Candidate): JsonNode {.raises: [].} =
  var checks = newJArray()
  for ch in c.checks:
    checks.add checkJson(ch)
  var dags = newJArray()
  for d in c.dags:
    dags.add dagJson(d)
  %*{
    "pr_number": c.prNumber,
    "head_sha": c.headSha,
    "queue_ref": c.queueRef,
    "queue_entry_at": c.queueEntryAt,
    "merged_at": c.mergedAt,
    "merge_commit": c.mergeCommit,
    "outcome": $c.outcome,
    "unknown_reason": c.unknownReason,
    "phases": phasesJson(c.phases),
    "ready_seconds": readySeconds(c.phases),
    "admission_seconds": admissionSeconds(c.phases),
    "last_finisher": lastFinisher(c.checks),
    "workflow_dags": dags,
    "checks": checks
  }

func statsJson(s: Stats): JsonNode {.raises: [].} =
  %*{
    "n": s.n,
    "p50_seconds": s.p50,
    "p90_seconds": s.p90,
    "mean_seconds": s.mean,
    "min_seconds": s.minSeconds,
    "max_seconds": s.maxSeconds
  }

func fmtSec(x: int): string {.raises: [].} =
  if x < 0: "n/a" else: $x & "s"

proc writeReport(outDir: string; repo: string; policyPath: string;
                 cohort: Cohort; expected: seq[ExpectedContext];
                 candidates: seq[Candidate]; rulesetNames: seq[string]
                 ): tuple[jsonPath, mdPath: string, observed, unknown: int]
                 {.axiomEffect: IoEffect.} =
  var observed: seq[Candidate] = @[]
  var unknown: seq[Candidate] = @[]
  for c in candidates:
    if c.outcome == ocObserved: observed.add c else: unknown.add c

  var tQueue, tVerify, tPub, tMerge, tReady, tAdmission: seq[int] = @[]
  for c in observed:
    let q = phaseSeconds(c.phases, "queue")
    let v = phaseSeconds(c.phases, "verify")
    let p = phaseSeconds(c.phases, "publication")
    let m = phaseSeconds(c.phases, "merge")
    if q >= 0: tQueue.add q
    if v >= 0: tVerify.add v
    if p >= 0: tPub.add p
    if m >= 0: tMerge.add m
    let r = readySeconds(c.phases)
    if r >= 0: tReady.add r
    let a = admissionSeconds(c.phases)
    if a >= 0: tAdmission.add a

  var finisherCounts = initOrderedTable[string, int]()
  for c in observed:
    let f = lastFinisher(c.checks)
    if f.len > 0:
      if not finisherCounts.hasKey(f):
        finisherCounts[f] = 0
      inc finisherCounts[f]

  var candJson = newJArray()
  for c in candidates:
    candJson.add candidateJson(c)

  let report = %*{
    "schema_version": SchemaVersion,
    "tool": ToolName,
    "repo": repo,
    "policy_path": policyPath,
    "estimators": {"p50": P50Estimator, "p90": P90Estimator},
    "cohort": {
      "source": cohort.source,
      "n": cohort.headShas.len,
      "head_shas": cohort.headShas,
      "pr_numbers": cohort.prNumbers
    },
    "binding": {
      "run_selection": "merge_group event, head_sha == candidate, head_branch startsWith gh-readonly-queue/",
      "attempt_edge": "GET /actions/runs/{id}/attempts/{n}/jobs -> job.check_run_url",
      "general_context": "check_run.id in the attempt job set of the context's declared workflow",
      "app_verdict": "check_run.app.id == expected producer AND started_at >= attempt created_at AND unique in the window",
      "check_runs_filter": "all (latest is per-suite scoped and collapses re-runs)",
      "ambiguity_policy": "UNKNOWN (never a guessed check-run)",
      "workflow_dag": "attribution by prefix (own(N,I) = N==I or N startsWith I&' / ' or I&' ('); bucket completed_at = max; suffix inversion is never used; skipped records are retained; the YAML is read at the candidate sha and its blob sha recorded",
      "critical_path_share_scope": "per workflow only — never a fraction of T_admission"
    },
    "authority": {
      "live_ruleset_required_contexts": rulesetNames,
      "policy_required_contexts": expectedContextNames(expected),
      "context_sets_equal": sameContextSet(rulesetNames, expectedContextNames(expected))
    },
    "observed_n": observed.len,
    "unknown_n": unknown.len,
    "phase_stats": {
      "queue": statsJson(statsOf(tQueue)),
      "verify": statsJson(statsOf(tVerify)),
      "publication": statsJson(statsOf(tPub)),
      "merge": statsJson(statsOf(tMerge)),
      "ready": statsJson(statsOf(tReady)),
      "admission": statsJson(statsOf(tAdmission))
    },
    "last_finisher_counts": finisherCounts,
    "candidates": candJson
  }

  createDir(outDir)
  let jsonPath = outDir / (ToolName & "_report.json")
  writeFile(jsonPath, pretty(report, indent = 2))

  var md = "# CI admission wall — cross-workflow observation\n\n"
  md.add "- tool: `" & ToolName & "` (" & SchemaVersion & ")\n"
  md.add "- repo: `" & repo & "`\n"
  md.add "- cohort source: `" & cohort.source & "` (" & $cohort.headShas.len & " entries)\n"
  md.add "- observed: **" & $observed.len & "**, unknown: **" & $unknown.len & "**\n"
  md.add "- p50 estimator: " & P50Estimator & "\n"
  md.add "- p90 estimator: " & P90Estimator & "\n\n"

  md.add "## Authority check (policy vs live ruleset)\n\n"
  md.add "- policy contexts: " & expectedContextNames(expected).join(", ") & "\n"
  md.add "- live ruleset contexts: " & rulesetNames.join(", ") & "\n"
  md.add "- equal: **" & $sameContextSet(rulesetNames, expectedContextNames(expected)) & "**\n\n"

  md.add "## Phase statistics (whole seconds, observed candidates only)\n\n"
  md.add "| phase | n | p50 | p90 | mean | min | max |\n"
  md.add "|---|---:|---:|---:|---:|---:|---:|\n"
  template row(label: string; v: seq[int]) =
    let s = statsOf(v)
    md.add "| " & label & " | " & $s.n & " | " & formatOneDecimal(s.p50) &
           " | " & formatOneDecimal(s.p90) & " | " & formatOneDecimal(s.mean) &
           " | " & fmtSec(s.minSeconds) & " | " & fmtSec(s.maxSeconds) & " |\n"
  row("T_queue", tQueue)
  row("T_verify", tVerify)
  row("T_publication", tPub)
  row("T_ready", tReady)
  row("T_merge", tMerge)
  row("T_admission", tAdmission)

  md.add "\n`T_ready = T_queue + T_verify + T_publication`; " &
         "`T_admission = T_ready + T_merge`. `T_exec` is not reported: it equals " &
         "`T_verify + T_publication`, and summing it again would double-count.\n\n"

  md.add "## Last-finishing required context\n\n"
  md.add "| context | candidates |\n|---|---:|\n"
  for k, v in finisherCounts:
    md.add "| `" & k & "` | " & $v & " |\n"
  md.add "\nThe last finisher is an OBSERVATION. It is not by itself proof that the " &
         "context's execution is the bottleneck — that requires the workflow's `needs` " &
         "edges and per-step attribution.\n\n"

  md.add "## Per-workflow critical path (diagnostic)\n\n"
  md.add "`critical_path_share` is `criticalPathSeconds / wallSeconds` for THAT " &
         "workflow only. It is never a fraction of `T_admission`: the fractions of " &
         "different workflows are not commensurable and do not sum to 1.\n\n"
  md.add "| pr | workflow | status | run | yaml blob sha | criticalPath | wall | share | reason |\n"
  md.add "|---:|---|---|---|---|---:|---:|---:|---|\n"
  for c in candidates:
    for d in c.dags:
      md.add "| " & $c.prNumber & " | `" & d.workflowPath & "` | " & $d.status & " | `" &
             d.runId & "#" & $d.runAttempt & "` | `" &
             (if d.blobSha.len > 8: d.blobSha[0 .. 7] else: d.blobSha) & "` | " &
             fmtSec(d.criticalPathSeconds) & " | " & fmtSec(d.wallSeconds) & " | " &
             formatOneDecimal(d.shareOfWall) & " | " & d.reason & " |\n"
  md.add "\n"
  for k, v in finisherCounts:
    md.add "| `" & k & "` | " & $v & " |\n"
  md.add "\nThe last finisher is an OBSERVATION. It is not by itself proof that the " &
         "context's execution is the bottleneck — that requires the workflow's `needs` " &
         "edges and per-step attribution.\n\n"

  md.add "## Unknown candidates (fail-closed)\n\n"
  if unknown.len == 0:
    md.add "none\n"
  else:
    md.add "| pr | head_sha | reason |\n|---:|---|---|\n"
    for c in unknown:
      md.add "| " & $c.prNumber & " | `" & c.headSha[0 .. min(11, c.headSha.high)] &
             "` | " & c.unknownReason & " |\n"

  let mdPath = outDir / (ToolName & "_report.md")
  writeFile(mdPath, md)
  (jsonPath, mdPath, observed.len, unknown.len)

# ═══════════════════════════════════════════════════════════════════════════
# §7. CLI
# ═══════════════════════════════════════════════════════════════════════════

proc usage*(): string {.raises: [].} =
  "usage:\n" &
  "  " & ToolName & " --cohort-from <collector report.json> --ruleset <id>\n" &
  "      [--repo owner/name] [--policy " & PolicyPath & "] [--out DIR]\n" &
  "  " & ToolName & " --pr <n>[,<n>...] --ruleset <id>\n" &
  "      [--repo owner/name] [--policy " & PolicyPath & "] [--out DIR]\n" &
  "  " & ToolName & " --help\n\n" &
  "--cohort-from consumes the entries tools/ci/ci_acceptance_collect already\n" &
  "selected (head_sha + pr_number), so both tools describe the SAME cohort.\n" &
  "--ruleset <id> is REQUIRED: the live ruleset is the merge authority, and a\n" &
  "policy/ruleset context mismatch fails closed (exit 1).\n\n" &
  "Exit: 0 OBSERVED, 1 FAILED (authority or reconciliation), 2 INCOMPLETE.\n"

proc die(msg: string, code = 2) {.noreturn.} =
  stderr.writeLine(ToolName & ": " & msg)
  quit(code)

proc main() {.axiomEffect: IoEffect.} =
  var
    repo = DefaultRepo
    cohortPath = ""
    prArg = ""
    rulesetId = ""
    policyPath = PolicyPath
    outDir = DefaultOutDir
  let args = commandLineParams()
  var i = 0
  while i < args.len:
    template needValue(): string =
      if i + 1 >= args.len: die("missing value for " & args[i])
      i.inc
      args[i]
    case args[i]
    of "--repo": repo = needValue()
    of "--cohort-from": cohortPath = needValue()
    of "--pr": prArg = needValue()
    of "--ruleset": rulesetId = needValue()
    of "--policy": policyPath = needValue()
    of "--out": outDir = needValue()
    of "--help", "-h":
      echo usage()
      quit(0)
    else:
      die("unknown argument '" & args[i] & "'\n" & usage())
    i.inc

  if rulesetId.len == 0:
    die("missing required --ruleset <id>: the live ruleset is the merge authority")
  if cohortPath.len == 0 and prArg.len == 0:
    die("one of --cohort-from or --pr is required\n" & usage())

  let (pok, pnode, perr) = readFileJson(policyPath)
  if not pok:
    die("cannot read policy: " & perr)
  let (expected, eerr) = expectedContextsFromPolicy(pnode)
  if eerr.len > 0:
    die("policy has no usable required-context set: " & eerr)

  var cohort = Cohort(source: "explicit --pr")
  if cohortPath.len > 0:
    let (cok, cnode, cerr) = readFileJson(cohortPath)
    if not cok:
      die("cannot read cohort report: " & cerr)
    let entries = at(cnode, "entries")
    if entries.isNil or entries.kind != JArray:
      die("cohort report has no entries array")
    for e in items(entries):
      let h = jsonStr(e, "head_sha")
      if h.len == 0:
        continue
      cohort.headShas.add h
      cohort.prNumbers.add jsonInt(e, "pr_number")
    cohort.source = cohortPath
  else:
    for part in prArg.split(','):
      let t = part.strip()
      if t.len == 0:
        continue
      try:
        cohort.prNumbers.add parseInt(t)
      except ValueError:
        die("--pr expects comma-separated integers, got '" & t & "'")

  if cohort.headShas.len == 0 and cohort.prNumbers.len == 0:
    die("cohort is empty")

  # Authority: the policy's set must equal the live ruleset's set, or no
  # measurement is published at all.
  let (rok, rulesetNames, rerr) = liveRequiredContexts(repo, rulesetId)
  if not rok:
    die("cannot read live ruleset " & rulesetId & ": " & rerr)
  if not sameContextSet(rulesetNames, expectedContextNames(expected)):
    stderr.writeLine(ToolName & ": required-context mismatch")
    stderr.writeLine("  policy:  " & expectedContextNames(expected).join(", "))
    stderr.writeLine("  ruleset: " & rulesetNames.join(", "))
    stderr.writeLine("  refusing to publish a measurement over an unverified authority")
    quit(1)

  var candidates: seq[Candidate] = @[]
  let n = max(cohort.headShas.len, cohort.prNumbers.len)
  for idx in 0 ..< n:
    let pr = if idx < cohort.prNumbers.len: cohort.prNumbers[idx] else: 0
    let sha = if idx < cohort.headShas.len: cohort.headShas[idx] else: ""
    var cand = Candidate(prNumber: pr, headSha: sha, outcome: ocUnknown)

    if cand.headSha.len == 0:
      cand.unknownReason = "cohort entry carries no head_sha"
      candidates.add cand
      continue

    let (tok, cycles, terr) = fetchTimeline(repo, cand.prNumber)
    if not tok:
      cand.unknownReason = "timeline unavailable: " & terr
      candidates.add cand
      continue
    let (cok, cyc, creason) = selectCycle(cycles, cand.headSha)
    if not cok:
      cand.unknownReason = creason
      candidates.add cand
      continue
    cand.queueEntryAt = cyc.enteredAt
    cand.mergedAt = cyc.mergedAt
    cand.mergeCommit = cyc.mergeCommit

    let (rok2, runs, rerr2) = fetchMergeGroupRuns(repo, cand.headSha)
    if not rok2:
      cand.unknownReason = "workflow runs unavailable: " & rerr2
      candidates.add cand
      continue
    if runs.len == 0:
      cand.unknownReason = "no merge_group run with this head_sha under a gh-readonly-queue ref"
      candidates.add cand
      continue

    # Diagnostic only: the queue ref is documented by prefix, not by the
    # pr-<n>-<base_sha> suffix. A suffix mismatch never invalidates a candidate.
    for r in runs:
      if cand.queueRef.len == 0:
        cand.queueRef = r.queueRef
      if ("pr-" & $cand.prNumber & "-") in r.queueRef:
        cand.queueRefSuffixMatched = true

    let (crok, checkRuns, crerr) = fetchCheckRuns(repo, cand.headSha)
    if not crok:
      cand.unknownReason = "check-runs unavailable: " & crerr
      candidates.add cand
      continue

    var checks: seq[CheckState] = @[]
    for e in expected:
      if e.isAppVerdict:
        continue
      let (sok, sel, sreason) = selectAttemptRun(runs, e.workflowPath)
      if not sok:
        var cs = CheckState(context: e.job, workflowPath: e.workflowPath,
                            isAppVerdict: false, expectedAppId: e.appId, bound: false)
        cs.unboundReason = sreason
        checks.add cs
        continue
      let (jok, ids, jerr) = fetchAttemptJobCheckRuns(repo, sel)
      if not jok:
        var cs = CheckState(context: e.job, workflowPath: e.workflowPath,
                            isAppVerdict: false, expectedAppId: e.appId,
                            runId: sel.runId, runAttempt: sel.runAttempt, bound: false)
        cs.unboundReason = "attempt jobs unavailable: " & jerr
        checks.add cs
        continue
      checks.add bindGeneralContext(e, checkRuns, ids, sel.runId, sel.runAttempt)

    for e in expected:
      if not e.isAppVerdict:
        continue
      # Floor = the queue cycle, not the Actions run (see bindAppVerdict).
      checks.add bindAppVerdict(e, checkRuns, cand.queueEntryAt, cand.mergedAt)

    checks.sort(proc (a, b: CheckState): int = cmp(a.context, b.context))
    cand.checks = checks

    let (subst, substDetail) = authoritySubstitution(checks)
    if subst:
      cand.unknownReason = "authority_substitution — " & substDetail
      candidates.add cand
      continue

    let (bok, breason) = allBound(checks)
    if not bok:
      cand.unknownReason = "unbound required context — " & breason
      candidates.add cand
      continue

    let phases = buildPhases(cand.queueEntryAt, cand.mergedAt, checks)
    if phases.len == 0:
      cand.unknownReason = "phase partition unconstructible (an instant is unobservable or out of order)"
      candidates.add cand
      continue
    cand.phases = phases
    let (rcok, _, _, residue) = reconcile(phases, cand.queueEntryAt, cand.mergedAt)
    if not rcok:
      cand.unknownReason = "phase residue " & $residue & "s — the four phases do not cover the interval"
      candidates.add cand
      continue

    # Per-workflow DAG diagnostics are ADDITIVE: they never gate the candidate's
    # outcome, because a workflow whose YAML cannot be read at the candidate sha
    # says nothing about whether the admission phases were observed.
    for e in expected:
      if e.isAppVerdict or e.workflowPath.len == 0:
        continue
      let (sok, sel, sreason) = selectAttemptRun(runs, e.workflowPath)
      if not sok:
        cand.dags.add DagResult(status: dsUnknown, workflowPath: e.workflowPath,
                                reason: sreason)
        continue
      let (bok2, blobSha, berr) = fetchBlobSha(repo, cand.headSha, e.workflowPath)
      if not bok2:
        cand.dags.add DagResult(status: dsUnknown, workflowPath: e.workflowPath,
                                runId: sel.runId, runAttempt: sel.runAttempt,
                                headSha: cand.headSha,
                                reason: "workflow YAML unavailable at the candidate sha: " & berr)
        continue
      let (yok, yaml, yerr) = fetchWorkflowYaml(repo, cand.headSha, e.workflowPath)
      if not yok:
        cand.dags.add DagResult(status: dsUnknown, workflowPath: e.workflowPath,
                                blobSha: blobSha, yamlRef: cand.headSha,
                                runId: sel.runId, runAttempt: sel.runAttempt,
                                headSha: cand.headSha,
                                reason: "workflow YAML unreadable: " & yerr)
        continue
      let (pok, graph, perr) = parseWorkflowJobs(yaml)
      if not pok:
        cand.dags.add DagResult(status: dsFailed, workflowPath: e.workflowPath,
                                blobSha: blobSha, yamlRef: cand.headSha,
                                runId: sel.runId, runAttempt: sel.runAttempt,
                                headSha: cand.headSha,
                                reason: "workflow YAML parse failed: " & perr)
        continue
      var g = graph
      g.blobSha = blobSha
      g.yamlRef = cand.headSha
      let (jok2, records, jerr2) = fetchAttemptJobRecords(repo, sel)
      if not jok2:
        cand.dags.add DagResult(status: dsUnknown, workflowPath: e.workflowPath,
                                blobSha: blobSha, yamlRef: cand.headSha,
                                runId: sel.runId, runAttempt: sel.runAttempt,
                                headSha: cand.headSha,
                                reason: "attempt job records unavailable: " & jerr2)
        continue
      cand.dags.add measureWorkflowDag(g, records, e.workflowPath, sel.runId,
                                       sel.runAttempt, cand.headSha)

    cand.outcome = ocObserved
    candidates.add cand

  let (jsonPath, mdPath, observed, unknown) = writeReport(
    outDir, repo, policyPath, cohort, expected, candidates, rulesetNames)

  echo ToolName & ": cohort=" & $candidates.len & " observed=" & $observed &
       " unknown=" & $unknown
  echo ToolName & ": wrote " & jsonPath & " and " & mdPath
  if unknown > 0:
    quit(2)
  quit(0)

when isMainModule:
  main()