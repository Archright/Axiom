# Context7 기반 아키텍처 주장 검토 보고서

> Date: 2026-06-13
> Method: Context7 MCP (`/nim-lang/nim`) + 코드베이스 정적 분석
> Scope: 사용자가 제기한 2가지 아키텍처 주장

---

## Executive Summary

| 주장 | 평가 | Context7 근거 강도 | 권고 |
|------|------|-------------------|------|
| **A**: 매크로 기반 레지스트리 배선 시 컴파일 순서/임포트 의존성 강제 필요 | **부분 지지** (원리상 옳으나 구체적 시나리오는 프로젝트 미확인) | 중간 | Composition Root 패턴 문서화 + `import` 강제 룰 제안 |
| **B**: FFI/복잡 제네릭 코드의 보수적 side-effect 추론으로 `split_by_effects.sh` 오분류 가능 | **지지** (Nim 효과 시스템 원리상 필연) | 높음 | `architecture_policy.lock`에 `[effect_hints]` 섹션 신설 + `split_by_effects.sh` FFI 패턴 감지 추가 |

---

## 1. 주장 A — 컴파일 순서/매크로 평가 시점

### 1.1 주장 내용

> Nim 컴파일러는 파일/모듈의 위상 기하학적 순서(Topological Order)에 따라 컴파일을 진행합니다. `autoWireStages` 매크로가 호출되어 레지스트리를 순회하는 시점에, 개별 스테이지 모듈(`pipeline_stage_swat.nim` 등)이 메인 오케스트레이터 상단에 명시적으로 `import`되어 있지 않다면 컴파일러가 해당 프라그마 매크로를 먼저 평가하지 못해 레지스트리가 비어 있는 채로 배선될 위험이 있습니다. 따라서 최종 배선이 일어나는 엔트리 포인트에서 대상 모듈들의 명시적 `import` 의존성을 강제하는 규칙을 룰셋에 포함해야 안전합니다.

### 1.2 Context7 근거

#### 1.2.1 모듈 의존성 그래프와 증분 컴파일

Context7 `/nim-lang/nim` 인용:

> "For debugging incremental compilation, key areas to inspect in the Nim compiler are 'compiler/deps.nim' for build file generation and the 'nim ic' entry point, and 'compiler/modulegraphs.nim' and 'compiler/pipelines.nim' for dependency graph and compilation pipeline integration."
> — Source: `doc/ic.md`

> "The 'depends.nim' module is a pass that computes dependencies between modules and can generate a dot file for visualization."
> — Source: `wiki/Compiler-module-reference`

**분석**: Nim 컴파일러는 모듈 간 의존성 그래프를 명시적으로 계산하며, 이 그래프가 컴파일 순서를 결정합니다. 따라서 "위상 기하학적 순서(Topological Order)"라는 표현은 Nim의 모듈 의존성 해석 메커니즘과 일치합니다.

#### 1.2.2 코드 재배열(Code Reordering)과 매크로/프라그마

Context7 `/nim-lang/nim` 인용:

> "Nim's code reordering feature automatically rearranges top-level procedure, template, macro definitions, and variable declarations to minimize the need for manual ordering or forward declarations within a module. This reordering applies only to symbols at the top-level scope."
> — Source: `doc/manual.md` / `nimdoc/rst2html/expected/rst_examples.html`

> "Code reordering allows the compiler to implicitly rearrange procedure, template, and macro definitions, along with variable declarations and initializations, at the top-level scope."
> — Source: `nimdoc/rst2html/source/rst_examples.rst`

**분석**: 코드 재배열은 **모듈 낶부**의 최상위 심볼 순서만 조정합니다. 모듈 간 의존성은 `import` 문에 의해 명시적으로 결정되며, 이는 재배열 대상이 아닙니다.

#### 1.2.3 매크로/프라그마 변환 시점

Context7 `/nim-lang/nim` 인용:

> "Demonstrates how a template used as a pragma is transformed by the compiler."
> — Source: `doc/manual.md` (Macro Pragmas Transformation Example)

> "Below calls 'echo getNum(123)' at compile time."
> — Source: `doc/manual.md` (Compile-Time Function Call and Evaluation)

