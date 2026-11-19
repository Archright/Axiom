## test_ci_acceptance_collect.nim — fixtures for tools/ci/ci_acceptance_collect.nim.
##
## NO network, NO subprocess, NO git: the collector's pure core is imported
## directly and every case is a synthetic run/attempt/evidence fixture. The
## cases pin the contract (docs/spec/ci_acceptance_contract.md):
##
##   * one entry per unique merge_group head_sha; re-runs are attempts;
##   * boundary filter (pre-boundary excluded, unknown ancestry stays as a gap);
##   * worst-of classification across attempts; retries never erase incidents;
##   * internal subtype precedence soundness > identity > projection;
##   * cancelled_superseded only with a same-PR same-base replacement;
##   * p50 over integer seconds (even n = mean of the two middle values);
##   * acceptance = 0 unexpected internal defects AND 0 unclassified;
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

func failure(runId: string; n = 1; text = "";
             start = "2026-11-19T00:00:00Z";
             upd = "2026-11-19T00:01:00Z"): ObservedAttempt =
  result = ObservedAttempt(
    runId: runId, attemptNumber: n, status: "completed",
    conclusion: "failure", runStartedAt: start, updatedAt: upd,
    evidenceFetched: true)
  if text.len > 0:
    result.artifacts = @[ev("admission-verdict-" & runId & ".log", text)]

func succeed(runId: string; n = 1;
             start = "2026-11-19T00:00:00Z";
             upd = "2026-11-19T00:01:00Z"): ObservedAttempt =
  ObservedAttempt(
    runId: runId, attemptNumber: n, status: "completed",
    conclusion: "success", runStartedAt: start, updatedAt: upd,
    evidenceFetched: true)

func cancelled(runId: string; n = 1;
               start = "2026-11-19T00:00:00Z";
               upd = "2026-11-19T00:01:00Z"): ObservedAttempt =
  ObservedAttempt(
    runId: runId, attemptNumber: n, status: "completed",
    conclusion: "cancelled", runStartedAt: start, updatedAt: upd,
    evidenceFetched: true)

func entry(head = Head1; base = BaseSha; pr = 1;
           attempts: seq[ObservedAttempt];
           post = true; ancestry = true;
           replacementObserved = true; replacementExists = false): ObservedEntry =
  ObservedEntry(headSha: head, baseSha: base, prNumber: pr,
                runIds: @[], attempts: attempts, postBoundary: post,
                ancestryObserved: ancestry,
                replacementObserved: replacementObserved,
                replacementExists: replacementExists)

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

func reportFor(entries: seq[ObservedEntry]; window = 20): AcceptanceReport =
  buildReport(entries, "Archright/Axiom", BaseSha,
              "2026-11-19T12:00:00Z", window)

# ---------------------------------------------------------------------------
# 1. Time / p50 formula
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

  test "wall is terminal attempt run_started_at -> updated_at in integer seconds":
    let e = entry(attempts = @[
      succeed("1", 1, "2026-11-19T00:00:00Z", "2026-11-19T00:01:00Z"),
      succeed("1", 2, "2026-11-19T00:05:00Z", "2026-11-19T00:14:06Z")])
    let w = entryWallSeconds(e)
    check w.observed
    check w.seconds == 546

  test "terminal attempt is latest by run_started_at before attempt number":
    let e = entry(attempts = @[
      succeed("1", 9, "2026-11-19T00:00:00Z", "2026-11-19T00:01:00Z"),
      succeed("2", 1, "2026-11-19T00:05:00Z", "2026-11-19T00:06:00Z")])
    check terminalAttempt(e).runId == "2"
    check entryWallSeconds(e).seconds == 60

  test "wall unobservable when the terminal timestamp is invalid":
    let e = entry(attempts = @[
      succeed("1", 1, "2026-11-19T00:00:00Z", "not-a-time")])
    let w = entryWallSeconds(e)
    check not w.observed
    check w.reason.len > 0

