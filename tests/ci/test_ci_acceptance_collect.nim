## test_ci_acceptance_collect.nim — fixtures for tools/ci/ci_acceptance_collect.nim.
##
## NO network, NO subprocess, NO git: the collector's pure core is imported
## directly and every case is a synthetic run/attempt/evidence/job fixture. The
## cases pin the contract (docs/spec/ci_acceptance_contract.md):
##
##   * one entry per unique merge_group head_sha; re-runs are attempts;
##   * boundary filter (pre-boundary excluded, unknown ancestry stays as a gap);
##   * worst-of classification across attempts; retries never erase incidents;
##   * internal subtype precedence authority > soundness > identity > projection;
##   * NO_CERT/SUBJECT_MISMATCH decided by the same attempt's mint/certificate
##     jobs, never guessed from the verdict text;
##   * admission-check must come from App 5795152 (identity, not re-admission);
##   * cancelled_superseded only with a same-PR same-base replacement;
##   * canonical wall = terminal-attempt job span; legacy = run timestamps;
##   * p50 over integer seconds (even n = mean of the two middle values);
##   * acceptance = full N window AND 0 unexpected internal defects AND
##     0 unclassified AND observation complete; shortfall = INCOMPLETE;
##   * initial = first N, rolling = last N by terminal run_started_at;
##   * artifact download allowlist excludes cache/build artifacts;
##   * missing artifact/log => unclassified + observation gap (fail-closed);
##   * report JSON/Markdown carry every required per-entry field.

import std/[json, strutils, unittest]

import ../../tools/ci/ci_acceptance_collect

const
  BaseSha = "1111111111111111111111111111111111111111"
  BaseSha2 = "2222222222222222222222222222222222222222"
  Head1 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  Head2 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  Head3 = "cccccccccccccccccccccccccccccccccccccccc"

# ---------------------------------------------------------------------------
# Fixture constructors
# ---------------------------------------------------------------------------

func ev(name, text: string): EvidenceText =
  EvidenceText(name: name, text: text)

func job(name, start, done: string; conclusion = "success";
         status = "completed"): ObservedJob =
  ObservedJob(name: name, status: status, conclusion: conclusion,
              startedAt: start, completedAt: done)

func failure(runId: string; n = 1; text = "";
             start = "2026-11-19T00:00:00Z";
             upd = "2026-11-19T00:01:00Z";
             jobs: seq[ObservedJob] = @[];
             jobsObserved = true): ObservedAttempt =
  result = ObservedAttempt(
    runId: runId, attemptNumber: n, status: "completed",
    conclusion: "failure", runStartedAt: start, updatedAt: upd,
    jobs: (if jobs.len > 0: jobs else: @[job("run", start, upd)]),
    jobsObserved: jobsObserved, evidenceFetched: true)
  if text.len > 0:
    result.artifacts = @[ev("admission-verdict-" & runId & ".log", text)]

func succeed(runId: string; n = 1;
             start = "2026-11-19T00:00:00Z";
             upd = "2026-11-19T00:01:00Z";
             jobs: seq[ObservedJob] = @[]): ObservedAttempt =
  ObservedAttempt(
    runId: runId, attemptNumber: n, status: "completed",
    conclusion: "success", runStartedAt: start, updatedAt: upd,
    jobs: (if jobs.len > 0: jobs else: @[job("run", start, upd)]),
    jobsObserved: true, evidenceFetched: true)

func cancelled(runId: string; n = 1;
               start = "2026-11-19T00:00:00Z";
               upd = "2026-11-19T00:01:00Z"): ObservedAttempt =
  ObservedAttempt(
    runId: runId, attemptNumber: n, status: "completed",
    conclusion: "cancelled", runStartedAt: start, updatedAt: upd,
    jobs: @[job("run", start, upd)], jobsObserved: true,
    evidenceFetched: true)

func entry(head = Head1; base = BaseSha; pr = 1;
           attempts: seq[ObservedAttempt];
           post = true; ancestry = true;
           replacementObserved = true; replacementExists = false;
           authorityObserved = true;
           admissionAppIds: seq[int] = @[RequiredAdmissionAppId];
           admissionAppHasRequired = true;
           admissionAppHasSuccess = true): ObservedEntry =
  ObservedEntry(headSha: head, baseSha: base, prNumber: pr,
                runIds: @[], attempts: attempts, postBoundary: post,
                ancestryObserved: ancestry,
                replacementObserved: replacementObserved,
                replacementExists: replacementExists,
                admissionAppIds: admissionAppIds,
                admissionAppHasRequired: admissionAppHasRequired,
                admissionAppHasSuccess: admissionAppHasSuccess,
                authorityObserved: authorityObserved)

func runRow(runId, head: string; base = BaseSha; pr = 1;
            attempts: seq[ObservedAttempt];
            observed = true): ObservedRun =
  ObservedRun(runId: runId, workflowName: "admission-gate",
              workflowPath: ".github/workflows/admission-gate-v2.yml",
              event: "merge_group", headSha: head, baseSha: base,
              prNumber: pr, runAttempt: 1,
              startedAt: "2026-11-19T00:00:00Z",
              updatedAt: "2026-11-19T00:01:00Z",
              status: "completed", conclusion: "failure",
              attempts: attempts, attemptsObserved: observed)

func reportFor(entries: seq[ObservedEntry]; window = -1;
               mode = wmInitial): AcceptanceReport =
  let w = (if window < 0: entries.len else: window)
  buildReport(entries, "Archright/Axiom", BaseSha,
              "2026-11-19T12:00:00Z", w, mode)

