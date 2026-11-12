## tools/merge_ruleset_drift_monitor.nim — live GitHub ruleset drift monitor
## for the auto-merge admission authority.
##
## Compares the LIVE state of the repository ruleset "main"
## (repo Archright/Axiom) against the EXPECTED rule set, and prints one
## OK/DRIFT line per rule plus a summary. Any DRIFT -> exit 1; any
## fetch/parse failure -> FAIL (fail-closed, exit 1). PASS is only ever
## the result of the live state matching every expectation.
##
## RULESET IDENTITY (hybrid authority rotation, policy v1.19.0,
## 2026-11-07): the ruleset is identified by NAME RESOLUTION, not by a
## hardcoded numeric id. The pre-rotation constant 20303214 belonged to
## the OLD repository (now <legacy-repo>) and 404s under the
## recreated repository — the GPA L2 leg and this monitor's default live
## fetch would have failed closed on the stale id. Resolution semantics
## (identical in the GPA workflow and landing_observe.sh — one judgment
## meaning across Nim/YAML/Shell):
##   - input: the COMPLETE paginated ruleset list
##     (GET repos/<repo>/rulesets?includes_parents=true, all pages);
##     an incomplete page run is UNKNOWN, never an empty result;
##   - selection conditions (all): name == "main" AND enforcement ==
##     "active" AND target == "branch" AND source is REPOSITORY level
##     (== the repo's own full name — org rulesets excluded) AND the
##     detail's conditions target refs/heads/main AND the
##     required_status_checks configuration matches the policy-derived
##     expected context set (app-level producer control included);
##   - cross-validation: the ruleset_id appears in the
##     GET repos/<repo>/rules/branches/main response;
##   - verdict: exactly 1 match -> resolved; 0 or 2+ -> fail-closed
##     (DRIFT — the admission surface is absent or ambiguous);
##     fetch failure / incomplete pagination -> UNKNOWN (explicitly
##     labelled, distinct from a zero-match REJECTED).
## The m7 canary guard (tools/ci/m7_canary_drill.sh) is deliberately
## EXEMPT from this dynamic resolution: its PROD_RULESET_ID is a Trust
## Anchor constant (26702792) — a canary must never discover its own
## protection target at runtime.
##
## EXPECTED ruleset semantics (binding): the ruleset is the merge-admission
## authority surface for refs/heads/main. It must enforce, per the
## auto-merge trust-surface policy — config/policy/merge_admission.json
## (the MACHINE-READABLE NORMATIVE SSOT; ADR-0035 records the rationale) and
## the derived identity mirror in src/cli/merge_cli.nim (RequiredChecks /
## RequiredWorkflowIds):
##   - merge_queue                with parameters.merge_method == "MERGE"
##                                (the automatic landing path);
##   - required_status_checks     EXACTLY the policy-derived context set —
##                                the LIVE three (ADR-0035, 2026-10-21):
##                                  "admission-check"     = merge eligibility
##                                    / trust-boundary verdict (produced by
##                                    the ORG-INJECTED workflow
##                                    Archright/.github admission-gate-v2.yml —
##                                    workflow_id 386419787, repository_id
##                                    1182157951 — see the policy SSOT's
##                                    requiredWorkflowDetection);
##                                  "bsec-integrity"      = record integrity
##                                    of the D2 verdict protocol
##                                    (derived == recorded == ledger heads)
##                                    ONLY — never a verdict GO;
##                                  "debt-registry-gate"  = the debt registry
##                                    contract gate (repo-native producer,
##                                    workflow_id 389486255).
##                                The expected set is DERIVED from the policy
##                                SSOT (requiredValidations[].job UNION
##                                requiredWorkflowDetection.verdictJob) — never
##                                hardcoded here — so the monitor, the policy
##                                and the compile-time constants are checked
##                                against ONE source. Fail-closed on the
##                                ABSENCE of any expected context and on any
##                                unexpected extra context ("exactly these");
##   - pull_request               with required_approving_review_count == 0
##                                (zero approving count is intentional: the
##                                adopted policy requires no review-based
##                                human gate);
##   - merge_queue                with parameters.grouping_strategy ==
##                                "ALLGREEN" — every required check in the
##                                group must be GREEN (ADR-0032 (e) policy
##                                layer; HEADGREEN is forbidden because a
##                                group > 1 would make the (B, H_PR)
##                                certification subject partial).
##
## APP-LEVEL PRODUCER CONTROL (part of expectation 2): every required-status-
## checks entry must carry integration_id == 15368 (the GitHub Actions App).
## That is the platform's app-level producer control — only a check-run
## produced by the Actions app can satisfy such a context. It does NOT close
## the within-Actions same-name residual (a PR-side workflow may define a job
## with the same name); that residual is closed on the Axiom side by the
## policy SSOT's recorded workflow-identity bindings (requiredValidations
## path + workflowId + job) — a RECORDED mirror for judgment reference, NOT a
## merge-time re-verification (P12 delegation retained: the admission
## predicate deliberately does not collect check-runs nor re-verify producer
## identity — ADR-0025 Amendment B / ADR-0035 §1).
##
## THREE LEGS (ADR-0035 §3 — three copies of one fact are not an SSOT; the
## monitor is the three-way checker):
##   leg 1  policy <-> constants  (STATIC; no credential): the compiled-in
##          RequiredChecks / RequiredWorkflowIds of src/cli/merge_cli.nim must
##          equal the policy-derived expectation set and the policy's
##          requiredValidations bindings — DUAL-SHAPE (v1.19.1): on the
##          binding axis BOTH sides declare, workflowPath (v1.19.0) or the
##          legacy integer workflowId; a shape mismatch between the sides is
##          DRIFT, never a cross-shape misparse. Always performed.
##   leg 2  policy <-> live ruleset (read via the native GitHub client; the
##          job's own GITHUB_TOKEN suffices — measured 2026-10-21, run
##          39603184495: ruleset drift 4/4 PASS with that token): the four
##          normative expectations above.
##   leg 3  policy <-> live producer (--observe-sha <sha>; checks:read): the
##          check-runs of an observed SHA must carry every expected context,
##          each produced by the expected App (id/slug). A context produced by
##          a DIFFERENT app is a same-name spoof signal -> DRIFT; a context
##          with NO check-run at the observed SHA -> DRIFT (missing != clean).
## A leg that could not be performed is reported as NOT PERFORMED with its
## reason — explicitly, never silently skipped. By default an unperformable
## leg 2 is a FAIL (fail-closed); --allow-unavailable-ruleset downgrades it
## to an explicitly-labelled DEGRADED MODE in which leg 3 (and leg 1) decide
## the verdict.
##
## DRIFT DETECTION IS NOT MERGE-TIME ENFORCEMENT: this monitor is post-hoc
## monitoring (ADR-0035 §4). Merge-time enforcement stays with the platform
## (the ruleset's required status checks + the org ruleset's sha-pinned
## workflows rule). The monitor never blocks a merge and never mutates any
## GitHub state — it only GETs and judges.
##
## NOT expectations (semantics fix 2026-10-12 — parameter-role table in
## docs/spec/github_delegation_residuals.md R2): max_entries_to_build (the
## concurrent check/build throttle for merge_group webhooks — NOT a
## group-size guarantee) and max_entries_to_merge (upper bound on PRs merged
## together). Neither carries the ALLGREEN + 1:1 policy: the 1:1 shape is
## enforced structurally — merge_group event parent relation, PR identity,
## candidate-tree equivalence — never by these config values. Configuration
## monitoring is NOT shape enforcement (authority layering,
## docs/agents/rules_workflow.md: "Never describe both as the same
## boundary").
##
## WHY require_code_owner_review is NOT an expectation (adopted policy
## 2026-09-30, "Axiom-controlled auto-land exclusion"): the org has exactly
## one human — the author is the sole architect — so any required review
## (code-owner or otherwise) would be a self-approval deadlock. The
## platform therefore keeps require_code_owner_review == false: normal PRs
## land through GitHub's merge queue + the `admission-check` required status
## check, while trust-surface PRs are routed to human manual merge.
## Independent third-party approval was never a documented policy
## requirement; the live `false` value is the adopted state, not drift.
##
## LATENT require_extra_approval_for_unattributed_changes (documentation only
## 2026-09-30 — deliberately NOT one of the monitor's expectations): the live ruleset
## also carries require_extra_approval_for_unattributed_changes == true, which is inert at
## required_approving_review_count == 0. Official semantics (GitHub
## Docs, "Available rules for rulesets"): when a pull request isn't attributed
## to a person, "the ruleset requires one more approval than the number you
## configured" and "This setting has no effect if the ruleset requires zero
## approvals" (https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets).
## CAUTION: if required_approving_review_count is ever deliberately raised to
## >= 1, this flag silently activates — unattributed commits (our CI/agent
## commits are authored "Axiom Agent <axiom@axiom.dev>") would need +1 approval
## and could auto-stall landings. Any change that raises the count must revisit
## this flag in the same change.
##
## NOTE: expectations track the ADOPTED policy — never the live state. If a
## second architect ever exists, ADR-0024's switch clause would re-introduce
## code-owner enforcement; re-adding require_code_owner_review == true here
## would then be a deliberate, policy-driven expectation change, not a fix
## to match live state.
##
## Live state is fetched with the native GitHub client only:
##   gh api --paginate --slurp "repos/Archright/Axiom/rulesets?includes_parents=true&per_page=100"
##   gh api repos/Archright/Axiom/rulesets/<resolved-id>   (per-candidate detail)
##   gh api repos/Archright/Axiom/rules/branches/main      (cross-validation)
## (credential contract — M7 no-fallback, docs/spec/diagnostic_execution_delegation.md
## §4: AXIOM_DIAG_TOKEN, when explicitly set, is injected as GH_TOKEN and used for
## the fetch — in the delegated workflow this is the in-job minted read-only
## installation token. AXIOM_DIAG_STRICT=1 refuses the `gh auth` fallback
## (operator PAT) — fail closed. Without strict mode the `gh auth` fallback stays
## but its source is printed (never silent). Explicitly provisioned secrets only —
## no credential discovery, AGENTS.md §2.4).
##
## CLI:
##   nim c -r tools/merge_ruleset_drift_monitor.nim \
##       [--ruleset-file <path>] [--policy-file <path>] \
##       [--merge-cli-source <path>] [--repo <owner/repo>] \
##       [--ruleset-id <id>] [--observe-sha <sha>] [--allow-unavailable-ruleset]
## --ruleset-file reads a ruleset JSON from disk (offline runs / fixtures);
## the default is a live name resolution (see RULESET IDENTITY above) of the
## repository ruleset "main" via `gh api` (paginated list + per-candidate
## detail + rules/branches/main cross-validation). --ruleset-id overrides the
## resolution and fetches that exact id (operator pin / reproduction).
## --policy-file selects the policy SSOT the expected context set is derived
## from (default: config/policy/merge_admission.json, resolved relative to the
## working directory — the same CWD-relative resolution the admission
## predicate uses for its trust-surface load).
## --merge-cli-source selects the compiled-in constant mirror leg 1 compares
## the policy against (default: src/cli/merge_cli.nim).
## --observe-sha enables leg 3 (the producer observation) on that SHA.
## --allow-unavailable-ruleset downgrades an unperformable live ruleset read
## to an explicitly-labelled DEGRADED MODE instead of a hard failure.
## Exit codes: 0 = all performed legs hold, 1 = drift or fetch/parse failure.

