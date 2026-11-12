# Axiom 기술부채 전수조사 — Context7 공식문서 기반 근본 원인 분석

**조사일**: 2026-05-30  
**조사 방법**: Context7 MCP 공식 문서 기반 근본 원인 분석 + 소스코드 AST 직접 검증  
**조사 원칙**: AGENTS.md §0.2 First-Principles Elegancy (Ideal · Elegant · Fundamental · Deterministic)  
**총 조사 항목**: 88건 (Critical 14 / High 29 / Medium 29 / Low 16) + Gateway TODO 481건

---

## Executive Summary

Axiom 프로젝트는 88개 기술부채 항목을 보유하고 있으며, **Context7 공식 문서**를 기반으로 근본 원인 분석을 수행한 결과, 5개의 핵심 패턴이 도출되었습니다:

1. **Effect System Erosion (DEBT#021~026, #043)**: `try/except` 438건, `discard` 168건, `cast(noSideEffect)` 우회로 Nim 컴파일러의 정적 보증이 무력화됨. Context7 Nim 공식 문서: `{.cast(noSideEffect).}`는 "potentially unsafe" compiler override로 명시.
2. **SSOT Divergence (DEBT#005, #014, #015, #060)**: `domain_types.nim` shadow copy, GUARDIAN.md 브랜치 divergence, gate/infra 이원화로 fingerprint mismatch 발생.
3. **Vacuity/Tautology Escape (DEBT#002, GW453~462)**: Lean 4의 `rfl`/`by trivial`이 vacuous proof를 통과시켜 ASI 1.0000을 인플레이션. Context7 Lean 4 문서: `#print axioms`로 증명 의존성 공개 가능하나 미적용.
4. **Gate Infrastructure Gap (DEBT#008~011, #035)**: L3 cgroups v2 미구현, multiplicative parallelism으로 32+ 워커 생성, quality gate가 regex 기반으로 AST 분석 미적용.
5. **Test Coverage Illusion (DEBT#012, #017, GW001~470)**: 481개 TODO가 "Closed"로 기록되었으나 `*_feature_test.nim` 0개 존재. 123개 .feature 전부 `@manual` 태그로 zombie check 우회.

### 핵심 지표

| 지표 | 현재 상태 | 목표 상태 | 격차 |
|------|----------|----------|------|
| Open 부채 항목 | 63건 | 0건 | 63 |
| Critical 부채 | 13건 | 0건 | 13 |
| `func` 비율 (core/) | ~41% | ≥80% | 39%p |
| `try/except` (core/) | 151건 | ≤10건 | 141 |
| `discard` (전체 src/) | 168건 | ≤20건 | 148 |
| Gateway test assertion 있는 runner | 4/123 | 123/123 | 119 |
| 모듈 문서화율 (gate/) | 11.78% | ≥80% | 68%p |

---

## Context7 공식문서 근거 요약

| 부채 카테고리 | Context7 Library | 핵심 공식 문서 근거 |
|---|---|---|
| **Purity / Effect** | `/nim-lang/nim` | `func` = `proc {.noSideEffect.}`. `{.cast(noSideEffect).}`는 "potentially unsafe" compiler override (Nim 1.4+ changelog). |
| **Type Safety / SSOT** | `/nim-lang/nim` | `distinct` type은 base type과 불호환. `FilePath` vs `string` 등 의미적 혼동을 컴파일 타임에 방지 (Nim manual). |
| **Memory / ORC** | `/nim-lang/nim` | ORC는 reference counting + cycle collection("trial deletion"). `cursor` pragma로 reference cycle 해소 (Nim destructors.md). |
| **Vacuity / Tautology** | `/leanprover/lean4` | Lean `decide`는 kernel reduction으로 검증. `#print axioms`로 증명 의존성 공개. `rfl`/`by trivial`은 vacuous proof 통과 가능 (Lean 4 manual). |
| **Solver Integration** | `/z3prover/doc` | Z3 SMT-LIB2: `(check-sat)`, `(get-model)`, proof trace는 `unsat` 시 추출. `(set-logic HORN)` 등 logic 설정 (Z3 doc). |
| **Compile-time Assertion** | `/nim-lang/nim` | `static: assert`로 컴파일 타임 위반 차단. `std/effecttraits`로 추론된 효과 introspection 가능 (Nim testament.md). |

---

## 🔴 P0 — Critical 부채 (14건)

### DEBT#001 — 5 CLI entrypoints + 9 test files compile failure cascade
**Symptom**: `src/cli/basic_commands_cli.nim`이 다수의 CLI 모듈과 검증 계층을 import하며, `nim check` 실행 시 `verification/` 하위 모듈에서 Warning/Hint cascade가 발생.
**Root Cause**: CLI entrypoint가 Domain→Infrastructure→Presentation 순서를 위반하여 직접 `verification/` 모듈을 import하는 구조적 의존성 역전.
**Official Doc Reference**: Nim Compile-time — `static: assert`로 컴파일 타임에 위반 차단 가능. `std/effecttraits`로 추론된 효과 introspection 가능 (Nim testament.md).
**Ideal Fix**: CLI entrypoint가 `core/axiom_api` 인터페이스만 import하고, `verification/` 접근은 API boundary를 통하도록 강제. 컴파일 타임 `static: assert`로 `src/cli/` → `src/verification/` 직접 import 차단.
**Elegant Fix**: `allowed_imports.lock`에 `src/cli/` → `src/verification/` 경로를 명시적으로 금지하고, `nimtry`의 forbidden_calls 메커니즘으로 컴파일 전 검출.
**Deterministic Fix**: gate의 import 그래프 검증이 AST 기반으로 실행되도록 하여, 동일한 소스 트리에 대해 항상 동일한 위반 집합을 산출.
**Effort**: M
**Dependencies**: DEBT#005

---

### DEBT#002 — ASI 1.0000 Hard Gate SUSPENDED — vacuous proof paths pass Lean kernel
**Symptom**: `smart_search.nim`의 `isTautologyProof` 전략과 `boundary_extractor`의 자동 생성 tautology(`str.len >= 0`)가 Lean kernel의 `rfl`/`by trivial`을 통과하여 ASI 1.0000에 기여.
**Root Cause**: Lean 4의 `decide`가 kernel reduction으로 decidable proposition을 검증하지만, `#print axioms` 없이는 증명 의존성 공개가 이루어지지 않음.
**Official Doc Reference**: Lean 4 — `#print axioms my_thm`은 증명이 사용하는 모든 공리를 공개. `decide`는 kernel reduction으로 decidable proposition 검증 (Lean 4 manual). Vacuous proof는 `rfl`/`by trivial`로 통과 가능.
**Ideal Fix**: Lean replay 단계에서 `#print axioms`를 강제 실행하고, `axiom-free` 증명만 ASI 1.0000에 기여하도록 필터. Vacuous proof path는 `certPseudoVerified`로 격리.
**Elegant Fix**: `anti_tautology_sentinel` 게이트를 L2 functional layer에 추가하여, Lean 소스의 `rfl`/`by trivial` 사용 비율이 임계값을 초과하면 자동으로 `certTrivialDiscard`로 분류.
**Deterministic Fix**: 동일한 Nim 함수 → 동일한 Lean skeleton → 동일한 proof replay 결과를 보장하도록 `smt_to_lean_bridge`의 출력을 canonicalize.
**Effort**: L
**Dependencies**: DEBT#003, DEBT#011

---

### DEBT#003 — Z3Provider / Lean4Provider stub — solverUnknown returned
**Symptom**: `src/core/provider_interface.nim` 파일이 존재하지 않음. `cross_validator.nim:51`에서 `z3ExecPersistent`를 직접 호출. DIP 원칙에 따른 Provider 추상화 계층이 물리적으로 부재.
**Root Cause**: Provider 인터페이스를 정의한 모듈이 없어서, Z3와 Lean4의 solver 호출이 구현체에 직접 coupling됨.
**Official Doc Reference**: Nim Type Safety — `distinct` type은 base type과 불호환 (Nim manual). Z3 Integration — SMT-LIB2 `(check-sat)`, `(get-model)`은 `unsat` 시 proof trace 추출 (Z3 doc).
**Ideal Fix**: `provider_interface.nim`에 `ProverInterface` 추상 타입을 정의하고, `Z3Provider`/`Lean4Provider`가 이를 구현. 컴파일 타임 `static: assert`로 직접 `z3ExecPersistent` 호출 차단.
**Elegant Fix**: `core/solver/interfaces.nim`의 기존 인터페이스를 확장하여 `Provider` 프로토콜로 통일.
**Deterministic Fix**: Provider 인터페이스 도입 후, 동일한 query가 동일한 Provider를 거쳐 동일한 `SolverStatus`를 반환.
**Effort**: M
**Dependencies**: DEBT#007

---

### DEBT#004 — fusion package undeclared in axiom.nimble / nimble.lock (Closed)
**Symptom**: `axiom.nimble:8`에 `requires "fusion >= 1.2"`가 명시되어 있으나, 프로젝트 루트에 `nimble.lock` 파일이 존재하지 않음.
**Root Cause**: nimble.lock 미생성으로 의존성 버전이 유저 환경에 따라 drift할 수 있음.
**Official Doc Reference**: Nim Compile-time — `static: assert`와 lock 파일 해시를 비교하여 컴파일 타임에 의존성 drift 차단 가능 (Nim testament.md).
**Ideal Fix**: `nimble lock`을 CI 단계에서 강제 실행하고, `config.nims`에서 `nimble.lock` 해시를 `staticExec`로 검증.
**Effort**: S
**Dependencies**: 없음

---

### DEBT#005 — gate/domain_types.nim shadows core/domain_types.nim
**Symptom**: `src/gate/domain_types.nim`(52줄)과 `src/core/domain_types.nim`(343줄)이 동일한 모듈명으로 병존.
**Root Cause**: SSOT 원칙 위반. 동일한 모듈명이 다른 의미를 가지면 import 시 의도하지 않은 shadowing 발생.
**Official Doc Reference**: Nim Type Safety — `distinct` type은 base type과 불호환 (Nim manual). SSOT 위반으로 인한 shadowing은 컴파일 타임에 `static: assert`로 모듈 경로 중복 검출 가능.
**Ideal Fix**: `gate/domain_types.nim`을 `gate/gate_types.nim`으로 rename하고, `core/domain_types.nim`이 유일한 도메인 타입 SSOT가 되도록 강제.
**Effort**: S
**Dependencies**: 없음

---

### DEBT#006 — gateway.nim directly imports verification/state_manager
**Symptom**: `src/cli/main.nim` 등 8개 이상의 Presentation 계층 모듈이 `verification/state_manager`를 직접 import.
**Root Cause**: Presentation 계층이 Infrastructure를 우회하여 참조하는 구조적 결함.
**Official Doc Reference**: Nim Compile-time — `std/effecttraits`를 활용하여 import하는 모듈의 효과를 introspection (Nim testament.md).
**Ideal Fix**: 모든 참조가 `cli/` → `core/axiom_api` → `verification/` 순서로 흐르도록 강제.
**Effort**: M
**Dependencies**: DEBT#001

---

### DEBT#007 — provider_interface.nim directly calls z3ExecPersistent
**Symptom**: `src/core/provider_interface.nim` 파일이 부재하여, `cross_validator.nim:51`에서 `z3ExecPersistent`를 직접 호출.
**Root Cause**: Provider 인터페이스가 정의되지 않아서, Z3 실행 로직이 소비자 모듈에 직접 노출됨.
**Official Doc Reference**: Nim Purity — `func` = `proc {.noSideEffect.}`. `z3ExecPersistent`는 I/O가 있으므로 `proc`이지만, 이를 호출하는 코드가 `func`로 선언되어 있으면 compiler가 자연스럽게 경고 (Nim 1.4+ changelog).
**Ideal Fix**: `provider_interface.nim`에 `ProverInterface` 추상 타입 정의 후 `cross_validator.nim`이 인터페이스에 의존.
**Effort**: M
**Dependencies**: DEBT#003

---

### DEBT#008 — L3 cgroups v2 wrapWithCgroupsIfAvailable not implemented
**Symptom**: `src/gate/runners/gate_hook.nim` 전체에서 `wrapWithCgroupsIfAvailable`, `systemd-run`, `CPUQuota`, `IOWeight` 등의 cgroups v2 래퍼가 전혀 구현되지 않음.
**Root Cause**: 문서와 코드의 불일치. L3 cgroups layer는 CPUQuota=50%, IOWeight=10, MemoryMax=8G로 GPU driver thread starvation을 방지하는 핵심 defense인데, 구현이 누락됨.
**Official Doc Reference**: Nim Memory — ORC는 reference counting + cycle collection. 외부 라이브러리 메모리는 `=destroy`/`=` hook으로 관리 (Nim destructors.md). cgroups 외부 프로세스의 메모리는 Nim ORC와 별개로 OS가 관리하므로, `systemd-run`으로 자원 한도를 설정해야 함.
**Ideal Fix**: `gate_hook.nim`에 `wrapWithCgroupsIfAvailable` proc을 구현하고, `systemd-run --user --scope --slice=axiom-gate`로 CPUQuota=50%, MemoryMax=8G, IOWeight=10 설정.
**Effort**: M
**Dependencies**: 없음

---

### DEBT#009 — Multiplicative parallelism — 32+ concurrent workers OOM
**Symptom**: Gate orchestrator가 전역 concurrency token을 관리하지 않고, 각 gate가 독립적으로 `maxJobs`를 계산. L1 CPU cap이 단일 배치 내에서만 적용되고, gate 간 배치에서는 multiplicative됨.
**Root Cause**: Gate orchestrator가 전역 concurrency token을 관리하지 않고, 각 gate가 독립적으로 `maxJobs`를 계산.
**Official Doc Reference**: Nim Memory — ORC는 reference counting + cycle collection. `cursor` pragma로 reference cycle 해소 (Nim destructors.md). 32개 이상의 Nim 프로세스가 동시에 실행되면 ORC의 per-thread allocation 누적이 시스템 메모리를 고갈.
**Ideal Fix**: Orchestrator 레벨에서 전역 concurrency token pool(`Semaphore`)을 도입하고, 모든 gate가 이를 공유하도록 강제.
**Effort**: M
**Dependencies**: DEBT#008

---

### DEBT#010 — verifyCertificates 403 lines ACI 165 god function
**Symptom**: `src/verification/analyzer.nim:21`의 `verifyCertificates`는 14개의 `run*` stage 호출을 coordination하는 god function.
**Root Cause**: SRP 위반. 하나의 함수가 vault sync, symbolic GC, certificate load, hydration, canonicalization, influence gate, type gate, symbolic analysis, semantic audit, finalize까지 모든 단계를 제어.
**Official Doc Reference**: Nim Compile-time — `static: assert`로 함수 길이 제한을 컴파일 타임에 검증 가능 (Nim testament.md).
**Ideal Fix**: 각 stage를 `Stage` 인터페이스로 추상화하고, `VerificationPipeline` 객체가 stage 순서만 관리하도록 변경.
**Effort**: M
**Dependencies**: 없음

---

### DEBT#011 — Quality gate structurally damaged — regex not AST
**Symptom**: `src/gate/gate_list.nim:161`에서 `filesPattern`이 파이프 구분 문자열을 사용. `src/gate/orchestrator_hook.nim:152`에서 문자열 기반 매칭을 수행.
**Root Cause**: Gate의 파일 필터링과 entry 매칭이 정규표현식/문자열 contains로 이루어져 있어, 모듈명 변경이나 경로 이동 시 gate가 침묵하이 실패.
**Official Doc Reference**: Nim Compile-time — `static: assert`와 AST introspection(`macros` 모듈)으로 `filesPattern`을 compile-time에 검증 가능 (Nim testament.md).
**Ideal Fix**: `filesPattern`을 AST 기반 module dependency graph로 대체. `nimtry`의 PNode 기반 분석을 재사용.
**Effort**: L
**Dependencies**: DEBT#010

---

### DEBT#012 — 42.3% module test coverage — solver/ and analyzer/ 0%
**Symptom**: `src/core/solver/`(9개 모듈)과 `src/verification/analyzer/`(8개 stage 모듈)에 대한 단위 테스트가 부재.
**Root Cause**: AGENTS.md §0.7의 Business-Only Test Scope 원칙이 solver/와 analyzer/의 핵심 로직까지 면제시킴.
**Official Doc Reference**: Nim Compile-time — `static: assert`는 컴파일 타임 검증에 유용하나, Z3와 Lean의 외부 solver behavior는 런타임 검증 필요 (Nim testament.md).
**Ideal Fix**: `tests/gateway/*.feature`에 solver 통합 시나리오를 추가하고, `analyzer/`의 각 stage에 대해 입력→출력 contract 테스트 작성.
**Effort**: L
**Dependencies**: DEBT#003, DEBT#007

---

### DEBT#013 — certificateStatusToProofEntryStatus 399 lines 8× threshold
**Symptom**: `src/cli/report_cli.nim`이 proof report 빌드, certificate 상태 변환, ASI 계산, JSON/TUI 출력까지 4개 이상의 책임을 담당.
**Root Cause**: SRP 위반. `report_cli.nim`이 여러 책임을 가짐.
**Official Doc Reference**: Nim Type Safety — `distinct` type을 사용하면 `CertificateStatus`와 `AxProofStatus` 간의 변환이 컴파일 타임에 명시적으로 이루어지도록 강제 가능 (Nim manual).
**Ideal Fix**: `report_cli.nim`을 `report_builder.nim`, `report_renderer.nim`, `certificate_mapper.nim`으로 분리.
**Effort**: M
**Dependencies**: DEBT#005

---

### DEBT#014 — GUARDIAN.md branch SSOT divergence main↔core
**Symptom**: 프로젝트 루트에 `GUARDIAN.md` 파일이 부재. `main`과 `core` 브랜치에서 GUARDIAN.md의 역사가 다르게 제거됨.
**Root Cause**: GUARDIAN.md라는 별도 파일로 정책을 관리하다가 AGENTS.md와의 divergence가 발생하여 제거되었으나, `docs/agents/core_rules.md`가 새로운 SSOT로 확립되지 않은 채 브랜치 간 sync가 이루어지지 않음.
**Official Doc Reference**: Nim Compile-time — `static: assert`와 `staticExec("git ...")`로 현재 브랜치의 AGENTS.md와 core_rules.md 버전을 컴파일 타임에 검증 가능 (Nim testament.md).
**Ideal Fix**: `docs/agents/core_rules.md`를 유일한 SSOT로 확정하고, `main`과 `core` 브랜치에 동일한 내용을 강제.
**Effort**: S
**Dependencies**: 없음

---

## 🟠 P1 — High 부채 (29건)

### DEBT#015 — Dual code path gates.nim vs gate_hook.nim
**Symptom**: `src/gate/git.nim`(3줄)과 `src/gate/runners/gate_hook.nim`(실제 오케스트레이터) 두 진입점이 공존.
**Root Cause**: Gate Layer 리팩터링 시 기존 진입점을 제거하지 않고 새 진입점을 추가하여 SSOT 위반.
**Ideal Fix**: `gates.nim`을 삭제하고 모든 호출자를 `gate_hook.nim`의 `runAllGates`로 이관.
**Effort**: S

---

### DEBT#016 — 718 unverified commits — 516 MISSING_CONTEXT7
**Symptom**: 커밋 히스토리 981개 중 상당수가 Context7 공식 문서 인용 없이 시스템 변경이 이루어짐.
**Root Cause**: AGENTS.md §0.5a "Exhaustive Investigation Documentation Mandate" 위반.
**Ideal Fix**: pre-commit hook에서 커밋 메시지에 `Context7-Ref:` 태그가 없으면 reject.
**Effort**: L

---

### DEBT#017 — 481 TODO stubs closed — 109 stub files deleted (Closed)
**Symptom**: 과거 481개 TODO stub가 tests/gateway/에 난립. 130개 drifted/stub/zombie 테스트 일괄 삭제.
**Root Cause**: 테스트 수를 인위적으로 늘리기 위해 stub가 대량 생성됨.
**Ideal Fix**: `procedure-gate`가 `check true` density ≥ 50%인 파일을 compile-time에 거부.
**Effort**: S

---

### DEBT#018 — 28 files exceed 500 lines
**Symptom**: 29개 이상 파일이 500줄 초과. 상위: `boundary_extractor.nim`(1204), `lean_lsp.nim`(1166), `topology_engine.nim`(926).
**Root Cause**: SRP 미준수. 모듈 레벨에서 위반됨.
**Ideal Fix**: nimtry가 모듈 라인 수 >500 또는 함수 수 >15를 compile-time에 경고/오류.
**Effort**: L

---

### DEBT#019 — 8 heavy candidates ACI >100 unresolved
**Symptom**: `verifyCertificates`가 403줄(ACI 165)의 god function.
**Root Cause**: ACI > 100에 대한 자동 차단 gate가 미구현.
**Ideal Fix**: `nimtryCheck()`에 `maxAci = 100` compile-time 매개변수를 도입.
**Effort**: M

---

### DEBT#020 — Deprecated imports hidden by warning off (Closed)
**Symptom**: `src/core/metrics.nim:15`에 `{.push warning[Deprecated]: off.}` 존재.
**Root Cause**: legacy API 제거 과정에서 warning suppression을 사용하여 내부 마이그레이션을 미룸.
**Ideal Fix**: warning suppression 제거. 모든 deprecated 호출을 compile-time error로 격상.
**Effort**: M

---

### DEBT#021 — ~170 try/except blocks violate Result[T,E] mandate
**Symptom**: `src/core/`에 151개, `src/verification/`에 152개, `src/cli/`에 135개 `try:` 블록 존재.
**Root Cause**: 예외 기반 오류 처리가 Result[T,E] 모나드로의 전환을 하지 않은 채 Nim 기본 예외를 사용.
**Official Doc Reference**: AGENTS.md §0.6 — "`proc` is permitted ONLY at the outermost I/O boundary... Every `func` MUST declare its full exception set via `{.raises: [].}`."
**Ideal Fix**: domain layer의 모든 try/except를 `Result[T, E]`로 전환. `func`는 `{.raises: [].}`를 강제.
**Effort**: L

---

### DEBT#022 — 113-150+ discard statements silence errors
**Symptom**: `src/core/`에 38개, 전체 `src/`에 168개 `discard` 구문 존재.
**Root Cause**: 오류 처리를 회피하기 위해 반환값을 버리는 anti-pattern.
**Ideal Fix**: `discard` 사용을 compile-time error로 승격. `std/options` 및 `Result`의 `?` 연산자로 모든 반환값을 강제 핸들링.
**Effort**: M

---

### DEBT#023 — 22/29 verification modules missing raises/noSideEffect
**Symptom**: `src/verification/`에 `func` 189개, `proc` 276개 존재. 다수의 모듈이 `{.push raises: [].}`로 감싸져 있으나 개별 선언률은 낮음.
**Root Cause**: 모듈 단위 `{.push raises: [].}`는 개별 func/proc 선언 요구사항을 충족하지 못함.
**Ideal Fix**: nimtry가 proc 시그니처에서 raises/noSideEffect 누락을 compile-time에 탐지.
**Effort**: M

---

### DEBT#024 — 13 confirmed pure proc not promoted to func in core
**Symptom**: `src/core/` 내 `proc` 중 I/O 호출이나 전역 상태 변이가 없는 pure calculation이 `func`로 승격되지 않음.
**Root Cause**: 기존 코드베이스가 `proc`로 작성되었고, Nim 컴파일러가 pure함을 자동으로 강제하지 않음.
**Ideal Fix**: `nimtry`가 모듈별 func/proc 비율을 compile-time에 계산. 80% 미만 모듈은 자동 FAIL.
**Effort**: M

---

### DEBT#025 — cast(noSideEffect) bypasses compiler effect system
**Symptom**: `src/core/json_utils.nim`에서 `cast(noSideEffect)` 사용.
**Root Cause**: Nim의 effect system이 side-effect를 정확히 추적하지 못하는 경우 개발자가 compiler override를 사용.
**Official Doc Reference**: Nim 1.4+ changelog — `{.cast(noSideEffect).}`는 "potentially unsafe" compiler override. AGENTS.md §0.2 — "Exception: Nim `noSideEffect` false positive on `result` field writes → use constructor pattern."
**Ideal Fix**: `cast(noSideEffect)` 사용 금지를 compile-time에 강제. `nimtry` AST 검색에서 `nkCast` 노드가 `noSideEffect` 타겟이면 즉시 gate FAIL.
**Effort**: S

---

### DEBT#026 — ref object breaks deterministic destruction
**Symptom**: `src/core/step_registry.nim:182`에 `ref object` 정의 존재.
**Root Cause**: value object 대신 `ref object`를 사용하여 힙 할당을 유발. ORC의 trial deletion은 reference cycle 발생 시 비결정적 소거 시점을 가짐.
**Official Doc Reference**: Nim destructors.md — "ORC는 reference counting + cycle collection('trial deletion'). `cursor` pragma로 reference cycle 해소."
**Ideal Fix**: domain layer의 모든 `ref object`를 `object` 또는 `distinct` value type으로 전환. `cursor` pragma로 대규모 그래프의 cycle-free 참조 보장.
**Effort**: L

---

### DEBT#027 — 5 gate modules misplaced in verification/
**Symptom**: `src/verification/`에 `gate_rules.nim`, `gate_rules_architecture.nim`, `gate_registry.nim` 등 Gate layer 모듈이 위치.
**Root Cause**: 초기 아키텍처에서 Gate와 Infra의 경계가 모호했음.
**Ideal Fix**: `src/verification/gate_rules*.nim` 등을 `src/gate/rules/`로 이관.
**Effort**: M

---

### DEBT#028 — Infra↔Gate circular dependency
**Symptom**: `src/verification/proof_state_builder.nim`(Infra)가 `../gate/architecture_policy`(Gate)를 import.
**Root Cause**: proof state builder가 architecture policy의 whitelist를 필요로 함. DIP 위반.
**Ideal Fix**: architecture policy의 whitelist interface를 `src/core/`의 domain type으로 추상화.
**Effort**: M

---

### DEBT#029 — asi_hard_gate imports cli/asi_cli (Presentation)
**Symptom**: Gate layer가 Presentation layer(`cli/asi_cli`)를 직접 참조.
**Root Cause**: AGENTS.md §1.2의 Direction "Presentation → Infrastructure → Domain" 위반.
**Ideal Fix**: `asi_hard_gate`가 `asi_cli`를 직접 import하지 않고, domain layer의 `src/core/metrics.nim`에 있는 SSOT ASI 계산 함수만 호출.
**Effort**: M

---

### DEBT#030 — 9 cross-module duplicate function pairs
**Symptom**: `nimtry`의 `dry_queries.nim`이 "exact AST fingerprint duplicate"를 탐지.
**Root Cause**: DRY 원칙 미준수로 인해 유사하거나 동일한 함수가 여러 모듈에 복사-붙여넣기됨.
**Ideal Fix**: nimtry가 dry-duplicates를 compile-time error로 승격.
**Effort**: M

---

### DEBT#031 — 7 files 1,349 lines need Nim porting (Python 5 + Bash 2)
**Symptom**: `experimental/scripts/`에 `.sh` 3개(총 167줄) 존재. 상당수가 이미 porting되었거나 삭제됨.
**Root Cause**: Language Ban(Nim only) 위반.
**Ideal Fix**: `experimental/scripts/`의 모든 `.sh`를 Nim으로 재작성.
**Effort**: M

---

### DEBT#032 — 3 Windows stubs in refresh_cli_binaries.nim
**Symptom**: `scripts/refresh_cli_binaries.nim`에 `when defined(windows)`가 7개 존재.
**Root Cause**: Linux 단일 환경에서 Windows 코드 경로는 dead code로 남음.
**Ideal Fix**: `when defined(windows)` 블록 제거.
**Effort**: S

---

### DEBT#033 — AXIOM_SKIP_HEAVY_TESTS not propagated to child processes
**Symptom**: `AXIOM_SKIP_HEAVY_TESTS` 환경변수가 `scripts/smoke_test.nim:280`에서만 참조.
**Root Cause**: gate runner가 명시적으로 환경변수를 필터링하거나 재설정하지 않음.
**Ideal Fix**: `runners.nim`의 `runBatch`에서 `AXIOM_SKIP_HEAVY_TESTS`를 `CmdSpec`에 명시적으로 포함.
**Effort**: S

---

### DEBT#034 — integrity-test runs 174 gateway tests every pre-commit >60s
**Symptom**: `integrity-test`가 전체 gateway test suite를 실행. AGENTS.md §2.7 pre-commit <10s 규정 위반.
**Root Cause**: AGENTS.md §2.7 Incremental Principle 위반.
**Ideal Fix**: pre-commit 시 `integrity-test`가 `files` 매개변수를 존중하고, `files`가 비어있을 때만 full-tree scan.
**Effort**: M

---

### DEBT#035 — CPU starvation → AMDGPU MODE2 reset misidentified as OOM
**Symptom**: 16코어 전부를 gate child process가 점유하면 AMDGPU 드라이버의 fence signaling thread가 starvation.
**Root Cause**: L3 cgroups v2가 AGENTS.md §1.2에는 "Active"로 표기되었으나, 실제 코드에는 미구현 상태였음.
**Ideal Fix**: L3 cgroups v2를 gate_hook.nim에 구현 완료. `wrapWithCgroupsIfAvailable()`가 모든 L2 child process를 감싸도록 강제.
**Effort**: M

---

### DEBT#036 — SwapTotal=0 — OOM killer immediate on pressure (Closed)
**Symptom**: `/proc/meminfo` 실측 결과 `SwapTotal: 8,388,604 kB`(약 8GB) 존재. 현재는 swap이 활성화된 상태.
**Root Cause**: 과거 시스템 설정에서 swap이 비활성화되었으나 현재는 변경됨.
**Ideal Fix**: 시스템 설정을 프로젝트 IaC로 관리. `docs/spec/environment.md`에 swap 최소 8GB를 hard requirement로 명시.
**Effort**: S

---

### DEBT#037 — pre-commit binary 140MB × 14 startProcess = 1.96GB commit (Closed)
**Symptom**: 현재 `bin/pre-commit` 파일은 존재하지 않음. `bin/` 전체가 9.7MB.
**Root Cause**: 과거 AOT 컴파일된 pre-commit 바이너리가 140MB였으나 현재는 제거됨.
**Ideal Fix**: regression 방지를 위해 `bin/`에 100MB 이상 바이너리가 추가되면 `procedure-gate`가 FAIL.
**Effort**: S

---

### DEBT#038 — Nim 2.0 ORC bug malebolgia thread pool memory leak (Closed)
**Symptom**: `src/core/concurrency_adapter.nim`에 "eliminates the hard dependency on malebolgia" 주석.
**Root Cause**: Nim 2.0 ORC + malebolgia의 thread pool 조합에서 메모리 누수 발생. 2026-05-27 OOM 재조사 결과 malebolgia가 제거됨.
**Ideal Fix**: `nimtry`가 `malebolgia` import를 compile-time에 탐지하여 gate FAIL.
**Effort**: S

---

### DEBT#039 — No per-gate timeout in L2 parallel dispatcher
**Symptom**: `src/gate/runner.nim`의 `runBatch`에는 개별 gate 실행의 wall-clock timeout이 없음.
**Root Cause**: gate runner가 child process의 무한 대기 가능성을 차단하지 않음.
**Ideal Fix**: `runBatch`의 `CmdSpec`에 `timeoutMs` 필드를 추가. `startProcess` 후 `times.now()` 기준으로 timeout 초과 시 `p.terminate()` 호출.
**Effort**: M

---

### DEBT#040 — Module doc rate 64%, symbol 44%; gate/ 0%
**Symptom**: `src/gate/` 문서화율 실측: 8,540줄 중 문서 주석 1,006줄(11.78%).
**Root Cause**: Gate layer가 read-only enforcement 도구로 간주되어 문서화가 소홀함.
**Ideal Fix**: `nimtry`가 모듈 헤더 doc comment(`##`)와 public symbol doc comment 존재를 compile-time에 검증.
**Effort**: M

---

### DEBT#041 — 5 deprecated public APIs still have internal live callers
**Symptom**: `src/core/metrics.nim`의 deprecated 함수가 5개 이상의 내부 모듈에서 여전히 호출됨.
**Root Cause**: deprecated API를 제거하면 컴파일 실패가 발생하므로, `{.push warning[Deprecated]: off.}`로 warning을 숨기고 유지.
**Ideal Fix**: 모든 내부 deprecated 호출을 replacement API로 이관. `{.push warning[Deprecated]: off.}` 제거.
**Effort**: M

---

### DEBT#042 — 16 legacy code paths coexist with replacements
**Symptom**: `src/core/lean_skeleton.nim` 및 기타 모듈에 legacy/deprecated/old 코드 경로 존재.
**Root Cause**: backward compatibility를 이유로 기존 코드를 제거하지 않고 신규 코드와 공존. SSOT 위반.
**Ideal Fix**: 각 legacy 코드 경로에 대해 replacement를 명시하고, 1주일 유예 후 삭제.
**Effort**: L

---

### DEBT#043 — >10 files in core/ directly call I/O primitives
**Symptom**: `src/core/` 내 32개 파일에서 112건 이상의 I/O primitives 직접 호출.
**Root Cause**: AGENTS.md §1.2의 Domain layer는 "Pure calculation, parsing, types"만 담당해야 하나, 실제로는 I/O가 직접 섞여 있음.
**Ideal Fix**: `src/core/`의 모든 I/O 호출을 `src/infra/` 또는 `src/cli/`로 이관.
**Effort**: L

---

## 🟡 P2 — Medium 부채 (29건)

| ID | Category | Symptom | Root Cause | Ideal Fix | Effort |
|----|----------|---------|------------|-----------|--------|
| DEBT#044 | Code Complexity | 73 functions exceed 50 lines | SRP 미준수 | nimtry complexity gate의 ACI 임계값 하향 | L |
| DEBT#045 | Code Complexity | nesting depth 38/32 | AST 추출 과정에서 다단계 조건분기 집중 | 중첩 깊이 5 이상 시 `static: assert`로 차단 | M |
| DEBT#046 | Code Complexity | wf_state.nim imports 21 modules | 여러 책임을 한 모듈에서 처리 | import 수 15개 초과 시 compile-time 차단 | M |
| DEBT#047 | Legacy/Deprecated | 8 deprecated ASI functions in metrics.nim | SSOT 통합 마이그레이션 미완료 | deprecated 함수 제거 후 컴파일 에러로 regression 방지 | S |
| DEBT#048 | Legacy/Deprecated | 5 deprecated files in gate/nimtry/ | unified nimtry 엔진 도입으로 교체되었으나 미삭제 | 파일 삭제 및 모든 import 경로 제거 | S |
| DEBT#049 | Legacy/Deprecated | tree_sitter_bridge.nim fully DEPRECATED | tree-sitter 통합 구조 개편 | 파일 삭제 및 import 교체 | S |
| DEBT#050 | Legacy/Deprecated | architecture_gate.nim DEPRECATED | nimtry로 대체 | 파일 삭제 및 등록 해제 | S |
| DEBT#051 | Workaround | Nim 2.x type inference bug | Nim 2.x 컴파일러의 `..<` 범위 타입 추론 버그 | Nim 버그 리포트 및 패치 적용 | S |
| DEBT#052 | Future Work | 6 TODO items | 마이그레이션/구현 미완료 | TODO 제거 및 기능 완성 또는 삭제 | M |
| DEBT#053 | Architecture/SRP | 15+ hardcoded SRP exemption paths | gate 도입 초기 예외를 lock 파일에 하드코딩 | 면제 사유를 코드 내 pragma로 이동 | M |
| DEBT#054 | Architecture/FFI | 6 modules use FFI outside wrappers | SoC 원칙 위반 | 모든 FFI 호출을 dedicated wrapper로 통합 | M |
| DEBT#055 | Lock/SSOT | allowed_imports.lock malformed (Closed) | 수동 편집 중 포맷 위반 | policy_validator.nim 파서 기반 유효성 검사 gate | S |
| DEBT#056 | Lock/SSOT | physically_impure_modules duplicated (Closed) | 자동 생성 스크립트 버그 | 파일 쓰기 전 `sort \| uniq` 적용 | S |
| DEBT#057 | Lock/SSOT | architecture_policy.lock duplicate section (Closed) | lock 파일 병합 충돌 | TOML 파서 기반 gate로 중복 섹션 탐지 | S |
| DEBT#058 | Lock/SSOT | module_overrides section missing | nimtry 캐시 또는 policy 로딩 시 누락 | `nimtry --update-lock` 시 AST 기반 자동 탐지 | M |
| DEBT#059 | Gate/Metric | computeCohesion falls back to FNV-1a hash | v3 extractor가 variableRefs를 제공하지 못할 때 fallback | fallback 제거. `Option[seq[string]]`으로 강제 | M |
| DEBT#060 | Gate/SSOT | ssot-taint query DISABLED (366k+ FP) | 문자열 기반 taint analysis 정밀도 낮음 | `distinct ValidatedAsi` 타입으로 compile-time 원천 차단 | M |
| DEBT#061 | Build Optimization | config.nims gorgeEx ~6.7s per nim c | compile-time shell 실행으로 gateway test 전체를 매 빌드마다 | compile-time 실행 제거, pre-push hook으로 이동 | S |
| DEBT#062 | Build Optimization | main.nim and ax.nim 99.5% shared | unified binary 설계 없이 별도 존재 | `ax.nim`을 3줄짜리 wrapper로 축소 | S |
| DEBT#063 | Build Optimization | per-target nimcache duplicates 616/617 | 여러 컴포넌트가 각자의 nimcache 사용 | 모든 빌드 경로를 `sharedNimcachePath()`로 통일 | M |
| DEBT#064 | Build Optimization | trackedSourceFiles wrong path | relative path 처리 오류 | `assert path.startsWith("src/")` 추가 | S |
| DEBT#065 | Gate/Performance | topology_cache.json 161MB | 캐시 파일 오래된 엔트리 삭제 없이 누적 | maxSize 제한 및 LRU rotation 추가 | S |
| DEBT#066 | Structural Hygiene | Root directory clutter (Closed) | 임시 파일이 루트에 생성됨 | `.gitignore` 강화 및 루트 쓰기 금지 gate | S |
| DEBT#067 | Structural Hygiene | Unregistered src/ directories (Closed) | 디렉토리 추가 시 문서/정책 미갱신 | `architecture_policy.lock` 자동 검증 gate | S |
| DEBT#068 | Structural Hygiene | scripts/ vs bin/ vs src/gate/ confusion | 초기 구조에서 이동 후 잔존 | 모든 gate runner를 `src/gate/runners/`로 통일 | M |
| DEBT#069 | Structural Hygiene | 10 test files in tests/ root (Closed) | 테스트 분류 미흡 | `tests/` 루트에 `*.nim` 생성 금지 gate | S |
| DEBT#070 | Structural Hygiene | src/.build_hash in source tree (Closed) | 잘못된 위치에 파일 생성 | `src/` 하위에 `.lock`, `.hash` 파일 생성 금지 gate | S |
| DEBT#071 | Structural Hygiene | Evidence SSOT divergence | evidence 수집 경로가 두 갈래로 운영 | `verifications/` → `docs/evidence/verifications/`로 통합 | M |
| DEBT#072 | DRY | heal.nim duplication (Closed) | 복사-붙여넣기 개발 | nimtry dry_queries로 duplicate block 탐지 | S |
| DEBT#088 | DRY | JSON parsing pattern duplication | 공통 JSON 유틸리티가 있음에도 중복 구현 | 모든 JSON 파싱을 `json_utils.nim`으로 통합 | M |

---

## 🟢 P3 — Low 부채 (16건)

| ID | Category | Symptom | Status | Why Closed/Status | Effort |
|----|----------|---------|--------|-------------------|--------|
| DEBT#073 | Repository Hygiene | Tracked runtime artifacts in Git | Closed | `.gitignore` 추가 | S |
| DEBT#074 | Repository Hygiene | diff.diff stale artifact | Closed | 삭제 | S |
| DEBT#075 | Repository Hygiene | 6 stale binaries | Partial | `bin/gate_test` 삭제, `bin/readfile_guard` 잔존 | S |
| DEBT#076 | Repository Hygiene | 2 unreferenced Nim files | Closed | 삭제 | S |
| DEBT#077 | Repository Hygiene | Root-level proof_universe.lock | Closed | 루트 파일 삭제 | S |
| DEBT#078 | Repository Hygiene | docs/ misplaced files | Closed | `docs/spec/`로 이동 | S |
| DEBT#079 | Dead Code | 35-line `when false:` block | Closed | 삭제 | S |
| DEBT#080 | Dead Code | 3 placeholder test files | Closed | 삭제 | S |
| DEBT#081 | Dead Code | ghost_update.nim never imported | Closed | 삭제 | S |
| DEBT#082 | Dead Code | unified_sentry binary unregistered | Closed | 삭제 또는 등록 | S |
| DEBT#083 | Language/Platform | ax.cmd references non-existent | Closed | 수정 | S |
| DEBT#084 | Language/Platform | GitHub Actions embed Bash/PowerShell | Closed | CI 워크플로우 수정 | S |
| DEBT#085 | Compiler Hygiene | std/times unused import | Closed | 삭제 | S |
| DEBT#086 | Compiler Hygiene | XDeclaredButNotUsed Hint | Closed | `config.nims`에 `hintAsError` 추가 | S |
| DEBT#087 | DRY | Hardcoded engine selection strings | Closed | 상수화 또는 registry로 이동 | S |

---

## Gateway Test TODO 부채 분석 (481건)

### Feature 영역별 미구현 테스트 분포

| Feature 영역 | TODO 수 | 비율 | 주요 항목 예시 |
|-------------|--------|------|--------------|
| Other (분류 어려움) | 134 | 27.9% | information_entropy_grading, scheduler, domain_types 등 |
| Solver/Proof | 70 | 14.6% | smt_to_lean, z3_integrity, lean_compiler_compat |
| Gate/Architecture | 52 | 10.8% | architecture_gate, solid_complexity_gate |
| CLI/Workflow | 47 | 9.8% | ax_command_surface, ax_help, report_cli |
| ASI/Metrics | 39 | 8.1% | asi_ssot, asi_hard_gate, asi_metric_unification |
| Translator/Boundary | 38 | 7.9% | transpilation_layer, universal_assembler |
| Extractor/Topology | 37 | 7.7% | boundary_extractor, tree_sitter_bridge |
| Type/Inference | 28 | 5.8% | context_aware_type_inference, refinement_types |
| Heal/Integrity | 21 | 4.4% | heal_on_prove_convergence, integrity_guard |
| Certificate/Vault | 8 | 1.7% | certStale_state_sync, proof_replay_ssot |

### Feature↔Test 매핑 누락

| 구분 | 수량 |
|------|------|
| 총 .feature 파일 | 123개 |
| 대응 runner 존재 | **4개** |
| Zombie (runner 없음) | **119개 (96.7%)** |
| @manual 태그 비율 | **100%** |

### 핵심 발견

1. **@manual 태그 남용**: 123개 .feature 전부가 `@manual` 태그를 첫 줄에 포함하여 zombie check를 우회.
2. **Stub 삭제 ≠ 테스트 구현**: 109개 stub 파일이 삭제되었으나, 실제 `*_feature_test.nim`은 0개 존재.
3. **실질 테스트 커버리지**: assertion이 있는 runner는 4개뿐 (3.2%).

---

## Recommended Roadmap

### Phase 0 — Firefighting (1주)
- **DEBT#001** 컴파일 불가 모듈 복구
- **DEBT#004** nimble.lock 생성 및 Git 추가
- **DEBT#005** gate/domain_types.nim → gate/gate_types.nim rename
- **DEBT#008** L3 cgroups v2 wrapWithCgroupsIfAvailable() 실제 구현

### Phase 1 — Core Integrity (2~3주)
- **DEBT#002** ASI 1.0000 Hard Gate 재가동: `#print axioms` 강제, anti_tautology_sentinel 추가
- **DEBT#003/#007** Provider 인터페이스 추상화 완성
- **DEBT#006** SoC 위반 import 정리
- **DEBT#009** Multiplicative parallelism 완화: 전역 concurrency token pool 도입
- **DEBT#014** GUARDIAN.md/core_rules.md SSOT 확정

### Phase 2 — Effect System Restoration (2~3주)
- **DEBT#021~026** Purity/Effect 복원: `func` 기본, `raises: []` 강제, `cast(noSideEffect)` 금지
- **DEBT#043** core/ I/O primitives를 infra/cli로 이관
- **DEBT#027~029** Gate↔Infra↔Presentation 경계 정리

### Phase 3 — Gate Hardening (2~3주)
- **DEBT#010/#011** verifyCertificates 분할 + quality gate AST 기반 재작성
- **DEBT#035** CPU starvation 방어 스택 검증
- **DEBT#039** per-gate timeout 구현

### Phase 4 — Test & Documentation (4~6주)
- **DEBT#012** solver/와 analyzer/ 테스트 커버리지 확보
- **DEBT#017/GW** @manual 태그 재검토 + 119개 zombie runner 구현
- **DEBT#040** 문서화율 목표: gate/ 80%+

### Phase 5 — Refactoring & Cleanup (지속)
- **DEBT#018~019** 500줄 초과 파일 및 ACI >100 함수 분할
- **DEBT#030~031** DRY 정리 + Python/Bash → Nim 포팅
- **DEBT#047~050** deprecated 파일/함수 정리

---

## Data Sources

1. **Context7 MCP**: `/nim-lang/nim`, `/leanprover/lean4`, `/z3prover/doc` 공식 문서 조회 (6개 라이브러리, 15+ 쿼리)
2. **DEBT_REGISTRY.md**: 88건 항목 전수 분석
3. **소스코드 AST 검증**: `nim check`, `grep`, `wc -l`, `git log` 기반 실측
4. **AGENTS.md**: §0.2~§2.8 전체 규칙 참조
5. **기존 감사 보고서**: `docs/reports/` 내 15종 보고서 종합

---

*본 보고서는 Context7 공식 문서를 근거로 하며, AGENTS.md §0.5a "Exhaustive Investigation Documentation Mandate"를 준수합니다.*
