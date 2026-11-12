# Self-Enforcing Architecture 설계 주장 Context7 검토 보고서

> Date: 2026-06-13
> Method: Context7 MCP (`/nim-lang/nim`) + 병렬 Subagent 코드베이스 분석
> Scope: 사용자가 제시한 4가지 컴파일타임 강제 아키텍처 설계

---

## Executive Summary

| # | 설계 주장 | 평가 | 핵심 결론 |
|---|-----------|------|-----------|
| 1 | Custom Pragma + Macro (`{.axiom: Pure.}`) | **지지** | Nim 언어/프로젝트 모두 지원. 단, `@axiom-effect` 코멘트는 실제로 존재하지 않음. 실제 마이그레이션 대상은 `axiom_ir.nim`의 문자열 기반 effect 탐지. |
| 2 | FFI Shield: distinct + ARC/ORC `=destroy` | **부분 지지** | `distinct`와 `cast(noSideEffect)`는 지지됨. `=destroy` RAII는 문서상 가능하나 `tree_sitter_ffi.nim`의 캐시 기반 생명주기와 충돌. |
| 3 | Compiler-Assisted Side-Effect Extractor | **핵심 메커니즘 반박** | `{.effects.}`는 **예외 효과만** 출력. side effect(IO) 분류는 출력하지 않음. 기존 `nimtry` BFS나 `proc→func` 변환 시도가 더 우수. |
| 4 | Composition Root compile-time guard | **부분 지지** | `staticRead` + `error()`/`{.fatal.}`로 텍스트 수준 import 완전성 검증은 가능. 그러나 `declared()`로 원격 파일의 import를 의미론적으로 검증하는 것은 불가. |

**총평**: 4가지 설계 방향 중 2개(1, 2)는 부분적/전면 적용 가능, 1개(3)는 핵심 메커니즘이 문서상 지원되지 않음, 1개(4)는 기능하나 의미론적 검증은 과대 주장.

---

## 1. 주장 1 — Custom Pragma + Macro 아키텍처

### 1.1 제안 내용

`# @axiom-effect` 코멘트를 버리고 `template axiom*(effectType: untyped) {.pragma.}`로 전환. `nimtry`가 `nnkPragma`를 순회해 추출하고, `hasNoSideEffects`로 검증하며, 불일치 시 `{.fatal.}`로 빌드 차단.

### 1.2 Context7 근거

#### Custom Pragma (`{.pragma.}`) — 지지

Nim 메뉴얼: custom typed pragmas are defined via `template name(args) {.pragma.}`. They do not affect code generation but **can be detected by macros**.

**프로젝트 선례**:

| Pragma | 파일 | 용도 |
|--------|------|------|
| `axiom_pure` | `contract_text_extractor.nim`, `smtlib2_sanitizer.nim`, `axiom_prelude.nim`, `tautology_prover.nim` | 순수 함수 마킹 |
| `axiom_dense_proof` | `complexity_index.nim`, `verified_axioms_*.nim`, `liquid_inference.nim`, `axiom_ir.nim` | proof density 마킹 |
| `axiomGcsafe` | `axiom_pragmas.nim` (정의), `judge.nim` (사용) | gcsafe contract |

#### nimtry의 Pragma 추출 — 지지

`src/gate/nimtry/nimtry_extract_part3_part2.nim`의 `extractPragmasV4()`는 이미 `nkPragma` 노드를 순회하며 `nkExprColonExpr` 형태의 pragma name/value를 추출.

```nim
let pragmas = n[4]
if not pragmas.isNil and pragmas.kind == nkPragma:
  while j < pragmas.safeLen:
    let pragmaNode = pragmas[j]
    if pragmaNode.kind == nkExprColonExpr and pragmaNode.safeLen >= 2:
      pragmaName = extractName(pragmaNode[0])
      pragmaValue = nodeToString(pragmaNode[1])
```

`nimtry_policy_lock.nim`은 이미 `pragma.pragmaName == "axiomImplements"` 필터를 사용 중.

#### `{.fatal.}` 빌드 차단 — 지지

Nim Manual: "The `fatal` pragma forces the compiler to output an error message and guarantees that compilation will be aborted."

프로젝트 선례: `src/core/test_support/pbt_gate.nim:19`.