> "Force expressions to be evaluated as constant expressions at compile time by coercing them to a `static` type."
> — Source: `doc/manual.md` (Compile-time Evaluation with static type coercion)

**분석**: 매크로와 `static` 블록은 컴파일 시점에 평가됩니다. 매크로가 다른 모듈의 레지스트리를 읽으려면, 해당 레지스트리를 채우는 모듈(top-level 매크로 호출 또는 등록 코드)이 이미 컴파일되어 있어야 합니다. Nim은 모듈 의존성 그래프에 따라 컴파일하므로, **레지스트리 소비 모듈이 레지스트리 생산 모듈을 (직/간접) import하지 않으면 생산 모듈의 최상위 코드는 실행되지 않습니다**.

### 1.3 코드베이스 검증

- `autoWireStages` 심볼은 현재 코드베이스에 존재하지 않음.
- 그러나 유사한 "Composition Root / Registry Pattern"이 이미 사용 중:
  - `src/core/orchestration/pipeline_dispatch.nim` — `personas/*` import 후 `createDefaultPipelineDispatch()` 반환
  - `src/core/orchestration/persona_bridge_init.nim` — `verification/*` import 후 `initPersonaBridge()`로 클로저 배선

```nim
# persona_bridge_init.nim (일부)
import verification/leanstral_gateway
import verification/unified_trajectory
import verification/pipeline_negative_scan
# ... (생략)
proc initPersonaBridge*(): PersonaBridge {.raises: [].} =
  result = PersonaBridge(
    callLeanstral: proc(prompt: string): LeanstralResult {.closure, raises: [].} =
      let gw = leanstral_gateway.callLeanstral(prompt)
      ...
```

이는 주장 A의 "최종 배선 엔트리 포인트에서 대상 모듈들의 명시적 import" 원칙을 이미 실천하고 있습니다.

### 1.4 평가

| 항목 | 결론 |
|------|------|
| "Nim은 모듈 의존성 그래프(Topological Order)에 따라 컴파일한다" | **지지** (Context7 `deps.nim`, `modulegraphs.nim`, `pipelines.nim` 인용) |
| "매크로 평가 시점에 import되지 않은 모듈의 레지스트리가 비어 있다" | **원리상 지지** (모듈이 import되지 않으면 컴파일 자체가 안 됨) |
| "`autoWireStages`가 구체적으로 존재한다" | **미확인** (코드베이스에 해당 심볼 없음) |
| "명시적 import 강제 룰이 필요하다" | **권고 수용** (Composition Root 패턴의 표준 안전 장치) |

### 1.5 권고사항

1. **Composition Root 패턴 문서화**: `docs/spec/intentional_architecture_patterns.md`에 "Composition Root는 반드시 구현체 모듈을 직접 import해야 한다"는 규칙 추가.
2. **Import Encapsulation Gate 강화**: `src/gate/runners/import_encapsulation_gate.nim` 또는 `nimtry`에서 Composition Root 파일의 상위 레이어 import 누락을 탐지하는 규칙 추가.
3. **`architecture_policy.lock` 연동**: `[module_roles]` 또는 새 `[composition_roots]` 섹션에 "wiring entry point → required implementation imports" 매핑 추가.

---

## 2. 주장 B — FFI/복잡 제네릭 코드의 보수적 Side-Effect 추론

### 2.1 주장 내용

> 외부 C/C++ FFI 라이브러리를 래핑한 모듈이나, 낶부적으로 이펙트 추론이 모호한 복잡한 제네릭 코드의 경우 컴파일러가 보수적으로 부작용이 있다고 판단(`not hasNoSideEffects`)할 가능성이 있습니다. 이때 `split_by_effects.sh`가 오분류를 일으키지 않도록, 명시적으로 이펙트 격리를 선언할 수 있는 에스케이프 해치(Escape Hatch)나 힌트 프라그마를 `architecture_policy.lock`에 연동해 두면 더욱 견고해질 것입니다.

### 2.2 Context7 근거

#### 2.2.1 `func`와 `noSideEffect`

Context7 `/nim-lang/nim` 인용:

> "Shows the expanded form of the 'func' declaration, explicitly marking it with the 'noSideEffect' pragma."
> ```nim
> proc binarySearch[T](a: openArray[T]; elem: T): int {.noSideEffect.}
> ```
> — Source: `doc/manual.md`

> "Demonstrates the use of `func` as syntactic sugar for procedures with no side effects."
> ```nim
> func `+` (x, y: int): int
> ```
> — Source: `doc/manual.md`

> "Nim's side effect analysis aims to determine if a procedure modifies locations reachable from its parameters or return value. A routine has no side effects if it doesn't access thread-local or global variables and doesn't call other routines with side effects. The compiler statically checks for `noSideEffect` annotations, and `func` is syntactic sugar for procedures with no side effects."
> — Source: `doc/manual.md` (Future directions > Side effects)

**분석**: `func`는 `{.noSideEffect.}`를 암시합니다. 컴파일러는 "전역/스레드 로컬 변수에 접근하지 않고, side effect가 있는 다른 루틴을 호출하지 않음"을 정적으로 검증해야 합니다. **검증 불가능한 외부 함수를 호출하면 `func` 선언은 컴파일 오류**가 됩니다.

#### 2.2.2 외부 함수 가져오기(`importc`, `dynlib`, `importcpp`)

Context7 `/nim-lang/nim` 인용:

> "Demonstrates calling a C function `sin` from Nim using `importc`. The `header` and `nodecl` pragmas are used for C function integration."
> ```nim
> proc sin(a: cdouble): cdouble {.importc, header: "math.h", nodecl.}
> ```
> — Source: `wiki/Nim-for-Haskell-Programmers`

> "Demonstrates how to import C++ structs and functions into Nim using the importcpp pragma."
> ```nim
> proc takesCStruct(x {.byref.}: CStruct): cint {.importc.}
> ```
> — Source: `doc/manual.md`

> "Demonstrates importing C++ templates as generic Nim objects. Requires the 'importcpp' pragma with type and operator definitions."
> ```nim
> type
>   StdMap[K, V] {.importcpp: "std::map", header: "<map>".} = object
> proc `[]=`[K, V](this: var StdMap[K, V]; key: K; val: V) {.
>     importcpp: "#[#] = #", header: "<map>".}
> ```
> — Source: `doc/manual.md`

**분석**: Context7 예제에서 모든 `importc`/`importcpp` 프로시저는 **`proc`로 선언**되며 `{.noSideEffect.}`가 없습니다. 이는 Nim 커뮤니티의 관행적 관찰과 일치합니다: **외부 C/C++ 함수의 효과를 컴파일러가 검증할 수 없으므로, 기본적으로 side effect가 있는 것으로 간주**됩니다.

#### 2.2.3 Side-Effect 추론 재정의

Context7 `/nim-lang/nim` 인용:

> "Shows how to use the `{.cast(noSideEffect).}` pragma block to override the compiler's automatic side effect analysis when necessary, such as for debugging."
> ```nim
> func f() =
>   {.cast(noSideEffect).}:
>     echo "test"
> ```
> — Source: `doc/manual.md`

> "Shows the new preferred syntax for `gcsafe` and `noSideEffect` pragmas using `{.cast(...).}`. This emphasizes the potentially unsafe nature of these pragmas."
> — Source: `changelogs/changelog_1_4_0.md`

**분석**: 컴파일러의 side-effect 분석을 재정의할 수 있는 메커니즘이 공식적으로 존재합니다. 그러나 `{.cast(noSideEffect).}`는 **안전하지 않을 수 있음**을 강조하며, AGENTS.md/GUARDIAN에서 남용을 금지하고 있습니다.

#### 2.2.4 제네릭/템플릿 효과 전파

Context7 `/nim-lang/nim` 인용:

> "Illustrates the behavior of `var` parameters in templates. While Nim accepts them and performs type checking, their usage within templates can lead to side effects due to the text substitution nature of templates."
> — Source: `wiki/Templates`

> "Improves the multiplication optimization by adding a 'noSideEffect' constraint to the parameter, preventing optimization of expressions with side effects."
> ```nim
> template optMul{`*`(a, 2)}(a: int{noSideEffect}): int = a + a
> ```
> — Source: `doc/manual_experimental.md`

