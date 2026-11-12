# CI Epoch Record — S5 build-skip (검증 공급 재사용 — landing B-cache HIT 재컴파일 소멸): Freeze / Record / Tombstone

> **성격**: AGENTS.md §2.5(CI Epoch Cutover Protocol) 단계 1–3 — **FREEZE / RECORD / TOMBSTONE** 기록 문서. 변경 = admission 파이프라인 job1(build-base-artifacts, landing venue)에 **S5 build-skip** 도입: B-restore 검증 OK(HIT) 시 컴파일 블록(nimcache probe / Lake smoke / `make ci-bootstrap`+ircheck 빌드)을 생략하고 **복원·검증된 payload를 공급으로 사용**. MISS·폐기는 기존 fail-closed 콜드 빌드 유지. 판정(job2 attest·verdict 전 체인)은 불변. 근거 = **J3 §3.1**(HIT = 검증된 계산 공급 재사용, 판정은 항상 재계약 — `docs/spec/ci_optimization_tcb_judgments.md:151-153`) + census 실측(`docs/evidence/ci_structural_duplicate_census_2026-09-30.md:43` — B-HIT 레인 warm 재컴파일 ~86s, 콜드 134–195s) + ADR-0032(landing venue 경계).
> **작성일**: 2026-10-09.
> **작업 브랜치**: `feat/s5-build-skip`.
> **결정 바인딩**: `docs/spec/ci_optimization_tcb_judgments.md` §3.1 (S5 봉인 해제 근거, 2026-10-07 착지 — `docs/evidence/j3_manifest_anchoring_2026-10-07.md`) · ADR-0032 · `data/ci_pareto/selection_table.json` processCaveats("S5 cache optimization unsealed").
> **기록 관례**: `docs/evidence/epoch_record_venue_split_2026-10-09.md`(Freeze/Record/Tombstone 템플릿) 준용.
> **변경 범위 판정**: SL-08 빌드 스테이지의 **공급 조달 방식 변경** — 판정 규칙·아티팩트 표면·required check·TWS writer 등식 불변. `admission-check.yml` blob 변경이 수반되므로 3파일 pin 유닛(`trustedAdmissionWorkflowSha`·`productionExecutionPin`)이 **동일 커밋**에서 원자 회전된다(ADR-0022 §5, G2a 의무 쌍).

---

## §0. 표면(surface) 판정

- 편집 대상 실측: `.github/workflows/admission-check.yml` → **CONTROLLED**, `config/trusted_writer_set.json`·`config/policy/epoch_manifest.json` → 정책 경로. `make check-repository-surface` = **exit 0**(§2.4).
- 신규 `tests/ci/test_s5_build_skip.nim`·`docs/evidence/epoch_record_s5_build_skip_2026-10-09.md` = PRODUCT ADD — 동일 게이트에서 판정.

## 1. Freeze (AGENTS.md §2.5 단계 1)

| 항목 | 값 |
|---|---|
| freeze tag | **`ci-frozen-2026-10-09-s5`** (annotated) |
| 태그 타입 | annotated — `git cat-file -t ci-frozen-2026-10-09-s5` = `tag` |
| freeze 대상 | origin/main == 작업 기준 HEAD == **`4a6ed589be3664f8a9962d4e61dd01a21e91d046`** |
| 실측 검증 | `git rev-parse ci-frozen-2026-10-09-s5^{commit}` == `4a6ed589b` — 일치 |
| push | **아니오 — 로컬 전용** (기존 `ci-frozen-*` 시리즈 동일 관례) |

## 2. Record (AGENTS.md §2.5 단계 2)

### 2.1 변경 요약 (본문 4파일 + 본 기록)

