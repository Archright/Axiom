# Axiom 기술부채 전수조사 보고서

**조사 일자**: 2026-05-30  
**조사 범위**: 전체 코드베이스 (`src/`, `tests/`, `scripts/`, `docs/`, `verifications/`, `logs/`, `bin/`)  
**조사 방법**: 기존 감사 보고서 15종 종합 + 소스코드 TODO/DEPRECATED/HACK 전수검색 + Gate 인프라 문서 분석 + `nimtry` 동적 검증  
**총 식별 항목**: 83건 (Critical 14 / High 24 / Medium 29 / Low 16)  

---

## Executive Summary

Axiom 프로젝트는 기능적으로 빠르게 진화하고 있으나, **검증 코어 미연결, 컴파일 불가 모듈 다수, ASI 1.0000 Hard Gate 정지, Gate 인프라 구현 공백, GUARDIAN.md 브랜치 간 SSOT divergence** 등 14개 Critical 기술부채가 즉시 조치를 요구합니다. 특히 `src/verification/`의 Z3Provider/Lean4Provider stub 상태는 "수학적 검증"이라는 프로젝트 핵심 가치를 훼손하고 있으며, `tests/gateway/`에 481개의 미구현 테스트가 존재하여 `ax prove` promotion rate ≥ 50% 달성이 사실상 불가능한 상태입니다.

**가장 시급한 5개 P0 항목**:
1. **컴파일 불가** — 5개 CLI 진입점 + 9개 테스트 파일 (cascade 실패)
2. **ASI 1.0000 Hard Gate SUSPENDED** — tautology/vacuity 경로가 Lean kernel을 통과
3. **Z3Provider / Lean4Provider stub** — SMT 검증 및 Lean proof replay 미연결
4. **`fusion` 미선언 의존성** — 빌드 실패 위험
5. **Gate 인프라 L3 cgroups 구현 공백** — 문서상 존재하나 코드상 부재

---

## 🔴 P0 — Critical (즉시 조치 필요)

