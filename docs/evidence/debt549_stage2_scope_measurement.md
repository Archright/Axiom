# DEBT#549 Stage 2 — 스코프 측정 증거 (2026-11-18)

> **종류**: 측정 증거(measurement evidence)다 — **결정이 아니다**. full-scope FAIL과 CI-scope PASS는 동일 커밋에서 관측된 두 스코프의 실행 결과이며, 어느 스코프가 제품 판정의 정본인지는 이 문서가 결정하지 않는다.
> **측정 대상**: 커밋 `983e8360f876acb058dd0ff78e6f50c2f0c60ffa`, 일회용 worktree `/tmp/axiom-stage2` (detached HEAD), 측정일 2026-11-18.
> **환경**: `bin/ax` v0.6.4 · Nim 2.2.10 · z3 4.13.3 · Lean 4.33.0 (elan). `lake build ircheck` 성공(6.8s). 모든 실행은 `AXIOM_CI=1` + 최소 `env -i` 환경.
> **기계 산출물**: [debt549_stage2_artifact.json](debt549_stage2_artifact.json) — sha256 `7b9e7f845ecca207ae4fd1af4e829370c5fea584fe3026c429ad3f345bb1c748`.

## §1. 실행 결과

| # | 스코프 | 명령 | Exit | `gateVerdict` | Wall |
|---|---|---|---|---|---|
| 1 | full (fresh state) | `AXIOM_STATE_DIR=/tmp/stage2-state-full bin/ax prove` | **1** | **FAIL** | 56s (01:44:07Z→01:45:03Z) |
| 2 | CI (fresh state) | `AXIOM_STATE_DIR=/tmp/stage2-state-ci bin/ax prove --target normalizeMaxWorkers` | **0** | **PASS** | 70s (01:46:03Z→01:47:13Z) |
| 3 | CI (warm state, 동일 state dir) | `AXIOM_STATE_DIR=/tmp/stage2-state-ci bin/ax prove --target normalizeMaxWorkers` | **0** | **PASS** | 28s (01:47:35Z→01:48:03Z) |

로그: `full_fresh.log` (`EXIT=1`, sha256 `519607caba5d55d04ec030c9da358777eccb7492a50c8511b0cf5fc1e5f85483`), `ci_fresh.log` (`EXIT=0`, sha256 `cbb79a600406e36ae23f9ad8d34e083da9445c390e54d185995d6df7a304905f`), `ci_warm.log` (`EXIT=0`, sha256 `96484f772144d4d808d5485f4726a8b740df2f20c30ea5ba501a698a6946f6d6`). 판정은 각 실행의 `$AXIOM_STATE_DIR/logs/ax_proof_state.json`에서 읽었다 — 인-레포 실행은 stdout에 JSON verdict를 출력하지 않는다(`src/cli/axiom_engine.nim:6086-6088`).

## §2. Full-scope: FAIL

`runAccounting` (`/tmp/stage2-state-full/logs/ax_proof_state.json`, sha256 `5d894db400259008670b3fcdfaa0dd84b33b53f6c6accd5dd20dcf63bf71ad6f`):

| required | satisfied | unsatisfied | pending | contested | proofFailed |
|---:|---:|---:|---:|---:|---:|
| 5 | 2 | 1 | 2 | 2 | 1 |

full-scope(무 `--target`)는 40개 커널 심볼 전체가 아니라 **5개 canonical unit**을 계획했다 — eligibility gate가 16,163개 중 5개를 통과시켰고(`full_fresh.log:19`), `firstIntCore`는 상류에서 `semantic.unresolved-fact`로 제외됐다(`full_fresh.log:15`).

| Unit | 결과 | 근거 |
|---|---|---|
| `normalizeMaxWorkers` | SATISFIED (FRESH) | `full_fresh.log:83` |
| `proximityScore` | SATISFIED (FRESH) | `full_fresh.log:86` |
| `safeSpeedupRatioCore` | **UNSATISFIED** | `EA_UNSUPPORTED: unsupported AST node (ckIfStmt)` — certified subset 밖 (`full_fresh.log:28`), `[FAILED]` (`:85`) |
| `calcDynamicTimeoutCore` | **CONTESTED** (PENDING) | canonical OGR=REQUIRED, runtime `orchestrationNoObligation`; `evidence=inconclusive`, "invariant does not imply postcondition" (`full_fresh.log:24,26,54-55`) |
| `firstBoolCore` | **CONTESTED** (PENDING) | canonical OGR=REQUIRED, runtime `certNoObligation` (`full_fresh.log:59-60`) |
| `firstIntCore` | eligibility-excluded | `rejection=semantic.unresolved-fact`, 시도되지 않음 (`full_fresh.log:15`) |