#### `std/effecttraits` / `hasNoSideEffects` — 부분 지지

Context7: `std/effecttraits` was introduced in Nim 1.4.0 for "introspection of inferred effects, aiming to enable more precise async macros regarding possible exceptions."

**중요한 제한**: `effecttraits`는 **해결된 proc/type 심볼(resolved symbols)**에 대해 동작. 임의의 `untyped` AST 매크로 본문에서 직접 호출하기 어려움. 현재 프로젝트는 `axiom_ir.nim`에서 `"nosideeffect"` 문자열 스캔을 사용 중.

### 1.3 코드베이스 검증

- `@axiom-effect` 코멘트는 **존재하지 않음** (grep 결과 0건).
- 실제 존재하는 것: `# @axiom-hint: lean="..." smt="..."` (20+건, SMT/Lean invariant용, effect 아님).
- Effect 탐지는 `axiom_ir.nim` line 240-247의 문자열 스캔으로 수행.

### 1.4 평가

| 세부 주장 | 평가 |
|-----------|------|
| Custom Pragma 정의 가능 | ✅ 지지 |
| nimtry가 AST에서 pragma 추출 가능 | ✅ 지지 (이미 구현) |
| `{.fatal.}`로 빌드 차단 가능 | ✅ 지지 |
| `hasNoSideEffects`로 compile-time 검증 | ⚠️ 부분 지지 (resolved symbol 필요) |
| `@axiom-effect` 코멘트 대체 | ❌ 대상 없음 |

### 1.5 권고

Custom Pragma 아키텍처는 **실현 가능하고 권고**.

1. `src/core/trusted/axiom_pragmas.nim`에 `template axiomEffect*(effectType: typedesc) {.pragma.}` 추가 (기존 `axiomGcsafe` 패턴 따름).
2. `{.axiomEffect: Pure.}`, `{.axiomEffect: IoEffect.}` 형태로 마킹.
3. `nimtry_query.nim`에 effect pragma 검증 규칙 추가.
4. 위반 시 `error()` 또는 `{.fatal.}`로 빌드 차단.
5. `std/effecttraits`는 초기 구현에서 제외 — 문자열/pragma 조합으로 충분.

---

## 2. 주장 2 — FFI Shield: Distinct Types + ARC/ORC Lifecycle Hooks

### 2.1 제안 내용

C 포인터를 `distinct` 타입으로 감싸고 `=destroy` 훅으로 RAII. 공개 인터페이스는 `func` + `{.noSideEffect.}`, 낶부에서만 `{.cast(noSideEffect).}`로 FFI 부작용 격리.

### 2.2 Context7 근거

#### `distinct` 타입 — 지지

Nim 메뉴얼: `distinct` creates new types without subtype relationship. Explicit conversions supported.

**프로젝트 선례** (20+):
- `FilePath* = distinct string`
- `AxiomSafe*[T] = distinct T`
- `SorterNodeId* = distinct string`
- `NodeId* = distinct uint32`, `SymbolId* = distinct uint32`
- `ProofState*[S] = distinct SharedProofContext`

**Gap**: `tree_sitter_ffi.nim`은 여전히 raw `ptr object` 사용.

#### `=destroy` 훅 — 부분 지지

Nim 메뉴얼은 C API 객체를 `=destroy`로 감싸는 예제를 제공:

```nim
type MyObject* = object
  apiObject: pointer

proc `=destroy`(o: var MyObject) =
  if not isNil(o.apiObject):
    apiDecRefCounter(o.apiObject)
```

그러나 프로젝트의 `src/` 전체에서 `=destroy` 사용은 **0건**.

**tree_sitter_ffi.nim 적용 시 충돌**:
- 현재 `TSParser = ptr object` — ARC는 `ref` 타입을 추적하지 `ptr`은 추적하지 않음.
- `=destroy`가 작동하려면 `object` 낶부에 raw pointer를 넣어야 함 → API 변경.
- `treeCache` 기반 batch cleanup과 자동 소멸 모델 충돌.
- copy semantics 처리 필요 (double-free 방지).

#### `func`/`{.noSideEffect.}` + `{.cast(noSideEffect).}` — 지지

Nim 메뉴얼: `{.cast(noSideEffect).}: ...` is the preferred syntax for overriding side-effect analysis since Nim 1.4.

