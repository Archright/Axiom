# Nim Const-Context Path Type Quirk (DEBT#453/454/455)

> 이 문서는 컴파일 시점(`const`·매크로·템플릿) 경로 값 — `currentSourcePath()`와
> `instantiationInfo(-1, true).filename` — 이 `LogicalPath`(`distinct string`)로
> wrap될 수 없는 이유를 기록한다. 결론부터: const 초기화 자체에서 distinct 변환은
> **컴파일된다** — 깨지는 지점은 **소비 경계**다. `staticRead`(`{.magic: "Slurp".}`),
> `static string` 파라미터, std/os 경로 대수(`parentDir` 등)는 모두 plain `string`만
> 수용하며 `distinct` 타입은 구조적 서브타이핑이 없어 거부된다. const-context 경로
> 값은 이 경계들로 즉시 흘러들어가므로 wrap은 모든 경계에서 `string(...)` 언래핑을
> 강제하고, 그 순간 distinct 타입의 보호 목적(artifact_determinism.md §2.3)이
> 경계마다 무효화된다.
> AGENTS.md §0.5 — Quirk Mandate (Documentation-First)의 실행 부속서다.
> 발견 계기: `physical_path_boundary_audit`가 DEBT#453/#454/#455로 등록한 quirk의
> 문서화 종결 슬라이스 (2026-11-16).

---

## §1. Symptom (실측, 2026-11-16, Nim 2.2.10)

래핑 시도는 세 종류의 경계에서 각각 아래와 같이 실패한다(원문 그대로):

**경계 1 — `staticRead` (const-context 자기 해시·매크로 소스 읽기):**

```
/tmp/quirk_repro/repro_const_context.nim(35, 35) Error: type mismatch
Expression: staticRead(wrappedFunc)
  [1] wrappedFunc: LogicalPath

Expected one of (first mismatch at [position]):
[1] proc staticRead(filename: string): string
```

**경계 2 — `static string` 매크로/프록 파라미터 (템플릿→매크로 handoff):**