func timedEntry(head, start, upd: string; text = ""): ObservedEntry =
  let a = if text.len > 0: failure(head, 1, text, start, upd)
          else: succeed(head, 1, start, upd)
  entry(head, attempts = @[a])

# ---------------------------------------------------------------------------
# 1. Time / p50 / canonical wall formula
# ---------------------------------------------------------------------------

suite "timestamp and p50 formula":

  test "ISO-8601 UTC parsing accepts GitHub timestamps":
    let (v, ok) = parseIsoUtc("2026-11-19T10:21:47Z")
    check ok
    check v > 0
    # 2026-11-19T00:00:00Z - 2026-11-18T00:00:00Z == 86400
    let (a, oka) = parseIsoUtc("2026-11-18T00:00:00Z")
    let (b, okb) = parseIsoUtc("2026-11-19T00:00:00Z")
    check oka and okb
    check b - a == 86400'i64
    check parseIsoUtc("2026-11-19T00:00:00.123Z").ok
    check parseIsoUtc("2026-11-19T00:00:00+00:00").ok

  test "ISO-8601 UTC parsing rejects non-UTC and malformed input":
    check not parseIsoUtc("not-a-time").ok
    check not parseIsoUtc("2026-11-19T00:00:00+02:00").ok
    check not parseIsoUtc("2026-13-19T00:00:00Z").ok
    check not parseIsoUtc("2026-11-19 00:00:00Z").ok

  test "p50: odd n is the middle value":
    check p50Seconds(@[546, 560, 574]) == 560.0

  test "p50: even n is the mean of the two middle values (574.5 preserved)":
    check p50Seconds(@[546, 560, 589, 600]) == 574.5
    check formatNumber(p50Seconds(@[546, 560, 589, 600])) == "574.5"
    check formatNumber(p50Seconds(@[546, 560, 574])) == "560"

  test "p50: empty input has no value (0.0)":
    check p50Seconds(@[]) == 0.0

  test "latencyStats carries n, p50, mean, min, max":
    let s = latencyStats(@[10, 30, 20])
    check s.n == 3
    check s.p50 == 20.0
    check s.mean == 20.0
    check s.minSeconds == 10
    check s.maxSeconds == 30

  test "canonical wall is the terminal attempt's job span, not updated_at":
    let e = entry(attempts = @[
      succeed("1", 1, "2026-11-19T00:00:00Z", "2026-11-19T00:01:00Z"),
      succeed("1", 2, "2026-11-19T00:05:00Z", "2026-11-19T00:20:00Z",
              jobs = @[job("start-up", "2026-11-19T00:05:00Z",
                           "2026-11-19T00:06:00Z"),
                       job("verdict", "2026-11-19T00:13:00Z",
                           "2026-11-19T00:14:06Z")])])
    let w = entryCanonicalWallSeconds(e)
    check w.observed
    check w.seconds == 546
    # Legacy run timestamps are a different clock and are labeled as such.
    let l = entryLegacyWallSeconds(e)
    check l.observed
    check l.seconds == 900

  test "terminal attempt is latest by run_started_at before attempt number":
    let e = entry(attempts = @[
      succeed("1", 9, "2026-11-19T00:00:00Z", "2026-11-19T00:01:00Z"),
      succeed("2", 1, "2026-11-19T00:05:00Z", "2026-11-19T00:06:00Z")])
    check terminalAttempt(e).runId == "2"
    check entryCanonicalWallSeconds(e).seconds == 60

  test "no observed jobs leaves the canonical wall unobservable":
    var a = succeed("1", 1, "2026-11-19T00:00:00Z", "2026-11-19T00:01:00Z")
    a.jobsObserved = false
    a.jobsError = "jobs endpoint failed"
    let e = entry(attempts = @[a])
    let w = entryCanonicalWallSeconds(e)
    check not w.observed
    check w.reason == "jobs endpoint failed"
    # Legacy timestamps remain independently observable.
    check entryLegacyWallSeconds(e).seconds == 60

  test "job without completed_at does not invent a span":
    var a = succeed("1")
    a.jobs = @[ObservedJob(name: "running", status: "in_progress",
                           conclusion: "", startedAt: "2026-11-19T00:00:00Z",
                           completedAt: "")]
    let e = entry(attempts = @[a])
    let w = entryCanonicalWallSeconds(e)
    check not w.observed
    check w.reason.len > 0

  test "legacy wall unobservable when the terminal timestamp is invalid":
    let e = entry(attempts = @[
      succeed("1", 1, "2026-11-19T00:00:00Z", "not-a-time",
              jobs = @[job("run", "2026-11-19T00:00:00Z",
                           "2026-11-19T00:01:00Z")])])
    check entryCanonicalWallSeconds(e).seconds == 60
    check not entryLegacyWallSeconds(e).observed

# ---------------------------------------------------------------------------
# 2. Grouping / attempts / boundary filter / window mode
# ---------------------------------------------------------------------------

