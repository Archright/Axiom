## Unit tests for tools/merge_ruleset_drift_monitor.nim — the live GitHub
## ruleset drift monitor for the auto-merge admission authority. Covers the
## pure judgment core over synthetic ruleset JSON fixtures: healthy fixture
## PASS, missing merge_queue FAIL, wrong merge_method FAIL, wrong
## grouping_strategy FAIL (HEADGREEN forbidden — ADR-0032 (e)), missing
## required-check context FAIL, wrong approving count FAIL, codeowner value
## NOT an expectation (adopted policy 2026-09-30 rejected enforced review for
## the one-human org — both true and false yield the same PASS), merge-queue
## size limits NOT expectations (max_entries_to_build is the merge_group
## webhook throttle — semantics fix in docs/spec/github_delegation_residuals.md
## R2), fail-closed on unparsable structure, and the suggestion text
## appearing exactly when drift occurs.
##
## The expected required-check set is NOT hardcoded in the monitor: it is
## DERIVED from the policy SSOT (config/policy/merge_admission.json —
## requiredValidations[].job ∪ requiredWorkflowDetection.verdictJob). These
## fixtures therefore carry a POLICY document and assert the derivation
## (ADR-0035 §3 — policy ↔ constants ↔ ruleset three-way agreement).
##
## No network access: fixtures are literals; only the pure judgment core
## (judgeRulesetDrift / judgeConstantMirror / judgeProducerObservation /
## expectedStatusContexts / resolveMainRuleset / ruleOfType /
## hasStatusContext) is exercised.
##
## Run from repo root:
##   nim c -r --hints:off --nimcache:/tmp/nimc_drift_mon \
##       tests/unit/test_merge_ruleset_drift_monitor.nim

import std/[json, sequtils, unittest, strutils]
import ../../tools/merge_ruleset_drift_monitor

## Policy SSOT fixture — the shape of config/policy/merge_admission.json
## v1.19.0 (hybrid authority rotation): workflowPath is the PRIMARY
## identifier; the numeric workflow id survives only as workflowIdObservation
## {value, observedAt} — an observed-at record, never a binding. Two
## repo-native requiredValidations + the org-injected producer recorded in
## requiredWorkflowDetection (the callee admission-check.yml is NOT a
## requiredValidations entry — it never emits a check-run named
## 'admission-check').
let POLICY = parseJson("""
{
  "requiredValidations": [
    {"workflowPath": ".github/workflows/bsec-integrity.yml",
     "workflowIdObservation": {"value": 409432614, "observedAt": "2026-11-07T05:23:47Z"},
     "job": "bsec-integrity",
     "acceptableConclusion": "success"},
    {"workflowPath": ".github/workflows/debt-registry-gate.yml",
     "workflowIdObservation": {"value": 409432630, "observedAt": "2026-11-07T05:23:47Z"},
     "job": "debt-registry-gate",
     "acceptableConclusion": "success"}
  ],
  "requiredWorkflowDetection": {
    "repositoryId": 1182157951,
    "workflowPath": ".github/workflows/admission-gate-v2.yml",
    "verdictJob": "admission-check"
  }
}
""")

## The compiled-in constant mirror fixture — the shape of the
## src/cli/merge_cli.nim declarations the policy is compared against.
## v1.19.0: RequiredWorkflowIds binds (job, workflowPath) tuples — the
## path identity (the numeric id is an observed-at record in the policy).
let MIRROR = """
const
  RequiredChecks*: seq[string] = @[
    "admission-check",
    "bsec-integrity",
    "debt-registry-gate",
  ]
  RequiredWorkflowIds*: seq[tuple[jobName: string, workflowPath: string]] = @[
    ("bsec-integrity", ".github/workflows/bsec-integrity.yml"),
    ("debt-registry-gate", ".github/workflows/debt-registry-gate.yml"),
  ]
"""

let HEALTHY = parseJson("""
{
  "id": 20303214,
  "name": "main",
  "target": "branch",
  "conditions": {"ref_name": {"exclude": [], "include": ["~DEFAULT_BRANCH"]}},
  "rules": [
    {"type": "deletion"},
    {"type": "non_fast_forward"},
    {"type": "pull_request",
     "parameters": {"required_approving_review_count": 0,
                    "require_code_owner_review": false,
                    "dismiss_stale_reviews_on_push": false,
                    "required_reviewers": []}},
    {"type": "required_status_checks",
     "parameters": {"strict_required_status_checks_policy": false,
                    "required_status_checks": [
                      {"context": "admission-check", "integration_id": 15368},
                      {"context": "bsec-integrity", "integration_id": 15368},
                      {"context": "debt-registry-gate", "integration_id": 15368}]}},
    {"type": "merge_queue",
     "parameters": {"merge_method": "MERGE", "grouping_strategy": "ALLGREEN",
                    "max_entries_to_build": 2}}
  ]
}
""")

## Check-runs payload fixture — the additive producer observation surface.
let CHECK_RUNS = parseJson("""
{
  "total_count": 3,
  "check_runs": [
    {"name": "admission-check", "conclusion": "success",
     "app": {"id": 15368, "slug": "github-actions"}},
    {"name": "bsec-integrity", "conclusion": "success",
     "app": {"id": 15368, "slug": "github-actions"}},
    {"name": "debt-registry-gate", "conclusion": "success",
     "app": {"id": 15368, "slug": "github-actions"}}
  ]
}
""")

