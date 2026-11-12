# CI Epoch Record Addendum — mg-reuse-eligibility 세대 전환 (2026-10-18)

> §2.5 CI Epoch Cutover — Freeze · Record · Cutover의 addendum. 정본 규칙:
> `AGENTS.md` §2.5 / `docs/agents/ci_epoch_cutover.md`. 형식 선행 기록:
> [ci_epoch_record_mg_evidence_gate_2026-10-17.md](ci_epoch_record_mg_evidence_gate_2026-10-17.md).
> 권위 재결: [mg_reuse_policy_redecision_2026-10-18.md](mg_reuse_policy_redecision_2026-10-18.md)
> (PR #918, merged 2026-10-18T07:12:47Z, mergeCommit `0ec9026cf`) — 본 전환은 그
> 재결의 구현 세대다.
> **전환 물건(동일 PR, 두 커밋 — #917 선례)**: (1) callee·테스트·yml 커밋 —
> `src/verification/judgment_cas.nim` (벨트→착지 장소 마커 + consult fall-through +
> rootRecord 봉인/검증) + `tests/unit/test_judgment_cas.nim` (G11 재작성·G12 신설·
> G7 (g)(h)) + `tests/unit/test_judgment_set_derivation.nim` (T7) +
> `.github/workflows/admission-check.yml` (MG 게이트 — eligible REUSED만 rootRecord
> 마커로 수용) + `src/cli/merge_cli.nim` (RotationAllowlistExtra 2경로 동반 등록);
> (2) 핀 커밋 — `config/trusted_writer_set.json` (trustedCheckerTreeClosure 재앵커 +
> trustedAdmissionWorkflowSha 회전) + `config/policy/epoch_manifest.json`
> (productionExecutionPin 회전) + 본 문서.

## 1. Freeze

| 항목 | 값 |
|---|---|
| freeze tag | `ci-freeze-mg-reuse-eligibility-20261018` (annotated) — **변경 이전 세대**(REUSED-on-MG 차단 세대; admission-check.yml blob `1c9848a74b…`, judgment_cas.nim blob `85771a78a5…`)를 가리킨다 |
| tag → commit | `0ec9026cf` (main — PR #918 병합 지점; 롤백 기준선) |

## 2. Record — 세대 상태 전이

### 2.1 구세대 (1c9848a74b…, ~2026-10-18)

- merge_group 착지 venue에서 Judgment CAS 원장 consult가 **차단**됐다 — 레인 plan env
  `AXIOM_JUDGMENT_CAS_FORCE_EXECUTED=1`(callee 상속 실측) + Nim 벨트
  (`judgmentForceExecutionArmed`)가 consult 전 `jExecuted`로 단락. 착지는 전부
  EXECUTED — 동일 클로저의 유효 사전 판정도 착지 증거로 불허.
- 착지 basis 증명: 전 decision 파일 `"basis":"EXECUTED"` 강제 (yml :1718-1730).

### 2.2 신세대 (eligible-REUSED 세대)

- **착지 재사용 재허용(조건부)**: 벨트는 `judgmentLandingVenueMarker`로 용도 변경 —
  차단이 아니라 decision 파일의 `landingVenue` 마커. plan은 **모든 venue에서** 원장을
  consult하고, 5조건 전수 재검증 사슬(키 결속·payload 계약·epoch)을 통과한 레코드만
  `jReused`로 도달한다(§5 (a)(b)(c)는 구조적으로 이 사슬의 통과다).
- **rootRecord provenance 마커**: jReused plan은 재인출 레코드의
  `evidenceKey·payloadSha256·executionEpoch` 3필드를 decision 파일에 봉인한다.
  armed-attest REUSED leg는 마커 **shape를 ledger IO 이전**에, **binding을 재인출
  레코드와 대조**해 검증 — 부재·빈 값·비-hex·불일치 전부 fail-closed(run 실패).
- **yml MG 게이트**: `basis=EXECUTED` **또는** `basis=REUSED ∧ rootRecord 마커 유효`
  (jq 64-hex×2 + non-empty epoch)만 수용; 그 외 기존 fail-closed exit 1 유지.
  SSOT 집합 동등성 루프·mint P7c·lane 분기 무변경. env :2696 유지(의미 = 마커).
- **활성화 순간**: 본 PR의 merge_group 런에서 (i) referenced_workflows의
  admission-check sha == 본 세대 blob **그리고** (ii) 집계 `admission-check` SUCCESS.

### 2.3 회전 (④ 재앵커 — derive_checker_closure 유도값, 추측 금지)

`bin/derive_checker_closure --ref HEAD~1 vs --ref HEAD` → 정확히 2멤버 변경,
멤버십 불변(876 엔트리). 핀 재앵커 후 `pin@H == derived(H)` 기계 검증:
멤버십 876==876, 라인 집합 완전 일치.

| 멤버 | 구핀 blob | 신핀 blob (유도값) |
|---|---|---|
| `src/verification/judgment_cas.nim` | `85771a78a53a96ad00073dfc493d4b6d1fd4a9b4` | `0c90e0a7a5823287e6486f90d7ec986b6c6615d4` |
| `src/cli/merge_cli.nim` | `f1116c1772267f59c651d1d49cc416950b8804c2` | `305e2eac968c5db85719d8530cb96b7d6cec46bd` (RotationAllowlistExtra 2경로 확장에 따른 재앵커) |

**핀 회전(A2 원자 쌍 — "두 값 외 변경 없음")**: `trustedAdmissionWorkflowSha` +
`productionExecutionPin` → 본 세대 admission-check.yml blob `ab4460fa36dd7a93756082d9dc0605d3822aefb3`.
epoch_transaction_gate의 쌍 규약: yml 변경 + TWS 값 변경 + manifest 핀 변경이 하나의
그룹(커밋 2)으로 착지 — trustedCheckerTreeClosure 재앵커는 핀 값 변경이 아니므로
layer 1 loud NOTE 대상(동일 커밋 병행).

### 2.4 검증 상태 (기계 관측 — 착지 전)

| 검증 | 결과 |
|---|---|
| `make test-fast-one T=tests/unit/test_judgment_cas.nim` (G1–G12 전수) | **PASS — 201 assertions, 0 FAIL, 0 SKIP** (G11 재작성·G12 신설 포함; 2026-10-18 08:26:18Z 종료) |
| `make test-fast-one T=tests/unit/test_judgment_set_derivation.nim` (T1–T7) | PASS — T7 dual-class 포함 |
| `bin/tcb_judgments selftest` | PASS — 12/12 (모든 판정의 FAIL 경로 생존) |
| J1 parity | PASS — 저장 payload vs 재채택 payload **바이트 동일** (sha256 `7fe2f817ea35d0479ec54e0fe231d39259aa091a8d5724fcb3f0d02bf974405a` 양측 동일); 음성 대조(판정 변조) → FAIL exit 2 |
| J1 exactly-once 제어 | 동일 바이트 재-append → `alreadyPresent` no-op |
| J2 canonical-identity-set | PASS (동일 파일) / FAIL exit 2 (변조 control) |
| J3 cache-manifest | PASS — `.github/actions/setup-axiom-toolchain/action.yml` 대상(신뢰 입력 유도 기대값 + semantic provenance probe). admission-check.yml은 J3의 대상이 아님(측정 대상 착오 — 본 기록에 정직 등재) |
| `make check-workflow-shell-syntax` | PASS — 173 run 블록, failures=0 |
| `bin/ax` 컴파일 | PASS (수정 judgment_cas.nim 포함) |
| `bin/debt_engine --validate` | PASS — 1489 checks (merge_cli.nim canonical hash `--regen-arch` 갱신 후) |
| `pin@H == derived(H)` | PASS — 876==876, 라인 집합 완전 일치 (§2.3) |
| `make push-admissibility` | (푸시 시 관측) |

### 2.5 J1 증거 (재결 §7 요구 — same-key reuse는 byte-identical canonical projection)

- 절차: canonical 투영을 원장에 mint-once append → REUSED consult로 재인출 →
  양측 sha256 대조 + `tcb_judgments --judgment parity` 기계 판정.
- 관측: stored `7fe2f817…405a` == readopted `7fe2f817…405a`; parity PASS;
  변조 candidate → parity FAIL (exit 2) — 판정기가 생존한다는 음성 대조 포함.
- 테스트면 동등 단언: G12(1) `judgmentRootRecordMarkerMismatch(decision.marker,
  rebuilt record, payload) == ""` + G10(b) 동일 클로저 재flush 바이트 동일.

## 3. Tombstone

**"REUSED-on-MG 차단"의 종료 선언(재결 이행).** 구세대의 무차별 실행 강제 포즈는
본 전환으로 끝난다. 이것은 **우회·면제·required-check 제거가 아니다**: required
check `admission-check`(ruleset 20303214)는 불변이며, 신세대는 착지 증거에
**rootRecord 귀속 가시성**을 추가한다(강화). 폐기되는 실행 경계는 없다 — 행동
포즈의 세대 교체만 기록된다. rollback: freeze 태그 `ci-freeze-mg-reuse-eligibility-20261018`
에서의 원자 revert(코드+yml+핀) — #895 선례의 절차를 따른다.

## 4. 측정 (재결 §4 — before-baseline 확정)

- **before-baseline (OLD gate 마지막 docs-only 착지 = 재결 PR 자신)**: PR #918 —
  preflight(D1) 243s (06:56:55→07:00:58) + queue-wait 18s + **MG wall 672s**
  (admission-gate run 39106118694, 07:01:16→07:12:28) + tail 19s = **D3 952s**
  (06:56:55→07:12:47). 항등식 243+18+672+19=952 ✓.
- **after 표본**: 본 세대 착지 후 docs-only PR ≥5건의 MG wall/D3 — §4 판정
  기준(중앙값 비교, 401s=등록 상한 증명이지 보증 아님)은 재결 문서 소관. 본 PR은
  실행-축 전진(코드 변경 → 키 전진 → EXECUTED)이므로 after 표본이 아니다.

## 5. Open items (§0.9)

1. **`tests/ci/test_admission_venue_split.nim` 선존재 red — 본 세대 밖(정직 기록)**:
   main(0ec9026cf) 기준 (i) `:314` nAdmission 핀 26 vs 실측 32 — 선행 착지들에서
   guard 수가 증가했으나 핀 개정 누락(b1659ef16 선례의 소급 정정 대상),
   (ii) `:315` 스텝명 핀 `'[check] GO-critical admission tests'` 0건 — 스텝 개명
   미반영. 본 세대 변경(스텝 추가/개명 없음)과 무관 — stash-검증으로 선존재 확인.
   follow-up 권고: 별도 슬라이스에서 소급 정정.
2. **after 표본 관측** — 재결 §4 절차(≥5 docs PRs)는 착지 후 별도 관측 workstream.
3. **§4.3 org ruleset 재핀** — 본 세대 yml 변경이 org controller 핀 대상인지
   착지 후 live 핀 확인으로 판정(§6).
