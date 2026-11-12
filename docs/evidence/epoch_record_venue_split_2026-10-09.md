# CI Epoch Record — admission venue split (PR 즉시 preflight / MG 착지 자격 정본): Freeze / Record / Tombstone

> **성격**: AGENTS.md §2.5(CI Epoch Cutover Protocol) 단계 1–3 — **FREEZE / RECORD / TOMBSTONE** 기록 문서. 변경 = admission 파이프라인에 실행 장소(venue) 분할 도입: `pull_request` = 신속 정적 preflight, `merge_group|workflow_call` = 착지 자격 정본 판정(기존 전 체인 무변경). 설계·근거 = **ADR-0032**.
> **작성일**: 2026-10-09.
> **작업 브랜치**: `feat/admission-venue-split`.
> **결정 바인딩**: `docs/adr/0032-admission-venue-split.md` (커밋 `19553a007`).
> **기록 관례**: `docs/evidence/epoch_record_memo_reanchor_2026-10-08.md`(Freeze/Record/Tombstone 템플릿) 준용.
> **변경 범위 판정**: admission 체인의 **venue 게드 추가** — 판정 규칙·아티팩트 표면·required check·TWS writer 등식 불변. `admission-check.yml` blob 변경이 수반되므로 3파일 pin 유닛(`trustedAdmissionWorkflowSha`·`productionExecutionPin`)이 **동일 커밋**에서 원자 회전된다(ADR-0022 §5).

---

## §0. 표면(surface) 판정

- 편집 대상 실측: `.github/workflows/admission-check.yml`·`.github/workflows/certificate-mint.yml` → **CONTROLLED**, `config/trusted_writer_set.json`·`config/policy/epoch_manifest.json` → 정책 경로, `src/cli/merge_cli.nim` → 코어. `make check-repository-surface` = **exit 0**(§2.4).
- 신규 `docs/evidence/epoch_record_venue_split_2026-10-09.md` = PRODUCT ADD — 동일 게이트에서 판정.

## 1. Freeze (AGENTS.md §2.5 단계 1)

| 항목 | 값 |
|---|---|
| freeze tag | **`ci-frozen-2026-10-09-venue-split`** (annotated) |
| 태그 타입 | annotated — `git cat-file -t ci-frozen-2026-10-09-venue-split` = `tag` ✓ |
| freeze 대상 | origin/main == 작업 기준 HEAD == **`ee6efd9c5fb346e786d6807ebf0d648e286b574b`** |
| 실측 검증 | `git rev-parse ci-frozen-2026-10-09-venue-split^{commit}` == `ee6efd9c5` — 일치 ✓ |
| push | **아니오 — 로컬 전용** (기존 `ci-frozen-*` 시리즈 동일 관례) |

## 2. Record (AGENTS.md §2.5 단계 2)

### 2.1 변경 요약 (본문 7파일 + 본 기록)

