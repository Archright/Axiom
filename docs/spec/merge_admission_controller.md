# Merge Admission Controller

**Status**: Normative contract (v9 draft 2026-08-31; **Model B revision 2026-09-10** — §11 exact-object publication superseded by GitHub native MERGE landing, see `docs/spec/certification_continuity_contract.md` §4.3; **2026-09-11 revision** — landing aligned to the approved v5 architecture: `PUT /pulls/{n}/merge` (merge_method=merge, atomic head `sha` CAS), minimal GITHUB_TOKEN permissions, invariant chain in §8b; **2026-09-12 revision (ADR-0021)** — verification execution authority moved to repository state transitions; workflow_dispatch entry removed (see `docs/adr/0021-execution-authority.md`); **2026-09-16 revision (slice 3a)** — all five required validations rebind to `admission_producer.yml` (workflowId 359582573, policy v1.4.0): `ci.yml` is a §-1 tombstone (read-only) and `readiness_start.yml` is retired as admission producers; §10 actuator trigger note `workflow_run completed for ci.yml/readiness_start.yml` is likewise historical — the current producer trigger is `pull_request` on `admission_producer.yml`. **CI=0 cutover (2026-09-20/21, 삭제 커밋 `ce92fc2d1` 2026-09-21)**: 워크플로 8개(admission_producer.yml 등)와 ci.yml·auto_merge.yml 등이 제거되었으나 2개가 잔존/복구되었다(`repository_surface.yml` — pull_request@main PR 관측 전용, required check 아님; `runner-pool-acceptance.yml` — push@main, 9-job; 2026-09-22 활성화). §2b/§6/§10의 워크플로 기반 actuator·producer 서술은 비준 계약의 설계 기록이며, 현행 실행 경로는 로컬 게이트(`bin/axiom-gate commit` + pre-push admissibility) + native MERGE 랜딩이다.) **2026-09-24 재등록 (policy v1.7.0)**: `admission-check.yml` (workflowId 365692388, main since PR #206)이 단일 required validation으로 재등록 — `config/policy/merge_admission.json` requiredValidations와 `src/cli/merge_cli.nim` RequiredChecks/RequiredWorkflowIds 양쪽에 이중 바인딩으로 고정되었고, `proof_unit_consistency_gate` (f.3)는 이 결정 개정에 따라 "RequiredWorkflowIds 블록 비공백"을 정책 상태 무관 상시 불변식으로 개정했다. **2026-09-29 revision (ADR-0027)**: §Scope boundary·§10의 "native merge queue pole은 폐기" 문구는 superseded — GitHub Merge Queue = 채택된 위임 대상(후보 인증 경로; 커스텀 queue/orchestrator 금지 유지). **2026-10-03 revision (Phase C3 authority dedupe)**: the in-CLI auto-merge arm lane (`ax merge --arm-auto` — live ruleset fetch, arm preflight, a second in-CLI admission adjudication, `gh pr merge --auto` actuation) is REMOVED. GitHub is the sole merge ENFORCEMENT authority (repository ruleset + the `admission-check` required status check); Axiom produces the single admission predicate whose exit code IS that check's conclusion — see §1 "Enforcement authority".
**Created**: 2026-08-31
**Related**: `docs/adr/0020-axiom-queue-semantics-and-executor-boundary.md`, `docs/adr/0021-execution-authority.md`, `docs/spec/change_manifest_contract.md`, `docs/spec/change_governance_contract.md`, `docs/spec/certification_continuity_contract.md` (successor contract — certification continuity v10, Phase 0 registered), `AGENTS.md` §-1, §0.3
**Implementation**: `src/cli/merge_cli.nim` (predicate + facts collection), `src/core/policy/change_graph_facts.nim` (pure change-graph predicates), `tools/ci/run_landing_continuity.sh` (landing continuity; 원 actuator `.github/workflows/auto_merge.yml`는 CI=0 cutover, 2026-09-20로 삭제). Planned (ADR-0020 Phase 3/4 — SUPERSEDED 2026-09-10): the speculative-queue provider layer (`candidate_adapter`/`candidate_materializer`/`executor_adapter`) was removed with Verdict B; `.github/workflows/verify-candidate.yml` now dispatches on (headSha, baseSha, prNumber) directly (CI=0로 삭제됨).

---

## 1. Purpose / Scope

This document defines the machine-verifiable **merge admission** contract: the deterministic predicate that decides whether a PR head is admissible for automatic merge, and the minimal privileged actuator that executes that verdict.

Architecture:

```
GitHub (event + scheduling + execution)  = Compute Plane (ADR-0020)
   │  workflow_run = evaluation opportunity only — NEVER a policy source
   ▼
collectAdmissionFacts(H, B)   ← I/O boundary: each logical fact source fetched ONCE; B = EVENT-FROZEN base anchor (AXIOM_MAIN_SHA), never the live PR API `base.sha` (ADR-0027 P4)
   ▼
AdmissionFacts(H, B)       ← immutable snapshot; every PR-derived fact bound to H; the base anchor is B
   ▼
MergeAdmissible(V, mainSha)   ← pure predicate (.raises: []); the single authority — Pass 0 base freshness consumes mainSha (BASE_UNRECORDED/STALE_BASE); Pass 2.96 also requires cert.baseSha == V.baseSha (the actuator's ledger key is the (base, head) PAIR)
   ▼
Tiny Actuator        ← re-check HEAD/base; PUT /pulls/{n}/merge (merge_method=merge, sha param = expected H — atomic head CAS); GitHub executes the native MERGE
   ▼
gate_history.jsonl         ← AUDIT ONLY — evidence store is never the authority
```

### Enforcement authority (2026-10-03)

- **GitHub is the sole merge ENFORCEMENT authority.** The repository ruleset (merge queue, `merge_method`, required status checks) and the `admission-check` required status check decide merge admission at merge time. Axiom never fetches, parses, or adjudicates the live ruleset configuration.
- **Axiom is the single admission predicate producer.** `MergeAdmissible(V, mainSha)` over the §2 fact model is the only source of the `admission-check` conclusion; `dryRunExit` projects that verdict onto the check's exit code (Axiom decides, GitHub enforces).
- **No duplicate authority inside the CLI.** The former `--arm-auto` lane — which fetched the live ruleset listing, evaluated `merge_queue` / `merge_method` / required-check presence, adjudicated admission a second time, and actuated via `gh pr merge --auto` — is REMOVED: re-adjudicating the platform's own ruleset duplicated the enforcement role inside the CLI. Landing remains the single native MERGE actuation (`performMerge`, §8b) under GitHub's re-evaluation.

### Scope boundary (revised v9 — ADR-0020)

- Replace GitHub's native merge-policy layers (required checks, rulesets, merge queue). When the repository gains GitHub-native enforcement (paid plan / public repo), the GitHub adapter graduates to a GitHub App Check Run + required check. v8 said the actuator "is removed"; v9 supersedes that narrative — the **actuator procs retire into the executor adapter seam** and the **backend swaps** (ADR-0020 D7). The seam and the predicate persist. **최종 landing 설계(Owner 결정 #11, 2026-09-24 — [`repository_surface_contract.md`](repository_surface_contract.md) §Owner 결정 기록)**: backend = **단일 Landing App이 이미 정의된 기계적 수용 술어(mechanical admission predicate)를 실행**하는 층(certificate 검증 → GitHub merge-tree 요청 → CreateCommit([B,H], tree) → `updateRefs` CAS)이며, **control-plane = GitHub 조직/엔터프라이즈 거버넌스**(ruleset Restrict updates + Landing App bypass — 런타임 경로 밖)가 강제를 담당한다. v9가 상정한 "GitHub-native enforcement로의 backend swap(GitHub App Check Run / native merge queue)" 중 **native merge queue pole은 폐기**(never landed)된다 — **2026-09-29 ADR-0027 supersede**: GitHub Merge Queue = **채택된 위임 대상**(ADOPTED delegation target, candidate certification 경로; **커스텀 queue/orchestrator 금지는 유지**). Landing App은 "판단 0"이 아니다 — cert 서명 검사·(B,H) 바인딩·branch 비교·tree/parent 형태 확인은 각각 보안 관련 판정이며, 실패 = 착지 없음.
- v8 prohibited introducing "a controller, event bus, queue, database, or distributed lock" because GitHub owned event delivery and scheduling. **v9 (ADR-0020) revises this**: Axiom now owns **queue semantics** — ordered queue, speculative prefix chain, queue-journal epoch (§2b 정의), predecessor invalidation (§2b) — as a **local deterministic state journal** (`data/merge_queue/`), not a service. Still NOT introduced: event bus, database, distributed lock.
- Implement Git merge/rebase semantics. Candidate construction is the repository provider's job (GitHub builds merge-group/temporary branches — `gh-readonly-queue` prefix); Axiom core consumes `CandidateConstructionResult` through the Repository Adapter and independently verifies the materialization (§2b).

## 2. Fact model — AdmissionFacts(H)

One admission evaluation collects every PR-derived fact **exactly once** into an immutable snapshot bound to the PR head SHA `H` observed at collection start:

| Fact | Source (fetched once) | Notes |
|---|---|---|
| head / base / mergeable | `GET /pulls/{N}` | base.sha is the canonical base (check-runs' embedded base is a stale-able secondary) |
| required validations | `/actions/runs?head_sha=H&event=pull_request` (all pages) → `/runs/{id}/attempts/{attempt}/jobs` | latest run → latest attempt (§4) |
| change graph | `GET /contents/config/changes?ref=H` | immutable snapshot; flat-only contract (§5) |
| trust surface | `GET /pulls/{N}/files` (all pages) | §6; compare API is NOT used |
| main SHA | `GET /commits/{default_branch}` (actuator side) | injected via `AXIOM_MAIN_SHA` |

**Invariant (snapshot consistency)**: within one evaluation, the same fact is never independently fetched twice, and every PR-derived fact remains bound to H even if the PR moves mid-evaluation. The pure predicate consumes the snapshot once.

**missing ≠ valid empty**: `admission: none(AdmissionFacts)` (facts never collected) and an empty validations snapshot both deny — `FACTS_MISSING`. The pure predicate evaluates new security facts; absence is not interpreted as "no violations".

### 2b. Candidate extension (v9 — ADR-0020)

v8's evaluation unit was a single PR head `H`. v9 extends the evaluation unit to a **speculative candidate**: an immutable logical repository state `C` (prefix + ordered changes) that has NOT landed. Admission may bind to a candidate subject under the same snapshot discipline.

**Candidate identity — three layers (ADR-0020 D4)**:

| Layer | Fields | Question |
|---|---|---|
| `CandidateStateIdentity` | `treeDigest` | WHAT repository state |
| `CandidateProvenance` | `baseCommit, orderedChanges, repositoryIdentity` | WHERE FROM |
| `VerificationContextIdentity` | `policyDigest, toolchainDigest, verificationContractDigest` | UNDER WHAT CONTRACT |
| `CandidateEvidenceDigest` | `H(state \| provenance \| context)` | combined identity (hash-of-parts convention, `identity.nim:212-217`) |

**Queue-journal epoch and dispatch depth are NEVER part of content identity** — the queue-journal epoch is a namespace/invalidation token (`cache_policy.md:24-26`), depth is execution policy (ADR-0020 D2). baseCommit ∈ Provenance: verification-result reuse keys on `CandidateStateIdentity` + `VerificationContextIdentity` only (`reusable(U)`, P2 §4.2 — anchor `incremental_ci_contract.md` deleted with CI=0 cutover, 2026-09-20; ADR-0017 is the reference copy — no baseCommit / queue-journal-epoch / depth constituents).

**"epoch" is overloaded — three distinct quantities, never interchangeable.** In this document "epoch" unqualified means the **queue-journal epoch** (ADR-0020 D7). The other two, defined elsewhere, are: **`executionEpoch`** — the execution semantic epoch `validatedAtEpoch == ctx.currentEpoch`, which **is** an identity constituent (`execution_accounting_contract.md` §15.4); and **`ciGeneration`** — the CI cutover generation (`docs/agents/ci_epoch_cutover.md`), which **must never** enter content identity (`execution_accounting_contract.md` §15.4, `verification_dag_contract.md` §3·§12). The rule stated above applies to the queue-journal epoch; it is stated *because* the other two are easy to mistake for it.

**Logical ≠ Materialized**: the provider-built ref/commit is a *materialization claim* (`MaterializedCandidate = {candidateRef, candidateCommit, declaredTreeDigest, provenance}`). Before use: `declaredTreeDigest == resolvedTreeDigest` via an **independent read path** (different code path AND data source — e.g. `GET /commits/{sha}` → `commit.tree.sha`; a same-API re-call is NOT independent). Mismatch = fail-closed (`MATERIALIZATION_MISMATCH`) + `Theater/MaterializationMismatch` debt registration (AGENTS.md §0.9). Precedent: `runner_pool_digest.sh` (declared) vs `jit_supervisor.sh:96-117` (measured, mismatch → exit 1).

**Run↔identity binding (ADR-0020 D6)**: a verification run R is evidence for candidate I only if, at the I/O boundary (`collectAdmissionFacts` — the pure predicate consumes results only):
1. `run.head_sha` == candidate commit SHA;
2. `GET /commits/{run.head_sha}.tree.sha == candidateTreeDigest` (independent re-derivation — head_sha alone proves the commit, not the intended tree);
3. dispatch inputs contrast — API `inputs` query preferred; fallback: trusted echo (workflow definition originates from the default branch) cross-checked against (2);
4. workflow_id + path double binding (§3).

Failure → `BINDING_MISMATCH` deny. Binding results are recorded as a `binding` sub-object of the admission audit entry.

**Evidence reuse**: `reusable(U)` is unchanged. Identical `CandidateStateIdentity` + matching `VerificationContextIdentity` reuses verification results across queue-journal epochs and depth changes. A reuse is a **reuse of a prior result, not a reproduction** of it — it is authoritative reuse only when re-validated against the current context (`execution_accounting_contract.md` §15.0).

**Queue semantics ≠ execution policy (ADR-0020 D2)**: the queue journal tracks ALL entries; only the **eligible speculative frontier** (within `speculativeDepth`, a policy key in `config/policy/merge_admission.json`) *(원안 — superseded 2026-10-10: `speculativeDepth`는 저장소 전역 실측상 코드 컨슈머 0건으로 정책 키에서 삭제되었다 — 아래 갱신 노트)* is materialized and dispatched. Entries beyond depth exist as `qesQueued` state only. Depth changes never alter landing decisions.

**갱신 (2026-10-10 — 위 단락의 `speculativeDepth` 정책 키 서술은 superseded)**: `speculativeDepth`는 저장소 전역 실측(`config/`·`src/`·`tools/` grep)에서 코드 컨슈머 **0건**이 확인되어 `config/policy/merge_admission.json`에서 삭제되었다(커밋 `463597973`, PR #713 — 중복 `version` 키와 함께 정리). depth의 네이티브 등가물은 **GitHub merge queue Build concurrency(1–100)** 설정이다 — ADR-0020 D2가 인용한 바로 그 선례다. **큐 의미론 결론 자체는 영향 없다** — 큐 저널이 모든 entry를 추적하고, 적격 프론티어(eligible frontier)만 materialize·dispatch되며, depth가 착지 결정을 바꾸지 않는다는 이 단락의 기제는 그대로 유효하다. 사라진 것은 정책 키뿐이다. 정본: [docs/adr/0020-axiom-queue-semantics-and-executor-boundary.md](../adr/0020-axiom-queue-semantics-and-executor-boundary.md)(superseded 원 출처) · `config/policy/merge_admission.json`(현행 SSOT).

**Serial landing (ADR-0020 D3)**: candidates are verified in parallel; landing is serial — dequeue → PR head re-check (`STALE_EVALUATION` path) → binding verification (above) → evidence re-collection → `MergeAdmissible` → `performMerge` (native MERGE: merge_method=merge + expected-head `sha` param, §8b) → `getTreeHash() == candidateTreeDigest` re-derivation → mismatch = fail-closed. Predecessor failure invalidates only the **dispatched** suffix; beyond-depth entries are promoted in queue state without invalidation semantics.

## 3. Validation identity — check name is not identity

A required validation is satisfied only when ALL of the following hold for the **latest applicable attempt**:

1. The run's `workflow_id` matches the policy entry AND the run's `path` matches the policy's `workflowPath` (double binding; mismatch = fail-closed, e.g. workflow deletion/recreation changes the id). *v9 note: the predicate must enforce this explicitly — v8 implementation checked job name + conclusion but not workflowId; fixed in ADR-0020 Phase 5.*
2. The run's `head_sha == H` and `event ∈ {pull_request, workflow_dispatch}` — v9: `workflow_dispatch` is admissible **only** for candidate runs dispatched by the executor adapter and only under the §2b binding verification; `pull_request` remains the sole admissible event for plain PR evaluations. **ADR-0021 (2026-09-12)**: the `workflow_dispatch` entry for candidate verification is **removed** — verification execution authority belongs to repository state transitions (`workflow_run` chain, `docs/adr/0021-execution-authority.md` D2/D3). `workflow_dispatch` remains **recovery/manual only**: an operator-run local `bin/ax cert attest --ref <sha>` (D9) — never a workflow dispatch surface. **ADR-0027 (2026-09-29)**: `merge_group`이 큐 경유 후보 인증(candidate certification)의 허용 이벤트로 추가된다 — `event ∈ {pull_request, workflow_dispatch, merge_group}`; candidate head = `github.event.pull_request.head.sha || github.event.merge_group.head_sha || github.sha`(event-branching fallback = source selection, P2), `prNumber := 0`(P1 — merge_group의 head_ref는 공식 payload 스키마상 정보용이며 파싱하지 않는다). `pull_request` remains the sole admissible event for plain PR evaluations. (The §10 actuator-seam dispatch to `merge_continuity.yml` is **unaffected** — ADR-0021 D3/D9 explicitly retain it; this clause governs candidate-verification runs only.)
3. The attempt-pinned job (`/attempts/{attempt}/jobs`) exists, is unambiguous (0 or 2+ applicable jobs = deny, `AMBIGUOUS_VALIDATION`), and its conclusion equals the policy's `acceptableConclusion` (exactly `"success"` — skipped/neutral/cancelled/failure never admit).

A check-run **name** alone is not identity: a PR can define its own workflow file (pull_request runs the PR's workflow version) with identical job names. The workflow identity binding blocks same-name spoofing by a *new* workflow; trust-surface protection (§6) blocks weakening of an *existing* one.

## 4. Latest applicable run/attempt (2-level selection)

- **ApplicableRun(H, workflow)** = latest run for (workflow_id, H, event) over ALL pagination pages with an explicit total ordering (max by `created_at`, tie-break by `id`). List default ordering is never trusted.
- **ApplicableAttempt** = that run's `run_attempt` (reruns increment the attempt on the same run id).

Stale-success defense: an older successful attempt never satisfies a validation once a newer attempt exists with a different conclusion.

## 5. ChangeGraphFacts(H)

`config/changes/*.toml` is a **flat directory contract** — only top-level `*.toml` files are manifests; subdirectories (`valid/`, `invalid_*/`) are validator fixtures. All manifest reads are pinned to `ref=H`; the graph must be acyclic, all `depends_on`/`conflicts_with` targets defined, `base_ref` non-empty, conflicts symmetric. Empty manifest set = fail-closed (`GRAPH_INVALID`), never "valid".

## 6. Trust surface

The admission authority dependency closure. A PR whose changed files match any trust-surface pattern — matching `filename` AND `previous_filename` (rename detection) — denies auto-merge (`TRUST_SURFACE_MODIFIED`, manual merge required). Current closure (surviving paths per policy v1.5.0 trustSurface; the producer workflows below were deleted by the CI=0 cutover, 2026-09-20 — protection-retention history): `auto_merge.yml`, `admission_producer.yml` (v1.4.0, 2026-09-16, slice 3a — the sole admission-producer workflow; `ci.yml` is a §-1 tombstone and `readiness_start.yml` is retired as a producer, both remain listed for protection retention), `ci.yml`, `readiness_start.yml`, `verify-candidate.yml`, `setup-axiom-toolchain/**`, `canonical-bootstrap/**`, `config/policy/merge_admission.json`, `src/cli/merge_cli.nim`, plus the planned certification-continuity construction/identity modules (registered ahead of implementation in the policy SSOT — a PR touching their future paths is denied even before the modules land; the module list is maintained in `config/policy/merge_admission.json` and mapped to phases in `docs/spec/certification_continuity_contract.md` §7 Phase 0).

Detection source is `GET /pulls/{N}/files` with **full pagination** — the compare API is not used because it silently truncates at 300 files / 2500 commits with no truncation flag (false-allow risk). Two listing-completeness fail-closed conditions:

1. Pagination must terminate cleanly via Link headers (error/interruption/partial = deny).
2. Collected file count ≥ 3000 (API cap reached; completeness unprovable) = deny.

**Trust model for speculative candidates (v9 — ADR-0020 D9)**. The closure above governs which *changed files* deny auto-merge. Candidate verification additionally classifies execution:

| Class | Contents | Treatment |
|---|---|---|
| Trusted | workflow definition (default-branch checkout — activation boundary, P2 §5.5 — anchor `incremental_ci_contract.md` deleted with CI=0 cutover, 2026-09-20; ADR-0017 is the reference copy), executor/adapter code, verification policy (`config/policy/*`) | may drive control flow; may gate admission |
| Untrusted (candidate) | repository contents, candidate scripts, Makefile, nimble/build/test code | executed as verification SUBJECT data on ephemeral runners; results consumed only through §2b binding; never admitted to trust state |

This formalizes v8's "candidate-branch workflow code is never executed or trusted" to cover build/test tooling: the candidate ref checked out by a trusted workflow is data, and code executed from it is untrusted even while it runs.

## 7. Verdict vocabulary

`MergeAdmissionResult`: `mergeGo` | `mergeRebaseRequired` | `mergeChecksIncomplete` | `mergeAborted` — paired with a human `reason` and machine `reasonCode` (`GO`, `STALE_BASE`, `CHECK_INCOMPLETE`, `AMBIGUOUS_VALIDATION`, `FACTS_MISSING`, `TRUST_SURFACE_MODIFIED`, `TRUST_SURFACE_INCOMPLETE`, `GRAPH_INVALID`, `STALE_EVALUATION`; v9 additions: `MATERIALIZATION_MISMATCH`, `BINDING_MISMATCH`; Phase 5 certificate-continuity additions: `NO_CERT`, `SUBJECT_MISMATCH`, `POLICY_MISMATCH`, `SCOPE_MISMATCH`, `CERT_INVALID`; proof-required vault-cert Pass 2.96b reuses the journal-string vocabulary `NO_CERT`/`SUBJECT_MISMATCH`/`POLICY_MISMATCH`/`SCOPE_MISMATCH` with the same meaning — see [proof_required_admission_contract.md](proof_required_admission_contract.md) §3).

Publication (Model B, 2026-09-10): the exact-object publisher (`publisher.nim` — pubPublished/pubMainMoved/pubError) is REMOVED; native MERGE landing verdicts are the actuator's merge result + continuity (ccPassed/ccMismatch/ccNoCert/ccError, all fail-visible/fail-closed — §11).

## 8. Staleness and base race (explicit defense levels)

- **HEAD race**: atomically guarded — merge API `sha` parameter (atomic head CAS). HEAD drift after evaluation rejects the merge.
- **Base race**: **eliminated on the CAS landing path** — `updateRefs beforeOid` CAS가
  base compare-and-swap을 공급한다. Landing App이 `updateRefs(beforeOid=B, afterOid=M)`로
  ref를 갱신하면, 평가와 update 사이에 base가 전진한 경우 GitHub가 reject하고
  **변화가 없다**(no landing). REST merge API(`sha` 파라미터)가 PR head만 원자
  보호한 데 비해, beforeOid CAS는 base까지 원자적으로 보호해 concurrent base
  advancement 창을 닫는다.
- **Base race — closed at admission (Model B, 2026-09-10)**: landing is the GitHub native MERGE (merge_method=merge, expected-head `sha` param). Base freshness is an admission-time recheck (`origin/main == cert.baseSha` → STALE_BASE fail-closed); the merge-commit parents are verified post-landing by continuity (parent1 == base, parent2 == head). The exact-object FF-CAS publisher is removed. §11.
- **Base race — the freshness anchor is EVENT-FROZEN (ADR-0027 P4, 2026-10-05)**: the base Axiom compares against is the run's own declared anchor (`AXIOM_MAIN_SHA` = `pr.base.sha || merge_group.base_sha`), the same value the subject-continuity certificate was minted against — **not** the live `pulls/N` `base.sha`. Both sides of Pass 0 are therefore the same declared value on every CI path, so on the **queue** path the Axiom-side freshness deny is an identity against the queue's own authoritative base and no longer fires there (it fired spuriously: the queue advances the base while the PR snapshot lags, so one landing PR invalidated every other queued PR — ~247 min of wasted CI measured 2026-10-04). The deny is **not removed** — it still fires when a declared main differs from the recorded anchor and for any caller reaching the predicate without an anchor (`BASE_UNRECORDED` is unreachable from the CLI paths, which reject an unset `AXIOM_MAIN_SHA` before collecting; the fail-closed branch is kept). On the **PR** path a base that moves *during* the run is still denied, by the workflow's identity re-derivation (`admission-check.yml` mint step fails closed when `PR base.sha != B`) and by GitHub's strict required-check invalidation — the Axiom predicate is not what covers that window. `loadLedgerCertFor`'s (base, head) PAIR key stays aligned with the anchor by construction, and Pass 2.96 denies `cert.baseSha != V.baseSha` so a mis-paired certificate can never be admitted.
- **Stale evaluation**: `Evaluation(H)` is computed entirely on the H snapshot, but is applicable only to H. If the current PR head ≠ H at evaluation end → `STALE_EVALUATION` deny + re-evaluate. *v9 (ADR-0020): the same snapshot discipline applies to candidate subjects — a candidate is landable only while its prefix has landed (`HEAD == rebase(parent)`) and its materialization + binding checks still hold.*
- `mergeable_state` is a supporting signal only (unknown → fail-closed); the core truth is checks ∧ change graph ∧ base freshness.

## 8b. Invariant chain, merge call semantics, atomicity boundary (2026-09-11 — v5 architecture)

### Final invariant chain

```
H → independently verifiable evidence → admission(H, evidence) → native MERGE(H) → L → continuity(L, H)
```

Whether a persistent ledger certificate is a **REQUIRED admission input** is a **separately proven product decision** (authority-artifact minimization analysis — pending). This document does not encode certificate necessity as settled here; `certRequired` (config/policy) remains the trigger, and the §11 admission pass applies only when certificate facts are bound to the admission snapshot.

**Certificate family boundary (2026-10-09 — boundary documentation only; the pending decision above stays OPEN, neither retracted nor adopted)**: two certificate families exist and are deliberately NOT interchangeable.

- **Vault certificates** — the `CertificateStatus` tier certificates (`certGreen` / `certLeanVerified` / `certDualVerified` / …) held in the certificate vault (runtime-canonical store `data/trusted/certificates`; canonical read `src/verification/certificates` — `cert_vault_role.nim`). Their consumers are the VKD / readiness / baseline projections (`docs/spec/verification_density.md`, `src/cli/shared/baseline_snapshot_core.nim`) — **NOT merge admission**. No `MergeAdmissible` pass reads a vault certificate, and wiring vault certificates to the `admission-check` required check is **Out of Scope** of this contract.
- **Subject-continuity certificates** — `kind == "subject-continuity"` objects produced by the attest→mint→ledger chain (`admission-check.yml` attest stage: D9 evidence staging + subject register, :985-1062 → mint publish → side-ref ledger / artifact transport). This is the ONLY certificate family admission can consume: the ledger transport is kind-gated at `src/cli/merge_cli.nim:1449` (`loadLedgerCertFor` — non-matching `kind` is skipped), the artifact transport at `:1515` (`verifiedCertificateArtifact` / `certificateFactFromPath`, :1526-1539 — non-matching `kind` is a fail-closed error), and Pass 2.96 (:700-742) enforces the bound facts fail-closed.

### Actuator responsibility ceiling

The actuator outputs the known landing OID `L` and **terminates**. "Landing event / known `L` → continuity verifier" is a **platform wiring seam** — a YAML step that invokes `merge_continuity.yml` via `workflow_dispatch` with `expectedOid` — NOT actuator logic. **No orchestration creep**: the actuator never invokes downstream subsystems.

### Merge call semantics (single-shot; no merge-time retry)

The one call is `PUT /pulls/{N}/merge`, `merge_method=merge`, `sha` param = expected head `H` (atomic head CAS — head drift after evaluation rejects the merge). Interpretation:

| Outcome | Meaning | Handling |
|---|---|---|
| 2xx | success | response body `sha` = merge commit OID `L` (the observation basis) |
| non-2xx → `GET /pulls/{N}`: `head.sha != H` | head moved after evaluation | **STALE_HEAD** deny — re-certify (fresh evaluation/certificate), **no merge-time retry** |
| non-2xx → `GET /pulls/{N}`: `head == H`, 405/409 | merge not possible / head mismatch | **deny** (no retry) |
| 403/429 with rate-limit headers | permission / rate limit | **deny**; rate-limit headers recorded in the journal only (the actuator never raises the limit) |
| 422 | validation failed / endpoint spammed | **deny** |

**Observation basis — `merge_commit_sha` is NOT used**: the `.sha` field of the merge response body is the observed merge commit OID. The `merge_commit_sha` field on PR responses is **scheduled for removal in REST API version 2026-03-10** ([breaking changes](https://docs.github.com/en/rest/about-the-rest-api/breaking-changes) — "Remove merge_commit_sha field from pull request responses"); observation must not depend on it.

**Success postcondition**: after a 2xx, `GET /pulls/{N}/merge` == **204** confirms the PR is merged/closed.

### Merge ↔ ledger atomicity prohibition

GitHub provides **no atomic merge + external-side-effect primitive**: webhooks are documented **at-least-once, unordered, lossy, and without automatic redelivery** ([handling failed webhook deliveries](https://docs.github.com/en/webhooks/using-webhooks/handling-failed-webhook-deliveries) — "GitHub does not automatically redeliver failed deliveries"; [troubleshooting webhooks](https://docs.github.com/en/webhooks/testing-and-troubleshooting-webhooks/troubleshooting-webhooks) — "Webhooks deliveries are out of order" + no auto-redelivery). **No code may rely on a ledger write being atomic with MERGE.** The failure window between MERGE and any ledger state change is proven **post-hoc by continuity** — the merge-commit parents vs the certified `(baseSha, headSha)` — **not** by atomic coupling.

### CI-green note for actuator landings

A `GITHUB_TOKEN` merge does **not** trigger push-event workflows (documented token recursion rule — GITHUB_TOKEN-triggered events other than `workflow_dispatch`/`repository_dispatch` do not create workflow runs; see [automatic token authentication](https://docs.github.com/en/actions/security-for-github-actions/security-guides/automatic-token-authentication) and [events that trigger workflows](https://docs.github.com/en/actions/writing-workflows/choosing-when-your-workflow-runs/events-that-trigger-workflows)). Post-merge main verification is the canonical-main `[continuity]` step
(`ax cert continuity` — `merge_continuity.yml` itself retired 2026-09-18, its
cert-selection walk extracted into tools/ci/run_landing_continuity.sh).
**CI-green claims for actuator landings are environment-specific verification procedures, not product invariants.**

## 9. Purity and boundary

- `MergeAdmissible(V, mainSha)` is a `func {.raises: [].}` — the Nim compiler's effect system (no IO inside `func`) plus the empty-raises pragma enforce purity at compile time. Facts collection lives in the I/O boundary (`collectAdmissionFacts`, procs with `axiomEffect: IOEffect`). *v9 (ADR-0020): materialization verification (§2b) and run↔identity binding (§2b) also live in the I/O boundary; the predicate consumes their results (`bindingVerified`) as snapshot data.*
- `mainSha` is the EVENT-FROZEN base of the run (`AXIOM_MAIN_SHA` = `github.event.pull_request.base.sha || github.event.merge_group.base_sha`), read from the environment before the snapshot is collected and used as BOTH the declared main and the snapshot's base anchor; it is not re-fetched from the API at evaluation time (a live re-read is what produced the queue-path false denies — ADR-0027 P4). The CLI refuses to evaluate without it (no testedBaseSha fallback — the old fallback made base freshness vacuously true, and the removed live-PR-API fallback would have re-introduced the lagging anchor).
- The actuator must not execute candidate-branch workflow code; the evaluator implementation originates from the default branch. `audit evidence (gate_history.jsonl) is never an authority. *v9: candidate repository contents (including build/test tooling) are untrusted data (§6 trust model) even though the runner executes them.*

## 10. Executor seam (v9 — ADR-0020; supersedes "temporary actuator")

The `auto_merge.yml` actuator (deleted by the CI=0 cutover, 2026-09-20 — historical design record): triggers on `workflow_run` completed for `ci.yml`/`readiness_start.yml`, runs on main checkout, invokes `ax merge --dry-run`, interprets **only** `mergeGo`, re-checks HEAD+base, then calls `PUT /pulls/{N}/merge` (merge_method=merge; `sha` param = expected head H — atomic head CAS; GitHub executes the native MERGE). Merging is **single-shot (no merge-time retry)**; §8b defines the merge call semantics. Concurrency group `auto-merge-pr-N` (`cancel-in-progress: false`) is duplicate suppression only. `permissions: {contents: write (native MERGE — GitHub documents merge under Contents write), pull-requests: read (GET /pulls, /pulls/files), checks: read (GET /commits/{sha}/check-runs), actions: read (GET /actions/runs + attempts/jobs)}`; `actions: write` appears only on the platform-wiring dispatch step (invoking
`merge_continuity.yml` via `workflow_dispatch`; `merge_continuity.yml` itself
retired 2026-09-18 — S1 slice, dead artifact with 0 callers). **GITHUB_TOKEN only** — no PAT / GitHub App.

v8 framed the actuator as temporary — removed when GitHub-native enforcement arrives. **v9 reframes (ADR-0020 D7)**: the actuator procs become the first implementation behind an **executor adapter seam** — the abstract event `CandidateDispatched` translated by a provider adapter (GitHub: `workflow_dispatch` + merge API). **백엔드 최종 형태(Owner 결정 #11, 2026-09-24)**: backend = **단일 Landing App**(기계적 수용 술어 실행 + `updateRefs` CAS — runtime mutation authority)이며, **native merge queue pole은 폐기**(never landed; **2026-09-29 ADR-0027 supersede** — GitHub Merge Queue = 채택된 위임 대상, 커스텀 queue/orchestrator 금지는 유지); control-plane 강제는 **GitHub 조직 거버넌스(ruleset Restrict updates + Landing App bypass)**가 담당한다. **The seam and the admission predicate persist.** GitLab/self-hosted backends require a committed customer contract (§0.12) before implementation.

## 11. Exact-object publication (Phase 5 — certification continuity, additive)

The certified path (certification_continuity_contract.md §4.1 "[Admission + publication]") publishes the **exact certified subject M** instead of calling the GitHub REST merge API:

```
ax merge publish --cert <certPath> [--pr N]
  cert structural verify + --kernel re-execution   → CERT_INVALID on failure
  sha256(policy file) / sha256(scope lock) == cert digests → POLICY_MISMATCH / SCOPE_MISMATCH
  fetch origin main == cert.baseSha                 → STALE_BASE (old cert invalid → re-materialize)
  re-materialize candidate from current main        → tip != cert.candidateCommit → SUBJECT_MISMATCH
  ledger membership (side-ref SSOT, INV-8)          → NO_CERT on absence / CERT_INVALID on mismatch
  [REMOVED — Model B] publisher.publishM FF-CAS push (superseded by native MERGE + continuity)
  → ls-remote == M (pubPublished) → PATCH /pulls/N state=closed → journal merge-publish
```

**Coexistence (§10 executor seam) — SUPERSEDED (Model B, 2026-09-10)**: the
exact-object publish path (`publishM`, `ax merge publish`) is REMOVED. The
REST merge actuator (`ax merge --apply` → `performMerge`, merge_method=merge,
expected-head `sha` param) is the ONE main landing path, gated by the
Model B sequence: load ledger cert → verify → base/head freshness →
policy/scope → admission → native MERGE → merge-commit parents verification →
continuity verdict → journal. "Only the certified path may advance main" is
now enforced in the actuator itself (NO_CERT/CERT_INVALID/STALE_BASE/
SUBJECT_MISMATCH fail-closed before merge). GitHub UI merge by a human cannot
be blocked on the free plan — continuity is the documented fail-visible
backstop.

**Base race closed at admission for this path (Model B)**: the REST merge API cannot guarantee candidate-identity preservation, so the invariant moved to input certification: the actuator re-checks `origin/main == cert.baseSha` immediately before merge (STALE_BASE fail-closed), pins the head with the expected-head `sha` parameter (409 on head drift), and continuity verifies the landed merge commit's parents (parent1 == base, parent2 == head) and head tree binding after landing — a moved base between admission and merge surfaces as parent1 mismatch (ccMismatch, fail-visible) → re-certify against the new base.

**PR close semantics** (contract §4.3): the rebase chain M does not make GitHub see the PR as merged (M's commits are not the PR head commits), so the actuator closes the PR via `PATCH /pulls/{N} {"state":"closed"}` and the **GitHub merged status is deliberately NOT produced**. The `merge-publish` journal record — `{prNumber, certId, candidateOid, preMainSha, postMainSha, verdict}` in `.axiom/gate_history.jsonl` — is the SSOT linking PR ↔ certificate ↔ main commit.

**Native MERGE landing (Model B, 2026-09-10)**: landing is the GitHub native merge commit (merge commit enabled; rebase/squash disabled at the repo level) — the certified (base, head) become the merge commit's two parents, preserving head-reachability and enabling mechanical continuity verification. The rebase-chain materializer (`merge_materializer.nim`) is removed.

**Certificate-continuity admission pass (pure)**: `MergeAdmissible` Pass 2.96 (between the candidate-binding pass and base freshness) enforces the same gates when certificate facts are bound to the admission snapshot: certificate presence (`NO_CERT` — missing ≠ valid empty, triggered by `certRequired`), Ed25519 signature (`CERT_INVALID`), `cert.candidateCommit == actualCandidateCommit` (`SUBJECT_MISMATCH` — INV-1 exact-object binding, no tree re-derivation per INV-3), policy/scope digest equality (`POLICY_MISMATCH` / `SCOPE_MISMATCH`). Base freshness remains the final, unchanged pass (`STALE_BASE`). Facts are collected at the I/O boundary by `collectCertificateContinuityFacts` (side-ref ledger list + per-cert download via `ledger_side_ref.downloadLedgerCertificate`, injectable transport for local-mode tests). **Pass 2.96은 executor identity를 평가하지 않는다** — executor epoch와 base epoch는 분리 불가(두 epoch 모두 §2b의 큐 저널 epoch 의미이며 `executionEpoch`/`ciGeneration`이 아니다 — §2b epoch 정의 참조; blob이 바뀌는 merge는 base를 전진시키는 merge → STALE_BASE가 이미 epoch 결합을 담당); 발급 권한만 TrustedExecutorSet(ADR-0021 D7, `config/executor_authority.json`)이 게이트한다.
## E2E actuator case-2 landing exercise (2026-09-12)

Non-trust-surface change: documentation note only. The certified-subset probe (src/verification/continuity_probe.nim) is unchanged at this head — the evidence emission step reads it via `git show <head>`. This PR exercises the full production path: verify-candidate evidence emission → attest binding verification → subject registration → certificate mint → ledger append → admission (Pass 2.96) → native MERGE → continuity.
