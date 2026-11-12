# nimtry Evaporate 클러스터 계획 — ③ 워크스트림 (2026-10-12)

> **종류**: 실행 계획 문서 (unit plan). `bin/nimtry src/` 앵커 17건의 증발(evaporate)을 위한 클러스터 분석 + ONE-UNIT 슬라이스 목록.
> **성격**: docs-only. 본 문서의 착지 자체는 src/ 무변경이며, 계획된 유닛들의 src/ 착지는 **현재 효과-측정 창이 닫힐 때까지 금지**된다 (§4).
> **증거 기준**: 모든 file:line·위반 ID·게이트 결과는 2026-10-12 worktree(origin/main `6ed4a6911`)에서 실측했다. 측정·판정 데이터는 이 문서에 새로 만들지 않고 기존 SSOT을 인용한다.

---

## 0. 권한 선언

- 본 문서는 **유닛 계획**일 뿐이다. 각 유닛의 실행은 별도 권한 사이클이며, 실행 시점에 §3.0 공통 프로토콜 전체를 재이행해야 한다.
- `AGENTS.md §-1` 불변 파일(`src/gate/runners/import_encapsulation_gate.nim`, `config.nims` importEncapsulation 블록)은 **모든 유닛에서 비대상**으로 사전 검증됐다 (유닛 표 §3.1 각 행). 실행 중이라도 이 파일들 편집이 필요해지는 순간 그 유닛은 **OUT-OF-AUTHORITY — 중단**한다.
- 앵커 17건의 재앵커링(--update-baseline)은 유닛의 목적이 아니다. 유닛은 자기 위반을 **해소**한다 (§6 성공 기준).

---

## 1. 증거 기반 (전부 실측, 2026-10-12)

### 1.1 앵커 17건

출처: PR #765 (`e8cde1652`, merge 2026-10-12, "post-freeze 신규 위반 17건 부채 스냅샷 갱신 — BUDGET#004"). 구베이스라인(freeze `2026-10-10T21:51:26+09:00`, 4145건)과 신베이스라인(4138건)의 ID diff로 17건을 기계적으로 확정했다:

| # | 위반 ID (접두) | 규칙 | 위치 | 내용 |
|---|---|---|---|---|
| 1 | `258da65f803a` | soc-surface-area | `src/cli/axiom_engine.nim` | imports 100 (layer cli max 30) |
| 2 | `36b7f6cd447d` | soc-surface-area | `src/cli/axiom_engine.nim` | exports 29 (max 20) |
| 3 | `d6261f15a1fe` | soc-surface-area | `axiom_engine.nim:302` | `runBatchVerification` 286 SLOC (max 50) |
| 4 | `c16574f42b5d` | soc-surface-area | `axiom_engine.nim:1348` | `buildBugVerdictDisplayJson` 101 SLOC |
| 5 | `5edd35ec87a1` | soc-surface-area | `axiom_engine.nim:2346` | `runVerificationWaves` 74 SLOC |
| 6 | `9a25fa23ae9c` | soc-surface-area | `axiom_engine.nim:2936` | `runProofPipeline` 52 SLOC |
| 7 | `0afb77c13ba0` | effect-transitive-io | `axiom_engine.nim:720` | `renderPersist` — I/O 도달, `{.raises: [].}`/주석 삼중조 부재 |
| 8 | `1d11e58fae6b` | soc-surface-area | `src/cli/verdict_display.nim:221` | `displayBugVerdict` 94 SLOC |
| 9 | `085c7786c816` | soc-surface-area | `src/cli/wf_render.nim:100` | `renderAxReportLines` 159 SLOC |
| 10 | `1a4639edae19` | soc-surface-area | `src/core/trusted/bug_attribution_grounds.nim:176` | `validateGroundsFile` 181 SLOC |
| 11 | `5dbec1b42140` | soc-surface-area | `src/cli/merge_cli.nim` | exports 58 (max 20) |
| 12 | `0c5bf0464591` | soc-surface-area | `merge_cli.nim:875` | `buildDryRunJson` 65 SLOC |
| 13 | `e4ca3c0702ac` | soc-surface-area | `merge_cli.nim:986` | `MergeAdmissible` 183 SLOC |
| 14 | `3626da2cf328` | soc-surface-area | `merge_cli.nim:1680` | `collectAdmissionFacts` 79 SLOC |
| 15 | `f1ec63db9241` | soc-surface-area | `merge_cli.nim:2594` | `runMergeCli` 78 SLOC |
| 16 | `e5fe2413a6e2` | solid-ocp | `merge_cli.nim` | case 분기 16개, 레지스트리 호출 0 |
| 17 | `34a854ceb845` | solid-ocp | `src/gate/runners/layer_enforcement_gate.nim` | case 분기 13개, 레지스트리 호출 0 |

