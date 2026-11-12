# Axiom Core IR 사양 (Specification)

**생성일**: 2026-06-28
**상태**: Phase 4A/6B — IR 정규화 + 양방향 변환 완료
**소스**: `src/core/trusted/axiom_ir.nim`, `src/core/trusted/axiom_ir_helpers.nim`,
        `src/core/trusted/ir_to_smt.nim`, `src/core/trusted/ir_to_lean.nim`
**AGENTS.md 참조**: §0.1 (프로젝트 목적), §0.2 (1원칙)

---

## 1. 개요

Axiom Core IR(Intermediate Representation)은 Nim AST와 백엔드(SMT-LIB2, Lean 4) 사이에 위치하는
**최소화된 순수 함수형 중간 표현**이다. 양쪽 백엔드가 이 단일 정규화 지점에서 파생되므로,
**의미적 분기(semantic divergence)가 원천적으로 차단된다**.

### 1.1 설계 원칙

- 모든 타입은 값형(value-like): `{.acyclic.}` ref object (공유가 필요한 곳만)
- 모든 프로시저는 `func` (부수 효과 없음)
- 모든 표현식은 variant object 트리로 구조화
- 결정론적 직렬화: 동일 IR → 동일 정규 문자열 → 동일 해시

---

## 2. 타입 시스템 (IRType)

### 2.1 IRTypeKind

```nim
type
  IRTypeKind* = enum
    irtBitVec64    ## 기계 정수 (64비트, 수학적 Int가 아님)
    irtBool        ## 불리언
    irtList        ## 요소 타입을 가지는 리스트
```

### 2.2 IRType

```nim
type
  IRType* {.acyclic.} = ref object
    case kind*: IRTypeKind
    of irtBitVec64: discard
    of irtBool:     discard
    of irtList:     elemType*: IRType   # 재귀적 정의
```

### 2.3 생성 함수

| 함수 | 설명 |
|------|------|
| `irTypeBitVec64()` | 64비트 비트벡터 타입 생성 |
| `irTypeBool()` | 불리언 타입 생성 |
| `irTypeList(elem)` | 리스트 타입 생성 (재귀 가능) |

---

## 3. 연산자 종류

### 3.1 이항 연산자 (BinOpKind)

| 열거형 값 | SMT-LIB2 기호 | Lean 4 기호 | 설명 |
|-----------|--------------|-------------|------|
| `boAdd` | `bvadd` | `+` | 덧셈 (래핑/부호 있음) |
| `boSub` | `bvsub` | `-` | 뺄셈 |
| `boMul` | `bvmul` | `*` | 곱셈 |
| `boDiv` | `bvsdiv` | `/ₛ` | 부호 있는 나눗셈 |
| `boRem` | `bvsrem` | `%ₛ` | 부호 있는 나머지 |
| `boLt` | `bvslt` | `<` | 부호 있는 비교 |
| `boLe` | `bvsle` | `≤` | 부호 있는 이하 |
| `boGt` | `bvsgt` | `>` | 부호 있는 초과 |
| `boGe` | `bvsge` | `≥` | 부호 있는 이상 |
| `boAnd` | `and` | `&&` | 논리곱 |
| `boOr` | `or` | `\|\|` | 논리합 |
| `boEq` | `=` | `==` | 동등성 (해석 불가) |
| `boLtU` | `bvult` | `BitVec.ult` | 무부호 비교 — u64 도메인 전제 수반 (아래 주석) |


**`boLtU` (v1.3, append-only)** — 열거 끝(`boEq` 뒤)에 추가된 무부호 엄밀 less-than.
와이어 서수는 16(`ir_binary_codec.nim` 도메인 상한 동시 확장). 의미: 고정 x86_64 대상
(SemanticProfileV1 `x86_64|64|64`)의 u64 도메인 `[0, 2^64)`에서의 Int 수학적 순서 —
해당 도메인에서 Int 순서와 무부호 비트 순서가 일치한다는 것이 Denotation 브리지 정리의
내용이며, 도메인 전제는 aoTypeDerived 범위 전제 기구(`rust_certified_subset.md` §4
`boLtU` 노트)가 확보한다. 방출: SMT `bvult`, Lean(BitVec 렌더러) `BitVec.ult`
(실측 kernel-clean — `#print axioms` = `[propext]`), Lean(Int 렌더러) `<` (도메인 가설
하에서 무부호 순서와 동치), replay 무부호 비트 패턴 비교. Int-도메인 폴백은
`ult ↔ 무부호 순서` 동등성 정리의 Lean 커널 검증 없이는 금지.

### 3.2 단항 연산자 (UnaryOpKind)