**프로젝트 선례**: `src/sieve/ast_inspector.nim:135-150`:

```nim
var parseRes: Result[XmlNode, string]
{.cast(noSideEffect).}:
  parseRes = parseNimRes(sourceCode)
if parseRes.isErr:
  return AstInspectionResult()
inspectAstNode(parseRes.get(), ...)
```

주석: "The cast is the I/O boundary seal: once parsing succeeds, all downstream work is pure func."

#### `{.acyclic.}` — 지지

이미 15+ 사용, `debt_blocker_gate`가 자동 검사.

### 2.3 평가

| 세부 주장 | 평가 |
|-----------|------|
| `distinct`로 C 포인터 감싸기 | ✅ 지지 |
| `=destroy` RAII | ⚠️ 문서상 지지, 그러나 현재 캐시 모델과 충돌 |
| `func` 인터페이스 + `cast(noSideEffect)` | ✅ 지지 (이미 사용 중) |
| `{.acyclic.}` | ✅ 지지 |

### 2.4 권고

1. **즉시**: `TSParser`, `TSTree`, `TSLanguage`를 `distinct` 타입으로 변환 — 타입 안전성 향상, 런타임 비용 0.
2. **단기**: `func` 인터페이스 + `cast(noSideEffect)` boundary seal 패턴을 tree-sitter FFI에 적용.
3. **중기**: `=destroy` RAII 도입은 캐시 생명주기 재설계가 필요하므로 별도 설계 태스크.
4. **금지**: `{.cast(noSideEffect).}` 남용 — AGENTS.md/GUARDIAN 정책 준수.

---

## 3. 주장 3 — Compiler-Assisted Side-Effect Extractor

### 3.1 제안 내용

`{.effects.}` pragma를 proc 본문에 삽입하여 `nim check`로 transitive effects를 출력받고, 이를 파싱해 `_core.nim`/`_io.nim`으로 분할.

### 3.2 Context7 근거 — **핵심 반박**

Nim Manual (Context7 `/nim-lang/nim`):

> "The `effects` pragma in Nim allows programmers to see all inferred effects up to its position in the code. The compiler then outputs a **hint message** listing potential effects, **such as exceptions that can be raised**, considering the control flow."

**중요한 구분**:
- `{.effects.}`는 **예외 효과(exception effects)**를 출력 — `{.raises: [].}`와 관련.
- **side effect(IO)**는 `{.noSideEffect.}`/`func` 분석 체계 — `{.effects.}`로 출력되지 않음.

Nim은 두 개의 별도 effect system을 가짐:
1. Exception effects (`{.raises.}`)
2. Side effects (`{.noSideEffect.}` / `func`)

### 3.3 추가 근거

- `std/effecttraits`도 "introspection of inferred effects"이나 **async macros의 예외 처리**를 목적으로 함 — side effect 아님.
- `nim check --output:json`은 진단 메시지(errors/warnings/hints)만 출력 — proc별 side effect 분류 없음.
- `--dump-effects`나 유사 플래그 존재하지 않음.

### 3.4 실제 대안 (프로젝트 이미 보유)

**Layer 1: nimtry transitive BFS**
- Call-graph 분석 + IO module seeding.
- 875→0 false positive 달성, ms 속도.
- `docs/spec/nimtry_transitive_proc_purity.md` Phase 1.

**Layer 3: aggressive proc→func conversion**
- 파일 내 모든 `proc`을 `func`로 바꾸고 `nim c` 실행.
- Side effect가 있는 함수는 컴파일 에러로 탐지.
- 100% 정확도, zero false negative.
- `docs/spec/nim_effect_system_quirks.md` §3.

### 3.5 평가

| 세부 주장 | 평가 |
|-----------|------|
| `{.effects.}`가 side effect 출력 | ❌ 반박 — 예외 효과만 출력 |
| `nim check`가 pure/IO 분류 제공 | ❌ 반박 — diagnostic만 제공 |
| compiler-assisted 접근 가능 | ✅ 지지 — 그러나 `proc→func` 변환 또는 nimtry BFS 방식 |
| pure Nim 도구 작성 가능 | ⚠️ 부분 — compiler API 사용 시 복잡 |

### 3.6 권고

제안의 핵심 메커니즘(`{.effects.}` 파싱)은 **지원되지 않음**. 대신:

1. **`split_by_effects.sh`는 유지**하되, nimtry의 call-graph IO reachability 데이터를 통합.
2. **Custom Pragma (`{.axiomEffect: Pure/Io.}`)**를 수동 오버라이드로 사용.
3. **AST 기반 재작성**은 compiler API(`compiler/` modules) 사용 — `{.effects.}`가 아닌 직접적인 AST/semantic 분석.

---

## 4. 주장 4 — Composition Root Compile-Time Guard

### 4.1 제안 내용

`staticRead`로 아키텍처 매니페스트를 읽고, `declared()`로 현재 스코프에 필요한 심볼이 존재하는지 검증. 누락 시 `{.fatal.}`로 즉시 빌드 차단.

### 4.2 Context7 근거

#### `staticRead` — 지지

Nim 메뉴얼: compile-time file read. Deterministic. 프로젝트에서 이미 5곳 이상 사용 (예: `axiom_pragmas.nim`, `version.nim`, `architecture_invariants.nim`).

#### `declared()` — **중요한 제한**

Nim RST examples (Context7):

> "Demonstrates how to check if a symbol is declared using the `declared` function. **Note that this only works for top-level scope symbols**."

**핵심**: `declared()`는 **호출자의 스코프**에서만 동작. `staticRead`로 읽은 원격 파일의 scope를 검증할 수 **없음**.

#### `{.fatal.}` — 지지

Nim Manual: "forces the compiler to output an error message and guarantees that compilation will be aborted."

### 4.3 평가

| 세부 주장 | 평가 |
|-----------|------|
| `staticRead`로 소스 읽기 | ✅ 지지 |
| `error()`/`{.fatal.}`로 차단 | ✅ 지지 |
| `declared()`로 원격 파일 import 검증 | ❌ 반박 — caller scope만 검사 |
| 텍스트 매칭으로 import 완전성 검증 | ⚠️ 부분 — alias, `from X import Y`, 주석 등 edge case |

### 4.4 실제 가능한 패턴

`axiom_pragmas.nim`의 `enforceFacadePattern`과 유사한 텍스트 기반 검증:

```nim
macro compositionRootGuard*(requiredModules: static seq[string]): untyped =
  let source = staticRead(instantiationInfo(-1, true).filename)
  for mod in requiredModules:
    if mod notin source:
      error("COMPOSITION ROOT: Missing required import: " & mod)
  result = newEmptyNode()
```

이는 **완전성(completeness)**은 검증하지만 **정확성(correctness)**은 컴파일러가 담당.

### 4.5 권고

1. `declared()` 기반 의미론적 검증은 **포기**.
2. 대신 `staticRead` + 문자열 포함 검사 + `error()`로 텍스트 수준 완전성 검증.
3. 매니페스트는 각 Composition Root 파일 상단/하단에 `const RequiredImports*`로 선언.
4. Edge case(alias, `from` import)는 known limitation으로 문서화.

---

## 5. 통합 우선순위 로드맵

### Phase 1 — 즉시 적용 (No Planning)

1. **Custom Pragma 도입**: `axiom_pragmas.nim`에 `axiomEffect` 추가.
2. **distinct FFI types**: `tree_sitter_ffi.nim`의 raw `ptr object`를 `distinct`로 변환.
3. **Composition Root 텍스트 가드**: `enforceCompositionRoot` 매크로 추가.

### Phase 2 — 단기 설계 필요

1. **`=destroy` RAII 설계**: tree-sitter 캐시 모델과의 통합 방안.
2. **nimtry effect pragma 규칙**: `axiomEffect` 추출 및 위반 시 `error()`.
3. **split_by_effects.sh 개선**: nimtry call-graph 데이터 통합 (대신 `{.effects.}`는 사용 불가).

### Phase 3 — 장기

1. **AST 기반 effector 도구**: compiler API를 사용한 pure Nim 도구 (Bash 완전 탈피).
2. **FFI Shield 아키텍처 전면 도입**: 모든 FFI 모듈에 `distinct` + boundary seal 패턴 적용.

---

## 6. Context7 증거 레지스트리

새로 추가된 항목은 `docs/evidence/context7/registry.md`의 "2026-06-13: Self-Enforcing Architecture Review" 섹션을 참조.