proc withoutRuleType(base: JsonNode; ruleType: string): JsonNode =
  ## Deep-copy fixture with rules of the given type removed (JsonNode is a
  ## ref; never mutate the shared HEALTHY literal).
  result = copy(base)
  var rs = newJArray()
  for r in result["rules"].items:
    if r["type"].getStr() != ruleType:
      rs.add(r)
  result["rules"] = rs

proc setRuleParam(base: JsonNode; ruleType, param: string; value: JsonNode): JsonNode =
  ## Deep-copy fixture with one parameters field replaced.
  result = copy(base)
  for r in result["rules"].items:
    if r["type"].getStr() == ruleType:
      r["parameters"][param] = value

suite "expectedStatusContexts — the expected set is DERIVED from the policy SSOT":
  test "requiredValidations[].job ∪ requiredWorkflowDetection.verdictJob":
    let ctx = expectedStatusContexts(POLICY)
    check ctx == @["admission-check", "bsec-integrity", "debt-registry-gate"]

  test "the org producer is carried by requiredWorkflowDetection, not requiredValidations":
    # The Axiom callee admission-check.yml (365692388) never emits a check-run
    # named 'admission-check' — it emits 'verdict / admission-check' inside the
    # org gate's own run. The derivation must therefore pick the context up
    # from requiredWorkflowDetection only.
    let ctx = expectedStatusContexts(POLICY)
    check "admission-check" in ctx
    for c in ctx:
      check c != "verdict / admission-check"

  test "a policy without any expectation yields an empty set (the caller fails closed)":
    let empty = parseJson("""{"requiredValidations": []}""")
    check expectedStatusContexts(empty).len == 0

  test "malformed entries are skipped, never guessed":
    let partial = parseJson("""
    {"requiredValidations": [{"job": "bsec-integrity"},
                              {"workflowId": 1},
                              {"job": 42},
                              {"job": "debt-registry-gate"}]}
    """)
    let ctx = expectedStatusContexts(partial)
    check ctx == @["bsec-integrity", "debt-registry-gate"]

