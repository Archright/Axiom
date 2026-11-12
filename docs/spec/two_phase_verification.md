# 2단계 검증 파이프라인 (Two-Phase Verification Pipeline)

**생성일**: 2026-06-28
**상태**: Phase 4A/6B — Z3 + Lean 역할 분리 완료
**소스**: `src/core/types/verification_tier.nim`, `src/core/types/certificate_types.nim`, `src/verification/cross_validation.nim`
**AGENTS.md 참조**: §0.1 (프로젝트 목적), §1 (아키텍처)

---

## 1. 개요

Axiom은 AI가 생성한 소프트웨어 로직의 무결성을 수학적으로 검증하는 엔진이다.
2단계 검증 파이프라인은 **Z3 SMT 솔버**(decidable fragments)와 **Lean 4 키ernel**(structural invariants)을
병렬로 활용하여, 각 솔버의 강점을 극대화하는 ** dual-verified ** 인증서를 생성한다.

### 1.1 설계 원칙 (AGENTS.md §0.2)

- **Ideal**: 컴파일 타임에 방지 가능한 오류는 런타임에서 검증하지 않는다.
- **Elegant**: 언어 네이티브 도구(Z3 FFI, Lean 4 LSP)를 사용한다.
- **Fundamental**: 하드코딩된 예외 없이, 원칙적으로 동작한다.
- **Deterministic**: 동일한 입력 → 동일한 출력.

---

## 2. 아키텍처 다이어그램

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Nim 소스 코드 (func / {.axiom.})                  │
└─────────────────────────┬───────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────────┐
│              Stage 1: 구문 경계 (Syntactic Guard)                   │
│  src/core/trusted/pure_func_guard.nim                              │
│  - AST walk로 금지 노드 종류 검출 (var, while, for, assignment)     │
│  - {.axiom.} pragma가 부착된 func에만 적용                         │
│  - 컴파일 타임 에러: AXIOM_VIOLATION                               │
└─────────────────────────┬───────────────────────────────────────────┘
                          │ 통과
                          ▼
┌─────────────────────────────────────────────────────────────────────┐
│           Stage 2: Axiom Core IR 변환 (AST → IR)                   │
│  src/core/trusted/axiom_ir.nim, axiom_ir_helpers.nim               │
│  - Nim AST를 IRExpr 트리로 정규화                                  │
│  - 모든 표현식은 variant object로 구조화                            │
│  - 불변수: 함수명, 파라미터, 반환 타입                              │
└────────┬──────────────────────────────────────────┬────────────────┘
         │                                          │
         ▼                                          ▼
┌────────────────────────┐            ┌──────────────────────────────┐
│  Stage 3a: Z3 FFI      │            │  Stage 3b: Lean 4 Kernel     │
│  via ir_to_smt.nim     │            │  via ir_to_lean.nim          │
│                        │            │                              │
│  IR → SMT-LIB2 변환    │            │  IR → Lean 4 소스 변환       │
│  QF_BV 로직 설정       │            │  termination_by 자동 삽입    │
│  Z3 FFI로 in-process   │            │  Lean sandbox에서 lake build │
│  검증                  │            │  검증                       │
│                        │            │                              │
│  결과:                 │            │  결과:                       │
│  - unsat → 검증 완료   │            │  - build 성공 → 검증 완료    │
│  - unknown → Lean 폴백 │            │  - build 실패 → 실패         │
│  - sat → 반례 발견     │            │  - sorry 발견 → 하드 실패    │
└────────┬───────────────┘            └──────────┬─────────────────┘
         │                                       │
         └──────────────┬────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────────────┐
│         Stage 4: 교차 검증 (Cross-Validation)                      │
│  src/verification/cross_validation.nim                             │
│  - 동일한 IR에서 파생된 Z3/Lean 출력의 구조적 일관성 확인          │
│  - 함수명, 파라미터 집합, 출력 구조 일치 검증                      │
│  - IR digest (SHA-256)로 감사 추적 생성                            │
└─────────────────────────┬───────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────────┐
│         Stage 5: 인증서 상태 분류 (Certificate Classification)       │
│  src/core/types/verification_tier.nim                              │
│  src/core/types/certificate_types.nim                              │
│                                                                     │
│  ┌──────────┬──────────────┬────────────────────────────────┐      │
│  │ Z3 결과  │ Lean 결과    │ 인증서 상태                     │      │
│  ├──────────┼──────────────┼────────────────────────────────┤      │
│  │ unsat    │ pass         │ certGreen (vtDual)             │      │
│  │ unsat    │ —            │ certZ3Verified (vtZ3Only)      │      │
│  │ —        │ pass         │ certLeanVerified (vtLeanOnly)  │      │
│  │ unsat    │ fail         │ certRed (vtNone)               │      │
│  │ unknown  │ —            │ Lean으로 폴백                  │      │
│  │ sat      │ —            │ certRed (반례 발견)            │      │
│  └──────────┴──────────────┴────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 3. VerificationTier 열거형