# ---------------------------------------------------------------------------
# 2. Grouping / attempts / boundary filter
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

  test "latest N window takes the last N by terminal run_started_at":
    let entries = @[
      entry(Head1, attempts = @[succeed("1", 1,
        "2026-11-19T00:00:00Z", "2026-11-19T00:01:00Z")]),
      entry(Head2, attempts = @[succeed("2", 1,
        "2026-11-19T01:00:00Z", "2026-11-19T01:01:00Z")]),
      entry(Head3, attempts = @[succeed("3", 1,
        "2026-11-19T02:00:00Z", "2026-11-19T02:01:00Z")])]
    let selected = selectWindow(entries, 2)
    check selected.len == 2
    check selected[0].headSha == Head2
    check selected[1].headSha == Head3

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

  test "NO_CERT is mint identity divergence":
    let ac = classifyAttempt(failure("1", text = "reasonCode=NO_CERT"), false, true)
    check ac.kind == ckInternalDefect
    check ac.subtype == dsIdentityDivergence

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
# 4. Cancelled handling
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
# 5. Acceptance predicate and window
# ---------------------------------------------------------------------------

suite "acceptance predicate":

  test "all success is accepted":
    let r = reportFor(@[entry(attempts = @[succeed("1")])])
    check r.acceptance.observedEntries == 1
    check r.acceptance.predicateHolds
    check r.acceptance.observationComplete
    check r.acceptance.accepted

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

  test "one unclassified outcome fails acceptance":
    let r = reportFor(@[
      entry(Head1, attempts = @[succeed("1")]),
      entry(Head2, attempts = @[failure("2", text = "unknown failure")])])
    check r.acceptance.unclassified == 1
    check not r.acceptance.accepted

  test "an observation gap fails acceptance even when a defect is present":
    let r = reportFor(@[
      entry(Head1, attempts = @[failure("1",
        text = "PLAN_COMPONENT_MISMATCH: x")]),
      entry(Head2, attempts = @[succeed("2")], ancestry = false)])
    check r.acceptance.internalDefect == 1
    check not r.acceptance.observationComplete
    check not r.acceptance.accepted
    check r.acceptance.gaps.len > 0

  test "window N excludes older entries from the predicate":
    let entries = @[
      entry(Head1, attempts = @[failure("1",
        text = "PLAN_COMPONENT_MISMATCH: x")]),
      entry(Head2, attempts = @[succeed("2")]),
      entry(Head3, attempts = @[succeed("3")])]
    # Starts are all equal in the fixture; selectWindow breaks ties by head_sha,
    # so ordering is deterministic. Widen the starts to make the intent exact.
    var timed = entries
    timed[0].attempts[0].runStartedAt = "2026-11-19T00:00:00Z"
    timed[0].attempts[0].updatedAt = "2026-11-19T00:01:00Z"
    timed[1].attempts[0].runStartedAt = "2026-11-19T01:00:00Z"
    timed[1].attempts[0].updatedAt = "2026-11-19T01:01:00Z"
    timed[2].attempts[0].runStartedAt = "2026-11-19T02:00:00Z"
    timed[2].attempts[0].updatedAt = "2026-11-19T02:01:00Z"
    let r = reportFor(timed, window = 2)
    check r.acceptance.observedEntries == 2
    check r.acceptance.internalDefect == 0
    check r.acceptance.accepted

  test "empty window is an observation gap, never a vacuous accept":
    let r = reportFor(@[])
    check r.acceptance.observedEntries == 0
    check not r.acceptance.observationComplete
    check not r.acceptance.accepted

  test "pre-boundary entries are not counted":
    let r = reportFor(@[
      entry(Head1, attempts = @[succeed("1")], post = false, ancestry = true)])
    check r.acceptance.observedEntries == 0
    check r.excludedBeforeBoundary == 1
    check not r.acceptance.accepted

