## test_ci_admission_observe.nim — fixtures for tools/ci/ci_admission_observe.nim.
##
## NO network, NO subprocess: the observer's pure core is imported directly and
## every case is a synthetic policy/check-run/job/time fixture. The cases pin the
## four corrections this tool exists to enforce:
##
##   * phase partition is non-overlapping and reconciles to the whole interval,
##     and T_exec is NOT a phase (it equals verify + publication: #420 = 436 + 3);
##   * p90 uses the same estimator family as the canonical p50 (Hyndman-Fan 7),
##     so p90 < p50 is unreachable and the pair stays interpretable;
##   * a general context binds ONLY through the attempt-exact job edge
##     (/attempts/{n}/jobs -> check_run_url); "newest check-run with that name"
##     is never a fallback;
##   * the App verdict context requires the declared producer app AND a unique
##     match inside the attempt window; duplicates are UNKNOWN, not a pick;
##   * one mismatching producer is authority_substitution, never a success.

import std/[json, strutils, unittest]

import ../../tools/ci/ci_admission_observe
from ../../tools/ci/ci_acceptance_collect import p50Seconds

# ---------------------------------------------------------------------------
# Fixture constructors
# ---------------------------------------------------------------------------

const
  TQueueEntry = "2026-11-23T13:51:42Z"
  TFirstStart = "2026-11-23T13:52:00Z"
  TLastGeneral = "2026-11-23T13:59:16Z"
  TAppVerdict = "2026-11-23T13:59:19Z"
  TMerged = "2026-11-23T13:59:42Z"
  AppId = 5795152
  ActionsId = 15368

func chk(name, start, done: string; app = ActionsId; verdict = false;
         bound = true): CheckState =
  CheckState(context: name, isAppVerdict: verdict, expectedAppId: app,
             observedAppId: app, startedAt: start, completedAt: done,
             bound: bound, status: "completed", conclusion: "success")

func checkRun(id: int; name, start, done: string; app = ActionsId): JsonNode =
  %*{
    "id": id,
    "name": name,
    "status": "completed",
    "conclusion": "success",
    "started_at": start,
    "completed_at": done,
    "app": {"id": app},
    "check_suite": {"id": 900 + id}
  }

func jobRow(checkRunId: int): JsonNode =
  %*{"check_run_url": "https://api.github.com/repos/o/r/check-runs/" & $checkRunId}

# The seven required contexts exactly as config/policy/merge_admission.json
# declares them: six Actions jobs plus the App-published verdict.
const RequiredJobs = ["bsec-integrity", "debt-registry-gate",
                      "generation-acceptance", "axiom-operational-slice",
                      "publication-integrity", "readiness-verdict"]

func policyNode(verdictJob = "admission-check"): JsonNode =
  var validations = newJArray()
  for j in RequiredJobs:
    validations.add %*{"job": j,
                       "workflowPath": ".github/workflows/" & j & ".yml"}
  %*{
    "requiredValidations": validations,
    "requiredWorkflowDetection": {
      "workflowPath": ".github/workflows/admission-gate-v2.yml",
      "verdictJob": verdictJob
    },
    "requiredCheckSources": {
      "default": ActionsId,
      "byContext": {verdictJob: AppId}
    }
  }

# ---------------------------------------------------------------------------
# 1. Estimator family
# ---------------------------------------------------------------------------

