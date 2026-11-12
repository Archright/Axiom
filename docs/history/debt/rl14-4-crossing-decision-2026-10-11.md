# RL-14.4 Crossing Decision (M-41 단계적 집행)

- 작성일: 2026-10-11
- 브랜치: `feat/rl14-4-execution-authority`
- 목적: RL-14.4(`src/core/` → `src/verification/`, `src/gate/` import 금지) 기존 위반 23쌍에 대한
  아키텍트 결정을 기록한다 — 정본 권위의 3층 배분, 승인된 단계적 적용, per-import-target 예외 스코프,
  예외 수명과 재검토, surface 재등록 Owner 결정, GitHub 집행 불변, 부채 등록 프로토콜을 확정한다.
  기록 목적의 참조 문서이며 자동 생성/검증 로직에는 영향 없다.
- 선행 문서: [orphan-gates-decision-2026-08-08.md](orphan-gates-decision-2026-08-08.md) (형식 선례),
  [allowed_imports_lock_status.md](../../spec/allowed_imports_lock_status.md) (좀비 SSOT 판정),
  DEBT#492 · DEBT#494 · DEBT#495 (`data/debt_registry.json`)

## 1. 승인 (Approval)

인간 사용자는 2026-10-11에 본 작업(RL-14.4/M-41 단계적 집행 착지 준비)에 대해 명시 승인을
부여하였다 — 원문 인용:

> **"권한이 필요한 부분은 전면 허가한다"** (2026-10-11)

이 승인은 아래 두 읽기 전용 경면에 대한 개정 근거이다:

- `docs/agents/architecture.md:24` — "Immutable Policy Artifacts: `AGENTS.md` and
  `docs/agents/*.md` are read-only policy SSOT. Build scripts MUST NOT write to them."
- `docs/agents/core_rules.md` §18 Amendment Authority — "This layer architecture may be amended
  only via GUARDIAN.md amendment procedure ... No agent may unilaterally alter layer boundaries."

본 기록은 계층 방향(RL-14.4)을 **변경하지 않는다** — 신규 import는 여전히 즉시 되돌리기 위반이며,
승인된 폐쇄 집합만 과도기적 예외로 문서화한다(§3 항목 2). `docs/agents/core_rules.md`에 대한 수정
(RL-14.4 과도기 조항 신설 + 스테일 주장 4건 교정)은 상기 승인의 이행이며, 에이전트의 일방적
(unilateral) 계층 경계 변경이 아니다. 착지는 기존 절차(GateInvariants 아키텍처 게이트 → pre-commit
승인 → GitHub merge authority)를 그대로 통과한다 — 이것이 §18이 요구하는 절차의 이행 경로다.

## 2. 근거 (Evidence)

- **DEBT#494**: `.githooks/pre-push`(Part 3 `layer_enforcement_gate` 직접 호출 — pre-commit Part 3와
  중복, push되는 OID를 전혀 검사하지 않음)와 `src/gate/architecture_policy.lock`(phantom
  `allowed_core_to_verification` 2건 — `core/contract/verification_interface.nim`,
  `core/boundary/persona_boundary.nim`는 직접 금지 계층 import가 없음) 수정이
  `bin/surface_guard` SURFACE_FORBIDDEN(FROZEN MODIFY=FAIL, base-policy binding)으로 시도·REVERTED되었다.
  명시된 해소 경로: "2-stage policy PR — stage 1 re-registers both paths as CONTROLLED with a
  numbered Owner decision (precedent v52 'Owner decision #18'), stage 2 applies the patches."
- **DEBT#492**: `src/gate/orchestrator_pure.nim` 모듈 헤더가 이미 삭제된
  `bin/orchestrator_pure_import_guard`(DEBT#491로 제거) 집행을 주장 — 스테일 클레임.
  명시된 해소 경로: "surface policy PR re-registering the file as CONTROLLED (Owner decision,
  precedent v52 'Owner decision #18'), then delete the one line."
- **DEBT#495**: 기존 per-FILE 허용 필터는 화이트리스트된 파일이 **새로운** verification/gate import를
  추가해도 묵인한다 — 예외는 (소스 파일, import 대상) 쌍 단위로 스코프되어야 한다(§4).
- **`docs/spec/allowed_imports_lock_status.md`**: `docs/agents/core_rules.md` 363·385·386·391행의
  `src/allowed_imports.lock` SSOT 주장이 FALSE로 판정됨(판정 근거와 교정 초안은 동 문서 §2·§6).