**소스**: `src/core/types/verification_tier.nim`

```nim
type
  VerificationTier* = enum
    vtNone      ## Neither Z3 nor Lean verified (초기/실패 상태)
    vtZ3Only    ## Z3 SMT 솔버에 의해서만 검증됨 (decidable fragment)
    vtLeanOnly  ## Lean 4 키ernel에 의해서만 검증됨 (higher-order structural)
    vtDual      ## Z3와 Lean 모두에 의해서 검증됨 (최고 신뢰도)
```

### 3.1 핵심 함수

| 함수 | 설명 | 순수(pure) |
|------|------|-----------|
| `tierFromResults(z3Success, leanSuccess)` | 솔버 결과 → VerificationTier 매핑 | O |
| `tierLabel(t)` | 사람이 읽을 수 있는 레이블 반환 | O |
| `isValid(t)` | vtNone가 아니면 true | O |
| `requiresFallback(t)` | vtZ3Only일 때 true (Lean 폴백 필요) | O |

### 3.2 진리표

```
Z3      │ Lean    │ VerificationTier │ CertificateStatus
────────┼─────────┼──────────────────┼───────────────────
true    │ true    │ vtDual           │ certGreen
true    │ false   │ vtZ3Only         │ certZ3Verified
false   │ true    │ vtLeanOnly       │ certLeanVerified
false   │ false   │ vtNone           │ certRed
```

> **정합성 참고**: `certDualVerified`는 과거 spec 잔재(dead legacy alias)이며 실제로 발급되지 않는다.
> 이중(dual) 보증의 정식 상태는 **`certGreen`** 이다 (코드상 `tierToStatusString(vtDual) == "certGreen"`).
> `certGreen`의 P0 불변식: `status == "certGreen" ⇒ z3Passed == true ∧ leanKernelVerified == true`
> (`statusConsistentWithEvidence`). Z3-only는 `certZ3Verified`로만 표현되며 절대 certGreen이 되지 않는다.

---

## 4. Z3 솔버 레이어

**소스**: `src/verification/solver/z3_bindings.nim`

### 4.1 FFI 구성

Z3 바인딩은 3가지 빌드 모드를 지원한다:

| 플래그 | 동작 |
|--------|------|
| `-d:ffiEnabled` | FFI 모드 강제 활성화 (libz3.so 필요) |
| `-d:ffiDisabled` | CLI 모드 강제 활성화 (스텁만 사용) |
| (기본) | 자동 감지: libz3.so 존재 시 FFI, 아니면 스텁 |

### 4.2 검증 가능한 속성

Z3 QF_BV(Quantifier-Free BitVector) 로직으로 검증 가능:
- 정수 연산의 오버플로/언더플로 없음
- 부호 있는 비교 연산 정확성
- 비트벡터 산술 정확성
- 함수 정의의 자기 일관성

### 4.3 제약 조건

- Z3 컨텍스트는 **스레드 안전하지 않음** (Z3 요구사항). 스레드당 1개 사용.
- `{.acyclic.}` pragma로 순환 참조 방지.
- 명시적 `close()` 호출 필요 (RAII 패턴).

---

## 5. Lean 4 검증 레이어

**소스**: `src/cli/lean_verify_cmd.nim`, `src/verification/lean_build_sandbox.nim`

### 5.1 검증 흐름

```
LeanVerifyResult = runLeanVerify(timeout)
  └→ verifyWithSandbox(timeout)
       ├→ createSandbox()      # 격리된 빌드 환경 생성
       ├→ buildInSandbox()     # lake build 실행
       └→ destroySandbox()     # 정리
  └→ classifyOutcome(result)
       ├→ leanVerifySuccess
       ├→ leanVerifySorryFound    # 하드 실패
       ├→ leanVerifyBuildFailed
       └→ leanVerifySandboxFailed
```