| 열거형 값 | SMT-LIB2 기호 | Lean 4 기호 | 설명 |
|-----------|--------------|-------------|------|
| `uoNot` | `not` | `!` | 불리언 부정 |
| `uoBvNot` | `bvnot` | `~~~` | 비트 단위 부정 |
| `uoBvNeg` | `bvneg` | `-'` | 산술 부정 |

---

## 4. 표현식 트리 (IRExpr)

### 4.1 IRExprKind

```nim
type
  IRExprKind* = enum
    irLit       ## 정수 리터럴
    irVar       ## 변수 참조
    irLet       ## let 바인딩: let name = val in body
    irIf        ## if-then-else
    irCase      ## case/패턴 매칭 (BitVec64 값 기준)
    irCall      ## 명명된 함수 호출
    irBinOp     ## 이항 연산
    irUnaryOp   ## 단항 연산
    irRecCall   ## 자기 재귀 호출
```

### 4.2 IRExpr 필드 상세

| 노드 종류 | 필드 | 타입 | 설명 |
|-----------|------|------|------|
| `irLit` | `litVal` | `int64` | 리터럴 값 (부호 도메인 [−2^63, 2^63−1]) |
| `irLit` | `litU64` | `uint64` | u64 도메인 리터럴 값 ([2^63, 2^64−1], `work/u64-add-2026-11-02`) |
| `irVar` | `varName` | `string` | 변수명 |
| `irVar` | `varType` | `IRType` | 변수 타입 |
| `irLet` | `letName` | `string` | 바인딩 이름 |
| `irLet` | `letVal` | `IRExpr` | 바인딩 값 |
| `irLet` | `letBody` | `IRExpr` | 본문 표현식 |
| `irIf` | `ifCond` | `IRExpr` | 조건 |
| `irIf` | `ifThen` | `IRExpr` | 참 분기 |
| `irIf` | `ifElse` | `IRExpr` | 거짓 분기 |
| `irCase` | `caseScrutinee` | `IRExpr` | 조사 표현식 |
| `irCase` | `caseBranches` | `seq[CaseBranch]` | 분기 목록 |
| `irCase` | `caseDefault` | `IRExpr` | 기본 분기 (nil = 완전 매칭) |
| `irCall` | `callName` | `string` | 함수명 |
| `irCall` | `callArgs` | `seq[IRExpr]` | 인자 목록 |
| `irBinOp` | `binOp` | `BinOpKind` | 연산 종류 |
| `irBinOp` | `binLhs` | `IRExpr` | 왼쪽 피연산자 |
| `irBinOp` | `binRhs` | `IRExpr` | 오른쪽 피연산자 |
| `irUnaryOp` | `unaryOp` | `UnaryOpKind` | 연산 종류 |
| `irUnaryOp` | `unaryArg` | `IRExpr` | 피연산자 |
| `irRecCall` | `recArgs` | `seq[IRExpr]` | 재귀 호출 인자 |

> **두 도메인 분리** (`work/u64-add-2026-11-02`): 부호 도메인 [−2^63, 2^63−1]은 `litVal`(int64, 정준 부호 판독)로, u64 도메인 [2^63, 2^64−1]은 u64 표현(`litU64`)으로만 담는다 — 2^63 이상 값은 u64 표현으로만 담고 `litVal` 재해석으로는 절대 담지 않는다(와이어 태그 `0x0F` = `irLitU64`, 8바이트 리틀 엔디안; 기존 `0x01` 태그는 상위 비트 설정 시 무효 — 구 디코더는 Nim·Lean 양측 모두 fail-closed). 왕복 시험이 불변식을 기계 검증한다.

### 4.3 CaseBranch

```nim
type
  CaseBranch* = object
    pattern*: int64       ## 매칭 값
    body*: IRExpr         ## 분기 표현식
```

---

## 5. 함수 정의 (IRFuncDef)

```nim
type
  IRFuncParam* = object
    name*: string        ## 파라미터 이름
    ty*: IRType          ## 파라미터 타입

  IRFuncDef* = object
    name*: string                ## 함수명
    params*: seq[IRFuncParam]    ## 파라미터 목록
    retType*: IRType             ## 반환 타입
    body*: IRExpr                ## 함수 본문
    isRecursive*: bool           ## 재귀 함수 여부
```

---

## 6. 오버플로 검사 (OverflowCheck)

```nim
type
  OverflowCheck* = enum
    ocNone            ## 오버플로 검사 없음
    oNoOverflow       ## 부호 있는 오버플로 없음을 assert
    oNoUnderflow      ## 부호 있는 언더플로 없음을 assert
    oNoWrap           ## 부호 없는 래핑 없음을 assert

  AnnotatedExpr* = object
    expr*: IRExpr
    overflow*: OverflowCheck
```