import std/[algorithm, json, os, osproc, sets, strutils]
import api/tools_facade

const
  DefaultRulesetRepo* = "Archright/Axiom"
  ## The merge-admission ruleset NAME — the resolution key (hybrid authority
  ## rotation, policy v1.19.0, 2026-11-07). The pre-rotation numeric constant
  ## 20303214 belonged to the OLD repository (preserved as
  ## <legacy-repo>) and 404s under the recreated repository; the
  ## live id is discovered per run by resolveMainRuleset (26702792 as
  ## measured 2026-11-07 — the observed-at record lives in the policy SSOT,
  ## not in this code).
  DefaultRulesetName* = "main"
  ## The default branch whose rules the resolved ruleset must target
  ## (cross-validation endpoint: repos/<repo>/rules/branches/main).
  DefaultBranchName* = "main"
  ## The normative policy SSOT the expected context set is derived from.
  DefaultPolicyPath* = "config/policy/merge_admission.json"
  ## The compiled-in constant mirror the policy is compared against
  ## (src/cli/merge_cli.nim RequiredChecks / RequiredWorkflowIds).
  DefaultMergeCliSource* = "src/cli/merge_cli.nim"
  ## The GitHub Actions App id — the app-level producer control carried by
  ## every required_status_checks entry of the live ruleset (measured
  ## 2026-10-21: integration_id 15368 on all three contexts). Platform
  ## constant, NOT a policy value: it identifies the PRODUCING APP, not a
  ## repository-owned rule.
  ExpectedActionsAppId* = 15368
  ## Actionable guidance printed whenever any expectation drifts: until the
  ## ruleset matches EXPECTED, trust-surface PRs must not ride the
  ## auto-merge queue — they are merged by humans.
  # <!-- monitor-purity:begin --> operator remediation string — legitimate
  # mention of the manual-merge command; the monitor itself only GETs
  SuggestionText* =
    "SUGGESTION: ruleset drift — trust-surface PRs must stay out of the " &
    "auto-merge queue until the ruleset matches EXPECTED; merge them " &
    "manually: `gh pr merge <N> --disable-auto` (see docs/agents/operations.md)"
  # <!-- monitor-purity:end -->
  ## Total number of EXPECTED ruleset expectations judged by
  ## judgeRulesetDrift. The unparsable-structure path reports 0 against this
  ## total, so the expectation count cannot silently rot.
  NumExpectations = 4

type
  DriftResult* = object
    ok*: bool
    lines*: seq[string]   ## per-rule OK/DRIFT lines, fixed judgment order
    summary*: string      ## one-line summary ("<holds>/<NumExpectations>
                          ## expectations hold")
    suggestion*: string   ## non-empty iff ok == false

  ## One required_status_checks entry of the live ruleset — the context name
  ## plus the producing App id (integration_id). integrationId == -1 means
  ## the entry carried no integration_id (older response shape).
  StatusEntry* = object
    context*: string
    integrationId*: int

  ## Outcome of the name-based ruleset resolution (hybrid authority
  ## rotation, policy v1.19.0). UNKNOWN is a distinct verdict from REJECTED:
  ## an unreadable/incomplete observation can never be read as "no ruleset
  ## matches" (missing != clean — the same fail-closed distinction the
  ## producer observation makes).
  RulesetResolutionStatus* = enum
    rrsResolved   ## exactly one ruleset satisfies every selection condition
    rrsRejected   ## zero or 2+ matches — fail-closed (absent or ambiguous)
    rrsUnknown    ## the observation itself is unusable (fetch failure /
                  ## incomplete pagination / unparsable payload)

  ## The resolution verdict: `rulesetId`/`detail` are valid iff
  ## status == rrsResolved; `lines` always carry the explicit per-stage
  ## reasoning (never silent).
  RulesetResolution* = object
    status*: RulesetResolutionStatus
    rulesetId*: int
    detail*: JsonNode
    lines*: seq[string]

  ## One per-candidate ruleset detail as fetched at the I/O boundary. `body`
  ## is valid iff ok (the fetch result text parsed; parsing happens at the
  ## boundary so the pure core never raises).
  RulesetDetailFetch* = object
    id*: int
    ok*: bool
    body*: JsonNode

  ## The identity-binding axis of ONE side of the policy <-> constants
  ## mirror (dual-shape, monitor v1.19.1, 2026-11-07). The hybrid authority
  ## rotation lands in two steps — the judge's monitor first, the constants
  ## second — so between the landings the BASE tree carries a v1.19.0
  ## monitor over legacy constants, and the standing monitor must adjudicate
  ## BOTH shapes coherently instead of misparsing the legacy tuple
  ## initializer (the misparse paired ADJACENT job names — bsec-integrity@
  ## debt-registry-gate — and self-test-failed the driver: PR #6 run
  ## 42359181261, L4 known-good rc=1).
  WorkflowBindingKind* = enum
    wbkUnreadable  ## neither binding axis detected — fail-closed
    wbkLegacyInt   ## (jobName, workflowId: int) — the pre-rotation axis
    wbkPath        ## (jobName, workflowPath: string) — the v1.19.0 axis

  ## Shape-tagged identity bindings of one mirror side. Exactly the seq
  ## matching `kind` is populated; the other stays empty.
  WorkflowBindings* = object
    kind*: WorkflowBindingKind
    legacyInt*: seq[tuple[jobName: string, workflowId: int]]
    paths*: seq[tuple[jobName: string, workflowPath: string]]

# ---------------------------------------------------------------------------
# Pure core
# ---------------------------------------------------------------------------

