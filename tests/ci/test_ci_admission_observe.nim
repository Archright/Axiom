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

import std/[algorithm, json, strutils, unittest]

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
  RunId = "45189948255"
  RunSha = "7f3424cca91f343aa55354b3084af97e30bf65d4"

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

# ---------------------------------------------------------------------------
# 8. Workflow YAML — `jobs:` and `needs:` only
# ---------------------------------------------------------------------------

const GateYaml = """name: admission-gate-v2
on:
  merge_group:
jobs:
  anchor-resolve:
    runs-on: ubuntu-latest
    steps:
      - name: resolve
        run: |
          echo "needs: [rogue-job]"
          echo "  attest:"
  closure-deriver:
    needs: [anchor-resolve]
  attest:
    needs: [anchor-resolve]
  mint-prepare:
    needs: [attest, anchor-resolve]
  mint-publish:
    needs: [mint-prepare, gateway, anchor-resolve]
  gateway:
    needs: [closure-deriver]
  verdict:
    needs: [mint-prepare, closure-deriver, anchor-resolve]
  admission-check:
    name: admission-check
    needs: [anchor-resolve, closure-deriver, attest, mint-prepare, mint-publish, verdict, gateway]
"""

suite "workflow YAML":
  test "the declared job ids and needs edges are read from `jobs:`":
    let (ok, g, err) = parseWorkflowJobs(GateYaml)
    check ok
    check err.len == 0
    check g.jobs == @["admission-check", "anchor-resolve", "attest",
                       "closure-deriver", "gateway", "mint-prepare",
                       "mint-publish", "verdict"]
    check g.needs.len == 18
    # admission-check needs all seven producers; anchor-resolve needs nothing.
    var headCount = 0
    for e in g.needs:
      if e.jobId == "anchor-resolve":
        inc headCount
    check headCount == 0
    var acCount = 0
    for e in g.needs:
      if e.jobId == "admission-check":
        inc acCount
    check acCount == 7
    check graphValidation(g).len == 0

  test "a `run: |` body is never mistaken for job or needs structure":
    # The block scalar above contains `needs: [rogue-job]` and `  attest:`, both
    # of which would fabricate a job id or an edge if indentation were ignored.
    let (ok, g, _) = parseWorkflowJobs(GateYaml)
    check ok
    check "rogue-job" notin g.jobs
    for e in g.needs:
      check e.need != "rogue-job"

  test "a job-level `name:` is captured, not treated as a job id":
    let (ok, g, _) = parseWorkflowJobs(GateYaml)
    check ok
    check g.jobNames.len == 1
    check g.jobNames[0].jobId == "admission-check"
    check g.jobNames[0].name == "admission-check"

  test "the block-list needs form is parsed the same as the flow form":
    let yaml = """
jobs:
  a:
    needs:
      - b
      - c
  b:
  c:
"""
    let (ok, g, err) = parseWorkflowJobs(yaml)
    check ok
    check err.len == 0
    check g.needs == @[(jobId: "a", need: "b"), (jobId: "a", need: "c")]

  test "a needs edge naming an undeclared job is an error, not a dropped edge":
    let yaml = """
jobs:
  a:
    needs: [ghost]
"""
    let (ok, _, err) = parseWorkflowJobs(yaml)
    check not ok
    check "undeclared job 'ghost'" in err

  test "a needs cycle is an error":
    let yaml = """
jobs:
  a:
    needs: [b]
  b:
    needs: [a]
"""
    let (ok, _, err) = parseWorkflowJobs(yaml)
    check not ok
    check "cycle" in err

  test "a duplicate job id is an error":
    let yaml = """
jobs:
  a:
  a:
"""
    let (ok, _, err) = parseWorkflowJobs(yaml)
    check not ok
    check "duplicate job id" in err

  test "a document with no `jobs:` is an error":
    let (ok, _, err) = parseWorkflowJobs("name: x\non: push\n")
    check not ok
    check "no top-level 'jobs:'" in err