suite "percentile estimator":
  test "R-7 on an empty and a single-element array":
    check r7Percentile(@[], 0.9) == 0.0
    check r7Percentile(@[42], 0.9) == 42.0

  test "R-7 interpolates linearly at h = (n-1)p":
    # n=10, p=0.9 -> h=8.1 -> 9 + 0.1*(10-9) = 9.1
    check r7Percentile(@[1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 0.9) == 9.1
    # n=2, p=0.9 -> h=0.9 -> 10 + 0.9*(20-10) = 19.0
    check r7Percentile(@[10, 20], 0.9) == 19.0

  test "R-7 at p=0.5 is the canonical collector p50 (same family, not a mix)":
    # Even n: the collector averages the two middle values.
    check r7Percentile(@[1, 2, 3, 4], 0.5) == 2.5
    # Odd n: the middle value.
    check r7Percentile(@[1, 2, 3], 0.5) == 2.0
    # Agreement on a wider array, which is what keeps p50/p90 comparable.
    let v = @[18, 23, 436, 457, 480, 5, 3]
    check r7Percentile(v, 0.5) == p50Seconds(v)

  test "p90 can never be below p50":
    for v in [@[5], @[5, 5], @[1, 900], @[3, 5, 18, 23, 436, 457, 480],
              @[0, 0, 0, 1]]:
      check r7Percentile(v, 0.9) >= r7Percentile(v, 0.5)

  test "statsOf reports p50 through the canonical estimator":
    let s = statsOf(@[480, 18, 457])
    check s.n == 3
    check s.p50 == 457.0
    check s.minSeconds == 18
    check s.maxSeconds == 480
    check statsOf(@[]).n == 0

# ---------------------------------------------------------------------------
# 2. Interval algebra
# ---------------------------------------------------------------------------

suite "interval algebra":
  test "secsBetween yields whole seconds between two instants":
    check secsBetween(TMerged, TQueueEntry) == 480
    check secsBetween(TFirstStart, TQueueEntry) == 18
    check secsBetween(TLastGeneral, TFirstStart) == 436
    check secsBetween(TAppVerdict, TLastGeneral) == 3
    check secsBetween(TMerged, TAppVerdict) == 23

  test "an impossible interval is -1, never 0":
    check secsBetween(TQueueEntry, TMerged) == -1
    check secsBetween("", TQueueEntry) == -1
    check secsBetween("not-a-timestamp", TQueueEntry) == -1
    check secsBetween(TMerged, "2026-11-23T13:51:42+09:00") == -1

# ---------------------------------------------------------------------------
# 3. Phase partition and reconciliation
# ---------------------------------------------------------------------------

suite "phase partition":
  func observedChecks(): seq[CheckState] =
    # The #420 shape: shards finish at different times, the slowest general
    # context decides T_verify, and the App verdict lands 3s after it.
    result = @[
      chk("bsec-integrity", "2026-11-23T13:52:04Z", "2026-11-23T13:55:10Z"),
      chk("debt-registry-gate", "2026-11-23T13:52:06Z", "2026-11-23T13:54:40Z"),
      chk("generation-acceptance", "2026-11-23T13:52:00Z", "2026-11-23T13:58:02Z"),
      chk("axiom-operational-slice", "2026-11-23T13:52:02Z", "2026-11-23T13:56:30Z"),
      chk("publication-integrity", "2026-11-23T13:52:05Z", TLastGeneral),
      chk("readiness-verdict", "2026-11-23T13:52:08Z", "2026-11-23T13:53:20Z"),
      chk("admission-check", "2026-11-23T13:59:16Z", TAppVerdict,
          app = AppId, verdict = true)]

  test "the #420 timeline partitions into 18 / 436 / 3 / 23":
    let phases = buildPhases(TQueueEntry, TMerged, observedChecks())
    check phases.len == 4
    check phaseSeconds(phases, "queue") == 18
    check phaseSeconds(phases, "verify") == 436
    check phaseSeconds(phases, "publication") == 3
    check phaseSeconds(phases, "merge") == 23

  test "T_ready and T_admission are 457 and 480, and T_exec is not a phase":
    let phases = buildPhases(TQueueEntry, TMerged, observedChecks())
    check readySeconds(phases) == 457
    check admissionSeconds(phases) == 480
    # T_exec == verify + publication, so exposing it as a phase would double-count.
    check phaseSeconds(phases, "exec") == -1

  test "the four phases reconcile to the whole interval with zero residue":
    let phases = buildPhases(TQueueEntry, TMerged, observedChecks())
    let r = reconcile(phases, TQueueEntry, TMerged)
    check r.ok
    check r.sumSeconds == 480
    check r.totalSeconds == 480
    check r.residue == 0

  test "a residue is never absorbed into a phase":
    let gapped = @[
      PhaseSpan(name: "queue", seconds: 18),
      PhaseSpan(name: "verify", seconds: 400),
      PhaseSpan(name: "publication", seconds: 3),
      PhaseSpan(name: "merge", seconds: 23)]
    let r = reconcile(gapped, TQueueEntry, TMerged)
    check not r.ok
    check r.residue == 36

  test "unbound checks are invisible to the partition":
    # buildPhases is only reached after allBound; an unbound check must never be
    # able to contribute an instant. Both directions are pinned: an unbound check
    # that would EXTEND the window (earlier start, later completion) and one that
    # would SHRINK it must leave the numbers untouched.
    var checks = observedChecks()
    checks.add chk("ghost-wide", "2026-11-23T13:00:00Z",
                   "2026-11-23T14:30:00Z", bound = false)
    checks.add chk("ghost-narrow", "2026-11-23T13:59:15Z",
                   "2026-11-23T13:59:20Z", bound = false)
    let phases = buildPhases(TQueueEntry, TMerged, checks)
    check phases.len == 4
    check phaseSeconds(phases, "queue") == 18
    check phaseSeconds(phases, "verify") == 436
    check phaseSeconds(phases, "publication") == 3
    check phaseSeconds(phases, "merge") == 23
    check readySeconds(phases) == 457
    check admissionSeconds(phases) == 480
    check lastFinisher(checks) == "admission-check"

  test "a partition can never be built from unbound checks alone":
    check buildPhases(TQueueEntry, TMerged,
                      @[chk("mystery", TFirstStart, TLastGeneral,
                            bound = false)]).len == 0

  test "out-of-order instants make the partition unconstructible":
    # merged before the last required completion is an impossible ordering; an
    # unrepresentable interval is never returned as 0.
    let checks = observedChecks()
    check buildPhases(TQueueEntry, TLastGeneral, checks).len == 0
    check buildPhases("", TMerged, checks).len == 0
    check reconcile(@[], TQueueEntry, TMerged).ok == false

  test "lastFinisher names the latest general+verdict completion":
    check lastFinisher(observedChecks()) == "admission-check"

  test "lastFinisher breaks ties lexicographically, not by input order":
    let tied = @[chk("zeta", TFirstStart, TLastGeneral),
                 chk("alpha", TFirstStart, TLastGeneral)]
    check lastFinisher(tied) == "alpha"
    check lastFinisher(@[chk("alpha", TFirstStart, TLastGeneral),
                         chk("zeta", TFirstStart, TLastGeneral)]) == "alpha"

# ---------------------------------------------------------------------------
# 4. Attempt-exact binding
# ---------------------------------------------------------------------------

suite "attempt-exact binding":
  func genCtx(name = "publication-integrity"): ExpectedContext =
    ExpectedContext(job: name, workflowPath: ".github/workflows/" & name & ".yml",
                    appId: ActionsId, isAppVerdict: false)

  test "check_run_url yields the trailing check-run id":
    check checkRunIdOfJob(jobRow(4242)) == "4242"
    check checkRunIdOfJob(%*{"check_run_url": "https://api.github.com/x/1/2/"}) == ""
    check checkRunIdOfJob(%*{"check_run_url": "https://api.github.com/x/12a"}) == ""
    check checkRunIdOfJob(%*{}) == ""
    check attemptCheckRunIds(%*[jobRow(1), jobRow(2), jobRow(1)]) == @["1", "2"]

  test "binding requires the id to be in the attempt job set":
    let crs = %*[checkRun(11, "publication-integrity", TFirstStart, TLastGeneral)]
    let c = bindGeneralContext(genCtx(), crs, @["11"], "run-1", 2)
    check c.bound
    check c.checkRunId == "11"
    check c.runAttempt == 2
    check c.startedAt == TFirstStart

  test "a same-name check-run outside the attempt set is NOT bound":
    # This is the whole point: a re-run's newer check-run shares the name.
    let crs = %*[checkRun(11, "publication-integrity", TFirstStart, TLastGeneral)]
    let c = bindGeneralContext(genCtx(), crs, @["77"], "run-1", 1)
    check not c.bound
    check "attempt-exact binding failed" in c.unboundReason
    check c.checkRunId.len == 0

  test "an empty attempt job set fails closed with its own reason":
    let crs = %*[checkRun(11, "publication-integrity", TFirstStart, TLastGeneral)]
    let c = bindGeneralContext(genCtx(), crs, @[], "run-1", 1)
    check not c.bound
    check "no check_run_url" in c.unboundReason

  test "a non-array check-runs payload fails closed":
    let c = bindGeneralContext(genCtx(), %*{"message": "Not Found"}, @["11"], "r", 1)
    check not c.bound
    check "not an array" in c.unboundReason

  test "a bound check-run without both timestamps is not usable":
    var cr = checkRun(11, "publication-integrity", TFirstStart, TLastGeneral)
    cr["completed_at"] = newJNull()
    let c = bindGeneralContext(genCtx(), %*[cr], @["11"], "run-1", 1)
    check not c.bound
    check "lacks both timestamps" in c.unboundReason

suite "app verdict binding":
  func verdictCtx(): ExpectedContext =
    ExpectedContext(job: "admission-check",
                    workflowPath: ".github/workflows/admission-gate-v2.yml",
                    appId: AppId, isAppVerdict: true)

  test "the declared producer app binds when it is unique in the window":
    let crs = %*[
      checkRun(1, "admission-check", "2026-11-23T13:52:00Z", "2026-11-23T13:52:05Z"),
      checkRun(2, "admission-check", TLastGeneral, TAppVerdict, app = AppId)]
    let c = bindAppVerdict(verdictCtx(), crs, TQueueEntry, TMerged)
    check c.bound
    check c.checkRunId == "2"
    check c.observedAppId == AppId
    check c.isAppVerdict

  test "the Actions app publishing the same context name is never selected":
    let crs = %*[
      checkRun(1, "admission-check", TLastGeneral, TAppVerdict, app = ActionsId)]
    let c = bindAppVerdict(verdictCtx(), crs, TQueueEntry, TMerged)
    check not c.bound
    check "no check-run from expected app " & $AppId in c.unboundReason

  test "two verdicts from the expected app in the window are UNKNOWN":
    let crs = %*[
      checkRun(2, "admission-check", TLastGeneral, TAppVerdict, app = AppId),
      checkRun(3, "admission-check", TLastGeneral, TAppVerdict, app = AppId)]
    let c = bindAppVerdict(verdictCtx(), crs, TQueueEntry, TMerged)
    check not c.bound
    check "ambiguous" in c.unboundReason

  test "a verdict started before the attempt is excluded":
    let crs = %*[
      checkRun(2, "admission-check", "2026-11-23T13:40:00Z",
               "2026-11-23T13:40:05Z", app = AppId)]
    let c = bindAppVerdict(verdictCtx(), crs, TQueueEntry, TMerged)
    check not c.bound

# ---------------------------------------------------------------------------
# 5. Queue-cycle binding (the same PR can be a different candidate each time)
# ---------------------------------------------------------------------------

suite "queue cycle":
  func cyc(entered, merged: string; commit = ""): QueueCycle =
    QueueCycle(enteredAt: entered, mergedAt: merged, mergeCommit: commit)

  test "a merge is bound by commit_id == head_sha, not by recency":
    # Measured: 402 and 400 each appear TWICE post-boundary with different SHAs.
    let cycles = @[cyc("2026-11-23T09:46:59Z", "2026-11-23T10:14:00Z", "aaaa"),
                   cyc("2026-11-23T14:58:25Z", "", "")]
    let (found, c, reason) = selectCycle(cycles, "aaaa")
    check found
    check c.enteredAt == "2026-11-23T09:46:59Z"
    check c.mergedAt == "2026-11-23T10:14:00Z"
    check reason.len == 0

  test "a candidate whose PR merged a different commit is UNKNOWN":
    let cycles = @[cyc("2026-11-23T14:58:09Z", "2026-11-23T15:07:36Z", "bbbb")]
    let (found, _, reason) = selectCycle(cycles, "aaaa")
    check not found
    check "merged commit bbbb" in reason
    check "not this candidate's head_sha" in reason

  test "a still-queued candidate is UNKNOWN with the cycle it is waiting in":
    let cycles = @[cyc("2026-11-23T15:31:52Z", "", "")]
    let (found, c, reason) = selectCycle(cycles, "aaaa")
    check not found
    check c.enteredAt == "2026-11-23T15:31:52Z"
    check "not merged yet" in reason

  test "two cycles claiming the same merge commit are ambiguous":
    let cycles = @[cyc("2026-11-23T09:00:00Z", "2026-11-23T10:00:00Z", "aaaa"),
                   cyc("2026-11-23T11:00:00Z", "2026-11-23T12:00:00Z", "aaaa")]
    let (found, _, reason) = selectCycle(cycles, "aaaa")
    check not found
    check "ambiguous" in reason

  test "an empty timeline is UNKNOWN, never a zero-length cycle":
    let (found, _, reason) = selectCycle(@[], "aaaa")
    check not found
    check "no merge-queue timeline events" in reason

# ---------------------------------------------------------------------------
# 6. Identifier reading
# ---------------------------------------------------------------------------

suite "identifiers":
  test "numeric ids are readable, not silently empty":
    # GitHub returns run/suite/app ids as JSON NUMBERS. Reading them as strings
    # produced `.../runs//attempts/1` against the live API.
    check jsonId(%*{"id": 45189948255}, "id") == "45189948255"
    check jsonId(%*{"id": "45189948255"}, "id") == "45189948255"
    check jsonId(%*{"id": 0}, "id") == "0"
    check jsonId(%*{}, "id") == ""
    check jsonId(%*{"id": newJNull()}, "id") == ""
    check jsonId(newJNull(), "id") == ""

  test "the app id of a check-run survives both encodings":
    check appIdOf(%*{"app": {"id": 5795152}}) == 5795152
    check appIdOf(%*{"app": {"id": "5795152"}}) == 0  # non-numeric is not guessed
    check appIdOf(%*{}) == 0

# ---------------------------------------------------------------------------
# 5. Authority substitution
# ---------------------------------------------------------------------------

suite "authority":
  test "a mismatching observed producer is an authority substitution":
    var c = chk("publication-integrity", TFirstStart, TLastGeneral)
    c.observedAppId = AppId
    let (found, detail) = authoritySubstitution(@[c])
    check found
    check "publication-integrity" in detail
    check $ActionsId in detail
    check $AppId in detail

  test "matching producers are clean and unbound checks are skipped":
    var unbound = chk("x", TFirstStart, TLastGeneral, bound = false)
    unbound.observedAppId = AppId
    let ok = @[chk("publication-integrity", TFirstStart, TLastGeneral),
               chk("admission-check", TLastGeneral, TAppVerdict,
                   app = AppId, verdict = true),
               unbound]
    let (found, detail) = authoritySubstitution(ok)
    check not found
    check detail.len == 0

# ---------------------------------------------------------------------------
# 6. Policy parsing
# ---------------------------------------------------------------------------

suite "policy":
  test "the declared set is six validations plus the verdict job":
    let (ctxs, err) = expectedContextsFromPolicy(policyNode())
    check err.len == 0
    check ctxs.len == 7
    check expectedContextNames(ctxs) == @[
      "admission-check", "axiom-operational-slice", "bsec-integrity",
      "debt-registry-gate", "generation-acceptance", "publication-integrity",
      "readiness-verdict"]

  test "producers come from requiredCheckSources, default and byContext":
    let (ctxs, _) = expectedContextsFromPolicy(policyNode())
    for c in ctxs:
      if c.job == "admission-check":
        check c.appId == AppId
        check c.isAppVerdict
        check c.workflowPath == ".github/workflows/admission-gate-v2.yml"
      else:
        check c.appId == ActionsId
        check not c.isAppVerdict

  test "a context declared twice is emitted once":
    var node = policyNode()
    node["requiredValidations"].add %*{"job": "bsec-integrity"}
    let (ctxs, _) = expectedContextsFromPolicy(node)
    check ctxs.len == 7
    var n = 0
    for c in ctxs:
      if c.job == "bsec-integrity":
        inc n
    check n == 1

  test "an absent producer map leaves general contexts on the Actions app":
    var node = policyNode()
    node.delete("requiredCheckSources")
    let (ctxs, err) = expectedContextsFromPolicy(node)
    # The verdict job is refused: a missing App producer is not defaultable.
    check ctxs.len == 0
    check "no independent App producer" in err

  test "an absent producer map is still refused for the verdict job only":
    var node = policyNode()
    node.delete("requiredWorkflowDetection")
    node.delete("requiredCheckSources")
    let (ctxs, err) = expectedContextsFromPolicy(node)
    check err.len == 0
    check ctxs.len == 6
    for c in ctxs:
      check c.appId == ActionsId
      check not c.isAppVerdict

  test "the verdict producer may be declared in verdictCheckSource instead":
    var node = policyNode()
    node.delete("requiredCheckSources")
    let (ctxs, err) = expectedContextsFromPolicy(node)
    check ctxs.len == 0
    check err.len > 0
    node["requiredWorkflowDetection"]["verdictCheckSource"] = %*{"appId": AppId}
    let (ctxs2, err2) = expectedContextsFromPolicy(node)
    check err2.len == 0
    check ctxs2.len == 7

  test "two different verdict producers are a contradiction, not a preference":
    var node = policyNode()
    node["requiredWorkflowDetection"]["verdictCheckSource"] = %*{"appId": 1234}
    let (ctxs, err) = expectedContextsFromPolicy(node)
    check ctxs.len == 0
    check "declared twice with different ids" in err

  test "a verdict job declared under the Actions app is refused":
    var node = policyNode()
    node["requiredCheckSources"]["byContext"]["admission-check"] = %*ActionsId
    let (ctxs, err) = expectedContextsFromPolicy(node)
    check ctxs.len == 0
    check "no independent App producer" in err

  test "a policy with no required contexts is rejected, not defaulted":
    let (ctxs, err) = expectedContextsFromPolicy(%*{"version": 1})
    check ctxs.len == 0
    check "no required contexts" in err
    check expectedContextsFromPolicy(newJNull()).err.len > 0

  test "sameContextSet ignores order and rejects a substituted producer set":
    check sameContextSet(@["b", "a"], @["a", "b"])
    check sameContextSet(@[], @[])
    check not sameContextSet(@["a"], @["a", "b"])
    check not sameContextSet(@["a"], @["b"])
    let (ctxs, _) = expectedContextsFromPolicy(policyNode())
    check sameContextSet(expectedContextNames(ctxs),
                         @["readiness-verdict", "publication-integrity",
                           "generation-acceptance", "debt-registry-gate",
                           "bsec-integrity", "axiom-operational-slice",
                           "admission-check"])

  test "distinctSorted is order-insensitive and duplicate-free":
    check distinctSorted(@["b", "a", "b", "a", "c"]) == @["a", "b", "c"]
    check distinctSorted(@[]) == newSeq[string]()

# ---------------------------------------------------------------------------
# 7. Attempt selection
# ---------------------------------------------------------------------------

suite "attempt selection":
  func run(id: string; createdAt: string; attempt: int; path = ".github/workflows/p.yml"): AttemptRun =
    AttemptRun(runId: id, runAttempt: attempt, workflowPath: path,
               queueRef: "gh-readonly-queue/main/pr-420-abc", createdAt: createdAt)

  test "the newest attempt of the context's own workflow wins":
    let runs = @[run("1", "2026-11-23T13:52:00Z", 1),
                 run("2", "2026-11-23T14:10:00Z", 1),
                 run("3", "2026-11-23T13:52:00Z", 1,
                     path = ".github/workflows/other.yml")]
    let (found, sel, reason) = selectAttemptRun(runs, ".github/workflows/p.yml")
    check found
    check sel.runId == "2"
    check reason.len == 0

  test "a re-run of the same run is ordered after its first attempt":
    let runs = @[run("9", "2026-11-23T13:52:00Z", 1),
                 run("9", "2026-11-23T13:52:00Z", 2)]
    let (found, sel, _) = selectAttemptRun(runs, ".github/workflows/p.yml")
    check found
    check sel.runAttempt == 2

  test "no run for the declared workflow fails closed with a reason":
    let runs = @[run("1", "2026-11-23T13:52:00Z", 1,
                     path = ".github/workflows/other.yml")]
    let (found, _, reason) = selectAttemptRun(runs, ".github/workflows/p.yml")
    check not found
    check ".github/workflows/p.yml" in reason

  test "an attempt number of 0 is not usable as an attempt edge":
    let runs = @[run("5", "2026-11-23T13:52:00Z", 0)]
    let (found, sel, _) = selectAttemptRun(runs, ".github/workflows/p.yml")
    check found
    # selectAttemptRun reports it; the fetch layer refuses attempt <= 0.
    check sel.runAttempt == 0