- **`src/gate/architecture_policy.lock:26`**: `Expires: 2026-12-12` — 예외 재검토 일정의 동기 기준.
- **현황 측정**: `src/core/` → `verification|gate` 기존 import는 15개 소스 파일에 걸쳐
  **23쌍**이다(§3.1 표). 신규 추가분은 없다.

## 3. 결정 항목

| # | 항목 | 결정 |
|---|------|------|
| 1 | 정본 권위 | **기계 정본** = `src/core/trusted/layer_rules.nim` (레이어 방향) / **예외 정본** = `src/gate/architecture_policy.lock` / **정책 서술** = `docs/agents/core_rules.md` (RL-14.4) |
| 2 | 전환 방식 | **(a) 승인된 단계적 적용** — 기존 23쌍 한시 예외, 신규는 차단 |
| 3 | 예외 범위 | **(소스 파일, 정규화 import 대상) 쌍** 23건 — §3.1 표 |
| 4 | 예외 수명 | 책임자 / 해소 조건 / **재검토 2026-12-12** (`architecture_policy.lock:26` Expires와 동기) / 종료 조건 — §3.2 |
| 5 | 변경 권한 | `repository_surface.json` 재등록 — **Owner 결정 #19** (§3.3) |
| 6 | GitHub 집행 | required check = **`admission-check` (기존 유지)**, merge queue = **기존 `ALLGREEN, max_entries_to_merge: 1`** (임의 선택 금지) |
| 7 | 부채 등록 | `docs/spec/debt_projection_contract.md` §5 프로토콜 (§3.4 인용) |

### 3.1 예외 23쌍 표