suite "entry grouping and boundary filter":

  test "one entry per unique head_sha; re-runs are attempts":
    let rows = @[
      runRow("100", Head1, attempts = @[failure("100", 1)]),
      runRow("100", Head1, attempts = @[failure("100", 1), succeed("100", 2)]),
      runRow("200", Head1, attempts = @[succeed("200", 1)]),
      runRow("300", Head2, attempts = @[succeed("300", 1)])]
    let entries = buildEntries(rows)
    check entries.len == 2
    var h1: ObservedEntry
    for e in entries:
      if e.headSha == Head1:
        h1 = e
    check h1.runIds == @["100", "200"]
    # §2.2: attempts are the union over the entry's runs; the duplicate row for
    # run 100 is de-duplicated, and both of its attempts are kept.
    check h1.attempts.len == 3
    var ids: seq[string]
    for a in h1.attempts:
      ids.add a.runId & ":" & $a.attemptNumber
    check "100:1" in ids
    check "100:2" in ids
    check "200:1" in ids
    check terminalAttempt(h1).runId == "100"
    check terminalAttempt(h1).attemptNumber == 2

  test "attempt list unavailable is a gap, never a hidden success":
    let rows = @[
      runRow("100", Head1, attempts = @[],
             observed = false)]
    let entries = buildEntries(rows)
    check entries.len == 1
    let ec = classifyEntry(entries[0])
    check ec.kind == ckUnclassified
    check ec.gap

  test "pre-boundary entries are excluded; unknown ancestry stays as a gap":
    let entries = @[
      entry(Head1, attempts = @[succeed("1")], post = true, ancestry = true),
      entry(Head2, attempts = @[succeed("2")], post = false, ancestry = true),
      entry(Head3, attempts = @[succeed("3")], post = false, ancestry = false)]
    let selected = selectWindow(entries, 10)
    check selected.len == 2
    var heads: seq[string]
    for e in selected:
      heads.add e.headSha
    check Head1 in heads
    check Head3 in heads
    check Head2 notin heads

  test "rolling mode takes the last N by terminal run_started_at":
    let entries = @[
      entry(Head1, attempts = @[succeed("1", 1,
        "2026-11-19T00:00:00Z", "2026-11-19T00:01:00Z")]),
      entry(Head2, attempts = @[succeed("2", 1,
        "2026-11-19T01:00:00Z", "2026-11-19T01:01:00Z")]),
      entry(Head3, attempts = @[succeed("3", 1,
        "2026-11-19T02:00:00Z", "2026-11-19T02:01:00Z")])]
    let selected = selectWindow(entries, 2, wmRolling)
    check selected.len == 2
    check selected[0].headSha == Head2
    check selected[1].headSha == Head3

  test "initial mode takes the first N by terminal run_started_at":
    let entries = @[
      entry(Head1, attempts = @[succeed("1", 1,
        "2026-11-19T00:00:00Z", "2026-11-19T00:01:00Z")]),
      entry(Head2, attempts = @[succeed("2", 1,
        "2026-11-19T01:00:00Z", "2026-11-19T01:01:00Z")]),
      entry(Head3, attempts = @[succeed("3", 1,
        "2026-11-19T02:00:00Z", "2026-11-19T02:01:00Z")])]
    let selected = selectWindow(entries, 2, wmInitial)
    check selected.len == 2
    check selected[0].headSha == Head1
    check selected[1].headSha == Head2

  test "base/pr derived from the canonical queue head_branch":
    let sha = "0123456789abcdef0123456789abcdef01234567"
    let branch = "gh-readonly-queue/main/pr-42-" & sha
    check baseFromHeadBranch(branch) == sha
    check prFromHeadBranch(branch) == 42
    check isHex40(sha)
    check not isHex40("abc")

# ---------------------------------------------------------------------------
# 3. Classification: legitimate policy / internal / unclassified
# ---------------------------------------------------------------------------