# ---------------------------------------------------------------------------
# 9. DAG attribution — prefix rule, never suffix inversion
# ---------------------------------------------------------------------------

func gateJobIds(): seq[string] =
  @["admission-check", "anchor-resolve", "attest", "closure-deriver", "gateway",
    "mint-prepare", "mint-publish", "verdict"]

suite "DAG attribution":
  test "`attest / admission-check` attributes to `attest`, not to `admission-check`":
    # `admission-check` IS a top-level job id, so a suffix parse silently binds
    # the callee's inner job to the WRONG producer. The prefix rule is the whole
    # defence; this assertion is the proof that it is the rule in force.
    let (id, reason) = attributeRecord(gateJobIds(), "attest / admission-check")
    check reason.len == 0
    check id == "attest"

  test "`verdict / admission-check` attributes to `verdict`":
    let (id, _) = attributeRecord(gateJobIds(), "verdict / admission-check")
    check id == "verdict"

  test "a matrix instance attributes to its caller job id":
    check attributeRecord(gateJobIds(), "attest / go-critical-lane (0)").jobId == "attest"
    check attributeRecord(gateJobIds(), "attest / go-critical-lane (3)").jobId == "attest"

  test "an exact job id attributes to itself":
    check attributeRecord(gateJobIds(), "admission-check").jobId == "admission-check"
    check attributeRecord(gateJobIds(), "gateway").jobId == "gateway"

  test "a separator is required; a bare prefix is not an attribution":
    # "attestation" starts with "attest" but is a different job.
    let (id, reason) = attributeRecord(gateJobIds(), "attestation")
    check id.len == 0
    check reason.len > 0

  test "an unattributable name is UNKNOWN, never a nearest guess":
    let (id, reason) = attributeRecord(gateJobIds(), "mystery-job")
    check id.len == 0
    check "attributes to no declared job id" in reason

  test "a name that declares an undeclared job id is a hard rejection":
    let (id, reason) = attributeRecord(gateJobIds(), "rogue-job / build")
    check id.len == 0
    check "does not declare" in reason

  test "a job-level `name:` makes a bare record name unattributable":
    let names = @[JobNameDecl(jobId: "admission-check", name: "Final Verdict")]
    let (id, reason) = attributeRecord(gateJobIds(), "Final Verdict", names)
    check id.len == 0
    check "`name:`" in reason

# ---------------------------------------------------------------------------
# 10. DAG bucketing — reusable-workflow expansion
# ---------------------------------------------------------------------------

func dagRecord(name, start, done: string; conclusion = "success";
               created = ""; jobSha = RunSha;
               attempt = 2): JobRecord =
  JobRecord(name: name, runId: RunId, runAttempt: attempt, headSha: jobSha,
            status: "completed", conclusion: conclusion, startedAt: start,
            completedAt: done, createdAt: created)

# The real bucket sizes of one observed attempt: 26 records over 8 job ids.
const
  AttestNames = ["attest / build-base-artifacts",
                 "attest / go-critical-lane (0)", "attest / go-critical-lane (1)",
                 "attest / go-critical-lane (2)", "attest / admission-check",
                 "attest / admission-independents"]
  GatewayNames = ["gateway / select", "gateway / candidate-build",
                  "gateway / candidate-build-arm", "gateway / gateway-shard (0)",
                  "gateway / gateway-shard (1)", "gateway / gateway-identity-gate",
                  "gateway / proof-reconcile", "gateway / sl09-scope"]
  VerdictNames = ["verdict / build-base-artifacts", "verdict / go-critical-lane (0)",
                  "verdict / go-critical-lane (1)", "verdict / admission-check",
                  "verdict / admission-independents"]
  MintPrepareNames = ["mint-prepare / prepare", "mint-prepare / publish"]
  MintPublishNames = ["mint-publish / prepare", "mint-publish / publish"]