suite "judgeRulesetDrift":
  test "healthy fixture PASS (all four expectations hold)":
    let v = judgeRulesetDrift(HEALTHY, expectedStatusContexts(POLICY))
    check v.ok
    check v.summary == "ruleset drift: 4/4 expectations hold"
    check v.suggestion.len == 0
    check v.lines.filterIt(it.startsWith("OK")).len == 4
    check v.lines.filterIt(it.startsWith("DRIFT")).len == 0

  test "missing merge_queue FAIL":
    let v = judgeRulesetDrift(withoutRuleType(HEALTHY, "merge_queue"),
                              expectedStatusContexts(POLICY))
    check not v.ok
    # both merge_queue expectations (merge_method, grouping_strategy) report
    # the one removed rule — two DRIFT lines.
    check v.lines.filterIt(it.startsWith("DRIFT merge_queue")).len == 2
    check v.suggestion.len > 0

  test "wrong merge_method FAIL":
    let v = judgeRulesetDrift(setRuleParam(HEALTHY, "merge_queue",
                                           "merge_method", %"REBASE"),
                              expectedStatusContexts(POLICY))
    check not v.ok
    let drift = v.lines.filterIt(it.startsWith("DRIFT merge_queue"))
    check drift.len == 1
    check "REBASE" in drift[0]

  test "wrong grouping_strategy FAIL (HEADGREEN forbidden — ADR-0032 (e))":
    let v = judgeRulesetDrift(setRuleParam(HEALTHY, "merge_queue",
                                           "grouping_strategy", %"HEADGREEN"),
                              expectedStatusContexts(POLICY))
    check not v.ok
    let drift = v.lines.filterIt(it.startsWith("DRIFT merge_queue"))
    check drift.len == 1
    check "HEADGREEN" in drift[0]
    check v.suggestion.len > 0

  test "missing grouping_strategy FAIL (fail closed on malformed value)":
    let v = judgeRulesetDrift(setRuleParam(HEALTHY, "merge_queue",
                                           "grouping_strategy", newJNull()),
                              expectedStatusContexts(POLICY))
    check not v.ok
    check v.lines.filterIt(
      it.startsWith("DRIFT merge_queue: parameters.grouping_strategy")).len == 1

  test "missing required-check context FAIL":
    let v = judgeRulesetDrift(
      setRuleParam(HEALTHY, "required_status_checks", "required_status_checks",
                   %* [{"context": "some-other-check", "integration_id": 15368}]),
      expectedStatusContexts(POLICY))
    check not v.ok
    check v.lines.filterIt(it.startsWith("DRIFT required_status_checks")).len == 1

  test "the S0 live shape (admission-check only) FAIL — the cutover state is DRIFT":
    # The adopted policy is the exact three-context set; a live ruleset that
    # still carries one context must DRIFT (fail-closed), never PASS.
    let v = judgeRulesetDrift(
      setRuleParam(HEALTHY, "required_status_checks", "required_status_checks",
                   %* [{"context": "admission-check", "integration_id": 15368}]),
      expectedStatusContexts(POLICY))
    check not v.ok
    let drift = v.lines.filterIt(it.startsWith("DRIFT required_status_checks"))
    check drift.len == 1
    check "bsec-integrity" in drift[0]
    check v.suggestion.len > 0

  test "missing admission-check FAIL (fail-closed on verdict absence)":
    let v = judgeRulesetDrift(
      setRuleParam(HEALTHY, "required_status_checks", "required_status_checks",
                   %* [{"context": "bsec-integrity", "integration_id": 15368},
                       {"context": "debt-registry-gate", "integration_id": 15368}]),
      expectedStatusContexts(POLICY))
    check not v.ok
    let drift = v.lines.filterIt(it.startsWith("DRIFT required_status_checks"))
    check drift.len == 1
    check "admission-check" in drift[0]

  test "extra context FAIL (exactly the expected set)":
    let v = judgeRulesetDrift(
      setRuleParam(HEALTHY, "required_status_checks", "required_status_checks",
                   %* [{"context": "admission-check", "integration_id": 15368},
                       {"context": "bsec-integrity", "integration_id": 15368},
                       {"context": "debt-registry-gate", "integration_id": 15368},
                       {"context": "lint"}]),
      expectedStatusContexts(POLICY))
    check not v.ok
    let drift = v.lines.filterIt(it.startsWith("DRIFT required_status_checks"))
    check drift.len == 1
    check "lint" in drift[0]

  test "wrong producing App FAIL (app-level producer control)":
    # integration_id != the GitHub Actions app id = the context is NOT bound to
    # the Actions app — the platform's app-level producer control is absent.
    let v = judgeRulesetDrift(
      setRuleParam(HEALTHY, "required_status_checks", "required_status_checks",
                   %* [{"context": "admission-check", "integration_id": 15368},
                       {"context": "bsec-integrity", "integration_id": 4242},
                       {"context": "debt-registry-gate", "integration_id": 15368}]),
      expectedStatusContexts(POLICY))
    check not v.ok
    let drift = v.lines.filterIt(it.startsWith("DRIFT required_status_checks"))
    check drift.len == 1
    check "bsec-integrity" in drift[0]
    check "integration_id" in drift[0]

  test "an empty expectation set FAILs closed (never vacuously PASS)":
    let v = judgeRulesetDrift(HEALTHY, @[])
    check not v.ok
    check v.lines.filterIt(it.startsWith("DRIFT ruleset")).len == 1
    check v.summary == "ruleset drift: 0/4 expectations hold"

  test "wrong approving review count FAIL":
    let v = judgeRulesetDrift(
      setRuleParam(HEALTHY, "pull_request",
                   "required_approving_review_count", %1),
      expectedStatusContexts(POLICY))
    check not v.ok
    check v.lines.filterIt(it.startsWith("DRIFT pull_request")).len == 1

  test "require_code_owner_review is not an expectation (both values PASS)":
    # Adopted policy 2026-09-30: enforced review (incl. code-owner) was
    # rejected for the one-human org, so the expected set has no code-owner
    # requirement. The live false value is the adopted state — not drift.
    let vFalse = judgeRulesetDrift(
      setRuleParam(HEALTHY, "pull_request", "require_code_owner_review", %false),
      expectedStatusContexts(POLICY))
    check vFalse.ok
    check vFalse.summary == "ruleset drift: 4/4 expectations hold"
    check vFalse.lines.filterIt(it.startsWith("DRIFT")).len == 0
    check vFalse.suggestion.len == 0
    # A hypothetical future flip to true (e.g. a second architect exists,
    # ADR-0024 switch clause) would also not drift until the expectation is
    # deliberately re-added.
    let vTrue = judgeRulesetDrift(
      setRuleParam(HEALTHY, "pull_request", "require_code_owner_review", %true),
      expectedStatusContexts(POLICY))
    check vTrue.ok
    check vTrue.lines.filterIt(it.startsWith("DRIFT")).len == 0
    check vTrue.summary == "ruleset drift: 4/4 expectations hold"

  test "merge-queue size limits are not expectations (semantics fix, R2)":
    # max_entries_to_build is the concurrent check/build throttle for
    # merge_group webhooks (NOT a group-size guarantee); max_entries_to_merge
    # bounds PRs merged together. The ALLGREEN + 1:1 policy does not ride on
    # these values — the 1:1 shape is enforced structurally (event parent
    # relation, PR identity, candidate-tree equivalence).
    let vBuild = judgeRulesetDrift(setRuleParam(HEALTHY, "merge_queue",
                                                "max_entries_to_build", %99),
                                   expectedStatusContexts(POLICY))
    check vBuild.ok
    check vBuild.summary == "ruleset drift: 4/4 expectations hold"
    let vMerge = judgeRulesetDrift(setRuleParam(HEALTHY, "merge_queue",
                                                "max_entries_to_merge", %5),
                                   expectedStatusContexts(POLICY))
    check vMerge.ok
    check vMerge.summary == "ruleset drift: 4/4 expectations hold"

  test "required_status_checks as plain strings shape accepted":
    let v = judgeRulesetDrift(
      setRuleParam(HEALTHY, "required_status_checks", "required_status_checks",
                   %* ["admission-check", "bsec-integrity", "debt-registry-gate"]),
      expectedStatusContexts(POLICY))
    check not v.ok
    # the plain-string shape carries no integration_id — the app-level
    # producer control cannot be confirmed -> DRIFT (fail-closed).
    check v.lines.filterIt(it.startsWith("DRIFT required_status_checks")).len == 1

  test "required_status_checks plain strings with extra context FAIL":
    let v = judgeRulesetDrift(
      setRuleParam(HEALTHY, "required_status_checks", "required_status_checks",
                   %* ["admission-check", "bsec-integrity", "debt-registry-gate", "lint"]),
      expectedStatusContexts(POLICY))
    check not v.ok

  test "unparsable structure FAIL (fail closed)":
    let v = judgeRulesetDrift(parseJson("""{"name": "main"}"""),
                              expectedStatusContexts(POLICY))
    check not v.ok
    check v.lines.filterIt(it.startsWith("DRIFT ruleset")).len == 1
    check v.summary == "ruleset drift: 0/4 expectations hold"
    check not judgeRulesetDrift(nil, expectedStatusContexts(POLICY)).ok