suite "classification hierarchy":

  test "TRUST_SURFACE_MODIFIED and ROT_ALLOWLIST are legitimate_policy":
    for text in ["reasons=trust_surface:mismatch; verdict.reasonCode=TRUST_SURFACE_MODIFIED",
                 "verdict NOT-ADMIT reasonCode=ROT_ALLOWLIST"]:
      let ac = classifyAttempt(failure("1", text = text), false, true)
      check ac.kind == ckLegitimatePolicy
      check not ac.gap

  test "explicit INVALID_INPUT subject-pin/document refusal is legitimate":
    let text = "[ERROR] INVALID_INPUT: SUBJECT_PIN_REJECTED — subject pin does not match"
    let ac = classifyAttempt(failure("1", text = text), false, true)
    check ac.kind == ckLegitimatePolicy

  test "INVALID_INPUT with identity divergence stays internal (identity wins)":
    let text = "INVALID_INPUT\nPLAN_COMPONENT_MISMATCH: envSnapshot — plan=aaaa attest=bbbb"
    let ac = classifyAttempt(failure("1", text = text), false, true)
    check ac.kind == ckInternalDefect
    check ac.subtype == dsIdentityDivergence

  test "judgment_cas decision-key divergence is identity_divergence":
    let text = "judgment_cas: decision file key b9e1bb0c8321 != freshly re-derived " &
               "ba05d5cfe9fe — the plan and the attest saw different closures"
    let ac = classifyAttempt(failure("1", text = text), false, true)
    check ac.kind == ckInternalDefect
    check ac.subtype == dsIdentityDivergence

  test "judgment_cas phrase alone is not identity divergence":
    let text = "judgment_cas: decision file key b9e1bb0c8321 was observed"
    let ac = classifyAttempt(failure("1", text = text), false, true)
    check ac.kind == ckUnclassified

  test "run_head_mismatch is a pre-registered identity signature":
    let text = "merge_group verdict: NOT-ADMIT reasons=run_head_mismatch " &
               "run head e4fafea != PR head e9ee0f3"
    let ac = classifyAttempt(failure("1", text = text), false, true)
    check ac.kind == ckInternalDefect
    check ac.subtype == dsIdentityDivergence

  test "NO_CERT with all mint jobs successful is certificate_present_but_unbound":
    let jobs = @[job("mint-prepare / prepare", "2026-11-19T00:00:00Z",
                     "2026-11-19T00:01:00Z"),
                 job("mint-publish / publish", "2026-11-19T00:01:00Z",
                     "2026-11-19T00:02:00Z")]
    let ac = classifyAttempt(failure("1", text = "reasonCode=NO_CERT",
                                     jobs = jobs), false, true)
    check ac.kind == ckInternalDefect
    check ac.subtype == dsIdentityDivergence
    check ac.subtypeDetail == "certificate_present_but_unbound"

  test "SUBJECT_MISMATCH with all mint jobs successful is the same defect":
    let ac = classifyAttempt(failure("1", text = "reasonCode=SUBJECT_MISMATCH",
                                     jobs = @[job("subject-certificate / mint",
                                                 "2026-11-19T00:00:00Z",
                                                 "2026-11-19T00:01:00Z")]),
                             false, true)
    check ac.kind == ckInternalDefect
    check ac.subtype == dsIdentityDivergence
    check ac.subtypeDetail == "certificate_present_but_unbound"

  test "NO_CERT with a failed mint job is unclassified, never guessed":
    let ac = classifyAttempt(failure("1", text = "reasonCode=NO_CERT",
                                     jobs = @[job("mint-publish / publish",
                                                 "2026-11-19T00:00:00Z",
                                                 "2026-11-19T00:01:00Z",
                                                 conclusion = "failure")]),
                             false, true)
    check ac.kind == ckUnclassified
    check ac.subtypeDetail == "mint_failed_unattributed"

  test "NO_CERT with no observable mint job is unclassified":
    let ac = classifyAttempt(failure("1", text = "reasonCode=NO_CERT"),
                             false, true)
    check ac.kind == ckUnclassified
    check ac.subtypeDetail == "mint_failed_unattributed"

  test "NO_CERT with unobservable jobs is unclassified with a gap":
    let ac = classifyAttempt(failure("1", text = "reasonCode=NO_CERT",
                                     jobsObserved = false), false, true)
    check ac.kind == ckUnclassified
    check ac.gap
    check ac.subtypeDetail == "mint_failed_unattributed"

  test "false clProved / missing dependency supply is soundness_failure":
    for text in ["SOUNDNESS_FAILURE: false clProved on unit x",
                 "missing dependency supply: json_serialization"]:
      let ac = classifyAttempt(failure("1", text = text), false, true)
      check ac.kind == ckInternalDefect
      check ac.subtype == dsSoundnessFailure

  test "empty canonical_digest is failure_projection":
    for text in ["canonical_digest=\n", "canonical_digest: \"\"\n",
                 "{\"canonicalRunDigest\":\"\"}"]:
      let ac = classifyAttempt(failure("1", text = text), false, true)
      check ac.kind == ckInternalDefect
      check ac.subtype == dsFailureProjection

  test "INTERNAL_ERROR carrying a refusal marker is failure_projection":
    let text = "[ERROR] INTERNAL_ERROR: document invalid — refusal before prepare"
    let ac = classifyAttempt(failure("1", text = text), false, true)
    check ac.kind == ckInternalDefect
    check ac.subtype == dsFailureProjection

  test "unknown failure evidence is unclassified without a gap":
    let ac = classifyAttempt(failure("1", text = "something unexpected broke"),
                             false, true)
    check ac.kind == ckUnclassified
    check not ac.gap

  test "missing artifact AND log is unclassified with a gap":
    let ac = classifyAttempt(failure("1", text = ""), false, true)
    check ac.kind == ckUnclassified
    check ac.gap
    check ac.gapReason.len > 0

  test "subtype precedence: soundness > identity > projection in one attempt":
    let both = "SOUNDNESS_FAILURE false clProved\nPLAN_COMPONENT_MISMATCH: x"
    check classifyAttempt(failure("1", text = both), false, true).subtype ==
      dsSoundnessFailure
    let identityAndProjection = "PLAN_COMPONENT_MISMATCH: x\ncanonical_digest="
    check classifyAttempt(failure("1", text = identityAndProjection), false, true).subtype ==
      dsIdentityDivergence

  test "subtype precedence across attempts keeps the more severe incident":
    let e = entry(attempts = @[
      failure("1", 1, "canonical_digest="),
      failure("1", 2, "PLAN_COMPONENT_MISMATCH: envSnapshot — plan=a attest=b")])
    let ec = classifyEntry(e)
    check ec.kind == ckInternalDefect
    check ec.subtype == dsIdentityDivergence

  test "success does not erase an earlier incident (worst-of)":
    let e = entry(attempts = @[
      failure("1", 1, "judgment_cas: decision file key a != freshly re-derived b"),
      succeed("1", 2)])
    let ec = classifyEntry(e)
    check ec.kind == ckInternalDefect
    check ec.subtype == dsIdentityDivergence

  test "legitimate_policy is not erased by a later success":
    let e = entry(attempts = @[
      failure("1", 1, "TRUST_SURFACE_MODIFIED"),
      succeed("1", 2)])
    check classifyEntry(e).kind == ckLegitimatePolicy

  test "unclassified outranks legitimate_policy":
    let e = entry(attempts = @[
      failure("1", 1, "ROT_ALLOWLIST"),
      failure("1", 2, "unknown failure")])
    check classifyEntry(e).kind == ckUnclassified

# ---------------------------------------------------------------------------
# 4. Authority: admission-check must come from App 5795152
# ---------------------------------------------------------------------------