func expansionRecords(): seq[JobRecord] =
  ## 6 + 8 + 5 + 2 + 2 + 1 + 1 + 1 = 26 records onto 8 declared job ids, on ONE
  ## coherent timeline: the chain comes out exactly equal to the run's own wall.
  ## anchor-resolve 04:34:50-04:34:55, closure-deriver ...-04:35:00,
  ## attest ...-04:35:10, gateway ...-04:36:00, mint-prepare ...-04:36:00,
  ## mint-publish ...-04:36:30, verdict ...-04:37:00,
  ## admission-check 04:37:01-04:37:10.
  for n in AttestNames:
    result.add dagRecord(n, "2026-11-24T04:35:00Z", "2026-11-24T04:35:10Z",
                         created = "2026-11-24T04:35:00Z")
  for n in GatewayNames:
    result.add dagRecord(n, "2026-11-24T04:35:00Z", "2026-11-24T04:36:00Z",
                         created = "2026-11-24T04:35:00Z")
  for n in VerdictNames:
    result.add dagRecord(n, "2026-11-24T04:36:01Z", "2026-11-24T04:37:00Z",
                         created = "2026-11-24T04:36:01Z")
  # prepare runs, publish is ALWAYS skipped — retained, never filtered.
  result.add dagRecord(MintPrepareNames[0], "2026-11-24T04:35:10Z",
                       "2026-11-24T04:36:00Z",
                       created = "2026-11-24T04:35:10Z")
  result.add dagRecord(MintPrepareNames[1], "2026-11-24T04:36:00Z",
                       "2026-11-24T04:36:00Z", conclusion = "skipped",
                       created = "2026-11-24T04:36:00Z")
  result.add dagRecord(MintPublishNames[0], "2026-11-24T04:36:00Z",
                       "2026-11-24T04:36:30Z",
                       created = "2026-11-24T04:36:00Z")
  result.add dagRecord(MintPublishNames[1], "2026-11-24T04:36:30Z",
                       "2026-11-24T04:36:30Z", conclusion = "skipped",
                       created = "2026-11-24T04:36:30Z")
  result.add dagRecord("anchor-resolve", "2026-11-24T04:34:50Z",
                       "2026-11-24T04:34:55Z",
                       created = "2026-11-24T04:34:50Z")
  result.add dagRecord("closure-deriver", "2026-11-24T04:34:56Z",
                       "2026-11-24T04:35:00Z",
                       created = "2026-11-24T04:34:56Z")
  result.add dagRecord("admission-check", "2026-11-24T04:37:01Z",
                       "2026-11-24T04:37:10Z",
                       created = "2026-11-24T04:37:01Z")

