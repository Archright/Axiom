# G1 Support-Ticket Evidence Package — ruleset-required workflow stops receiving `workflow_run` events after an enforcement evaluate cycle (2026-10-16)

> **Purpose**: complete, self-contained bug report for GitHub Support (Enterprise). Every claim below carries its own reproduction command (`gh api` form) and the observed value, so Support can verify each step read-only against `Archright` without asking for more context.
> **Snapshot time**: all live API observations in this document were taken **2026-10-16T04:40–05:20Z** by an org admin (`wintrover`, user id 53123826; classic PAT with `admin:enterprise, admin:org, repo, workflow`).
> **Locale note**: timestamps are UTC (`Z`) unless a ruleset-history version id is quoted, in which case the raw API value (+09:00) is also given.

---

## 1. Summary

**`workflow_run` events are not delivered for ONE org-ruleset-required workflow (`admission-gate`) while a structurally identical sibling (`landing-integrity`) in the same ruleset pair delivers normally.**

- Repository: **`Archright/Axiom`** (repo id **`<legacy-repo>`**, private, default branch `main`)
- Organization: **`Archright`** (org id **268288440**)
- Source repo of the required workflows: **`Archright/.github`** (repo id **1182157951**)
- Required via org rulesets **24233738** (`axiom-admission-gate` → `.github/workflows/admission-gate.yml`) and **23943917** (`landing-integrity` → `.github/workflows/landing-integrity.yml`), both pinned to the same source-repo commit.
- `admission-gate` runs still **execute** normally (required checks enforced, runs green), but its completed runs have generated **zero** `workflow_run` deliveries to a listening workflow since **2026-10-12T12:41:49Z** — across **239 recorded completions (176 successful)** in the following 4 days. The death instant correlates with the ruleset's **enforcement active→evaluate→active cycle** (16 min 17 s) during a documented emergency maintenance window.
- A repo-side probe (`ci-cache-publisher` with a permissive `workflow_run.workflows: ['*']` trigger plus an in-job guard that logs the triggering run's `path`) proves the asymmetry directly: after the probe landed (2026-10-15T13:22:00Z), **293** probe runs fired on natural completions — **46 were bound to `landing-integrity`** (delivery works) and **0 were bound to `admission-gate`** (delivery dead).

We believe this is a platform-side event-subscription defect: the required workflow's `workflow_run` subscription appears to have been **detached at the (repository_id, path) unit** when the ruleset cycled through `evaluate`, and none of the sanctioned update paths re-attach it.

---

## 2. Environment and identifiers (all verifiable read-only)

```bash
gh api repos/Archright/Axiom --jq '{id, name, default_branch}'
# → {"id":<legacy-repo>,"name":"Axiom","default_branch":"main"}
gh api orgs/Archright --jq '{login, id}'
# → {"login":"Archright","id":268288440}
gh api repos/Archright/.github --jq '{id, name}'
# → {"id":1182157951,"name":".github"}
```

Listener workflow (the only `workflow_run` consumer in the repo):

- `.github/workflows/ci-cache-publisher.yml` — repo-owned, registered as the **single trusted cache publisher** in the repo's repository-surface policy since policy version **v27** (2026-09-29, "workflow_run single trusted cache publisher").

---

## 3. The A/B pair: two ruleset-required workflows, structurally identical

### 3.1 The rulesets are byte-for-byte siblings (same enforcement, same conditions, same source repo, same pinned sha)

```bash
gh api orgs/Archright/rulesets/24233738
gh api orgs/Archright/rulesets/23943917
```

Observed 2026-10-16 (verbatim, current state):

```json
{"id":24233738,"name":"axiom-admission-gate","enforcement":"active",
 "conditions":{"ref_name":{"include":["refs/heads/main"]},
               "repository_name":{"include":["Axiom"]}},
 "rules":[{"type":"workflows",
           "parameters":{"do_not_enforce_on_create":false,
             "workflows":[{"path":".github/workflows/admission-gate.yml",
                           "repository_id":1182157951,
                           "sha":"ade11572052d9bce01242df452d05ab38ed78eb0"}]}}]}

{"id":23943917,"name":"landing-integrity","enforcement":"active",
 "conditions":{"ref_name":{"include":["refs/heads/main"]},
               "repository_name":{"include":["Axiom"]}},
 "rules":[{"type":"workflows",
           "parameters":{"do_not_enforce_on_create":false,
             "workflows":[{"path":".github/workflows/landing-integrity.yml",
                           "repository_id":1182157951,
                           "sha":"ade11572052d9bce01242df452d05ab38ed78eb0"}]}}]}
```

Both: `enforcement: active`, identical `conditions` (`refs/heads/main` ∩ repository `Axiom`), identical source repository (`Archright/.github`, id 1182157951), identical pinned commit (`ade115720…`). `bypass_actors: []` on both. The pair has been moved **in lockstep** through its entire life — every ruleset-history version on one has a same-instant twin on the other (see §6).

### 3.2 Neither workflow exists in the target repo's Actions workflow registry

```bash
gh api repos/Archright/Axiom/actions/workflows --jq '.workflows[] | .path' | grep -E "admission-gate|landing-integrity"
# → (no output — neither is listed)

gh api repos/Archright/Axiom/actions/workflows/admission-gate.yml
# → {"message":"Not Found",...,"status":"404"}
gh api repos/Archright/Axiom/actions/workflows/landing-integrity.yml
# → {"message":"Not Found",...,"status":"404"}

gh api repos/Archright/Axiom/actions/required_workflows
# → HTTP 422 "As of January 2024, this feature is fully deprecated and creating
#    required workflows is only available with repository rulesets..."
```

The workflows still **execute** (required checks are enforced; runs appear under `GET /repos/Archright/Axiom/actions/runs` with `path` = the required path), but there is no workflow object in the registry for either — both are injected purely by the org rulesets.

### 3.3 The probe: a permissive `workflow_run` trigger that records what was actually delivered

On 2026-10-15T13:22:00Z (PR Archright/Axiom#846, merge commit `5dc7167d444547626505e5ac40ed18aee2209405`) the listener's trigger was widened from the name filter `workflows: [admission-gate]` (which had silently stopped matching — see §5) to the documented permissive glob, with loop hygiene negation:

```yaml
on:
  workflow_run:
    workflows: ['*', '!ci-cache-publisher']
    types: [completed]
```

The first job step then re-resolves the triggering run via `GET /repos/Archright/Axiom/actions/runs/{github.event.workflow_run.id}` and logs its `path` (publish-skip line) — i.e. **every probe run records exactly which completed workflow was delivered to it**:

```
[publish-skip] run path '.github/workflows/<X>.yml' != .github/workflows/admission-gate.yml (orchestrator identity)
```

Extraction (read-only, per run):

```bash
gh api repos/Archright/Axiom/actions/runs/<RUN_ID>/logs   # zip; grep the line above
```

### 3.4 Result: 293 delivered completions — landing-integrity delivers, admission-gate does not

Probe runs from the first post-merge instant (2026-10-15T13:22:16Z, run **38742110908**) through 2026-10-16T04:17Z: **293 runs**, every one triggered by a real completed workflow elsewhere in the repo. Binding census (authoritative source: the guard log line of each run):

| delivered triggering workflow (`run.path`) | probe runs |
|---|---|
| `.github/workflows/trusted-writer-set.yml` | 49 |
| `.github/workflows/bsec-integrity.yml` | 49 |
| `.github/workflows/observation.yml` | 47 |
| **`.github/workflows/landing-integrity.yml`** | **46** |
| `.github/workflows/merge-queue-rearm.yml` | 31 |
| `.github/workflows/repository_surface.yml` | 28 |
| `.github/workflows/probe-merge-queue.yml` | 20 |
| `.github/workflows/h4-routing-measure.yml` | 5 |
| `.github/workflows/closure-watcher.yml` | 2 |
| **`.github/workflows/admission-gate.yml`** | **0** |
| (cancelled-before-start, no log retained — excluded from attribution) | 16 |

**`admission-gate` completed at least 30 times in this same window** (its runs kept executing; e.g. success runs `38805085401`, `38846646087`, `38847179520`) — **none of them was ever delivered**.

26 representative attributed runs, first to last of the recorded range (IDs verbatim from the recorded data; bound path extracted from each run's guard log as in §3.3):

| probe (publisher) run | created_at (UTC) | bound triggering path | conclusion |
|---|---|---|---|
| 38742110908 | 2026-10-15T13:22:16Z | trusted-writer-set.yml | success |
| 38742131568 | 2026-10-15T13:22:25Z | landing-integrity.yml | success |
| 38742198101 | 2026-10-15T13:22:54Z | trusted-writer-set.yml | success |
| 38742202751 | 2026-10-15T13:22:56Z | merge-queue-rearm.yml | success |
| 38742342778 | 2026-10-15T13:23:54Z | bsec-integrity.yml | success |
| 38742718541 | 2026-10-15T13:26:33Z | observation.yml | success |
| 38743749063 | 2026-10-15T13:33:45Z | trusted-writer-set.yml | success |
| 38743772824 | 2026-10-15T13:33:55Z | landing-integrity.yml | success |
| 38743979230 | 2026-10-15T13:35:21Z | bsec-integrity.yml | success |
| 38744022673 | 2026-10-15T13:35:40Z | repository_surface.yml | success |
| 38744474386 | 2026-10-15T13:38:51Z | observation.yml | success |
| 38744683792 | 2026-10-15T13:40:20Z | probe-merge-queue.yml | success |
| 38744691874 | 2026-10-15T13:40:23Z | landing-integrity.yml | success |
| 38744798515 | 2026-10-15T13:41:06Z | trusted-writer-set.yml | success |
| 38744808967 | 2026-10-15T13:41:11Z | merge-queue-rearm.yml | success |
| 38745399228 | 2026-10-15T13:45:18Z | observation.yml | success |
| 38745637204 | 2026-10-15T13:46:58Z | trusted-writer-set.yml | success |
| 38745661231 | 2026-10-15T13:47:08Z | landing-integrity.yml | success |
| 38745927748 | 2026-10-15T13:49:01Z | repository_surface.yml | success |
| 38746064261 | 2026-10-15T13:49:58Z | merge-queue-rearm.yml | success |
| 38746067191 | 2026-10-15T13:50:00Z | merge-queue-rearm.yml | success |
| 38746325379 | 2026-10-15T13:51:47Z | observation.yml | success |
| 38747442452 | 2026-10-15T13:59:35Z | trusted-writer-set.yml | success |
| 38748611467 | 2026-10-15T14:07:34Z | observation.yml | success |
| 38748794399 | 2026-10-15T14:08:49Z | probe-merge-queue.yml | success |
| 38749639829 | 2026-10-15T14:14:34Z | probe-merge-queue.yml | success |

(The recorded range continues — e.g. probe run **38848928391**, 2026-10-16T04:07:00Z, bound `merge-queue-rearm.yml` — full census available on request.)

### 3.5 The cleanest single A/B pair: same second, same event, opposite outcomes

On 2026-10-16T03:39:59Z a merge-group landing started **both** required workflows in the same second (same triggering commit family):

- `landing-integrity` run **38846645927** (merge_group) → completed (success) 03:40:20Z → probe run **38846680919** fired at **03:40:21Z** (+1 s) with guard log `[publish-skip] run path '.github/workflows/landing-integrity.yml' …` — **delivered**.
- `admission-gate` run **38846646087** (merge_group) → completed (success) 03:56:52Z → **no probe run bound to `admission-gate` exists, anywhere before or after** — **not delivered**.

Both workflows were required by the same ruleset pair, from the same source repo, at the same pinned sha, at that instant.

---

## 4. Timeline

### 4.1 Healthy delivery: 2026-09-29 → 2026-10-12T10:05Z (continuous)

While `admission-gate.yml` was still a repository-owned workflow (registry-resolvable by name), the publisher's `workflow_run.workflows: [admission-gate]` filter fired on every gate completion:

- First recorded publisher run in the continuous chain: **36515591951**, created **2026-09-29T03:05:29Z**, success.
- Last delivered event before death: gate run **38232126661** (`merge_group`, completed **2026-10-12T10:05:14Z**) → publisher run **38234089918** created **2026-10-12T10:05:16Z** (+2 s), success.
- Density: 900 publisher runs in 2026-10-04→10-12 alone (daily 38/57/119/105/197/134/65/95 for 10-05→10-12); **zero** day-gaps in the window.

```bash
gh api "repos/Archright/Axiom/actions/runs/36515591951" --jq '{id,name,event,created_at,conclusion}'
gh api "repos/Archright/Axiom/actions/runs/38234089918" --jq '{id,name,event,created_at,conclusion}'
gh api "repos/Archright/Axiom/actions/runs/38232126661" --jq '{id,name,path,event,created_at,updated_at}'
```

### 4.2 Death correlates with the ruleset enforcement cycle (2026-10-12T12:25→12:41Z)

GitHub's own ruleset audit trail (history endpoint) for ruleset 24233738:

| version_id | updated_at (raw API, +09:00) | UTC | change |
|---|---|---|---|
| 52836629 | 2026-10-12T21:25:32.859+09:00 | **12:25:32Z** | enforcement **active → evaluate** |
| 52838211 | 2026-10-12T21:41:49.886+09:00 | **12:41:49Z** | enforcement **evaluate → active** |

(This 16 min 17 s window was a documented emergency maintenance window used to land a hotfix PR while a broken workflow pin made required checks structurally unfailable; total scope was this single enforcement toggle on 24233738 plus a 66 s twin on repo ruleset 20303214. Actor: user id 53123826.)

```bash
gh api "orgs/Archright/rulesets/24233738/history" --jq '.[] | {version_id, updated_at}'
gh api "orgs/Archright/rulesets/24233738/history/52836629" --jq '.state.enforcement'   # → "evaluate"
gh api "orgs/Archright/rulesets/24233738/history/52838211" --jq '.state.enforcement'   # → "active"
```

- **First real completion after the cycle that was never delivered**: gate run **38249840104** (`merge_group`, completed **2026-10-12T12:42:52Z** — 63 s after enforcement returned to `active`). No publisher run followed. Recorded in our measurement ledger (`data/e4e5/ledger.json`, observation `{run_id: 38249840104, …}`) and verifiable:

```bash
gh api repos/Archright/Axiom/actions/runs/38249840104 --jq '{id,path,event,created_at,updated_at,conclusion}'
# → {"path":".github/workflows/admission-gate.yml","event":"merge_group",
#    "created_at":"2026-10-12T12:34:10Z","updated_at":"2026-10-12T12:42:52Z",...}
```

- **Total starvation, measured**: between 2026-10-12T10:06:00Z and 2026-10-15T13:22:00Z the publisher received **zero** `workflow_run` runs of any kind:

```bash
gh api "repos/Archright/Axiom/actions/runs?event=workflow_run&created=2026-10-12T10:06:00Z..2026-10-15T13:22:00Z&per_page=100" \
  --jq '[.workflow_runs[] | select(.name == "ci-cache-publisher")] | length'
# → 0
```

### 4.3 The missed completions accumulate (~160+ → 239 measured)

From the death instant (2026-10-12T12:41:49Z) through 2026-10-16T05:00Z, `admission-gate` completed **239 times (176 success, 63 failure)** — full scan of the runs list, client-filtered by `path == .github/workflows/admission-gate.yml` and `updated_at > death instant`:

| completion day (UTC) | runs completed |
|---|---|
| 2026-10-12 (after 12:41Z) | 24 |
| 2026-10-13 | 96 |
| 2026-10-14 | 40 |
| 2026-10-15 | 65 |
| 2026-10-16 (through 05:00Z) | 14 |

Examples of undelivered **successful** completions (each verbatim from the runs API):

| gate run | event | completed_at (UTC) | conclusion |
|---|---|---|---|
| 38249840104 | merge_group | 2026-10-12T12:42:52Z | failure |
| 38520769457 | pull_request | 2026-10-14T06:21:31Z | success |
| 38805085401 | merge_group | 2026-10-15T21:06:42Z | success |
| 38846646087 | merge_group | 2026-10-16T03:56:52Z | success |
| 38847179520 | merge_group | 2026-10-16T04:06:18Z | success |

Note on measurement hygiene: the `created=…` range filter of the runs-list endpoint is **lossy for these registry-absent workflow runs** (a `created=2026-10-11..2026-10-16` scan reports no runs on 10-12/10-13 even though they exist; a full unfiltered scan finds them). The counts above come from the full unfiltered scan. We mention this because it may share a root cause with the delivery defect (both touch resolution of registry-absent, ruleset-injected workflows).

---

## 5. What we tried (all readback-verified; delivery never resumed)

### 5.1 PUT updates to ruleset 24233738 after death (GitHub's own history as audit trail)

Every state change below is a versioned record of `GET /orgs/Archright/rulesets/24233738/history`; each was verified by an independent GET readback immediately after the PUT. Enforcement was **never** put back into `evaluate` after 12:41:49Z — deliberately, because `landing-integrity` (the sibling of the pair) keeps delivering and its required checks must stay enforcing; the one evaluate cycle already in the record (§4.2) is itself the suspected trigger of the defect.

| version_id | when (UTC) | change |
|---|---|---|
| 53287273 | 10-15T06:30:38Z | pin mode switch: mutable `ref: "main"` → **sha pin** `e968b5c0…` (first post-death write) |
| 53348828 | 10-15T14:36:12Z | sha rotation → `135644a3…` |
| 53376820 | 10-15T17:31:48Z | sha rotation → `f26306b4…` |
| 53389937 | 10-15T19:04:23Z | sha rotation → `b26fbbd8…` |
| 53395292 | 10-15T19:35:36Z | sha rotation → `f26306b4…` |
| 53399402 | 10-15T20:10:45Z | sha rotation → `74b415c4…` |
| 53438401 | 10-16T03:13:55Z | **workflows rule removed entirely** (rules: []) |
| 53438415 | 10-16T03:14:06Z | workflows rule **re-added** verbatim (sha `74b415c4…`) — **11 s detach/attach window**, with the repo's independent merge-blocks triple-proven first (required_status_checks + pull_request rule + merge-queue frozen to `max_entries_to_build: 0`) |
| 53438781 | 10-16T03:18:53Z | sha rotation → `ade115720…` (current state) |

The sibling ruleset 23943917 received **lockstep PUTs at the same instants** (history versions 53287319, 53348833, 53376823, 53389942, 53395299, 53399407, 53438786). Counting both rulesets this is **16 PUT operations** since death; additionally an **identical-content PUT** (verbatim baseline body) was performed at 2026-10-16T02:16:39Z — the server returned 200, the readback diff vs. baseline was **empty (0 lines)** and even `updated_at` did not change, i.e. a confirmed complete no-op (recorded in `docs/evidence/g1_cache_supply_experiment_2026-10-16.md` §S1).

After every one of these writes, subsequent `admission-gate` completions were still never delivered (the §3.4 census covers the windows after each write; e.g. the first gate completion after the identical-content PUT — run 38839840065, success 2026-10-16T02:33:32Z — was again not delivered).

### 5.2 Ruleset DELETE + CREATE experiment ("Lever-A") — status: **in progress, not yet executed**

A controlled DELETE → verbatim-CREATE of ruleset 24233738 is being prepared and executed by a parallel workstream at the time of this writing (pre-write record staged at `docs/evidence/g1_leverA_create_experiment_2026-10-16.md`; baseline GETs frozen 2026-10-16T04:14–04:23Z; merge-queue freeze procedure defined; safety basis: repo ruleset 20303214's `required_status_checks [admission-check, bsec-integrity]` + `pull_request` rule fail-close independent merges while the org ruleset is absent). **As of the snapshot time of this document, no deletion appears in the ruleset history** (last version 53438781, 03:18:53Z) — the result is not yet known and will be appended to that record before/with filing. Supporting observation for why CREATE is the remaining candidate: every ruleset-workflow **creation** in this org's history delivered `workflow_run` events from birth; no *update* path has ever resurrected a dead subscription.

### 5.3 Why the name filter itself stopped working (context, not the ask)

Until 10-12 the publisher's `workflow_run.workflows: [admission-gate]` matched by **workflow name**. After the registry entry for the injected workflow disappeared from the target repo (§3.2), name matching could not resolve, so the publisher starved silently — that is the consumer-side half of the story, worked around by the §3.3 probe. The **event-production** half — no `workflow_run` event is ever emitted for the `admission-gate` required workflow's completions, while the structurally identical `landing-integrity` sibling's completions *are* emitted — is the platform defect this report asks you to fix, and no client-side trigger shape can bypass it (the §3.3 probe is trigger-agnostic: it receives everything *except* `admission-gate`).

---

## 6. Impact

- The repo's **cache-supply pipeline is starved for the `admission-gate` lane**: `ci-cache-publisher` is the single trusted publisher (repository-surface policy v27 registration; ADR-0025 Amendment B) that re-seeds the B-cache/base artifacts immediately after each green gate run. Since 2026-10-12 no `admission-gate` completion has reached it, so every merge-cycle cache seed for the main lane is missing (consumers fall back to cold rebuilds; the stale 10-11 key is still being re-consumed).
- **Merges are NOT blocked**: required checks are enforced separately (repo ruleset 20303214 `required_status_checks`), and the gate itself executes fine. This is a **pure event-delivery defect** — the workflow runs, its conclusion is recorded, but the `workflow_run` event is never emitted to listeners.
- Cache staleness is currently masked by an old seeded key (created 2026-10-11, still being consumed) — the pipeline degrades silently rather than failing loudly.

---

## 7. Ask

1. **Confirm whether an `enforcement: evaluate` cycle (or the evaluate→active re-attach) on an org ruleset can permanently detach the `workflow_run` event subscription of a ruleset-required workflow** — i.e. whether the (repository_id, path)-keyed required-workflow event binding created at ruleset/workflow registration time is dropped when enforcement cycles, and is not re-created by any subsequent ruleset update (sha re-pin, rule remove+re-add, verbatim PUT).
2. Provide **remediation**: either a **server-side re-attach** of the `workflow_run` subscription for `Archright/.github` commit `ade11572052d9bce01242df452d05ab38ed78eb0` → `.github/workflows/admission-gate.yml` @ `Archright/Axiom` (org ruleset 24233738), or a **sanctioned API path** that reliably re-creates the subscription short of deleting and recreating the ruleset.

---

## Appendix A — one-shot reproduction for Support

```bash
# A/B rulesets (structurally identical, both active, same source repo + sha)
gh api orgs/Archright/rulesets/24233738
gh api orgs/Archright/rulesets/23943917

# enforcement-cycle versions that correlate with the death
gh api "orgs/Archright/rulesets/24233738/history" --jq '.[] | {version_id, updated_at}'

# neither required workflow is registry-resolvable in the target repo
gh api repos/Archright/Axiom/actions/workflows --jq '[.workflows[].path] | map(select(test("admission-gate|landing-integrity")))'
gh api repos/Archright/Axiom/actions/workflows/admission-gate.yml          # → 404
gh api repos/Archright/Axiom/actions/workflows/landing-integrity.yml       # → 404

# the gate completes but nothing listens: last delivered (10-12T10:05:16Z) vs. first undelivered (12:42:52Z)
gh api repos/Archright/Axiom/actions/runs/38232126661 --jq '{path,event,updated_at}'   # completed 10:05:14Z — delivered
gh api repos/Archright/Axiom/actions/runs/38249840104 --jq '{path,event,updated_at}'   # completed 12:42:52Z — never delivered

# starvation window: zero workflow_run-triggered publisher runs
gh api "repos/Archright/Axiom/actions/runs?event=workflow_run&created=2026-10-12T10:06:00Z..2026-10-15T13:22:00Z&per_page=100" \
  --jq '[.workflow_runs[] | select(.name == "ci-cache-publisher")] | length'          # → 0

# post-probe asymmetry: sibling delivered, admission-gate never
gh api repos/Archright/Axiom/actions/runs/38846645927 --jq '{path,event,updated_at}'   # landing-integrity, completed 03:40:20Z
gh api repos/Archright/Axiom/actions/runs/38846680919/logs | grep -aoE "run path '[^']+'"   # → .github/workflows/landing-integrity.yml  (DELIVERED)
gh api repos/Archright/Axiom/actions/runs/38846646087 --jq '{path,event,updated_at}'   # admission-gate, completed 03:56:52Z
# → no publisher run exists whose guard log shows "run path '.github/workflows/admission-gate.yml'" anywhere after 2026-10-12T10:05Z
```

## Appendix B — related internal records (context, not required for triage)

- Delivery-degradation forensics and the probe fix: PR `Archright/Axiom#846` (merged 2026-10-15T13:22:00Z).
- Emergency evaluate window audit (the 10-12 toggle, versions 52836629/52838211): `docs/evidence/emergency_evaluate_window_2026-10-12.md`.
- Identical-content PUT + rule remove/re-add record: `docs/evidence/g1_cache_supply_experiment_2026-10-16.md`.
- Ruleset API write-path observations: `docs/spec/github_ruleset_api_quirks.md`.
- Required-workflow registration structure (repository_id 1182157951, sha pins): `docs/evidence/admission_generation_freeze_2026-10-15.md` §2–3.