suite "admission-check authority":

  func checkRuns(items: seq[tuple[name: string, appId: int,
                                   conclusion: string]]): JsonNode =
    result = newJArray()
    for it in items:
      result.add %*{"name": it.name,
                    "app": {"id": it.appId},
                    "conclusion": it.conclusion}

  test "App 5795152 success satisfies the authority requirement":
    let s = admissionCheckSummary(checkRuns(@[
      ("admission-check", RequiredAdmissionAppId, "success")]))
    check s.appIds == @[RequiredAdmissionAppId]
    check s.requiredPresent
    check s.requiredSuccess

  test "a same-name check from Actions only is not authority":
    let s = admissionCheckSummary(checkRuns(@[
      ("admission-check", ActionsAppId, "success")]))
    check s.appIds == @[ActionsAppId]
    check not s.requiredPresent
    check not s.requiredSuccess

  test "both apps: the App wins and both ids are recorded":
    let s = admissionCheckSummary(checkRuns(@[
      ("admission-check", ActionsAppId, "success"),
      ("admission-check", RequiredAdmissionAppId, "success")]))
    check s.appIds.len == 2
    check ActionsAppId in s.appIds
    check RequiredAdmissionAppId in s.appIds
    check s.requiredPresent
    check s.requiredSuccess

  test "App check with a non-success conclusion is present but not success":
    let s = admissionCheckSummary(checkRuns(@[
      ("admission-check", RequiredAdmissionAppId, "failure")]))
    check s.requiredPresent
    check not s.requiredSuccess

  test "unrelated check names are ignored":
    let s = admissionCheckSummary(checkRuns(@[
      ("admission_check", RequiredAdmissionAppId, "success"),
      ("admission-check-extra", RequiredAdmissionAppId, "success")]))
    check s.appIds.len == 0
    check not s.requiredPresent

  test "entry with only another App is authority_substitution":
    let e = entry(attempts = @[succeed("1")],
                  admissionAppIds = @[ActionsAppId],
                  admissionAppHasRequired = false)
    let ec = classifyEntry(e)
    check ec.kind == ckInternalDefect
    check ec.subtype == dsAuthoritySubstitution

  test "entry with both Apps classifies on the attempt, App authority present":
    let e = entry(attempts = @[succeed("1")],
                  admissionAppIds = @[ActionsAppId, RequiredAdmissionAppId],
                  admissionAppHasRequired = true)
    check classifyEntry(e).kind == ckSuccess

  test "entry with unobservable check-runs is unclassified with a gap":
    let e = entry(attempts = @[succeed("1")], authorityObserved = false)
    let ec = classifyEntry(e)
    check ec.kind == ckUnclassified
    check ec.gap

  test "authority_substitution outranks identity in the same entry":
    let e = entry(attempts = @[failure("1",
                  text = "PLAN_COMPONENT_MISMATCH: x")],
                  admissionAppIds = @[ActionsAppId],
                  admissionAppHasRequired = false)
    check classifyEntry(e).subtype == dsAuthoritySubstitution

# ---------------------------------------------------------------------------
# 5. Cancelled handling
# ---------------------------------------------------------------------------

suite "cancelled_superseded":

  test "cancelled with a same-PR same-base replacement is superseded":
    let e = entry(attempts = @[cancelled("1")],
                  replacementObserved = true, replacementExists = true)
    check classifyEntry(e).kind == ckCancelledSuperseded
    check not classifyEntry(e).gap

  test "cancelled without a replacement is unclassified, not failed-as-gap":
    let e = entry(attempts = @[cancelled("1")],
                  replacementObserved = true, replacementExists = false)
    let ec = classifyEntry(e)
    check ec.kind == ckUnclassified
    check not ec.gap

  test "cancelled with unobservable replacement context is a gap":
    let e = entry(attempts = @[cancelled("1")],
                  replacementObserved = false, replacementExists = false)
    let ec = classifyEntry(e)
    check ec.kind == ckUnclassified
    check ec.gap

  test "cancelled superseded + success collapses to success":
    let e = entry(attempts = @[cancelled("1"), succeed("2")],
                  replacementObserved = true, replacementExists = true)
    check classifyEntry(e).kind == ckSuccess

# ---------------------------------------------------------------------------
# 6. Acceptance predicate and window
# ---------------------------------------------------------------------------

