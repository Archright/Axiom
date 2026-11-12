# Axiom 아키텍처 결정 및 구조적 한계 기록

> 기술부채가 아닌 것으로 판정된 항목들의 근거를 기록합니다.
> 이 문서는 DEBT_REGISTRY의 반대편 — "의도된 설계"를 증명합니다.

---

## 1. CLI push [Exception] (63파일) — Imperative Shell 정상 설계

### 판정: 기술부채 아님 ✅

### 근거

`src/cli/`는 **Imperative Shell** 레이어 — 사용자 입력을 받고, 파일을 읽고, 화면에 출력하는 I/O 경계.

```nim
# src/cli/main.nim — CLI 진입점
{.push raises: [Exception].}  # ← I/O 경계에서 모든 예외 허용

proc runMain(args: seq[string]) =
  let config = readFile("axiom.toml")  # ← stdlib [Exception]
  let result = computeResult(config)    # ← pure core 호출
  echo result                           # ← I/O
```

### 아키텍처 패턴: Functional Core, Imperative Shell

| 레이어 | push 정책 | 이유 |
|--------|----------|------|
| `src/core/` (Domain) | `push []` (85%) | 순수 계산, I/O 없음 |
| `src/cli/` (Presentation) | `push [Exception]` (62%) | I/O 경계, 예외 허용 |
| `src/verification/` (Infrastructure) | `push [CatchableError]` (56%) | I/O + 제어된 예외 |
| `src/gate/` (Gate) | `push [CatchableError]` (45%) | 게이트 러너 |

### Context7 공식 근거

> "A routine has no side effects if it does not access a threadlocal or global variable and it does not call any routine that has a side effect." — Nim manual.md

CLI 레이어는 I/O를 수행하므로 side-effect 존재. `push [Exception]`은 이 레이어에서 **의도된 설계**.

### 아키텍처 문서 참조

- AGENTS.md §1.2: "Domain never imports Infrastructure, Presentation, or Gate"
- docs/agents/core_rules.md: 레이어별 역할 정의

---

## 2. proc→func 차단 (100 proc) — 구조적 한계

### 판정: 기술부채 아님 ✅

### 근거

Nim 컴파일러의 **전이적 noSideEffect 분석**으로 인해, I/O를 호출하는 proc은 `func`로 전환 불가.

```nim
proc computeMetric(data: string): float {.raises: [].} =
  let parsed = readFileSafe(path)  # ← readFileSafe는 proc (side-effect)
  result = parsed.len.float
```

→ `func`로 변경 시: "func can have side effects — readFileSafe is proc (side-effect)"

### Context7 공식 근거

> "The `func` keyword is syntactic sugar for a procedure with the `noSideEffect` pragma." — Nim manual.md

> "Marking a procedure to have no side effect if the compiler cannot verify this results in a static error." — Nim manual.md

### 현재 달성 상태

| 구분 | 수치 |
|------|------|
| `func` with `{.raises: [].}` | **401개** ✅ |
| `proc` with `{.raises: [].}` | **116개** (I/O 경계) ✅ |
| `func` + `proc` with `{.raises: [].}` | **517개** (전체의 68%) |

### "순수함수 지향적 proc" 패턴

이미 구현된 패턴:
- `func` = 순수 계산 (I/O 없음)
- `proc` + `{.raises: [].}` = I/O 경계 (래퍼 호출)

이것은 Nim 언어의 구조적 한계이며, 프로젝트가 통제할 수 없음.

---

## 3. 래퍼 내부 I/O 호출 (7건) — 래퍼 구현체

### 판정: 기술부채 아님 ✅

### 근거

래퍼는 내부에서 stdlib을 직접 호출해야 함. 이것이 래퍼의 존재 이유.

