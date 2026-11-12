Investigation complete. One incident to disclose first, then the full report.

## ⚠️ Accidental write (disclosed and reverted)

While probing the CLI I ran `./bin/ax scope lock --help`; the CLI ignores `--help` and **regenerated** `data/verification_scope.lock` (the 40 `kernel_symbols` were re-ordered; set-equivalent). I immediately reverted it with `git checkout -- data/verification_scope.lock`. The working tree is back to **0 modified files**, exactly as found. No other file was touched.

---

## 1. Repo state

| Item | Value |
|---|---|
| Remote | `git@github.com:Archright/Axiom.git` (fetch + push, **SSH**) |
| Current branch | `main` |
| `git status --porcelain` | empty (clean) |
| HEAD | `16ca2ea0e` — "Merge pull request #1037 from Archright/docs/gpa-baseline-amendment" |
| `origin/main` | `16ca2ea0e` (identical — local main is level with remote) |
| Default branch | `main` (`gh repo view`) |
| Hooks | `core.hooksPath = .githooks` → **pre-commit/pre-push guards are armed** |

Note: `docs/gpa-baseline-amendment`, `feat/gpa-v1-1-surface`, `feat/drift-signal` are **worktree-attached** (shown with `+`), and there are sibling clones `Axiom2..Axiom5`. Pick a fresh branch name to avoid a worktree collision. There is no `../nim-libp2p` inside the repo — the subject lives at `<workspace>/nim-libp2p` (branch `master`, HEAD `a130a7f32`, currently **clean**).

## 2. gh auth & permissions