| 파일 | 변경 |
|---|---|
| `.github/workflows/admission-check.yml` | (a) 4 job(build-base-artifacts·admission-check 등) **최상단 `[venue]` 스텝** — `github.event_name` 3-way case: `pull_request`→preflight, `merge_group\|workflow_call`→landing, 기타 fail-closed exit 1 (b) 무거운 스텝 20개에 `steps.venue.outputs.venue == 'landing'` 컨정크트 추가 — MG 게드 의미 불변 (c) attests/verdict legs에 **PR preflight 스텝 2개**(TWS pin pairing + policy SSOT / policy SSOT + stage dispatch 구조) — `venue == 'preflight'` 게드, fail-closed 실검사 (d) identity 재유도(sl01)는 의도적 무게이트 유지(preflight identity 내용) |
| `.github/workflows/certificate-mint.yml` | 동일 venue 계약: prepare·publish job 최상단 `[venue]` 스텝, 무거운 스텝 15개 landing 컨정크트, prepare/publish legs PR preflight 스텝 2개(policy SSOT + mint 구조 / single-writer posture + stage 구조), (P0) activation guard는 **의도적 무게이트** 유지 |
| `src/cli/merge_cli.nim` | `effectiveCertRequired(preflight)` 순수함수(`CertRequired and not preflight`), `ax merge --preflight` 명시 opt-in, `--preflight`+`--apply` 조합 거부(exit 1), `--json` 기계 라인에 `"preflight"` 필드, 비정원 판정임을 명시하는 logInfo |
| `config/trusted_writer_set.json` | `trustedAdmissionWorkflowSha`: `ba827508f…` → **`9d8382376ba4a53d45c5b0cb1ae389bb06e1bed5`** (신규 admission-check.yml blob — A2 원자 쌍) |
| `config/policy/epoch_manifest.json` | `productionExecutionPin`: `ba827508f…` → **`9d8382376…`** (TWS와 동일 커밋 동일값) |
| `tests/ci/test_admission_venue_split.nim` | 신규 — 24 assertion: venue 스텝 구조·실행 시뮬레이션(3 event + fail-closed)·landing 컨정크트 하한선/정확 카운트·preflight 4 legs 실검사·3-way pin 일치·아티팩트 표면 불변(freeze 대비) |
| `tests/cli/test_merge_cli.nim` | 확장 — effectiveCertRequired(true/false), `--json` preflight 마커, `--preflight --apply` 거부 |
| `Makefile` | `test-unit`에 `tests/ci/test_admission_venue_split.nim` 등록 |
| `docs/evidence/epoch_record_venue_split_2026-10-09.md` | 본 기록 |

### 2.2 authority·전이 정의 (§2.6 필수 4요소)

- **authority**: 착지 자격(landing-eligibility) 판정 권한 = **merge_group venue의 정본 verdict**(`admission-check` required check 체인 — 기존 권한, 불변). PR venue는 **새 권한이 아니라** 명시적 `--preflight` opt-in으로만 도달하는 **비정원 preflight 신호**(ADR-0032 (f))다 — "preflight success ≠ landing evidence"가 모든 PASS 라인에 명시된다.
- **state transition**: `pull_request` 이벤트 → 무거운 스텝(landing 게드 20+15개) 미발화, 경량 identity 재유도 + preflight 대조 스텝만 발화, job 성공 = 구조 preflight 합격. `merge_group|workflow_call` → 기존 전 체인 발화(게드 의미 불변). 그 외 이벤트 → venue 미결 = exit 1(무 venue, 무 run).
- **failure semantics**: fail-closed 유지·강화 — venue 판정 불가 = exit 1; preflight 대조 실패(TWS pin pairing 불일치, policy SSOT drift, stage 구조 drift) = PR check red; landing 체인 실패 의미 불변; `--preflight --apply` = 즉시 거부(preflight는 actuation 불가).
- **proof**: 본 기록 §2.4 게이트 출력 + `tests/ci/test_admission_venue_split.nim`(24 [OK]) + `tests/cli/test_merge_cli.nim` ADR-0032 스위트(4 [OK]) + blob 3-way 일치 실측(git hash-object == TWS == manifest pin).

### 2.3 변경 전 검증 (본문 커밋 전 워킹트리 실측)

- `python3 -c "import yaml; yaml.safe_load(…)"` 양측 워크플로 → YAML OK
- `nim check src/cli/merge_cli.nim` → SuccessX
- venue run 본문을 **원문 그대로 실행**하는 시뮬레이션(테스트 내장): pull_request→preflight / merge_group·workflow_call→landing / push·workflow_dispatch→exit 1 — 모두 계약대로
- `verify_trusted_writer_set.sh` — 미커밋 상태에서는 HEAD blob 대조상 VIOLATION(원자성 계약의 정상 동작) → 동일 커밋 착지 후 재실행 요건

### 2.4 기계 게이트 실행 (본문 PR에서 — 실측)