| # | 카테고리 | 항목 | 근거 |
|---|---------|------|------|
| P0-1 | Compiler Hygiene | 5개 CLI 진입점(`basic_commands_cli.nim`, `asset_collector.nim`, `thought_dashboard.nim`, `gateway_constraint.nim`, `cross_validator.nim`) 및 9개 테스트 파일이 현재 **컴파일 불가**(exit=1). undeclared identifier, ambiguous call, missing import 등 cascade. | `technical_debt_comprehensive_audit_2026_05_26.md` §1 |
| P0-2 | Tautology / Vacuity | **ASI 1.0000 Hard Gate가 SUSPENDED** 상태. `smart_search.nim`(n=n 자기동등), `submit.nim`(True trivial fallback), `gateway.nim`((assert true) 주입) 등 3개 이상 경로에서 vacuous proof가 Lean 4 kernel을 통과하고 `verifiedKey`로 승격. 518개 `missing-loop-invariant` 경고가 ASI를 인플레이션. | `technical_debt_tautology_2026_05.md` 전체 |
| P0-3 | Critical Stubs | `provider_interface.nim`의 **Z3Provider** 및 **Lean4Provider**가 stub — `makeProver(pkZ3)`/`makeProver(pkLean4)`가 `solverUnknown` 반환. SMT 검증 및 Lean proof replay 실패. | `technical_debt_comprehensive_audit_2026_05_04.md` §8 |
| P0-4 | Dependency Health | `fusion` 패키지가 `src/gate/rule_patterns.nim`에서 사용되나 `axiom.nimble` 및 `nimble.lock`에 **미선언**. | `dependency_health_report.md` §2.4 |
| P0-5 | Architecture / SSOT | `src/gate/domain_types.nim`이 `src/core/domain_types.nim`의 Domain 타입을 **shadow copy**로 재정의. 두 정의가 발산 → fingerprint mismatch → ASI 저하. | `structural_audit_2026-05-29.md` §2.1 |
| P0-6 | Architecture / SoC | `src/core/gateway.nim`이 `verification/state_manager`를 직접 import — Domain→Infrastructure SoC 위반. `architecture_gate.nim`이 `isGrandfatheredException`으로 하드코드 면제. | `quality_gate_4p_audit_2026_05_20.md` §3 (LV-001) |
| P0-7 | Architecture / DIP | `src/core/provider_interface.nim`에서 `z3ExecPersistent`를 직접 호출 — DIP 위반. `isSolverDependencyOwner` 하드코드 면제 존재. | `quality_gate_4p_audit_2026_05_20.md` §3 (LV-002) |
| P0-8 | Gate Infrastructure | AGENTS.md §1.2 4-Layer Defense Stack의 **L3 cgroups v2**(`systemd-run --slice=axiom-gate`)가 `scripts/gate_hook.nim`에 **전혀 구현되지 않음**. 문서와 코드의 분리. | `docs/history/2026-05-28-layered-gate-concurrency-cap.md`, AGENTS.md §1.2 |
| P0-9 | Gate Infrastructure | **Multiplicative Parallelism** — L2 슬롯(4) × L1 작업수(8) × 게이트 내부 병렬 = 32+ 동시 작업자. pre-push 시 83개 프로세스가 28.8GB+6.8GB swap 점유 → OOM killer. | `docs/history/oom-*.md`, `verifications/gate_infrastructure_debt_audit.txt` |
| P0-10 | Code Complexity | `verifyCertificates` (`src/verification/analyzer.nim`) — **403줄, ACI 165, 14개 책임 영역**. 10단계 nesting, inline closure 2개, 10개 exit path. 기계적 리팩토링 불가능. | `aci_refactoring_residual_2026_05.md` §Heavy #1, `wave_z_automation_blockers.md` |
| P0-11 | Gate Infrastructure | Quality gate가 **구조적으로 손상** — 위반을 탐지하지 않고 무시하도록 프로그램됨. regex 기반 문자열 파싱(~950줄)이며 AST 기반이 아님. | `quality_gate_4p_audit_2026_05_20.md` 전체 |
| P0-12 | Test Coverage | 전체 소스 모듈 중 **42.3%만** 임포트 기준 테스트 보유. `src/core/solver/` 12개 파일 전무, `src/verification/analyzer/` 8개 stage 전무, `src/gate/` 44개 중 8개만 테스트(18%). 3개 placeholder, 23개 zero-assertion 테스트 파일. | `technical_debt_comprehensive_audit_2026_05_26.md` §4 |
| P0-13 | Code Complexity | `certificateStatusToProofEntryStatus` (`src/cli/report_cli.nim`) — **399줄**, 8× 임계치 초과. | `code_complexity_report.md` §2 |
| P0-14 | Structural / SSOT Divergence | **GUARDIAN.md 브랜치 간 SSOT divergence**. `main` 브랜치(`73af5524`)에서 GUARDIAN.md를 삭제하고 `docs/agents/core_rules.md`로 rename했으나, 현재 HEAD인 `core` 브랜치에서는 GUARDIAN.md가 여전히 존재하고 `docs/agents/core_rules.md`는 없음. AGENTS.md 참조도 브랜치별로 상이(`main`→`core_rules.md`, `core`→`GUARDIAN.md`). 더욱이 `core` 브랜치의 AGENTS.md에는 `main`에 존재하는 §0.7~0.9(Static First Enforcement, Business-Only Test Scope, No Stub Files)가 누락. `core`→`main` merge 시 정책 유실 또는 충돌 위험. | `git diff main..core -- GUARDIAN.md docs/agents/core_rules.md AGENTS.md` |

---

## 🟠 P1 — High (단기 해결 필요)