구성: `[soc-surface-area]` ×14 · `[solid-ocp]` ×2 · `[effect-transitive-io]` ×1 — 작업 지시서의 규칙 분포와 일치.

### 1.2 브랜치 게이트 실측 (본 계획 착지 전, 동일 트리)

- `bin/nimtry src/` → **PASS — 4138 violations (debt anchored)**, exit 0.
- `bin/debt_engine --validate` → **All debt validation checks passed**, exit 0.
- `make check-imports` → PASSED (pre-commit 게이트 경로).

---

## 2. 클러스터링 — 17건 → 5개 코드 검증 클러스터

### 2.1 클러스터 표

| 클러스터 | 멤버 (안정 identifier + 위반 ID 접두) | 근본 원인 (코드 검증) | 추정 blast radius |
|---|---|---|---|
| **A. bug-verdict 표시·저장 경로** (axiom_engine → verdict_display → bug_attribution_grounds 선형 체인) | `axiom_engine.renderPersist` (#7) · `axiom_engine.buildBugVerdictDisplayJson` (#4) · `verdict_display.displayBugVerdict` (#8) · `bug_attribution_grounds.validateGroundsFile` (#10) | 파이프라인 post-loop 저장 한 곳에 렌더+표시+영속이 융합: `renderPersist`(720)가 `renderLegacyReport` → `buildBugVerdictDisplayJson` → `persistAxProofState`를 순서대로 호출(720–737)하고, 빌더 내부에서 `assessGrounds`(verdict_display:133, 호출 axiom_engine:1398)→`validateGroundsFile`(bug_attribution_grounds:176, 호출 verdict_display:138)와 표시 투영 `displayBugVerdict`(호출 axiom_engine:1464)까지 수행 | 모듈 소비자가 각 1개로 폐쇄적: verdict_display ← axiom_engine만, bug_attribution_grounds ← verdict_display만. 테스트: `test_bug_attribution_grounds.nim`, `test_bug_attribution_display.nim`, `test_bug_verdict_projection.nim`. 상태파일(X1 canonical boundary) 스키마 불변이 핵심 구속 |
| **B. 검증 파이프라인 척추 + 모듈 표면** (axiom_engine) | `runBatchVerification` (#3) · `runVerificationWaves` (#5) · `runProofPipeline` (#6) · imports-100 (#1) · exports-29 (#2) | 검증 수직 슬라이스 전체가 cli 계층 단일 모듈에 누적: `runProofPipeline`(2936)→`prepareProofRun`(2780, 2944)+`runVerificationWaves`(2346, 2952)→`runOneWave`(2274)→`runBatchVerification`(302, 호출 2295). 100개 import는 overlay 합성 가족(949–2340)이 가진 verification/core 의존이 주성분 | src 소비자 2개: `action_interpreter_cli.nim:199`(runAxiomEngineCli), `vkd_sync_cli.nim:63`(runAxiomEngineCli). 테스트: `test_axiom_engine.nim`, `test_bug_verdict_projection.nim`. 파이프라인 출력(report/state-file) 전체가 하류 — 유닛 순서에서 최후반 배치 |
| **C. 병합 어드미션 표면** (merge_cli) | exports-58 (#11) · `buildDryRunJson` (#12) · `MergeAdmissible` (#13) · `collectAdmissionFacts` (#14) · `runMergeCli` (#15) · solid-ocp-16 (#16) | 어드미션 판정(순수 `func MergeAdmissible{.raises: [].}`, 986)+사실 수집(1680)+CLI I/O(2594)+dry-run JSON(875)이 한 모듈에 융합, case 기반 분기(681/738/744/1091/2923)로 레지스트리 없음 | src 소비자 2개·소비 심볼 폐쇄적으로 실측됨: `action_interpreter_cli.nim:182`는 `mergeCli` 1개, `landing_cli.nim:54`는 `appendGateHistory·getTimestamp·ghGet·loadLedgerCertFor·performMerge·resolveMergeShapeApi` 6개. 테스트: `test_merge_cli.nim`(거부 행렬), `test_merge_admission_candidate.nim`, `test_merge_cli_trailers.nim`, `test_attestation.nim`. **거부 판정 어휘(§6) 불변이 최상위 구속** |
| **D. 보고서 라인 조판** (wf_render) | `renderAxReportLines` (#9) | 라인 계열별 포맷 변형이 단일 함수에 누적(159 SLOC) | 소비자 3개: `wf_runners.nim:200`, `axiom_engine`, `ax_workflow_cli`. 테스트: `test_deterministic_report.nim`, `test_assurance_tier_node_report.nim`, `test_bug_attribution_display.nim`, `test_bug_verdict_projection.nim` + generated feature. 결정적 바이트 출력이 곧 계약 |
| **E. 게이트 케이스 디스패치** (layer_enforcement_gate) | solid-ocp-13 (#17) | verdict/kind 매핑이 case 분기(273/283/309/332)로 하드코드 — 레지스트리 없음 | 임포터 0개(standalone runner, `proc main` 347 + `when isMainModule` 405). `make check-layer-enforcement --strict` + `check-layer-negative`가 직접 회귀. 단, 이 파일은 **isAllowedImport의 페어 주입 소비자**(37, 174)라서 §5 리스크 1과 결합 — 순서 최후 배치 |

합계 4+5+6+1+1 = 17 ✓

### 2.2 감사 주장 클러스터(`obligation_ir` ×4 · `z3_pool` ×2 · `pipeline_effect` ×2) 대조 — **기각·재분류**

세 클러스터 모두 코드에서 **실재를 확인**했다:

- `obligation_ir` ×4: `ir_to_lean.nim:25`, `ir_to_smt.nim:29`, `private/canonical_chc_compiler.nim:25`, `private/ir_loop_to_horn.nim:65` — 전부 `import verification/obligation/obligation_ir`
- `z3_pool` ×2: `proof_vacuity_gate.nim:8`, `gate/gate_to_smt.nim:7` — 전부 `import verification/solver/z3_pool`
- `pipeline_effect` ×2: `pipeline_dispatch.nim:12`, `pipeline_types.nim:17` — 전부 `import verification/pipeline_effect`

그러나 이들은 **앵커 17건(soc-surface-area 계열)을 분할하지 않는다** — 이것들은 `[soc-layer-imports]`(core→verification 금지 계층 crossing) 가족이며, `src/gate/architecture_policy.lock`의 `core_to_verification_pairs` 페어 레지스트리가 처리하는 대상이다 (§5 리스크 1). 감사 문서가 두 위반 가족을 한 표로 섞은 것으로 보이므로 본 계획은 둘을 분리한다: 17건 = §2.1의 A–E, soc-layer-imports = §5.1의 상시 리스크.

### 2.3 soc-layer-imports 현재 상태 (실측)

- 구베이스라인(freeze)에는 soc-layer-imports **14건**이 있었고, 페어 레지스트리는 그중 **13건을 커버**한다 (작업 지시서 주장 확인). 미커버 1건 = `verification/batch_uap/loop_driver.nim:3` → `cli/selection_state` (verification→cli 방향 — 레지스트리가 커버하는 core→* 방향 밖). **이 1건은 현재 베이스라인에도 live**다 (현재 baseline에서 soc-layer-imports = 1건).
- 락의 페어는 총 23쌍 = ADR-014 composition root 5쌍(`v0.5.0` 만료) + **`2026-12-12` 만료 18쌍(14개 파일)**. 18쌍 중 4쌍(`verification_interface.nim`, DEBT#483 type-only facade)은 live 위반이 없는 방어 쌍이다.

---

## 3. 유닛 계획 — ONE-UNIT 슬라이스 16개

### 3.0 유닛 공통 프로토콜 (모든 유닛에 적용, 예외 없음)

1. **앵커-플립 금지 (기계 설계 규칙)**: nimtry v2는 fingerprint 래칫이다 (`nimtry_cli.nim:441-442` — "기존 위반 = 부채 앵커링, 신규 위반만 FAIL"). 위반 함수를 **다른 모듈로 이동만 하면** 기존 지문은 해소되고 동일 규칙의 **신규 위반이 새 위치에 생겨** 게이트가 FAIL한다. 따라서 (a) SLOC 위반 함수는 **같은 모듈 안에서 비공개 헬퍼 분할**(이동 아님)로만 해소하고, (b) 모듈 간 재배치(U15)는 **위반이 없는(clean) 함수만** 대상으로 하며, (c) 유닛 종료 시 `newViolations == 0`이 아니면 그 유닛은 설계 결함으로 간주해 중단·재설계한다.
2. **mechanical-move-only 증명**: diff는 "문장 집합·실행 순서 불변, 함수 경계·가시성만 신설/축소"임을 diff 리뷰로 확인한다(§5 리스크 3의 순서 민감점 목록 대조). 로직·조건식·호출 순서 변경 0.
3. **명시 회귀 스위트 (공통 바닥 — 매 유닛)**:
   - GO-critical 4종 (CI-wired, `admission-check.yml` DEBT#432 — 로컬에서 `make test-fast-one T=` 로 각각 실행): `tests/unit/proof_integrity_test.nim`, `tests/unit/test_s1a_lean_golden.nim`, `tests/unit/test_d2_golden.nim`, `tests/unit/test_d2_persist.nim`
   - `bin/nimtry src/` exit 0 (해당 유닛 앵커 resolved + 신규 0)
   - `bin/debt_engine --validate` exit 0 (= `make check-debt`)
4. **클러스터 전용 스위트 (추가)**: 유닛 표의 "스위트" 열.
5. **명시 실행 필요(CI 미배선) 스위트**: `tests/cli/test_merge_cli.nim`(거부 행렬)은 workflow 어디에도 없음(실측: `.github/workflows/` 미참조 — Makefile `test-unit`에만 포함), `tests/cli/test_merge_admission_candidate.nim`은 Makefile·workflow 양쪽 모두 미배선. **merge_cli 유닛(U04–U08)에서는 반드시 로컬 명시 실행**.
6. **운영 경로 확인**: 유닛 표의 "운영 경로" 열 — 변경 전/후 동일 입력 → 동일 exit code·동일 출력 스키마(또는 바이트 동일)를 고정 피스팅에 대해 대조 기록.
7. **§-1 사전 점검**: 유닛 표의 "§-1" 열이 OUT이면 즉시 중단. 16개 유닛 전부 사전 검증 결과 **IN**(비대상)이다.
8. **1유닛 = 1 PR = 1 사이클** (§4 창 닫힘 이후). 두 유닛을 한 PR에 묶는 것 금지 — blast radius 귀속과 CAS 키 회전 귀속이 무너진다.
9. **trustedCheckerTreeClosure 멤버 sha 원자적 동반 갱신**: 유닛의 변경이 `trustedCheckerTreeClosure` 멤버 파일에 닿는다면, **같은 PR 헤드 트리**에서 그 멤버의 blob sha를 `config/trusted_writer_set.json`에 갱신해야 한다(원자적 동반 — 핀 값 자체는 불변). 검증은 클로저 재도출(`bin/derive_checker_closure --ref HEAD`)로 집합 동등성을 확인하는 것 — 핀 집합 == 도출 집합(864==864, 차이 = 해당 멤버 1행). 누락 시 큐가 ROT_NEW_PIN(`newAnchorOk:false`)으로 fail-closed 거부한다(실측: PR #787 — runs 38286110903/38288401507, `bug_attribution_grounds.nim` 3547f4ec→6c9f7a6e 미동반; 선행 재앵커 커밋: `327a961b`, `32992b0d`). 회전 PR의 changed 경로는 회전 allowlist(클로저 pin@B keys ∪ `docs/adr/**` ∪ `config/trusted_writer_set.json` ∪ A2 동반 목록) 내로 한정된다 — 비허용 파일(예: 본 계획 문서)의 동반 수정은 **별도 docs-only PR**로 착지한다(실측: ROT_ALLOWLIST, run 38324839465 — 회전 PR은 allowlist 내 2경로만으로 MERGED `31fb3e50`).

### 3.1 순서 목록 (leaf-first: 소비자 최소 → 최대, 저위험 → 고위험)

| 순서 | 유닛 | 해소 앵커 | 기계적 diff 형태 (move-only) | 전용 스위트 | 운영 경로 확인 | §-1 |
|---|---|---|---|---|---|---|
| U01 | `bug_attribution_grounds.validateGroundsFile` 분할 | #10 (181) | 같은 모듈 비공개 `func` 추출(레코드 루프·스펙 대조 블록), `{.raises: [].}` 유지, 호출부(verdict_display:138) 시그니처 불변 | + `tests/unit/test_bug_attribution_grounds.nim`, `test_bug_attribution_display.nim` | `assessGrounds` 경로 — display JSON grounds 축 불변 (golden) | IN |
| U02 | `verdict_display.displayBugVerdict` 분할 | #8 (94) | 2축 투영을 축별 비공개 func로 추출 — glossary §2.4 우선순위·fail-closed 열등 선택 불변 | + `test_bug_attribution_display.nim` | display 블록 nil-존재 규칙 동일 (골든 비교) | IN |
| U03 | `wf_render.renderAxReportLines` 분할 | #9 (159) | 라인 계열별 렌더 func 추출, 출력 라인 시퀀스 불변 | + `test_deterministic_report.nim`, `test_assurance_tier_node_report.nim` | `wf_runners:200` 조립 라인 바이트 동일 | IN |
| U04 | `merge_cli.buildDryRunJson` 분할 | #12 (65) | JSON 섹션별 빌더 func 추출 — 키 집합·순서 불변 | + `test_merge_cli.nim`(거부 행렬, 명시), `test_merge_admission_candidate.nim`(명시), `test_merge_cli_trailers.nim` | `action_interpreter_cli:182` `mergeCli` dry-run 스모크 — JSON 스키마 동일 | IN |
| U05 | `merge_cli.collectAdmissionFacts` 분할 | #14 (79) | 팩트 계열별 수집 func 추출 — 수집 순서·None 의미 불변 (fail-closed: 미수집=거부) | U04와 동일 + `test_attestation.nim` | U04와 동일 | IN |
| U06 | `merge_cli.runMergeCli` 분할 | #15 (78) | 인자 해석과 어드미션 실행의 분리 추출 — `axiomEffect` 경계 유지 | U04와 동일 | `mergeCli`(2914)→`runMergeCli`(2952) 전체 스모크 — exit code 표 동일 | IN |
| U07 | `merge_cli.MergeAdmissible` pass 분할 | #13 (183) | Pass −1…Pass N을 pass별 비공개 func로 추출 — **pass 순서·거부 reason 문자열 불변**(§6), `func{.raises: [].}` 순수성 유지 | U04와 동일 | 거부 행렬 전 케이스 reason 코드 바이트 동일 | IN |
| U08 | `merge_cli` solid-ocp case→레지스트리 | #16 (16분기) | case 분기를 total 매핑 테이블+등록 핸들러로 전환 — 분기 서술 집합 동일, 등록 순서 = 기존 case 순서. **유일하게 '순수 이동'이 아닌 구조 전환** — §5 리스크 3 프로토콜 최대 강도 적용 | U04와 동일 (전 케이스 커버) | U06 스모크 + 거부 행렬 — 판정·reason 100% 동일 | IN |
| U09 | `axiom_engine.buildBugVerdictDisplayJson` 분할 | #4 (101) | overlay 프루브/행 매치/스코프 표 블록을 비공개 func 추출 — nil-블록 규칙 불변 | + `test_bug_verdict_projection.nim`, `test_bug_attribution_display.nim` | display JSON 골든 동일 | IN |
| U10 | `axiom_engine.runVerificationWaves` post-loop 추출 | #5 (74) | 루프 후 1회 실행 블록(문서 주석 명시)을 비공개 func 추출 — wave 루프 본체·max-64 가드 불변 | + `test_axiom_engine.nim` | 상태파일 스키마 동일 (persistAxProofState 출력 비교) | IN |
| U11 | `axiom_engine.runProofPipeline` 꼬리 분할 | #6 (52) | persist/ASI 꼬리 추출 — `renderPersist` 호출 순서(3007) 불변 | + `test_axiom_engine.nim` | U10과 동일 | IN |
| U12 | `axiom_engine.runBatchVerification` 분할 | #3 (286) | 286 SLOC을 단계별 비공개 func로 분할 — 요청 정렬·집계 순서 불변 | + `test_axiom_engine.nim` | runAxiomEngineCli 스모크 (`vkd_sync_cli:63` 포함) | IN |
| U13 | `axiom_engine.renderPersist` 효과 주석 완결 | #7 (effect-transitive-io) | **본체 무변경** — I/O 경계 주석 삼중조(`axiomEffect`/`tags`)를 모듈 관행(runProofPipeline 패턴)대로 완결. 실행 전 nimtry EFFECT-transitive-io 판정기 정의를 재확인하고 주석이 그 판정을 충족함을 로컬로 관측 | + `test_axiom_engine.nim`, `test_bug_verdict_projection.nim` | 상태파일 바이트 동일 (X1 boundary) | IN |
| U14 | `axiom_engine` exports 축소 | #2 (29→≤20) | 내부 전용 심볼에서 `*` 제거(가시성 축소만). src 소비자 필요 집합은 실측됨: `runAxiomEngineCli`, `report` — 실행 시 테스트 소비 심볼까지 대조 후 축소 목록 확정 | + `test_axiom_engine.nim`, `test_bug_verdict_projection.nim` (컴파일 자체가 회귀) | runAxiomEngineCli 스모크 | IN |
| U15 | `axiom_engine` import 축소 | #1 (100→≤30) | **clean 함수만** 응집 블록(overlay 합성 가족 중 위반 없는 함수)을 신규 cli 모듈로 재배치 + import 집합 이동. 신규 모듈: cli 계층 legal import, ≤30 imports, ≤20 exports, 이동 함수 전부 ≤50 SLOC. 앵커-플립 금지 규칙(§3.0-1)상 SLOC 위반 함수는 이동 대상에서 제외 | + `test_axiom_engine.nim` 외 이동 함수 커버 테스트 전부 | runAxiomEngineCli 전 경로 스모크 | IN |
| U16 | `layer_enforcement_gate` solid-ocp case→레지스트리 | #17 (13분기) | U08과 동일 형태. 단, 이 파일은 페어 레지스트리 주입 소비자(37, 174) — **판정 경로(isAllowedImport) 무변경**을 diff 리뷰로 별도 확인 | + `make check-layer-enforcement --strict`, `make check-layer-negative`(음성 피스팅이 여전히 FAIL — anti-theater liveness) | 전 트리 스캔 판정 동일 | IN |

순서 근거: A클러스터 소비 폐쇄(각 1 소비자)를 먼저 증발시켜 이후 유닛의 관측면을 줄이고, merge_cli는 거부 행렬이라는 기계적 오라클이 있는 순서로, axiom_engine 척추(B)는 하류 전체가 걸려 있어 최후반에, 레지스트리 전환(U08·U16)은 '순수 이동' 강도가 가장 약한 전환이므로 각 모듈의 마지막에 배치했다.

---

## 4. 순서 제약 — 측정 창과 착지 해제 조건

**현재 src/ 착지는 전면 금지다** (본 워크스트림 포함 — 그래서 본 문서는 docs-only로 착지한다). 병렬 워크스트림이 E3 측정 계약(`docs/evidence/e3_measurement_contract_2026-10-11.md`, 고정 병합 `ad43e67fa` 2026-10-11T02:52:14Z + 개정 A1)의 확증 데이터를 수집 중이기 때문이다.

**해제 조건 (정확한 형태)** — 다음 중 **먼저 도래하는 것**이 창을 닫는다:

1. **정상 종료**: 고정 n 도달 — B-arm n_B=12(감증 규칙 A1: 소요 사전관측 런 제외, fail-closed) + C-arm n_C=30 충족 → 세대-수준 블록 부트스트랩(§5.3) 분석 1회 실행 → **사전 등록된 판정이 `docs/evidence/`에 기록·병합된 시점**.
2. **창 닫힘 종료**: 계약 병합 후 30일 경과(≈ 2026-11-10) 시점에 유효 n 미달 → "underpowered, non-confirmatory" 명기 분석 1회를 같은 경로로 기록.

두 경우 모두 판정 기록의 병합 OID가 창 닫힘의 증거다. 창 닫힘 이후:

- 유닛은 **1사이클(1 PR)에 1개씩** U01→U16 순서로 착지한다.
- 각 PR은 §3.0 공통 프로토콜 전체(명시 스위트 + 운영 경로 대조 + nimtry/debt 게이트)를 통과해야 착지된다.
- 유닛 실패 시 다음 유닛으로 진행하지 않고 해당 유닛을 재설계한다 (순서 의존성: U15는 U12–U14 이후에만 의미가 있다).

---

## 5. 상시 리스크 (3건 — 유닛 실행 내내 유효)

### 5.1 락 만료 2026-12-12 — soc-layer-imports ×13 재출현

`core_to_verification_pairs`의 `2026-12-12` 만료 18쌍(14파일, §2.3)은 구베이스라인 soc-layer-imports 14건 중 13건을 커버한다. 만료 시 그 13건이 nimtry 게이트에 **재출현**해 FAIL이 된다. 소유권은 락 헤더가 명시한다: "Owner: human architect (review/termination) + RL-14.4 workstream (settlement)" — 본 워크스트림의 권한 밖이지만, **U-시리즈가 2026-12-12 이후로 걸리면 유닛당 "신규 위반 0" 기준과 정면충돌**한다. 따라서: (a) U-시리즈는 가능한 한 12-12 이전에 완주하거나, (b) 각 페어의 disposition(타입 이동 페어별 정산 — 락 자체가 "v0.5.0 = settled by type-move release" 형식을 정의)이 RL-14.4에서 먼저 진행되어야 한다. 이 리스크는 유닛 계획의 일정 압력으로 변환된다.

### 5.2 CAS closure 키 회전 — 모듈 이동의 2차 효과

실측된 키 대수(E3 §3.1): `b_identity = sha256(sorted closure)`, closure = `src/**`(`src/generated` 제외)+고정 목록. U08/U15 같은 **파일 신설·이동은 전체 closure 키를 회전**시킨다:

- CI 컴파일 캐시 MISS → 시딩 지연(30–45분, E3 §3.2 실측)과 결합해 **착지가 느려진다**.
- judgment-CAS 피험자(4 GO-critical 테스트)의 byte binding이 변하면 **REUSED→EXECUTED 전환**으로 커널 재실행이 강제된다 (admission-check.yml CAS 분기 실측).

둘 다 **J3 중립**이다 — 캐시는 가속일 뿐 판정이 아니며(admission-check.yml GO-critical 스텝 주석: "cache is acceleration, never evidence"), GO-critical 판정 결과는 변하지 않는다. 그러나 GO-critical 스텝 **소요**는 E3의 1차 추정량(Δ = μ_B − μ_C)이라 **측정 교란**이다. 이것이 §4 창 내 착지 금지의 2차 근거이며, 창 닫힘 후에도 1유닛/1사이클 규칙이 키 회전의 귀속을 1:1로 유지한다.

### 5.3 "mechanical-move-only" 수용 기준의 한계 — 부수효과 순서

표본 I/O 테스트의 통과는 **부수효과 순서 보존을 보장하지 않는다**. 실측으로 확인한 순서 민감점:

1. `persistAxProofState`는 post-loop에서 **1회**만 — X1 canonical boundary (DEBT#458 폐쇄, axiom_engine 737 주변 주석). U10–U13은 이 호출 횟수·시점을 절대 바꾸지 못한다.
2. `renderPersist` 내부 순서: render → display 블록 주입 → persist (720–737).
3. `MergeAdmissible` pass 순서: Pass −1(FACTS_MISSING) → Pass 0(base freshness) → … — 거부 reason 문자열이 pass 도달 순서의 함수다.
4. `runVerificationWaves` max-iteration 64 가드와 post-loop 1회 실행 보장 (2346 문서 주석).

프로토콜: 각 유닛 diff 리뷰에서 "이동된 문장의 정규화 시퀀스 불변"을 확인하고, golden이 존재하는 경로(`test_deterministic_report.nim`, `test_d2_golden.nim`)는 **바이트 동일**을 요구한다. U08·U16(레지스트리 전환)에는 이 프로토콜을 최대 강도로 적용한다 — 전환은 분기 서술 집합이 total·동일임이 표로 증명될 때만 수용한다.

---

## 6. 유닛별 성공 기준 (매 유닛, 전부 충족)

1. **판정 어휘 불변**: merge journal reason 문자열 `NO_CERT` / `CERT_INVALID` / `SUBJECT_MISMATCH` / `POLICY_MISMATCH` / `SCOPE_MISMATCH`(및 기존 전체 어휘 — 계약 위치 `merge_cli.nim:57-58` "Reason vocabulary = journal strings … (no new enum/gate/authority)")가 리터럴 그대로 유지된다. 신규 enum·게이트·authority 없음.
2. **GO-critical 결과 동일**: 4종 테스트(`proof_integrity_test` / `test_s1a_lean_golden` / `test_d2_golden` / `test_d2_persist`) 전부 PASS, 유닛은 judgment-CAS basis를 건드리지 않는다(REUSED skip을 유도하지 않는다).
3. **nimtry 증발 확인**: `bin/nimtry src/` exit 0, 해당 유닛의 앵커 지문이 resolved로 소비되고 **신규 위반 0**.
4. **부채 장부 — 문서화 도구 경로**: `bin/debt_engine --validate` exit 0 (문서화: `tools/debt_engine.nim` 헤더 `./tools/debt_engine --help` / `--validate`). nimtry 위반 예산 레코드(`bcNimtryViolation`)의 갱신도 debt_engine 계약 내에서만 수행한다. `make check-debt` green.
5. **운영 경로 동일**: 유닛 표의 확인 단계가 변경 전/후 대조 기록을 남긴다.

---

## 7. 이 계획의 한계

- 본 문서는 분석 시점(origin/main `6ed4a6911`, 2026-10-12)의 코드에 대한 계획이다. 창 닫힘까지 main이 성장하면 각 유닛의 file:line은 실행 시점에 재확인해야 한다 (위반 ID는 fingerprint라 안정적).
- U13(effect 주석 완결)은 nimtry 판정기의 정확한 요구를 실행 시점에 재확인하도록 명시했다 — 본 계획은 위반 메시지("lacks {.raises: [].}")와 모듈 관행의 불일치를 관측했을 뿐, 판정기 소스를 대체하지 않는다.
- soc-layer-imports 13건의 정산은 본 계획 밖이다 (§5.1 — RL-14.4 소관).