| 게이트 | 결과 |
|---|---|
| `make check-workflow-shell-syntax` | **PASS** — run blocks checked=123 failures=0 |
| `make check-repository-surface` | **PASS** (exit 0) |
| `make check-merge-admission-cert-mirror` | **PASS** — policy SSOT certRequired == `CertRequired*` == true |
| `bin/tcb_judgments selftest` | **PASS** — 12 passed, 0 failed |
| `make test-unit` | 신규 `test_admission_venue_split.nim` 포함 — **exit 0, 125 [OK], 0 FAILED** |
| `bin/epoch_transaction_gate --diff` | **PASS (exit 0)** — catalog↔manifest↔engine 3-way 등식 + pin 3-way 일치(base leg + HEAD). 최초 FAIL의 SL-18 3건은 **게이트 바이너리가 SL-18 이전 카탈로그를 임베딩한 stale 인공물**(bin 10/06 vs slice_catalog.nim 10/09)로, 재빌드 후 소멸 — 저장소 드리프트 아님(초기 기정사실 정정). G2b 1건은 귀속 정정으로 해소(아래 §4) |
| `verify_trusted_writer_set.sh` | **PASS** — HEAD blob `9d8382376…` == trustedAdmissionWorkflowSha, contents:write holder == certificate-mint.yml@`9d8382376…` 단일 등식 |

## 3. Tombstone (AGENTS.md §2.5 단계 3)

1. 본 Tombstone은 **게이트 우회(break-glass)가 아니다** — N/A(폐기 대상 없음). landing 체인의 모든 게이트·검증 의무는 무변경으로 유지되며, PR venue에는 fail-closed 실검사가 **추가**된다.
2. 본 Tombstone은 **면제(waiver)가 아니다** — N/A. `config/decision_binding.waiver.*` 등록 없음(본 변경 관련 면제 0건).
3. 본 Tombstone은 **required-check 제거가 아니다** — N/A. `admission-check` required check는 양 venue 모두에서 발화하며, merge_group invocation이 여전히 유일한 착지 자격 판정이다. PR venue의 job 성공은 구조 preflight 합격일 뿐 착지 증거가 아니다((f) 표시 유지).
4. 본 Tombstone은 **검증 면제를 의미하지 않는다** — N/A. PR에서 건너뛰어지는 것은 착지 자격 판정(merge_group 전용 authority)뿐이며, 그 판정의 실행 장소가 merge_group으로 명시 고정된 것이다 — 검증 제거가 아니라 venue 재배치다.
5. Tombstone은 역사적 폐기 기록이며 실행·검증 권한을 갖지 않는다(AGENTS.md §2.5 Mandatory Invariants) — 본 원칙 준용.

## 4. 연결 (결정 바인딩 · 잔여)

- 결정 바인딩: `docs/adr/0032-admission-venue-split.md` — venue 3-way 분기, landing 컨정크트, preflight 4 legs, `--preflight` opt-in의 비정원 선언, A2 원자 핀 회전.
- 잔여 불변: A2 pin pair(원자성), 단일 writer 등식(certificate-mint.yml), stage 배출(attest/verdict 배타성 — `test_admission_check_stages.nim` 계속 통과), 아티팩트 identity conventions(freeze 대비 불변 실측).
- G2b 귀속 정정(본 epoch에서 수행, `tools/ci/epoch_transaction_gate.nim`): 핀 엔진(admission-check.yml)이 동일 diff에 있을 때 TWS/pin 변경은 **G2a 의무 쌍**으로 귀속 — G2b path 2의 "epoch 정의 불변" 판정에서 제외. authority: epoch transaction 기계 판정(게이트 자체, 기존). state transition: 판정 입력 분류만 변경(위반 경로·fail-closed 기본 불변 — TWS 단독·pin 단독·admission-check 무쌍·catalog/슬라이스 필드 접촉은 계속 FAIL). failure semantics: fail-closed 불변. proof: 본 기록 §2.4 게이트 PASS 실측 + 수정 전 FAIL/수정 후 PASS 대비. 배경: {핀 회전 + 비핀 엔진 변경}의 한 PR 결합이 규칙 문언상 불가능(G2a가 pin 동반을 의무화 → G2b가 pin 접촉을 FAIL)하는 false-negative — 2026-09-29 분할 정정이 해소한 A/B/C 교착과 동일 형태.