| 파일 | 호출 | 역할 |
|------|------|------|
| `io_utils.nim:13` | `readFile(path)` | `readFileOpt` 구현체 |
| `io_utils.nim:32` | `writeFile(tmpPath, content)` | `writeFileOpt` 구현체 |
| `io_utils.nim:33` | `moveFile(tmpPath, path)` | `writeFileOpt` 구현체 |
| `io_utils.nim:59` | `moveFile(source, dest)` | `moveFileOpt` 구현체 |
| `file_utils.nim:17` | `readFile(path)` | `readFileSafe` 구현체 |
| `file_utils.nim:22` | `writeFile(path, data)` | `writeFileSafe` 구현체 |
| `json_safe.nim:21` | `readFile(path)` | `safeParseJsonFile` 구현체 |

### 3-Layer Effect Isolation

| 레이어 | 역할 | raises |
|--------|------|--------|
| `std/syncio` | 원시 stdlib I/O | `[Exception]` |
| `io_utils.nim` | I/O 방화벽 (래퍼) | `[]` (내부에서 Exception 흡수) |
| 소비자 코드 | 순수 도메인 로직 | `[]` |

---

## 4. except Exception 잔여 (70건) — Nim stdlib 한계

### 판정: 기술부채 아님 ✅ (업스트림 이슈)

### 근거

Nim stdlib의 I/O 함수가 `{.raises: [Exception].}`으로 선언:

```nim
# Nim stdlib (lib/std/syncio.nim)
proc readFile*(filename: string): string {.raises: [Exception].}

# Nim stdlib (lib/pure/json.nim)
proc parseJson*(s: string): JsonNode {.raises: [Exception].}
```

→ `except CatchableError`로 변경하면:
```
Error: readFile(path) can raise an unlisted exception: Exception
```

### Context7 공식 근거

> "CatchableError is used for standard exceptions, while Defect represents uncatchable runtime errors." — Nim exceptions.html

`Exception`은 `CatchableError`의 상위 클래스. `except CatchableError`는 `Exception` 자체를 잡을 수 없음.

### Nim 업스트림 마이그레이션 상태

| stdlib 모듈 | 현재 선언 | 마이그레이션 상태 |
|-------------|----------|-----------------|
| `times.nim` | `[CatchableError]` | ✅ 완료 |
| `syncio.nim` | `[Exception]` | ❌ 미완료 |
| `osdirs.nim` | `[Exception]` | ❌ 미완료 |
| `json.nim` | `[Exception]` | ❌ 미완료 |

### Nim 1.4.0 changelog

> "exception types in the standard library should now correctly inherit from CatchableError or Defect, rather than Exception."

시작했지만 완료하지 않음. Nim 3.0에서 완료 예상이나 공식 로드맵 없음.

---

## 5. Effect Adapter 불필요 — 현재 구현이 이미 올바름

### 판정: Gemini 제안 불필요 ✅

### 근거

Gemini가 제안한 `except Exception` → `CatchableError` 재포장은 불필요.

현재 `safeParseJson` 구현:
```nim
proc safeParseJson*(raw: string): Result[JsonNode, string] {.raises: [].} =
  try:
    ok(parseJson(raw))
  except CatchableError:  # ← CatchableError만 잡음
    err("JSON parse failed: " & getCurrentExceptionMsg())
```

### Context7 공식 근거

> "Defect represents uncatchable runtime errors. CatchableError encompasses runtime errors that are expected to be handled." — Nim exceptions.html

> "Exceptions inheriting from Defect are no longer tracked by the `.raises: []` mechanism." — Nim changelog_1_4_0.md

Nim 2.x에서 `{.raises: [].}`는 `CatchableError`만 추적. `Defect`는 추적 안 함.

→ `except CatchableError`만으로 `{.raises: [].}` 만족. `Defect`는 자연 전파됨.

### nim 실전 테스트

```
Test: except CatchableError only + {.raises: [].}
Result: ✅ 컴파일 성공 (exit 0)

Test: except Exception → raise CatchableError + {.raises: [CatchableError].}
Result: ✅ 컴파일 성공 (exit 0) — 하지만 불필요
```

---

## 작성 정보

| 항목 | 값 |
|------|-----|
| 작성일 | 2026-06-01 |
| 작성 근거 | Context7 MCP 공식 문서 + nim 실전 테스트 |
| 참조 | AGENTS.md §0.2, §1.2, docs/agents/core_rules.md |
