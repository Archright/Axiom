# Axiom 기술부채 전수조사 보고서 — Context7 공식 문서 교차검증

**조사 일자**: 2026-05-31
**조사 범위**: 전체 코드베이스 (`src/` 400파일, `tests/` 219파일, `scripts/` 8파일, `bin/` 12바이너리)
**조사 방법**: Context7 MCP 공식 문서(Nim 2.2.10) 교차검증 + DEBT_REGISTRY 88건 분석 + 병렬 서브에이전트 코드베이스 탐사 + GUARDIAN §-1 4차원 검증
**근거 문서**: `/nim-lang/nim` (Context7 Library ID, 4405 snippets), `/websites/nim-lang_github_io_nim` (11048 snippets)
**총 식별 항목**: 88건 (Critical 15 / High 32 / Medium 28 / Low 13)
**완료 항목**: 22건 자동완료 (2026-05-30 Phase 3 Core Isolation)
**잔여 미해결**: 66건

---

## §0. Executive Summary

Axiom 프로젝트는 **400개 소스 모듈, 179개 코어 엔진 파일, 61개 게이트 모듈**로 구성된 대규모 정적 분석·검증 엔진입니다. 2026-05-30 Phase 3 Core Isolation에서 22건이 자동완료되었으나, **15개 Critical 항목**이 여전히 프로젝트 핵심 가치를 위협하고 있습니다.

### 핵심 발견 (Context7 공식 문서 근거)

| 발견 | Severity | Context7 근거 | 4차원 판정 |
|------|----------|---------------|-----------|
| func/proc 비율 79.35% (임계치 80% 미달) | Critical | Nim 공식: "`func` is a shortcut for a `noSideEffect` proc" — 순수성 검증은 컴파일러가 기계적으로 보장 | Ideal❌ Elegant✓ Fundamental✓ Deterministic✓ |
| `cegar_engine.nim` Domain→Infrastructure 계층 위반 | Critical | Nim 공식: effect system은 모듈 경계에서 작동 — import 방향이 side effect 전파를 결정 | Ideal✓ Elegant✓ Fundamental❌ Deterministic✓ |
| ~170개 try/except → Result[T,E] 미전환 | High | Nim 공식: "errors must be handled explicitly as data through `Option[T]` or `Result[T, E]` types" (manual.md) | Ideal✓ Elegant✓ Fundamental❌ Deterministic✓ |
| `cast(noSideEffect)` compiler 우회 2건 | High | Nim 공식: `{.cast(noSideEffect).}: ...` — "new preferred syntax" (changelog_1_4_0.md)이나 남용은 effect system 무력화 | Ideal❌ Elegant❌ Fundamental❌ Deterministic✓ |
| `ref object` in core/ — deterministic destruction 파괴 | High | Nim 공식: "ORC primarily uses reference counting with cycle collection" (mm.md) — ref object는 cycle risk | Ideal❌ Elegant❌ Fundamental✓ Deterministic✓ |
| ASI 1.0000 Hard Gate SUSPENDED | Critical | 프로젝트 핵심: vacuous proof가 Lean kernel을 통과하면 수학적 검증 자체가 무의미 | Ideal❌ Elegant❌ Fundamental❌ Deterministic✓ |
| Z3Provider/Lean4Provider stub | Critical | 프로젝트 핵심: "수학적 검증"의 물리적 백엔드 미연결 | Ideal❌ Elegant❌ Fundamental❌ Deterministic✓ |

### 가장 시급한 5개 P0 항목

