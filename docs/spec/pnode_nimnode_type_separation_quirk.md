# PNode / NimNode Type Separation Quirk (DEBT#395)

## 증상 (Symptom)

Nim 2.2.10에서 `PNode = ref TNode`(compiler/ast)와 `NimNode = ref NimNodeObj`(std/macros)는 서로 다른 타입 계층이다. 런타임에 두 타입 간 캐스팅을 시도하면 `.compileTime proc` 오류가 발생한다. 또한 `std/macros.parseStmt`는 `.compileTime` 프로시저이므로 런타임 테스트 프로세스에서는 사용할 수 없다.

```nim
import std/[macros, ast]

let raw = """var x = 42"""
let nn = parseStmt(raw)           # .compileTime proc — 런타임에서 호출 불가
let pn = cast[PNode](nn)          # 런타임 캐스트 실패: ".compileTime proc" 오류
```

## 근본 원인 (Root Cause)

1. **별개 타입 계층**: `compiler/ast.PNode`는 컴파일러 내부 AST 표현이고, `std/macros.NimNode`는 매크로 시스템의 추상화 계층이다. 두 타입은 서로 관련 없는 `ref object`이며 상호 변환이 불가능하다.
2. **컴파일타임 제약**: `std/macros.parseStmt`는 `{.compileTime.}`으로 마크되어 있어 컴파일 타임에만 호출 가능하다. 런타임 코드(테스트 프로세스 포함)에서는 사용할 수 없다.
3. **Nim 표준 라이브러리 설계**: `std/macros` 모듈은 메타프로그래밍 전용이며, 정적 분석 엔진과 런타임 파싱을 분리하는 것이 Nim의 의도된 아키텍처다.

## 안전 패턴 (Safe Patterns)

```nim
# 패턴 A: TCB/검증 엔진 코어 → PNode 독점 사용
# compiler/ast를 직접 import하고 core/parser_utils.parseStringAST 사용
import core/parser_utils   # runtime-capable, threadvar-cached

let pn = parseStringAST("var x = 42")  # 런타임에서 안전하게 호출 가능
# pn은 PNode 타입 — 검증 엔진에서 즉시 사용 가능

# 패턴 B: 매크로/메타프로그래밍 도메인 → NimNode 독점 사용
import std/macros

macro myMacro(n: NimNode): NimNode =    # 컴파일타임에서만 동작
  result = n

# 패턴 C: 도메인 간 런타임 캐스트 금지
# PNode ↔ NimNode 간 변환은 절대 런타임에서 수행하지 말 것
# 교차 도메인이 필요하면 AST 직렬화 + 파싱 브리지 사용
```

**핵심 원칙**:
- 검증/정적 분석 영역: `PNode` 독점 (`compiler/ast` via `core/parser_utils.parseStringAST`)
- 매크로/메타프로그래밍 영역: `NimNode` 독점 (`std/macros`, `quote do:`)
- 도메인 경계에서 런타임 캐스트: FORBIDDEN

## 영향 범위 (Impact)

- `ast_to_ir` 테스트 초기에 차단됨 (`parseStmt` compileTime 제약)
- `parseStringAST`(`src/core/parser_utils.nim`)를 통해 해결 — 런타임 가능하며 threadvar 캐싱 적용
- 컴파일러 내부와 stdlib 매크로 시스템을 혼동하는 새로운 에이전트의 실수 예방

## 참조 (References)

- `src/core/parser_utils.nim` parseStringAST (런타임 AST 파서)
- `tests/unit/ast_to_ir_test.nim` (패턴 A 활용 예시)
- `docs/spec/nim_json_getordefault_quirk.md` (quirk 문서화 템플릿)
- Nim 2.2.10 `lib/compiler/ast.nim` PNode 정의
- Nim 2.2.10 `lib/pure/macros.nim` NimNode 정의 및 parseStmt(.compileTime)

## 갱신 기록 (docs-only 실증 커밋)

- 2026-08-01: docs-only 라우팅 실증 (run_ci: false 검증)

---

## NimNode API Quirks (Phase C, 2026-08-16)

### QUIRK#C001 — `parseFile` does NOT exist in Nim 2.2.10

**Symptom**: Code calling `parseFile(path)` fails with "undeclared identifier: parseFile".

**Root cause**: `std/macros` in Nim 2.2.10 provides only `parseExpr(s, filename)` and `parseStmt(s, filename)` — both take a string content, not a file path. There is no `parseFile`.

**Safe pattern**:
```nim
import std/[os, macros]

proc parseSourceFile*(path: string): seq[CanonNode] =
  if not fileExists(path): return @[]
  let content = readFile(path)
  if content.len == 0: return @[]
  let tree = parseStmt(content, path)  # runtime-capable
  result = @[]
  for i in 0 ..< tree.len:
    result.add(toCanon(tree[i]))
```

### QUIRK#C002 — `safeLen` does NOT exist on NimNode

**Symptom**: `child.safeLen` fails with "undeclared field: safeLen for type system.NimNode".

**Root cause**: `NimNode` has only `len()` (magic `NLen`). `safeLen` was never part of the public API; it may have been an internal compiler helper or confusion with another type.

**Safe pattern**:
```nim
if n.len >= 1 and n[0].kind in {nnkIdent, nnkSym}:
  # safe access
```

### QUIRK#C003 — `{.init.}` pragma unsupported for local variables

**Symptom**: `var x {.init.} = 0` fails with "invalid pragma: init".

**Root cause**: Nim 2.2.10 does not support `{.init.}` as a variable annotation. Local variables are zero-initialized by default for numeric types.

**Safe pattern**:
```nim
var total = 0   # implicitly initialized to 0
```

### QUIRK#C004 — Table `[]` access can raise KeyError

**Symptom**: `funcMap[key].totalBranches.inc` raises `ref KeyError` at runtime when key is missing, even after `notin` check in some edge cases.

**Root cause**: In `{.raises: [].}` procs, any unhandled exception causes compilation failure. `TableRef[]` raises `KeyError`.

**Safe pattern**:
```nim
var fs = funcMap.getOrDefault(key)
fs.totalBranches.inc
funcMap[key] = fs
```