suite "DAG bucketing":
  test "26 records expand onto 8 job ids with zero remainder":
    let (ok, g, err) = parseWorkflowJobs(GateYaml)
    check ok
    check err.len == 0
    let recs = expansionRecords()
    check recs.len == 26
    let b = bucketRecords(g, recs, RunId, 2, RunSha)
    check b.status == dsMeasured
    check b.reason.len == 0
    check b.buckets.len == 8
    var total = 0
    for x in b.buckets:
      total += x.members
      case x.jobId
      of "attest": check x.members == 6
      of "gateway": check x.members == 8
      of "verdict": check x.members == 5
      of "mint-prepare": check x.members == 2
      of "mint-publish": check x.members == 2
      of "anchor-resolve": check x.members == 1
      of "closure-deriver": check x.members == 1
      of "admission-check": check x.members == 1
      else: check false
    # Zero remainder: every record landed in exactly one bucket.
    check total == recs.len

  test "the skipped half of a reusable expansion is retained":
    let (ok, g, _) = parseWorkflowJobs(GateYaml)
    check ok
    let b = bucketRecords(g, expansionRecords(), RunId, 2, RunSha)
    var mp: Bucket
    for x in b.buckets:
      if x.jobId == "mint-prepare":
        mp = x
    check mp.members == 2
    check mp.skippedMembers == 1
    # A skipped record is not a success, and it never becomes one.
    check not mp.allSuccess

  test "bucket completed_at is max across the bucket, never min or any member":
    let (ok, g, _) = parseWorkflowJobs(GateYaml)
    check ok
    var recs = expansionRecords()
    # attest members finish at 04:36:00 except one at 04:35:10.
    recs.add dagRecord("attest / late-shard", "2026-11-24T04:35:00Z",
                       "2026-11-24T04:37:00Z")
    let b = bucketRecords(g, recs, RunId, 2, RunSha)
    check b.status == dsMeasured
    check b.reason.len == 0
    for x in b.buckets:
      if x.jobId == "attest":
        check x.completedAt == "2026-11-24T04:37:00Z"

  test "input record order does not change the buckets":
    let (ok, g, _) = parseWorkflowJobs(GateYaml)
    check ok
    let forward = expansionRecords()
    var backward = expansionRecords()
    backward.reverse()
    let a = bucketRecords(g, forward, RunId, 2, RunSha)
    let b = bucketRecords(g, backward, RunId, 2, RunSha)
    check a.status == b.status
    check a.buckets.len == b.buckets.len
    for i in 0 ..< a.buckets.len:
      check a.buckets[i].jobId == b.buckets[i].jobId
      check a.buckets[i].members == b.buckets[i].members
      check a.buckets[i].startedAt == b.buckets[i].startedAt
      check a.buckets[i].completedAt == b.buckets[i].completedAt
      check a.buckets[i].seconds == b.buckets[i].seconds

  test "a job SHA that differs from the run SHA is rejected":
    let (ok, g, _) = parseWorkflowJobs(GateYaml)
    check ok
    var recs = expansionRecords()
    recs[0] = dagRecord(recs[0].name, recs[0].startedAt, recs[0].completedAt,
                        jobSha = "0000000000000000000000000000000000000000")
    let b = bucketRecords(g, recs, RunId, 2, RunSha)
    check b.status == dsFailed
    check "head_sha" in b.reason

  test "a run_attempt mismatch is rejected":
    let (ok, g, _) = parseWorkflowJobs(GateYaml)
    check ok
    var recs = expansionRecords()
    recs[0] = dagRecord(recs[0].name, recs[0].startedAt, recs[0].completedAt,
                        attempt = 1)
    let b = bucketRecords(g, recs, RunId, 2, RunSha)
    check b.status == dsFailed
    check "run_attempt" in b.reason

  test "a record present in the API but absent from the graph is rejected":
    let (ok, g, _) = parseWorkflowJobs(GateYaml)
    check ok
    var recs = expansionRecords()
    recs.add dagRecord("rogue-job / build", "2026-11-24T04:35:00Z",
                       "2026-11-24T04:35:10Z")
    let b = bucketRecords(g, recs, RunId, 2, RunSha)
    check b.status == dsFailed
    check "does not declare" in b.reason

  test "a declared job with no record is UNKNOWN, never a zero-weight node":
    let (ok, g, _) = parseWorkflowJobs(GateYaml)
    check ok
    var recs = expansionRecords()
    var kept: seq[JobRecord] = @[]
    for r in recs:
      if r.name != "closure-deriver":
        kept.add r
    let b = bucketRecords(g, kept, RunId, 2, RunSha)
    check b.status == dsUnknown
    check "no job record" in b.reason

# ---------------------------------------------------------------------------
# 11. Critical path
# ---------------------------------------------------------------------------