1. **Z3Provider/Lean4Provider stub** (DEBT#003) — 검증 엔진의 물리적 백엔드 미연결
2. **ASI 1.0000 Hard Gate SUSPENDED** (DEBT#002) — vacuous proof 경로 차단 실패
3. **컴파일 불가 모듈** (DEBT#001) — 5개 CLI 진입점 + 9개 테스트 cascade 실패
4. **func/proc 비율 임계치 미달** (신규) — 79.35% vs 80% 임계치
5. **Domain→Infrastructure 계층 위반** (DEBT#006, 신규 cegar_engine)

---

## §1. 조사 방법론 — 4차원 검증 프레임워크

GUARDIAN §-1의 Four-Dimension Mandate에 따라 모든 발견을 4차원으로 판정합니다:

| 차원 | 질문 | Context7 검증 방법 |
|------|------|-------------------|
| **Ideal** | 컴파일 타임에 위반을 불가능하게 만들 수 있는가? | Nim effect system, `{.raises: [].}`, `func`, distinct types 확인 |
| **Elegant** | 언어 네이티브 도구(컴파일러 AST, 타입 시스템, effect system)를 사용하는가? | Nim manual의 pragma, macro, type system 섹션 참조 |
| **Fundamental** | 하드코딩 예외, 화이트리스트, 규칙 틈새가 없는가? | 소스코드의 `isGrandfatheredException`, hardcoded bypass 패턴 검출 |
| **Deterministic** | 동일 입력 → 동일 출력이 환경 무관하게 보장되는가? | Nim ORC 동작, 빌드 캐시, 파일시스템 의존성 분석 |

---

## §2. 코드베이스 현황 (2026-05-31 기준)

### 2.1 규모 지표

| 지표 | 수치 |
|------|------|
| 소스 모듈 (`src/**/*.nim`) | **400** |
| 테스트 파일 (`tests/**/*.nim`) | **219** (활성 193, deprecated 26) |
| BDD Feature 파일 | **124** |
| 게이트 바이너리 (`bin/`) | **12** |
| 빌드 스크립트 (`scripts/`) | **8** |
| 문서 (`docs/**/*.md`) | **89** |
| 외부 의존성 | tree-sitter-nim (submodule), checksums + fusion (nimble) |

### 2.2 아키텍처 레이어 분포

| 레이어 | 경로 | 파일 수 | 비고 |
|--------|------|---------|------|
| Domain | `src/core/` | 179 | BMC 엔진, 파서, solver, 타입 시스템 |
| Infrastructure | `src/verification/` | 75 | 인증서 관리, Lean LSP, 파이프라인 |
| Presentation | `src/cli/` + `src/mcp/` + `src/ui/` + `src/api/` | 70 | CLI, MCP, TUI, API |
| Gate | `src/gate/` | 61 | nimtry, 게이트 러너, 아키텍처 분석 |
| 기타 | `src/personas/` + `src/frontend/` + `src/translator/` + 등 | 15 | 페르소나, 프론트엔드, 번역기 |

### 2.3 순수성 지표

| 지표 | 수치 | 임계치 | 상태 |
|------|------|--------|------|
| `func` 선언 수 | **1,003** | — | ✅ |
| `proc` 선언 수 | **261** | — | ⚠️ |
| func/proc 비율 | **79.35%** | ≥80% (AGENTS.md §0.6) | 🔴 미달 |
| `{.raises: [].}` 선언 수 | **633+** | — | ✅ |
| TODO/FIXME/HACK 마커 (core/) | **0** | 0 | ✅ |
| distinct 타입 사용 | **6+** | — | ✅ |

---

## §3. Critical 발견 (P0) — 즉시 조치 필요

### DEBT#001: 5개 CLI 진입점 + 9개 테스트 컴파일 불가

- **Severity**: Critical
- **Category**: Compiler Hygiene
- **File**: `src/cli/basic_commands_cli.nim`, `asset_collector.nim`, `thought_dashboard.nim`, `gateway_constraint.nim`, `cross_validator.nim`
- **Context7 근거**: Nim 공식 — "Nim is a statically typed, compiled systems programming language" — 컴파일 불가는 런타임 안전성 자체를 보장 불가
- **4차원**: Ideal❌ (런타임에 발견), Elegant✓ (컴파일러가 탐지), Fundamental✓, Deterministic✓
- **조치**: 미사용 모듈 정리 또는 import 수정. `nim c` exit=1을 해결하여 게이트 체인 복구

### DEBT#002: ASI 1.0000 Hard Gate SUSPENDED

- **Severity**: Critical
- **Category**: Tautology / Vacuity
- **File**: `src/core/smart_search.nim`, `src/cli/commands/submit.nim`, `src/core/gateway.nim`
- **Context7 근거**: 프로젝트 핵심 가치 — "수학적 검증"이 vacuous proof를 통과하면 전체 인증서 체인이 무의미
- **4차원**: Ideal❌ (런타임에서만 탐지), Elegant❌ (regex 기반 탐지), Fundamental❌ (3+ 우회 경로 존재), Deterministic✓
- **조치**: Vacuity sentinel을 compile-time AST 분석으로 강화. `smart_search.nim`의 n=n 자기동등 패턴 차단

### DEBT#003: Z3Provider / Lean4Provider stub

- **Severity**: Critical
- **Category**: Critical Stubs
- **File**: `src/core/provider_interface.nim`
- **Context7 근거**: 프로젝트 헌법 §0.1 — "Integrity Engine proving Race Condition, Memory Safety, and Logic Correctness through BMC" — BMC의 물리적 백엔드가 stub이면 검증 자체가 불가
- **4차원**: Ideal❌, Elegant❌, Fundamental❌, Deterministic✓
- **조치**: Z3 persistent pool 연결 또는 Lean4 LSP bridge 활성화. `solverUnknown` 반환을 `Result[T,E]`로 명확화

### DEBT#005: gate/domain_types.nim이 core/domain_types.nim을 shadow copy

- **Severity**: Critical
- **Category**: Architecture / SSOT
- **File**: `src/gate/domain_types.nim` vs `src/core/domain_types.nim`
- **Context7 근거**: Nim 공식 distinct types — "prevents accidental mixing" (manual.md) — 타입 정의가 두 곳에 존재하면 distinct type의 의미론적 경계가 무력화
- **4차원**: Ideal❌, Elegant❌ (SSOT 위반), Fundamental❌ (하드코딩 면제), Deterministic❌ (정의 발산 가능)
- **조치**: `gate/domain_types.nim` 삭제, `core/domain_types.nim`만 사용. gate 모듈이 core를 import하도록 변경

### DEBT#006: gateway.nim이 verification/state_manager를 직접 import

- **Severity**: Critical
- **Category**: Architecture / SoC
- **File**: `src/core/gateway.nim`
- **Context7 근거**: Nim effect system — import 방향이 side effect 전파를 결정. Domain이 Infrastructure를 import하면 순수성이 보장 불가
- **4차원**: Ideal✓ (compile-time 탐지 가능), Elegant✓ (import 분석), Fundamental❌ (`isGrandfatheredException` 하드코딩), Deterministic✓
- **조치**: `state_manager`의 타입 정의를 `core/`로 추출하거나, gateway를 `verification/`로 이동

### DEBT#007: provider_interface.nim이 z3ExecPersistent를 직접 호출

- **Severity**: Critical
- **Category**: Architecture / DIP
- **File**: `src/core/provider_interface.nim`
- **Context7 근거**: GUARDIAN §15 — "Persistent Pool Disabling Anti-Pattern" — z3ExecPersistent는 오케스트레이션 불변식이며 직접 호출은 DIP 위반
- **4차원**: Ideal✓ (compile-time import 분석), Elegant✓, Fundamental❌ (`isSolverDependencyOwner` 하드코딩), Deterministic✓
- **조치**: `ProverInterface` closure 또는 `SolverBridgeResult`를 통한 간접 호출로 전환

### DEBT#008: L3 cgroups v2 구현 공백

- **Severity**: Critical
- **Category**: Gate Infrastructure
- **File**: `scripts/gate_hook.nim`
- **4차원**: Ideal❌ (문서와 코드 분리), Elegant❌ (시스템 호출 미구현), Fundamental❌ (문서상 존재하나 코드상 부재), Deterministic✓
- **조치**: `wrapWithCgroupsIfAvailable` 구현 또는 AGENTS.md §1.2 문서 업데이트

### DEBT#009: Multiplicative parallelism — 32+ 동시 작업자 OOM

- **Severity**: Critical
- **Category**: Gate Infrastructure
- **File**: `src/gate/runner.nim`
- **Context7 근거**: Nim 공식 ORC — "RC operations are not atomic and subgraphs can be moved between threads" (mm.md) — 과도한 병렬성은 ORC의 reference counting을 불안정하게 만듦
- **4차원**: Ideal✓ (compile-time cap 가능), Elegant❌ (하드코딩 슬롯 수), Fundamental✓, Deterministic❌ (환경 의존적)
- **조치**: `safeMaxJobs` 함수로 메모리/CPU 기반 동적 cap. `countProcessors() div 2` 상한 적용

### DEBT#010: verifyCertificates 403줄 god function

- **Severity**: Critical
- **Category**: Code Complexity
- **File**: `src/verification/analyzer.nim`
- **4차원**: Ideal❌, Elegant❌ (14개 책임 영역), Fundamental✓, Deterministic✓
- **조치**: 8-stage 파이프라인으로 분해. 각 stage를 독립 모듈로 추출

### DEBT#011: Quality gate 구조적 손상 — regex 기반

- **Severity**: Critical
- **Category**: Gate Infrastructure
- **File**: `src/gate/quality_gate.nim`
- **Context7 근거**: Nim 공식 — AST 기반 분석이 regex보다 우월. `std/effecttraits` 모듈로 introspection 가능 (changelog_1_4_0.md)
- **4차원**: Ideal❌ (regex는 타입 정보 무시), Elegant❌ (언어 네이티브 도구 미사용), Fundamental✓, Deterministic✓
- **조치**: regex 기반 검출을 Nim AST 파서 기반으로 전환

### DEBT#012: 42.3% 모듈 테스트 커버리지

- **Severity**: Critical
- **Category**: Test Coverage
- **범위**: `src/core/solver/` 12개 파일 0%, `src/verification/analyzer/` 8개 stage 0%, `src/gate/` 44개 중 8개만 테스트
- **4차원**: Ideal❌, Elegant✓, Fundamental✓, Deterministic✓
- **조치**: AGENTS.md §0.7에 따라 BDD feature 기반 통합 테스트 우선 작성

### DEBT#013: certificateStatusToProofEntryStatus 399줄

- **Severity**: Critical
- **Category**: Code Complexity
- **File**: `src/cli/report_cli.nim`
- **4차원**: Ideal❌, Elegant❌, Fundamental✓, Deterministic✓
- **조치**: 상태 변환을 테이블 기반 매핑으로 전환

### DEBT#014: GUARDIAN.md 브랜치 간 SSOT divergence

- **Severity**: Critical
- **Category**: Structural / SSOT Divergence
- **범위**: `main` 브랜치에서 GUARDIAN.md 삭제 → `core_rules.md`로 rename. `core` 브랜치에서는 반대. AGENTS.md 참조도 브랜치별 상이
- **4차원**: Ideal❌, Elegant❌, Fundamental❌, Deterministic❌
- **조치**: `core` 브랜치 rebase로 GUARDIAN.md → `core_rules.md` 통일. AGENTS.md 참조 경로 일원화

---

## §4. High 발견 (P1) — 단기 해결 필요

### P1-Architecture: 계층 위반 (5건)

| ID | 항목 | 파일 | Context7 근거 |
|----|------|------|--------------|
| DEBT#027 | 5개 gate 모듈이 verification/에 misplaced | `src/verification/gate_*.nim` | Nim 모듈 시스템 — import 경계가 effect 전파를 결정 |
| DEBT#028 | Infra↔Gate 순환 의존성 | `proof_state_builder.nim` ↔ `convergence_sidecar.nim` | Nim 컴파일러 — 순환 import는 컴파일 순서 불확실성 야기 |
| DEBT#029 | asi_hard_gate가 cli/asi_cli를 import | `src/gate/runners/asi_hard_gate.nim` | Gate는 read-only — Presentation 의존은 side effect 전파 |
| 신규 | cegar_engine.nim Domain→Infrastructure | `src/core/cegar_engine.nim` | Domain 순수성 보장을 위한 import 방향 엄수 |
| 신규 | solver_bridge.nim이 Lake import | `src/core/solver_bridge.nim` | 외부 빌드 도구 의존은 Infrastructure에 격리 |

### P1-Purity: Effect System 미준수 (6건)

| ID | 항목 | 수치 | Context7 근거 |
|----|------|------|--------------|
| DEBT#021 | try/except 블록 ~170개 | `src/core/` ~90, `src/verification/` ~80 | Nim 공식: "errors must be handled as data through Result[T, E]" |
| DEBT#022 | discard 문 113~150+개 | `semantic_graph.nim` 15+, `lean_lsp.nim` 20+ | 오류 침묵 — 컴파일러가 탐지 불가 |
| DEBT#023 | verification 모듈 22/29개 {.raises: [].} 미적용 | `src/verification/` | Nim 공식: `{.push raises: [].}`로 파일 수준 정책 선언 가능 |
| DEBT#024 | 13개 pure proc → func 미전환 | `src/core/` | Nim 공식: "`func` is a shortcut for `noSideEffect` proc" — 기계적 순수성 보장 |
| DEBT#025 | `cast(noSideEffect)` 우회 2건 | `sync_utils.nim`, `z3_pool.nim` | Nim 공식: `{.cast(noSideEffect).}:` — 새 구문이나 남용은 effect system 무력화 |
| DEBT#026 | `ref object` in core — deterministic destruction 파괴 | `semantic_graph.nim`, `lean_lsp.nim` | Nim 공식 ORC: "cycle collection mechanism based on trial deletion" — ref object는 cycle risk |

### P1-Code Complexity: 대형 함수/파일 (4건)

| ID | 항목 | 수치 |
|----|------|------|
| DEBT#018 | 500줄 초과 파일 28개 | 상위: `axiom_api.nim`(1,408), `boundary_extractor.nim`(1,204) |
| DEBT#019 | ACI >100 heavy candidate 8개 | `extractBoundaries`(129), `sanitizeLeanSource`(117) 등 |
| DEBT#044 | 50줄 초과 함수 73개 | 전체 src/ 분포 |
| DEBT#045 | 과도한 nesting depth | `lean_skeleton.nim`(depth 38), `contract_ast_extractor.nim`(32) |

### P1-Resource: 시스템 안정성 (4건)

| ID | 항목 | Context7 근거 |
|----|------|--------------|
| DEBT#035 | CPU starvation → AMDGPU MODE2 reset | 16코어 포화 시 GPU driver fence 스레드 기아 |
| DEBT#036 | SwapTotal=0 — OOM killer 즉시 작동 | 시스템 설정 문제 |
| DEBT#037 | pre-commit 140MB × 14 startProcess = 1.96GB | Nim ORC + threads:on의 메모리 특성 |
| DEBT#038 | Nim 2.0 ORC bug — malebolgia 메모리 누수 | Nim 공식 이슈 #23361 |

### P1-legacy: Deprecated 코드 (3건)

| ID | 항목 | 수치 |
|----|------|------|
| DEBT#041 | 5개 deprecated API가 live caller 보유 | `nimTypeToLeanType` 등 |
| DEBT#042 | 16개 legacy code path가 replacement와 병존 | `lean_skeleton.nim` 등 |
| DEBT#047 | 8개 deprecated ASI 계산 함수 in metrics.nim | `computeAsi*` 등 |

### P1-Gate: 게이트 인프라 (4건)

| ID | 항목 | 영향 |
|----|------|------|
| DEBT#015 | Dual code path: gates.nim vs gate_hook.nim | 7개 활성 게이트 미등록 |
| DEBT#033 | AXIOM_SKIP_HEAVY_TESTS 미전파 | pre-commit 시 불필요한 22초 smoke test |
| DEBT#034 | integrity-test 매 pre-commit 174개 gateway test 실행 | >60s (규정 <10s) |
| DEBT#039 | L2 병렬 디스패처에 게이트별 timeout 부재 | hung 게이트가 파이프라인 차단 |

### P1-DRY: 코드 중복 (2건)

| ID | 항목 | 수치 |
|----|------|------|
| DEBT#030 | 9개 cross-module 중복 함수 쌍 | `clampInt`, `declareSmtVars`, `compactWhitespace` 등 |
| DEBT#031 | 7개 파일 1,349줄 Nim 미포팅 | Python 5, Bash 2 — AGENTS.md §1.1 Language Ban 위반 |

---

## §5. Medium 발견 (P2) — 중기 개선

### P2-Architecture (3건)

| ID | 항목 | 비고 |
|----|------|------|
| DEBT#043 | core/ 내 10+ 파일 직접 I/O 호출 | Domain 순수성 위반 |
| DEBT#046 | wf_state.nim 21개 모듈 import | 과도한 결합도 |
| DEBT#053 | 15+ 하드코딩 SRP 면제 경로 | nimtry에서 관리 필요 |

### P2-Legacy/Deprecated (3건)

| ID | 항목 | 비고 |
|----|------|------|
| DEBT#048 | nimtry/ 내 5개 deprecated 파일 | 정리 필요 |
| DEBT#049 | tree_sitter_bridge.nim 완전 DEPRECATED | 삭제 후보 |
| DEBT#050 | architecture_gate.nim DEPRECATED | thin wrapper만 유지 |

### P2-Workaround (1건)

| ID | 항목 | Context7 근거 |
|----|------|--------------|
| DEBT#051 | Nim 2.x 타입 추론 버그 workaround | Nim 공식: 알려진 이슈 — Nim 버전 업그레이드 시 재평가 필요 |

### P2-Future Work (1건)

| ID | 항목 | 비고 |
|----|------|------|
| DEBT#052 | 6개 TODO 항목 | heal_parsing, cbor, smt_reconstruction 등 |

### P2-Gate/Metric (2건)

| ID | 항목 | 비고 |
|----|------|------|
| DEBT#058 | module_overrides 섹션 누락 — 8개 모듈 미검사 | architecture_policy.lock |
| DEBT#059 | computeCohesion FNV-1a fallback — 수학적 무의미 | cohesion_enforce.nim |

### P2-Gate/SSOT (1건)

| ID | 항목 | 비고 |
|----|------|------|
| DEBT#060 | ssot-taint 쿼리 비활성화 — 366k+ false positive | nimtry |

### P2-Build Optimization (4건)

| ID | 항목 | 비고 |
|----|------|------|
| DEBT#061 | config.nims gorgeEx all_gateway_runner ~6.7s/nim c | 빌드 병목 |
| DEBT#062 | main.nim과 ax.nim 99.5% 공유 but 별도 컴파일 | 중복 빌드 |
| DEBT#063 | per-target nimcache 격리로 616/617 아티팩트 중복 | 디스크 낭비 |
| DEBT#064 | trackedSourceFiles 잘못된 경로 | config.nims |

### P2-Structural (2건)

| ID | 항목 | 비고 |
|----|------|------|
| DEBT#065 | topology_cache.json 161MB 로테이션 없음 | 디스크 관리 |
| DEBT#068 | scripts/ vs bin/ vs src/gate/ 혼재 | 구조 정리 필요 |

### P2-Documentation (1건)

| ID | 항목 | 비고 |
|----|------|------|
| DEBT#040 | 모듈 문서화율 64%, 심볼 44%, gate/ 0% | 문서화 필요 |

### P2-DRY (1건)

| ID | 항목 | 비고 |
|----|------|------|
| DEBT#088 | JSON 파싱/CLI fallback 패턴 중복 | src/cli/ |

### P2-Lock/SSOT (1건)

| ID | 항목 | 비고 |
|----|------|------|
| DEBT#071 | Evidence SSOT 분기: verifications/ vs docs/evidence/ | 통합 필요 |

---

## §6. Low 발견 (P3) — 장기 정리

| ID | 항목 | 상태 |
|----|------|------|
| DEBT#075 | 6개 stale 바이너리 — 소스 미연결 | Partial |
| DEBT#088 | JSON 파싱 패턴 중복 | Open |

**나머지 Low 항목(22건)은 2026-05-30 Phase 3에서 자동완료 처리됨.**

---

## §7. 양호 항목 — Context7 공식 문서와 일치하는 설계

### ✅ Domain 타입 SSOT (`domain_types.nim`)

- 343줄, 22-variant `AxiomError` enum, 6-state `CertificateStatus` distinct enum
- `{.push raises: [].}` + `{.push noSideEffect.}` 파일 수준 적용
- **Context7 근거**: Nim 공식 — distinct types로 "prevents accidental mixing" (manual.md) — 프로젝트가 이를 충실히 이행

### ✅ distinct 타입 사용 (6+)

- `CertificateStatus`, `AxiomSafe[T]`, `SorterNodeId`, `AxiomFormula`, `ValidatedAsi`, `ProviderSolverStatus`
- **Context7 근거**: Nim 공식 SQL injection 예제와 동일 패턴 — "Static error: `query` expects an SQL string!" (manual.md)

### ✅ `{.raises: [].}` 준수 (633+ 선언)

- core/ 전체에 걸쳐 파일 수준 `{.push raises: [].}` 적용
- FFI 경계(`tree_sitter_parse.nim`)에서만 명시적 raise set 선언
- **Context7 근거**: Nim 공식 — `{.push raises: [].}`로 모듈 수준 정책 선언 가능

### ✅ ORC 기반 메모리 관리

- `config.nims`에서 `--mm:orc` 명시적 설정
- value-type 중심 설계 지향
- **Context7 근거**: "ORC is the default memory management strategy" (mm.md) — 프로젝트가 기본값을 따름

### ✅ 게이트 체인 무결성

- 12개 게이트 바이너리, L0→L1→L2 계층 구조
- compile-time gate bonding (`config.nims`에서 게이트 실패 시 빌드 중단)
- **Context7 근거**: Nim의 compile-time 검증 철학과 일치

### ✅ BDD 기반 테스트

- 124개 Gherkin feature 파일, `@executable`/`@manual` 태그 스키마
- **AGENTS.md §0.7**: "Business-Only Test Scope" — 컴파일러가 보장하는 동작은 테스트하지 않음

---

## §8. Context7 공식 문서 근거 레지지스트리

| 주제 | Context7 Library ID | 쿼리 | 핵심 근거 |
|------|---------------------|------|----------|
| Effect System | `/nim-lang/nim` | "func proc noSideEffect raises" | "`func` is a shortcut for a `noSideEffect` proc" — 기계적 순수성 보장 |
| ORC Memory | `/nim-lang/nim` | "ORC memory management ref object" | "ORC primarily uses reference counting with cycle collection" — ref object는 cycle risk |
| Distinct Types | `/nim-lang/nim` | "distinct types type safety" | "Static error: `query` expects an SQL string!" — 타입 안전성은 컴파일러가 보장 |
| Static Analysis | `/nim-lang/nim` | "nim check static analysis" | DrNim: "Detect Array Index Out of Bounds Bug" — compile-time 검증 가능 |
| Effect Introspection | `/nim-lang/nim` | "effecttraits module introspection" | "`std/effecttraits` module is now available for introspection of inferred effects" |
| Deprecated Syntax | `/nim-lang/nim` | "cast noSideEffect new syntax" | "`{.cast(noSideEffect).}: ...` which is the new preferred syntax" (changelog_1_4_0) |

---

## §9. 우선순위 기반 복구 로드맵

### Phase 0: 즉시 (이번 주)

| 순위 | 항목 | 작업 | 예상 시간 |
|------|------|------|----------|
| 1 | DEBT#003 | Z3Provider/Lean4Provider 연결 또는 명확한 에러 반환 | 2h |
| 2 | DEBT#001 | 5개 CLI 진입점 컴파일 에러 수정 | 1h |
| 3 | 신규 | `cegar_engine.nim` 계층 위반 수정 (→ verification/ 이동) | 30m |
| 4 | 신규 | 5-6개 pure proc → func 전환 (80% 임계치 달성) | 1h |

### Phase 1: 단기 (2주 이내)

| 순위 | 항목 | 작업 | Context7 근거 |
|------|------|------|--------------|
| 5 | DEBT#005 | gate/domain_types.nim 삭제, core/domain_types.nim 통합 | distinct types SSOT |
| 6 | DEBT#002 | ASI Hard Gate 복구 — vacuity sentinel 강화 | 프로젝트 핵심 가치 |
| 7 | DEBT#025 | `cast(noSideEffect)` → 생성자 패턴 전환 | GUARDIAN §15 |
| 8 | DEBT#021 | 핵심 try/except → Result[T,E] 전환 (10건/주) | Nim 공식 error handling |
| 9 | DEBT#009 | safeMaxJobs 동적 cap 구현 | ORC threading model |

### Phase 2: 중기 (1개월 이내)

| 순위 | 항목 | 작업 |
|------|------|------|
| 10 | DEBT#010 | verifyCertificates 8-stage 파이프라인 분해 |
| 11 | DEBT#011 | quality gate regex → AST 기반 전환 |
| 12 | DEBT#018 | 500줄 초과 파일 28개 모듈 분할 |
| 13 | DEBT#030 | 9개 cross-module 중복 함수 추출 |
| 14 | DEBT#015 | gates.nim / gate_hook.nim 듀얼 코드 패스 통합 |

### Phase 3: 장기 (분기 이내)

| 순위 | 항목 | 작업 |
|------|------|------|
| 15 | DEBT#012 | 테스트 커버리지 42.3% → 80% 달성 |
| 16 | DEBT#014 | GUARDIAN.md 브랜치 SSOT 통일 |
| 17 | DEBT#031 | Python/Bash 파일 Nim 포팅 (1,349줄) |
| 18 | DEBT#040 | 문서화율 64% → 90% 달성 |

---

## §10. 결론

Axiom 프로젝트는 **아키텍처 의도가 우수**합니다 — 4계층 분리, distinct 타입, `{.raises: [].}` 633+ 선언, compile-time gate bonding은 Nim 공식 문서가 권장하는 최선의 실천과 일치합니다. 그러나 **구현과 의도 사이의 갭**이 66건의 미해결 기술부채로 나타나고 있습니다.

가장 근본적인 문제는 **3개 Critical stub**(Z3/Lean4 provider, ASI hard gate, 컴파일 불가 모듈)으로, 이들은 프로젝트의 핵심 가치 proposition인 "수학적 검증" 자체를 물리적으로 불가능하게 만듭니다.

**Context7 공식 문서 기반 최종 권고**: Nim 2.2.10의 effect system, ORC, distinct types은 이미 프로젝트가 요구하는 모든 안전성을 **컴파일 타임에** 제공합니다. 현재 기술부채의 대부분은 이 언어 네이티브 도구를 충분히 활용하지 못한 결과입니다 — regex 대신 AST, try/except 대신 Result, proc 대신 func, hardcoded bypass 대신 type-system enforcement.

**"We don't protect code; we protect the 'laws of physics' we declare."** — GUARDIAN