### 6.1 SMT-LIB2 생성 규칙

| 연산 | 검사 종류 | 생성되는 assert |
|------|-----------|----------------|
| `boAdd` | `oNoOverflow` | `(no_overflow_add l r)` + `(no_underflow_add l r)` |
| `boAdd` | `oNoUnderflow` | `(no_underflow_add l r)` |
| `boAdd` | `oNoWrap` | `(bvuge (bvadd l r) l)` |
| `boMul` | `oNoOverflow` | `(no_overflow_mul l r)` |
| `boMul` | `oNoUnderflow` | `(no_underflow_mul l r)` |
| `boMul` | `oNoWrap` | `(bvuge (bvmul l r) l)` |

---

## 7. IR → SMT-LIB2 매핑

**소스**: `src/core/trusted/ir_to_smt.nim`

### 7.1 타입 매핑

| IRType | SMT-LIB2 sort |
|--------|---------------|
| `irtBitVec64` | `(_ BitVec 64)` |
| `irtBool` | `Bool` |
| `irtList(T)` | `T의 sort` (QF_BV에 리스트 sort 없음) |

### 7.2 표현식 매핑

| IRExprKind | SMT-LIB2 변환 |
|------------|---------------|
| `irLit(v)` | `#x{hex16}` (16자리 헥스) |
| `irVar(name)` | `name` (심볼) |
| `irLet(name, val, body)` | `(let ((name val)) body)` |
| `irIf(cond, then, else)` | `(ite cond then else)` |
| `irCase(scrutinee, branches, default)` | 중첩 `(ite (= scrutinee pattern) body ...)` |
| `irCall(name, args)` | `(name arg1 arg2 ...)` |
| `irBinOp(op, lhs, rhs)` | `(op_smt lhs rhs)` |
| `irUnaryOp(op, arg)` | `(op_smt arg)` |
| `irRecCall(args)` | `(rec arg1 arg2 ...)` |

### 7.3 완전한 SMT-LIB2 스크립트 구조

```smt2
(set-logic QF_BV)
(declare-fun param1 () (_ BitVec 64))
(declare-fun param2 () Bool)
(define-fun funcName ((param1 (_ BitVec 64)) (param2 Bool)) (_ BitVec 64)
  <body>)
(assert (= (funcName param1 param2) <body>))
(check-sat)
```

### 7.4 Case 매칭 역직렬화

`irCase`는 SMT-LIB2에 `(ite ...)` 중첩으로 변환된다:

```nim
# 3개 분기 + 기본값:
(ite (= scrutinee #x0000000000000003) body3
  (ite (= scrutinee #x0000000000000002) body2
    (ite (= scrutinee #x0000000000000001) body1
      default)))
```

---

## 8. IR → Lean 4 매핑

**소스**: `src/core/trusted/ir_to_lean.nim`

### 8.1 타입 매핑

| IRType | Lean 4 타입 |
|--------|------------|
| `irtBitVec64` | `BitVec 64` |
| `irtBool` | `Bool` |
| `irtList(T)` | `List (T의 Lean 타입)` |

### 8.2 표현식 매핑

| IRExprKind | Lean 4 변환 |
|------------|------------|
| `irLit(v)` | `v` (십진수 리터럴) |
| `irVar(name)` | `name` |
| `irLet(name, val, body)` | `let name := val\n  body` |
| `irIf(cond, then, else)` | `if cond then\n  then_expr\nelse\n  else_expr` |
| `irCase(scrutinee, branches, default)` | `match scrutinee with\n  \| p => body ...` |
| `irCall(name, args)` | `name arg1 arg2 ...` |
| `irBinOp(op, lhs, rhs)` | `(op_lean lhs rhs)` |
| `irUnaryOp(op, arg)` | `(op_lean arg)` |
| `irRecCall(args)` | `__self__ arg1 arg2 ...` (이름 해석 후 실제 함수명으로 치환) |

### 8.3 재귀 함수 처리 (Termination Strategies)

**소스**: `src/core/trusted/ir_to_lean.nim` — `TerminationStrategy`

```nim
type
  TerminationStrategy* = enum
    tsNone          # 비재귀 함수 — 별도 처리 불필요
    tsStructural    # 구조적 하강 — Lean이 자동 감지
    tsNumeric       # 수치적 하강 — termination_by + decreasing_by omega
    tsFallback      # 폴백 — partial def + termination_by sorry
```

#### 전략 1: 구조적 하강 (Structural Descent)

리스트 파라미터의 재귀에서 Lean이 자동으로 종료를 증명한다.

