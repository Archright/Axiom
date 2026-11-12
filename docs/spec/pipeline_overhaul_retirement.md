# 파이프라인 오버홀 레거시 코드 은퇴 명세서 (Phase 6A)

> **작성일**: 2026-06-28
> **상태**: 활성 (레거시 코드 마이그레이션 진행 중)

---

## 1. 개요

이 문서는 Axiom 파이프라인 오버홀의 일환으로 폐기 대상이 된 레거시 코드를 기록하고,
다운스트림 소비자를 위한 마이그레이션 경로를 정의한다.

모든 레거시 코드는 `# DEPRECATED [Phase 6A]:` 주석이 추가되어 있으며,
새로운 파이프라인 컴포넌트로의 전환이 완료될 때까지 후방 호환성을 위해 유지된다.

---

## 2. 폐기 코드 → 대체 모듈 매핑

| # | 레거시 코드 (레거시) | 파일 경로 | 대체 모듈 (신규) | 파일 경로 | 상태 |
|---|---|---|---|---|---|
| 1 | Nim 기반 구조적 Lean 커널 검증 (`verifyLeanKernel`) | `src/infrastructure/gate_signing/proof_verifier.nim` | Phase 3B Lean 검증 CLI | `src/cli/lean_verify_cmd.nim` + `src/verification/lean_build_sandbox.nim` | ✅ 비활성화됨 |
| 2 | `certVerifiedAxiom` 카탈로그 조회 상태 | `src/core/types/certificate_types.nim` | Phase 5A AST 기반 시그니처 | `src/core/verified_axioms/ast_signature.nim` | ✅ 비활성화됨 |
| 3 | `certIntrinsic` 별칭 | `src/core/types/certificate_types.nim` | Phase 5A AST 기반 시그니처 | `src/core/verified_axioms/ast_signature.nim` | ✅ 비활성화됨 |
| 4 | `promoteToCertVerifiedAxiom` 프로시저 | `src/verification/certificate_manager.nim` | Phase 5A AST 기반 시그니처 | `src/core/verified_axioms/ast_signature.nim` | ✅ 비활성화됨 |
| 5 | Nim IR → Lean 4 브릿지 (파일 생성+컴파일 패턴) | `src/verification/nim_to_lean_bridge.nim` | Core IR 리프터 | `src/core/trusted/ir_to_lean.nim` + `src/cli/lean_verify_cmd.nim` | ✅ 비활성화됨 |
| 6 | AST-to-Lean 스켈레톤 브릿지 (문자열 기반 변환) | `src/core/translator/ast_to_lean_bridge.nim` | Core IR 리프터 | `src/core/trusted/ir_to_lean.nim` | ✅ 비활성화됨 |
| 7 | SMT-to-Lean 브릿지 퍼서에이드 (재내보내기 패턴) | `src/core/encoding/smt_to_lean_bridge.nim` | Core IR 리프터 | `src/core/trusted/ir_to_smt.nim` + `src/core/trusted/ir_to_lean.nim` | ✅ 비활성화됨 |

---

## 3. 상세 사유

### 3.1 Nim 기반 Lean 커널 검증 → Phase 3B (_Lean 검증 CLI_)

**레거시**: `proof_verifier.nim`의 `verifyLeanKernel` 함수는 Nim 수준에서 Z3 증명 DAG의
구조적 타당성(전제 유효성, 규칙 arity, DAG 순서)을 검증했다.これは 실제 Lean 4 커널 검증이 아닌
Nim 기반 구조적 검사였다.

**신규**: Phase 3B는 `lean_verify_cmd.nim`과 `lean_build_sandbox.nim`을 통해 실제 Lean 4 커널 검증을 수행한다.
격리된 `lake build` 실행으로 진정한 논리적 건전성을 보장한다.

**영향**: `verifyLeanKernel`, `checkPremisesValid`, `checkRuleArity` 함수에 deprecated 주석 추가.

### 3.2 `certVerifiedAxiom` 카탈로그 조회 → Phase 5A (AST 기반 시그니처)

**레거시**: `certVerifiedAxiom` 상태는 문자열 기반 카탈로그 조회를 사용하여 공리 인증을 수행했다.
이 접근 방식은 변수명이나 포맷에 따라 동일한 함수가 다르게 인식될 수 있었다.

