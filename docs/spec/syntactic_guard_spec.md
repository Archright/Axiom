# 구문 경계 사양 (Syntactic Guard Specification)

**생성일**: 2026-06-28
**상태**: Phase 2B/6B — 컴파일 타임 순수 함수성 강제 완료
**소스**: `src/core/trusted/pure_func_guard.nim`
**AGENTS.md 참조**: §0.2 (1원칙 — Ideal, Elegant, Fundamental, Deterministic)

---

## 1. 개요

구문 경계(Syntactic Guard)는 `{.axiom.}` pragma가 부착된 Nim `func`의 AST body를
**컴파일 타임에 재귀적으로 순회**하여, 비순수 함수적 구조를 **즉시 차단**하는 컴파일러 매크로이다.

### 1.1 설계 원칙 (AGENTS.md §0.2)

| 원칙 | 구현 |
|------|------|
| **Ideal** | 컴파일 타임에 위반을 방지 (런타임 검사 불필요) |
| **Elegant** | Nim 네이티브 `std/macros` AST walk 사용 |
| **Fundamental** | 화이트리스트 접근 — 알려진 나쁜 노드만 거부 |
| **Deterministic** | 동일 AST → 동일 판정 (결정론적) |

### 1.2 핵심 소스

```nim
# src/core/trusted/pure_func_guard.nim
import std/macros

const forbiddenNodeKinds* = {
  nnkVarSection,   # var 선언 — 순수 함수에서 가변성 금지
  nnkWhileStmt,    # while 루프 — 무한 반복 금지
  nnkForStmt,      # for 루프 — 명령형 반복 금지
  nnkAsgn,         # 대입 (x = expr) — 가변성 금지
}
```

---

## 2. 금지된 AST 노드 종류 (Forbidden Node Kinds)

### 2.1 목록

| NimNodeKind | 표시명 | 금지 사유 | 대체 허용 |
|-------------|--------|----------|----------|
| `nnkVarSection` | `var` | 순수 함수에서 가변 상태 허용 안 됨 | `nnkLetSection` (let 바인딩) |
| `nnkWhileStmt` | `while` | 무한 반복 가능성 — 종료 보장 불가 | 구조적 재귀 |
| `nnkForStmt` | `for` | 명령형 반복 — 순수 함수 모델에 부합 안 됨 | `nnkCase` + 재귀 |
| `nnkAsgn` | `assignment` | 기존 변수 변경 — 순수 함수에서 금지 | `nnkLetSection` + 재귀적 바인딩 |

### 2.2 검출 메커니즘

```nim
proc walkAndGuard*(body: NimNode, funcName: string) {.compileTime.} =
  ## 재귀적 AST 순회 및 금지 노드에서 CompileError 발생
  if body.kind in forbiddenNodeKinds:
    error("AXIOM_VIOLATION: func '" & funcName & "' contains '" &
          nodeKindDisplayName(body.kind) &
          "' — {.axiom.} requires pure functional style", body)
  for child in body:
    walkAndGuard(child, funcName)
```

- `{.compileTime.}` — AST 분석은 컴파일 타임에만 수행
- `error()` — Nim 컴파일러의 `CompileError`를 발생시켜 빌드 중단

### 2.3 오류 메시지 형식

```
AXIOM_VIOLATION: func '<함수명>' contains '<위반 구문 종류>' — {.axiom.} requires pure functional style
```

**예시**:
```
AXIOM_VIOLATION: func 'counter' contains 'var' — {.axiom.} requires pure functional style
AXIOM_VIOLATION: func 'loop' contains 'while' — {.axiom.} requires pure functional style
AXIOM_VIOLATION: func 'mutate' contains 'assignment' — {.axiom.} requires pure functional style
```

---

## 3. 허용된 구조 (Allowed Constructs)

구문 경계는 **화이트리스트 접근**을 사용한다. 알려진 나쁜 노드만 거부하며,
허용된 구조는 모두 통과시킨다.

### 3.1 허용된 AST 노드 종류

| NimNodeKind | 설명 | 사용 예 |
|-------------|------|---------|
| `nnkLetSection` | let 바인딩 | `let y = x + 1` |
| `nnkIfExpr` | if 식 (표현식) | `if x > 0 then x else 0` |
| `nnkIfStmt` | if 문 (명령문) | `if cond: expr1 else: expr2` |
| `nnkCall` | 함수 호출 | `myFunc(x, y)` |
| `nnkInfix` | 중위 연산자 | `x + y`, `a == b` |
| `nnkPrefix` | 전위 연산자 | `not a`, `-x` |
| `nnkCaseStmt` | case 패턴 매칭 | `case x of ...` |
| `nnkStmtList` | 명령문 목록 | 코드 블록 |
| `nnkReturnStmt` | 반환 | `return expr` |
| `nnkIntLit` / `nnkStrLit` | 리터럴 | `42`, `"hello"` |

### 3.2 재귀 패턴

구문 경계는 재귀 호출을 명시적으로 허용한다:

```nim
# 허용: 구조적 재귀
func factorial(n: int): int {.axiom.} =
  if n <= 1: 1
  else: n * factorial(n - 1)

# 허용: 리스트 재귀
func length(xs: List[int]): int {.axiom.} =
  case xs of
  | Nil => 0
  | Cons(_, tail) => 1 + length(tail)
```

---

## 4. 사용 방법 (Usage Patterns)

### 4.1 블록 가드 (Block Guard)