suite "critical path":
  func simpleGraph(): WorkflowGraph =
    WorkflowGraph(jobs: @["a", "b", "c"],
                  needs: @[(jobId: "b", need: "a"), (jobId: "c", need: "b")])

  func bucket(id, start, done, created: string): Bucket =
    Bucket(jobId: id, members: 1, startedAt: start, completedAt: done,
           createdAt: created, allSuccess: true,
           seconds: max(0, secsBetween(done, start)))

  test "the longest path is the sum of node spans plus handoff waits":
    let buckets = @[
      bucket("a", "2026-11-24T04:00:00Z", "2026-11-24T04:01:00Z",
             "2026-11-24T03:59:00Z"),
      bucket("b", "2026-11-24T04:01:05Z", "2026-11-24T04:03:00Z",
             "2026-11-24T04:01:05Z"),
      bucket("c", "2026-11-24T04:03:02Z", "2026-11-24T04:03:10Z",
             "2026-11-24T04:03:02Z")]
    # a=60, edge a->b = 5, b=115, edge b->c = 2, c=8  => 190
    let cp = criticalPath(simpleGraph(), buckets, 200)
    check cp.status == dsMeasured
    check cp.reason.len == 0
    check cp.seconds == 190
    check cp.path == @["a", "b", "c"]

  test "multiple predecessors: the one carrying the longer chain wins":
    # A predecessor's total contribution is (consumer created_at - its own chain
    # root start + consumer span), so the EARLIEST chain root wins. The tie a
    # plain "longer job span" would produce is broken by an earlier root here.
    var g = WorkflowGraph(
      jobs: @["p", "q", "s"],
      needs: @[(jobId: "s", need: "p"), (jobId: "s", need: "q")])
    let buckets = @[
      bucket("p", "2026-11-24T04:04:00Z", "2026-11-24T04:04:55Z",
             "2026-11-24T04:04:00Z"),
      bucket("q", "2026-11-24T04:00:00Z", "2026-11-24T04:05:00Z",
             "2026-11-24T04:00:00Z"),
      bucket("s", "2026-11-24T04:05:01Z", "2026-11-24T04:06:00Z",
             "2026-11-24T04:05:01Z")]
    let cp = criticalPath(g, buckets, 400)
    check cp.status == dsMeasured
    check cp.reason.len == 0
    # q: 300 + edge(1) + s(59) = 360. p: 55 + edge(6) + 59 = 120.
    check cp.path == @["q", "s"]
    check cp.seconds == 360

  test "a negative edge weight clamps to 0 and is recorded as an anomaly":
    # A real run has `gateway / proof-reconcile` completed 2s BEFORE its own
    # created_at — a GitHub artifact on skipped jobs. Never a negative weight.
    let buckets = @[
      bucket("a", "2026-11-24T04:00:00Z", "2026-11-24T04:01:00Z",
             "2026-11-24T03:59:00Z"),
      bucket("b", "2026-11-24T04:00:58Z", "2026-11-24T04:01:30Z",
             "2026-11-24T04:00:58Z"),
      bucket("c", "2026-11-24T04:01:31Z", "2026-11-24T04:01:40Z",
             "2026-11-24T04:01:31Z")]
    let cp = criticalPath(simpleGraph(), buckets, 200)
    check cp.status == dsMeasured
    check cp.reason.len == 0
    var found = false
    for a in cp.anomalies:
      if "negative edge 'a' -> 'b'" in a:
        found = true
    check found
    check cp.seconds == 60 + 0 + 32 + 1 + 9

  test "an absent consumer created_at makes the answer a LOWER BOUND":
    # The edge weight is the CONSUMER's created_at, so a consumer without one
    # leaves the gap unknown. Unknown is a lower bound, never a 0.
    var buckets = @[
      bucket("a", "2026-11-24T04:00:00Z", "2026-11-24T04:01:00Z",
             "2026-11-24T03:59:00Z"),
      bucket("b", "2026-11-24T04:01:05Z", "2026-11-24T04:03:00Z", ""),
      bucket("c", "2026-11-24T04:03:02Z", "2026-11-24T04:03:10Z",
             "2026-11-24T04:03:02Z")]
    let cp = criticalPath(simpleGraph(), buckets, 200)
    check cp.status == dsMeasured
    check cp.reason.len == 0
    check cp.lowerBound
    var flagged = false
    for a in cp.anomalies:
      if "NO_LOG_SOURCE" in a:
        flagged = true
    check flagged
    # 60 + (unknown -> 0) + 115 + 2 + 8
    check cp.seconds == 185

  test "a missing instant on a node fails closed, never substituted as 0":
    var buckets = @[
      bucket("a", "2026-11-24T04:00:00Z", "2026-11-24T04:01:00Z",
             "2026-11-24T03:59:00Z"),
      bucket("b", "", "", "2026-11-24T04:01:05Z"),
      bucket("c", "2026-11-24T04:03:02Z", "2026-11-24T04:03:10Z",
             "2026-11-24T04:03:02Z")]
    let cp = criticalPath(simpleGraph(), buckets, 200)
    check cp.status == dsUnknown
    check "no usable started_at/completed_at" in cp.reason

  test "a missing created_at on a node with no predecessor is not an anomaly":
    # The first batch has no edge weight to lose, so its absent created_at only
    # affects `queuedSeconds` — which is reported separately and as NO_LOG_SOURCE.
    var buckets = @[
      bucket("a", "2026-11-24T04:00:00Z", "2026-11-24T04:01:00Z", ""),
      bucket("b", "2026-11-24T04:01:05Z", "2026-11-24T04:03:00Z",
             "2026-11-24T04:01:05Z"),
      bucket("c", "2026-11-24T04:03:02Z", "2026-11-24T04:03:10Z",
             "2026-11-24T04:03:02Z")]
    let cp = criticalPath(simpleGraph(), buckets, 200)
    check cp.status == dsMeasured
    check not cp.lowerBound
    # 60 + 5 + 115 + 2 + 8
    check cp.seconds == 190

  test "identical completed_at resolves deterministically, not by input order":
    var g = WorkflowGraph(
      jobs: @["a", "b"],
      needs: @[(jobId: "b", need: "a")])
    let one = @[
      bucket("a", "2026-11-24T04:00:00Z", "2026-11-24T04:01:00Z",
             "2026-11-24T03:59:00Z"),
      bucket("b", "2026-11-24T04:01:00Z", "2026-11-24T04:02:00Z",
             "2026-11-24T04:01:00Z")]
    var two = one
    two.reverse()
    let p1 = criticalPath(g, one, 200)
    let p2 = criticalPath(g, two, 200)
    check p1.status == dsMeasured
    check p1.seconds == p2.seconds
    check p1.path == p2.path

  test "a critical path longer than the workflow wall is a hard error":
    # Two overlapping jobs declared as a chain: the serial reconstruction exceeds
    # the observed wall, so the graph and the timestamps contradict each other.
    var g = WorkflowGraph(jobs: @["a", "b"], needs: @[(jobId: "b", need: "a")])
    let buckets = @[
      bucket("a", "2026-11-24T04:00:00Z", "2026-11-24T04:01:00Z",
             "2026-11-24T04:00:00Z"),
      bucket("b", "2026-11-24T04:00:30Z", "2026-11-24T04:01:30Z",
             "2026-11-24T04:00:30Z")]
    # path = 60 + 0 + 60 = 120, wall = 90
    let cp = criticalPath(g, buckets, 90)
    check cp.status == dsFailed
    check "exceeds wallSeconds" in cp.reason

  test "a needs cycle in a hand-built graph is a hard error":
    var g = WorkflowGraph(jobs: @["a", "b"],
                          needs: @[(jobId: "a", need: "b"),
                                   (jobId: "b", need: "a")])
    let buckets = @[
      bucket("a", "2026-11-24T04:00:00Z", "2026-11-24T04:01:00Z", ""),
      bucket("b", "2026-11-24T04:00:00Z", "2026-11-24T04:01:00Z", "")]
    let cp = criticalPath(g, buckets, 200)
    check cp.status == dsFailed
    check "cycle" in cp.reason

  test "skipped, cancelled and null conclusions are never a success":
    var recs = @[
      dagRecord("a", "2026-11-24T04:00:00Z", "2026-11-24T04:01:00Z"),
      dagRecord("b", "2026-11-24T04:01:00Z", "2026-11-24T04:02:00Z",
                conclusion = "skipped"),
      dagRecord("c", "2026-11-24T04:02:00Z", "2026-11-24T04:03:00Z",
                conclusion = "cancelled"),
      dagRecord("d", "2026-11-24T04:03:00Z", "2026-11-24T04:04:00Z",
                conclusion = "")]
    let g = WorkflowGraph(jobs: @["a", "b", "c", "d"], needs: @[])
    let b = bucketRecords(g, recs, RunId, 2, RunSha)
    check b.status == dsMeasured
    check b.reason.len == 0
    for x in b.buckets:
      if x.jobId == "a":
        check x.allSuccess
      else:
        check not x.allSuccess

  test "measureWorkflowDag divides by the same workflow's wall only":
    let (ok, g, _) = parseWorkflowJobs(GateYaml)
    check ok
    var gg = g
    gg.blobSha = "abc123"
    gg.yamlRef = RunSha
    let r = measureWorkflowDag(gg, expansionRecords(),
                               ".github/workflows/admission-gate-v2.yml",
                               RunId, 2, RunSha)
    check r.status == dsMeasured
    check r.reason.len == 0
    check r.blobSha == "abc123"
    check r.yamlRef == RunSha
    check r.wallSeconds == secsBetween("2026-11-24T04:37:10Z",
                                       "2026-11-24T04:34:50Z")
    check r.criticalPathSeconds <= r.wallSeconds
    check abs(r.shareOfWall - float(r.criticalPathSeconds) /
               float(r.wallSeconds)) < 0.0001