> "Illustrates a scenario where Nim versions before 1.6.0 would compile without error, but Nim 1.6.0 correctly identifies side effects in a 'func' using a borrowed proc."
> — Source: `changelogs/changelog_1_6_0.md`

**분석**: 템플릿과 제네릭은 호출부의 효과가 본문에 전파됩니다. `noSideEffect` 제약은 컴파일러가 보수적으로 거부할 수 있는 지점입니다. 복잡한 제네릭 코드에서 효과 추론이 모호해지면 컴파일러는 안전 측면(side effect 있음)으로 판단할 수 있습니다.

### 2.3 코드베이스 검증

#### 2.3.1 FFI 래퍼 실제 사례: `src/core/parsers/tree_sitter_ffi.nim`

```nim
proc ts_parser_new*(): TSParser {.importc, cdecl.}
proc ts_parser_delete*(parser: TSParser) {.importc, cdecl.}
proc ts_parser_set_language*(parser: TSParser, language: TSLanguage): bool {.importc, cdecl.}
proc ts_parser_parse_string*(parser: TSParser, old_tree: ptr TSTree,
                              source: cstring, length: uint32): ptr TSTree {.importc, cdecl.}
# ...
proc tree_sitter_nim*(): TSLanguage {.importc, cdecl.}
```

모든 FFI 프로시저는 `proc`로 선언되며 `{.noSideEffect.}`가 없습니다. 이는 Nim 컴파일러가 해당 C 함수의 효과를 검증할 수 없음을 반영합니다.

#### 2.3.2 Windows API FFI 실제 사례: `src/core/sync/sync_utils_resource.nim`

```nim
proc globalMemoryStatusEx(lpBuffer: var MemoryStatusEx): WINBOOL {.
  stdcall, dynlib: "kernel32", importc: "GlobalMemoryStatusEx".}
```

`dynlib` + `importc` 조합. 이 프로시저를 호출하는 `func`는 컴파일되지 않습니다.

#### 2.3.3 `split_by_effects.sh` 분석

`tools/ci/split_by_effects.sh`의 I/O 패턴 목록:

```bash
IO_PATTERNS=(
  "readFile" "writeFile" "echo" "execProcess" "startProcess" "open\\("
  "close\\(" "getEnv" "putEnv" "fileExists" "dirExists" "createDir"
  "removeFile" "stdin" "stdout" "stderr" "sleep" "getCurrentDir"
  "getAppFilename" "existsEnv"
)
```

**문제점**: `importc`, `importcpp`, `dynlib`, `header`와 같은 FFI 선언을 **전혀 감지하지 못합니다**. 따라서 다음과 같은 함수는 `split_by_effects.sh`에 의해 "pure"로 잘못 분류될 수 있습니다:

```nim
proc wrapTsParse*(s: string): TSNode =
  let parser = ts_parser_new()   # FFI 호출 — side effect
  ...
```

이 함수는 I/O 패턴이 없으므로 `_core.nim`으로 분류되지만, 실제로는 C 힙 할당(`ts_parser_new`) 등의 side effect를 포함합니다.

### 2.4 평가

| 항목 | 결론 |
|------|------|
| "FFI 래퍼는 보수적으로 side effect로 판정될 수 있다" | **강력 지지** (Context7 + 코드베이스 실제 사례) |
| "복잡한 제네릭 코드도 side effect로 판정될 수 있다" | **지지** (Nim 효과 전파 메커니즘상 가능) |
| "`split_by_effects.sh`가 FFI를 오분류할 수 있다" | **확인** (스크립트가 FFI 패턴 미포함) |
| "`architecture_policy.lock`에 escape hatch/hint pragma 연동 필요" | **권고 수용** (프로젝트에 `@axiom-hint` 코멘트 기반 힌트 시스템 이미 존재) |

### 2.5 권고사항

#### 2.5.1 단기 — `split_by_effects.sh` 개선

FFI 선언을 I/O 패턴에 추가:

```bash
IO_PATTERNS+=(
  "importc"
  "importcpp"
  "dynlib"
  "{.compile.}"
)
```

그러나 이는 거친 휴리스틱입니다. FFI 함수 **선언** 자체는 side effect가 아니며, 해당 함수를 **호출**하는 본문만 side effect가 있을 수 있습니다. 더 정확한 방식은 "해당 함수 본문에서 FFI 선언된 proc을 호출하는지" 확인하는 것입니다.

#### 2.5.2 중기 — `architecture_policy.lock`에 `[effect_hints]` 섹션 신설

```toml
[effect_hints]
# 모듈/함수별 명시적 effect 선언. split_by_effects.sh와 nimtry가 참조.
"src/core/parsers/tree_sitter_ffi.nim" = { effect = "io", reason = "C API wrapper via {.importc.}" }
"src/core/sync/sync_utils_resource.nim" = { effect = "io", reason = "Windows kernel32.dll FFI" }
"src/core/sync/sync_utils_process.nim" = { effect = "io", reason = "Process spawn/IPC" }

[effect_hints.functions]
"tree_sitter_ffi.ts_parser_new" = "io"
"tree_sitter_ffi.ts_tree_delete" = "io"
"sync_utils_resource.globalMemoryStatusEx" = "io"
```

#### 2.5.3 중기 — `@axiom-effect` 코멘트/프라그마 표준화

프로젝트에 이미 `# @axiom-hint: lean="..." smt="..."` 코멘트 기반 힌트 시스템이 존재합니다. 이를 확장하여:

```nim
# @axiom-effect: io
# @axiom-effect: pure
# @axiom-effect: raises=[CatchableError]
```

`split_by_effects.sh`와 `nimtry`가 이 코멘트를 읽어 우선적으로 적용하도록 합니다. 이는 `{.cast(noSideEffect).}`보다 안전하고 감사 가능합니다.

#### 2.5.4 장기 — FFI 효과 추론을 위한 전용 어댑터 모듈

`src/core/trusted/` 하위에 `effect_shim.nim`, `stdlib_shield.nim`과 유사한 **FFI shield** 패턴 도입:

```nim
# src/core/trusted/ffi_shield.nim
{.push raises: [].}

import core/parsers/tree_sitter_ffi

proc safeTsParserNew*(): TSParser {.raises: [].} =
  tree_sitter_ffi.ts_parser_new()

proc safeTsTreeDelete*(tree: ptr TSTree) {.raises: [].} =
  tree_sitter_ffi.ts_tree_delete(tree)
```

도메인 코드는 `ffi_shield`를 통해서만 FFI에 접근하도록 하여 효과 경계를 명확히 합니다.

---

## 3. 종합 권고 및 다음 단계

### 3.1 즉시 실행 권고

1. `docs/spec/nim_effect_system_quirks.md`에 "§7 FFI 래퍼의 side effect 분류" 추가.
2. `tools/ci/split_by_effects.sh`에 `importc`/`importcpp`/`dynlib`/`{.compile.}` 패턴 감지 추가.
3. `src/core/parsers/tree_sitter_ffi.nim`, `src/core/sync/sync_utils_resource.nim`, `src/core/sync/sync_utils_process.nim`을 `docs/spec/intentional_architecture_patterns.md`의 "FFI boundary"로 등록.

### 3.2 단기 실행 권고

1. `architecture_policy.lock`에 `[effect_hints]` 섹션 초안 추가.
2. `@axiom-effect` 코멘트 컨벤션 정의 및 `nimtry` 파서 확장.
3. `import_encapsulation_gate`에 "Composition Root는 구현체 import 누락 금지" 규칙 추가.

### 3.3 장기 실행 권고

1. `src/core/trusted/ffi_shield.nim` 같은 표준 FFI 어댑터 패턴 도입.
2. `split_by_effects.sh`를 AST 기반(nim compiler API 또는 `nimparse`)으로 재작성하여 휴리스틱 오분류 제거.

---

## 4. Context7 증거 레지스트리 참조

새로 추가된 Context7 항목은 `docs/evidence/context7/registry.md`의 "2026-06-13: Architecture Claim Review" 섹션을 참조.