### 5.2 LeanVerifyOutcome 분류

```nim
type
  LeanVerifyOutcome* = enum
    leanVerifySuccess          # 빌드 성공, sorry 없음
    leanVerifySorryFound       # sorry 발견 — 하드 실패
    leanVerifyBuildFailed      # lake build 비-영종료
    leanVerifySandboxFailed    # 샌드박스 생성/실행 오류
```

### 5.3 Sorry 감지

`sorry` 키워드는 Lean 증명에서 사실상 "증명 안 함"을 의미하므로,
Axiom 파이프라인에서는 **하드 실패**로 처리한다.
이 기능은 `sorry_audit_gate`와 중복 검증을 제공한다.

---

## 6. 교차 검증 메커니즘 (Cross-Validation)

**소스**: `src/verification/cross_validation.nim`

### 6.1 목적

동일한 IR에서 파생된 SMT-LIB2와 Lean 4 출력이 구조적으로 일관되는지 확인한다.
이는 두 백엔드가 동일한 함수를 동일하게 인코딩하는지를 보장하는 **방어적 검증**이다.

### 6.2 검증 항목

| 검사 | SMT-LIB2 기준 | Lean 4 기준 |
|------|--------------|-------------|
| 출력 비어있지 않음 | check | check |
| 함수명 존재 | `(define-fun name ...)` | `def name` |
| 파라미터 존재 | 모든 파라미터명 포함 | 모든 파라미터명 포함 |

### 6.3 IR Digest

동일한 IR → 동일한 정규 문자열 → 동일한 SHA-256 해시.
감사 추적을 위한 결정론적 다이제스트를 생성한다.

```
IRFuncDef → serializeIRFuncDef() → SHA-256 → irDigest
```

### 6.4 CrossValidationStatus

```nim
type
  CrossValidationStatus* = enum
    cvsConsistent    # 양쪽 백엔드 모두 유효하고 일치
    cvsZ3Failed      # SMT-LIB2 생성 실패 또는 빈 출력
    cvsLeanFailed    # Lean 4 생성 실패 또는 빈 출력
    cvsBothFailed    # 양쪽 모두 실패
    cvsDiverged      # 양쪽 모두 출력했지만 구조 검사 불일치
```

---

## 7. 인증서 상태 (CertificateStatus)

**소스**: `src/core/types/certificate_types.nim`

### 7.1 상태 계층

```
 certDualVerified (최고 신뢰도)
     │
     ├── certZ3Verified    (Z3만 통과)
     ├── certLeanVerified  (Lean만 통과)
     │
 certVerifiedAxiom (기존 시스템)
 certPseudoVerified
 certGreen
     │
 certYellow (부분 검증)
     │
 certPending (대기 중)
 certStale   (만료)
 certRed     (실패)
```

### 7.2 VerificationTier 필드

`FunctionCertificate` 구조체에 `verificationTier: VerificationTier` 필드가 추가되어,
각 인증서가 어떤 검증 단계를 통과했는지 기록한다.

---

## 8. 게이트 통합

### 8.1 관련 게이트

| 게이트 ID | 레이어 | 설명 |
|-----------|--------|------|
| `sorry-audit-gate` | functional | proofs/ 디렉토리의 .lean 파일에서 sorry 스캔 |
| `lean-kernel` | functional | Lean 4 키널 검증 (sandbox 빌드) |
| `z3-ffi-health` | functional | Z3 FFI 사용 가능성 확인 |
| `lean-z3-consensus-gate` | functional | Z3/Lean 합의 검증 |

### 8.2 실행 순서

```
pre-push:
  cli-build
    → sorry-audit-gate
      → lean-kernel
    → z3-ffi-health
```

---

## 9. 참고 문서

- `docs/spec/gate_registry.md` — 게이트 레지스트리 형식 및 규칙
- `docs/spec/tcb_formal_verification_roadmap.md` — TCB 공식 검증 로드맵
- `docs/spec/bmc_core.md` — 유계 모델 검증 코어
- `docs/spec/axiom_core_ir_spec.md` — Axiom Core IR 사양
- `docs/spec/syntactic_guard_spec.md` — 구문 경계 사양
- `docs/spec/axiom_constraint_spec.md` — 제약 조건 사양
- `src/verification/cross_validation.nim` — 교차 검증 구현
- `src/core/types/verification_tier.nim` — 검증 티어 타입
- `src/core/types/certificate_types.nim` — 인증서 타입