func firstLine(text: string): string {.raises: [].} =
  ## Pure: the first non-empty line of `text` (single-line rendering of a
  ## multi-line tool error — the messages are embedded in one output line).
  for ln in text.splitLines():
    let s = ln.strip()
    if s.len > 0:
      return s
  ""

func child(node: JsonNode; key: string): JsonNode {.raises: [].} =
  ## Non-raising field access: nil when `node` is not an object or `key` is
  ## absent. std/json `[]`(name) raises KeyError, which the {.raises: [].}
  ## contract forbids, so the object's own pairs iterator is used.
  if node.isNil or node.kind != JObject:
    return nil
  for k, v in node:
    if k == key:
      return v
  nil

func ruleOfType*(ruleset: JsonNode; ruleType: string): JsonNode {.raises: [].} =
  ## Pure: the first ruleset rule whose `type` equals `ruleType`, else nil.
  let rules = child(ruleset, "rules")
  if rules.isNil or rules.kind != JArray:
    return nil
  for r in rules:
    if r.kind != JObject:
      continue
    let t = child(r, "type")
    if not t.isNil and t.kind == JString and t.getStr() == ruleType:
      return r
  nil

func statusEntries*(params: JsonNode): seq[StatusEntry] {.raises: [].} =
  ## Pure: the required_status_checks entries with their producing App id.
  ## Live entries are objects {"context": ..., "integration_id": ...}; older
  ## responses use plain strings (no App id -> -1). Missing/malformed -> @[].
  let arr = child(params, "required_status_checks")
  result = @[]
  if arr.isNil or arr.kind != JArray:
    return
  for e in arr.items:
    if e.isNil:
      continue
    if e.kind == JString:
      result.add(StatusEntry(context: e.getStr(), integrationId: -1))
    elif e.kind == JObject:
      let c = child(e, "context")
      if not c.isNil and c.kind == JString:
        var iid = -1
        let i = child(e, "integration_id")
        if not i.isNil and i.kind == JInt:
          iid = i.getInt()
        result.add(StatusEntry(context: c.getStr(), integrationId: iid))

func statusContexts*(params: JsonNode): seq[string] {.raises: [].} =
  ## Pure: all required_status_checks contexts, in live order. Live entries
  ## are objects {"context": ..., "integration_id": ...}; older responses use
  ## plain strings — both shapes are collected. Missing/malformed -> @[].
  for e in statusEntries(params):
    result.add(e.context)

func hasStatusContext*(params: JsonNode; ctx: string): bool {.raises: [].} =
  ## Pure: does parameters.required_status_checks contain `ctx`? Retained
  ## helper — shape handling lives in statusEntries; the drift judgment
  ## itself uses the context set for the exact-set expectation.
  for c in statusContexts(params):
    if c == ctx:
      return true
  false

func expectedStatusContexts*(policy: JsonNode): seq[string] {.raises: [].} =
  ## Pure: the NORMATIVE required-check context set derived from the policy
  ## SSOT (config/policy/merge_admission.json v1.15.0, ADR-0035):
  ##   requiredValidations[].job  UNION  requiredWorkflowDetection.verdictJob
  ## The union is the point: the repo-native producers are recorded as
  ## requiredValidations entries (path + workflowId + job), while the
  ## org-injected producer of the 'admission-check' context is recorded as
  ## requiredWorkflowDetection (repository id + path + verdictJob) — the
  ## callee admission-check.yml (workflowId 365692388) never emits a
  ## check-run named 'admission-check', so it is not (and must not be) a
  ## requiredValidations entry.
  ## Result: byte-sorted, duplicate-free. Empty = the policy carries no
  ## expectation — the caller fails closed (an empty expectation set would
  ## trivially "match" any live set).
  var seen = initHashSet[string]()
  var contexts: seq[string] = @[]
  let rv = child(policy, "requiredValidations")
  if not rv.isNil and rv.kind == JArray:
    for entry in rv.items:
      if entry.isNil or entry.kind != JObject:
        continue
      let job = child(entry, "job")
      if not job.isNil and job.kind == JString and job.getStr().len > 0:
        if job.getStr() notin seen:
          seen.incl(job.getStr())
          contexts.add(job.getStr())
  let rwd = child(policy, "requiredWorkflowDetection")
  if not rwd.isNil and rwd.kind == JObject:
    let vj = child(rwd, "verdictJob")
    if not vj.isNil and vj.kind == JString and vj.getStr().len > 0:
      if vj.getStr() notin seen:
        seen.incl(vj.getStr())
        contexts.add(vj.getStr())
  contexts.sort()
  contexts

func contextList(contexts: seq[string]): string {.raises: [].} =
  ## Pure: render an expectation set for a message.
  if contexts.len == 0:
    "<empty>"
  else:
    "{" & contexts.join(", ") & "}"

# ---------------------------------------------------------------------------
# Ruleset name resolution (hybrid authority rotation, policy v1.19.0)
# ---------------------------------------------------------------------------

func flattenRulesetPages*(pages: JsonNode): seq[JsonNode] {.raises: [].} =
  ## Pure: the ruleset entries of a paginated list read. Accepts both shapes
  ## the boundary can produce: a flattened array of rule objects, or the
  ## `gh api --paginate --slurp` array-of-pages (array of arrays). Any other
  ## shape -> @[] (the caller treats a non-array payload as UNKNOWN, never
  ## as an empty list — incomplete != empty).
  if pages.isNil or pages.kind != JArray:
    return
  for e in pages.items:
    if e.isNil:
      continue
    if e.kind == JObject:
      result.add(e)
    elif e.kind == JArray:
      for inner in e.items:
        if not inner.isNil and inner.kind == JObject:
          result.add(inner)

func listLevelMatch*(entry: JsonNode; repoFullName: string): bool {.raises: [].} =
  ## Pure: the LIST-level selection conditions — name == "main" AND
  ## enforcement == "active" AND target == "branch" AND source is
  ## REPOSITORY level (== the repository's own full name; org-level
  ## rulesets carry the bare org name and are excluded).
  if entry.isNil or entry.kind != JObject:
    return false
  let name = child(entry, "name")
  let enf = child(entry, "enforcement")
  let tgt = child(entry, "target")
  let src = child(entry, "source")
  if name.isNil or name.kind != JString or name.getStr() != DefaultRulesetName:
    return false
  if enf.isNil or enf.kind != JString or enf.getStr() != "active":
    return false
  if tgt.isNil or tgt.kind != JString or tgt.getStr() != "branch":
    return false
  if src.isNil or src.kind != JString or src.getStr() != repoFullName:
    return false
  true

func listLevelCandidateIds*(pages: JsonNode; repoFullName: string): seq[int] {.raises: [].} =
  ## Pure: the ids of the list-level candidates (name/enforcement/target/
  ## source) of a paginated ruleset read — the ids whose details the I/O
  ## boundary must fetch before the full resolution verdict can run.
  for e in flattenRulesetPages(pages):
    if listLevelMatch(e, repoFullName):
      let rid = child(e, "id")
      if not rid.isNil and rid.kind == JInt:
        result.add(rid.getInt())

func conditionsTargetMain*(detail: JsonNode): bool {.raises: [].} =
  ## Pure: does the ruleset DETAIL's conditions target refs/heads/main?
  ## The ref_name include list must carry the default-branch token
  ## ("~DEFAULT_BRANCH") or the literal ref ("refs/heads/main") — both
  ## denote refs/heads/main while main is the default branch. A missing or
  ## differently-scoped conditions block fails the condition (fail-closed:
  ## the selection must observe its target, never assume it).
  if detail.isNil or detail.kind != JObject:
    return false
  let cond = child(detail, "conditions")
  if cond.isNil or cond.kind != JObject:
    return false
  let refName = child(cond, "ref_name")
  if refName.isNil or refName.kind != JObject:
    return false
  let incl = child(refName, "include")
  if incl.isNil or incl.kind != JArray:
    return false
  for t in incl.items:
    if not t.isNil and t.kind == JString and
        (t.getStr() == "~DEFAULT_BRANCH" or t.getStr() == "refs/heads/main"):
      return true
  false