suite "judgeConstantMirror — the policy ↔ constants leg":
  test "an agreeing mirror PASS":
    let v = judgeConstantMirror(POLICY, MIRROR, expectedStatusContexts(POLICY))
    check v.ok
    check v.summary == "constant mirror: 2/2 checks hold"
    check v.lines.filterIt(it.startsWith("OK")).len == 2

  test "a divergent RequiredChecks set FAIL":
    let stale = MIRROR.replace("\"debt-registry-gate\",", "\"debt-registry-gate-legacy\",")
    let v = judgeConstantMirror(POLICY, stale, expectedStatusContexts(POLICY))
    check not v.ok
    check v.lines.filterIt(it.startsWith("DRIFT constant mirror")).len == 2

  test "a divergent RequiredWorkflowIds binding FAIL":
    let stale = MIRROR.replace(
      "(\"debt-registry-gate\", \".github/workflows/debt-registry-gate.yml\")",
      "(\"debt-registry-gate\", \".github/workflows/spoofed-producer.yml\")")
    let v = judgeConstantMirror(POLICY, stale, expectedStatusContexts(POLICY))
    check not v.ok
    let drift = v.lines.filterIt(it.startsWith("DRIFT constant mirror"))
    check drift.len == 1
    check "spoofed-producer" in drift[0]

  test "an unreadable mirror FAILs closed (never reads as agreement)":
    let v = judgeConstantMirror(POLICY, "", expectedStatusContexts(POLICY))
    check not v.ok
    check v.lines.filterIt(it.startsWith("DRIFT constant mirror")).len == 2
    check v.summary == "constant mirror: 0/2 checks hold"

suite "judgeProducerObservation — the policy ↔ live producer leg":
  test "all expected contexts produced by the Actions app PASS":
    let v = judgeProducerObservation(CHECK_RUNS, expectedStatusContexts(POLICY))
    check v.ok
    check v.summary == "producer observation: 3/3 contexts observed"
    check v.lines.filterIt(it.startsWith("OK")).len == 3

  test "a context produced by another app FAIL (same-name spoof signal)":
    let spoofed = copy(CHECK_RUNS)
    for cr in spoofed["check_runs"].items:
      if cr["name"].getStr() == "bsec-integrity":
        cr["app"] = %* {"id": 4242, "slug": "some-app"}
    let v = judgeProducerObservation(spoofed, expectedStatusContexts(POLICY))
    check not v.ok
    let drift = v.lines.filterIt(it.startsWith("DRIFT producer observation"))
    check drift.len == 1
    check "bsec-integrity" in drift[0]

  test "a missing context FAIL (missing != clean)":
    # The read is COMPLETE here (total_count == fetched) — the context simply
    # was not produced (a distinct fact from a truncated read).
    var partial = copy(CHECK_RUNS)
    var kept = newJArray()
    for cr in partial["check_runs"].items:
      if cr["name"].getStr() != "debt-registry-gate":
        kept.add(cr)
    partial["check_runs"] = kept
    partial["total_count"] = %2
    let v = judgeProducerObservation(partial, expectedStatusContexts(POLICY))
    check not v.ok
    let drift = v.lines.filterIt(it.startsWith("DRIFT producer observation"))
    check drift.len == 1
    check "debt-registry-gate" in drift[0]
    check "incomplete" notin drift[0]

  test "an unparsable payload FAILs closed":
    let v = judgeProducerObservation(parseJson("""{"nope": 1}"""),
                                     expectedStatusContexts(POLICY))
    check not v.ok
    check v.lines.filterIt(it.startsWith("DRIFT producer observation")).len == 1

  test "a truncated read FAILs closed as INCOMPLETE (never as a missing context)":
    # Measured 2026-10-21: the check-runs API paginates at 30 by default and a
    # landing carries 31+ check-runs. A truncated read must be reported as an
    # incomplete read — reading it as "the context was never produced" is a
    # false drift signal (the first dispatched drift run hit exactly that).
    let truncated = %* {"total_count": 31,
                        "check_runs": [{"name": "admission-check",
                                        "app": {"id": 15368, "slug": "github-actions"}}]}
    let v = judgeProducerObservation(truncated, expectedStatusContexts(POLICY))
    check not v.ok
    let drift = v.lines.filterIt(it.startsWith("DRIFT producer observation"))
    check drift.len == 1
    check "incomplete" in drift[0]
    check "missing" notin drift[0]

  test "a complete read (total_count == fetched) is judged on the contexts":
    let complete = %* {"total_count": 1,
                       "check_runs": [{"name": "admission-check",
                                       "app": {"id": 15368, "slug": "github-actions"}}]}
    let v = judgeProducerObservation(complete, expectedStatusContexts(POLICY))
    check not v.ok
    # no truncation verdict — the missing contexts are reported as missing
    let drift = v.lines.filterIt(it.startsWith("DRIFT producer observation"))
    check drift.len == 2
    check drift.allIt("incomplete" notin it)

