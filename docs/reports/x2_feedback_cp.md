# X2 Cycle F-A — FEEDBACK_CP Baseline + Decision Record

> 작성일: 2026-09-07 · 상태: **DECISION RECORD — baseline evidence 확정**
> 범위: docs + data only (production code 변경 없음). `ci.yml` / `AGENTS.md` / `import_encapsulation_gate.nim` / `config.nims` importEncapsulation 블록 미변경 (§-1).
> 증거 SSOT: `data/benchmarks/x2_feedback_cp_baseline.json` (schemaVersion 1.0)

---

## 1. 요약

CI 최적화의 목적함수를 **단일 CI_RUN_CP**에서 **2-목적함수**로 분리한다. 최상위 목표는 `FEEDBACK_CP`(PR CI → merge → post-merge CI가 개발자에게 돌아오는 critical path)의 최소화이며, CI_RUN_CP는 그 하위 구성요소다. 실측 페어 2건으로 FEEDBACK_CP baseline을 확정하고, PR CI ⊇ post-merge CI 정적 증명으로 F-B/F-C 설계의 근거를 고정한다.

## 2. 2-목적함수 분리 (CI_RUN_CP vs FEEDBACK_CP)

| 목적함수 | 정의 | 실측 baseline |
|---|---|---|
| **CI_RUN_CP** | 단일 CI workflow run의 critical path | warm 28m37–45s / stale 59m24s |
| **FEEDBACK_CP** | PR CI → merge → post-merge CI가 개발자에게 돌아오는 critical path | fresh 페어 57m22s / stale 페어 ~118m48s |
| **topLevelTarget** | FEEDBACK_CP 최소화 | — |

실측 페어 (run ID는 GitHub Actions API로 검증 완료 — §7):

| PR | prRun | prVi | postMergeRun | postMergeVi | feedbackCP | cacheState |
|---|---|---|---|---|---|---|
| 47 | 34055586611 | 28m45s | 34079669387 | 28m37s | **57m22s** | fresh |
| 46 | 34062398285 | 59m24s | 34066011764 | 59m24s | **118m48s** | stale |

- fresh 페어: PR 47 → merge(`c786f8934`, PRUNE #1) → post-merge push run.
- stale 페어: PR 46 → merge(`37f944d71`) → post-merge push run.
- **FEEDBACK_CP baseline = 57m22s (fresh) / ~118m48s (stale)**. stale 값은 상한(upper bound)으로만 명시한다 — 캐시 신선도에 따라 변동하며 최악 관측값이다.

## 3. PR ⊇ post-merge 정적 증명

**Claim**: base가 움직이지 않은 rebase-merge PR에서, PR CI가 보장하는 것 ⊇ post-merge CI가 보장하는 것 — 3개 verify job(verify-static, verify-integration, verify-coverage-guard)이 100% content-redundant.

**jobIdentity** (agent 검증): 세 job 정의는 event-agnostic으로 동일 — `ci.yml:58/:179/:311`의 `if: github.event_name != 'schedule'` 조건으로 push/pull_request 양쪽에서 동일 실행. event-dependent한 부분은 오직:
- checkout ref: PR은 `refs/pull/N/merge`, push는 pushed SHA — base가 안 움직이면 같은 tree (GITHUB_SHA=refs/pull/N/merge semantics).
- coverage-guard cache key: `ci.yml:326` — PR은 `base.sha`, non-PR은 `github.sha`.

**잔여 3목록** (post-merge가 추가로 보장하는 것):
1. **base-moved merged-tree coverage** — auto_merge.yml base-freshness guard(`PR_BASE != MAIN_SHA → rebase/re-run required`)가 대부분 선차단; 잔여 = 수동 merge + base-race window.
2. **generate-docs ~2m** (main-only job).
3. **nightly** (`[run-nightly]` gated, schedule 전용).

## 4. FEEDBACK_CP baseline

- **57m22s (fresh)** — PR CI 28m45s + post-merge CI 28m37s.
- **~118m48s (stale)** — 59m24s × 2. stale 값은 **상한(upper bound)으로만** 명시: 캐시 신선도에 좌우되며 목표 수립에 최악 관측값으로 사용한다.
- 목표: F-B+F-C 랜딩 후 FEEDBACK_CP = CI_RUN_CP 1회 (warm 15.3m / cold 31m) — §5.

## 5. F-B / F-C 설계 요약

**F-B — 2xCX23 2-runner split**: R1(bootstrap → e2e-full → verify-contract(g7-consume) → ci-gates) + R2(ci-unit-tests ‖ verify-all ‖ test-gateway ‖ ci-lake-build). `bin/ax` 8.4MB artifact를 R1→R2로 전달; R2는 cache restore-only. 기대 CI_RUN_CP: warm 28m37s → **15.3m** / cold **31m**.

**F-C — post-merge tree-identity detector**: pushed SHA → `commits/{sha}/pulls` API → `refs/pull/N/merge^{tree}` vs `HEAD^{tree}` 비교; 동일하면 3개 verify job skip. generate-docs/nightly는 보존. L2 역할 재정의(§6).

**기대 FEEDBACK_CP**: F-B+F-C 랜딩 시 = CI_RUN_CP 1회 (warm 15.3m / cold 31m).

## 6. tree-identity detector 설계 (fail-closed)

- 흐름: `pushed SHA → GET commits/{sha}/pulls → refs/pull/N/merge^{tree} vs HEAD^{tree}`.
- tree 동일 → 3개 verify job skip (PR CI가 이미 merge-boundary tree를 검증했으므로).
- **fail-closed**: API/ref 조회 실패, PR 없음, tree 불일치 → 전체 run (skip 금지). detector는 "검증 제거"가 아니라 **중복(DUPLICATION) 제거**만 허용한다 (§8 invariants).

## 7. L2 역할 재정의 제안

- 현행: `docs/agents/operations.md:122` — "main CI | post-merge / full certification (L2)".
- 제안: PR CI = **merge-boundary certification**, post-merge = **merged-tree/docs certification** (generate-docs + nightly 포함).
- 갱신 예고: `docs/agents/operations.md:122` + `docs/spec/incremental_ci_contract.md` §5.3 (L2 — 전체 인증) — F-C 랜딩 시 함께 갱신한다.

## 8. 하드웨어 right-sizing

하드웨어 right-sizing(러너 확장/교체)은 **CP < 10m 도달 이후의 escalation option**으로만 명시한다. 현재 단계의 1순위는 F-B/F-C (워크플로우 구조 + 중복 제거)이며, 하드웨어는 그 후속 수단이다.

## 9. 근거 인용

- agent 검증: 3 verify job event-agnostic 동일 정의 `ci.yml:58/:179/:311`; coverage key `ci.yml:326`; auto_merge base-freshness guard (`auto_merge.yml` PR_BASE vs MAIN_SHA); GITHUB_SHA=refs/pull/N/merge semantics.
- 실측 run IDs: `34055586611` (PR 47) / `34079669387` (post-merge push @c786f8934) / `34062398285` (PR 46) / `34066011764` (post-merge push @37f944d71) — GitHub Actions API로 conclusion=success, event 타입 확인.
- invariants: semantic equivalence · verification coverage (중복 제거만, 검증 제거 금지) · determinism · isolation · fail-closed detector.