suite "acceptance predicate":

  test "all success is accepted":
    let r = reportFor(@[entry(attempts = @[succeed("1")])])
    check r.acceptance.observedEntries == 1
    check r.acceptance.predicateHolds
    check r.acceptance.observationComplete
    check r.acceptance.accepted
    check r.acceptance.status == asAccepted
    check r.acceptance.mode == wmInitial
    check r.acceptance.shortfall == 0

  test "legitimate_policy is reported but never fails acceptance":
    let r = reportFor(@[
      entry(Head1, attempts = @[succeed("1")]),
      entry(Head2, attempts = @[failure("2", text = "ROT_ALLOWLIST")])])
    check r.acceptance.success == 1
    check r.acceptance.legitimatePolicy == 1
    check r.acceptance.unexpectedInternalDefects == 0
    check r.acceptance.unclassified == 0
    check r.acceptance.accepted

  test "one internal defect fails acceptance and counts its subtype":
    let r = reportFor(@[
      entry(Head1, attempts = @[succeed("1")]),
      entry(Head2, attempts = @[failure("2",
        text = "PLAN_COMPONENT_MISMATCH: envSnapshot — plan=a attest=b")])])
    check r.acceptance.internalDefect == 1
    check r.acceptance.identityDivergence == 1
    check r.acceptance.unexpectedInternalDefects == 1
    check not r.acceptance.predicateHolds
    check not r.acceptance.accepted
    check r.acceptance.status == asFailed

  test "one unclassified outcome fails acceptance":
    let r = reportFor(@[
      entry(Head1, attempts = @[succeed("1")]),
      entry(Head2, attempts = @[failure("2", text = "unknown failure")])])
    check r.acceptance.unclassified == 1
    check not r.acceptance.accepted
    check r.acceptance.status == asFailed

  test "authority_substitution is counted and fails acceptance":
    let r = reportFor(@[
      entry(Head1, attempts = @[succeed("1")]),
      entry(Head2, attempts = @[succeed("2")],
            admissionAppIds = @[ActionsAppId],
            admissionAppHasRequired = false)])
    check r.acceptance.authoritySubstitution == 1
    check r.acceptance.internalDefect == 1
    check not r.acceptance.accepted
    check r.entries[1].subtype == dsAuthoritySubstitution

  test "authority unobservable is unclassified and fails acceptance":
    let r = reportFor(@[
      entry(Head1, attempts = @[succeed("1")], authorityObserved = false)])
    check r.acceptance.unclassified == 1
    check not r.acceptance.observationComplete
    check not r.acceptance.accepted
    check r.acceptance.status == asIncomplete

  test "an observation gap fails acceptance even when a defect is present":
    let r = reportFor(@[
      entry(Head1, attempts = @[failure("1",
        text = "PLAN_COMPONENT_MISMATCH: x")]),
      entry(Head2, attempts = @[succeed("2")], ancestry = false)])
    check r.acceptance.internalDefect == 1
    check not r.acceptance.observationComplete
    check not r.acceptance.accepted
    check r.acceptance.gaps.len > 0

  test "rolling mode excludes older entries from the predicate":
    let entries = @[
      timedEntry(Head1, "2026-11-19T00:00:00Z", "2026-11-19T00:01:00Z",
                 text = "PLAN_COMPONENT_MISMATCH: x"),
      timedEntry(Head2, "2026-11-19T01:00:00Z", "2026-11-19T01:01:00Z"),
      timedEntry(Head3, "2026-11-19T02:00:00Z", "2026-11-19T02:01:00Z")]
    let r = reportFor(entries, window = 2, mode = wmRolling)
    check r.acceptance.mode == wmRolling
    check r.acceptance.observedEntries == 2
    check r.acceptance.internalDefect == 0
    check r.acceptance.accepted

  test "initial mode evaluates the first N entries":
    let entries = @[
      timedEntry(Head1, "2026-11-19T00:00:00Z", "2026-11-19T00:01:00Z",
                 text = "PLAN_COMPONENT_MISMATCH: x"),
      timedEntry(Head2, "2026-11-19T01:00:00Z", "2026-11-19T01:01:00Z"),
      timedEntry(Head3, "2026-11-19T02:00:00Z", "2026-11-19T02:01:00Z")]
    let r = reportFor(entries, window = 2, mode = wmInitial)
    check r.acceptance.mode == wmInitial
    check r.acceptance.internalDefect == 1
    check not r.acceptance.accepted

  test "fewer than N entries is INCOMPLETE with a shortfall, never accepted":
    let entries = @[
      timedEntry(Head1, "2026-11-19T00:00:00Z", "2026-11-19T00:01:00Z"),
      timedEntry(Head2, "2026-11-19T01:00:00Z", "2026-11-19T01:01:00Z"),
      timedEntry(Head3, "2026-11-19T02:00:00Z", "2026-11-19T02:01:00Z")]
    let r = reportFor(entries, window = 5)
    check r.acceptance.observedEntries == 3
    check r.acceptance.shortfall == 2
    check not r.acceptance.predicateHolds
    check not r.acceptance.accepted
    check r.acceptance.status == asIncomplete

  test "empty window is an observation gap, never a vacuous accept":
    let r = reportFor(@[], window = 3)
    check r.acceptance.observedEntries == 0
    check r.acceptance.shortfall == 3
    check not r.acceptance.observationComplete
    check not r.acceptance.accepted
    check r.acceptance.status == asIncomplete

  test "pre-boundary entries are not counted":
    let r = reportFor(@[
      entry(Head1, attempts = @[succeed("1")], post = false, ancestry = true)],
      window = 1)
    check r.acceptance.observedEntries == 0
    check r.acceptance.shortfall == 1
    check r.excludedBeforeBoundary == 1
    check not r.acceptance.accepted
    check r.acceptance.status == asIncomplete

# ---------------------------------------------------------------------------
# 7. Report rendering
# ---------------------------------------------------------------------------