| 파일 | 변경 |
|---|---|
| `.github/workflows/admission-check.yml` | job1(build-base-artifacts)에 **`[s5] Supply-mode judgment`** 스텝 1개 추가(toolchain 액션 직후, sl08 ∧ landing 게드, mode 중립 — 판정자가 자기 판정에 종속되지 않음): 복원 payload 전 멤버(4 ci-compile 바이너리 + ircheck + fingerprint manifest + nimcache 클래스)의 존재·실행비트 검사 후 `mode=skip`(명시적 라인 **`SUPPLY REUSE — verified payload restored; compile skipped (ADR-0032/J3 §3.1)`**) 또는 `mode=build`(**`S5 COLD BUILD — verified supply absent …`**). 컴파일 경로 3스텝(nimcache functional probe / Lake build smoke / Build bin/ax+harness)에 `steps.s5-supply.outputs.mode == 'build'` 컨정크트 추가 — **HIT 시 스킵**. manifest emit + 업로드 2종(admission-check-base-artifacts / base-nimcache)은 **양 모두 실행** — emit은 skip 경로에서 복원 바이너리를 fail-closed(`test -x` + sha256) 결속하므로 job2·mint·publisher 소비 표면(build_sha==B + per-file sha256) 불변 |
| `config/trusted_writer_set.json` | `trustedAdmissionWorkflowSha`: `9ed9826ad…` → **`62294da238826552afb778e6107fc8bbaf113647`** (신규 admission-check.yml blob — A2 원자 쌍) |
| `config/policy/epoch_manifest.json` | `productionExecutionPin`: `9ed9826ad…` → **`62294da2…`** (TWS와 동일 커밋 동일값) |
| `Makefile` | `test-unit`에 `tests/ci/test_s5_build_skip.nim` 등록 |
| `tests/ci/test_s5_build_skip.nim` | 신규 — 스텝 본문을 YAML에서 원문 추출 실행하는 파손 시뮬레이션: (a) HIT → mode=skip + SUPPLY REUSE 라인 + emit이 복원 바이너리 5종 digest 결속 (b) MISS 전체/부분(nimcache·ircheck 결손·실행비트 소실) → mode=build + COLD 라인 (c) verify FAIL 폐기 잔존 상태(discard_b가 fingerprint만 남김 — 원문 사실) → mode=build (d) mode 컨정크트 보유 스텝 집합이 컴파일 3종으로 정확히 닫힘 + job2(attest/verdict) 무접촉 = 판정 불변 (e) 빌드 없는 MISS에서 emit 실패(무증 아티팩트 차단) + Q4 무보간 스캔 + freeze 대비 업로드 payload 불변 |
| `tests/ci/test_admission_venue_split.nim` | landing-gated 정확 카운트 개정 20 → **21** (S5 판정 스텝 1건 추가 — 계약 핀의 문서화된 개정) |

### 2.2 authority·전이 정의 (§2.6 필수 4요소)

- **authority**: 착지 자격 판정 권한 = **merge_group venue의 정본 verdict**(`admission-check` required check 체인 — 기존 권한, 불변). S5가 바꾸는 것은 job1의 **공급 조달**뿐이다 — 검증된 공급(복원 바이너리)이든 신규 빌드이든, 그 판정 소비자(job2 attest 체인·mint·publisher)는 전부 자기 fail-closed 재검증(manifest build_sha==B + per-file sha256 + B-verify/probe)을 유지하며 판정 권한의 이동은 없다. J3 §3.1: "생략되는 것은 검증된 공급의 재사용이지 판정 재계약이 아니다 — 판정은 실행된다".
- **state transition**: landing venue의 B-HIT(검증 OK) 사이클 → 컴파일 3스텝 미발화, 판정 스텝 `[s5]`가 `SUPPLY REUSE` 라인을 로그로 남기고 manifest emit이 복원 바이너리를 결속 → 업로드 2종이 복원 payload를 그대로 운반(publisher base-seed의 아티팩트 존재 게이트 불변). MISS·검증 FAIL(probe/verify 폐기) 사이클 → `S5 COLD BUILD` 라인 + 기존 콜드 빌드와 바이트 동일. PR(preflight) venue → job1 중요 스텝 전체가 기존대로 landing 게드(변경 없음).
- **failure semantics**: fail-closed 유지·강화 — skip 판정의 입력은 "전 멤버 존재 ∧ 실행비트"라는 **관측된 디스크 상태**뿐(액션이 b-verify/probe FAIL 시 폐기했으므로 잔존 = 검증 OK의 필요조건); 임의 멤버 결손·비트 소실·fingerprint 부재 = 콜드 폴백(절대 skip 아님); emit은 skip 경로에서도 `test -x` + digest로 결속하므로 무증 공급이 아티팩트에 실릴 수 없다; 조용한 skip 금지(§0.9) — 두 판정 라인이 모든 분기에서 로그로 발화.
- **proof**: 본 기록 §2.4 게이트 출력 + `tests/ci/test_s5_build_skip.nim`(19 [OK]) + `tests/ci/test_admission_venue_split.nim`(카운트 개정 후 통과) + 운영 실측(acceptance 문서 — 착지·핀 회전 후 MG HIT/MISS 레인 벽시계·판정 발화·`landing_observe.sh` VERDICT로 별도 기록).

### 2.3 변경 전 검증 (본문 커밋 전 워킹트리 실측)