`failed_symbols`는 비-SATISFIED 3개 unit을 모두 나열하고, `unsatisfied_count`는 UNSATISFIED 행만 센다. CONTESTED = canonical OGR REQUIRED ∧ runtime no_obligation(`src/verification/accounting/run_accounting.nim:725-729`).

## §3. CI-scope: PASS

`--target normalizeMaxWorkers`는 정확히 **1개 unit**을 계획했다(`ci_fresh.log:8-9`). `runAccounting`: required=1, satisfied=1, unsatisfied=0, contested=0, pending=0 (`/tmp/stage2-state-ci/logs/ax_proof_state.json`, fresh sha256 `aca7e5b045717a1ebc90bce65ff9f191097c8a82b02ab7f2f1fa60e42fc6399b` → warm sha256 `eaeac7e7d0808e56bf74453955d76cfe38c59160b6c93417dcb7fcc7662463f3`). `runOutcome.gateVerdict=PASS` (`ci_fresh.log:59`).

즉 **동일 커밋이 full scope에서 FAIL, CI scope에서 PASS**다 — 두 스코프는 상호 교환 가능하지 않다.

## §4. Warm CI-scope: state는 재사용, certificate는 재사용 아님

warm 실행도 PASS했지만 `satisfiedByReused=0`, `reuseEligibleRowCount=0`, `summary.solverInvocationCount=1`이다. certificate는 **바이트 동일**하게 재방출됐다 — `build/certificates/e57ee9394d16b8dcb8a859eb205f59a55dc3926227dc2250a21448c8d5ebf200.json` sha256 `bae2e26c5a740dab7e31076a3048f4825d37f56b87608d00d8fdfb608a384a41` (fresh·warm 동일). `build/certificates/manifest.json`만 `lastVerifiedAt`으로 변경됐다(fresh `6dca3b398765fd7c75673f3571798046d0a29d63d2a6da708809c90ddccafef4` → warm `1ebfbf26feddd57f45645271aa17fbcf03ba5e3cbacf2e4e2fc6b776f34f02af`). 읽기는 repo-relative `data/trusted/certificates`, 쓰기는 `$AXIOM_STATE_DIR/build/certificates`다(`src/verification/cert_vault_role.nim:21-29`; `src/cli/axiom_engine.nim:5366`).

warm 단축은 proof reuse가 아니라 **topology/graph 캐시**에서 나왔다: 동일 state dir의 cold CI 실행 `topology: 2562 files, 2562 changed`(`ci_fresh.log:5`) → warm `2562 files, 570 changed`(`ci_warm.log:5`). `logs/z3_telemetry.jsonl`는 2,912 B → 5,824 B(총 16 records)로 증가해 warm에서도 solver 호출이 있었음을 확인한다.

## §5. Digest (재계산 값)

| Artifact | sha256 |
|---|---|
| `docs/evidence/debt549_stage2_artifact.json` | `7b9e7f845ecca207ae4fd1af4e829370c5fea584fe3026c429ad3f345bb1c748` |
| `stage2_artifact.json` (source copy) | `7b9e7f845ecca207ae4fd1af4e829370c5fea584fe3026c429ad3f345bb1c748` |

복사 전후 digest가 일치하며 `cmp`로 바이트 동일을 확인했다. artifact `measured_at_utc` = `2026-11-18T01:50:08Z`.

| Log | sha256 |
|---|---|
| full fresh | `519607caba5d55d04ec030c9da358777eccb7492a50c8511b0cf5fc1e5f85483` |
| ci fresh | `cbb79a600406e36ae23f9ad8d34e083da9445c390e54d185995d6df7a304905f` |
| ci warm | `96484f772144d4d808d5485f4726a8b740df2f20c30ea5ba501a698a6946f6d6` |

## §6. 한계와 스코프 주의

- **완전히 빈 state dir는 fail-closed**: exit **2**, `loadKernelScope fail-closed: lock file missing at '/tmp/stage2-state-full/data/verification_scope.lock'` (`full_fresh_empty_state_attempt.log`, sha256 `5ce05704e2ef3c3838421d2db25d542ed4de4f7cffac7389748d46c94e1e9c4c`). 따라서 fresh state dir는 `data/verification_scope.lock` + `data/baseline.json`만 커밋에서 바이트 동일하게 복사해 seeding했다 — `.github/workflows/byo-agent.yml:217-226`과 동일한 seeding이다.
- full-scope 로그의 IR pipeline "Total 4 / Pass 2 / Fail 2"(`full_fresh.log:40-43`)는 추출된 IR entry 수이며, run-accounting의 5개 unit과 다른 계수다.
- `make build`가 일회용 worktree에서 추적 대상 `src/generated/build_metadata.json`을 재생성했다. 수동 편집·커밋·reset·checkout은 수행하지 않았다.
- 이 문서는 측정 기록이며, DEBT#559(별도 엔트리)는 readiness evaluator의 fail-open을 **등록만** 한다 — 수정은 이 슬라이스 범위 밖이다.