# ---------------------------------------------------------------------------
# 6. Report rendering
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
                "conclusion", "classification", "subtype", "evidence",
                "wall_seconds", "gap", "gap_reason", "post_boundary"]:
      check item.hasKey(key)
    check item{"run_id"}.getStr == "77"
    check item{"attempt_ids"}[0].getStr == "77:3"
    check item{"classification"}.getStr == "internal_defect"
    check item{"subtype"}.getStr == "identity_divergence"
    check item{"evidence"}.getStr.contains("artifact:")
    check node{"counts"}{"internal_defect"}.getInt == 1
    check node{"counts"}{"internal_defect_subtypes"}{"identity_divergence"}.getInt == 1
    check node{"acceptance"}{"unexpected_internal_defects"}.getInt == 1

  test "Markdown reports counts, subtypes, latency, and gaps":
    let r = reportFor(@[
      entry(Head1, attempts = @[succeed("1")]),
      entry(Head2, attempts = @[failure("2", text = "ROT_ALLOWLIST")])])
    let md = renderMarkdown(r)
    check md.contains("CI Acceptance Contract v2")
    check md.contains("legitimate_policy")
    check md.contains("identity_divergence")
    check md.contains("p50=")
    check md.contains("## Gaps")

# ---------------------------------------------------------------------------
# 7. --recompute-baseline (pure core)
# ---------------------------------------------------------------------------

suite "recompute-baseline":

  func runListRow(id, start, upd: string, attempts = newJArray()): JsonNode =
    %*{"id": id, "run_started_at": start, "updated_at": upd,
       "attempts": attempts}

  test "run list uses the terminal attempt and the same p50 formula":
    let attempts = newJArray()
    attempts.add %*{"run_attempt": 1,
                    "run_started_at": "2026-11-19T00:00:00Z",
                    "updated_at": "2026-11-19T00:10:00Z"}
    attempts.add %*{"run_attempt": 2,
                    "run_started_at": "2026-11-19T00:20:00Z",
                    "updated_at": "2026-11-19T00:20:50Z"}
    let root = %*{"runs": [runListRow("1", "2026-11-19T00:00:00Z",
                                      "2026-11-19T00:00:30Z", attempts),
                            runListRow("2", "2026-11-19T01:00:00Z",
                                      "2026-11-19T01:00:20Z"),
                            runListRow("3", "2026-11-19T02:00:00Z",
                                      "2026-11-19T02:00:41Z")]}
    let durations = durationsFromRunList(root)
    check durations.len == 3
    check durations[0].seconds == 50   # terminal attempt 2, not attempt 1
    check durations[1].seconds == 20
    check durations[2].seconds == 41
    check p50Seconds(@[50, 20, 41]) == 41.0  # sorted 20,41,50

  test "top-level array is accepted":
    let root = %*[runListRow("1", "2026-11-19T00:00:00Z",
                             "2026-11-19T00:09:06Z")]
    let durations = durationsFromRunList(root)
    check durations.len == 1
    check durations[0].seconds == 546

  test "unparsable row is excluded and makes the baseline incomplete":
    let root = %*[runListRow("1", "2026-11-19T00:00:00Z",
                             "2026-11-19T00:09:06Z"),
                  runListRow("2", "not-a-time", "also-not-a-time")]
    let durations = durationsFromRunList(root)
    check durations.len == 2
    check durations[0].observed
    check not durations[1].observed
    check not baselineComplete(durations)
    let node = baselineJson(durations)
    check node{"n"}.getInt == 1
    check node{"excluded"}.getInt == 1
    check node{"p50_display"}.getStr == "546"
    check node{"gaps"}.len == 1

  test "empty run list is not a complete baseline":
    check not baselineComplete(@[])
    let node = baselineJson(@[])
    check node{"n"}.getInt == 0

# ---------------------------------------------------------------------------
# 8. Fail-closed invariants
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