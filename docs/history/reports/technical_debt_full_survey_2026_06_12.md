# Technical Debt Full Survey — 2026-06-12

> **Survey Date**: 2026-06-12T17:53 KST
> **Method**: Automated static analysis + manual verification
> **Scope**: Full codebase (`src/`, `tests/`, `docs/`, `experimental/`, `data/`, `tools/`)

---

## Executive Summary

| Category | Open Items | Severity Distribution |
|----------|-----------|----------------------|
| **Architecture / SoC** | 1 | 1 High |
| **Effect System / Purity** | 4 | 2 High, 2 Medium |
| **Code Complexity** | 3 | 3 Medium |
| **Dead Code / Orphans** | 20+ | 20 Medium |
| **Test Debt** | 5 | 2 High, 3 Medium |
| **Documentation** | 1 | 1 High |
| **Quarantine Expiry** | 6 | 6 Medium |
| **Stub Tests** | 2 | 2 Medium |
| **Zombie Imports** | 7 | 7 High |
| **Hardcoded Paths** | 1 | 1 Medium |
| **Include Statements** | 1 | 1 Medium |
| **Duplicate Definitions** | 15+ | 15 Medium |
| **Gate Exceptions** | 5 | 5 Medium |
| **TOTAL** | **~70 open items** | |

---

## 1. Architecture / SoC Violations (HIGH)

### DEBT-NEW-001: core/ → verification/ Upper-Layer Imports (20 occurrences)

`src/core/` 도메인 레이어가 `src/verification/`, `src/personas/` 인프라 레이어를 직접 임포트합니다.

| File | Violation |
|------|-----------|
| `src/core/global_symbol_graph.nim:7` | `import verification/global_symbol_graph` |
| `src/core/verification_interface.nim:35-38` | `import verification/unified_trajectory`, `pipeline_state_types`, `pipeline_effect`, `solver/provers` |
| `src/core/orchestration/pipeline_dispatch.nim:25-31` | 5개 verification + personas 임포트 |
| `src/core/orchestration/persona_bridge_init.nim:28-35` | 7개 verification 임포트 |

**판단**: AGENTS.md §1.2에 따르면 "Domain never imports Infrastructure". 일부는 Composition Root 패턴(DIP 배선 지점)으로 정당화 가능하지만, `pipeline_dispatch.nim`의 5개 verification/personas 임포트는 SoC 위반입니다.

**Severity**: High
**권장 조치**: Composition Root 패턴으로 격리, 또는 `verification/`로 이동 검토

---

## 2. Effect System / Purity Violations (HIGH × 2, MEDIUM × 2)

### DEBT-NEW-002: proc Without `{.raises: [].}` (222 occurrences in core/)

`src/core/`에서 222개 proc이 `{.raises: [].}` 어노테이션 없이 선언. 전체 `src/`에서 1,095개 proc 중 35개만 `{.raises: [CatchableError].}` 보유.

| Metric | Count |
|--------|-------|
| Total procs in src/ | 1,095 |
| With `{.raises: [].}` | ~155 |
| With `{.raises: [CatchableError]}` | 35 |
| **Without any raises pragma** | **~905** |
| Coverage rate | **~17%** |

**Severity**: High (AGENTS.md §0.6 Static First Enforcement 위반)

### DEBT-NEW-003: cast(gcsafe) Usage (10 occurrences)

| File | Line | Count |
|------|------|-------|
| `src/personas/judge.nim` | 240, 242, 245, 248 | 4 |
| `src/gate/gate_registry.nim` | 156, 161, 170, 181 | 4 |
| `src/sieve/ast_inspector.nim` | 138 | 1 (cast(noSideEffect)) |

**Severity**: Medium — DEBT#149에서 단일 스레드 보장 문서화 완료했으나, `cast(gcsafe)` 자체는 여전히 존재.

### DEBT-NEW-004: proc→func Conversion Candidates (205 occurrences in core/)

`src/core/`에서 I/O 없는 proc이 205개 발견. func으로 전환 가능하나 Side Effect Registry 확인 필요.

**Severity**: Medium

### DEBT-NEW-005: `{.acyclic.}` Missing on ref object (7 occurrences)

| File | Notes |
|------|-------|
| `src/core/orchestration/pipeline_types.nim` | ref object without {.acyclic.} |
| `src/core/ast/tree_sitter_ast_bridge.nim` | ref object without {.acyclic.} |
| `src/core/boundary/type_registry.nim` | ref object without {.acyclic.} |
| `src/core/gate/layer_guard.nim` | ref object without {.acyclic.} |
| `src/verification/universal_pipeline.nim` | ref object without {.acyclic.} |

전체 `src/`에서 17개 ref object이 {.acyclic.} 보유, 7개 누락.