- `python3 -c "import yaml; yaml.safe_load(…)"` admission-check.yml → YAML OK
- 스텝 본문 원문 실행 시뮬레이션(테스트 내장): HIT/MISS/부분 결손 3종/폐기 잔존/emit fail-closed — 모두 계약대로
- 컴파일 경로 3스텝의 게드 접두사 불변(`scope_sl08 && venue == 'landing'` — S5 컨정크트는 접미 추가만)
- Q4 스캔: 신규·수정 run 본문(주석 포함)에 보간 토큰 0건 — emit의 build_sha 이벤트 보간 1건은 freeze 대비 원문 계약

### 2.4 기계 게이트 실행 (본문 PR에서 — 실측)

| 게이트 | 결과 |
|---|---|
| `make check-workflow-shell-syntax` | **PASS** — run blocks checked=125 failures=0 |
| `make check-repository-surface` | **PASS** (exit 0) |
| `make check-merge-admission-cert-mirror` | **PASS** — policy SSOT certRequired == `CertRequired*` == true |
| `bin/tcb_judgments selftest` | **PASS** — 12 passed, 0 failed |
| `make test-unit` | 신규 `test_s5_build_skip.nim` 포함 — **exit 0, 143 [OK], 0 FAILED, 25 suites** |
| `bin/epoch_transaction_gate --diff origin/main HEAD` | **PASS (exit 0)** — catalog↔manifest↔engine 3-way 등식(양방향) + pin consistency(base leg @base + new-state 3-way @HEAD). admission-check.yml blob 변경 + TWS/pin 회전이 동일 diff(G2a 의무 쌍)로 귀속 |
| `tools/ci/verify_trusted_writer_set.sh` | **PASS (exit 0)** — admission-check.yml@`62294da2…` == trustedAdmissionWorkflowSha, contents:write holders == certificate-mint.yml@`62294da2…` 단일 등식 |

## 3. Tombstone (AGENTS.md §2.5 단계 3)

1. 본 Tombstone은 **게이트 우회(break-glass)가 아니다** — N/A(폐기 대상 없음). 모든 게이트·검증 의무는 무변경으로 유지되며, 생략되는 것은 **검증된 공급의 재컴파일**뿐이다(J3 §3.1 — 판정은 항상 실행).
2. 본 Tombstone은 **면제(waiver)가 아니다** — N/A. `config/decision_binding.waiver.*` 등록 없음(본 변경 관련 면제 0건).
3. 본 Tombstone은 **required-check 제거가 아니다** — N/A. `admission-check` required check는 양 venue 모두에서 발화하며, MG landing 체인(attest·mint·verdict)은 바이트 동일하게 발화한다. skip된 컴파일 스텝은 플랫폼상 success로 계수되므로 명시적 판정 라인(`SUPPLY REUSE`/`S5 COLD BUILD`)이 로그로 의도를 증명한다 — 조용한 skip 아님(§0.9).
4. 본 Tombstone은 **검증 면제를 의미하지 않는다** — N/A. 컴파일은 판정이 아니라 공급 조달이며, 공급은 exact-key 복원 + 신뢰 입력 재유도 검증 + 4종 semantic provenance probe를 통과한 것으로 대체된다(action.yml b-verify 계약 — correctness = exact key → verify → use, FAIL → discard → cold). 검증된 공급의 재사용은 J3 §3.1이 정당화한 계약이다.
5. Tombstone은 역사적 폐기 기록이며 실행·검증 권한을 갖지 않는다(AGENTS.md §2.5 Mandatory Invariants) — 본 원칙 준용.

## 4. 연결 (결정 바인딩 · 잔여)

- 결정 바인딩: `docs/spec/ci_optimization_tcb_judgments.md` §3.1 — "HIT = 검증된 계산(프로그램) 공급 재사용 — 판정은 항상 재계산된다". census §2-§3(B-HIT 레인 4종 nim 재컴파일 ~86s)가 본 슬라이스의 대상 중복 계산. ADR-0032 landing venue가 실행 장소.
- 잔여 불변: A2 pin pair(원자성 — G2a 동일 diff 회전), 아티팩트 identity conventions(freeze `ci-frozen-2026-10-09-venue-split` 대비 이름·경로 불변 실측), publisher base-seed 게이트(`admission-check-base-artifacts` 존재 — skip 경로에서도 emit+업로드가 유지), 판정 스텝 무스킵(job2 전체).
- 핀 활성화: 본 PR 착지 후 조직 저장소 `Archright/.github`의 dependabot 트리거 PR → Dependabot 범프 3건(admission-check·certificate-mint·runner-pool-acceptance) 머지로 callee 핀이 S5 포함 tip으로 회전한다(선례: org #88→#89–91, #93→#94–96, #97→#98–100). 실측 acceptance는 `docs/evidence/s5_build_skip_acceptance_2026-10-09.md`.
