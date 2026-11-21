# 회전 allowlist 사전등록 — obligation-count 회전 동반 5경로 (ADR-0025 Amendment A8)

> **Status**: 사전등록(prereg). 본 문서는 **아직 착지하지 않은** 회전 동반 집합 확장의 근거·범위·비확장 논증을 착지 전에 고정한다.
> **Created**: 2026-11-21
> **대상 PR**: #287 (`fix(batch-uap): keep obligation counts and rank the declared projection (DEBT#423/#487)`, head `a130d0b`)
> **실측 verdict**: merge_group run `44882710554` (2026-11-21T08:07Z), `reasonCode=ROT_ALLOWLIST`
> **개정 대상**: ADR-0025 Amendment A8 (`docs/adr/0025-gateway-landing-authority.md`)

## §1. 실측 사실 (착지 전 관측)

PR #287의 merge_group verdict에서 관측된 `rotationCheck`:

```json
{
  "closureChange": true,
  "changed": [
    "config/trusted_checker_closure.json",
    "data/architecture_debt.json",
    "data/debt_reduction_baseline.json",
    "data/nimtry_baseline.json",
    "src/generated/type_registry_metadata.json",
    "src/verification/batch_uap/ir_pipeline_runner.nim",
    "tests/unit/test_hotspot_ranker.nim",
    "tests/unit/test_ir_pipeline_theaterguard.nim",
    "tools/ci/proof_unit_consistency_gate.nim",
    "tools/hotspot_ranker.nim"
  ],
  "allowlistOk": false,
  "subjectDeltaZero": false,
  "oldAnchorOk": true,
  "newAnchorOk": true,
  "delegatedToPlatform": true
}
```

기존 허용 집합 안이었던 경로(4): `config/trusted_checker_closure.json`, `data/architecture_debt.json`, `data/nimtry_baseline.json`, `src/generated/type_registry_metadata.json`.
클로저 멤버(pin@B 키)로 허용된 경로(1): `src/verification/batch_uap/ir_pipeline_runner.nim`.
**허용 집합 밖이었던 경로(5)** — 본 개정이 수록하는 대상:

1. `tests/unit/test_ir_pipeline_theaterguard.nim`
2. `tests/unit/test_hotspot_ranker.nim`
3. `tools/ci/proof_unit_consistency_gate.nim`
4. `tools/hotspot_ranker.nim`
5. `data/debt_reduction_baseline.json`

## §2. 회전 대상과 제품 결함 (왜 이 PR이 회전인가)

회전은 `src/verification/batch_uap/ir_pipeline_runner.nim`(클로저 멤버)의 변경 때문에 발생한다. 이 변경은 DEBT#423의 실제 결함을 고친다:

- canonical success 경로가 `:740`에서 `obligationCount: generatedObligationCount`를 기록하지만, 이 변수의 대입은 `:761`에서 일어난다. 따라서 canonical success는 **항상 0**을 보고한다.
- DEBT#304가 인용한 TheaterGuard(`:1316`)는 이 early-return 경로를 커버하지 못하므로, #304의 stale-close 서술은 canonical success 경로에 대해 거짓이다.
- PR #287은 generation boundary에서 count를 고정하고(`runIrPipelineCore(..., generatedCount: var int)`), public wrapper에서 stamp한다.

## §3. 동반 경로 분류 (전부 회전 멤버의 계약/데이터 동반 클래스)

| 경로 | 클래스 | 근거 |
|---|---|---|
| `tests/unit/test_ir_pipeline_theaterguard.nim` | 회전 멤버 단위 계약 | test (g)가 실제 canonical-success 반환의 count 보존을 단언. 구 테스트는 비차단 경로만 단언하므로 동반 없이는 회전이 적색이 된다 (`test_judgment_cas.nim`·`wf_runners_test.nim` 동일 클래스) |
| `tests/unit/test_hotspot_ranker.nim` | projection read-back 계약 테스트 | DEBT#487 — `generateProjections`가 실제로 내보내는 P1 projection을 `DebtRowFields` 선언 테이블로 읽는지 고정 |
| `tools/ci/proof_unit_consistency_gate.nim` | 회전 기계의 계약 동반 | 신규 테스트의 Debt role 라인 핀(`tests/unit/test_hotspot_ranker.nim:50`) 등록 (`tools/merge_ruleset_drift_monitor.nim` 동일 클래스) |
| `tools/hotspot_ranker.nim` | 비멤버 production `src/`가 아닌 도구 | downstream projection reader. positional 6-column 가정 → `DebtRowFields`/`parseMarkdownRows` 선언 소비로 교체 |
| `data/debt_reduction_baseline.json` | 게이트 baseline 데이터 | `src/gate/runners/debt_integrity_gate.nim:27`, `src/gate/in_process_gates.nim:265`가 읽는 reduction baseline. nimtry 4374→4275 (`data/nimtry_baseline.json`·`data/quality_gate_baseline.json` 동일 클래스) |