func requiredChecksMatchPolicy*(detail: JsonNode;
                                expectedContexts: seq[string]): bool {.raises: [].} =
  ## Pure: does the ruleset DETAIL's required_status_checks configuration
  ## match the policy-derived expectation — the exact context set AND the
  ## app-level producer control (integration_id == the Actions App) on
  ## every entry? This is the same judgment expectation 2 of
  ## judgeRulesetDrift makes; the resolution runs it as a SELECTION
  ## condition (the resolved ruleset is THE admission surface, so a drifted
  ## configuration is a failed selection, judged below as DRIFT).
  let rsc = ruleOfType(detail, "required_status_checks")
  if rsc.isNil:
    return false
  var entries: seq[StatusEntry] = @[]
  let params = child(rsc, "parameters")
  if not params.isNil:
    entries = statusEntries(params)
  if entries.len != expectedContexts.len:
    return false
  var seen = initHashSet[string]()
  for e in entries:
    if e.context notin expectedContexts:
      return false
    if e.integrationId != ExpectedActionsAppId:
      return false
    seen.incl(e.context)
  seen.len == expectedContexts.len

func branchRulesMentionRuleset*(branchRules: JsonNode; rulesetId: int): bool {.raises: [].} =
  ## Pure: does the rules/branches/main response (the merged rule list of
  ## every ruleset applying to that branch) mention the ruleset id — the
  ## cross-validation that the resolved ruleset actually applies to
  ## refs/heads/main?
  if branchRules.isNil or branchRules.kind != JArray:
    return false
  for r in branchRules.items:
    if r.isNil or r.kind != JObject:
      continue
    let rid = child(r, "ruleset_id")
    if not rid.isNil and rid.kind == JInt and rid.getInt() == rulesetId:
      return true
  false

func resolveMainRuleset*(pages: JsonNode; complete: bool;
                         details: seq[RulesetDetailFetch];
                         branchRules: JsonNode;
                         expectedContexts: seq[string];
                         repoFullName: string): RulesetResolution {.raises: [].} =
  ## Pure: the name-resolution verdict (RULESET IDENTITY semantics above).
  ## Deterministic stage order — incomplete pagination -> unparsable list ->
  ## list-level candidates -> per-candidate detail availability -> full
  ## selection conditions -> branch cross-validation -> count verdict.
  ## Every stage's outcome is recorded in `lines` explicitly.
  template unknown(reason: string) =
    result.status = rrsUnknown
    result.lines.add("UNKNOWN ruleset resolution: " & reason)
  template rejected(reason: string) =
    result.status = rrsRejected
    result.lines.add("REJECTED ruleset resolution: " & reason)

  if not complete:
    unknown("ruleset list pagination is INCOMPLETE — no judgment is possible " &
      "(an incomplete read is never an empty result)")
    return
  if pages.isNil or pages.kind != JArray:
    unknown("ruleset list payload is unparsable (not a JSON array)")
    return
  let entries = flattenRulesetPages(pages)
  result.lines.add("ruleset list: " & $entries.len & " entr" &
    (if entries.len == 1: "y" else: "ies") & " read (complete)")

  # stage 1 — list-level candidates
  let candIds = listLevelCandidateIds(pages, repoFullName)
  if candIds.len == 0:
    rejected("zero list-level candidates (name=\"" & DefaultRulesetName &
      "\", enforcement=active, target=branch, source=" & repoFullName &
      ") — the admission ruleset is ABSENT")
    return
  var candTexts: seq[string] = @[]
  for cid in candIds:
    candTexts.add($cid)
  result.lines.add("list-level candidates: " & candTexts.join(", "))

  # stage 2 — every candidate's detail must be readable (else UNKNOWN)
  for cid in candIds:
    var found = false
    for d in details:
      if d.id == cid:
        found = true
        if not d.ok or d.body.isNil:
          unknown("ruleset detail fetch failed for candidate " & $cid &
            " — the selection conditions cannot be evaluated")
          return
        break
    if not found:
      unknown("ruleset detail missing for candidate " & $cid &
        " — the selection conditions cannot be evaluated")
      return

  # stage 3 — the detail-level selection conditions (conditions + policy
  # check) on each candidate; the branch cross-validation runs only for the
  # survivors and its READ AVAILABILITY is checked first — an unavailable
  # cross-validation is UNKNOWN (could not confirm), distinct from an id
  # absent from the response (excluded).
  var conditional: seq[RulesetDetailFetch] = @[]
  for cid in candIds:
    for d in details:
      if d.id != cid:
        continue
      if not conditionsTargetMain(d.body):
        result.lines.add("candidate " & $cid & ": conditions do not target " &
          "refs/heads/main — excluded")
      elif not requiredChecksMatchPolicy(d.body, expectedContexts):
        result.lines.add("candidate " & $cid & ": required_status_checks " &
          "!= policy expectation " & contextList(expectedContexts) &
          " — excluded (drift; judged in detail by the ruleset leg)")
      else:
        conditional.add(d)
      break
  if conditional.len > 0 and (branchRules.isNil or branchRules.kind != JArray):
    unknown("rules/branches/" & DefaultBranchName & " cross-validation read " &
      "unavailable — the applicability of the surviving candidate(s) cannot " &
      "be confirmed")
    return
  var matched: seq[RulesetDetailFetch] = @[]
  for d in conditional:
    if not branchRulesMentionRuleset(branchRules, d.id):
      result.lines.add("candidate " & $d.id & ": ruleset_id absent from " &
        "rules/branches/" & DefaultBranchName & " — cross-validation failed, " &
        "excluded")
    else:
      result.lines.add("candidate " & $d.id & ": all selection conditions " &
        "hold (cross-validated via rules/branches/" & DefaultBranchName & ")")
      matched.add(d)

  if matched.len == 1:
    result.status = rrsResolved
    result.rulesetId = matched[0].id
    result.detail = matched[0].body
    result.lines.add("RESOLVED ruleset " & DefaultRulesetName & " = id " &
      $matched[0].id)
  elif matched.len == 0:
    rejected("zero candidates satisfy ALL selection conditions (see per-" &
      "candidate exclusions above)")
  else:
    var ids: seq[string] = @[]
    for m in matched:
      ids.add($m.id)
    rejected("candidates " & ids.join(", ") & " ALL satisfy the selection " &
      "conditions — the admission surface is AMBIGUOUS (2+ matches)")

func policyWorkflowBindings*(policy: JsonNode): WorkflowBindings {.raises: [].} =
  ## Pure: the policy SSOT's requiredValidations identity bindings,
  ## shape-tagged (dual-shape, v1.19.1). Since the hybrid authority rotation
  ## (policy v1.19.0, 2026-11-07) workflowPath is the PRIMARY identifier —
  ## a repository-scoped numeric workflow id is not stable across repository
  ## recreation (measured: all four pre-migration ids 404 under the recreated
  ## repository), so the id survives only as `workflowIdObservation {value,
  ## observedAt}` — an observed-at record, never a binding. A policy still
  ## carrying the legacy integer `workflowId` binding (the pre-rotation
  ## shape) is adjudicated on that axis. Every entry must carry the SAME
  ## axis — mixed or absent axes are unreadable (fail-closed, the same
  ## mixed-shape rule the .github merge-admission-sanity judge applies to
  ## the policy file).
  result.kind = wbkUnreadable
  let rv = child(policy, "requiredValidations")
  if rv.isNil or rv.kind != JArray or rv.len == 0:
    return
  var sawPath = false
  var sawLegacy = false
  for entry in rv.items:
    if entry.isNil or entry.kind != JObject:
      return
    let job = child(entry, "job")
    if job.isNil or job.kind != JString or job.getStr().len == 0:
      return
    let obs = child(entry, "workflowIdObservation")
    let wid = child(entry, "workflowId")
    let obsShaped = not obs.isNil and obs.kind == JObject
    let legacyShaped = not wid.isNil and wid.kind == JInt
    if obsShaped and legacyShaped:
      return ## one entry carrying BOTH axes is ambiguous — unreadable
    if obsShaped:
      ## a present observation must be well-formed (value:int, observedAt:
      ## non-empty) — garbage is fail-closed, never read as "unobserved".
      let value = child(obs, "value")
      let stamp = child(obs, "observedAt")
      if value.isNil or value.kind != JInt:
        return
      if stamp.isNil or stamp.kind != JString or stamp.getStr().len == 0:
        return
    if legacyShaped:
      sawLegacy = true
      result.legacyInt.add((job.getStr(), wid.getInt()))
    else:
      ## obsAxis (validated above) or the null/absent pre-push placeholder —
      ## either way THIS entry's binding axis is the workflowPath.
      let path = child(entry, "workflowPath")
      if path.isNil or path.kind != JString or path.getStr().len == 0:
        return
      sawPath = true
      result.paths.add((job.getStr(), path.getStr()))
  if sawPath and not sawLegacy:
    result.kind = wbkPath
  elif sawLegacy and not sawPath:
    result.kind = wbkLegacyInt
  else:
    result.paths = @[]
    result.legacyInt = @[]