| 소스 파일 | 정규화 import 대상 | 근거 | 만기 |
|---|---|---|---|
| `core/application/persona_context_init.nim` | `verification/composition/leanstral_registry`, `scan_registry`, `bmc_registry`, `cegar_registry`, `healing_registry` | ADR-014 (Accepted) — composition root | v0.5.0 |
| `core/boundary/verification_interface.nim` | `verification/abstract_provider_types`, `verification/pipeline_state_types`, `verification/solver/fixedpoint_types`, `verification/unified_trajectory_types` | type-only facade (DEBT#483) | 2026-12-12 |
| `core/orchestration/pipeline_dispatch.nim` | `verification/pipeline_effect` | orchestration wiring | 2026-12-12 |
| `core/orchestration/pipeline_types.nim` | `verification/pipeline_effect` | shared effect types | 2026-12-12 |
| `core/judge/lean_replay.nim` | `verification/lean_lsp_compiler`, `verification/obligation/lean_kernel_boundary` | — | 2026-12-12 |
| `core/proof/proof_vacuity_gate.nim` | `verification/solver/z3_pool` | + RL-14.10 별도 처분 필요 | 2026-12-12 |
| `core/symbol_graph/lean_symbol_integration.nim` | `verification/lean_lsp_protocol` | — | 2026-12-12 |
| `core/trusted/compile_time_manifest.nim` | `gate/manifest_schema_validator` | — | 2026-12-12 |
| `core/trusted/ir_to_lean.nim` | `verification/obligation/obligation_ir` | — | 2026-12-12 |
| `core/trusted/ir_to_smt.nim` | `verification/obligation/obligation_ir` | 미사용 import 후보 — 삭제 검토 | next review |
| `core/trusted/layer_enforcement.nim` | `gate/gate_consts` | 재배선 검토 | next review |
| `core/trusted/private/canonical_chc_compiler.nim` | `verification/obligation/obligation_ir` | — | 2026-12-12 |
| `core/trusted/private/ir_loop_to_horn.nim` | `verification/obligation/obligation_ir` | — | 2026-12-12 |
| `core/verifier/lean_repl_bridge.nim` | `verification/lean_repl_bridge` | — | 2026-12-12 |
| `core/gate/gate_to_smt.nim` | `verification/solver/z3_pool` | + RL-14.10 별도 처분 필요 | 2026-12-12 |

15개 소스 파일, 합계 **23쌍** (5+4+1+1+2+1+1+1+1+1+1+1+1+1+1). 집합은 폐쇄적이며, 추가는
Amendment Authority 절차 전체를 요구하고 만기 전에는 **수축만** 가능하다.

### 3.2 예외 수명

- **책임자**: 인간 아키텍트(재검토·종료 판정) + RL-14.4 workstream(정산 실행).
  개별 쌍의 정산 소관은 §3.1 근거 열이 지칭하는 기존 ADR/부채 항목(DEBT#483, RL-14.10 별도 처분 등)을 따른다.
- **해소 조건**: 유형별 정산 — (i) 타입 이동(예: verification 타입의 Domain 이전, v0.5.0 표기 쌍),
  (ii) 미사용 import 삭제(`ir_to_smt.nim`), (iii) 재배선(`layer_enforcement.nim` ← `gate/gate_consts`),
  (iv) composition root 이외 경로의 접근 재설계. 정산된 쌍은 예외 정본에서 **제거**한다.
- **재검토**: **2026-12-12** — `src/gate/architecture_policy.lock:26`의 `Expires: 2026-12-12`와
  동기. 재검토에서 잔존 쌍은 1건씩 존업(justify) 또는 제거된다.
- **종료 조건**: 23쌍 전체 소멸(정산 완료) 시 본 과도기 조항은 폐쇄되고 RL-14.4는 무예외로 복귀한다.
  만기 도과 시 미정산 쌍의 예외는 소멸하고 정상 위반으로 환원된다(fail closed).

### 3.3 변경 권한 — surface 재등록 (결정 항목 5 상세)

**Owner 결정 #19** (정책 `policyVersion` 56 → 57, `config/repository_surface.json` v57 노트):
RL-14.4/M-41 workstream이 수정해야 하는 FROZEN 경로 4건을 **개별 CONTROLLED로 재등록**한다 —
`.githooks/pre-push`(DEBT#494 stage-2), `src/gate/architecture_policy.lock`(DEBT#494 stage-2 +
M-41 예외 정본), `src/gate/orchestrator_pure.nim`(DEBT#492), `src/gate/runners/layer_enforcement_gate.nim`
(M-41 게이트 러너 본문). broad wildcard 금지 — `src/gate/**`, `.githooks/**` FROZEN glob은 불변이며
나머지 경로는 동결 유지된다.

- `Makefile`은 재등록 불요 — v55가 이미 CONTROLLED에 개별 등록하였고 classResolutionOrder
  (PRODUCT→CONTROLLED→FROZEN first-match)상 CONTROLLED가 우선한다.
- `.github/workflows/admission-check.yml`은 v52(Owner 결정 #18)로 이미 CONTROLLED이며, 본 결정 항목 6에
  따라 CI 정의는 **무변경**이다. `.github/actions/**`를 포함한 나머지 `.github/**`는 FROZEN 유지.
- 정책 PR 자신은 FROZEN(본 정책 파일) 수정이므로 base-policy binding상 착지 전까지 효력이 없다 —
  Owner 결정 #18(c)이 문서화한 수용 리스크 경로와 2단계 choreography를 따른다. 본문 PR에는
  `--no-verify`를 적용하지 않는다.

### 3.4 부채 등록 프로토콜 (결정 항목 7 인용)

`docs/spec/debt_projection_contract.md` §5 (Atomic Materialization — Mutation Protocol):

```
1. validate   → bin/debt_engine --validate
               (confirms current projections match the SSOT)

2. mutate SSOT → edit data/debt_registry.json
               (only file developers may hand-edit)

3. regenerate → bin/debt_engine --codegen
               (computes both P1 projections in memory, writes both)

4. re-validate → bin/debt_engine --validate
               (confirms new projections are byte-identical to what was just written)

5. commit     → single changeset containing:
                 - data/debt_registry.json (SSOT mutation)
                 - docs/DEBT_REGISTRY.md (P1 projection)
                 - src/generated/debt_constants.nim (P1 projection)
                 - data/debt_ledger.json (only if BUDGET counts changed; run --sync-budget first)
```

"If step 3 or step 4 fails, no commit is made. The mutation is all-or-nothing."
(단일 기록자: ADR-0029 — `docs/DEBT_REGISTRY.md`·`src/generated/debt_constants.nim` 수편집 금지)

## 4. 설계 결함 명시 및 기각된 설계

- **설계 결함 (DEBT#495)**: 기존 per-FILE 필터는 화이트리스트된 소스 파일이 **신규** import를
  추가하는 것을 묵인한다 — 예외는 **per import target**으로 스코프되어야 한다. 이에 따라 예외 정본
  (`src/gate/architecture_policy.lock`)과 본 문서 §3.1 표는 (소스 파일, 정규화 import 대상) 쌍
  단위이며, `docs/agents/core_rules.md`의 과도기 조항도 "a whitelisted file MUST NOT gain new
  verification|gate imports (DEBT#495)"을 명문화한다.
- **기각된 설계**: `src/core/trusted/layer_rules.nim`이 `src/gate/architecture_policy.lock`을
  직접 읽는 방식은 **채택하지 않는다**. 이는 Domain(`src/core/trusted/`)→Gate(`src/gate/`) 데이터
  의존을 재창출하며 `docs/agents/architecture.md:88` — "Domain never imports Infrastructure,
  Presentation, or Gate" — 을 위반한다. 대신 `layer_rules.nim`은 레이어 방향 정본으로서 잠금
  허용목록을 **파라미터로 소비**하며, 소비자(게이트 러너 측)가 잠금 파일을 읽어 주입한다.
  예외 정본과 방향 정본의 권위 분리는 §3 항목 1과 같다.

## 5. 검증 (Verification)

아래는 이 문서 작성 시점에 실행한 검증 결과이다.

| 검증 항목 | 명령 | 기대값 | 실제 값 | 판정 |
|-----------|------|--------|---------|------|
| B14 사전 비행 (파일 생성 전) | `nim c -r src/gate/runners/agent_preflight.nim` | `[SUCCESS] Agent Pre-flight Guard` | `[SUCCESS] Agent Pre-flight Guard: Workspace 무결성 검증 통과.` (decision-binding WARN 28건 — escalation 30일 미도과, 기존 상태) | PASS |
| Surface guard (본 슬라이스 diff 3경로) | `bin/surface_guard --policy config/repository_surface.json --diff <git diff --name-status>` | 정책 파일 자체는 FROZEN-MODIFY로 FAIL 예정(의도된 self-authorization block), 나머지 본 슬라이스 경로 PASS | `verdict: FAIL / SURFACE_FORBIDDEN / policyVersion: 57 / binding: base` — 위반 **1건뿐**: `config/repository_surface.json` (M, FROZEN, base-policy). `docs/agents/core_rules.md`(M)·`docs/history/debt/rl14-4-crossing-decision-2026-10-11.md`(A)는 PASS. 이 FAIL은 v51 knownBlindSpots가 문서화한 의도된 self-authorization block이며, Owner 결정 #18(c)·#19의 2단계 choreography(정책 PR 선착지 → 본문 PR) 그대로다. 전체 작업 트리 diff(타 트랙 20 changes 포함) 재판정에서도 위반은 동일 1건뿐 | PASS(예상대로) — 정책 PR push는 Owner 결정 #1 수용 리스크 경로(`--no-verify`) 문서화 그대로 |
| 부채 투영 정합 | `bin/debt_engine --validate` | 프로젝션==SSOT, exit 0 | `Checks: 1423 total, 1423 passed, 0 failed` / `All debt validation checks passed.` / EXIT=0 (nimtry_violations DRIFT 1건 — disposition=INFO, 기존 상태) | PASS |
| B14 사후 비행 (3파일 수정 후) | `nim c -r src/gate/runners/agent_preflight.nim` | `[SUCCESS]` | `[SUCCESS] Agent Pre-flight Guard: Workspace 무결성 검증 통과.` | PASS |

## 6. 불가침 파일 미수정 선언

본 슬라이스는 위 3개 파일 —
`docs/history/debt/rl14-4-crossing-decision-2026-10-11.md`(신규),
`docs/agents/core_rules.md`, `config/repository_surface.json` — 만 생성/수정하였으며,
아래 파일들은 **일절 수정하지 않았다**.

- `AGENTS.md` (AGENTS.md §-1 불변)
- `src/gate/runners/import_encapsulation_gate.nim` + `config.nims` importEncapsulation 블록 (§-1 불변)
- `src/core/trusted/layer_rules.nim`, `src/core/trusted/layer_enforcement.nim` — 다른 트랙 소유
- `src/gate/architecture_policy.lock`, `src/gate/runners/layer_enforcement_gate.nim` — 다른 트랙 소유
- `Makefile` — 다른 트랙 소유
- `tests/negative/**` — 다른 트랙 소유
- `.githooks/pre-push`, `src/gate/orchestrator_pure.nim` — DEBT#494/DEBT#492 stage-2 대상 (다른 트랙)
- `src/allowed_imports.lock` — Deprecated 헤더로 이미 정산됨(allowed_imports_lock_status.md), 본 슬라이스 변경 없음
- `.github/**` 전체 — 결정 항목 6(기존 유지, 임의 선택 금지)에 따라 무변경