suite "ruleOfType / hasStatusContext":
  test "rule lookup by type":
    check not ruleOfType(HEALTHY, "merge_queue").isNil
    check ruleOfType(HEALTHY, "merge_queue")["type"].getStr() == "merge_queue"
    check ruleOfType(HEALTHY, "workflow_rules").isNil
    check ruleOfType(nil, "merge_queue").isNil

  test "status context detection (object and string shapes)":
    let paramsObj = %* {"required_status_checks": [{"context": "admission-check"}]}
    check hasStatusContext(paramsObj, "admission-check")
    check not hasStatusContext(paramsObj, "other")
    let paramsStr = %* {"required_status_checks": ["admission-check"]}
    check hasStatusContext(paramsStr, "admission-check")
    check not hasStatusContext(%* {"required_status_checks": "admission-check"},
                               "admission-check")
    check not hasStatusContext(%* {}, "admission-check")

suite "v1.19.0 workflowIdObservation — the id is an observed-at record, not a binding":
  ## Policy SSOT v1.19.0 (hybrid authority rotation): workflowPath is the
  ## PRIMARY identifier; the numeric workflow id survives only as
  ## workflowIdObservation {value, observedAt}. The (job, workflowPath)
  ## binding is therefore INDEPENDENT of the observation record: an entry
  ## whose id has not yet been observed (workflowIdObservation null — the
  ## pre-push placeholder state, the v1.16.0/v1.7.0 're-registration
  ## post-push' convention rebased onto path identity) still contributes
  ## the full binding, and a same-name spoof (a different path bound to the
  ## job) is DRIFT exactly as before.
  let unobservedPolicy = parseJson("""
{
  "requiredValidations": [
    {"workflowPath": ".github/workflows/bsec-integrity.yml",
     "workflowIdObservation": {"value": 409432614, "observedAt": "2026-11-07T05:23:47Z"},
     "job": "bsec-integrity",
     "acceptableConclusion": "success"},
    {"workflowPath": ".github/workflows/debt-registry-gate.yml",
     "workflowIdObservation": {"value": 409432630, "observedAt": "2026-11-07T05:23:47Z"},
     "job": "debt-registry-gate",
     "acceptableConclusion": "success"},
    {"workflowPath": ".github/workflows/generation-acceptance.yml",
     "workflowIdObservation": null,
     "job": "generation-acceptance",
     "acceptableConclusion": "success"}
  ],
  "requiredWorkflowDetection": {
    "repositoryId": 1182157951,
    "workflowPath": ".github/workflows/admission-gate-v2.yml",
    "verdictJob": "admission-check"
  }
}
""")
  let unobservedMirror = """
const
  RequiredChecks*: seq[string] = @[
    "admission-check",
    "bsec-integrity",
    "debt-registry-gate",
    "generation-acceptance",
  ]
  RequiredWorkflowIds*: seq[tuple[jobName: string, workflowPath: string]] = @[
    ("bsec-integrity", ".github/workflows/bsec-integrity.yml"),
    ("debt-registry-gate", ".github/workflows/debt-registry-gate.yml"),
    ("generation-acceptance", ".github/workflows/generation-acceptance.yml"),
  ]
"""
  test "an unobserved id still contributes the full (job, workflowPath) binding":
    check expectedStatusContexts(unobservedPolicy) ==
      @["admission-check", "bsec-integrity", "debt-registry-gate",
        "generation-acceptance"]
    let pb = policyWorkflowBindings(unobservedPolicy)
    check pb.kind == wbkPath
    check pb.paths ==
      @[("bsec-integrity", ".github/workflows/bsec-integrity.yml"),
        ("debt-registry-gate", ".github/workflows/debt-registry-gate.yml"),
        ("generation-acceptance", ".github/workflows/generation-acceptance.yml")]
  test "the unobserved policy and its path mirror AGREE":
    let v = judgeConstantMirror(unobservedPolicy, unobservedMirror,
                                expectedStatusContexts(unobservedPolicy))
    check v.ok
    check v.summary == "constant mirror: 2/2 checks hold"
  test "a mirror that omits the unobserved entry's binding is DRIFT (fail-closed)":
    let premature = unobservedMirror.replace(
      "(\"generation-acceptance\", \".github/workflows/generation-acceptance.yml\"),\n", "")
    let v = judgeConstantMirror(unobservedPolicy, premature,
                                expectedStatusContexts(unobservedPolicy))
    check not v.ok
    # RequiredChecks still agrees; the RequiredWorkflowIds binding set does not
    check v.lines.filterIt(it.startsWith("DRIFT constant mirror")).len == 1
    check "generation-acceptance" in v.lines.filterIt(
      it.startsWith("DRIFT constant mirror"))[0]

# ---------------------------------------------------------------------------
# resolveMainRuleset — the v1.19.0 name resolution (hybrid authority rotation)
# ---------------------------------------------------------------------------
## The seven contract cases, as literals (deterministic — no network). The
## fixtures mirror the live shapes measured 2026-11-07: the --slurp list
## (array of pages), the ruleset detail, and the rules/branches/main merged
## rule list (array of rule objects each carrying ruleset_id). The
## resolution semantics are identical in the GPA workflow (YAML) and
## landing_observe.sh (Shell) — this suite pins the Nim reference.

const
  REPO_FULL = "Archright/Axiom"