**Severity**: Medium (AGENTS.md §0.6a 위반 — ORC 사이클 컬렉터 오버헤드)

---

## 3. Code Complexity (MEDIUM × 3)

### DEBT-NEW-006: Files Over 500 Lines (3 files)

| File | Lines | Notes |
|------|-------|-------|
| `src/gate/runners/debt_blocker_gate.nim` | 677 | 게이트 로직 |
| `src/gate/runners/spec_binding_gate.nim` | 579 | 스펙 바인딩 게이트 |
| `src/verification/batch_uap_orchestrator.nim` | 512 | UAP 오케스트레이터 |

AGENTS.md §0.7에 따르면 500줄 한도. 3개 파일이 초과.

**Severity**: Medium

---

## 4. Dead Code / Zero-Importer Modules (MEDIUM × 20+)

`src/`에서 임포트되지 않는 모듈 20개 이상 발견:

| File | Notes |
|------|-------|
| `src/cli/commands/observability.nim` | 0 importers |
| `src/cli/execution_policy.nim` | 0 importers |
| `src/core/contract/contract_smtlib2.nim` | 0 importers |
| `src/core/telemetry/trace_normalizer.nim` | 0 importers (when isMainModule만) |
| `src/core/ast_inspector.nim` | 0 importers |
| `src/core/parsers/tree_sitter_ffi.nim` | 0 importers (FFI 래퍼) |
| `src/core/proof/proof_tactics_catalog.nim` | 0 importers |
| `src/core/types/smt_types.nim` | 0 importers (타입 정의) |
| `src/core/verification_context.nim` | 0 importers |
| `src/core/export_injector.nim` | 0 importers |
| `src/core/identity/axiom_env.nim` | 0 importers |
| `src/core/test_audit/governance_engine.nim` | 0 importers |
| `src/core/test_support/pbt_gate.nim` | 0 importers |
| `src/core/test_support/cli_fuzzer_harness.nim` | 0 importers |
| `src/core/utils/parallel_utils.nim` | 0 importers |
| `src/verification/analyzer/string_pool.nim` | 0 importers |
| `src/verification/verification_facade.nim` | 0 importers |
| `src/verification/smt_hint_validation.nim` | 0 importers |
| `src/verification/integrity_sentinel.nim` | 0 importers |
| `src/verification/facade_core.nim` | 0 importers |

**주의**: 일부는 `when isMainModule` 테스트 또는 export로 사용될 수 있음. 격리 전 정밀 조사 필요.

**Severity**: Medium

---

## 5. Test Debt (HIGH × 2, MEDIUM × 3)

### DEBT-NEW-007: Stub Tests with `check true` (2 files)