```nim
func myFunc(x: int): int {.axiom.} =
  pureFuncGuard:
    let y = x + 1
    y
```

### 4.2 정의 프라그마 (Definition Pragma)

```nim
func myFunc(x: int): int {.pureFuncGuard.} =
  let y = x + 1
  y
```

### 4.3 통합 가드 (axiomImpl)

```nim
func myFunc(x: int): int {.axiomImpl.} =
  let y = x + 1
  y
```

---

## 5. {.axiom.} 프라그마 통합

### 5.1 동작 원리

`{.axiom.}` pragma는 Nim AST에서 `{.pureFuncGuard.}`로 변환되거나,
`axiomImpl` 매크로 내부에서 자동으로 `pureFuncGuard`를 호출한다.

### 5.2 검증 대상

- **{.axiom.}** 프라그마가 부착된 모든 `func`
- **{.pureFuncGuard.}** 프라그마가 부착된 모든 `func`
- **{.axiomImpl.}** 매크로의 본문

### 5.3 제외 대상

- 일반 `proc` — 효과 시스템이 이미 관리
- `{.noSideEffect.}` 없는 일반 `func` — Nim 자체 검증
- `macro` / `template` — 메타프로그래밍 컨텍스트

---

## 6. 효과 시스템과의 관계

### 6.1 Nim 효과 시스템 보완

Nim의 효과 시스템은 `proc`의 부수 효과를 추적하지만, `func`에 대한 검증은 제한적이다.
구문 경계는 이 갭을 **AST 수준에서 보완**한다:

```
Nim 효과 시스템          구문 경계
─────────────────     ─────────────────────
proc → 효과 추적       {.axiom.} func → AST 구조 검증
func → 부분 검증       var/while/for/asgn 컴파일 에러
{.noSideEffect.} → TCB  구문 경계 → TCB 불필요
```

### 6.2 TCB (Trusted Computing Base) 관계

구문 경계 자체는 `{.compileTime.}` 매크로이므로 **TCB에 포함되지 않는다**.
`std/macros` 모듈은 Nim 언어의 신뢰할 수 있는 부분이다.

구문 경계를 통과한 함수는 추가적으로 **Z3/Lean 2단계 검증**을 받는다.
이를 통해 **완전한 공식 검증 체인**이 구성된다:

```
Nim func → 구문 경계(컴파일 타임) → Axiom Core IR → {Z3 + Lean}
```

---

## 7. 판정 흐름도

```
{.axiom.} func 호출
     │
     ▼
AST body를 pureFuncGuard에서 수신
     │
     ▼
walkAndGuard(body, funcName) 호출
     │
     ▼
body.kind in forbiddenNodeKinds?
     │
     ├── YES → CompileError (AXIOM_VIOLATION)
     │          빌드 중단
     │
     └── NO → 모든 자식 노드에 재귀 순회
                │
                ▼
              모든 노드 통과?
                │
                ├── NO → CompileError (자식에서 발견)
                │
                └── YES → 통과
                           │
                           ▼
                     Axiom Core IR로 변환
                           │
                           ▼
                     Z3/Lean 검증 진행
```

---

## 8. 제한 사항

### 8.1 검출 불가능한 항목

구문 경계는 AST 노드 종류만 검사하므로 다음은 검출하지 못한다:

| 항목 | 설명 | 후속 검증 레이어 |
|------|------|-----------------|
| 외부 IO 함수 호출 | `echo`, `writeFile` 등 | Nim 효과 시스템 (`{.raises: [].}`) |
| 전역 상태 접근 | 전역 `var` | 구조적 안전 게이트 |
| 무한 재귀 | 종료 조건 없는 재귀 | Z3/Lean 종료 분석 |
| 정확성 | 함수가 올바르게 동작하는지 | Z3/Lean 기능적 검증 |

### 8.2 확장 고려 사항

미래에 다음 검증이 추가될 수 있다:
- `nnkAsgn` 대신 모든 변형 대입 검출
- 허용된 함수 호출 allowlist
- I/O 함수 시그니처 검출

---

## 9. 게이트 통합

구문 경계는 **컴파일 타임에 자동 실행**되므로 별도의 게이트 항목이 불필요하다.
`{.axiom.}` pragma가 사용된 코드가 컴파일될 때마다 자동으로 검증된다.

구문 경계를 통과한 코드만이 Axiom Core IR로 변환되어 후속 파이프라인에 진입한다:

```
pure_func_guard (컴파일 타임)
    → axiom_ir.nim (AST → IR 변환)
    → ir_to_smt.nim + ir_to_lean.nim (양방향 변환)
    → Z3 FFI + Lean 4 sandbox (검증)
    → cross_validation.nim (교차 검증)
    → FunctionCertificate (인증서)
```

---

## 10. 참고 문서

- `src/core/trusted/pure_func_guard.nim` — 구문 경계 구현 (SSOT)
- `docs/spec/two_phase_verification.md` — 2단계 검증 파이프라인 개요
- `docs/spec/axiom_core_ir_spec.md` — Axiom Core IR 사양
- `docs/spec/tcb_formal_verification_roadmap.md` — TCB 공식 검증 로드맵
- `docs/spec/nim_effect_system_quirks.md` — Nim 효과 시스템 기행
- AGENTS.md §0.2 — 1원칙 (Ideal, Elegant, Fundamental, Deterministic)
- AGENTS.md §0.6 — Static First Enforcement