# ---------------------------------------------------------------------------
# 12. Queue decomposition — two phenomena, never one sum
# ---------------------------------------------------------------------------

suite "queue decomposition":
  func qbucket(id, start, done, created: string): Bucket =
    Bucket(jobId: id, members: 1, startedAt: start, completedAt: done,
           createdAt: created, allSuccess: true,
           seconds: max(0, secsBetween(done, start)))

  test "batch 0 is the set with no needs":
    let g = WorkflowGraph(jobs: @["a", "b", "c"],
                          needs: @[(jobId: "b", need: "a"),
                                   (jobId: "c", need: "b")])
    let batches = batchIndexOf(g)
    for e in batches:
      case e.jobId
      of "a": check e.batch == 0
      of "b": check e.batch == 1
      of "c": check e.batch == 2
      else: check false

  test "first-batch queueing and dependency handoff stay separate":
    let g = WorkflowGraph(jobs: @["a", "b"],
                          needs: @[(jobId: "b", need: "a")])
    let buckets = @[
      qbucket("a", "2026-11-24T04:00:10Z", "2026-11-24T04:01:00Z",
              "2026-11-24T04:00:00Z"),
      qbucket("b", "2026-11-24T04:01:03Z", "2026-11-24T04:02:00Z",
              "2026-11-24T04:01:03Z")]
    let q = queueReport(g, buckets)
    check q.status == "MEASURED"
    check q.firstBatch.len == 1
    check q.firstBatch[0].jobId == "a"
    check q.firstBatch[0].seconds == 10
    check q.handoff.len == 1
    check q.handoff[0].jobId == "b"
    check q.handoff[0].seconds == 3
    # Never a single mixed sum.
    check q.firstBatch[0].seconds + q.handoff[0].seconds != 10

  test "an absent created_at is NO_LOG_SOURCE, never 0":
    let g = WorkflowGraph(jobs: @["a", "b"],
                          needs: @[(jobId: "b", need: "a")])
    let buckets = @[
      qbucket("a", "2026-11-24T04:00:10Z", "2026-11-24T04:01:00Z", ""),
      qbucket("b", "2026-11-24T04:01:03Z", "2026-11-24T04:02:00Z",
              "2026-11-24T04:01:03Z")]
    let q = queueReport(g, buckets)
    check q.status == "NO_LOG_SOURCE"
    check q.firstBatch.len == 0
    var flagged = false
    for a in q.anomalies:
      if "NO_LOG_SOURCE" in a:
        flagged = true
    check flagged