func mergeCliRequiredChecks*(source: string): seq[string] {.raises: [].} =
  ## Pure: the RequiredChecks initializer of src/cli/merge_cli.nim parsed as
  ## context names. Textual, regex-free scan (the same technique
  ## tools/ci/proof_unit_consistency_gate.nim uses on the same file) — the
  ## mirror under comparison is the COMPILED-IN constant seen as SOURCE, so
  ## the leg compares policy ↔ source, not policy ↔ binary.
  let mark = source.find("RequiredChecks*: seq[string]")
  if mark < 0:
    return
  let arr = source.find("@[", mark)
  if arr < 0:
    return
  var i = arr + 2
  while i < source.len and source[i] != ']':
    if source[i] == '"':
      let start = i + 1
      var j = start
      while j < source.len and source[j] != '"':
        inc j
      if j < source.len:
        result.add(source[start ..< j])
        i = j + 1
        continue
    inc i

func mergeCliWorkflowBindings*(source: string): WorkflowBindings {.raises: [].} =
  ## Pure: the RequiredWorkflowIds initializer of src/cli/merge_cli.nim,
  ## shape-tagged by its TUPLE DECLARATION (dual-shape, v1.19.1). The
  ## declaration names the binding axis — `workflowPath: string` (v1.19.0)
  ## or `workflowId: int` (legacy) — so the entry parse is never guessed
  ## from initializer contents: a legacy `("job", 381835906)` entry parsed
  ## as two quoted strings silently pairs ADJACENT job names (the misparse
  ## measured 2026-11-07: bsec-integrity@debt-registry-gate — a false DRIFT
  ## that self-test-failed the driver). The block keeps its historical name
  ## RequiredWorkflowIds because proof_unit_consistency_gate (f.3) pins that
  ## identifier as the standing non-emptiness invariant.
  result.kind = wbkUnreadable
  let mark = source.find("RequiredWorkflowIds*: seq[tuple")
  if mark < 0:
    return
  let declEnd = source.find("]]", mark)
  if declEnd < 0:
    return
  let decl = source[mark ..< declEnd]
  if decl.contains("workflowPath: string"):
    result.kind = wbkPath
  elif decl.contains("workflowId: int"):
    result.kind = wbkLegacyInt
  else:
    return ## an unknown declaration shape is unreadable — fail-closed
  let arr = source.find("@[", mark)
  if arr < 0 or arr < declEnd:
    return ## no initializer following the declaration — unreadable
  case result.kind
  of wbkLegacyInt:
    var i = arr + 2
    while i < source.len and source[i] != ']':
      if source[i] == '(':
        let q1 = source.find('"', i)
        if q1 < 0:
          break
        let q2 = source.find('"', q1 + 1)
        if q2 < 0:
          break
        var numStart = q2 + 1
        while numStart < source.len and source[numStart] notin {'0'..'9'}:
          inc numStart
        var numEnd = numStart
        while numEnd < source.len and source[numEnd] in {'0'..'9'}:
          inc numEnd
        if numEnd == numStart:
          break
        var wid = 0
        for k in numStart ..< numEnd:
          wid = wid * 10 + (ord(source[k]) - ord('0'))
        result.legacyInt.add((source[q1 + 1 ..< q2], wid))
        i = numEnd
        continue
      inc i
  of wbkPath:
    var i = arr + 2
    while i < source.len and source[i] != ']':
      if source[i] == '(':
        let q1 = source.find('"', i)
        if q1 < 0:
          break
        let q2 = source.find('"', q1 + 1)
        if q2 < 0:
          break
        let q3 = source.find('"', q2 + 1)
        if q3 < 0:
          break
        let q4 = source.find('"', q3 + 1)
        if q4 < 0:
          break
        result.paths.add((source[q1 + 1 ..< q2], source[q3 + 1 ..< q4]))
        i = q4 + 1
        continue
      inc i
  of wbkUnreadable:
    discard

func bindingAxisName*(kind: WorkflowBindingKind): string {.raises: [].} =
  ## Pure: the human-facing name of a binding axis for DRIFT messages.
  case kind
  of wbkPath: "workflowPath (v1.19.0)"
  of wbkLegacyInt: "workflowId (legacy integer)"
  of wbkUnreadable: "unreadable"

func renderWorkflowBindings*(b: WorkflowBindings): string {.raises: [].} =
  ## Pure: render one mirror side's bindings for DRIFT messages — the
  ## rendering itself is the evidence of WHAT was parsed, so a misparse is
  ## visible in the message (the 2026-11-07 misparse was found exactly in
  ## such a rendered line).
  var rendered: seq[string] = @[]
  case b.kind
  of wbkPath:
    for s in b.paths:
      rendered.add(s.jobName & "@" & s.workflowPath)
  of wbkLegacyInt:
    for s in b.legacyInt:
      rendered.add(s.jobName & "@" & $s.workflowId)
  of wbkUnreadable:
    return "<unreadable>"
  if rendered.len == 0:
    return "<empty>"
  rendered.join(", ")

func judgeConstantMirror*(policy: JsonNode; mergeCliSource: string;
                          expectedContexts: seq[string]): DriftResult {.raises: [].} =
  ## Pure: the POLICY <-> CONSTANTS leg of the three-way agreement
  ## (ADR-0035 §3: policy ↔ ruleset ↔ constants — three copies of one fact
  ## are not an SSOT). Two checks:
  ##   (1) the compiled-in RequiredChecks set == the policy-derived context
  ##       set (requiredValidations[].job ∪ requiredWorkflowDetection.verdictJob);
  ##   (2) the compiled-in RequiredWorkflowIds bindings == the policy's
  ##       requiredValidations bindings, on the axis BOTH sides declare
  ##       (dual-shape, v1.19.1: workflowPath since policy v1.19.0 — the
  ##       numeric id is an observed-at record, not a binding — or the
  ##       legacy integer workflowId axis; a shape mismatch between the two
  ##       sides is DRIFT, never a cross-shape misparse).
  ## A source that carries neither declaration is DRIFT (fail-closed): an
  ## unreadable mirror must never read as "in agreement".
  let srcChecks = mergeCliRequiredChecks(mergeCliSource)
  var holds = 0
  var total = 0

  inc total
  var srcCheckSet = initHashSet[string]()
  for c in srcChecks:
    srcCheckSet.incl(c)
  var expectedSet = initHashSet[string]()
  for c in expectedContexts:
    expectedSet.incl(c)
  if srcChecks.len == 0:
    result.lines.add("DRIFT constant mirror: src/cli/merge_cli.nim declares no RequiredChecks " &
      "initializer (fail-closed — an unreadable mirror is not agreement)")
  elif srcCheckSet == expectedSet:
    result.lines.add("OK    constant mirror: RequiredChecks == policy-derived " &
      contextList(expectedContexts))
    inc holds
  else:
    result.lines.add("DRIFT constant mirror: RequiredChecks " & contextList(srcChecks) &
      " != policy-derived " & contextList(expectedContexts) & " (fail-closed)")

  inc total
  let srcB = mergeCliWorkflowBindings(mergeCliSource)
  let polB = policyWorkflowBindings(policy)
  if srcB.kind == wbkUnreadable:
    result.lines.add("DRIFT constant mirror: src/cli/merge_cli.nim declares no readable " &
      "RequiredWorkflowIds binding axis (fail-closed — an unreadable mirror is not agreement)")
  elif polB.kind == wbkUnreadable:
    result.lines.add("DRIFT constant mirror: the policy's requiredValidations carry no single " &
      "binding axis (mixed or absent identity bindings — fail-closed, the same rule the " &
      ".github merge-admission-sanity judge applies)")
  elif srcB.kind != polB.kind:
    result.lines.add("DRIFT constant mirror: binding-axis mismatch — policy binds " &
      bindingAxisName(polB.kind) & " identity [" & renderWorkflowBindings(polB) &
      "], constants bind " & bindingAxisName(srcB.kind) & " [" &
      renderWorkflowBindings(srcB) & "] (fail-closed — both sides of the mirror must " &
      "carry the same axis; a mid-rotation tree is judged on ITS OWN axis, never misparsed)")
  else:
    var allPresent: bool
    if polB.kind == wbkPath:
      allPresent = srcB.paths.len == polB.paths.len
      if allPresent:
        for s in srcB.paths:
          if s notin polB.paths:
            allPresent = false
            break
    else:
      allPresent = srcB.legacyInt.len == polB.legacyInt.len
      if allPresent:
        for s in srcB.legacyInt:
          if s notin polB.legacyInt:
            allPresent = false
            break
    if allPresent:
      result.lines.add("OK    constant mirror: RequiredWorkflowIds == policy requiredValidations " &
        "(" & bindingAxisName(polB.kind) & " — " & renderWorkflowBindings(polB) & ")")
      inc holds
    else:
      result.lines.add("DRIFT constant mirror: RequiredWorkflowIds (" &
        renderWorkflowBindings(srcB) & ") != policy requiredValidations (" &
        renderWorkflowBindings(polB) & ") (fail-closed)")

  result.summary = "constant mirror: " & $holds & "/" & $total & " checks hold"
  result.lines.add(result.summary)
  result.ok = holds == total