let LIVE_LIST = parseJson("""
[[{"id":25218071,"name":"axiom-admission-gate","source":"Archright","target":"branch","enforcement":"active"},
  {"id":23943917,"name":"landing-integrity","source":"Archright","target":"branch","enforcement":"active"},
  {"id":26702792,"name":"main","source":"Archright/Axiom","target":"branch","enforcement":"active"},
  {"id":26702920,"name":"cas-probe-scratch","source":"Archright/Axiom","target":"branch","enforcement":"active"},
  {"id":26702960,"name":"execution-surface-create","source":"Archright/Axiom","target":"push","enforcement":"active"},
  {"id":26702965,"name":"artifact-hygiene","source":"Archright/Axiom","target":"push","enforcement":"active"}]]
""")

let LIVE_DETAIL = parseJson("""
{"id":26702792,"name":"main","source":"Archright/Axiom","target":"branch",
 "enforcement":"active",
 "conditions":{"ref_name":{"exclude":[],"include":["~DEFAULT_BRANCH"]}},
 "rules":[
  {"type":"deletion"},
  {"type":"non_fast_forward"},
  {"type":"pull_request",
   "parameters":{"required_approving_review_count":0}},
  {"type":"required_status_checks",
   "parameters":{"required_status_checks":[
     {"context":"admission-check","integration_id":15368},
     {"context":"bsec-integrity","integration_id":15368},
     {"context":"debt-registry-gate","integration_id":15368}]}},
  {"type":"merge_queue",
   "parameters":{"merge_method":"MERGE","grouping_strategy":"ALLGREEN"}}]}
""")

let LIVE_BRANCH_RULES = parseJson("""
[{"type":"workflows","ruleset_source_type":"Organization","ruleset_source":"Archright","ruleset_id":25218071},
 {"type":"required_status_checks","ruleset_source_type":"Repository","ruleset_source":"Archright/Axiom","ruleset_id":26702792},
 {"type":"merge_queue","ruleset_source_type":"Repository","ruleset_source":"Archright/Axiom","ruleset_id":26702792}]
""")

let LIVE_CONTEXTS = @["admission-check", "bsec-integrity", "debt-registry-gate"]

proc detailFetch(id: int; body: JsonNode): RulesetDetailFetch =
  RulesetDetailFetch(id: id, ok: true, body: body)

proc branchRulesWithIds(ids: seq[int]): JsonNode =
  var arr = newJArray()
  for i in ids:
    arr.add(%* {"type": "pull_request", "ruleset_source_type": "Repository",
                "ruleset_source": REPO_FULL, "ruleset_id": i})
  arr