```lean
-- Lean이 자동 감지:
def mapList (f : α → β) (xs : List α) : List β :=
  match xs with
  | [] => []
  | x :: xs' => f x :: mapList f xs'
```

감지 기준:
1. 파라미터 중 `List` 타입이 있으면 `tsStructural`
2. 본문에 `irCase` 패턴 매칭이 있으면 `tsStructural`

#### 전략 2: 수치적 하강 (Numeric Descent)

정수 파라미터가 본문에서 `-1` 되는 경우:

```nim
# detectNumericDecrement: boSub && lhs == paramName && rhs == litVal(1)
```

```lean
-- Lean 4 출력:
def countdown (n : BitVec 64) : BitVec 64 :=
  if n == 0 then 0
  else countdown (n - 1)
termination_by n
decreasing_by omega
```

#### 전략 3: 폴백 (Fallback)

자동 종료 분석이 불가능한 경우:

```lean
-- partial def + termination_by sorry
partial def unknownRec (n : BitVec 64) : BitVec 64 :=
  sorry
termination_by sorry
```

`terminationUnchecked: true`로 메타데이터에 기록된다.

### 8.4 Lean 모듈 출력 구조

```lean
import Axiom.IR.Types
-- (선택적 추가 import)

def funcName (param1 : BitVec 64) (param2 : Bool) : BitVec 64 :=
  <body>
```

---

## 9. 정규 직렬화 (Canonical Serialization)

**소스**: `src/verification/cross_validation.nim`

### 9.1 직렬화 형식

```
IRFuncDef →
  FUNC(name,(p1:TYPE1,p2:TYPE2):RETTYPE=EXPR,rec=BOOL)

IRExpr →
  L(value)                              -- irLit
  V(name:TYPE)                          -- irVar
  LET(name=VAL|BODY)                    -- irLet
  IF(COND?THEN:ELSE)                    -- irIf
  CASE(SCRUT{pat=>BODY,...|D=>DEF})     -- irCase
  CALL(name,[ARGS])                     -- irCall
  BIN(OP,LHS,RHS)                      -- irBinOp
  UN(OP,ARG)                            -- irUnaryOp
  REC([ARGS])                           -- irRecCall
```

### 9.2 Digest 계산

```
IRFuncDef → serializeIRFuncDef() → SHA-256 → irDigest (hex)
```

동일한 IR 구조는 항상 동일한 digest를 생성한다 (결정론적).

---

## 10. 헬퍼 함수 ( Shortcut Constructors )

**소스**: `src/core/trusted/axiom_ir_helpers.nim`

| 함수 | 설명 |
|------|------|
| `irLit(v)` | 정수 리터럴 |
| `irVar(name, ty)` | 변수 참조 |
| `irLet(name, val, body)` | let 바인딩 |
| `irIf(cond, then, else)` | 조건 분기 |
| `irBinOp(op, lhs, rhs)` | 이항 연산 |
| `irUnaryOp(op, arg)` | 단항 연산 |
| `irCall(name, args)` | 함수 호출 |
| `irRecCall(args)` | 자기 재귀 호출 |
| `irCase(scrutinee, branches, default)` | 패턴 매칭 |
| `irAdd(a, b)` | 덧셈 shorthand |
| `irSub(a, b)` | 뺄셈 shorthand |
| `irMul(a, b)` | 곱셈 shorthand |
| `irDiv(a, b)` | 나눗셈 shorthand |
| `irRem(a, b)` | 나머지 shorthand |
| `irLt(a, b)` ~ `irGe(a, b)` | 비교 shorthand |
| `irEq(a, b)` | 동등성 shorthand |
| `irAnd(a, b)`, `irOr(a, b)` | 논리 연산 shorthand |
| `irNot(a)`, `irBvNot(a)`, `irBvNeg(a)` | 단항 shorthand |
| `irFuncDef(name, params, ret, body, isRec)` | 함수 정의 생성 |

---

## 11. 참고 문서

- `src/core/trusted/axiom_ir.nim` — IR 타입 정의 (SSOT)
- `src/core/trusted/axiom_ir_helpers.nim` — IR 생성/출력 헬퍼
- `src/core/trusted/ir_to_smt.nim` — IR → SMT-LIB2 변환기
- `src/core/trusted/ir_to_lean.nim` — IR → Lean 4 변환기
- `src/verification/cross_validation.nim` — 교차 검증
- `docs/spec/two_phase_verification.md` — 2단계 검증 파이프라인 개요
- `docs/spec/syntactic_guard_spec.md` — 구문 경계 사양
- `docs/spec/axiom_constraint_spec.md` — 제약 조건 사양