func liveString(jn: JsonNode): string {.raises: [].} =
  ## Pure: render a live JSON value for DRIFT messages. Arrays of status
  ## check entries render as their context names — the DRIFT line for
  ## required_status_checks is the primary context-set transition signal
  ## (ADR-0035 §3), so the live set must be observable.
  if jn.isNil:
    "<missing>"
  elif jn.kind == JString:
    jn.getStr()
  elif jn.kind == JBool:
    $jn.getBool()
  elif jn.kind == JInt:
    $jn.getInt()
  elif jn.kind == JArray:
    var parts: seq[string] = @[]
    for e in jn.items:
      if e.isNil:
        parts.add("<null>")
      elif e.kind == JString:
        parts.add(e.getStr())
      elif e.kind == JObject:
        let c = child(e, "context")
        if not c.isNil and c.kind == JString:
          parts.add(c.getStr())
        else:
          parts.add("<object>")
      else:
        parts.add("<" & $e.kind & ">")
    "[" & parts.join(", ") & "]"
  else:
    "<unexpected>"

func judgeRulesetDrift*(ruleset: JsonNode; expectedContexts: seq[string]):
    DriftResult {.raises: [].} =
  ## Pure: judge one ruleset JSON against EXPECTED. Deterministic judgment
  ## order: merge_queue (merge_method) -> required_status_checks (exact
  ## policy-derived context set + per-entry app-level producer control) ->
  ## pull_request (approving count) -> merge_queue (grouping_strategy). Any
  ## structural surprise is DRIFT (fail closed) — never silence.
  ## An EMPTY expected set is DRIFT (fail-closed): the expectation set is
  ## derived from the policy SSOT, and a policy that yields no context would
  ## vacuously "match" any live set.
  let rules = child(ruleset, "rules")
  if ruleset.isNil or ruleset.kind != JObject or rules.isNil or rules.kind != JArray:
    result.ok = false
    result.lines = @["DRIFT ruleset: unparsable structure (no rules array)"]
    result.summary = "ruleset drift: 0/" & $NumExpectations & " expectations hold"
    result.suggestion = SuggestionText
    return
  if expectedContexts.len == 0:
    result.ok = false
    result.lines = @["DRIFT ruleset: expected context set is EMPTY (policy SSOT " &
      "carries no required-check expectation — fail-closed)"]
    result.summary = "ruleset drift: 0/" & $NumExpectations & " expectations hold"
    result.suggestion = SuggestionText
    return

  result.ok = true
  var holds = 0
  var total = 0

  # 1. merge_queue with merge_method == "MERGE"
  inc total
  let mq = ruleOfType(ruleset, "merge_queue")
  if mq.isNil:
    result.lines.add("DRIFT merge_queue: rule missing (expected parameters.merge_method == \"MERGE\")")
  else:
    let mm = child(child(mq, "parameters"), "merge_method")
    if not mm.isNil and mm.kind == JString and mm.getStr() == "MERGE":
      result.lines.add("OK    merge_queue: parameters.merge_method == \"MERGE\"")
      inc holds
    else:
      result.lines.add("DRIFT merge_queue: parameters.merge_method == \"MERGE\" (live: " &
        liveString(mm) & ")")

  # 2. required_status_checks: exactly the policy-derived context set, and
  #    every entry carries the app-level producer control
  #    (integration_id == the GitHub Actions App id). Fail-closed on the
  #    ABSENCE of any expected context (the merge-eligibility verdict and the
  #    two integrity gates), on any unexpected extra context, and on an
  #    entry whose producing App differs.
  inc total
  let expectedText = contextList(expectedContexts)
  let rsc = ruleOfType(ruleset, "required_status_checks")
  if rsc.isNil:
    result.lines.add("DRIFT required_status_checks: rule missing (expected exactly " &
      expectedText & ")")
  else:
    let params = child(rsc, "parameters")
    var entries: seq[StatusEntry] = @[]
    if not params.isNil:
      entries = statusEntries(params)
    var missing: seq[string] = @[]
    var extras: seq[string] = @[]
    var appMismatch: seq[string] = @[]
    var seen = initHashSet[string]()
    for c in expectedContexts:
      var found = false
      for e in entries:
        if e.context == c:
          found = true
          if e.integrationId != ExpectedActionsAppId and c notin seen:
            seen.incl(c)
            appMismatch.add(c & " (integration_id=" & $e.integrationId & ")")
      if not found:
        missing.add(c)
    for e in entries:
      if e.context notin expectedContexts:
        extras.add(e.context)
    if missing.len == 0 and extras.len == 0 and appMismatch.len == 0:
      result.lines.add("OK    required_status_checks: exactly " & expectedText &
        " (app-level producer control: integration_id " &
        $ExpectedActionsAppId & " on every entry)")
      inc holds
    else:
      var why: seq[string] = @[]
      if missing.len > 0:
        why.add("missing context(s): " & missing.join(", "))
      if extras.len > 0:
        why.add("unexpected extra context(s): " & extras.join(", "))
      if appMismatch.len > 0:
        why.add("wrong producing App (expected integration_id " &
          $ExpectedActionsAppId & "): " & appMismatch.join(", "))
      result.lines.add("DRIFT required_status_checks: expected exactly " & expectedText &
        " — " & why.join("; ") & " (live: " & liveString(child(child(rsc,
        "parameters"), "required_status_checks")) & ")")

  # 3. pull_request: approving count == 0
  inc total
  let pr = ruleOfType(ruleset, "pull_request")
  if pr.isNil:
    result.lines.add("DRIFT pull_request: rule missing (expected required_approving_review_count == 0)")
  else:
    let params = child(pr, "parameters")
    let cnt = child(params, "required_approving_review_count")
    if not cnt.isNil and cnt.kind == JInt and cnt.getInt() == 0:
      result.lines.add("OK    pull_request: required_approving_review_count == 0")
      inc holds
    else:
      result.lines.add("DRIFT pull_request: required_approving_review_count == 0 (live: " &
        liveString(cnt) & ")")

  # 4. merge_queue with grouping_strategy == "ALLGREEN" — every required
  #    check in the group must be GREEN (ADR-0032 (e) policy layer;
  #    HEADGREEN forbidden: a group > 1 would make the (B, H_PR)
  #    certification subject partial, ADR-0027 α)
  inc total
  let gq = ruleOfType(ruleset, "merge_queue")
  if gq.isNil:
    result.lines.add("DRIFT merge_queue: rule missing (expected parameters.grouping_strategy == \"ALLGREEN\")")
  else:
    let gs = child(child(gq, "parameters"), "grouping_strategy")
    if not gs.isNil and gs.kind == JString and gs.getStr() == "ALLGREEN":
      result.lines.add("OK    merge_queue: parameters.grouping_strategy == \"ALLGREEN\"")
      inc holds
    else:
      result.lines.add("DRIFT merge_queue: parameters.grouping_strategy == \"ALLGREEN\" (live: " &
        liveString(gs) & ")")

  result.summary = "ruleset drift: " & $holds & "/" & $total & " expectations hold"
  result.lines.add(result.summary)
  if holds < total:
    result.ok = false
    result.suggestion = SuggestionText