suite "report rendering":

  test "JSON carries every required per-entry field":
    let e = entry(attempts = @[failure("77", 3,
      text = "judgment_cas: decision file key a != freshly re-derived b")])
    let r = reportFor(@[e])
    let node = reportJson(r)
    check node{"schema_version"}.getStr == SchemaVersion
    check node{"contract"}.getStr == ContractPath
    let entries = node{"entries"}
    check entries.len == 1
    let item = entries[0]
    for key in ["run_id", "run_ids", "attempt_ids", "head_sha", "base_sha",
                "conclusion", "classification", "subtype", "subtype_detail",
                "evidence", "wall_seconds", "wall_observed",
                "legacy_wall_seconds", "legacy_wall_observed",
                "admission_app_ids", "gap", "gap_reason", "post_boundary"]:
      check item.hasKey(key)
    check item{"run_id"}.getStr == "77"
    check item{"attempt_ids"}[0].getStr == "77:3"
    check item{"classification"}.getStr == "internal_defect"
    check item{"subtype"}.getStr == "identity_divergence"
    check item{"evidence"}.getStr.contains("artifact:")
    check item{"wall_seconds"}.getInt == 60
    check item{"legacy_wall_seconds"}.getInt == 60
    check item{"admission_app_ids"}[0].getInt == RequiredAdmissionAppId
    check node{"counts"}{"internal_defect"}.getInt == 1
    check node{"counts"}{"internal_defect_subtypes"}{"identity_divergence"}.getInt == 1
    check node{"counts"}{"internal_defect_subtypes"}{"authority_substitution"}.getInt == 0
    check node{"acceptance"}{"mode"}.getStr == "initial"
    check node{"acceptance"}{"status"}.getStr == "FAILED"
    check node{"acceptance"}{"shortfall"}.getInt == 0
    check node{"acceptance"}{"unexpected_internal_defects"}.getInt == 1
    check node{"latency"}.hasKey("formula")
    check node{"latency"}.hasKey("legacy_formula")
    check node{"latency"}{"legacy_n"}.getInt == 1

  test "JSON records unobserved legacy latency as null":
    var a = succeed("1")
    a.updatedAt = "not-a-time"
    let r = reportFor(@[entry(attempts = @[a])])
    let item = reportJson(r){"entries"}[0]
    check not item{"legacy_wall_observed"}.getBool
    check item{"legacy_wall_seconds"}.kind == JNull

  test "JSON records certificate detail and both App ids":
    let jobs = @[job("mint-publish / publish", "2026-11-19T00:00:00Z",
                     "2026-11-19T00:01:00Z")]
    let e = entry(attempts = @[failure("9", text = "reasonCode=NO_CERT",
                                       jobs = jobs)],
                  admissionAppIds = @[ActionsAppId, RequiredAdmissionAppId])
    let item = reportJson(reportFor(@[e])){"entries"}[0]
    check item{"subtype_detail"}.getStr == "certificate_present_but_unbound"
    check item{"admission_app_ids"}.len == 2

  test "Markdown reports mode, status, subtypes, latency, and gaps":
    let r = reportFor(@[
      entry(Head1, attempts = @[succeed("1")]),
      entry(Head2, attempts = @[failure("2", text = "ROT_ALLOWLIST")])])
    let md = renderMarkdown(r)
    check md.contains("CI Acceptance Contract v2")
    check md.contains("status: **ACCEPTED**")
    check md.contains("legitimate_policy")
    check md.contains("identity_divergence")
    check md.contains("authority_substitution")
    check md.contains("p50=")
    check md.contains("legacy")
    check md.contains("## Gaps")

  test "Markdown lists the certificate subtype detail":
    let jobs = @[job("mint-publish / publish", "2026-11-19T00:00:00Z",
                     "2026-11-19T00:01:00Z")]
    let md = renderMarkdown(reportFor(@[
      entry(attempts = @[failure("9", text = "reasonCode=NO_CERT",
                                 jobs = jobs)])]))
    check md.contains("certificate_present_but_unbound")
    check md.contains("status: **FAILED**")

# ---------------------------------------------------------------------------
# 8. Artifact allowlist (§4.6)
# ---------------------------------------------------------------------------

suite "artifact allowlist":

  test "only the five evidence prefixes and two exact names are selected":
    let names = @["admission-verdict-123", "admission-check-9",
                  "judgment-record-1", "evidence-record-2",
                  "subject-certificate-3", "derived-closure",
                  "ci-select-decision",
                  "nimcache-pool", "base-artifacts", "bootstrap-artifacts",
                  "go-build-cache", "tested-tree-digest", "unrelated"]
    let selected = selectArtifactNames(names)
    check selected == @["admission-verdict-123", "admission-check-9",
                        "judgment-record-1", "evidence-record-2",
                        "subject-certificate-3", "derived-closure",
                        "ci-select-decision"]
    for denied in ["nimcache-pool", "base-artifacts", "bootstrap-artifacts",
                   "go-build-cache", "tested-tree-digest", "unrelated"]:
      check denied notin selected

  test "cache/build names are denied even under an allowed prefix":
    check not allowedArtifactName("admission-check-nimcache")
    check not allowedArtifactName("go-admission-verdict-x")
    check not allowedArtifactName("bootstrap-artifacts")
    check not allowedArtifactName("admission-check-base-artifacts")
    check deniedArtifactName("subject-certificate-bootstrap-artifacts")

  test "selection is de-duplicated and order-preserving":
    check selectArtifactNames(@["derived-closure", "derived-closure",
                                "ci-select-decision"]) ==
      @["derived-closure", "ci-select-decision"]

  test "empty names and unknown shapes are not selected":
    check not allowedArtifactName("")
    check selectArtifactNames(@[]).len == 0

# ---------------------------------------------------------------------------
# 9. --recompute-baseline (pure core)
# ---------------------------------------------------------------------------