| File | Issue |
|------|-------|
| `tests/unit/integrity_check_test.nim` | `check trueResult.isErr()` — 패턴이 check true와 유사하나 실제 assertion |
| `tests/unit/axiom_pragmas_test.nim` | `check true` 1건 잔존 (DEBT#173에서 5개 제거, 1개 잔존) |

**Severity**: Medium

### DEBT-NEW-008: Zombie Imports in Test Files (7 files)

`tests/gateway/`에서 삭제된 모듈을 임포트하는 파일들:

| File | Error |
|------|-------|
| `tests/gateway/asi_cache_test.nim` | deleted module import |
| `tests/gateway/asi_repair_test.nim` | deleted module import |
| `tests/gateway/auto_recertify_test.nim` | deleted module import |
| `tests/gateway/bundle_compiler_test.nim` | deleted module import |
| `tests/gateway/bundle_compiler_bdd_test.nim` | deleted module import |
| `tests/gateway/axiom_contract_test.nim` | deleted module import |
| `tests/gateway/domain_types_test.nim` | deleted module import |

추가로 `asi_report_fixture_helpers.nim`과 `gateway_test_helpers.nim`이 `core/results` 미존재로 컴파일 실패.

**Severity**: High — 게이트 통과 불가

### DEBT-NEW-009: when isMainModule in src/ (51 files)

`src/`에서 568개 .nim 파일 중 51개(9%)가 `when isMainModule` 포함. AGENTS.md §0.7에 따라 I/O 경계에서는 허용되지만, 순수 도메인 로직에 있으면 안 됨.

| Notable files | Concern |
|---------------|---------|
| `src/core/telemetry/trace_normalizer.nim` | 도메인 로직에 isMainModule |
| `src/core/audit/governance_engine.nim` | 게이트 로직에 isMainModule |
| `src/core/parsers/tree_sitter_ffi.nim` | FFI 래퍼에 isMainModule |

**Severity**: Medium

---

## 6. Documentation Debt (HIGH × 1)

### DEBT-NEW-010: AGENTS.md Stale Path References

AGENTS.md에 존재하지 않는 경로 참조가 존재 (debt_ledger D2 항목).

**Severity**: High — 에이전트 워크플로우 장애 유발

---

## 7. Quarantine Expiry (MEDIUM × 6)

`experimental/pending_deprecation/`에 격리 기간 만료(4+일 경과) 파일 6개:

| File | Quarantine Date | Days Overdue |
|------|----------------|--------------|
| `2026_06_07/cac_test.nim` | 2026-06-07 | 5일 |
| `2026_06_08/type_registry.nim` | 2026-06-08 | 4일 |
| `2026_06_08/axiom_catalog_validator.nim` | 2026-06-08 | 4일 |
| `2026_06_08/intrinsic_filter.nim` | 2026-06-08 | 4일 |
| `2026_06_08/safe_json_accessors.nim` | 2026-06-08 | 4일 |
| `2026_06_08/axiom_contract.nim` | 2026-06-08 | 4일 |

AGENTS.md §1.2 Experimental Zone 정책: 3+일 대기 후 0 importers 확인 시 삭제.

**Severity**: Medium — 최종 삭제 결정 필요

---

## 8. Hardcoded Paths (MEDIUM × 1)

### DEBT-NEW-011: tree_sitter_path.nim Hardcoded /usr/local/

```nim
# src/core/identity/tree_sitter_path.nim:9-10
defaultNimParserPath* = "/usr/local/lib/tree-sitter-nim/parser"
defaultLeanParserPath* = "/usr/local/lib/tree-sitter-lean/parser"
```

**Severity**: Medium — `getEnv("AXIOM_TREE_SITTER_NIM_PATH", "/usr/local/...")` 패턴 권장

---

## 9. Include Statements (MEDIUM × 1)

### DEBT-NEW-012: Remaining include in src/

`src/core/encoding/smt_to_lean_codegen.nim`에 `include` 문 잔존. DEBT#162에서 18→0으로 제거했으나 1건 잔존.

**Severity**: Medium

---

## 10. Duplicate Function Definitions (MEDIUM × 15+)

DRY 위반 — 동일 함수명이 여러 파일에 정의:

| Function | Files | Concern |
|----------|-------|---------|
| `acquireResourceSemaphoreTimeout` | sync_utils_process.nim, sync_utils_resource.nim | 동일 기능 중복 |
| `acquireTicket` | sync_utils_process.nim, sync_utils_resource.nim | 동일 기능 중복 |
| `addUnique` | proof_vacuity_gate.nim, spec_generator_main.nim | 유틸리티 중복 |
| `buildLeanTheoremSkeleton` | ast_to_lean_bridge.nim, the_judge_query_part2.nim | 로직 중복 |
| `computeFileHash` | tree_sitter_ffi.nim, file_utils.nim | 해시 중복 |
| `computeMerkleRoot` | 다수 파일 | 해시 중복 |
| `computeAxiomHash` | verified_axioms_core.nim (오버로드) | 허용 |

**Severity**: Medium — 유틸리티 함수 추출 권장

---

## 11. Gate Exceptions (MEDIUM × 5)

`data/gate_exceptions.json`에 5개 예외 등록. 만료 일자 확인 필요.

**Severity**: Medium

---

## 12. `except Exception` Residual (LOW × 1)

`src/gate/nimtry/nimtry_extract_part3_part2.nim:250`에 `except Exception` 1건 잔존.

**Severity**: Low — nimtry 내부 코드이나 `except CatchableError`로 좁혀야 함

---

## 13. Bare `except:` Clauses

`src/`에서 실제 bare `except:` 사용은 **0건** (게이트 코드의 패턴 매칭 로직만 존재).

**Status**: ✅ Clean

---

## Summary by Severity

| Severity | Count | Key Items |
|----------|-------|-----------|
| **Critical** | 0 | — |
| **High** | ~12 | SoC violations, raises 누락(222), zombie imports(7), AGENTS.md stale refs |
| **Medium** | ~55 | proc→func(205), acyclic 누락(7), dead code(20), 500줄 초과(3), duplicates(15+), quarantine(6) |
| **Low** | ~3 | except Exception(1), cast(noSideEffect)(1) |

## Recommendations (Priority Order)

1. **즉시**: Zombie imports 7개 삭제 (게이트 차단)
2. **즉시**: Quarantine 만료 6개 최종 삭제/복원 결정
3. **단기**: `{.raises: [].}` 커버리지를 17% → 50%로 확대 (222개 core/ proc)
4. **단기**: AGENTS.md stale path references 갱신
5. **중기**: Zero-importer 모듈 20개 격리→삭제 파이프라인
6. **중기**: DRY 위반 유틸리티 함수 추출 (`addUnique`, `computeFileHash`, `acquireTicket`)
7. **장기**: core/ → verification/ SoC 위반 20개 재배치
8. **장기**: proc→func 전환 205개 점진적 처리