suite "resolveMainRuleset — the hybrid authority rotation contract":
  test "case 1: exactly one full match RESOLVES (the live shape as measured)":
    let r = resolveMainRuleset(LIVE_LIST, true,
                               @[detailFetch(26702792, LIVE_DETAIL)],
                               LIVE_BRANCH_RULES, LIVE_CONTEXTS, REPO_FULL)
    check r.status == rrsResolved
    check r.rulesetId == 26702792
    check not r.detail.isNil
    check r.lines.len > 0

  test "case 2: zero candidates REJECTED (no ruleset named main)":
    let noMain = %* [[{"id": 25218071, "name": "axiom-admission-gate",
                       "source": "Archright", "target": "branch",
                       "enforcement": "active"}]]
    let r = resolveMainRuleset(noMain, true, @[], LIVE_BRANCH_RULES,
                               LIVE_CONTEXTS, REPO_FULL)
    check r.status == rrsRejected
    check r.lines[^1].startsWith("REJECTED")

  test "case 3: two full matches REJECTED (ambiguous admission surface)":
    let twoCands = %* [[
      {"id": 26702792, "name": "main", "source": "Archright/Axiom",
       "target": "branch", "enforcement": "active"},
      {"id": 26709999, "name": "main", "source": "Archright/Axiom",
       "target": "branch", "enforcement": "active"}]]
    let r = resolveMainRuleset(twoCands, true,
                               @[detailFetch(26702792, LIVE_DETAIL),
                                 detailFetch(26709999, LIVE_DETAIL)],
                               branchRulesWithIds(@[26702792, 26709999]),
                               LIVE_CONTEXTS, REPO_FULL)
    check r.status == rrsRejected
    check r.lines[^1].contains("AMBIGUOUS")

  test "case 4: an INACTIVE main ruleset REJECTED (enforcement filter)":
    let inactive = %* [[{"id": 26702792, "name": "main",
                         "source": "Archright/Axiom", "target": "branch",
                         "enforcement": "disabled"}]]
    let r = resolveMainRuleset(inactive, true, @[], LIVE_BRANCH_RULES,
                               LIVE_CONTEXTS, REPO_FULL)
    check r.status == rrsRejected
    check r.lines[^1].contains("ABSENT")

  test "case 5: wrong ownership/conditions/checks REJECTED":
    # (a) org-owned "main" (source=Archright) is excluded at the list level
    let orgOwned = %* [[{"id": 99, "name": "main", "source": "Archright",
                         "target": "branch", "enforcement": "active"}]]
    let rA = resolveMainRuleset(orgOwned, true, @[], LIVE_BRANCH_RULES,
                                LIVE_CONTEXTS, REPO_FULL)
    check rA.status == rrsRejected
    # (b) repo-owned main whose conditions target a non-main ref
    let wrongCond = LIVE_DETAIL.copy()
    wrongCond{"conditions"} = %* {"ref_name": {"exclude": [], "include": ["refs/heads/develop"]}}
    let rB = resolveMainRuleset(LIVE_LIST, true,
                                @[detailFetch(26702792, wrongCond)],
                                LIVE_BRANCH_RULES, LIVE_CONTEXTS, REPO_FULL)
    check rB.status == rrsRejected
    check rB.lines.anyIt(it.contains("conditions do not target"))
    # (c) repo-owned main whose required checks do not match the policy
    let wrongChecks = LIVE_DETAIL.copy()
    var entries = newJArray()
    for c in LIVE_CONTEXTS:
      entries.add(%* {"context": c, "integration_id": 15368})
    entries.add(%* {"context": "rogue-context", "integration_id": 15368})
    for rule in wrongChecks{"rules"}.items:
      if rule{"type"}.getStr() == "required_status_checks":
        rule{"parameters"}{"required_status_checks"} = entries
    let rC = resolveMainRuleset(LIVE_LIST, true,
                                @[detailFetch(26702792, wrongChecks)],
                                LIVE_BRANCH_RULES, LIVE_CONTEXTS, REPO_FULL)
    check rC.status == rrsRejected
    check rC.lines.anyIt(it.contains("required_status_checks"))

  test "case 6: a failed detail fetch is UNKNOWN (never zero-match)":
    let r = resolveMainRuleset(LIVE_LIST, true,
                               @[RulesetDetailFetch(id: 26702792, ok: false,
                                                    body: nil)],
                               LIVE_BRANCH_RULES, LIVE_CONTEXTS, REPO_FULL)
    check r.status == rrsUnknown
    check r.lines[^1].startsWith("UNKNOWN")

  test "case 7: incomplete pagination is UNKNOWN (distinct from empty)":
    let r = resolveMainRuleset(LIVE_LIST, false, @[], LIVE_BRANCH_RULES,
                               LIVE_CONTEXTS, REPO_FULL)
    check r.status == rrsUnknown
    check r.lines[^1].contains("INCOMPLETE")

  test "an unavailable branch cross-validation read is UNKNOWN, an absent id is excluded":
    # read unavailable (nil) while a candidate passes the detail conditions
    let rNil = resolveMainRuleset(LIVE_LIST, true,
                                  @[detailFetch(26702792, LIVE_DETAIL)],
                                  nil, LIVE_CONTEXTS, REPO_FULL)
    check rNil.status == rrsUnknown
    check rNil.lines[^1].contains("cross-validation read unavailable")
    # read available but the candidate's ruleset_id is absent from the branch
    # response (the ruleset does not apply to refs/heads/main) -> excluded
    let rAbsent = resolveMainRuleset(LIVE_LIST, true,
                                     @[detailFetch(26702792, LIVE_DETAIL)],
                                     branchRulesWithIds(@[25218071]),
                                     LIVE_CONTEXTS, REPO_FULL)
    check rAbsent.status == rrsRejected
    check rAbsent.lines.anyIt(it.contains("cross-validation failed, excluded"))

  test "the flattened (non-slurp) list shape resolves identically":
    let flat = %* [{"id": 26702792, "name": "main", "source": "Archright/Axiom",
                    "target": "branch", "enforcement": "active"},
                   {"id": 26702965, "name": "artifact-hygiene",
                    "source": "Archright/Axiom", "target": "push",
                    "enforcement": "active"}]
    let r = resolveMainRuleset(flat, true,
                               @[detailFetch(26702792, LIVE_DETAIL)],
                               LIVE_BRANCH_RULES, LIVE_CONTEXTS, REPO_FULL)
    check r.status == rrsResolved
    check r.rulesetId == 26702792

  test "an empty but COMPLETE list is REJECTED (empty != incomplete)":
    let r = resolveMainRuleset(%* [], true, @[], LIVE_BRANCH_RULES,
                               LIVE_CONTEXTS, REPO_FULL)
    check r.status == rrsRejected

  test "an unparsable list payload (non-array) is UNKNOWN":
    let r = resolveMainRuleset(%* {"message": "Not Found"}, true, @[],
                               LIVE_BRANCH_RULES, LIVE_CONTEXTS, REPO_FULL)
    check r.status == rrsUnknown

  test "the ref name literal refs/heads/main also satisfies the conditions":
    let literalRef = LIVE_DETAIL.copy()
    literalRef{"conditions"} = %* {"ref_name": {"exclude": [],
                                                "include": ["refs/heads/main"]}}
    let r = resolveMainRuleset(LIVE_LIST, true,
                               @[detailFetch(26702792, literalRef)],
                               LIVE_BRANCH_RULES, LIVE_CONTEXTS, REPO_FULL)
    check r.status == rrsResolved

suite "listLevelCandidateIds / flattenRulesetPages":
  test "slurp and flat shapes flatten to the same entries":
    check flattenRulesetPages(LIVE_LIST).len == 6
    check listLevelCandidateIds(LIVE_LIST, REPO_FULL) == @[26702792]
  test "nil and non-array payloads yield no entries":
    check flattenRulesetPages(nil).len == 0
    check flattenRulesetPages(%* {"x": 1}).len == 0