suite "recompute-baseline":

  func jobJson(start, done: string): JsonNode =
    %*{"name": "j", "status": "completed", "conclusion": "success",
       "started_at": start, "completed_at": done}

  func runListRow(id, start, upd: string; jobs = newJArray();
                  attempts = newJArray()): JsonNode =
    %*{"id": id, "run_started_at": start, "updated_at": upd,
       "jobs": jobs, "attempts": attempts}

  test "run list uses the terminal attempt's jobs and the same p50 formula":
    let attempts = newJArray()
    attempts.add %*{"run_attempt": 1,
                    "run_started_at": "2026-11-19T00:00:00Z",
                    "updated_at": "2026-11-19T00:10:00Z",
                    "jobs": [jobJson("2026-11-19T00:00:00Z",
                                     "2026-11-19T00:10:00Z")]}
    attempts.add %*{"run_attempt": 2,
                    "run_started_at": "2026-11-19T00:20:00Z",
                    "updated_at": "2026-11-19T00:20:50Z",
                    "jobs": [jobJson("2026-11-19T00:20:00Z",
                                     "2026-11-19T00:20:50Z")]}
    let root = %*{"runs": [runListRow("1", "2026-11-19T00:00:00Z",
                                      "2026-11-19T00:20:50Z", attempts = attempts),
                            runListRow("2", "2026-11-19T01:00:00Z",
                                      "2026-11-19T01:00:20Z",
                                      jobs = %*[jobJson("2026-11-19T01:00:00Z",
                                                      "2026-11-19T01:00:20Z")]),
                            runListRow("3", "2026-11-19T02:00:00Z",
                                      "2026-11-19T02:00:41Z",
                                      jobs = %*[jobJson("2026-11-19T02:00:00Z",
                                                      "2026-11-19T02:00:41Z")])]}
    let durations = durationsFromRunList(root)
    check durations.len == 3
    check durations[0].seconds == 50   # terminal attempt 2's jobs, not attempt 1's
    check durations[0].legacySeconds == 50
    check durations[1].seconds == 20
    check durations[2].seconds == 41
    check p50Seconds(@[50, 20, 41]) == 41.0  # sorted 20,41,50

  test "canonical job span differs from legacy run timestamps":
    let root = %*[runListRow("1", "2026-11-19T00:00:00Z",
                             "2026-11-19T00:10:00Z",
                             jobs = %*[jobJson("2026-11-19T00:00:00Z",
                                             "2026-11-19T00:01:00Z")])]
    let d = durationsFromRunList(root)[0]
    check d.seconds == 60
    check d.legacySeconds == 600

  test "top-level array is accepted":
    let root = %*[runListRow("1", "2026-11-19T00:00:00Z",
                             "2026-11-19T00:09:06Z",
                             jobs = %*[jobJson("2026-11-19T00:00:00Z",
                                             "2026-11-19T00:09:06Z")])]
    let durations = durationsFromRunList(root)
    check durations.len == 1
    check durations[0].seconds == 546

  test "row without jobs is excluded but legacy stays observed":
    let root = %*[runListRow("1", "2026-11-19T00:00:00Z",
                             "2026-11-19T00:09:06Z",
                             jobs = %*[jobJson("2026-11-19T00:00:00Z",
                                             "2026-11-19T00:09:06Z")]),
                  runListRow("2", "2026-11-19T01:00:00Z",
                             "2026-11-19T01:01:00Z")]
    let durations = durationsFromRunList(root)
    check durations.len == 2
    check durations[0].observed
    check not durations[1].observed
    check durations[1].legacyObserved
    check durations[1].legacySeconds == 60
    check not baselineComplete(durations)
    let node = baselineJson(durations)
    check node{"n"}.getInt == 1
    check node{"excluded"}.getInt == 1
    check node{"p50_display"}.getStr == "546"
    check node{"legacy_n"}.getInt == 2
    check node{"gaps"}.len == 1
    check node{"runs"}[1]{"seconds"}.kind == JNull
    check node{"runs"}[1]{"legacy_seconds"}.getInt == 60

  test "job missing completed_at does not invent a wall":
    let unfinished = newJArray()
    unfinished.add %*{"name": "j", "status": "in_progress",
                      "started_at": "2026-11-19T00:00:00Z",
                      "completed_at": ""}
    let root = %*[runListRow("1", "2026-11-19T00:00:00Z",
                             "2026-11-19T00:09:06Z", jobs = unfinished)]
    let d = durationsFromRunList(root)[0]
    check not d.observed
    check d.gapReason.len > 0

  test "baseline JSON carries canonical mean/min/max and legacy stats":
    let root = %*[
      runListRow("1", "2026-11-19T00:00:00Z", "2026-11-19T00:00:10Z",
                 jobs = %*[jobJson("2026-11-19T00:00:00Z",
                                 "2026-11-19T00:00:10Z")]),
      runListRow("2", "2026-11-19T00:00:00Z", "2026-11-19T00:00:20Z",
                 jobs = %*[jobJson("2026-11-19T00:00:00Z",
                                 "2026-11-19T00:00:20Z")]),
      runListRow("3", "2026-11-19T00:00:00Z", "2026-11-19T00:00:30Z",
                 jobs = %*[jobJson("2026-11-19T00:00:00Z",
                                 "2026-11-19T00:00:30Z")])]
    let node = baselineJson(durationsFromRunList(root))
    check node{"n"}.getInt == 3
    check node{"p50_seconds"}.getFloat == 20.0
    check node{"mean_seconds"}.getFloat == 20.0
    check node{"min_seconds"}.getInt == 10
    check node{"max_seconds"}.getInt == 30
    check node{"legacy_n"}.getInt == 3
    check node{"legacy_p50_seconds"}.getFloat == 20.0
    check node{"legacy_mean_seconds"}.getFloat == 20.0
    check node{"runs"}[0]{"legacy_seconds"}.getInt == 10

  test "empty run list is not a complete baseline":
    check not baselineComplete(@[])
    let node = baselineJson(@[])
    check node{"n"}.getInt == 0

# ---------------------------------------------------------------------------
# 10. Fail-closed invariants
# ---------------------------------------------------------------------------

suite "fail-closed invariants":

  test "success with an unobservable attempt list is not success":
    var a = succeed("1")
    a.attemptListGap = true
    let ac = classifyAttempt(a, false, true)
    check ac.kind == ckUnclassified
    check ac.gap

  test "attempt not terminal is unclassified with a gap":
    var a = succeed("1")
    a.status = "in_progress"
    let ac = classifyAttempt(a, false, true)
    check ac.kind == ckUnclassified
    check ac.gap

  test "classification never invents a class from absent evidence":
    let ac = classifyAttempt(failure("1", text = ""), false, true)
    check ac.kind == ckUnclassified
    check ac.gap

  test "entry without attempts is unclassified with a gap":
    let e = entry(attempts = @[])
    let ec = classifyEntry(e)
    check ec.kind == ckUnclassified
    check ec.gap