func judgeProducerObservation*(checkRuns: JsonNode; expectedContexts: seq[string]):
    DriftResult {.raises: [].} =
  ## Pure: the ADDITIVE producer observation (not one of the four normative
  ## expectations). Reads the check-runs of an observed SHA and reports the
  ## producing App per expected context. A context whose check-run was
  ## produced by a DIFFERENT app than the expected one is a same-name spoof
  ## signal -> DRIFT. A context with NO check-run at the observed SHA ->
  ## DRIFT (the context was never produced; missing != clean).
  let arr = child(checkRuns, "check_runs")
  if arr.isNil or arr.kind != JArray:
    result.ok = false
    result.lines = @["DRIFT producer observation: unparsable check-runs payload (no check_runs array)"]
    result.summary = "producer observation: 0/" & $expectedContexts.len & " contexts observed"
    return
  # Completeness guard (fail-closed): a truncated read (pagination) must never
  # be read as "the context was never produced" — the two are different facts.
  let totalNode = child(checkRuns, "total_count")
  if not totalNode.isNil and totalNode.kind == JInt and totalNode.getInt() > arr.len:
    result.ok = false
    result.lines = @["DRIFT producer observation: incomplete check-runs read (total_count=" &
      $totalNode.getInt() & " > fetched=" & $arr.len &
      ") — a truncated read cannot decide the observation (fail-closed)"]
    result.summary = "producer observation: 0/" & $expectedContexts.len & " contexts observed"
    return
  var holds = 0
  for c in expectedContexts:
    var found = false
    var appId = -1
    var slug = ""
    for cr in arr.items:
      if cr.isNil or cr.kind != JObject:
        continue
      let name = child(cr, "name")
      if name.isNil or name.kind != JString or name.getStr() != c:
        continue
      let app = child(cr, "app")
      if not app.isNil and app.kind == JObject:
        let id = child(app, "id")
        if not id.isNil and id.kind == JInt:
          appId = id.getInt()
        let sl = child(app, "slug")
        if not sl.isNil and sl.kind == JString:
          slug = sl.getStr()
      found = true
      break
    if not found:
      result.lines.add("DRIFT producer observation: no check-run named \"" & c &
        "\" at the observed SHA (fail-closed — missing != clean)")
    elif appId != ExpectedActionsAppId:
      var slugText = ""
      if slug.len > 0:
        slugText = " (" & slug & ")"
      result.lines.add("DRIFT producer observation: context \"" & c &
        "\" was produced by app id " & $appId & slugText &
        " — expected the GitHub Actions app (id " & $ExpectedActionsAppId & ")")
    else:
      result.lines.add("OK    producer observation: context \"" & c &
        "\" produced by app id " & $appId & " (" & slug & ")")
      inc holds
  result.summary = "producer observation: " & $holds & "/" & $expectedContexts.len &
    " contexts observed"
  result.lines.add(result.summary)
  result.ok = holds == expectedContexts.len

# ---------------------------------------------------------------------------
# IO boundary
# ---------------------------------------------------------------------------

# M7 no-fallback credential guard (docs/spec/diagnostic_execution_delegation.md §4):
# AXIOM_DIAG_TOKEN = explicitly provisioned diagnostic credential (in the
# delegated workflow: the in-job minted read-only installation token — a token
# that never reaches a local machine). AXIOM_DIAG_STRICT=1 refuses the `gh auth`
# fallback (operator PAT) — fail closed. The credential source is ALWAYS printed
# (never silent). Without strict mode the `gh auth` fallback stays (§2.4 native
# client); the tool does not discover credentials anywhere.
proc resolveDiagCredential(toolName: string): tuple[token, source: string] =
  let explicit = getEnv("AXIOM_DIAG_TOKEN").strip()
  if explicit.len > 0:
    result = (explicit, "AXIOM_DIAG_TOKEN")
  elif getEnv("AXIOM_DIAG_STRICT") == "1":
    stderr.writeLine(toolName & ": FAIL — AXIOM_DIAG_TOKEN absent and AXIOM_DIAG_STRICT=1: " &
      "`gh auth` credentials (operator PAT) are refused for diagnostic execution " &
      "(M7 no-fallback — docs/spec/diagnostic_execution_delegation.md §4)")
    quit(1)
  else:
    let preexisting = getEnv("GH_TOKEN").strip()
    if preexisting.len > 0:
      result = ("", "GH_TOKEN (pre-set in the environment — e.g. the job's own GITHUB_TOKEN; " &
        "NOT a diagnostic credential)")
    else:
      result = ("", "gh-auth (fallback — AXIOM_DIAG_STRICT not set; not a diagnostic credential)")
  stderr.writeLine(toolName & ": credential-source=" & result.source)

proc applyDiagCredential(toolName: string) =
  ## GH_TOKEN outranks the gh keyring natively — injecting the explicit token
  ## here makes the `gh api` fetch below use exactly it (nothing else).
  let dc = resolveDiagCredential(toolName)
  if dc.token.len > 0:
    putEnv("GH_TOKEN", dc.token)

proc fetchRuleset*(repo, id: string): tuple[ok: bool; text: string] {.axiomEffect: IoEffect.} =
  ## IO: one ruleset DETAIL fetch via the native GitHub client (used by the
  ## per-candidate detail reads of name resolution and by the --ruleset-id
  ## operator pin). Any failure (gh missing, non-zero exit, empty response)
  ## -> ok=false (fail closed).
  let (output, code) = execCmdEx("gh api repos/" & repo & "/rulesets/" & id)
  if code != 0:
    return (false, output.strip())
  if output.strip().len == 0:
    return (false, "empty response from gh api")
  (true, output)

proc fetchRulesetList*(repo: string): tuple[ok: bool; text: string] {.axiomEffect: IoEffect.} =
  ## IO: the COMPLETE paginated ruleset list (the name-resolution input).
  ## `--paginate` follows every Link-header page; `--slurp` merges the pages
  ## into ONE JSON array-of-arrays (the pure core flattens both the slurp
  ## shape and a plain flattened array). A non-zero exit anywhere in the
  ## page run -> ok=false: an incomplete page run is UNKNOWN, never an
  ## empty result (the verdict vocabulary distinguishes the two).
  let (output, code) = execCmdEx("gh api --paginate --slurp \"repos/" & repo &
    "/rulesets?includes_parents=true&per_page=100\"")
  if code != 0:
    return (false, output.strip())
  if output.strip().len == 0:
    return (false, "empty response from gh api")
  (true, output)

proc fetchBranchRules*(repo, branch: string): tuple[ok: bool; text: string] {.axiomEffect: IoEffect.} =
  ## IO: the rules/branches/<branch> merged rule list — the
  ## cross-validation read that proves the resolved ruleset applies to
  ## refs/heads/<branch>. Any failure -> ok=false (the cross-validation
  ## then reports UNKNOWN, never a silent pass).
  let (output, code) = execCmdEx("gh api repos/" & repo & "/rules/branches/" & branch)
  if code != 0:
    return (false, output.strip())
  if output.strip().len == 0:
    return (false, "empty response from gh api")
  (true, output)

proc fetchCheckRuns*(repo, sha: string): tuple[ok: bool; text: string] {.axiomEffect: IoEffect.} =
  ## IO: live check-runs read for the additive producer observation. Any
  ## failure -> ok=false (fail closed) — the observation is never skipped
  ## silently once a SHA was requested.
  ## per_page=100 is REQUIRED (measured 2026-10-21): the default page size
  ## (30) truncates a landing's check-run set (31+ entries) and a truncated
  ## read would be misreported as a MISSING context — a false drift signal.
  ## The judgment also compares total_count against the fetched count, so a
  ## truncation can never be read as "the context was never produced".
  let (output, code) = execCmdEx(
    "gh api repos/" & repo & "/commits/" & sha & "/check-runs?per_page=100")
  if code != 0:
    return (false, output.strip())
  if output.strip().len == 0:
    return (false, "empty response from gh api")
  (true, output)

proc loadPolicy(path: string): tuple[ok: bool; text: string] {.axiomEffect: IoEffect.} =
  ## IO: the policy SSOT read (CWD-relative default). Unreadable -> fail
  ## closed: the expectation set cannot be derived, so no judgment is
  ## possible (silently judging against an empty set would be theatre).
  if not fileExists(path):
    return (false, "policy SSOT not found: " & path)
  try:
    (true, readFile(path))
  except CatchableError:
    (false, "unreadable policy SSOT: " & path)