```
/tmp/quirk_repro/repro_macro_context.nim(31, 17) Error: type mismatch
Expression: guardWrapped(LogicalPath(srcPath`gensym2))
  [1] LogicalPath(srcPath`gensym2): LogicalPath

Expected one of (first mismatch at [position]):
[1] macro guardWrapped(path: static string): untyped
```

**경계 3 — std/os 경로 대수 (compileTime 루트 탐색 체인):**

```
/tmp/quirk_repro/repro_compiletime_proc.nim(28, 25) Error: type mismatch
Expression: parentDir(wrappedRoot)
  [1] wrappedRoot: LogicalPath

Expected one of (first mismatch at [position]):
[1] proc parentDir(path: string): string
```

## §2. Root cause

1. **경로 소스가 이미 `string`으로 타입된 컴파일러 내장이다.**
   - `currentSourcePath(): string` — system 모듈 템플릿. "Returns the full file-system
     path of the current source... The path returned by this template is set at compile
     time." (https://nim-lang.github.io/Nim/system.html)
   - `instantiationInfo(index = -1; fullPaths = false): tuple[filename: string,
     line: int, column: int] {.magic: "InstantiationInfo".}` — 컴파일러 magic
     (https://nim-lang.github.io/Nim/system.html). `.filename` 필드는 `string`이다.
2. **소비 경계도 `string` 전용이다.**
   - `staticRead(filename: string): string {.magic: "Slurp".}` — 컴파일러 magic.
     공식 서명이 `string`이며 distinct 타입 인자는 §1 경계 1처럼 거부된다
     (https://nim-lang.github.io/Nim/system.html).
   - `static[T]` 파라미터 — "As their name suggests, static parameters must be constant
     expressions" (https://nim-lang.github.io/Nim/manual.html). `static string` 파라미터는
     정확히 `string` 타입을 요구한다 (§1 경계 2).
   - std/os 경로 대수(`parentDir`·`extractFilename`·`/`) — 모두 `string` 파라미터
     (§1 경계 3).
3. **`distinct`는 구조적 서브타이핑이 없다.** `distinct string`은 새 타입을 만들며
   원본 타입의 프로시저·컴파일러 내장 호환성을 상속받지 않는다. 그래서
   `LogicalPath(currentSourcePath())` **생성은 가능하지만**(§3 참조), 생성된 값을
   위 2의 어떤 경계에도 통과시킬 수 없다.
4. **const-context 규칙**(문맥 조건): "Constant expressions are restricted to depend
   only on... literals, built-in operators, previously declared constants and
   compile-time variables, previously declared macros and templates, previously
   declared procedures that have no side effects"
   (https://nim-lang.github.io/Nim/manual.html). 부수효과 없는 변환 func
   (`toLogical`)의 const-context 호출 자체는 이 규칙 안에서 허용된다 — 제약은
   const-context 자체가 아니라 경로 값의 소비처가 전부 `string` 전용이라는 점에 있다.

**정확한 본질 요약**: quirk는 "const 표현식에서 distinct 생성이 불가능하다"가
아니다(실측상 가능). "컴파일 시점 경로 파이프라인의 모든 소비 경계 —
`staticRead`, `static string` 파라미터, std/os 경로 대수 — 가 plain `string`만
수용하고 distinct 타입을 거부한다"이다. 경로 값은 소스(1)에서 나오는 순간 이
경계들로 흘러가므로, wrap은 경계마다 명시적 `string(...)` 언래핑을 요구하고
그러면 타입 수준 보호가 무의미해진다.

## §3. Reproduction (minimal)

독립 파일 세 벌(/tmp에서 실측; 저장소 회귀 테스트는 §7). 모두 Nim 2.2.10.

**R1 — const-context (`architecture_invariants.nim` InvariantSourceHash 축소):**

```nim
import std/os
import std/strutils

type LogicalPath* = distinct string
type PhysicalPath* = distinct string

func toLogical*(pp: PhysicalPath; root: string): LogicalPath {.raises: [].} =
  let s = string(pp)
  if root.len > 0 and s.startsWith(root):
    let relative = s.substr(root.len)
    LogicalPath(relative.strip(chars = {'/'}))
  else:
    LogicalPath(s)

const srcPath = currentSourcePath()                              # 통과 (string)
const wrappedDirect = LogicalPath(currentSourcePath())           # 통과 (distinct 생성)
const wrappedFunc = toLogical(PhysicalPath(currentSourcePath()), "/nonexistent/root")  # 통과
const selfContent = staticRead(srcPath)                          # 통과 (string)
const selfContentWrapped = staticRead(string(wrappedDirect))     # 통과 (명시적 언랩)
const selfContentFunc = staticRead(wrappedFunc)                  # 실패 — §1 경계 1
```

**R2 — macro/template handoff (`axiom_pragmas_macros.nim` 패턴 축소):**

```nim
import std/macros

type LogicalPath* = distinct string

macro guardWrapped(path: static string): untyped =
  discard

template autoGuardWrapped*() =
  const srcPath = instantiationInfo(-1, true).filename   # 템플릿 확장 지점 = 실제 경로
  guardWrapped(LogicalPath(srcPath))                      # 실패 — §1 경계 2

autoGuardWrapped()
```

(동일 파일에서 `guardWrapped(srcPath)` — 언랩 없이 string 그대로 — 는 통과한다.)

**R3 — compileTime proc + std/os 체인 (`layer_enforcement.nim` resolveProjectRoot 축소):**

```nim
import std/os
import std/strutils

type LogicalPath* = distinct string

proc findProjectRoot(start: string): string {.compileTime.} =
  var current = start
  while true:
    let parent = current.parentDir()
    if parent == current:
      return ""
    if fileExists(parent / ".axiom_root"):
      return parent
    current = parent

proc resolveProjectRoot*(): string {.compileTime.} =
  const srcPath = currentSourcePath()
  result = findProjectRoot(srcPath)

const root = resolveProjectRoot()          # 통과
const wrappedRoot = LogicalPath(root)      # 통과 (distinct 생성)
const parent = parentDir(wrappedRoot)      # 실패 — §1 경계 3
```

## §4. 허용 계약 (안전 패턴) — debt 사이트의 현재 코드가 올바른 이유

1. **const/매크로/템플릿 문맥의 경로 값은 `string`(= `PhysicalPath` 의미)으로 유지한다.**
   이것이 `artifact_determinism.md` §2.4 "Deferred approach"가 규정하는 정당한 수용
   패턴이다. DEBT#453(`layer_enforcement.nim` resolveProjectRoot 체인),
   DEBT#454(`architecture_invariants.nim` InvariantSourceHash의
   `currentSourcePath().parentDir() / ...` → `staticRead` 체인),
   DEBT#455(`axiom_pragmas_macros.nim` 전 매트릭스)의 현 코드가 정확히 이 패턴이다.
2. **template→macro handoff는 `string`으로만 존재할 수 있다.** 매크로 본문에서
   `instantiationInfo`는 `"???"`를 반환하므로(§6) 실제 호출자 경로를 얻으려면
   템플릿 확장 지점에서 `instantiationInfo(-1, true).filename`을 계산해 macro
   `static string` 파라미터로 넘겨야 한다(`axiomLayerGuardAuto*`,
   `enforceFacadePattern*`, `compositionRootGuard*`). 이 handoff 자체가 §1 경계 2이므로
   경로 값은 `string`이어야 한다.
3. **런타임 경계에서만 `LogicalPath`로 변환한다.** 경로 소비가 런타임 `proc`으로
   리팩터링되는 시점에 `path_identity.nim`의 `toLogical`(단일 변환 경계)로
   변환한다 — §2.4 "Deferred approach"와 동일한 계약.
4. **금지**: 이 quirk를 "해소"한다고 const-context 사이트에 경계마다
   `string(...)` 언랩을 산재시키는 것 — 그것은 타입 보호를 무효화하는 극장이다.
   컴파일러가 `staticRead`/`static string`에 distinct를 수용하는 날(§7 회귀 테스트가
   실패로 신호) 비로소 wrap이 의미를 갖는다.

## §5. 영향 범위 (2026-11-16 실측)

- DEBT#453: `src/core/trusted/layer_enforcement.nim` — `resolveProjectRoot`
  (const `currentSourcePath()` → `findProjectRoot` → std/os 체인) 및
  `axiomLayerPragmaImpl`(const `instantiationInfo(-1, true).filename` →
  `staticRead`).
- DEBT#454: `src/core/trusted/architecture_invariants.nim` — `InvariantSourceHash`
  (`currentSourcePath()` → `parentDir`/`/` → `staticRead` 전체 체인) 및
  `executeAntiSlackingScan` 템플릿 handoff.
- DEBT#455: `src/core/trusted/axiom_pragmas_macros.nim` — `axiomLayerGuard`,
  `axiomLayerGuardAutoImpl` handoff, `enforceFacadePattern`, `verifySpecification`,
  `registerStageImpl`, `compositionRootGuard` 전 경로Embedding.
- 같은 제약이 §2.4 지연 레지스트리의 다른 사이트들(`feature_manifest_guard.nim`,
  `verified_axioms_catalog_part1.nim`, `canonical_verification.nim`,
  `cli/version.nim`)에도 동일하게 적용된다 — 동일 근본 quirk.
- Nim 2.2.10 (저장소 pinned, choosenim). 상위 Nim 버전에서의 해소 여부는
  §7 회귀 테스트가 자동 감지한다.

## §6. 관련 관측 — 매크로 본문 `instantiationInfo` "???" 비대칙

Nim 2.2.10 실측(독립 프로브, 2026-11-16):

```
macro filename=[???] line=0      # 매크로 본문 — const 평가·VM 평가 모두
template filename = [/tmp/quirk_repro/repro_iii_filename.nim]   # 템플릿 확장 지점
```

매크로 **본문** 안에서는 `instantiationInfo(-1, true)`가 filename `"???"`,
line 0을 반환한다(호출자 정보가 매크로 본문까지 전파되지 않는다). 템플릿은 확장
지점에서 평가되므로 실제 호출자 파일 경로를 얻는다. 이 비대칭이 §4-2의
handoff 패턴이 존재하는 이유이며, `layer_enforcement.nim`
`enforceLayerImports` 주석(약 254-277행)이 기술하는 "??? guard"의 근거다.
본 quirk 문서의 주 대상(타입 경계)과는 별개 관측이지만, handoff 패턴의
존재 근거로 함께 기록한다.

## §7. 회귀 테스트

`tests/unit/test_const_context_path_type_quirk.nim` (Makefile `TESTS_FAST_UNIT` 등록).
`compiles()`/`not compiles()` 로 세 경계의 거부 동작과 baseline 통과 동작을 고정한다:

- baseline: `staticRead(string)`, `static string` handoff, std/os — 모두 통과.
- direct distinct 생성(`LogicalPath(currentSourcePath())`)은 통과(§2 본질 정확화).
- `staticRead(LogicalPath(...))` / `static string` 파라미터 / `parentDir(LogicalPath(...))`
  — 모두 **컴파일 거부**.
- 매크로 본문 filename `"???"`·템플릿 실경로(§6) 고정.

**quirk 소멸 감지**: 컴파일러 업그레이드로 `staticRead`·`static string` 파라미터가
distinct를 수용하기 시작하면 `not compiles(...)` 검증이 실패한다 — 그 시점에
DEBT#453/#454/#455의 지연 사유가 소멸했으므로 재평가(랩 도입) 신호다.
반대로 baseline 검증이 실패하면 현행 패턴이 깨진 것이므로 즉시 수선 필요다.

실행: `make test-fast-one T=tests/unit/test_const_context_path_type_quirk.nim`
(전체 suite: `make test-fast`).

## 참조 (References)

- https://nim-lang.github.io/Nim/system.html — `currentSourcePath(): string`,
  `instantiationInfo(...): tuple[filename: string, ...] {.magic: "InstantiationInfo".}`,
  `staticRead(filename: string): string {.magic: "Slurp".}`.
- https://nim-lang.github.io/Nim/manual.html — "Constants and Constant Expressions"
  (const 표현식 허용 목록), "static[T]" (static 파라미터 규칙), "Distinct types"
  (구조적 서브타이핑 부재).
- `src/core/utils/path_identity.nim` — PhysicalPath/LogicalPath 정의·`toLogical`
  단일 변환 경계.
- `docs/spec/artifact_determinism.md` §2.3-2.5 — 타입 수준 보호 규칙·지연 레지스트리.
- `data/debt_registry.json` — DEBT#453/#454/#455 엔트리.
- `tests/unit/test_const_context_path_type_quirk.nim` — 회귀 테스트(§7).

## 갱신 기록

- 2026-11-16: 최초 문서화. DEBT#453/#454/#455 quirk 문서화 종결 슬라이스
  (VS-1 후속) — 최소 재현 3종·공식 문서 근거·회귀 테스트 동반.