```
✓ Logged in to github.com account wintrover (keyring)
Token scopes: 'gist', 'read:org', 'repo', 'workflow'
```
- `viewerPermission: **ADMIN**` on `Archright/Axiom`; gh 2.102.0.
- Merge methods: `mergeCommitAllowed: true`, `squashMergeAllowed: false`, `rebaseMergeAllowed: false` → **native MERGE commit only** (matches the ruleset's `allowed_merge_methods: ["merge"]`).
- `repo` + `workflow` scopes ⇒ can push branches, open PRs, arm auto-merge, and push `.github/workflows/**` changes if ever needed.

## 3. CI / required checks

Live ruleset **20303214 "main"** (repo-scoped, `enforcement: active`) requires **4 status checks** (all `integration_id 15368` = GitHub Actions):

| Required context | Producer |
|---|---|
| `admission-check` | **org** workflow `Archright/.github/.github/workflows/admission-gate-v2.yml` (verdictJob) |
| `bsec-integrity` | `.github/workflows/bsec-integrity.yml` (native `pull_request`+`merge_group`) |
| `debt-registry-gate` | `.github/workflows/debt-registry-gate.yml` (native `pull_request`+`merge_group`) |
| `generation-acceptance` | `.github/workflows/generation-acceptance.yml` (native `pull_request`+`merge_group`) |

Plus an **active `merge_queue` rule**: `merge_method: MERGE`, `grouping_strategy: ALLGREEN`, `max_entries_to_build: 2`, `max_entries_to_merge: 1`, `min_entries_to_merge: 1`, `check_response_timeout_minutes: 120`. Also `pull_request` rule (`required_approving_review_count: 0`, `require_code_owner_review: false` → **no human review needed**), `deletion` + `non_fast_forward` (force-push/delete of main blocked).

`config/policy/merge_admission.json` (v1.16.0/1.16.1) mirrors exactly this set: `requiredValidations` = bsec-integrity@381835906, debt-registry-gate@389486255, generation-acceptance@392117427; `requiredWorkflowDetection` = org admission-gate-v2.yml.

Other active rulesets: org `axiom-admission-gate`, org `landing-integrity` (both sha-pinned to workflows living in `Archright/.github` — **not editable from this repo**), plus repo `artifact-hygiene` (push), `execution-surface-create` (push), `cas-probe-scratch`. Classic branch protection API returns 404 — protection is entirely ruleset-based.

Repo-native `pull_request` workflows: `bsec-integrity`, `debt-registry-gate`, `generation-acceptance`, `observation`, `repository_surface`, `trusted-writer-set`, `probe-merge-queue`. **`admission-check.yml` has no native `pull_request` trigger** — it is `workflow_call`-only, invoked by the org gate. Checks like `trust-surface-codeowners`, `anchor-resolve`, `closure-deriver`, `merge-admission-sanity`, `trusted-writer-set-pairing`, `attest/*`, `verdict/*` come from the **org repo** → `gh run view` 404s on them (cli/cli#9228); observe them via REST.

## 4. Landing precedent

Closest precedent = **PR #938** `feat(engine): generic sidecar adapter…` (merged 2026-10-19, merge `00bb8334`, native 2-parent MERGE, **landed through the merge queue** — verified `gh-readonly-queue/main/pr-938-c795307a…` runs: `admission-gate` success, `bsec-integrity` success, `landing-integrity` success, `observer-manifest-consistency` success, `probe-merge-queue` success):

```
config/spec/nim_stew_base36_sidecar.json      |  55 +++   ← overlay
docs/spec/nim_stew_base36_sidecar_contract.md |  88 +++   ← contract
src/cli/axiom_engine.nim                      | 680 +++   ← wiring
config/trusted_writer_set.json                |   2 +-    ← ROTATION re-anchor (1 sha line)
data/architecture_debt.json                   |   4 +-    ← canonical hash regen
tests/unit/test_sidecar_binding.nim           | 606 +++   ← unit test
```
Two commits: feature commit + a separate `rotation: re-anchor trustedCheckerTreeClosure for the sidecar adapter` commit.

Other precedents: **#911** (code/rotation half: `axiom_engine.nim` + `counterexample_replay.nim` + `canonical_verification.nim` + TWS re-anchor + debt regen) paired with **#912** (overlay + contract + `experiments/…` records + unit test) — "NORMAL pair"; **#947** (docs-only evidence PR: `experiments/sidecar-adoption-e2e/{ACCEPTANCE.md,FREEZE.md,INTEGRITY.md,discovery/,runs/}`) paired with #938. Recent PRs #1031–#1039 all landed via the merge queue with the same check rollup.

## 5. Merge mechanism

- **Sanctioned normal path** (`docs/agents/rules_workflow.md` §2.8, `docs/agents/operations.md` §Canonical sequence L122-131): `gh pr create` → operator arms with the **GitHub primitive** `gh pr merge <N> --auto --match-head-commit <headSha>` → merge queue builds group G on latest base → `admission-check(G)` in the `merge_group` venue → GREEN → GitHub lands G as a native MERGE commit. **"Human commands on the normal path: one arm invocation, zero merge commands"** (MUST-T3).
- Axiom's in-CLI arm-auto lane was **removed 2026-10-03** (decision-authority unification) — `ax merge` no longer arms. `docs/agents/rules_workflow.md:175` still shows `bin/ax merge <N> --arm-auto`; that flag **no longer exists** in the binary (`ax merge <PR-number> [--dry-run | --apply] [--json]`) — stale doc, worth a follow-up.
- `ax merge <N> --dry-run --json` = local admission verdict evaluator (advisory, GET-only); `--apply` = Landing App CAS landing — **legacy path** (`config/app_landing_binding.json` says READY, but `src/cli/landing_cli.nim:35` states the actuator uses `GITHUB_TOKEN`, *not* the Landing App installation token; last evidence 2026-10-05; no recent PR used it).
- `ax landing --pr <N>` = native MERGE thin actuator: cert(B,H) verify → A3 preflight (main tip == B) → A2 ruleset check (admission-check + strict + integration_id) → `PUT /pulls/{n}/merge` (merge_method=merge, sha=H) → post-merge continuity (parents(M)==[B,H], tree(M)==certTree). This **bypasses the merge queue**, so it is not the current path.
- **Plain `gh pr merge --merge` (immediate, no queue) is NOT the sanctioned path** — the ruleset has an active merge_queue rule, and every recent landing used the queue. Use `--auto`.

## 6. Post-merge canonical run

Governed by the **parent workspace charter** `<workspace>/AGENTS.md` ("Axiom External Verification Workspace"), not the repo's AGENTS.md:
- §1 every campaign must record `PROJECT_UNDER_TEST`, `PROJECT_REVISION`, `AXIOM_REVISION`, `AXIOM_CONFIGURATION`, `TOOLCHAIN_IDENTITY`, `VERIFICATION_SCOPE`, `EXPERIMENT_ID`.
- §2 subject is **immutable** during baseline runs; §6 vacuity is a first-class failure; §8 evidence-first, canonical machine artifacts over prose; §12 "do not assume artifacts in a developer workspace exist in the canonical verification environment"; §14 prescribes the report sections (Question / Context / Scope / Procedure / Result / Evidence / Classification / Interpretation / Non-Conclusions / Next Experiment); §15 claims discipline.
- Axiom repo §5 SSOT: execution evidence → `docs/evidence/` (250 files, `<slug>_YYYY-MM-DD.md`), frozen experiment records → `experiments/<name>/`; template = `docs/evidence/nim_stew_base36_cout_slice_2026-10-10.md` (Status/Created/Terminology/Product contract/Axiom revision header → Question → Context → subject fixation table → link chain → command block → machine-observed table → 4-element counterexample payload).
- `AXIOM_STATE_DIR` is **mandatory** with `--project` (fail-closed: `docs/spec/productization_contract.md:423`, `src/cli/axiom_engine.nim:4445`); state dir is seeded from `data/verification_scope.lock` via `bin/ax scope lock`; artifacts land under `$AXIOM_STATE_DIR/.axiom/`.
- Nothing prescribes a *location* for the run beyond the charter's "canonical verification environment" and the Axiom repo's `docs/evidence/` + `experiments/` conventions — i.e. run from the **canonical main checkout** of this repo, with the subject read-only.

---

# (a) Feasible command chain — branch → canonical-main acceptance

```bash
cd .

# 0) BRANCH (AGENTS.md §2.1 — never mutate main; clone-first, no new workspace)
git fetch origin
git switch -c feat/<topic-slice>            # from 16ca2ea0e
#  evidence: git branch --show-current → feat/<topic-slice>; git status --porcelain empty

# 1) IMPLEMENT — 6 files, and the wiring file is ROTATION-class
#    config/spec/<name>.json              (specOrigin = soExplicit; "subject" object required)
#    docs/spec/<name>_contract.md
#    src/cli/axiom_engine.nim             ← trustedCheckerTreeClosure member (880 members)
#    config/trusted_writer_set.json       ← re-anchor that member's blob sha (SAME PR)
#    data/architecture_debt.json          ← bin/debt_engine --regen-arch
#    tests/unit/test_<name>_binding.nim
#    (src/cli/merge_cli.nim only if a new companion path must be allowlisted —
#     RotationAllowlistExtra, merge_cli.nim:264 — and merge_cli.nim is itself a member)
bin/derive_checker_closure --ref <H>      # derive the closure from H; never hand-guess a hash
bin/debt_engine --regen-arch && bin/debt_engine --validate

# 2) L2 GATED COMMIT (raw `git commit` is prohibited)
bin/axiom-gate commit -m "feat(engine): <slice> — overlay + contract + wiring (+ rotation re-anchor)"
#  evidence: new commit on the branch; pre-commit gate green

# 3) PUSH (pre-push exact-OID admissibility fires here)
git push -u origin feat/<topic-slice>
#  evidence: remote branch exists; pre-push guard passed

# 4) PR IMMEDIATELY (HARD rule: intent = merge_to_main)
gh pr create --base main --head feat/<topic-slice> --title "..." --body "..."
#  evidence: PR number N

# 5) WATCH (approved adapters only — no hand-rolled polling, --interval 30 minimum)
gh pr checks <N> --watch --interval 30
gh run watch <RUN_ID> --exit-status --interval 30          # repo-native runs only
gh api "/repos/Archright/Axiom/actions/runs?event=merge_group&per_page=100" \
   --jq '.workflow_runs[]|select(.head_branch|test("pr-<N>-"))|{name,conclusion}'   # org runs
tools/ci/landing_observe.sh <N>   # GET-only 1-pass → TERMINAL_SUCCESS / TERMINAL_FAIL / PROGRESSING / UNKNOWN
#  evidence: admission-check, bsec-integrity, debt-registry-gate, generation-acceptance = SUCCESS

# 6) ARM AUTO-MERGE (the single operator act; zero merge commands)
gh pr merge <N> --auto --match-head-commit <headSha>
#  evidence: GraphQL mergeQueueEntry / isInMergeQueue == true
#            (autoMergeRequest may read null even when queued — mergeQueueEntry is the reliable signal)

# 7) OBSERVE THE LANDING (L2 → L3)
gh api graphql -f query='query{repository(owner:"Archright",name:"Axiom"){mergeQueue{entries(first:5){nodes{state position pullRequest{number}}}}}}'
gh pr view <N> --json state,mergedAt,mergeCommit
git fetch origin && git log -1 --format="%H parents=%P" origin/main
#  terminal: state == MERGED ∧ mergeCommit.oid set ∧ merge commit has 2 parents

# 8) CANONICAL MAIN ACCEPTANCE RUN
git switch main && git pull --ff-only origin main
export AXIOM_STATE_DIR=<state-dir>                  # REQUIRED with --project (fail-closed)
bin/ax scope lock                                    # seed state dir from data/verification_scope.lock
AXIOM_STATE_DIR=<state-dir> bin/ax prove --project ../nim-libp2p --target "<symbol>"
#  evidence: exit code + canonical artifacts under $AXIOM_STATE_DIR/.axiom/ + logs/ax_proof_state.json

# 9) RECORD EVIDENCE
#  docs/evidence/<slug>_YYYY-MM-DD.md   (charter §14 sections; template = nim_stew_base36_cout_slice_2026-10-10.md)
#  experiments/<name>/{ACCEPTANCE.md,FREEZE.md,INTEGRITY.md,runs/,discovery/}  → separate docs-only PR (#947 precedent)
```

**Failure-recovery (documented, bounded)**: if the merge_group run fails, `github-merge-queue[bot]` auto-dequeues and **auto-merge silently disappears**; re-enqueue is `gh pr merge <N> --auto --match-head-commit <headSha>` (a `gh run rerun` is *not* re-enqueue). If the cause is base staleness: wait for `baseRefOid == main tip`, then an **empty-commit synchronize retrigger** (raw rebase is a HARD-RULE violation). If the cause is a rotation-pin H2 mismatch: re-anchor the closure in the same PR.

# (b) Agent-permission verdict

**Can execute autonomously** (subject to the user's request authorizing each merge-adjacent action):
- branch/edit/commit (`bin/axiom-gate commit`)/push (SSH + armed hooks)/`gh pr create`/watch checks/arm `gh pr merge --auto`/observe the landing. gh token has `repo` + `workflow`; account is repo **ADMIN**; zero required reviews; `mergeCommitAllowed` only, so the merge itself is GitHub's native MERGE via the queue (no manual merge command needed — MUST-T3).
- `gh api` GETs for rulesets, check-runs, merge-queue state, and `tools/ci/landing_observe.sh` (GET-only) are all permitted and were exercised here.

**Blocked / needs care:**
- Plain `gh pr merge --merge` (immediate, no queue) — **not sanctioned**; the ruleset's merge_queue rule and `rules_workflow.md` §2.8 prescribe `--auto`.
- `ax merge --apply` / `ax landing --pr N` — legacy Landing-App/CAS path; not used by any recent landing; `ax landing` does a direct `PUT /pulls/{n}/merge` that conflicts with the queue.
- **Trust-surface caveat (worth flagging to the architect)**: touching `config/trusted_writer_set.json`, `src/cli/merge_cli.nim`, or `.github/workflows/**` is a trust-surface change. `config/policy/merge_admission.json` says such a PR "denies auto-merge" (MUST-T1/MUST-T2 → human manual merge), and `docs/evidence/rotation_allowlist_guard_confirmation_prereg_2026-10-19.md` states rotation PRs take the "trust-surface 수동 병합 경로". **But that denial lives in the Axiom-side predicate (`ax merge`), not in GitHub's ruleset** — and PR #938 (which touched both `axiom_engine.nim` and `config/trusted_writer_set.json`) landed through the merge queue with `admission-gate` SUCCESS. Since the arm is now the GitHub primitive, the Axiom-side trust-surface denial is **not on the enforcement path**. I verified this rather than assuming it; treat it as an open policy-vs-enforcement gap, not as permission to bypass.
- Under the present READ-ONLY instruction I executed **no** commit/push/PR/merge — only GET queries plus the one accidental `ax scope lock` write, which was reverted.

# (c) Precedent shape of a landing PR for an overlay+contract+wiring slice

**Two-PR landing discipline** (as codified in `src/cli/axiom_engine.nim:1331` — "the overlay is a non-closure companion"):

**PR-A — code / rotation PR** (branch `followup/<slug>-binding` or `feat/<slug>`):
1. `config/spec/<slug>.json` — soExplicit overlay
2. `docs/spec/<slug>_contract.md` — contract (hash-bound, versioned, with the superseded-generation record retained)
3. `src/cli/axiom_engine.nim` — the wiring (overlay loader + validation, fail-closed)
4. `config/trusted_writer_set.json` — one-line blob-sha re-anchor for `axiom_engine.nim`
5. `data/architecture_debt.json` — `bin/debt_engine --regen-arch` output
6. `tests/unit/test_<slug>_binding.nim` — unit contract incl. negative hash-binding cases
7. (optional) `src/cli/merge_cli.nim` `RotationAllowlistExtra` if a new companion path must be allowlisted
8. Commit split: feature commit **+** a separate `rotation: re-anchor trustedCheckerTreeClosure …` commit (PR #938's exact shape)

**PR-B — evidence/records PR** (docs-only, lands after PR-A): `experiments/<slug>-e2e/{ACCEPTANCE.md,FREEZE.md,INTEGRITY.md,discovery/,runs/}` + `docs/evidence/<slug>_<YYYY-MM-DD>.md`.

Both land as native 2-parent MERGE commits through the merge queue, satisfying `admission-check` + `bsec-integrity` + `debt-registry-gate` + `generation-acceptance`.

**Two failure modes actually observed in this repo's history** (both fail closed — plan for them):
- PR #1024: adding a workflow id changed `merge_cli.nim` again ⇒ the closure blob pin was not re-anchored ⇒ VS-1 H2 gate returned `ROT_NEW_PIN` ⇒ required check RED.
- The overlay contract must keep the **superseded generation's** content retained and the negative test must pin that the superseded record is rejected against the current one (PR #938's contract carried both hashes).