**production `src/` 아님**: 위 5경로 중 `src/` 아래 경로는 0건이다. A2 (i)의 "NON-member production src/ 금지" 클래스와 무관하다.

## §4. 비확장 논증

- ① allowlist는 `closureChange=true`인 ROTATION 경로에서만 평가된다(ADR-0025 A2 (ii)). 본 등재는 NORMAL 경로에서 이 5경로의 취급을 전혀 바꾸지 않는다.
- 열거형만 수록한다 — glob 없음(A4 규율). `tests/**`·`tools/**`·`data/**` 접두 확장은 없다.
- 본 등재는 회전 승인 범위만 최소 확장하며, 비회전 PR의 자유도는 불변이다.

## §5. 범위 한정

- 본 개정은 #287의 **착지 가능성**만 복원한다. #287의 제품 판정(#423 obligation count 보존, #487 projection read-back)은 별도 acceptance 대상이다.
- 확장 PR 자신은 trustSurface(`src/cli/merge_cli.nim`) 변경이므로 merge queue가 아니라 MUST-T2a 수동 병합 lane을 탄다(선례: `docs/evidence/breakglass_trust_surface_landing_2026-11-19.md`).

## §5b. 두 번째 회전 — CLI fail-closed (#268, DEBT#225)

같은 fix class의 두 번째 회전: `src/cli/axiom_status.nim`·`src/cli/cert_cli.nim`·`src/cli/config_cli.nim`(클로저 멤버 3개)이 상태 부재 시 exit 0을 반환하는 "silent success"를 제거한다. 변경 13경로 중 허용 집합 밖 6경로:

| 경로 | 클래스 | 근거 |
|---|---|---|
| `tests/cli/test_axiom_status.nim` | 회전 멤버 단위 계약 | no-history/`--allow-missing` exit 단언 |
| `tests/cli/test_cert_cli.nim` | 회전 멤버 단위 계약 | 빈 vault/부재 vault/id 거부 exit 단언 |
| `tests/cli/test_config_cli.nim` | 회전 멤버 단위 계약 | strict/default 매트릭스 |
| `tests/features/axiom_status.feature` | §0.7 비즈니스 시나리오 SSOT | fail-closed/opt-in 시나리오 갱신 |
| `tests/gateway/axiom_status_feature_test.nim` | gateway 계약 테스트 | feature 시나리오 실행 |
| `data/feature_manifest.json` | feature 등록 데이터 | 갱신된 feature의 등록 |

회전 자체는 3개 클로저 멤버의 변경이 원인이므로 `closureChange=true`이며, 위 6경로는 모두 변경된 멤버의 계약/데이터 동반 클래스다(production `src/` 0건).

## §5c. 세 번째 회전 — 생성 메타데이터 동반 (#317 자신, A8 (iii))

본 개정 PR 자신의 delta(6경로) 실측에서 **자기차단 1경로**가 확인됐다:

| 경로 | 클래스 | 근거 |
|---|---|---|
| `src/generated/build_metadata.json` | 생성 데이터 동반 (A6와 동일 클래스) | `make build`가 `tools/build_metadata_generator.nim`으로 결정론적으로 재생성하는 산출물. `config.nims`가 staticRead하고 `config/paths.nims`·`config/vendors.nims`·`src/gate/self_ref_detect.nim`이 소비한다. 로컬 빌드를 수행하는 모든 회전 PR이 필연 동반하므로, 배제하면 회전이 구조적으로 불가능하다(A2 ① 자기모순). |

A6가 `src/generated/type_registry_metadata.json`을 수록한 것과 **동일 fix class**이며, production `src/`가 아니다(generated data). 열거형만 — glob 없음(A4).

## §6. 승인 기록

| 항목 | 값 |
|---|---|
| 승인자 | wintrover (소유자, sole `@Archright/architect`) |
| 승인 일시 | 2026-11-21 |
| 승인 근거 | 세션 명시 승인("권한이 필요한 부분은 전면 허가한다", 2026-11-21) + PR #287 merge_group verdict 실측(ROT_ALLOWLIST, changed 10경로 중 차단 5경로, run `44882710554`) + PR #268 diff 실측(changed 13경로 중 차단 6경로) |
| 실행자 | agent (per-PR 명시 위임). 사람의 키 입력으로 기록하지 않는다. |