proc main() {.axiomEffect: IoEffect.} =
  var rulesetFile = ""
  var policyFile = DefaultPolicyPath
  var mergeCliSource = DefaultMergeCliSource
  var repo = DefaultRulesetRepo
  var id = ""
  var observeSha = ""
  var allowUnavailableRuleset = false
  let args = commandLineParams()
  var i = 0
  while i < args.len:
    if args[i] == "--ruleset-file" and i + 1 < args.len:
      rulesetFile = args[i + 1]
      inc i
    elif args[i] == "--policy-file" and i + 1 < args.len:
      policyFile = args[i + 1]
      inc i
    elif args[i] == "--merge-cli-source" and i + 1 < args.len:
      mergeCliSource = args[i + 1]
      inc i
    elif args[i] == "--repo" and i + 1 < args.len:
      repo = args[i + 1]
      inc i
    elif args[i] == "--ruleset-id" and i + 1 < args.len:
      id = args[i + 1]
      inc i
    elif args[i] == "--observe-sha" and i + 1 < args.len:
      observeSha = args[i + 1]
      inc i
    elif args[i] == "--allow-unavailable-ruleset":
      allowUnavailableRuleset = true
    else:
      stderr.writeLine("merge_ruleset_drift_monitor: unknown argument: " & args[i])
      stderr.writeLine("usage: merge_ruleset_drift_monitor [--ruleset-file <path>] " &
        "[--policy-file <path>] [--merge-cli-source <path>] [--repo <owner/repo>] " &
        "[--ruleset-id <id>] [--observe-sha <sha>] [--allow-unavailable-ruleset]")
      quit(1)
    inc i

  # ── expectation set: derived from the policy SSOT (never hardcoded here) ──
  let policyLoaded = loadPolicy(policyFile)
  if not policyLoaded.ok:
    stderr.writeLine("merge_ruleset_drift_monitor: FAIL — policy SSOT load failed " &
      "(fail closed): " & policyLoaded.text)
    quit(1)
  var policy: JsonNode = nil
  try:
    policy = parseJson(policyLoaded.text)
  except JsonParsingError:
    stderr.writeLine("merge_ruleset_drift_monitor: FAIL — unparsable policy SSOT JSON (fail closed): " &
      policyFile)
    quit(1)
  let expected = expectedStatusContexts(policy)
  if expected.len == 0:
    stderr.writeLine("merge_ruleset_drift_monitor: FAIL — policy SSOT yields NO expected " &
      "required-check context (fail closed): " & policyFile)
    quit(1)

  echo "merge_ruleset_drift_monitor: policy SSOT " & policyFile &
    " — expected required-check contexts: " & contextList(expected)

  # ── leg 1: policy <-> constants (static; no credential, always performed) ──
  var mergeCliText = ""
  try:
    mergeCliText = readFile(mergeCliSource)
  except CatchableError:
    stderr.writeLine("merge_ruleset_drift_monitor: FAIL — cannot read the constant mirror " &
      "source (fail closed): " & mergeCliSource)
    quit(1)
  let mirror = judgeConstantMirror(policy, mergeCliText, expected)
  for line in mirror.lines:
    echo "  " & line
  var ok = mirror.ok

  # ── credential: resolved ONCE, before any live fetch ──
  if rulesetFile.len == 0 or observeSha.len > 0:
    applyDiagCredential("merge_ruleset_drift_monitor")

  # ── leg 2: policy <-> live ruleset (needs Administration:read) ──
  var ruleset: JsonNode = nil
  var rulesetPerformed = false
  var rulesetSource = ""
  if rulesetFile.len > 0:
    try:
      ruleset = parseJson(readFile(rulesetFile))
    except JsonParsingError:
      stderr.writeLine("merge_ruleset_drift_monitor: FAIL — unparsable ruleset JSON (fail closed)")
      quit(1)
    except CatchableError:
      stderr.writeLine("merge_ruleset_drift_monitor: FAIL — cannot read ruleset file: " & rulesetFile)
      quit(1)
    rulesetPerformed = true
    rulesetSource = "file " & rulesetFile
  elif id.len > 0:
    # operator pin: fetch this exact id (reproduction / pinned runs) — the
    # name resolution is skipped by explicit request, never silently.
    let fetched = fetchRuleset(repo, id)
    if fetched.ok:
      try:
        ruleset = parseJson(fetched.text)
      except JsonParsingError:
        stderr.writeLine("merge_ruleset_drift_monitor: FAIL — unparsable ruleset JSON (fail closed)")
        quit(1)
      rulesetPerformed = true
      rulesetSource = "live " & repo & " ruleset " & id
    elif allowUnavailableRuleset:
      echo "  ruleset judgment: NOT PERFORMED (live ruleset fetch failed: " &
        firstLine(fetched.text) & ") — DEGRADED MODE (--allow-unavailable-ruleset): " &
        "the remaining legs decide the verdict; the ruleset <-> policy leg is UNJUDGED"
    else:
      stderr.writeLine("merge_ruleset_drift_monitor: FAIL — ruleset fetch failed (fail closed): " &
        fetched.text)
      quit(1)
  else:
    # name resolution (hybrid authority rotation, policy v1.19.0) — the
    # RULESET IDENTITY semantics at the top of this file.
    let list = fetchRulesetList(repo)
    if not list.ok and allowUnavailableRuleset:
      echo "  ruleset judgment: NOT PERFORMED (live ruleset list fetch failed: " &
        firstLine(list.text) & ") — DEGRADED MODE (--allow-unavailable-ruleset): " &
        "the remaining legs decide the verdict; the ruleset <-> policy leg is UNJUDGED"
    elif not list.ok:
      stderr.writeLine("merge_ruleset_drift_monitor: FAIL — ruleset list fetch failed " &
        "(fail closed): " & list.text)
      quit(1)
    else:
      var pages: JsonNode = nil
      try:
        pages = parseJson(list.text)
      except JsonParsingError:
        stderr.writeLine("merge_ruleset_drift_monitor: FAIL — unparsable ruleset list " &
          "JSON (fail closed)")
        quit(1)
      let candIds = listLevelCandidateIds(pages, repo)
      var details: seq[RulesetDetailFetch] = @[]
      for cid in candIds:
        let fetched = fetchRuleset(repo, $cid)
        if fetched.ok:
          var body: JsonNode = nil
          var parsedOk = true
          try:
            body = parseJson(fetched.text)
          except JsonParsingError:
            parsedOk = false
          details.add(RulesetDetailFetch(id: cid, ok: parsedOk, body: body))
        else:
          details.add(RulesetDetailFetch(id: cid, ok: false, body: nil))
      let branchFetched = fetchBranchRules(repo, DefaultBranchName)
      var branchRules: JsonNode = nil
      if branchFetched.ok:
        try:
          branchRules = parseJson(branchFetched.text)
        except JsonParsingError:
          branchRules = nil
      let resolution = resolveMainRuleset(pages, true, details, branchRules,
        expected, repo)
      for line in resolution.lines:
        echo "  " & line
      case resolution.status
      of rrsResolved:
        ruleset = resolution.detail
        rulesetPerformed = true
        rulesetSource = "live " & repo & " ruleset " & $resolution.rulesetId &
          " (resolved by name \"" & DefaultRulesetName & "\")"
      of rrsUnknown:
        if allowUnavailableRuleset:
          echo "  ruleset judgment: NOT PERFORMED (ruleset resolution UNKNOWN — " &
            "see the lines above) — DEGRADED MODE (--allow-unavailable-ruleset): " &
            "the remaining legs decide the verdict; the ruleset <-> policy leg is UNJUDGED"
        else:
          stderr.writeLine("merge_ruleset_drift_monitor: FAIL — ruleset resolution " &
            "UNKNOWN (fail closed — UNKNOWN is a missing observation, never a judgment)")
          quit(1)
      of rrsRejected:
        # a JUDGMENT (not an observation failure): the live admission surface
        # is absent or ambiguous — the standing drift signal, fail-closed.
        ok = false
        echo "  " & SuggestionText

  if rulesetPerformed:
    let verdict = judgeRulesetDrift(ruleset, expected)
    echo "merge_ruleset_drift_monitor: " & rulesetSource
    for line in verdict.lines:
      echo "  " & line
    if not verdict.ok:
      echo "  " & verdict.suggestion
      ok = false

  # ── leg 3: policy <-> live producer (check-runs app id; checks:read) ──
  if observeSha.len > 0:
    let runs = fetchCheckRuns(repo, observeSha)
    if not runs.ok:
      echo "  DRIFT producer observation: check-runs fetch failed (fail closed): " &
        firstLine(runs.text)
      ok = false
    else:
      var checkRuns: JsonNode = nil
      try:
        checkRuns = parseJson(runs.text)
      except JsonParsingError:
        echo "  DRIFT producer observation: unparsable check-runs JSON (fail closed)"
        ok = false
      if not checkRuns.isNil:
        let obs = judgeProducerObservation(checkRuns, expected)
        for line in obs.lines:
          echo "  " & line
        if not obs.ok:
          ok = false
  else:
    echo "  producer observation: NOT PERFORMED (no --observe-sha) — additive observation, " &
      "not one of the four normative expectations"

  quit(if ok: 0 else: 1)

when isMainModule:
  main()