| # | 카테고리 | 항목 | 근거 |
|---|---------|------|------|
| P1-1 | Gate / SSOT | `gates.nim`(14개 우선순위 등록)과 `gate_hook.nim`(T0-T3 인라인 파이프라인)이 **듀얼 코드 패스**. 7개 활성 게이트가 `gates.nim`에 미등록. | `verifications/gate_infrastructure_debt_audit.txt`, `docs/history/2026_05_gate_hardening.md` |
| P1-2 | Process / Audit | **718개 unverified commits**. 특히 516개 MISSING_CONTEXT7 — 시스템/커널/드라이버 관련 변경 시 공식 문서 미참조. | `unverified_commits_audit.md` |
| P1-3 | Test Coverage | `tests/gateway/`에 **481개 미구현 테스트 TODO**. `orchestrator_feature_test.nim`(22), `ax_command_surface_feature_test.nim`(18), `architecture_gate_feature_test.nim`(18) 등. | 코드 TODO 전수검색 |
| P1-4 | Code Complexity | 500줄 초과 파일 **28개**. 상위 5: `axiom_api.nim`(1,408), `boundary_extractor.nim`(1,204), `lean_lsp.nim`(1,166), `tree_sitter_bridge.nim`(978), `gateway.nim`(918). | `technical_debt_comprehensive_audit_2026_05_26.md` §6 |
| P1-5 | Code Complexity | ACI >100인 **8개 heavy candidate** 미해결: `extractBoundaries`(129), `sanitizeLeanSource`(117), `saveHint`(112), `assemblePrimitiveProof`(110), `tryLeanstralSelfCorrection`(108), `extractPathConditions`(105), `analyzeVariableIntervalsAtLoopHeader`(103). | `aci_refactoring_residual_2026_05.md` |
| P1-6 | Compiler Hygiene | 전역 deprecated import 경고 — `std/cpuinfo`, `std/threadpool`, `std/locks`. `orchestrator.nim`이 `{.warning[Deprecated]: off.}`로 숨김. Nim 3.0 제거 시 치명적. | `tech_debt_audit_2026_05.md` §2.1 |
| P1-7 | Exception Handling | `src/core/` ~90개, `src/verification/` ~80개의 `try/except` 블록. GUARDIAN.md §4가 `Result[T,E]`만 요구하나 대거 위반. | `technical_debt_comprehensive_audit_2026_05_04.md` §3 |
| P1-8 | Exception Handling | 예외 핸들러 내부 **113~150+개 `discard` 문**으로 오류 침묵. `semantic_graph.nim`(15+), `lean_lsp.nim`(20+), `abstract_provider.nim`(12+). | `technical_debt_comprehensive_audit_2026_05_04.md` §3.2 |
| P1-9 | Purity / Effect | `src/verification/` 29개 모듈 중 22개가 `{.push raises: [].}` + `{.push noSideEffect.}` 미적용. | `technical_debt_comprehensive_audit_2026_05_04.md` §2.1 |
| P1-10 | Purity / Effect | `src/core/`에서 **13개 compiler-confirmed** pure `proc`이 `func`로 승격 가능하나 미변환. `src/verification/`에서는 **121개 estimated** pure proc 후보. | `technical_debt_comprehensive_audit_2026_05_04.md` §2.2 |
| P1-11 | Purity / Effect | `cast(noSideEffect)`로 compiler effect system 우회: `src/core/json_utils.nim`, `src/core/solver/z3_pool.nim`. | `technical_debt_comprehensive_audit_2026_05_04.md` §2.3 |
| P1-12 | Purity / Effect | `ref object`가 core/verification에 존재하여 deterministic destruction 파괴: `src/core/semantic_graph.nim` (`SemanticGraph`), `src/verification/lean_lsp.nim` (`LeanLspClient`). | `technical_debt_comprehensive_audit_2026_05_04.md` §2.4 |
| P1-13 | Architecture / SoC | `src/verification/`에 **5개의 gate 모듈**이 잘못 배치됨 (`gate_registry.nim`, `gate_rules.nim`, `gate_rules_architecture.nim`, `gate_rules_module_classifier.nim`, `gate_rules_normalization.nim`). | `structural_audit_2026-05-29.md` §2.3 |
| P1-14 | Architecture / SoC | `src/verification/proof_state_builder.nim` ↔ `src/gate/convergence_sidecar.nim` 간 **Infra↔Gate 순환 의존성**. | `structural_audit_2026-05-29.md` §2.2 |
| P1-15 | Architecture / SoC | `src/gate/runners/asi_hard_gate.nim`이 `cli/asi_cli` (Presentation)를 import. Gate는 read-only이며 Presentation에 의존 불가. | `technical_debt_comprehensive_audit_2026_05_26.md` §5 |
| P1-16 | DRY | **9개 cross-module** 중복 함수 쌍: `clampInt`/`clampProgressInt`, `declareSmtVars`/`declareSmtVarsFromExpr`, `compactWhitespace` 등. | `technical_debt_comprehensive_audit_2026_05_04.md` §5.1 |
| P1-17 | Language Ban | AGENTS.md §1.1 위반 — **7개 파일, 1,349줄**이 Nim으로 포팅 필요: Python 5개, Bash 2개. 추가로 `scripts/prepare-commit-msg`(Bash, 96줄), `scripts/gates/architecture-gate`(POSIX shell, 15줄). | `technical_debt_comprehensive_audit_2026_05_26.md` §3 |
| P1-18 | Stubs | `scripts/refresh_cli_binaries.nim` 내 3개 Windows stub — `acquireBuildMutex()`(무조건 true), `terminateMcpServerProcesses()`(no-op), `signBinaries()`(warning만). | `tech_debt_audit_2026_05.md` §1.1 |
| P1-19 | Gate / Env | `AXIOM_SKIP_HEAVY_TESTS=true`가 L2 dispatcher의 `putEnv`를 통해 자식 프로세스에 전달되지 않아 `external_cli_smoke`가 매 pre-commit 시 22초 전체 smoke test 실행. | `docs/history/2026-05-29-build-optimization.md` |
| P1-20 | Gate / Performance | `integrity-test`가 매 pre-commit 시 174개 gateway test를 내부적으로 실행하여 >60s 소요. AGENTS.md §2.7 pre-commit <10s 규정 위반. | `verifications/gate_infrastructure_debt_audit.txt` |
| P1-21 | Resource / Freeze | **CPU starvation → AMDGPU MODE2 reset** — 16코어 CPU가 gate 프로세스로 포화될 때 GPU driver fence 스레드 기아 → 디스플레이 블랙아웃. 사용자가 "OOM"으로 오인. | `docs/history/freeze-root-cause-evidence-2026-05-27.md` |
| P1-22 | Resource / OOM | 시스템 **SwapTotal=0**. 메모리 부족 시 OOM killer 즉시 작동. | `docs/history/oom-forensic-analysis-2026-05-28.md` |
| P1-23 | Resource / Memory | `pre-commit` 바이너리가 140MB(ORC+threads:on). 14개 `startProcess` 동시 실행 시 가상 메모리 1.96GB 즉시 커밋(fork() COW). | `docs/history/precommit_timeout_root_cause_2026-05-28.md` |
| P1-24 | Resource / Memory | Nim 2.0 ORC 공식 버그(GitHub #23361): malebolgia 기반 병렬 실행 시 스레드 풀 메모리 회수 실패. | `docs/history/malebolgia_fd_root_cause_analysis.md` |
| P1-25 | Gate / Timeout | L2 병렬 디스패처에 **게이트별 timeout 부재**. 느리거나 hung 게이트가 파이프라인 전체를 무한정 차단. | `verifications/gate_infrastructure_debt_audit.txt` |
| P1-26 | Documentation | 모듈 레벨 문서화율 **64%**(231/357), 심볼 문서화율 **44%**(1,124/2,514). `gate/` 0%, `verification/analyzer/` 0%, `translator/` 4%. | `technical_debt_comprehensive_audit_2026_05_26.md` §8 |
| P1-27 | Legacy APIs | **5개 deprecated public API**가 내부에서 live caller 보유: `nimTypeToLeanType`, `buildLeanQuery`, `translateNimTypeToLean`, `buildLeanBridge`, `buildLeanBridgeFromSource`. | `tech_debt_audit_2026_05.md` §2.2 |
| P1-28 | Legacy | **16개 legacy code path**가 replacement와 병존. `lean_skeleton.nim` Wave 15 fallback, `verified_axioms.nim` dual-registry, `intrinsic_filter.nim` 전체 모듈 legacy. | `tech_debt_audit_2026_05.md` §3.1 |
| P1-29 | Architecture / SoC | `src/core/` 내 10개 이상 파일에서 `readFile`/`writeFile`/`fileExists` 등 직접 I/O 호출. Domain 계층이므로 Infrastructure/CLI로 이동 필요. | `technical_debt_comprehensive_audit_2026_05_04.md` §4.1 |

---

## 🟡 P2 — Medium (중기 개선)

| # | 카테고리 | 항목 | 근거 |
|---|---------|------|------|
| P2-1 | Code Complexity | 50줄 초과 함수 **73개** 존재. | `technical_debt_comprehensive_audit_2026_05_26.md` §6 |
| P2-2 | Code Complexity | 과도한 nesting depth: `lean_skeleton.nim`(depth 38), `contract_ast_extractor.nim`(depth 32). | `code_complexity_report.md` §3 |
| P2-3 | Code Complexity | 높은 coupling: `src/cli/wf_state.nim`이 21개 모듈 import(fan-out 최고). 15개 파일이 14개 이상 모듈 import. | `technical_debt_comprehensive_audit_2026_05_26.md` §6 |
| P2-4 | Legacy / Deprecated | `src/core/metrics.nim`에 8개 deprecated ASI 계산 함수(`computeAsi`, `computeAxiomaticIntegrity`, `computeKernelRatio`, `computeCompositeAsi`, `computeSplitAsi`, `computeWeightedAsi`, `computeEntropyWeightedAsi`) 누적. | 코드 TODO 전수검색 |
| P2-5 | Legacy / Deprecated | `src/gate/nimtry/`에 5개 deprecated 파일: `core_rules.nim`, `cohesion_analyzer.nim`, `query_engine.nim`, `query_types.nim`, `taint_tracker.nim`. | 코드 TODO 전수검색 |
| P2-6 | Legacy / Deprecated | `src/core/tree_sitter_bridge.nim` — 모듈 전체 DEPRECATED. | 코드 TODO 전수검색 |
| P2-7 | Legacy / Deprecated | `src/gate/architecture_guard.nim` 및 `src/gate/runners/architecture_guard.nim` — DEPRECATED. | 코드 TODO 전수검색 |
| P2-8 | Workaround | `src/gate/macros/cohesion_enforce.nim`에 Nim 2.x type inference 버그 workaround(`..<` 대신 `while`) 2개. | 코드 TODO 전수검색 |
| P2-9 | Future Work | 향후 개선 TODO 6개: `heal_parsing.nim`(AxHealFlags 이관), `trusted/cbor.nim`(path restoration), `smt_reconstruction.lean`(sorryAx), `procedure_gate_test.nim`(통합테스트), `mcp_steps.nim`, `workflow_steps.nim`. | 코드 TODO 전수검색 |
| P2-10 | Architecture / SRP | Gate 코드가 SRP 체크 시 **15개 이상 하드코드 경로 면제**(`report_cli.nim`, `analyzer.nim`, `heal.nim`, `boundary_extractor.nim` 등). `allowed_imports.lock`에 미등록. | `quality_gate_4p_audit_2026_05_20.md` §3.3 |
| P2-11 | Architecture / FFI | 6개 모듈에서 전용 wrapper 밖에서 FFI 사용: `sync_utils.nim`, `orchestrator.nim`, `z3_pool.nim`, `orchestrator_types.nim`, `lean_lsp.nim`, `gate_rules.nim`. | `technical_debt_comprehensive_audit_2026_05_04.md` §4.2 |
| P2-12 | Lock / SSOT | `src/allowed_imports.lock` 형식 불량 — line 76에 `threadpool`만 단독 존재. 누락: `std/strtabs`, `std/unicode`, `malebolgia`, `Lake`. | `tech_debt_audit_2026_05.md` §2.4 |
| P2-13 | Lock / SSOT | `src/verification/.physically_impure_modules` 내 **19개 모듈 항목이 전부 중복**(각 2회 등장). | `tech_debt_audit_2026_05.md` §1.2 |
| P2-14 | Lock / SSOT | `architecture_policy.lock`에 **두 개의 `[surface_area]` 섹션** 중복. TOML 파서가 silently override 가능. | `docs/history/2026-05-28-technical-debt-remediation.md` |
| P2-15 | Lock / SSOT | `module_overrides` 섹션 누락 — 8개 모듈 오버라이드가 현재 lock 파일에 없음. `gateway.nim`(36 exports), `axiom_api.nim`(20 exports)이 `core=15` 한도 초과에도 통과. | `docs/history/2026-05-28-technical-debt-remediation.md` |
| P2-16 | Gate / Metric | `cohesion_enforce.nim`의 `computeCohesion`이 `variableRefs`가 비어 있으면 `normalizedAstFingerprint`(FNV-1a hash)로 fallback. hash 위에서 LCOM/TCC를 계산하는 것은 수학적으로 무의미. | `docs/history/2026-05-28-technical-debt-remediation.md` |
| P2-17 | Gate / SSOT | `ssot-taint` query가 366k+ false positive로 **비활성화(DISABLED)**. SSOT 위반이 탐지되지 않을 수 있음. | `docs/history/2026-05-28-technical-debt-remediation.md` |
| P2-18 | Build Optimization | `config.nims`가 매 `nim c` 호출 시 `all_gateway_runner`를 `gorgeEx`로 실행(~6.7s). 6개 타겟 시 총 ~40s 낭비. | `docs/history/2026-05-29-build-optimization.md` |
| P2-19 | Build Optimization | `main.nim`과 `ax.nim`이 99.5% 코드 공유에도 별도 바이너리로 컴파일. | `docs/history/2026-05-29-build-optimization.md` |
| P2-20 | Build Optimization | per-target nimcache isolation — 각 타겟이 격리된 nimcache를 사용하여 616/617개 공유 산출물을 중복 컴파일. | `docs/history/2026-05-29-build-optimization.md` |
| P2-21 | Build Optimization | `trackedSourceFiles()`가 `cli/main.nim` 대신 `src/cli/main.nim` 경로를 사용하여 소스 변경 감지 실패. | `docs/history/2026-05-29-build-optimization.md` |
| P2-22 | Gate / Performance | `topology_cache.json`이 **161MB**. gate 실행 중 로드 시 즉각 메모리 압력. 자동 제한/rotation 로직 부재. | `docs/history/2026-05-28-token-scheduler-oom-mitigation.md` |
| P2-23 | Structural Hygiene | Root directory clutter — `analyze_docs_final.py`, `run_nimcheck.sh`, `code_complexity_report.md` 등이 카테고리화되지 않은 위치에 존재. | `structural_audit_2026-05-29.md` §3.1 |
| P2-24 | Structural Hygiene | `src/` 내 미등록 디렉터리 — `engine/`, `frontend/`, `translator/`, `types/`, `metrics/`, `personas/`가 AGENTS.md §1.2 architecture table에 없음. `src/types/`는 `core/types/`와 중복. | `structural_audit_2026-05-29.md` §4.1 |
| P2-25 | Structural Hygiene | `scripts/` vs `bin/` vs `src/gate/` 혼란 — `scripts/gate_replay`(컴파일된 ELF), `scripts/gate_hook.nim`, `scripts/nim_check_gate.nim` 등이 잘못된 위치. `bin/nimtry_old`는 stale artifact. | `structural_audit_2026-05-29.md` §4.2 |
| P2-26 | Structural Hygiene | `tests/` root에 테스트 파일 10개가 직접 존재. 일부는 `tests/unit/`로 이동 필요, 일부는 `_test` suffix 누락. | `structural_audit_2026-05-29.md` §4.3 |
| P2-27 | Structural Hygiene | `src/.build_hash`, `src/allowed_imports.lock`이 소스 트리 내에 존재. `src/core/.physically_impure_modules`가 Domain 계층에 audit marker로 남아 있음. | `structural_audit_2026-05-29.md` §3.3 |
| P2-28 | Structural Hygiene | Evidence SSOT divergence — `verifications/`(16개 `.txt`)와 `docs/evidence/`가 별개로 존재. 형식 불일치(`.txt` vs `.md`). | `structural_audit_2026-05-29.md` §4.4 |
| P2-29 | DRY | `cli/commands/heal.nim` 내부에 **3× 동일 필터 루프**, **7× 동일 에러 핸들링 블록**, **4× 동일 telemetry 블록** 중복. | `technical_debt_comprehensive_audit_2026_05_04.md` §5.2 |

---

## 🟢 P3 — Low (장기 관리)

| # | 카테고리 | 항목 | 근거 |
|---|---------|------|------|
| P3-1 | Repository Hygiene | Tracked runtime artifact — `logs/proof_universe.lock`, `logs/axiom.db`, `logs/axiom_vault.idx`, `logs/*.cache.json`(6개) 등이 Git에 tracked. `.gitignore` 대상. | `structural_audit_2026-05-29.md` §5 |
| P3-2 | Repository Hygiene | `diff.diff`(898줄)가 프로젝트 root에 stale artifact로 남아있음. | `tech_debt_audit_2026_05.md` §3.3 |
| P3-3 | Repository Hygiene | 6개 stale binary — `bin/ax_test`, `bin/guardian_scanner`, `bin/inject_core_pragmas`, `tests/gateway/debug_asi*` 등. traceable `.nim` source 없음. | `technical_debt_comprehensive_audit_2026_05_04.md` §1.3 |
| P3-4 | Repository Hygiene | `scripts/deprecated/` 내 2개 Nim 파일 (`backfill_winning_strategies.nim`, `promote_green_to_verified_axiom.nim`) — unreferenced. | `structural_audit_2026-05-29.md` §4.2 |
| P3-5 | Repository Hygiene | Root-level `proof_universe.lock`이 `logs/proof_universe.lock`과 중복. | `structural_audit_2026-05-29.md` §3.1 |
| P3-6 | Repository Hygiene | `docs/false-positives.md`, `docs/known-limitations.md`가 `docs/spec/`이 아닌 `docs/` root에 존재. | `structural_audit_2026-05-29.md` §3.2 |
| P3-7 | Dead Code | `src/cli/wf_runners.nim:245-279` — 35줄짜리 `when false:` dead code 블록. CLI workflow command 등록 코드가 비활성화된 채 남아있음. | `technical_debt_comprehensive_audit_2026_05_26.md` §2 |
| P3-8 | Dead Code | 3개 placeholder 테스트 파일 (1줄짜리): `asi_ssot_unify_test.nim`, `cli_build_test.nim`, `reasoning_recorder_test.nim`. | `technical_debt_comprehensive_audit_2026_05_26.md` §4 |
| P3-9 | Dead Code | `ghost_update.nim` — **어디서도 import되지 않음**, dead code 가능성 높음. | `tech_debt_audit_2026_05.md` §4.2 |
| P3-10 | Dead Code | `unified_sentry` 바이너리가 `gates.nim`과 `gate_hook.nim` 어느 쪽에도 등록되지 않음. | `verifications/gate_infrastructure_debt_audit.txt` |
| P3-11 | Language / Platform | `ax.cmd` — Windows CMD 런처, 존재하지 않는 실행 파일 참조. | `technical_debt_comprehensive_audit_2026_05_04.md` §1.2 |
| P3-12 | Language / Platform | GitHub Actions workflow 파일들에 embedded Bash/PowerShell — `certificate-asi-gate.yml`, `os-compatibility-gate.yml`, `uap-integrity-gate.yml`, `windows-signed-release.yml`. | `technical_debt_comprehensive_audit_2026_05_04.md` §1.2 |
| P3-13 | Compiler Hygiene | `src/core/semantic_graph.nim`에 `std/times` unused import 존재. | `technical_debt_comprehensive_audit_2026_05_04.md` §6.1 |
| P3-14 | Compiler Hygiene | `XDeclaredButNotUsed` Hint가 error로 승격되지 않아 사용되지 않는 식별자가 코드베이스에 누적됨. | `docs/history/2026-05-28-technical-debt-remediation.md` |
| P3-15 | DRY | Hardcoded engine selection: `gateway.nim`, `certificate_cli.nim`, `pipeline_core_types.nim`에 `"z3"`, `"lean4-lsp"` 문자열 분기 하드코딩. | `technical_debt_comprehensive_audit_2026_05_04.md` §5.3 |
| P3-16 | DRY | JSON parsing / CLI fallback 패턴 중복: `parseJsonStringField`, manual JSON field validation, CLI-arg→file→stdin fallback 등. | `technical_debt_comprehensive_audit_2026_05_04.md` §5.4 |

---

## Category Summary Matrix

| 카테고리 | Critical | High | Medium | Low | 합계 |
|----------|----------|------|--------|-----|------|
| Compiler Hygiene | 1 | 1 | 0 | 2 | 4 |
| Architecture / SoC / DIP / SRP | 3 | 5 | 2 | 0 | 10 |
| Purity / Effect System | 0 | 4 | 0 | 0 | 4 |
| Exception / Error Handling | 0 | 2 | 0 | 0 | 2 |
| Test Coverage | 1 | 1 | 0 | 0 | 2 |
| Code Complexity / ACI | 3 | 2 | 3 | 0 | 8 |
| Tautology / Vacuity / ASI | 1 | 0 | 0 | 0 | 1 |
| Critical Stubs | 1 | 1 | 0 | 0 | 2 |
| DRY / Duplication | 0 | 1 | 1 | 2 | 4 |
| Dependency Health | 1 | 0 | 0 | 0 | 1 |
| Gate Infrastructure | 3 | 7 | 2 | 0 | 12 |
| Build Optimization | 0 | 0 | 4 | 0 | 4 |
| Language Ban / Platform | 0 | 1 | 0 | 2 | 3 |
| Documentation | 0 | 1 | 0 | 0 | 1 |
| Legacy / Deprecated | 0 | 2 | 7 | 0 | 9 |
| Structural / Repository Hygiene | 1 | 0 | 6 | 6 | 13 |
| Dead Code | 0 | 0 | 0 | 4 | 4 |
| Resource / OOM / Freeze | 0 | 5 | 0 | 0 | 5 |
| Process / Unverified Commits | 0 | 1 | 0 | 0 | 1 |
| **합계** | **14** | **24** | **29** | **16** | **83** |

---

## Recommended Roadmap

### Phase 0 — Firefighting (1주)
- **P0-1** 컴파일 불가 모듈 복구: `basic_commands_cli.nim`, `asset_collector.nim`, `gateway_constraint.nim` 등 undeclared identifier 해결
- **P0-3** Z3Provider/Lean4Provider stub 제거: 실제 Z3 bridge 및 Lean LSP 연결 구현 또는 최소한의 실패-safe 경로 확보
- **P0-4** `fusion` 패키지를 `axiom.nimble`에 명시적 선언
- **P0-8** L3 cgroups v2 `wrapWithCgroupsIfAvailable()` 실제 구현 (AGENTS.md 문서와 코드 일치)

### Phase 1 — Core Integrity (2~3주)
- **P0-2** ASI 1.0000 Hard Gate 재가동: Path A/B/C 차단, `missing-loop-invariant`를 `agError`로 승격
- **P0-5** `src/gate/domain_types.nim` shadow copy 제거 → `src/core/domain_types.nim` 단일 SSOT
- **P0-6** `src/core/gateway.nim`의 `verification/state_manager` 직접 import 제거 (facade 또는 event bus 도입)
- **P0-7** `provider_interface.nim` DIP 정리: `ProverInterface` 추상화 완성, `z3ExecPersistent` 직접 참조 제거
- **P0-9** Multiplicative parallelism 완화: pre-push `MaxConcurrentL2`를 4→2로 감소, Token scheduler `MemoryHigh=6G` soft throttle 검증
- **P0-10** `verifyCertificates` 403줄 God Function 수동 분할 (closure conversion 및 effect system 고려)

### Phase 2 — Gate Hardening (2~3주)
- **P0-11** Quality gate를 regex 기반에서 AST 기반으로 재작성 (또는 nimtry의 커버리지 확대)
- **P1-1** Gate Layer SSOT 통합: `gates.nim`과 `gate_hook.nim`의 듀얼 코드 패스 제거
- **P1-21~P1-24** 리소스 방어 스택 검증: cgroups enforcement gap, swap 0B 호스트 설정, ORC `-d:useMalloc` 전면 적용
- **P2-17** `ssot-taint` 비활성화 해소: distinct types + constructor pattern 기반 SSOT 검증 활성화

### Phase 3 — Test & Documentation (4~6주)
- **P1-3** `tests/gateway/` 481개 TODO stub → 실제 테스트 구현 (웨이브 단위로 점진적)
- **P0-12** `src/core/solver/` 및 `src/verification/analyzer/` 테스트 커버리지 0%→최소 50% 달성
- **P1-26** 문서화율: `gate/`, `verification/analyzer/`, `translator/`에 최소 모듈 레벨 docstring 작성
- **P1-2** unverified commits 중 MISSING_CONTEXT7 516개에 대해 retroactive 문서화 (핵심 시스템 변경만)

### Phase 4 — Refactoring & Cleanup (지속)
- **P1-4~P1-5** 500줄 초과 파일 및 ACI >100 함수 분할
- **P1-17** Python/Bash → Nim 포팅 (우선 `scripts/` 내 프로젝트 코드)
- **P1-29** `src/core/` 직접 I/O 호출을 Infrastructure/Presentation 계층으로 이동
- **P2-23~P2-28** Structural hygiene: root clutter 정리, `src/` 미등록 디렉터리 처리, evidence SSOT 통합
- **P3-1~P3-6** Repository hygiene: tracked runtime artifact `.gitignore` 처리, stale binary/artifact 제거

---

## Data Sources & Methodology

1. **기존 감사 보고서 종합** (Agent #1): `docs/reports/` 내 11개 기술부채/품질/복잡도 감사 보고서를 읽고 unresolved 항목만 추출. 중복 통합 수행.
2. **소스코드 마커 전수검색** (Agent #2): `src/`, `tests/`, `scripts/`에서 `TODO`, `FIXME`, `HACK`, `XXX`, `DEPRECATED`, `BROKEN`, `WORKAROUND`, `TEMP`를 `grep`으로 추출하여 563라인 → 520+ 실제 마커로 분류.
3. **Gate 인프라·빌드·검증 파이프라인 분석** (Agent #3): `verifications/gate_infrastructure_debt_audit.txt`, `docs/history/` 18개 파일, `docs/reports/wave_z_automation_blockers.md` 분석.
4. **동적 정적분석** (Direct): `bin/nimtry` 실행 결과 — **PASSED, no violations** (cache: 398 hits, 0 misses). 단, `ssot-taint` query는 DISABLED 상태이므로 모든 아키텍처 원칙을 커버하지는 않음.
5. **Git 브랜치 비교** (Direct): `git diff main..core`로 `main`과 `core` 브랜치 간 GUARDIAN.md / AGENTS.md divergence 확인.

---

## Disclaimer

- 본 보고서는 기존 감사 보고서(최신 2026-05-26) 및 소스코드 주석 분석을 기반으로 합니다. 일부 항목은 5월 26일 이후에 이미 해결되었을 수 있습니다.
- `nim check` 전체 실행은 본 조사에서 수행되지 않았습니다. P0-1의 "컴파일 불가"는 5월 26일 감사 시점의 데이터이며, 현재 시점에서는 일부가 해결되었을 수 있습니다. 즉시 확인이 권장됩니다.
- `bin/nimtry`의 "PASSED"는 현재 캐시/정책 범위 내 violations가 없음을 의미하며, 이는 일부 query(예: `ssot-taint`)가 비활성화되어 있기 때문일 수 있습니다.