suite "dual-shape constant mirror (v1.19.1) — the rotation window":
  ## The hybrid authority rotation lands in two steps: the judge's monitor
  ## first (PR #7), the constants second (PR #6). Between the two landings
  ## the BASE tree carries a v1.19.0 monitor over LEGACY constants — the
  ## mirror must adjudicate the legacy axis coherently. The pre-v1.19.1
  ## parser read the legacy ("job", 381835906) tuples as two QUOTED strings
  ## and silently paired ADJACENT job names (bsec-integrity@debt-registry-
  ## gate) — a false DRIFT that self-test-failed the driver (PR #6 run
  ## 42359181261, L4 known-good rc=1; reproduced locally 2026-11-07 with
  ## the exact workflow invocation).
  let legacyPolicy = parseJson("""
{
  "requiredValidations": [
    {"workflowPath": ".github/workflows/bsec-integrity.yml",
     "workflowId": 381835906,
     "job": "bsec-integrity",
     "acceptableConclusion": "success"},
    {"workflowPath": ".github/workflows/debt-registry-gate.yml",
     "workflowId": 389486255,
     "job": "debt-registry-gate",
     "acceptableConclusion": "success"}
  ],
  "requiredWorkflowDetection": {
    "repositoryId": 1182157951,
    "workflowPath": ".github/workflows/admission-gate-v2.yml",
    "verdictJob": "admission-check"
  }
}
""")
  let legacyMirror = """
const
  RequiredChecks*: seq[string] = @[
    "admission-check",
    "bsec-integrity",
    "debt-registry-gate",
  ]
  RequiredWorkflowIds*: seq[tuple[jobName: string, workflowId: int]] = @[
    ("bsec-integrity", 381835906),
    ("debt-registry-gate", 389486255),
  ]
"""

  test "the legacy declaration parses as (job, integer id) — never adjacent job pairs":
    let b = mergeCliWorkflowBindings(legacyMirror)
    check b.kind == wbkLegacyInt
    check b.legacyInt == @[("bsec-integrity", 381835906),
                           ("debt-registry-gate", 389486255)]
    check b.paths.len == 0

  test "a legacy policy and its legacy mirror AGREE (the base-tree self-test)":
    let v = judgeConstantMirror(legacyPolicy, legacyMirror,
                                expectedStatusContexts(legacyPolicy))
    check v.ok
    check v.summary == "constant mirror: 2/2 checks hold"
    check v.lines.filterIt(it.startsWith("OK")).len == 2

  test "a legacy binding value mismatch is DRIFT":
    let stale = legacyMirror.replace("(\"debt-registry-gate\", 389486255)",
                                     "(\"debt-registry-gate\", 424242)")
    let v = judgeConstantMirror(legacyPolicy, stale,
                                expectedStatusContexts(legacyPolicy))
    check not v.ok
    let drift = v.lines.filterIt(it.startsWith("DRIFT constant mirror"))
    check drift.len == 1
    check "424242" in drift[0]

  test "cross-shape (path policy x legacy constants) is an explicit axis-mismatch DRIFT":
    let v = judgeConstantMirror(POLICY, legacyMirror,
                                expectedStatusContexts(POLICY))
    check not v.ok
    let drift = v.lines.filterIt(it.startsWith("DRIFT constant mirror"))
    check drift.len == 1
    check "binding-axis mismatch" in drift[0]
    check "legacy integer" in drift[0]

  test "a policy mixing axes across entries is unreadable (fail-closed)":
    let mixed = parseJson("""
{
  "requiredValidations": [
    {"workflowPath": ".github/workflows/bsec-integrity.yml",
     "workflowId": 381835906,
     "job": "bsec-integrity",
     "acceptableConclusion": "success"},
    {"workflowPath": ".github/workflows/debt-registry-gate.yml",
     "workflowIdObservation": {"value": 409432630, "observedAt": "2026-11-07T05:23:47Z"},
     "job": "debt-registry-gate",
     "acceptableConclusion": "success"}
  ],
  "requiredWorkflowDetection": {
    "repositoryId": 1182157951,
    "workflowPath": ".github/workflows/admission-gate-v2.yml",
    "verdictJob": "admission-check"
  }
}
""")
    let v = judgeConstantMirror(mixed, legacyMirror,
                                expectedStatusContexts(mixed))
    check not v.ok
    check v.lines.filterIt(it.startsWith("DRIFT constant mirror")).len == 1

  test "an entry carrying BOTH axes on one entry is unreadable (fail-closed)":
    let both = parseJson("""
{
  "requiredValidations": [
    {"workflowPath": ".github/workflows/bsec-integrity.yml",
     "workflowId": 381835906,
     "workflowIdObservation": {"value": 409432614, "observedAt": "2026-11-07T05:23:47Z"},
     "job": "bsec-integrity"}
  ],
  "requiredWorkflowDetection": {"verdictJob": "admission-check"}
}
""")
    let b = policyWorkflowBindings(both)
    check b.kind == wbkUnreadable

  test "an unknown declaration shape is unreadable (fail-closed)":
    let alien = MIRROR.replace(
      "seq[tuple[jobName: string, workflowPath: string]]",
      "seq[tuple[jobName: string, checksum: string]]")
    let b = mergeCliWorkflowBindings(alien)
    check b.kind == wbkUnreadable

  test "a malformed workflowIdObservation is fail-closed, never 'unobserved'":
    let malformed = parseJson("""
{
  "requiredValidations": [
    {"workflowPath": ".github/workflows/bsec-integrity.yml",
     "workflowIdObservation": {"value": "not-an-int", "observedAt": "x"},
     "job": "bsec-integrity"}
  ],
  "requiredWorkflowDetection": {"verdictJob": "admission-check"}
}
""")
    let b = policyWorkflowBindings(malformed)
    check b.kind == wbkUnreadable