**신규**: Phase 5A의 `ast_signature.nim`은 결정론적 IR-구조 해싱을 사용하여 동일한 IR 구조를 가진
두 함수가 동일한 시그니처를 생성하도록 한다.

**영향**: `certVerifiedAxiom` 열거형 값, `certIntrinsic` 별칭, `promoteToCertVerifiedAxiom` 프로시저에 deprecated 주석 추가.
기존 증명 JSON 파일과의 후방 호환성을 위해 열거형 값 자체는 유지.

### 3.3 독립적 SMT/Lean 리프터 → Core IR

**레거시**: `nim_to_lean_bridge.nim`, `ast_to_lean_bridge.nim`, `smt_to_lean_bridge.nim`은
각각 독립적인 경로로 Nim AST를 Lean 4로 변환했다. 이 모듈들은 문자열 기반 변환, 파일 생성 후 컴파일 패턴을 사용했다.

**신규**: `ir_to_smt.nim`과 `ir_to_lean.nim`은 Core IR 타입 시스템(`axiom_ir.nim`)을 통해
순수 함수형으로 SMT-LIB2 및 Lean 4 소스 코드를 생성한다. 파일 I/O 없이 문자열만 반환한다.

**영향**: 세 개의 브릿지 모듈 전체에 deprecated 주석 추가.

---

## 4. 마이그레이션 가이드

### 4.1 `verifyLeanKernel` 사용자

```nim
# 이전 (레거시):
import infrastructure/gate_signing/proof_verifier
let valid = verifyLeanKernel(proofObj)

# 이후 (신규):
import cli/lean_verify_cmd
let result = runLeanVerify(timeout = 120)
if not result.success:
  # 검증 실패 처리
```

### 4.2 `certVerifiedAxiom` 상태 사용자

```nim
# 이전 (레거시):
import core/types/certificate_types
if cert.status == certVerifiedAxiom:
  # 카탈로그 기반 검증

# 이후 (신규):
import core/verified_axioms/ast_signature
let sig = axiomSignature(irFunc, leanOutput)
# sig.nimHash로 결정론적 시그니처 비교
```

### 4.3 `nim_to_lean_bridge` / `ast_to_lean_bridge` 사용자

```nim
# 이전 (레거시):
import verification/nim_to_lean_bridge
let result = bridgeNimToLean(irFunc)

# 이후 (신규):
import core/trusted/ir_to_lean
let leanSource = irToLeanModule(irFunc)
# leanSource는 순수 문자열 — 파일 쓰기는 호출자가 처리
```

### 4.4 `smt_to_lean_bridge` 사용자

```nim
# 이전 (레거시):
import core/encoding/smt_to_lean_bridge
# 재내보내기된 모든 심볼에 접근

# 이후 (신규):
import core/encoding/smt_to_lean_codegen   # Z3 증명 → Lean tactic
import core/encoding/smt_to_lean_translate  # SMT-LIB2 → Lean 정리
# 또는 Core IR 경로:
import core/trusted/ir_to_smt
import core/trusted/ir_to_lean
```

---

## 5. 제거 타임라인

| 단계 | 시점 | 작업 |
|---|---|---|
| Phase 6A (현재) | 2026-06-28 | Deprecated 주석 추가, 은퇴 명세서 작성 |
| Phase 6B | TBD (2개월 후) | 모든 다운스트림 호출부 마이그레이션 확인 |
| Phase 6C | TBD (3개월 후) | Deprecated 모듈의 공개 API를 `when defined(legacyCompat)` 조건부로 전환 |
| Phase 6D | TBD (6개월 후) | Deprecated 모듈 완전 삭제 (게이트 검증 후) |

> **주의**: Phase 6D의 삭제는 다음 조건이 충족되어야 한다:
> 1. 모든 테스트가 deprecated 모듈 없이 통과
> 2. CI 파이프라인이 deprecated import 없이 빌드 성공
> 3. 아키텍처 검문소 게이트의 `--deprecated` 플래그가 0개 경고

---

## 6. 관련 문서

- `docs/spec/ir_pipeline_integration.md` — Phase 4D AST 시그니처/IR 파이프라인 통합
- `docs/spec/hermetic_build.md` — Phase 3B/3D 격리된 빌드 정책 검증 (hermetic enforcement)
- `docs/spec/axiom_core_ir_spec.md` — Core IR 타입 시스템
- `AGENTS.md §1` — 전체 아키텍처 사양
