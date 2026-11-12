# Technical Debt Full Survey — 2026-06-07

> **Methodology**: Fowler Technical Debt Quadrant × SonarQube Metrics × Axiom 4D Gate (Ideal/Elegant/Fundamental/Deterministic)
> **Context7 Sources**: Martin Fowler (Technical Debt Quadrant), Refactoring Guru (Code Smells Taxonomy), SonarQube (Quality Metrics)
> **Scan Agents**: 6 parallel (code, directory, architecture, test, documentation, gate infrastructure)
> **Evidence Files**: `verifications/*_debt_scan_2026_06_07.txt` (6 files, ~79KB total)

---

## Executive Summary

| Category | Critical | High | Medium | Low | Total |
|----------|----------|------|--------|-----|-------|
| Code Debt | 0 | 2 | 5 | 3 | **10** |
| Directory Debt | 1 | 2 | 4 | 3 | **10** |
| Architecture Debt | 0 | 4 | 4 | 0 | **8** |
| Test Debt | 0 | 3 | 2 | 2 | **7** |
| Documentation Debt | 0 | 2 | 3 | 3 | **8** |
| Gate Infrastructure | 0 | 1 | 3 | 1 | **5** |
| **Total** | **1** | **14** | **21** | **12** | **48** |

**Open Registry DEBTs (pre-existing)**: 8 items (#143, #162, #163, #166, #167, #169, #175, #176)
**New Items Registered**: DEBT#190~#207 (18 items)
**Immediate Fixes**: 4 items (D-01 쓰레기파일, D-02 ELF, D-05 pycache, C-01 stub)

### Regression Alert 🚨

**`when isMainModule` anti-pattern**: 32 → 51 files (+59% regression vs DEBT#166/#175 baseline)

---

## §1. Code Debt (10 items)

| ID | Severity | Quadrant | Finding | Location |
|----|----------|----------|---------|----------|
| C-01 | 🟡 Medium | Reckless/Inadvertent | `test_v3_config.nim` — 4줄 stub (`echo "test"`만) | `src/gate/test_v3_config.nim` |
| C-02 | 🔴 High | Reckless/Inadvertent | `echo "hi"` 디버그 잔재 | `src/core/global_symbol_graph_builder_part2.nim:313` |
| C-03 | 🟢 Low | Prudent/Inadvertent | proc→func 전환 가능 ~4개 (30개 중 I/O 아닌 순수 계산) | `src/core/spec_generator_helpers.nim` 등 |
| C-04 | 🟡 Medium | Prudent/Deliberate | backward-compat re-export facade 21개 (17 파일) | `src/cli/`, `src/core/`, `src/verification/` |
| C-05 | 🟢 Low | Prudent/Inadvertent | magic number `96` 미추출 | `src/core/the_judge_lean.nim:162` |
| C-06 | 🟡 Medium | Prudent/Deliberate | deprecated func 5개 (`computeAsi` overloads) | `src/core/metrics.nim:92-116` |
| C-07 | 🟢 Low | Prudent/Deliberate | "REMOVED" tombstone comment 4건 | `translation_validator.nim` 등 |
| C-08 | 🟡 Medium | Prudent/Inadvertent | TODO/FIXME 주석 4건 | `refactoring_engine.nim`, `diagnostics_engine_main.nim` 등 |
| C-09 | 🔴 High | Reckless/Inadvertent | `echo "test"` stub 파일 (C-01과 중복, gate에서 §0.8 위반) | `src/gate/test_v3_config.nim` |
| C-10 | 🟡 Medium | Prudent/Deliberate | debug echo 2건 (BONUS: `echo "hi"` + `echo "test"`) | `src/core/`, `src/gate/` |

**Fowler 분류**: C-02/C-09는 Reckless+Inadvertent (디버그 잔재를 인지하지 못한 채 방치). C-04/C-06은 Prudent+Deliberate (backward compat을 의도적으로 유지).

---

## §2. Directory Debt (10 items)

| ID | Severity | Quadrant | Finding | Location |
|----|----------|----------|---------|----------|
| D-01 | 🔴 Critical | Reckless/Inadvertent | `0:` — 0바이트 쓰레기 파일, git-tracked | 프로젝트 루트 |
| D-02 | 🔴 High | Prudent/Deliberate | src/ 내 stale ELF 바이너리 10개 (8.7MB, untracked) | `src/personas/`, `src/cli/` 등 |
| D-03 | 🟡 Medium | Prudent/Inadvertent | 빈 top-level 디렉토리 3개 | `cli/`, `mcp-notion-server/`, `vendor/` |
| D-04 | 🟡 Low | Prudent/Inadvertent | 빈 서브디렉토리 4개 | `logs/effect_system_fix/` 등 |
| D-05 | 🟡 Medium | Prudent/Inadvertent | `tools/__pycache__/` 잔존 | `tools/` |
| D-06 | 🔴 High | Reckless/Inadvertent | **tests/features/ 내 git-tracked ELF 바이너리 4개 (~2.4MB)** | `tests/features/` |
| D-07 | 🟡 Medium | Prudent/Deliberate | PDF 7개 (5.7MB) in `docs/spec/` | `docs/spec/` |
| D-08 | 🟡 Medium | Prudent/Inadvertent | `seed_symbol_graph.json` 3.8MB data asset | `src/core/` |
| D-09 | 🟢 Low | Prudent/Inadvertent | 중복 evidence 파일 (동일 76K 파일 2경로) | `verifications/` |
| D-10 | 🟢 Low | Prudent/Deliberate | `build/` 70MB on-disk (gitignore 처리됨) | `build/` |

**🚨 신규 발견**: D-06 — `tests/features/`에 **git-tracked ELF 바이너리 4개**가 커밋되어 있다. 2.4MB의 레포 부풀림.

---

## §3. Architecture Debt (8 items)

| ID | Severity | Quadrant | Finding | Related DEBT |
|----|----------|----------|---------|-------------|
| A-01 | 🔴 High | Reckless/Inadvertent | `domain_types.nim` SSOT 위반 — 2개 파일 (core 5.8K vs core/types 8.8K) | DEBT#005 패턴 재발 |
| A-02 | 🔴 High | Prudent/Inadvertent | stub/real 쌍 3개: `vault_index`, `proof_universe_lock`, `cert_writer` | — |
| A-03 | 🟡 Medium | Reckless/Inadvertent | `session_parser_types` 7개 파일 각 12줄 (83줄→1파일 통합 가능) | — |
| A-04 | 🔴 High | Prudent/Deliberate | 3단계 중첩 `_parts/_parts/`, 16개 디렉토리, 38개 part 파일 | DEBT#162 |
| A-05 | 🔴 High | Reckless/Inadvertent | `pipeline_core_types.nim` 계층 간 타입 분할 (core↔verification) | — |
| A-06 | 🟡 Medium | Prudent/Deliberate | backward-compat facade 23개 모듈 | — |
| A-07 | 🟡 Medium | Prudent/Deliberate | `src/core/` 과밀 — 167개 top-level .nim 파일 | DEBT#163 |
| A-08 | 🟡 Medium | Prudent/Inadvertent | 중복 파일명 7개 (14파일 across src/) | — |

**include chain**: 18개 체인, 2개가 3단계 깊이 (DEBT#162+#167)

---

## §4. Test Debt (7 items)

| ID | Severity | Quadrant | Finding | Related DEBT |
|----|----------|----------|---------|-------------|
| T-01 | 🟢 Low | Prudent/Deliberate | @manual↔runner 모순 0건 (이전 조사와 달리 없음) | — |
| T-02 | 🔴 High | Reckless/Inadvertent | `resource_limits_test.nim` — 100% trivial stub (`check ok == true or ok == false`) | §0.8 위반 |
| T-03 | 🔴 High | Reckless/Inadvertent | `gate_utils_test.nim` — 100% trivial stub (동일 패턴) | §0.8 위반 |
| T-04 | 🔴 High | Reckless/Inadvertent | **`when isMainModule` 안티패턴 32→51개 (+59% 회귀)** | DEBT#166/#175 |
| T-05 | 🟡 Medium | Prudent/Deliberate | @manual 비율 61.5% (85/138 features) | DEBT#176 |
| T-06 | 🟡 Medium | Prudent/Inadvertent | experimental orphan 테스트 6개 (feature 미연결) | — |
| T-07 | 🟢 Low | Prudent/Inadvertent | `axiom_pragmas_test.nim` — `check true` 40% density | — |

**🚨 회귀 경보**: `when isMainModule`이 32개에서 51개로 +59% 증가. DEBT#166/#175의 기준선이 붕괴됨.

---

## §5. Documentation Debt (8 items)

| ID | Severity | Quadrant | Finding | Location |
|----|----------|----------|---------|----------|
| DOC-01 | 🔴 High | Reckless/Inadvertent | `fixedpoint_engine.nim` (273줄, CHC/PDR/Z3) 전용 spec 없음 | `src/verification/solver/` |
| DOC-02 | 🔴 High | Reckless/Inadvertent | `config.nims` — DI 프로토콜, compile-time 스위치, hooks 검증 전용 spec 없음 | `config.nims` |
| DOC-03 | 🟡 Medium | Prudent/Inadvertent | `solver_infrastructure_spec.md`가 CHC/PDR 엔진 미커버 | `docs/spec/` |
| DOC-04 | 🟡 Medium | Prudent/Inadvertent | `pbt_policy.md`가 삭제된 `fuzz_queries.nim` 5회 참조 | `docs/spec/pbt_policy.md` |
| DOC-05 | 🟡 Medium | Prudent/Inadvertent | 버전 불일치: nimble/lakefile v0.3.6 vs 커밋 "v0.3.7 baseline" | `axiom.nimble`, `lakefile.toml` |
| DOC-06 | 🟢 Low | Prudent/Inadvertent | AGENTS.md §1.3 SSOT 경로 모호성 (`certificate_manager.nim`) | `AGENTS.md` |
| DOC-07 | 🟢 Low | Prudent/Inadvertent | `axiom.toml` 상세 spec 없음 (architecture_v2.md에서만 간략 언급) | `axiom.toml` |
| DOC-08 | 🟢 Low | Prudent/Deliberate | stdlib .nim 파일 참조 일부 검증 불가 (stdlib vs 프로젝트) | `docs/spec/` |

**✅ 양호**: AGENTS.md 교차참조 15개 유효, docs/spec/ 38개 파일 모두 최근 5일 이내 갱신, README.md 7개 모두 존재.

---

## §6. Gate Infrastructure Debt (5 items)

| ID | Severity | Quadrant | Finding | Location |
|----|----------|----------|---------|----------|
| G-01 | 🔴 High | Reckless/Inadvertent | `test_v3_config.nim` — 4줄 stub (§0.8 위반) | `src/gate/test_v3_config.nim` |
| G-02 | 🟡 Medium | Prudent/Inadvertent | orphan runner 3개: `binary_freshness_gate`, `quality_gate_runner`, `unified_sentry` | `src/gate/runners/` |
| G-03 | 🟡 Medium | Prudent/Deliberate | 11개 gates source만 있고 bin/ 바이너리 없음 (compile-on-demand 추정) | `src/gate/runners/` |
| G-04 | 🟡 Medium | Prudent/Deliberate | 10개 gates bin/ 경로 등록 vs src/gate/runners/ 소재 — 불일치 | `gate_list.nim` |
| G-05 | 🟢 Low | Prudent/Inadvertent | `context_size_guard.nim`이 `src/gate/` 최상위에 있음 (runners/에 있어야 함) | `src/gate/` |

**이전 audit 대비 개선**: 2026-05-27 ghost gates (`nim_check_gate`, `gateway_test_gate`) 해결됨. 현재 `gate_list.nim`에 22개 gates 등록.

---

## §7. DEBT Registry Updates (DEBT#190~#207)

### 신규 등록 항목

| ID | Severity | Category | Title | Due |
|----|----------|----------|-------|-----|
| DEBT#190 | High | Directory / Git | tests/features/ 내 git-tracked ELF 바이너리 4개 (2.4MB 레포 부풀림) | 2026-06-14 |
| DEBT#191 | High | Code / Dead Code | `test_v3_config.nim` stub 파일 (§0.8 위반) | 2026-06-14 |
| DEBT#192 | High | Code / Debug | `echo "hi"` 디버그 잔재 in `global_symbol_graph_builder_part2.nim` | 2026-06-14 |
| DEBT#193 | High | Test / Regression | `when isMainModule` 안티패턴 32→51개 (+59% 회귀) — DEBT#166/#175 기준선 붕괴 | 2026-12-31 |
| DEBT#194 | High | Test / Stubs | `resource_limits_test.nim` + `gate_utils_test.nim` 100% trivial assertion | 2026-06-14 |
| DEBT#195 | High | Architecture / SSOT | `domain_types.nim` 중복 (core vs core/types) — DEBT#005 패턴 재발 | 2026-12-31 |
| DEBT#196 | High | Architecture / SSOT | `pipeline_core_types.nim` 계층 간 타입 분할 (core↔verification) | 2026-12-31 |
| DEBT#197 | High | Documentation | `fixedpoint_engine.nim` CHC/PDR/Z3 엔진 전용 spec 문서 없음 | 2026-12-31 |
| DEBT#198 | High | Documentation | `config.nims` DI 프로토콜/compile-time 스위치 전용 spec 없음 | 2026-12-31 |
| DEBT#199 | Medium | Architecture | stub/real 쌍 3개 (vault_index, proof_universe_lock, cert_writer) | 2026-12-31 |
| DEBT#200 | Medium | Architecture | backward-compat facade 23개 모듈 — import indirection debt | 2026-12-31 |
| DEBT#201 | Medium | Architecture | `session_parser_types` 7×12줄 과분할 | 2026-12-31 |
| DEBT#202 | Medium | Code | deprecated func 5개 (`computeAsi` overloads) in `metrics.nim` | 2026-12-31 |
| DEBT#203 | Medium | Documentation | `solver_infrastructure_spec.md` CHC/PDR 미커버 + `pbt_policy.md` stale ref | 2026-12-31 |
| DEBT#204 | Medium | Documentation | 버전 불일치 nimble/lakefile v0.3.6 vs v0.3.7 | 2026-06-14 |
| DEBT#205 | Medium | Gate Infrastructure | orphan runner 3개 (`binary_freshness_gate`, `quality_gate_runner`, `unified_sentry`) | 2026-12-31 |
| DEBT#206 | Low | Directory | 빈 디렉토리 7개 (top-level 3 + sub 4) | 2026-06-14 |
| DEBT#207 | Low | Code | TODO/FIXME 주석 4건 + tombstone comment 4건 | 2026-12-31 |

### 즉시 수정 가능 (Phase 4)

| ID | Action | Status |
|----|--------|--------|
| D-01 | `git rm "0:"` — 쓰레기 파일 제거 | ✅ 안전 확인 |
| D-02 | rm stale ELF 10개 (화이트리스트 방식) | ✅ 안전 검증 완료 (7단계) |
| D-05 | `rm -rf tools/__pycache__` | ✅ 안전 확인 |
| C-01/G-01 | `rm src/gate/test_v3_config.nim` | ✅ 안전 확인 |

---

## §8. Evidence Verification

```bash
# 증거 파일 존재 확인
ls -la verifications/*debt*2026_06_07*
# 6 files, ~79KB total

# DEBT_REGISTRY 신규 항목 확인
grep 'DEBT#19\|DEBT#20' docs/DEBT_REGISTRY.md

# config.nims spec gap 확인
grep -rl 'injectAxiomDependencies' docs/spec/ 2>/dev/null || echo "CONFIRMED GAP"

# CHC/PDR spec gap 확인
grep -rl 'fixedpoint_engine' docs/spec/ 2>/dev/null || echo "CONFIRMED GAP"
```
