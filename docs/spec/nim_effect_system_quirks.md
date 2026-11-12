# Nim Effect System 특이사항 레지스트리

> 이 문서는 `proc` → `func` 전환 과정에서 발견한 Nim 컴파일러의 side effect 판정 특이사항을 기록합니다.
> 모든 에이전트는 func/proc 전환 시 이 문서를 먼저 참조해야 합니다.
> AGENTS.md §0.6 (Static First Enforcement)의 실행 부속서입니다.

---

## §1. Nim stdlib side effect 목록

Nim 표준 라이브러리에서 side effect로 마킹된 함수들입니다. 이 함수들을 호출하는 함수는 **반드시 `proc`으로 유지**해야 합니다.

### 1.1 JSON 파싱 (`std/json`)

| 함수 | side effect 원인 | 영향 범위 |
|------|-----------------|----------|
| `parseJson` | 낭비 메모리 할당 + 상태 변경 | `parseJson`을 호출하는 **모든 함수**가 side effect로 판정됨 |
| `parseJson` → `JsonNode` | 위와 동일 | JSON 문자열을 파싱하는 모든 유틸리티 |

**영향 받는 프로젝트 모듈**:
- `core/logic/pipeline_trace_artifacts.nim`: `parseCounterExampleInputNode`, `bindingsFromCounterExample`
- `verification/state_manager.nim`: `resetHighAttemptProofState`, `propagateVerifiedDuplicateProofState`, `recomputeProofStateSummary`
- `verification/proof_state_projection.nim`: `applyProofStateSyncStatus`, `applyCertificateProjection`, `proofStateEntryFromCertificate`
- `verification/static_rules.nim`: `staticRuleToJson`, `jsonToStaticRule`
- `verification/leanstral_gateway.nim`: `parseLeanstralJson`
- `verification/thought_dashboard.nim`: `summaryJson`, `renderThoughtDashboard`
- `verification/analyzer/analyzer_shared_cert.nim`: `parseJsonSafe`

**근거**: Nim 2.2.10 `lib/pure/json.nim:1043` — `parseJson`은 `{.noSideEffect.}` 미선언.

**대안**: 현재 없음. Nim 표준 라이브러리의 구조적 특성. 향후 Nim 버전에서 `parseJson`이 pure로 마킹되면 재평가 가능.

### 1.2 파일 I/O (`std/syncio`, `std/os`)

| 함수 | side effect 원인 |
|------|-----------------|
| `readFile`, `writeFile` | 디스크 I/O |
| `fileExists`, `dirExists` | 파일시스템 쿼리 |
| `walkDir`, `walkDirRec`, `walkFiles` | 디렉토리 탐색 |
| `open`, `close`, `readLine`, `write` | 스트림 I/O |
| `removeFile`, `moveFile`, `copyFile` | 파일시스템 변경 |
| `existsOrCreateDir`, `createDir` | 디렉토리 생성 |
| `getCurrentDir` | OS 호출 |

**정책**: 위 함수를 호출하는 proc은 `func`로 전환 불가. I/O 경계(현관)로 분류.

### 1.3 시간 (`std/times`)

| 함수 | side effect 원인 |
|------|-----------------|
| `now()`, `getTime()` | 시스템 클럭 읽기 |
| `cpuTime()`, `epochTime()` | 시스템 클럭 읽기 |

**정책**: 시간 함수를 호출하는 proc은 `func`로 전환 불가.

### 1.4 프로세스 (`std/osproc`)

| 함수 | side effect 원인 |
|------|-----------------|
| `startProcess`, `execCmdEx`, `execProcess` | 프로세스 생성 |
| `waitForExit`, `peekExitCode` | 프로세스 상태 확인 |

**정책**: 프로세스 함수를 호출하는 proc은 `func`로 전환 불가.

### 1.5 네트워크 (`std/httpclient`)

| 함수 | side effect 원인 |
|------|-----------------|
| `HttpClient.get`, `HttpClient.post` | 네트워크 I/O |
| `newHttpClient` | 소켓 생성 |

**정책**: 네트워크 함수를 호출하는 proc은 `func`로 전환 불가.

### 1.6 콘솔 (`std/streams`)

| 함수 | side effect 원인 |
|------|-----------------|
| `echo`, `writeLine` | stdout/stderr 출력 |
| `stdout.write`, `stderr.write` | 스트림 I/O |

**정책**: 콘솔 출력을 호출하는 proc은 `func`로 전환 불가.

### 1.7 시스템 호출

| 함수 | side effect 원인 |
|------|-----------------|
| `getEnv` | 환경변수 읽기 |
| `getCurrentDir` | OS 경로 쿼리 |
| `setrlimit` | 리소스 제한 변경 |
| `initLock`, `acquire`, `release` | 뮤텍스 조작 |
| `getThreadId` | 스레드 상태 |

---

## §2. Nim 컴파일러 false positive 패턴

### 2.1 `result` 필드 쓰기 (해결됨)

Nim 컴파일러가 `result.field = value`를 side effect로 오인하는 경우.

**해결법**: GUARDIAN §15 생성자 패턴 사용:
```nim
# ❌ 컴파일러 에러: "can have side effects"
func f(): Result[T, E] =
  result.ok = false
  result.err = value

# ✅ 생성자 패턴: 컴파일러가 pure로 판정
func f(): Result[T, E] =
  Result[T, E](ok: false, err: value)
```

### 2.2 `{.cast(noSideEffect).}` 남용 (금지)

GUARDIAN §11에 따라 `{.cast(noSideEffect).}`로 compiler effect system을 우회하는 것은 **금지**입니다. 이는 side effect를 숨기는 것이지 제거하는 것이 아닙니다.

**예외**: Nim 1.4.0+에서 `{.cast(noSideEffect).}: ...` 블록 구문은 허용되되, **남용은 금지**. 반드시 생성자 패턴을 먼저 시도할 것.

---

## §3. 전환 방법론 — "공격적 전환 + 컴파일러 안전망"

### 3.1 절차

1. 대상 파일의 모든 `proc`을 `func`로 일괄 변경 (`sed -i 's/^\(\s*\)proc /\1func /g'`)
2. `nim c` 실행 — side effect가 있는 func은 컴파일 에러로 탐지됨
3. 에러 메시지에서 side effect 원인 추적 (Hint 체인 확인)
4. 실제 I/O 경계 proc을 `proc`로 복원
5. 반복 until 컴파일 성공

### 3.2 안전성 보장

Context7 공식 문서:
> "It is a static error to mark a proc/iterator to have no side effect if the compiler cannot verify this." — Nim manual

컴파일러가 side effect를 놓치는 경우는 **존재하지 않습니다**. false negative는 없고, false positive만 있습니다 (§2 참조).

### 3.3 자동 분류 결과 (2026-05-31)

| 분류 | 건수 | 비율 |
|------|------|------|
| 순수 연산 → func 전환 성공 | **95건** | 71% |
| I/O 경계 → proc 유지 (컴파일러 판정) | **38건** | 29% |
| **합계** | **133건** | 100% |

---

## §4. discard 패턴 분류 (Context7 검증 완료, 2026-05-31)

Nim 공식 문서: "The discard statement evaluates its expression for side-effects and throws the expression's resulting value away, and should only be used when ignoring this value is known not to cause problems."

Nim 공식 문서: "Ignoring the return value of a procedure without using a discard statement is a static error."

### 4.1 정당한 discard 패턴

| 패턴 | 근거 | 예시 |
|------|------|------|
| best-effort cleanup | cleanup 실패는 안전하게 무시 가능 | `try: removeDir(tmp) except: discard` |
| case exhaustiveness | Nim 공식 관용 패턴 | `else: discard` (enum 미매칭) |
| 부수효과 목적 반환값 무시 | Nim 공식: "useful when interested in side effects" | `discard writeFileOpt(path, data)` |
| void context | Nim 언어 요구사항 | `discard` 필수 (컴파일 에러 방지) |
| `{.discardable.}` 대상 | 언어 수준 지원 | discardable pragma 함수 호출 |

### 4.2 문제적 discard 패턴

| 패턴 | 문제 | 대안 |
|------|------|------|
| 맹목적 에러 삼킴 | `try: criticalOp() except: discard` — 에러 원인 소실 | `gripIO`/`gripVoid` from `error_bridge.nim` |
| 파싱 실패 무시 | `try: parseJson(data) except: discard` — 데이터 손실 | Result 반환 또는 에러 로깅 |

### 4.3 Axiom 프로젝트 분석 결과 (2026-05-31)

| 유형 | 수 | 판정 |
|------|-----|------|
| case else: discard | ~200 | ✅ 정당 |
| best-effort cleanup | ~50 | ✅ 정당 |
| 부수효과 반환값 무시 | ~150 | ✅ 정당 (대부분 `writeFileOpt`, `execCmdEx`) |
| 맹목적 에러 삼킴 | ~1 | ❌ gripOr로 변환 완료 |
| **합계** | **446** | |

---

## §5. 업데이트 정책

- Nim 버전 업그레이드 시 이 문서를 재검증할 것
- `parseJson`이 future Nim 버전에서 pure로 마킹되면 §1.1 전체 재평가
- 새로운 stdlib 모듈 사용 시 side effect 여부를 먼저 확인할 것
- 이 문서는 `docs/spec/nim_effect_system_quirks.md`에 위치하며, AGENTS.md §0.5b에서 참조

---

## §6. {.raises: [].} 컨텍스트에서의 I/O 금지 패턴

### 6.1 문제

`{.raises: [].}`로 선언된 함수에서는 **모든 I/O가 컴파일 에러**입니다:
- `stderr.writeLine(...)` → `IOError` 발생 → 컴파일 실패
- `echo` → `IOError` 발생 가능 → 컴파일 실패
- `writeFile(...)` → `IOError` 발생 → 컴파일 실패

### 6.2 금지 패턴: try/except로 우회

```nim
# ❌ 금지: DEBT#021에서 제거한 패턴을 다시 도입하는 것
proc doSomething() {.raises: [].} =
  if not someIOOperation():
    try: stderr.writeLine("error") except: discard
```

**왜 금지**: 프로젝트는 DEBT#021에서 ~170개의 try/except를 제거하고 gripOr 패턴으로 전환했습니다. 새 try/except를 추가하는 것은 이 역사를 되돌리는 것입니다.

### 6.3 올바른 패턴: discard + 정직한 주석

```nim
# ✅ 올바른: 제약을 정직하게 인정
proc doSomething() {.raises: [].} =
  discard someIOOperation()  # write failure is non-fatal; {.raises: [].} prevents error logging
```

### 6.4 대안: 함수 시그니처 변경 가능 시

```nim
# ✅ 대안: 에러를 호출자에게 전파
proc doSomething(): Result[void, string] {.raises: [].} =
  let res = someIOOperation()
  if not res:
    return Result[void, string].err("IO operation failed")
```

### 6.5 대안: gripOr 패턴 (error_bridge.nim)

```nim
# ✅ 대안: gripOr로 안전하게 처리
import ../core/error_bridge
proc doSomething() {.raises: [].} =
  let res = gripOr(someIOOperation(), false)
  # res가 에러면 false 반환, 성공하면 원래 값
```


## §7. Stdlib Missing Raises Pragma Forces `except Exception`

### 7.1 발견 일자
2026-06-03 (DEBT#141 청산 중 Context7 공식 문서 검증으로 식별)

### 7.2 증상
Nim stdlib의 일부 proc (`parseXml`, `moveFile`, `writeFile` 등)은 명시적인 `raises` pragma를 **선언하지 않음**. Nim compiler의 기본 동작은 "raises pragma 없음 = can raise Exception". 이로 인해 `{.push raises: [].}` 아래에서도 compiler는 해당 proc이 `Exception`을 raise할 수 있다고 판단.

결과적으로 `except CatchableError:`만으로는 compiler의 "unlisted exception" 검사를 통과할 수 없으며, `{.raises: [].}` contract를 위반함.

### 7.3 영향 받는 모듈

| 모듈 | proc | stdlib 호출 | 원인 |
|------|------|-------------|------|
| ~~tree_sitter_parse.nim~~ (deleted Phase 5.3) | `parseWithTreeSitter` | `parseXml(newStringStream(...))` | `parseXml` lacks raises pragma |
| ~~`src/core/io_utils.nim`~~ (deleted) | `writeFileOpt` | `writeFile`, `moveFile` | `moveFile` lacks raises pragma — now isolated in `src/core/trusted/stdlib_shield.nim` |
| ~~`src/core/io_utils.nim`~~ (deleted) | `moveFileOpt` | `moveFile` | `moveFile` lacks raises pragma — now isolated in `src/core/trusted/stdlib_shield.nim` |
| `src/gate/nimtry/nimtry_extract_part3_part2.nim` | `extractModuleFactsV4` | `openParser` | `openParser` (compiler/parser) lacks raises pragma; raises generic `Exception` on malformed input |
| `src/core/trusted/stdlib_shield.nim` | `safeParseXml` | `parseXml` | `parseXml` lacks raises pragma; shield converts to `XmlParseError` (CatchableError) |
| `src/core/trusted/stdlib_shield.nim` | `safeMoveFile` | `moveFile` | `moveFile` lacks raises pragma; shield converts to `FileMoveError` (CatchableError) |

### 7.4 시도한 실패 패턴

```nim
# ❌ 실패: CatchableError만으로는 compiler 불만족
except CatchableError as e:
  # Error: parseXml can raise an unlisted exception: Exception
```

```nim
# ❌ 실패: Defect re-raise도 불가능
except Exception as e:
  if e of Defect:
    raise  # Error: Exception can raise an unlisted exception: Exception
           # (raise 자체가 Exception으로 tracked됨)
```

### 7.5 허용 패턴 (근거 기반 workaround)

**Canonical**: Effect-Isolation Encapsulation via `{.raises: [CatchableError].}` wrapper.

```nim
# src/core/utils/io_utils_isolation.nim
proc isolatedParseXml*(xmlStr: string): XmlNode {.raises: [CatchableError].} =
  try:
    result = parseXml(newStringStream(xmlStr))
  except Exception as e:
    # Quirk isolation: ONLY this module may use except Exception for stdlib.
    raise newException(ValueError, "xml parse failed: " & e.msg)

proc isolatedMoveFile*(source, dest: string) {.raises: [CatchableError].} =
  try:
    moveFile(source, dest)
  except Exception as e:
    raise newException(IOError, "moveFile failed: " & e.msg)
```

```nim
# ✅ Business logic uses clean CatchableError contract
except CatchableError as e:
  err("writeFileOpt(" & path & "): " & e.msg)
```

### 7.6 Context7 근거
- Nim Manual §Exception Tracking: "Procedures with an explicit `.raises: []` annotation are assumed not to raise exceptions, even if they contain operations that could potentially raise."
- Nim Manual §Pragmas > acyclic: Compiler assumes worst-case `Exception` when raises pragma is absent.
- Nim 2.0 Changelog: `warnBareExcept` warns on bare `except:` but does not address `except Exception:` vs missing stdlib raises pragma.

### 7.7 장기적 해결책
1. **Immediate**: `src/core/utils/io_utils_isolation.nim` 유지 — 모든 stdlib missing-raises-pragma 호출은 이 모듈을 통해 격리
2. **Upstream**: Nim stdlib에 `parseXml`, `moveFile`, `writeFile` 등에 raises pragma 추가 PR
3. 프로젝트 난이도: Nim 커뮤니티 PR 필요, 버전 호환성 문제
4. 현재는 `io_utils_isolation.nim` + 주석으로 관리

### 7.8 정책
- **NEP-1 권장**: `except CatchableError:`가 canonical
- **예외 허용**: stdlib proc이 raises pragma를 누락한 경우, **`src/core/utils/io_utils_isolation.nim` 낭비 패턴을 통해 격리** 후 사용 가능
- **금지**: 비즈니스 로직(`.nim` 파일) 낭비에 직접 `except Exception:`을 남겨두는 것
- **필수**: isolation 모듈 낭비에 `# Quirk: ...` 주석 + `docs/spec/nim_effect_system_quirks.md` cross-reference
- **금지**: Defect swallowing을 의도적으로 이용한 `except Exception:` (§6.2 참조)

## §9. Effect Cast Registry — All `{.cast(noSideEffect).}` and `{.cast(raises: []).}` Usages

> **AGENTS.md §0.5b Compliance**: Every effect cast in the codebase MUST be registered here with reason, verification, and SEE annotation in source.
> Agents adding new casts MUST update this registry in the same commit.

### 9.1 `{.cast(noSideEffect).}` Registry

#### [src/sieve/ast_inspector.nim]
- **Location**: Line 137
- **Reason**: `inspectAstNodeSafe` is declared as `func` (implies `{.noSideEffect.}`), but calls `parseNimRes(sourceCode)` which is a `proc` with file I/O side effects (Nim compiler's parser, internally reads from filesystem streams). The cast is needed because the function is designed as a safe wrapper that treats parsing as pure: (a) input is a string parameter, not a file path — no external state mutation, (b) the function returns an empty `AstInspectionResult()` on parse failure, ensuring deterministic behavior.
- **Verification**: `inspectAstNodeSafe` returns `AstInspectionResult()` (empty) if `parseRes.isErr`. The actual AST inspection (`inspectAstNode`) is already a `func`. No external state mutation occurs — the only "side effect" is the parsing step which operates on an in-memory string via `parseNimRes`. The `func` declaration + `raises: []` contract ensures no exceptions escape.
- **SEE annotation required**: Yes — `## [SEE: nim_effect_system_quirks.md]` above the cast

**Total `{.cast(noSideEffect).}` usages**: 8

#### [src/core/pure/json_parse.nim]
- **Location**: Line 20
- **Reason**: `pureParseJson` wraps `std/json.parseJson` which is declared as `proc` in stdlib due to heap allocation and exception raising. In Nim's ORC memory manager, heap allocation is not a logical side effect. The wrapper enables `src/core/` functions that call `parseJson` to be declared as `func`, eliminating transitive side-effect contamination from stdlib annotation deficiency.
- **Verification**: Input is a `string` parameter (no external state mutation). The function delegates to `stdJson.parseJson` which is deterministic for identical inputs. `ValueError` on malformed JSON propagates through the caller's `{.raises: [].}` contract. No global state, no I/O, no thread-local access.
- **SEE annotation required**: Yes — `## [SEE: nim_effect_system_quirks.md §1.1, §9.1]` above the module and cast

#### [src/core/bmc/bmc_generic.nim:192]
- **Location**: Line 192
- **Reason**: `getMonoTime()` reads the system monotonic clock for wall-clock timeout guard inside `genericExplore` (a `func`). `std/monotimes.getMonoTime()` is classified as side-effecting (§1.3 — system clock read), but the operation is deterministic in this context: it only reads a monotonic counter for timeout comparison and does not mutate any state. The cast allows the BMC explore loop to remain a `func`, preserving the purity contract of the BMC engine core.
- **Verification**: `getMonoTime()` is called only to compare against a pre-computed `deadline: MonoTime` parameter. The comparison result controls early exit (`result.timedOut = true`). No external state mutation — the monotonic clock is a read-only OS query. The `func` declaration + `raises: []` contract ensures no exceptions escape.
- **SEE annotation required**: Yes — `## [SEE: nim_effect_system_quirks.md §9.1]` above the cast

#### [src/core/bmc/bmc_generic.nim:229]
- **Location**: Line 229
- **Reason**: `getMonoTime() + initDuration(milliseconds = config.timeoutMs)` initializes the deadline value inside `verifyGenericProperty` (a `func`). Both `getMonoTime()` and `initDuration()` are stdlib functions classified as effectful (§1.3 — system clock read), but the operation is deterministic: it computes a fixed deadline timestamp from the current monotonic clock plus a config-derived duration. No state mutation occurs.
- **Verification**: The deadline is a local `var` used only to pass into `genericExplore`. `initDuration` is pure arithmetic on a duration value. No global state, no I/O, no thread-local access. The `func` declaration + `raises: []` contract ensures no exceptions escape.
- **SEE annotation required**: Yes — `## [SEE: nim_effect_system_quirks.md §9.1]` above the cast

#### [src/core/bmc/bmc_engine.nim:137]
- **Location**: Line 137
- **Reason**: `getMonoTime()` reads the system monotonic clock for wall-clock timeout guard inside `explore` (a `func`). Same rationale as `bmc_generic.nim:192` — `std/monotimes.getMonoTime()` is classified as side-effecting but operates as a read-only monotonic clock query for timeout comparison. The cast allows the BMC race-condition explore loop to remain a `func`.
- **Verification**: `getMonoTime()` is compared against a pre-computed `deadline: MonoTime` parameter. The comparison controls early exit (`result.timedOut = true`). No external state mutation. The `func` declaration + `raises: []` contract ensures no exceptions escape.
- **SEE annotation required**: Yes — `## [SEE: nim_effect_system_quirks.md §9.1]` above the cast

#### [src/core/bmc/bmc_engine.nim:154]
- **Location**: Line 154
- **Reason**: `getMonoTime() + initDuration(milliseconds = bmcWallClockTimeoutMs)` initializes the deadline value inside `verifyRaceCondition` (a `func`). Same rationale as `bmc_generic.nim:229` — both functions are classified as effectful but the operation is deterministic: computing a fixed deadline timestamp from the monotonic clock plus a constant duration.
- **Verification**: The deadline is a local `var` used only to pass into `explore`. No global state, no I/O, no thread-local access. The `func` declaration + `raises: []` contract ensures no exceptions escape.
- **SEE annotation required**: Yes — `## [SEE: nim_effect_system_quirks.md §9.1]` above the cast

#### [src/core/topology/lock.nim:115]
- **Location**: Line 115
- **Reason**: `parseTime(meta.created_at, "yyyy-MM-dd'T'HH:mm:sszzz", utc())` parses a datetime string into a `Time` object inside `checkTransitionalTTLWithTime` (a `func`). `std/times.parseTime` is classified as side-effecting (§1.3 — stdlib time functions), but the operation is deterministic: it parses a string parameter against a format pattern and returns a `Time` value. No state mutation occurs — the input is a string field from the lock data, not a system resource.
- **Verification**: `parseTime` receives a `string` parameter (`meta.created_at`) and format literals. The result is assigned to a local `var created: Time` and used only for arithmetic (`currentTime.toTime - created`).inDays. No external state, no I/O, no thread-local access. The `func` declaration ensures purity.
- **SEE annotation required**: Yes — `## [SEE: nim_effect_system_quirks.md §9.1]` above the cast

#### [src/core/topology/lock.nim:219]
- **Location**: Line 219
- **Reason**: `fileExists(p)` is wrapped in a `{.cast(noSideEffect).}` block inside a closure passed to the pure `identifyStaleEntries` func. `std/os.fileExists` is classified as side-effecting (§1.2 — filesystem query), but it is used here as a read-only predicate to check file existence, and the result is immediately consumed by the pure staleness-identification logic. The cast is needed because the `existsFn` closure must satisfy `{.noSideEffect, raises: []}` to be passed to a `func`.
- **Verification**: `fileExists` is a read-only filesystem predicate — it does not mutate state. The closure captures no mutable state; it receives a `string` path and returns a `bool`. The `proc removeStaleEntries` is declared as `proc` (correctly — it is an I/O shell), but the inner closure must be pure for the `func identifyStaleEntries` to accept it.
- **SEE annotation required**: Yes — `## [SEE: nim_effect_system_quirks.md §9.1]` above the cast

### 9.2 `{.cast(raises: []).}` Registry

#### [src/verification/llm_backend.nim]
- **Location**: Line 59
- **Reason**: `httpLLMBackend` is a factory returning `func` (LLMBackend type = `proc(LLMRequest): LLMResponse {.gcsafe, raises: [].}`). The inner closure makes HTTP calls (`newHttpClient`, `client.postContent`, `parseJsonOpt`) which can raise `CatchableError`. Nim stdlib's `httpclient` module lacks proper `raises` pragma annotations (§7), so the compiler tracks these as potentially raising `Exception`. The `{.cast(raises: []).}` block overrides the compiler's effect tracking to satisfy the `LLMBackend` type contract — same pattern as Nim stdlib's own `json.nim` (§8.3).
- **Verification**: All exception paths are handled by `except CatchableError as e:` which returns `LLMResponse(success: false, error: ...)`. No exceptions escape the cast block. The `try/except` structure ensures runtime safety. Timeout and connection errors are specifically detected and mapped to structured `LLMResponse` fields (`timedOut: true`).
- **SEE annotation required**: Yes — `## [SEE: nim_effect_system_quirks.md]` above the cast

**Total `{.cast(raises: []).}` usages**: 1

### 9.3 Other Effect System Workarounds

| Workaround | Location | Status | Details |
|-----------|----------|--------|--------|
| `{.push noSideEffect.}` | `src/cli/report_format.nim`, `report_layout.nim`, `report_render.nim`, `version.nim`, 15+ `src/core/` modules | Normal pragma (not a workaround) | Standard Nim mechanism for bulk func marking |
| Constructor pattern (§2.1) | Multiple `src/core/` modules | Resolved | Avoids compiler false positive on `result.field = value` |
| Effect-Isolation Encapsulation (§7.5) | `src/core/utils/io_utils_isolation.nim` | Active workaround | stdlib missing raises pragma → `except Exception` isolation wrapper |

---

## §8. `{.cast(raises: []).}` — Official Nim stdlib Mechanism for Effect Override

### 8.1 발견 일자
2026-06-04 (DEBT#143 root-cause analysis 중 Context7 + Nim stdlib 소스 검증)

### 8.2 증상
`std/asyncdispatch.waitFor`는 `{.raises: [Exception].}`를 선언합니다. 이를 호출하는 proc이 `{.raises: [AxiomLspError].}`만 선언하면:
```
Error: waitFor(fut) can raise an unlisted exception: Exception
```
`safeWaitFor` template은 inline expansion 특성상 compiler가 exception flow를 추적하지 못해 `{.push raises: [Exception].}` 전체 모듈 오염을 해결하지 못했습니다.

### 8.3 Nim stdlib 사용 증거
Nim 2.2.10 공식 릴리즈의 Nim core team이 동일한 문제에 동일한 pragma를 사용합니다:

```nim
# nim-2.2.10/lib/pure/json.nim
{.cast(raises: []).}: # bug #19303
  result = a.elems == b.elems

# nim-2.2.10/lib/pure/streamwrapper.nim
{.cast(raises: []), cast(tags: []).}:
  ...

# nim-2.2.10/lib/std/socketstreams.nim
{.cast(raises: [IOError, OSError]), cast(tags: []).}:
  ...
```

### 8.4 핵심 규칙: statement context only
`{.cast(raises: []).}`는 **statement/block context**에서만 유효합니다. proc declaration에 직접 붙이면:
```
Error: 'cast' pragma only allowed in a statement context
```

올바른 패턴은 `json.nim`과 동일하게 **body 내부 block** 또는 **proc declaration 외부 block**입니다.

### 8.5 Axiom Canonical Pattern: Exception Boundary for async/waitFor

**파일**: `src/verification/lean_lsp.nim`

```nim
proc safeWaitFor*[T](fut: Future[T]): T {.raises: [AxiomLspError].} =
  {.cast(raises: [AxiomLspError]).}:
    try:
      return waitFor(fut)
    except Exception as e:
      if e of Defect: raise e        # Defect는 unrecoverable — crash fast
      raise newException(AxiomLspError, "LSP operation failed: " & e.msg, e)

proc getLiveDiagnosticFeedback*(...): LeanLiveDiagnosticFeedback {.raises: [AxiomLspError].} =
  {.cast(raises: [AxiomLspError]).}:
    var client: LeanLspClient = nil
    try:
      client = startLeanLsp(leanExe)
      let currentDir = getCurrentDir()
      if not safeWaitFor(client.initialize(currentDir)):
        return LeanLiveDiagnosticFeedback(...)
      client.openDocument(filePath, source)
      return safeWaitFor(client.getLiveDiagnosticFeedback(...))
    except AxiomLspError as e:
      return LeanLiveDiagnosticFeedback(...)
    except CatchableError as e:
      return LeanLiveDiagnosticFeedback(...)
    finally:
      if not client.isNil:
        client.shutdown()
```

**설계 의도**:
1. **proc declaration**은 `{.raises: [AxiomLspError].}`로 정직하게 계약합니다 — caller는 오직 `AxiomLspError`만 처리하면 됩니다.
2. **`cast` block**은 compiler의 effect tracker를 override합니다 — `waitFor`의 `Exception`, `startLeanLsp`의 `CatchableError`, `getCurrentDir`의 `OSError`가 모두 unlisted exception으로 탈출하지 못하게 합니다.
3. **runtime safety**는 `try/except`가 보장합니다 — `except Exception` 안에서 `Defect`는 re-raise되어 crash합니다.
4. **parent exception chaining** (`newException(AxiomLspError, msg, e)`)은 원래 stack trace를 보존합니다.

### 8.6 주의사항
- `cast(raises: [X])`는 compiler에게 "이 block은 오직 X만 raise합니다"라고 말하는 것입니다. 이 계약을 runtime에서 위반하면(예: `Defect`가 탈출) UB는 아니지만 contract breach입니다.
- `cast` block 내부에서 `return`은 허용됩니다(일반 statement context와 동일).
- `cast` block은 **최소한의 범위**에 적용할 것 — 전체 proc body보다는 exception boundary가 필요한 구문 주변만 감싸는 것이 유지보수에 유리합니다.

### 8.7 Nim stdlib 기준으로 정당화된 도구
AGENTS.md §0.2 (First-Principles Elegance)에 따라:
- **Ideal**: compile-time 방지 — `cast`는 compile-time에 잘못된 effect tracking을 수정합니다.
- **Elegant**: language-native — Nim core team이 동일한 문제에 동일한 도구를 사용합니다.
- **Fundamental**: no hardcoded exception — `cast`의 인수는 일반적인 `raises` pragma와 동일한 문법을 사용합니다.
- **Deterministic**: identical input → identical output — `cast` block의 범위는 소스 코드에서 명시적입니다.

### 8.8 정책
- **허용**: `std/asyncdispatch.waitFor` 호출처럼 Nim compiler가 과도하게 `Exception`을 추적하는 경우, `{.cast(raises: [SpecificError]).}` block 사용 가능.
- **필수**: `cast` block 내부에는 반드시 `try/except`로 runtime safety를 보장할 것.
- **금지**: `cast` block을 I/O나 side effect를 숨기는 용도로 사용하는 것 (§2.2 `{.cast(noSideEffect).}` 금지 정책과 동일한 spirit).
- **금지**: `cast` block 없이 `except Exception`만으로 effect system을 억제하는 것 (§7.8 참조).

---

## §10. FFI 래퍼의 Side-Effect 분류

### 10.1 발견 일자
2026-06-13 (Context7 기반 아키텍처 주장 검토 중 확인)

### 10.2 증상
외부 C/C++ 함수를 래핑하는 proc은 Nim compiler가 그 효과를 검증할 수 없으므로, **기본적으로 side effect가 있는 것으로 추론**됩니다. `func`로 선언하거나 `{.noSideEffect.}`를 붙이면 컴파일 에러가 발생합니다.

### 10.3 Context7 근거
- Nim Manual: "A routine has no side effects if it doesn't access thread-local or global variables and doesn't call other routines with side effects."
- Nim Manual: `{.cast(noSideEffect).}`는 compiler의 자동 분석을 override할 수 있으나 unsafe할 수 있음.
- Nim 위키/메뉴얼의 모든 `importc`/`importcpp`/`dynlib` 예제는 `proc`로 선언되며 `{.noSideEffect.}`가 없음.

### 10.4 영향 받는 모듈

| 모듈 | FFI 패턴 | 분류 |
|------|----------|------|
| ~~tree_sitter_ffi.nim~~ (deleted Phase 5.3) | `{.importc, cdecl.}` | I/O boundary — C 힙 할당/해제; all tree-sitter FFI modules purged in Phase 5.3 |
| `src/core/sync/sync_utils_resource.nim` | `{.stdcall, dynlib: "kernel32", importc.}` | I/O boundary — OS API |
| `src/core/sync/sync_utils_process.nim` | `{.stdcall, dynlib: "kernel32", importc.}` | I/O boundary — OS API |

### 10.5 ~~~`split_by_effects.sh`~~~ (deleted) 오분류 위험

~~`tools/ci/split_by_effects.sh`~~ (deleted)는 다음 패털만 I/O로 감지했습니다:

```bash
IO_PATTERNS=(
  "readFile" "writeFile" "echo" "execProcess" "startProcess" "open\\("
  "close\\(" "getEnv" "putEnv" "fileExists" "dirExists" "createDir"
  "removeFile" "stdin" "stdout" "stderr" "sleep" "getCurrentDir"
  "getAppFilename" "existsEnv"
)
```

`importc`/`importcpp`/`dynlib`/`{.compile.}`가 **누락**되어 있으므로, FFI 호출만 하는 함수가 `_core.nim`(pure)로 잘못 분류될 수 있습니다.

**예시**:
```nim
# ❌ ~~split_by_effects.sh가~~ pure로 분류할 수 있었음 (deleted)
proc wrapTsParse*(s: string): TSNode =
  let parser = ts_parser_new()   # C heap allocation side effect
  ...
```

### 10.6 권장 패턴

#### 10.6.1 ~~단기: `split_by_effects.sh` 감지 확장~~ (deprecated — file deleted)

```bash
IO_PATTERNS+=(
  "importc"
  "importcpp"
  "dynlib"
  "\\{\\.compile\\.\\}"
)
```

주의: 이는 선언 자체가 아닌 호출부를 정확히 구분하지 못하는 거친 휴리스틱입니다.

#### 10.6.2 중기: `axiomEffect` Custom Pragma 컨벤션

코멘트 기반 `@axiom-effect` 대신 Nim 일급 시민인 Custom Pragma 사용:

```nim
import core/trusted/axiom_pragmas

proc parseWithCache*(filePath: string; language: TSLanguage): TSNode
    {.axiomEffect: IoEffect.} =
  ...

proc pureWrapper*(s: string): string {.axiomEffect: Pure.} =
  ...
```

- `AxiomEffectKind` enum(`Pure`, `IoEffect`)으로 컴파일 타임에 값 검증.
- `nimtry`는 `nkPragma` 노드를 순회하여 `axiomEffect`를 AST 수준에서 추출 (`extractPragmasV4`).
- `@axiom-effect` 코멘트는 ~~`split_by_effects.sh`의~~ 휴리스틱 폴백으로만 유지했으나, 현재는 nimtry의 AST 분석이 이를 대체함.

#### 10.6.3 장기: FFI Shield 모듈 + Distinct Types

C 포인터 핸들을 `distinct` 타입으로 감싸 compile-time에 잘못된 핸들 교차 사용 방지:

```nim
type
  TSParserRaw = ptr object
  TSParser* = distinct TSParserRaw
```

~~tree_sitter_ffi.nim~~ (deleted Phase 5.3) was previously refactored — `TSParser`/`TSTree`/`TSLanguage` were converted to `distinct` types in `tree_sitter/types.nim`. All tree-sitter FFI modules were purged in Phase 5.3; the code block below is historical record only.

```nim
# [HISTORICAL — PURGED Phase 5.3]
# ffi_shield.nim was removed along with tree_sitter/* submodules.
# AST parsing now uses Nim compiler parser in-process via nimtry.
```

도메인 코드는 `ffi_shield`를 통해서만 FFI에 접근하여 효과 경계를 명확히 합니다.

### 10.7 정책
- **FFI proc은 기본 `proc`**: `{.importc.}`/`{.importcpp.}`/`dynlib` 래퍼는 `func`로 전환하지 말 것.
- **FFI 핸들은 `distinct`로 격리**: C 포인터를 raw `ptr object`로 노출하지 말 것.
- **FFI 호출부도 I/O로 분류**: ~~`split_by_effects.sh`는~~ FFI 선언/호출을 pure 영역으로 분류하지 않아야 했음 (deleted — nimtry AST 분석이 대체).
- **명시적 effect 선언 권장**: `{.axiomEffect: Pure/IoEffect.}` pragma 또는 `architecture_policy.lock` `[effect_hints]` 섹션으로 효과 격리 의도를 기록.
- **금지**: FFI 래퍼에 `{.cast(noSideEffect).}` 남용 (§2.2 참조).

---

## §11. Self-Enforcing Architecture — `axiomEffect` & nimtry Effect Integration

### 11.1 `axiomEffect` replaces comment-based effect hints

Phase 1 introduces `{.axiomEffect: Pure.}` and `{.axiomEffect: IoEffect.}` as compile-time custom pragmas defined in `src/core/trusted/axiom_pragmas.nim`. These replace the legacy `# @axiom-effect: IoEffect` comment convention.

**Why custom pragmas are superior**:
- **Compile-time validation**: The `AxiomEffectKind` enum (`Pure`, `IoEffect`) is validated at compile time — a typo like `{.axiomEffect: IoEfekt.}` produces a compiler error, not a silent misclassification.
- **AST-level extraction**: nimtry's `extractPragmasV4` traverses `nkPragma` nodes to find `axiomEffect` pragmas, enabling programmatic analysis without regex heuristics.
- **Type safety**: The pragma is typed, not a raw string — IDE tooling and LSP can introspect it.

The comment-based `@axiom-effect` is retained as a heuristic fallback for ~~`split_by_effects.sh` only~~ (deleted — nimtry AST analysis supersedes).

### 11.2 ~~`split_by_effects.sh` is deprecated~~ (deleted)

~~`tools/ci/split_by_effects.sh`~~ is **deleted**. It was replaced by `src/gate/nimtry/nimtry_cli.nim --full-tree` which performs AST-level analysis.

**Reason for deletion**: `split_by_effects.sh` used regex pattern matching on source text, which produced false positives (e.g., strings containing `readFile` in comments) and false negatives (FFI calls via `importc`/`importcpp`/`dynlib` not in the IO_PATTERNS list — see §10.5). nimtry's AST-level analysis eliminates both classes of error. The tool was deprecated and subsequently removed from the repository.

### 11.3 nimtry effect analysis pipeline

nimtry performs effect classification using a three-source approach:

1. **Call-graph BFS**: Starting from each `proc`/`func` declaration, nimtry traverses the call graph transitively. If any transitive callee reaches I/O (file, console, process, network, system), the root proc is flagged.

2. **`[effect_hints]` from `architecture_policy.lock`**: Explicit declarations in the policy lock file mark modules/procs as `Pure` or `IoEffect` for cases where static analysis is insufficient (e.g., FFI wrappers, `{.cast(noSideEffect).}` blocks).

3. **`axiomEffect` pragmas**: Compile-time annotations on proc declarations. These take precedence when present and are validated by `effect-pragma-consistency`.

**nimtry queries**:
- `effect-pragma-consistency`: Errors when annotation contradicts Nim's effect system (`func` + `IoEffect`, or `proc` + `Pure` without being truly pure).
- `effect-transitive-io`: Warns when a `proc` reaches I/O transitively but lacks `IoEffect` annotation — incomplete effect contract.

### 11.4 `{.effects.}` pragma outputs exception effects only

The `{.effects.}` pragma outputs **exception tracking** information (`{.raises.}` family), NOT side-effect analysis (`{.noSideEffect.}`/`func`).

This is a critical distinction:
- `{.effects.}` → "this proc can raise X, Y, Z" (exception effects)
- `func` / `{.noSideEffect.}` → "this proc does not mutate global state" (side effects)

`{.effects.}` **cannot** be used to determine whether a proc is safe to convert from `proc` to `func`. For that, nimtry's call-graph BFS + `axiomEffect` pragmas are the correct tools (§11.3).

**Context7 evidence**: Nim Manual — "The `effects` pragma outputs hint messages listing potential effects, such as exceptions that can be raised."

### 11.5 Purity gate respects I/O module hints

`src/gate/nimtry/nimtry_cli.nim`'s `PURITY-new-code-must-be-func` rule skips modules that are registered as I/O in `src/gate/nimtry/io_module_registry.nim` (the `[effect_hints]` SSOT). This allows FFI wrapper modules to use `proc` for `{.importc.}` bindings, which the Nim compiler correctly classifies as side-effecting.

Without this carve-out, every `proc` in an FFI module would be flagged as a purity violation, even though `func` is impossible for `importc` calls. The hint registry is therefore part of the effect system contract, not an exemption.

### 11.6 `{.push noSideEffect.}` does not suppress `func` global-state detection

**Discovery date**: 2026-06-14

The `{.push noSideEffect.}` pragma block does NOT make `func` declarations within it immune to global state access detection. The Nim compiler still detects module-level `var` access (e.g., a global `Table`) as a side effect, even when the `func` is declared inside a `{.push noSideEffect.}` block.

**Reproduction**:
```nim
import std/tables
{.push noSideEffect.}
var registry = initTable[string, string]()
func register*(key: string, val: string) =
  registry[key] = val  # ERROR: 'register' can have side effects
{.pop.}
```

**Root cause**: `func` is syntactic sugar for `proc {.noSideEffect.}`. The `{.push noSideEffect.}` sets the **default** for `proc` declarations within the block, but `func` has its own **built-in** `{.noSideEffect.}` that takes precedence. The compiler's side-effect analysis for `func` is independent of the push/pop context.

**Workaround**: Use `proc` for functions that access module-level mutable state. This is the correct semantic choice — such functions genuinely have side effects. Document the false-positive gap between nimtry's "no transitive I/O" heuristic (which flags these as `SAFETY-proc-purity`) and the Nim compiler's stricter global-state detection.

**Affected code**: `src/core/policy/section_parsers.nim` (`registerSection`, `getHandler`, `isRegistered`, `validateRegistry`) and all `registerXxxSections` procs in `src/core/policy/parsers/parse_*.nim` (14 total).

**nimtry impact**: 14 `SAFETY-proc-purity` false positives. The heuristic checks for transitive I/O calls but not global `var` table access. These are informational warnings, not blocking violations.

---

---

## §5. nimtry Purity False Positives — Transitive I/O Delegation

### 5.1 `executeProof` — Delegation to I/O proc (Z3 subprocess)

**File**: `src/core/boundary/verification_interface.nim:120` (+ `contract/` forwarding stub)

```nim
proc executeProof*(prover: Z3PoolProver; query: string; timeoutMs: int = 5000): bool =
  ## Delegates to the concrete prover's prove method.
  provers.prove(prover, query, timeoutMs)
```

**Gate**: `PURITY-new-code-must-be-func` / proc→func report `🔴 Effect: 3`

**Root cause**: nimtry inspects the **immediate function body** only. The body contains a single call to `provers.prove()`, which transitively calls `z3ExecPersistent()` (Z3 subprocess via `std/osproc`) — genuine I/O. The gate heuristic does not trace transitive side effects through delegation chains.

**Verdict**: `proc` is correct. This is a genuine I/O boundary proc per AGENTS.md §0.6. The Nim compiler correctly detects the transitive side effect. nimtry false positive.

**Action**: No code change. Add to nimtry purity allowlist or accept as informational.

---

## §6. nimtry SoC False Positives — Hub Module Type-Only Imports

### 6.1 `verification_interface.nim` imports from `verification/` layer

**File**: `src/core/boundary/verification_interface.nim:35-40`

**Gate**: `soc-layer-imports` (6 violations)

**Root cause**: This module is the **Hub Module** per Clean Architecture DIP (§1.3a). It imports **pure type definitions** (enums, objects, proc types) from `verification/` to create a single controlled gateway. BLOCK#001 in `blocked_patterns.json` enforces that `core/orchestration/` and `core/gateway/` import ONLY this module, never `verification/` directly.

The imports are:
- `verification/unified_trajectory` → `StageKind`, `StageStatus` (pure enums)
- `verification/pipeline_state_types` → `PipelineInput`, `SwatStageOutcome` etc. (pure objects)
- `verification/pipeline_effect` → `DispatchTarget`, `DispatchResult` etc. (pure objects)
- `verification/solver/provers` → `Z3PoolProver`, `LeanProver` (type aliases)
- `verification/solver/fixedpoint_engine` → `FixedpointResult` (pure object)
- `verification/abstract_provider` → `AbstractContext`, `Interval` (pure objects)

**Verdict**: All imports are **type-only** with zero side effects. The Hub Module pattern is a well-established Clean Architecture construct. nimtry's layer-import check is a heuristic that cannot distinguish type-only imports from behavioral imports.

**Action**: No code change. The Hub Module pattern is by design. Add to nimtry SoC allowlist for this specific file.

---

## §12. `gorge()` + Git Worktree Root Resolution — `.axiom_root` Declarative Anchor

### 12.1 발견 일자
2026-06-16 (pre-push gate failure root cause analysis)

### 12.2 문제
`gorge("git rev-parse --show-toplevel")`은 Git worktree 환경에서 **올바르게 프로젝트 루트를 반환하지 못한다**. 추가로, fallback walk-up 로직의 `test -d '.git'` 검사도 worktree에서 실패한다.

**증상**: `src/core/trusted/axiom_pragmas.nim`의 `verifySpecification` macro가 compile-time에 `gorge()`로 프로젝트 루트를 탐색하는데, worktree 환경에서 루트를 `src/core/trusted`로 잘못 반환하거나 빈 문자열을 반환한다.

### 12.3 근본 원인

**원인 1 — `gorge()` CWD 동작**: Nim의 compile-time `gorge()`는 소스 파일의 디렉토리에서 shell을 실행한다. `git rev-parse --show-toplevel`이 worktree 환경에서 `gorge()` 컨텍스트에서 실패하면, fallback 로직이 작동한다.

**원인 2 — `.git`이 파일인 worktree**: Git worktree에서 `.git`은 **파일**(worktree config pointer)이지 **디렉토리**가 아니다. 따라서 `test -d '.git'` walk-up은 worktree root에서도 일치하지 않는다.

```
# worktree 환경:
$ ls -la .git
-rw-rw-r-- 1 user user 127 Jun 16 10:00 .git   # 파일, not 디렉토리!

# main worktree:
$ ls -la .git
drwxr-xr-x 1 user user 4096 Jun 16 10:00 .git  # 디렉토리
```

**원인 3 — nimcache에 stale `gorge()` 결과**: Nim compiler는 compile-time `gorge()` 결과를 `.nimcache/`에 저장할 수 있다. 이전에 잘못된 루트로 컴파일된 적이 있다면, 후속 컴파일에서 동일한 잘못된 값을 재사용한다.

### 12.4 해결책: `.axiom_root` Declarative Anchor

Git 의존성을 제거하고 **선언적 앵커 파일**로 프로젝트 루트를 지정한다.

**3-step deterministic architecture**:

| 단계 | 구성요소 | 설명 |
|------|----------|------|
| 1 | `.axiom_root` anchor file | 프로젝트 루트에 위치하는 선언적 마커 파일 |
| 2 | `repo_root.nim` | Runtime walk-up: `fileExists(result / ".axiom_root")` — git 불필요 |
| 3 | `axiom_pragmas.nim` | Compile-time walk-up: `fileExists(d / ".axiom_root")` via `gorge()` — git 불필요 |

**`.axiom_root` 파일**:
```yaml
# Axiom Project Root Anchor
# This file is the declarative anchor for root resolution.
# All tools MUST use this file to find the project root.
version: 1.0
created: 2026-06-16
```

**`repo_root.nim` (runtime)**:
```nim
const axiomRoot* = ".axiom_root"
const axiomToml* = "axiom.toml"

proc findRepoRoot*(startDir: string = getAppDir()): string {.raises: [].} =
  result = startDir
  for _ in 0..10:
    if fileExists(result / axiomRoot): return result
    if fileExists(result / axiomToml): return result
    let parent = parentDir(result)
    if parent == result: break
    result = parent
  result = parentDir(startDir)  # legacy fallback
```

**`axiom_pragmas.nim` (compile-time)**:
```nim
macro verifySpecification*(specPath: static string): untyped =
  # No git dependency — walk up from source dir to find .axiom_root
  let srcFile = instantiationInfo(-1, true).filename
  var d = parentDir(srcFile)
  for _ in 0..10:
    if fileExists(d / ".axiom_root"):
      projectRoot = d; break
    if fileExists(d / "axiom.toml"):  # backward compat
      projectRoot = d; break
    let p = parentDir(d)
    if p == d: break
    d = p
```

### 12.5 Nim compile-time `staticFileExists`

Nim 2.0+에서 `std/staticos`의 `staticFileExists`를 사용하면 compile-time에 파일 존재를 검증할 수 있다. 그러나 `verifySpecification` macro는 `gorge()` walk-up이 필요하므로 `fileExists` (runtime) + `gorge()` 조합을 사용한다.

**`staticFileExists` 사용 가능한 경우**:
```nim
import std/staticos
# compile-time에 파일 존재 확인 (gorge 불필요)
static:
  doAssert staticFileExists("path/to/.axiom_root")
```

**`gorge()`가 필요한 경우** (동적 walk-up):
- compile-time에 파일 시스템을 순회해야 하는 경우
- `instantiationInfo()`로 소스 파일 위치를 기반으로 탐색해야 하는 경우

### 12.6 정책
- **필수**: 프로젝트 루트 탐색은 반드시 `.axiom_root` anchor를 사용할 것
- **금지**: `gorge("git rev-parse --show-toplevel")`을 루트 탐색의 primary 방법으로 사용하는 것
- **허용**: `.axiom_root`를 찾지 못하면 `axiom.toml`로 fallback (backward compat)
- **금지**: `test -d '.git'`을 worktree-aware 루트 탐색으로 사용하는 것
- **필수**: worktree 전환 후 `rm -rf nimcache .nimcache` 실행 — stale `gorge()` 캐시 제거
- **참조**: `docs/evidence/prepush_failure_root_cause_2026-06-16.md` §3.2

---

## §13. axiomIoBoundary는 모듈 레벨 템플릿이다 (per-proc pragma 아님)

### 13.1 발견 상황
- `{.axiomIoBoundary.}`를 per-proc pragma로 사용하려 했으나 `Error: invalid pragma: axiomIoBoundary` 발생
- `axiomIoBoundary`는 `src/core/trusted/axiom_pragmas.nim`에서 `template axiomIoBoundary*() = discard`로 정의됨

### 13.2 올바른 사용법

| 컨텍스트 | 문법 | 예시 |
|----------|------|------|
| 모듈 레벨 | `{.axiomIoBoundary.}` | `import core/trusted/axiom_pragmas; {.axiomIoBoundary.}` |
| Per-proc I/O 표기 | `{.axiomEffect: IoEffect.}` | `proc readFile*(path: string): string {.axiomEffect: IoEffect, raises: [].}` |

### 13.3 정책
- `axiomIoBoundary`는 모듈 전체에 I/O boundary를 선언할 때만 사용
- 개별 proc에 I/O를 표기하려면 `{.axiomEffect: IoEffect.}` 사용
- `IOCapability` sealed token (`src/core/interfaces/io_executor.nim`)은 per-proc 표기가 필요할 때 사용

### 13.4 영향 받는 파일
- `src/core/io/file_utils.nim` — `{.axiomEffect: IoEffect.}` 적용됨
- `src/core/io/io_utils.nim` — 11개 proc에 `{.axiomEffect: IoEffect.}` 적용됨
- `src/core/interfaces/io_executor.nim` — `createIOCapability()`에 `{.axiomEffect: IoEffect.}` 적용됨

### 13.5 검증
- `nim c src/core/io/file_utils.nim` — 컴파일 성공
- `nim c src/core/interfaces/io_executor.nim` — 컴파일 성공
- **참조**: `docs/spec/declarative_effect_isolation_quirks.md` §axiomIoBoundary

---

## §14. NimScript Gorge 한계 (config.nims) — status: not implemented / code mismatch

> **상태**: not implemented / code mismatch. AGENTS.md §3의 Hermetic Build Orchestrator(v28) 설명은 `config.nims hermeticPreBuild` 블록을 전제하지만, 현재 저장소에는 해당 NimScript 블록이 없습니다. 이전 “해결됨” 문구는 코드와 불일치하므로 이 섹션은 문서화용으로만 유지합니다.

### 14.1 원래 문제

NimScript (`config.nims`)는 Nim의 **축소 런타임**입니다. `std/os`, `std/json`, `walkDir`, `getFileInfo` 등이 **사용 불가능**합니다. 이로 인해 config.nims에서 외부 프로세스(`gorge("grep")`, `gorge("stat")` 등)에 의존하는 패턴이 존재했습니다.

### 14.2 현재 실제 구현

현재 구현은 Nimble task를 명시적으로 호출하는 방식입니다:

1. `axiom.nimble`의 `task hermetic`이 `bin/hermetic_build`을 빌드합니다.
2. `nimble hermetic`이 `bin/hermetic_build`을 실행합니다.
3. `tools/hermetic_build.nim`이 `src/generated/build_env.nim`을 생성합니다.
4. 생성된 파일은 frozen 상수를 포함합니다: `BuildEnvZ3Version`, `BuildEnvCommitCount`, `BuildEnvGitHash`.

**UNTRACKED + gitignored + `.default` bootstrap (blanket purity)**: `src/generated/build_env.nim`은 이제 **트래킹하지 않습니다** (gitignore, blanket purity). 대신 `src/generated/build_env.nim.default`가 **GIT-TRACKED 정적 baseline**이며 **모든 const를 완전 정의**합니다 (git hash, source hash 등은 placeholder 값). 빌드 최초 컴파일 시 (git clean 이후) `config.nims`는 `copyFile`로 `.default` → `build_env.nim`을 복사합니다 (0.1ms, exec 없음, hand-crafted 문자열 없음). 본문 캐시(`.axiom/cache/build_env.body`)는 최초 `bin/hermetic_build --check-decision-bindings` 호출 시 생성됩니다 — `check-decision-binding` make target (이 형태는 `local-verify-static`의 일부)이 **지정된 body-cache bootstrap target**이며, 이후 `config.nims`는 캐시에서 복원하되 **live git hash 치환**을 적용합니다. `BuildEnvGitHash` placeholder는 반드시 `"0000000"` (7자) 여야 합니다 — `constants.nim:53`의 `[0..6]` 슬라이스가 빈 문자열에서 크래시합니다. env-hash는 **현재 git SHA** 기반이므로 재생성 내용이 항상 달라지던 구(舊) PARENT-commit 자가참조 드리프트 문제가 사라지며, 트래킹에서 제외되었으므로 CI verify-static purity check는 scoped `:!` 제외 없이 **전체 0-diff blanket 검증**으로 충분합니다.

**`--skipProjCfg` invariant (HARD)**: untrack 전환으로 build_env.nim은 남은 `--skipProjCfg` 컴파일에서 **부재할 수 있습니다** — `config.nims`(build_env.nim을 복원/생성하는 경로)가 skip되기 때문입니다. 따라서 다음 **비보호(unguarded) importer**는 `--skipProjCfg` 컴파일에 도달해선 안 됩니다: `src/cli/main.nim`, `src/core/utils/constants.nim`, `src/verification/state_manager.nim`, `src/core/trusted/architecture_invariants.nim`, `src/infrastructure/gate_signing/proof_verifier.nim` (직접 `import generated/build_env`). 반면 **보호(guarded) importer** — `src/verification/cert_writer.nim`, `src/core/trusted/axiom_pragmas_types.nim` — 는 `when fileExists("src/generated/build_env.nim")` 가드로 안전하게 degrade되므로 `--skipProjCfg`의 안전 경로입니다.

### 14.3 AGENTS.md 설명과 코드 불일치

- `config.nims` 및 `config/*.nims`에서 `hermeticPreBuild`를 검색한 결과, 현재 저장소에는 해당 블록/문자열이 없습니다.
- 따라서 `config.nims`가 컴파일 전 `gorgeEx("bin/hermetic_build")`를 호출한다는 설명은 현재 코드와 맞지 않습니다.
- 실제 진입점은 Nimble task `nimble hermetic`이며, `config.nims`가 NimScript에서 직접 orchestrator를 실행하는 구조는 구현되지 않았습니다.

### 14.4 NimScript `gorge` 패턴 현황

`config.nims`에는 아직 NimScript 축소 런타임 상에서 외부 프로세스를 호출하는 패턴이 남아 있습니다. 현재 기준으로는 이 패턴들이 `hermeticPreBuild`를 통해 NimScript 바깥으로 완전히 이동된 것이 아닙니다.

### 14.5 검증

- `grep -RIn "hermeticPreBuild" config.nims config/*.nims || true` → 출력 없음
- `axiom.nimble:88-91` — `task hermetic`이 `bin/hermetic_build`을 빌드/실행
- `tools/hermetic_build.nim:987-1009` — `src/generated/build_env.nim` 생성 및 frozen 상수 작성
- `src/generated/build_env.nim:10-13` — `BuildEnvZ3Version`, `BuildEnvCommitCount`, `BuildEnvGitHash`

---

## §15. expandFilename() Compile-time 불가 (axiom_pragmas.nim) ✅ RESOLVED

> **해결됨** (Phase 0-C, 2026-06-22): `expandFilename` → `when fileExists` guard + `pathnorm.normalizePath` + `BuildEnvProjectRoot`.
> 더 이상 `gorgeEx`도 사용하지 않음. compile-time 안전 경로 해석으로 완전 전환.

<details><summary>원본 발견 기록 (2026-06-20)</summary>

`expandFilename()`은 Posix에서 C의 `realpath()`를 `{.importc.}`로 호출합니다.
Nim의 compile-time macro VM은 `{.importc.}` 함수를 실행할 수 없습니다.

해결: `when fileExists` guard로 build_env.nim 유무에 따라 분기:
- build_env.nim 존재: `BuildEnvProjectRoot / srcDir` (compile-time 상수 결합)
- build_env.nim 부재: `srcDir` as-is (degraded fallback, self-healing)

`pathnorm.normalizePath`는 compile-time 안전 (pure string, no FFI).
</details>

---

## §16. classifyFailure Exit Code Contract

### 16.1 Problem

The previous `classifyFailure(output: string)` parsed log strings for `[fcPermanent]` and `[fcValidation]` markers to classify gate failures. This was brittle — string patterns change between Nim versions and gate runners may not emit structured markers.

### 16.2 Solution

`classifyFailure(exitCode: int, output: string)` uses POSIX exit codes as the primary classification signal. Exit codes are deterministic and version-independent.

### 16.3 Exit Code Mapping

| Exit Code | Signal | `FailureCategory` | Rationale |
|-----------|--------|--------------------|-----------|
| 0 | — | `fcTransient` | Success (shouldn't be called for failure classification) |
| 1 | — | `fcValidation` | Gate logic rejected the input (assertion failure, test failure) |
| 2 | — | `fcPermanent` | Configuration/policy error (missing file, permission denied) |
| 134 (128+6) | SIGABRT | `fcPermanent` | Self-diagnostic failure (assert abort) |
| 139 (128+11) | SIGSEGV | `fcPermanent` | Memory fault (null pointer, buffer overflow) |
| other | — | Falls through to output marker check, then `fcTransient` | Unrecognized codes are transient (retryable) |

### 16.4 Backward Compatibility

For exit codes not in the primary mapping (e.g., exit code 13 from a gate that uses custom exit codes), the function falls back to checking structured output markers (`[fcPermanent]`/`[fcValidation]`). If no markers are found, it defaults to `fcTransient`. This preserves backward compatibility with gates that emit structured markers.

### 16.5 Cache Impact

- `fcTransient` failures: cached with TTL=300s (retried after expiry)
- `fcPermanent` and `fcValidation` failures: not cached (TTL=0, never retried)

Previously, SIGSEGV (exit 139) and SIGABRT (exit 134) were classified as `fcTransient` (the default). They are now correctly classified as `fcPermanent`, which means they will NOT be cached. This is correct — memory faults and assertion aborts should always be retried fresh.

### 16.6 Affected Modules

- `src/gate/gate_contract.nim`: `GateResult.exitCode` field added
- `src/gate/orchestrator_pure.nim`: `classifyFailure` signature changed
- `src/gate/orchestrator/hook/executor.nim`: `runSingleGateImpl` threads exit code to `GateResult`, `pollL2GatesWithTimeout` (2 overloads) passes exit code from `ws.code` (POSIX) or `exitCode` (non-POSIX); 2 callers pass `res.exitCode` from `GateResult`

---

## §17. `gorge()` Z3 PATH Quirk (`nim check` vs `nim c`)

### 17.1 Discovery

- **Date**: 2026-06-23
- **Context**: drnim gate pre-commit failure during Phase 3 gate validation
- **Affected**: `src/gate/runners/nim_check_gate.nim` (successor of the removed `drnim_gate`), any gate runner using `execCmdEx("nim check ...")`

### 17.2 Symptom

`gorge("z3 --version 2>/dev/null")` in `config.nims` returns an empty string during `nim check` but works correctly during `nim c`, even though Z3 is installed at `~/.local/bin/z3` and is in PATH.

```
# nim check: FAIL
❌ [hermetic] Critical: Z3 is missing from PATH!

# nim c: PASS
Z3 version 4.13.3 - 64 bit
```

### 17.3 Root Cause

Nim compiler's `gorge()` function uses different PATH resolution in check mode vs compile mode. The `nim check` command processes `config.nims` but the underlying `execProcess` call for `gorge()` may use a restricted PATH or different shell environment.

### 17.4 Workaround

Use `-d:allowMissingZ3` flag when running `nim check`:

```nim
let (output, exitCode) = execCmdEx("nim check -d:allowMissingZ3 " & t)
```

This bypasses the hermetic Z3 check in `config.nims` while preserving all other validations.

### 17.5 Policy

- **Required**: Gate runners using `nim check` MUST include `-d:allowMissingZ3`
- **Forbidden**: Bypassing Z3 validation entirely (Z3 is validated separately by `hermetic-test-gate`)
- **Recommended**: Document the quirk reference in gate runner comments

---

## §18. `supportsCopyMem` vs `supportsCopy` for `string`/`seq` Types

### 18.1 Discovery

- **Date**: 2026-06-27
- **Nim version**: 2.2.10
- **Affected**: `src/core/types/results.nim`, 249+ call sites

### 18.2 Symptom

`static: assert supportsCopyMem(E)` in `results.nim` rejected `string` as a valid error type, breaking 249+ call sites that used `string` as the error payload in `Result[T, E]`.

### 18.3 Root Cause

`supportsCopyMem(string)` returns `false` because `string` has an internal pointer (heap-allocated data buffer). `supportsCopyMem` checks **raw memory copyability** — whether a type can be `memcpy`'d without invoking any hooks. `string` fails this check due to its internal `{data, len, reserved}` layout with a heap pointer.

However, `string` IS safe as a `Result[T, E]` error payload under ARC/ORC because its lifecycle is managed by the `=copy`/`=sink`/`=destroy` hooks. The correct check is `supportsCopy`, which verifies whether the type has a valid `=copy` hook — and `string` does.

| Predicate | What it checks | `string` | `seq[T]` |
|-----------|---------------|----------|----------|
| `supportsCopyMem` | Raw `memcpy` safety (no internal pointers) | `false` | `false` |
| `supportsCopy` | Has a valid `=copy` hook | `true` | `true` |

### 18.4 Workaround

```nim
static: assert supportsCopyMem(E) or E is string or E is seq
```

Explicit allowlist for known-safe heap types that have proper `=copy` hooks but fail the raw memory copy check.

### 18.5 Policy

- **Forbidden**: Using `supportsCopyMem` alone to gate generic type parameters that may be `string` or `seq`
- **Required**: When asserting copy safety for generic types, combine `supportsCopyMem` with an allowlist: `supportsCopyMem(T) or T is string or T is seq`
- **Note**: `supportsCopy` is the semantically correct check for ARC/ORC-managed types; `supportsCopyMem` is only appropriate for low-level `memcpy`-based operations (e.g., `GC_copy` internals)

---

## §19. `IOError` vs `IoError` Symbol Collision

### 19.1 Discovery

- **Date**: 2026-06-27
- **Nim version**: 2.2.10
- **Affected**: `src/core/gate/file_hash_cache.nim`

### 19.2 Symptom

Compilation failure when a module imports both `std/os` (which brings `IOError` — a `ref IOError` exception class) and a module that exports `IoError` (an enum). Nim's overload resolution fails on `newException(IOError, ...)` because both identifiers are in scope.

### 19.3 Root Cause

Nim's symbol resolution does not distinguish identifiers by casing the way Python does. When `std/os` re-exports `IOError` (from `system`) and a project module exports an `IoError` enum, the compiler sees two candidates with nearly identical names. Unlike Rust where `IoError` vs `io::Error` would be distinct paths, Nim's unqualified names collide.

Key difference from Python:
- Python: `IOError` (exception) vs `IoError` (enum) → distinct because Python is case-sensitive
- Nim: `IOError` (exception) vs `IoError` (enum) → ambiguous because Nim normalizes identifiers to the same symbol table

### 19.4 Workaround

Qualify the exception type explicitly:

```nim
raise newException(system.IOError, "message")
```

This selects the stdlib `IOError` exception type unambiguously, bypassing the collision with the project's `IoError` enum.

### 19.5 Policy

- **Required**: When a module defines an enum/identifier with a name similar to a stdlib exception (e.g., `IoError`), downstream modules that import both MUST qualify the stdlib exception as `system.IOError`
- **Recommended**: Avoid naming project identifiers to closely mirror stdlib exception names (e.g., use `IoErr` or `IoErrorKind` instead of `IoError`)
- **Forbidden**: Using `import std/os` and a module exporting `IoError` in the same file without qualification

---

## §20. sync-protocol-gate: `flock`, `proc`/`func` Boundary, `lent` Return, and POSIX `importc` Constants

> **Historical**: The `sync_protocol_gate` runner and its `tx_manifest` companion
> were **removed on 2026-08-02** (rebase-only sync refactor). The quirks below
> (flock, `parseJson` side effects, `lent` returns, POSIX `importc` constants)
> are general Nim quirks that remain applicable; module references are historical.

### 20.1 Discovery

- **Date**: 2026-06-27
- **Nim version**: 2.2.10
- **Affected**: `src/infrastructure/tx_manifest.nim` (removed 2026-08-02), `src/infrastructure/push_context.nim`, `src/gate/runners/sync_protocol_gate.nim` (removed 2026-08-02)

### 20.2 Quirk 20a — `flock` vs `fcntl` on Linux: `std/posix` Does Not Re-export `flock`

#### Symptom

Calling `posix.flock(fd, LOCK_EX)` after `import std/posix` produces an `undeclared identifier` error on Linux. `std/posix` on Linux (glibc) does **not** re-export the `flock` binding — only `fcntl`-style locking (`F_SETLK`, etc.) is available through the module.

#### Root Cause

`std/posix` conditionally exports symbols based on the OS. On Linux/glibc targets, `flock` lives in `<sys/file.h>` but Nim's `std/posix` wrapper only imports it for BSD/Darwin. The POSIX `fcntl()` advisory locking (`F_SETLK`/`F_SETLKW`) is an alternative, but it operates on byte ranges rather than whole-file locks and has different semantics (no fork-inheritance).

#### Workaround

Define a local `importc` binding:

```nim
proc c_flock(fd: cint, operation: cint): cint
    {.importc: "flock", header: "<sys/file.h>", sideEffect.}

const
  LOCK_EX = cint(2)   ## Exclusive lock
  LOCK_UN = cint(8)   ## Unlock
```

This is the approach used in `tx_manifest.nim`. The constants must also be defined locally because `std/posix` does not export `LOCK_EX`/`LOCK_UN` on Linux.

#### Policy

- **Required**: Any module needing `flock` on Linux MUST define its own `importc` binding + local constants rather than relying on `std/posix`.
- **Note**: The `fcntl` alternative (`F_SETLK`) has different semantics — whole-file exclusive lock via `flock` is strongly preferred for manifest atomicity.

### 20.3 Quirk 20b — `parsePushContext` Must Be `proc`, Not `func`

#### Symptom

Declaring `parsePushContext` as `func` triggers a compile error: `can have side effects`.

#### Root Cause

`parsePushContext` calls `std/json.parseJson`, which is **not** marked `{.noSideEffect.}` in Nim's stdlib (see §1). Even though `parsePushContext` itself has no intentional side effects, the compiler propagates the side-effect annotation from `parseJson` upward. Using `func` is a compile-time contract that the function has zero side effects — `parseJson` violates this.

#### Workaround

```nim
proc parsePushContext*(jsonStr: string): PushContext {.raises: [].} =
  ## NOTE: proc (not func) because std/json.parseJson has side effects.
  let j = parseJson(jsonStr)
  ...
```

The `{.raises: [].}` pragma is still achievable (catches internally), but `func` is not.

#### Policy

- **Required**: Any deserializer that calls `parseJson`, `parseFile`, or other stdlib JSON functions MUST be declared as `proc`, not `func`.
- **See also**: §1 (JSON `parseJson` side effect registry).

### 20.4 Quirk 20c — `lent seq[string]` Return: No Address-Of on Literal

#### Symptom

Returning `lent seq[string]` from a `func` works correctly — the compiler does not attempt to take the address of the backing data. However, attempting to pass the `lent` result to a proc expecting `var seq[string]` or taking its address (`addr`) fails.

#### Root Cause

`lent T` in Nim is a **borrowed read-only view** — it does not create a copy but also does not allow mutation or address-taking. The `commitShas` accessor in `push_context.nim` returns `lent seq[string]` to avoid copying the commit SHA list:

```nim
func commitShas*(ctx: PushContext): lent seq[string] {.raises: [].} =
  ctx.commits
```

This is correct and zero-copy, but downstream code MUST treat the return as immutable.

#### Workaround

No workaround needed — this is the intended behavior. Document that `lent` returns are borrowed views that must not outlive the source object or be mutated.

#### Policy

- **Required**: Accessors returning `lent` must have callers treat the result as immutable. Do not attempt `addr`, `var`, or mutation on `lent` returns.
- **Recommended**: Use `lent` for zero-copy accessors on object fields (e.g., `PushContext.commits`). Use plain `seq[T]` returns only when a copy is acceptable.

### 20.5 Quirk 20d — POSIX Constants Need Local `importc` Definitions

#### Symptom

`O_CREAT`, `O_RDWR`, and file mode constants (`S_IRUSRW`) are undefined or have wrong types when used from `std/posix` on Linux.

#### Root Cause

Nim's `std/posix` module defines these constants only for specific OS targets. On Linux, some are exported as `cint`, some as `Mode`, and some are missing entirely. The `open()` proc from `std/posix` expects `cint` for flags and `Mode` for the mode parameter, but the constant definitions may not match.

`tx_manifest.nim` defines them locally with explicit types:

```nim
const
  O_CREAT  = cint(0o100)
  O_RDWR   = cint(0o2)
  S_IRUSRW = Mode(0o600)  ## rw-------
```

#### Workaround

Define all POSIX constants locally with explicit type annotations. Do not rely on `std/posix` re-exports for file-open flags on Linux.

#### Policy

- **Required**: When using `posix.open()` on Linux, define `O_CREAT`, `O_RDWR`, and permission mode constants locally with explicit `cint`/`Mode` types.
- **Note**: This is a recurring pattern — any POSIX low-level I/O module in the project should include its own constant block.

---

## §21. `cpuinfo.countProcessors()` vs `osproc.countProcessors()` — Ambiguous Symbol Error

### 21.1 Discovery

- **Date**: 2026-06-27
- **Nim version**: 2.2.10
- **Affected**: Any module importing both `std/cpuinfo` and `std/osproc`

### 21.2 Symptom

Importing both `std/cpuinfo` and `std/osproc` in the same module produces an ambiguous identifier error on `countProcessors`. Both modules export a symbol named `countProcessors`, and Nim's overload resolution cannot disambiguate.

### 21.3 Root Cause

`std/cpuinfo` provides `proc countProcessors*(): int` (hardware CPU core count via `sysconf`/`sysctl`). `std/osproc` also exports `proc countProcessors*()` — originally imported from `cpuinfo` for backward compatibility. When both are in scope, the unqualified name `countProcessors` is ambiguous.

This is a stdlib module design issue: `osproc` re-exports `cpuinfo.countProcessors` rather than providing its own implementation, creating a namespace collision for consumers that need both modules.

### 21.4 Workaround

Qualify the call with the module name:

```nim
import std/cpuinfo
import std/osproc

# BAD — ambiguous:
let cores = countProcessors()

# GOOD — qualified:
let cores = cpuinfo.countProcessors()
```

The project uses this pattern in `src/gate/orchestrator/hook/executor.nim:1063`:

```nim
log.log(&"[GATE] Global concurrency budget: {globalConcurrencyBudget} workers (CPU cores: {cpuinfo.countProcessors()})")
```

### 21.5 Policy

- **Required**: Any module importing both `std/cpuinfo` and `std/osproc` MUST qualify `countProcessors` as `cpuinfo.countProcessors()`.
- **Recommended**: Prefer `import std/cpuinfo` alone when only CPU count is needed — `std/osproc` is heavy and brings process management overhead into scope.

---

## §22. `checksums/sha2` vs Non-Existent `std/sha256` — SHA-256 Is Not in Stdlib

### 22.1 Discovery

- **Date**: 2026-06-27
- **Nim version**: 2.2.10
- **Affected**: All modules performing SHA-256 hashing (entire project)

### 22.2 Symptom

`import std/sha256` or `import std/sha` produces a module-not-found error. Nim's standard library does **not** include a SHA-256 implementation.

### 22.3 Root Cause

Nim's stdlib provides `std/sha1` (SHA-1 only, for backwards compatibility) but **not** SHA-256. SHA-256 is available via the `checksums` Nimble package (`checksums/sha2`), which ships with Nim by default as a dependency but must be imported explicitly as `checksums/sha2`, not `std/sha256`.

The `checksums/sha2` package provides:
- `initSha_256()` — streaming/incremental hasher
- `update(ctx, data)` — feed data chunks
- `secureHash(Sha_256, data)` — one-shot hex digest (returns `SecureHash`)
- `$secureHash(Sha_256, data)` — string conversion of hex digest

### 22.4 Workaround

Use `checksums/sha2` for all SHA-256 operations:

```nim
import checksums/sha2

# One-shot hex digest (most common pattern in the project):
proc sha256Hex*(s: string): string =
  $secureHash(Sha_256, s)

# Streaming/incremental hasher:
var hasher = initSha_256()
hasher.update(part1)
hasher.update(part2)
let hash = $secureHash(hasher)
```

The project centralizes this in `src/core/gate/hash_types.nim:35-37`:

```nim
func sha256Hex*(s: string): string {.inline.} =
  ## Full SHA-256 hex digest (64 chars). Cross-platform deterministic.
  $secureHash(Sha_256, s)
```

### 22.5 Policy

- **Required**: All SHA-256 operations MUST use `checksums/sha2`, not `std/sha256` (which does not exist).
- **Required**: New modules MUST import `core/gate/hash_types` for the `sha256Hex` wrapper rather than calling `$secureHash(Sha_256, ...)` directly — this ensures a single SSOT for hash algorithm choice.
- **Forbidden**: Using shell-dependent `gorge("sha256sum ...")` for runtime hashing (see §25).

---

## §23. `startProcess(env=)` for Hermetic Build Isolation

### 23.1 Discovery

- **Date**: 2026-06-27
- **Nim version**: 2.2.10
- **Affected**: `src/core/gate/hermetic_sandbox.nim`, `tools/hermetic_build.nim`

### 23.2 Symptom

Child processes inherit the full parent environment, making builds non-deterministic. Environment variables like `LD_LIBRARY_PATH`, `TMPDIR`, or user-specific settings leak into child processes, causing "works on my machine" failures.

### 23.3 Root Cause

Nim's `std/osproc.startProcess` accepts an `env: StringTableRef = nil` parameter:

- `nil` (default) → child inherits **entire** parent environment
- Non-nil `StringTableRef` → child gets **only** the variables in the table (isolated environment, equivalent to `env -i` + whitelist)

Most Nim code uses the default `nil`, unintentionally leaking the full environment into child processes.

### 23.4 Workaround

Construct an explicit `StringTableRef` with only the required variables:

```nim
import std/[os, osproc, strutils]

proc hermeticStartProcess*(cmd: string; args: seq[string];
                           repoRoot: string): Process =
  var env = newStringTable(modeStyleNormal)
  # Whitelist only deterministic-relevant variables:
  env["PATH"] = getEnv("PATH")  # Needed to find binaries
  env["HOME"] = getEnv("HOME")  # Needed by some build tools
  env["SOURCE_DATE_EPOCH"] = getEnv("SOURCE_DATE_EPOCH")  # Reproducible builds
  # Explicitly EXCLUDE: LD_LIBRARY_PATH, TMPDIR, USER, SHELL, etc.

  startProcess(cmd, args = args,
               workingDir = repoRoot,
               env = env,
               options = {poParentStreams, poUsePath})
```

### 23.5 Policy

- **Required**: Any build or verification subprocess that requires deterministic output MUST pass an explicit `env` to `startProcess`.
- **Required**: The whitelist MUST include only `PATH`, `HOME`, and build-relevant variables (`SOURCE_DATE_EPOCH`, `NIMBLE_DIR`, etc.).
- **Forbidden**: Passing `env = nil` (or omitting the parameter) in hermetic build contexts.

---

## §24. Parent Directory `fsync` After `rename(2)` — Dentry Flush for Crash Safety

### 24.1 Discovery

- **Date**: 2026-06-27
- **Nim version**: 2.2.10
- **Affected**: `src/gate/attestation.nim` (`fsyncDirectory` after rename),
  `src/core/gate/state_ledger.nim` (tmp+fsync+rename), any module performing
  atomic file replacement. Formerly also `tx_manifest.nim` (removed 2026-08-02).

### 24.2 Symptom

After an atomic `rename(tmp, target)`, a power loss or kernel crash can cause the renamed file to "disappear" from the directory — the file data is intact on disk, but the directory entry (dentry) was not flushed. The file becomes an orphaned inode with no directory entry pointing to it.

### 24.3 Root Cause

POSIX `rename(2)` is atomic for the **file data** and the **directory entry update** at the filesystem level, but the directory's metadata (the mapping from filename → inode) may sit in the kernel's dentry cache and not be written back to disk immediately. A power loss between the `rename(2)` return and the directory flush can lose the directory entry.

This is distinct from `fsync(fd)` on the file itself — `fsync` on the file ensures the data is on disk, but does **not** flush the parent directory's dentry.

### 24.4 Workaround

After `rename(2)`, explicitly fsync the parent directory:

```nim
import std/[posix, os]

proc atomicRename*(tmpPath, targetPath: string) =
  ## Atomically replace targetPath with tmpPath, with dentry flush.
  discard rename(tmpPath.cstring, targetPath.cstring)

  # Flush the parent directory dentry — without this, power loss
  # can cause the file to "disappear" from the directory listing.
  let parentDir = parentDir(targetPath)
  let dirFd = open(parentDir.cstring, O_RDONLY)
  if dirFd >= 0:
    discard fsync(dirFd)
    discard close(dirFd)
```

### 24.5 Policy

- **Required**: Any module performing atomic file replacement via `rename(2)` MUST fsync the parent directory afterward.
- **Required**: The `src/gate/attestation.nim` pattern (write + fsync + rename +
  dir-fsync via `fsyncDirectory`) is the reference implementation for all
  manifest/proof/ledger writes. (The former `tx_manifest.nim` reference pattern
  was removed with the sync protocol gate on 2026-08-02.)
- **Note**: This is especially critical for power-loss-sensitive paths (proof vault, state ledger, manifest files).

---

## §25. `walkDirRec` vs `gorge("ls ...")` for Compile-Time File Discovery

### 25.1 Discovery

- **Date**: 2026-06-27
- **Nim version**: 2.2.10
- **Affected**: `src/gate/gate_registry.nim` (`static:` block runner discovery)

### 25.2 Symptom

Using `gorge("ls src/gate/runners/*.nim")` for compile-time file discovery produces inconsistent results across environments. Different shells, locales, and OS configurations yield different file orderings or even different file lists (e.g., `ls` glob expansion varies between GNU coreutils and BSD).

### 25.3 Root Cause

`gorge()` executes a shell command at compile time via the host system's `/bin/sh`. The output depends on:

1. **Shell behavior**: `ls *.nim` glob expansion is shell-dependent (bash vs dash vs zsh)
2. **Locale**: `LC_ALL`/`LANG` affect sort order of `ls` output
3. **Non-determinism**: The file list is an unordered shell expansion, not a sorted Nim operation
4. **Portability**: BSD `ls` and GNU `ls` have different default sort orders and flag semantics

`walkDirRec()` is a pure Nim function that operates deterministically regardless of shell, locale, or OS.

### 25.4 Workaround

Use `walkDirRec` in `static:` blocks for compile-time file discovery:

```nim
# BAD — non-deterministic, shell-dependent:
static:
  let files = gorge("ls src/gate/runners/*.nim").splitLines()

# GOOD — deterministic, pure Nim:
static:
  var discoveredRunners: seq[string]
  for f in walkDirRec("src/gate/runners"):
    if f.endsWith(".nim"):
      discoveredRunners.add(f)
```

The project already uses the correct pattern in `src/gate/gate_registry.nim`:

```nim
static:
  var discoveredRunners: seq[string]
  for f in walkDirRec("src/gate/runners"):
    if f.endsWith(".nim"):
      discoveredRunners.add(f)
```

### 25.5 Policy

- **Required**: All compile-time file discovery MUST use `walkDirRec()` (or `walkDir`) — never `gorge("ls ...")` or `gorge("find ...")`.
- **Required**: `static:` blocks using `walkDirRec` MUST include a `discoveredRunners.len > 0` guard, because `walkDirRec` returns empty during `nim check` (the Nim VM has no filesystem access).
- **Forbidden**: Using `gorge()` for file listing in any `static:` or `block:` context.

---

## §26. Process Pool Sliding-Window Throttling — Full OS-Level Isolation

### 26.1 Discovery

- **Date**: 2026-06-27
- **Nim version**: 2.2.10
- **Affected**: `src/gate/runners/runner_process_pool.nim`, `src/gate/types.nim`

### 26.2 Symptom

Using `std/threadpool`'s `spawn` for parallel gate execution causes intermittent segfaults and race conditions. Each spawned task shares the parent process's compiler state, memory allocator, and GC — leading to data corruption when multiple tasks access shared mutable state concurrently.

### 26.3 Root Cause

Nim's `std/threadpool.spawn` executes tasks in **green threads** (or OS threads with ORC) within the **same process**. This means:

1. **Shared compiler state**: Nim's runtime (GC/ORC, thread-local storage) is shared across all spawned tasks
2. **No memory isolation**: A segfault or memory corruption in one task crashes the entire process
3. **No nimcache isolation**: Concurrent compilation tasks may overwrite each other's nimcache files
4. **ORC reference counting**: Concurrent destructor calls on shared objects cause use-after-free

The project solves this with a **process pool** (`runner_process_pool.nim`) that uses `startProcess` for true OS-level isolation:

```nim
proc launchProcess(spec: CmdSpec; repoRoot: string): Process =
  startProcess("nice", args = @["-n", "10", spec.cmd] & spec.args,
               workingDir = repoRoot,
               options = {poParentStreams, poUsePath})
```

Each child process gets:
- **Separate address space** — no shared memory, no shared GC
- **Separate nimcache** — each gate compiles into its own `--nimcache` directory
- **Separate file descriptors** — no contention on stdout/stderr

### 26.4 Sliding-Window Architecture

The pool implements a sliding-window throttle capped at `countProcessors()` workers:

```nim
proc runBatch*(commands: seq[CmdSpec]; repoRoot: string;
               maxJobs: int): seq[int] =
  var running: seq[(Process, int, times.Time)] = @[]
  result = newSeq[int](commands.len)
  var nextIdx = 0

  while nextIdx < commands.len or running.len > 0:
    # Memory-aware spawn gate (check every 5th poll ~50ms)
    if pollCount mod 5 == 0:
      let memBased = safeMaxJobs(maxJobs)
      let globalBudget = computeGlobalConcurrencyBudget()
      effectiveMaxJobs = max(1, min(memBased, globalBudget))

    # Spawn up to effectiveMaxJobs processes
    while running.len < effectiveMaxJobs and nextIdx < commands.len:
      let p = launchProcess(commands[nextIdx], repoRoot)
      running.add((p, nextIdx, getTime()))
      inc nextIdx

    if running.len > 0:
      reapCompletedProcesses(running, result, commands)
      if running.len > 0:
        sleep(10)  # 10ms poll interval
```

The sliding window works by:
1. Checking memory availability before each spawn wave
2. Applying a global concurrency budget (`computeGlobalConcurrencyBudget()`) to prevent multiplicative overcommit when multiple gates run concurrently
3. Reaping completed processes before spawning new ones — "drain oldest, spawn newest"

### 26.5 Global Concurrency Budget (DEBT#009)

Without a global budget, 4 concurrent gates on a 16-core machine each claim `countProcessors() div 2 = 8` workers → 32 total workers, 2× overcommit:

```nim
proc computeGlobalConcurrencyBudget*(): int =
  let cpuCores = countProcessors()
  let cpuBudget = max(1, cpuCores div 2)  # Leave cores for UI/GPU
  let memBudget = safeMaxJobs(cpuBudget)
  result = max(1, min(cpuBudget, memBudget))
```

### 26.6 Policy

- **Required**: All parallel gate execution MUST use the process pool (`runner_process_pool.nim`) — never `std/threadpool.spawn` for I/O-bound or compilation tasks.
- **Required**: Each gate runner MUST pass a unique `--nimcache` path to its child process to prevent cache collisions.
- **Required**: The global concurrency budget MUST be respected — no gate may claim more workers than `computeGlobalConcurrencyBudget()` allows.
- **Forbidden**: Using `spawn` with `ref object` arguments (see AGENTS.md §0.6a — value types only for `spawn`).

---

### 27. `=destroy`/`=copy`/`=dup` Hooks Require Underlying Object Type (Nim 2.2.10)

**Quirk**: In Nim 2.2.10, type-bound lifecycle hooks (`=destroy`, `=copy`, `=dup`) **cannot** be defined on `ref` types directly. They must be defined on the underlying `object` type. Defining them on a `ref` type produces:

```
Error: signature for '=destroy' must be proc[T: object](x: var T) or proc[T: object](x: T)
```

**Workaround**: Split `ref object` into separate `object` + `ref` declaration:

```nim
# WRONG — fails in Nim 2.2.10:
type
  MyRef* {.acyclic.} = ref object
    raw: pointer
    closed: bool

proc `=destroy`(r: MyRef) =  # ERROR
  ...

# CORRECT — hooks on the underlying object:
type
  MyObj = object
    raw: pointer
    closed: bool

  MyRef* {.acyclic.} = ref MyObj

proc `=destroy`(o: var MyObj) =  # OK
  if not o.closed:
    ...
    o.closed = true

proc `=copy`(dest: var MyObj; source: MyObj) {.error: "cannot copy".}
proc `=dup`(source: MyObj): MyObj {.error: "cannot dup".}
```

**Applies to**: formerly `Z3ContextObj`/`Z3Context`, `Z3SolverObj`/`Z3Solver` in `src/verification/solver/z3_bindings.nim` — the Z3 FFI layer was **removed** (AGENTS.md §1 v30); Z3 now runs via CLI subprocess (`src/verification/solver/z3_pool.nim`). The hook pattern applies to any `ref object` wrapping an external resource.

**Note**: `{.error.}` on `=copy`/`=dup` only prevents value-type copies of the underlying object. Ref sharing (passing the same ref to multiple functions) is still allowed by Nim's reference semantics — it just increments the refcount. To enforce single-owner transfer at the API level, use `sink` parameters.

---

## §18. Term-Rewriting Template: NOT an Experimental Feature (Nim 2.2.10)

**Discovery Date**: 2026-07-02  
**Severity**: Documentation Mismatch  
**Status**: Resolved  

### Symptom

Adding `switch("experimental", "termRewriting")` to `config/effects.nims` caused:
```
config.nims(1, 2) Error: unknown experimental feature
```

### Root Cause

`termRewriting` is **NOT** an experimental feature in Nim 2.2.10. The `template name{pattern}()` syntax is a standard language feature and requires no `--experimental` flag.

The Nim 2.2.10 experimental feature enum (from `compiler/options.nim:206-235`) contains:
```
dotOperators, callOperator, parallel, destructor, notnil,
dynamicBindSym, forLoopMacros, caseStmtMacros, codeReordering,
compiletimeFFI, vmopsDanger, strictFuncs, views, strictNotNil,
overloadableEnums, strictEffects, unicodeOperators,
flexibleOptionalParams, strictDefs, strictCaseObjects,
inferGenericTypes, openSym, genericsOpenSym, vtables, typeBoundOps
```

No `termRewriting` entry exists. Context7 documentation incorrectly indicated `{.experimental: "termRewriting".}` was required.

### Resolution

Removed `switch("experimental", "termRewriting")` from `config/effects.nims`. The TRM template that motivated the switch worked natively without any experimental flag. That template (`rewriteGateSeverity`, rewriting `getEnv("AXIOM_GATE_SEVERITY", "error")` into `getAxiomEnv(evGateSeverity, "error")`) no longer exists: its subject environment variable was deleted entirely in the DEBT#478 ambient-severity closure (2026-10-07), and no term-rewriting template remains under `src/core/trusted/`. The language insight below is unaffected.

### Key Insight

Term-rewriting templates (`template name{pattern}(...)`) in Nim 2.2.10 are **standard language constructs**, not experimental. They differ from the older `termRewriting` experimental feature (Nim 0.x/1.x era macro rewriting).

### Affected Files
- `config/effects.nims` — removed invalid switch
- `src/core/trusted/axiom_pragmas.nim` — former TRM template definition (template since deleted; see Resolution)

---

## §28. `{.nodiscard.}` Does Not Exist — `discard` Is the Only Way to Ignore Return Values

**Discovery Date**: 2026-07-02
**Nim version**: 2.2.10
**Severity**: Documentation Misconception
**Status**: Resolved

### Symptom

Agents (and some documentation sources) refer to `{.nodiscard.}` as a Nim pragma that prevents ignoring return values, analogous to `[[nodiscard]]` in C++ or `#[must_use]` in Rust.

### Root Cause

Nim does **not** have a `{.nodiscard.}` pragma. The only related pragma is `{.discardable.}`, which does the **opposite** — it *allows* callers to ignore the return value without a compiler warning. In Nim, ignoring an unused return value without `{.discardable.}` produces:

```
Warning: expression 'foo()' is of type 'int' and has to be used (or discarded)
```

There is no pragma to *enforce* return-value usage. The warning is the enforcement mechanism itself.

### Key Facts

| Statement | Correct? |
|-----------|----------|
| `{.nodiscard.}` exists in Nim | **False** |
| `{.discardable.}` suppresses unused-return warnings | **True** |
| `discard` is the only way to intentionally ignore a return value | **True** |
| `discard` is explicit, not accidental — it signals intentional non-use | **True** |

### Implication for `proc` → `func` Migration

When converting `proc` to `func`, any call that previously returned a value and was ignored via `discard` will still require `discard` after conversion. The `discard` keyword is not an anti-pattern — it is Nim's deliberate mechanism for expressing "I acknowledge this value exists but do not need it."

```nim
# This is perfectly valid and idiomatic:
proc writeFile(path: string; data: string) {.discardable, tags: [WriteIOEffect].} =
  ...

# Caller:
discard writeFile("/tmp/test", "hello")  # Explicit: I know it returns, I don't need it
```

Removing `discard` statements during `proc` → `func` conversion is **wrong** — they are intentional.

---

## §29. Compile-Time Purity Tester: Shadow File + `nim check` Approach

**Discovery Date**: 2026-07-02
**Nim version**: 2.2.10
**Affected**: `tools/proc_to_func_tester.nim`, all `src/` modules
**Full spec**: `docs/spec/compile_time_purity_tester.md`

### Approach

Instead of agent-based heuristic classification (which is error-prone and requires per-proc analysis), the compile-time purity tester uses the Nim compiler itself as the side-effect oracle:

1. Create shadow copies (`*_shadow.nim`) of source files with `proc` → `func` substitution
2. Run `nim check --errorMax:0` on **all** shadow files in a single invocation
3. Parse compiler output: "can have side effects" → `io`, no error → `pure`

This is an **O(1) batch** operation — one compiler invocation classifies every proc in the project.

### Error Cascading Behavior

When converting transitively-dependent procs, the Nim compiler exhibits **error cascading**:

```
# Original:
proc parseConfig(path: string): Config =       # calls readFile → side effect
  let raw = readFile(path)                      # I/O
  result = parseJson(raw)                       # pure

proc validate(cfg: Config): bool =              # calls parseConfig → transitive side effect
  let parsed = parseConfig("config.json")       # transitive I/O via parseConfig
  result = parsed.isValid
```

If both are converted to `func`, the compiler flags **both**:
- `parseConfig` — direct I/O (`readFile`)
- `validate` — transitive I/O (calls `parseConfig` which calls `readFile`)

**This is correct behavior.** A function that transitively depends on I/O is not pure. The cascading ensures no impure function slips through the classification.

### Policy

- **Required**: The compile-time purity tester (`tools/proc_to_func_tester.nim`) is the **authoritative** source for `proc` → `func` conversion decisions.
- **Forbidden**: Agent-based heuristic classification of side effects without compiler verification.
- **Required**: Shadow files MUST be cleaned up after each tester run (the tool handles this automatically).

---

## §30. Mid-line `##` Doc Comment After a Pragma — Lexical Parse Error

### 30.1 Discovery

- **Date**: 2026-08-02
- **Context**: `nim check src/verification/symbolic_test_synth.nim` failed while running the nimtry v2 full-tree scan (check-arch gate)
- **Affected**: any Nim source with a `##` doc comment mid-line immediately after a `{.raises: [].}` (or other) pragma inside a proc(...) parameter list; example at HEAD: `z3Exec: proc(script: string): string {.raises: [].}  ## Z3 executor callback`

### 30.2 Symptom

`nim check` reports `Error: expected: ')', but got: '<comment text>'` / `expression expected, but found ')'` at the pragma line — the parse error breaks the parameter list.

### 30.3 Root Cause

`##` is a documentation comment; lexically it must follow a newline or another comment. Inline after code it consumes the remainder of the line/expression instead of being treated as a plain trailing comment, corrupting the enclosing proc type parameter parse. (Single `#` is a plain line comment and is safe mid-line. `{.pragma.}`-only template lines are special-cased by the lexer and tolerate a trailing `##`.)

### 30.4 Workaround

Use `# ` (single hash) for trailing inline comments inside signatures; reserve `##` for standalone doc-comment lines.

### 30.5 Policy

- **Required**: no mid-line `##` after a trailing pragma/parameter on the same line
- **Recommended**: gate scanners that parse source should fail fast on this pattern (it is a lexical error, not a semantic one)

---

## §31. `--experimental:strictEffects` Is Declared but Never Read (Nim 2.2.10) — Verified No-Op

### 31.1 Discovery

- **Date**: 2026-10-04
- **Context**: workstream `fix/authority-singularity-d1d2` — equivalence audit of candidate delegations to platform features. `config/effects.nims` enables the flag on the global build path.
- **Affected**: every compilation unit built through `config/effects.nims`; the flag reads as effect enforcement but enforces nothing by itself.

### 31.2 Status: VERIFIED (not an unverified claim)

Verified against the pinned toolchain at `<user-home>/.choosenim/toolchains/nim-2.2.10/` (`nim --version` → `Nim Compiler Version 2.2.10 [Linux: amd64]`, compiled 2026-04-24) by four independent checks:

1. **Declaration only.** `grep -rn 'strictEffects' compiler/ *.nim plugins/` over the compiler sources returns exactly ONE hit: `compiler/options.nim:225`, the bare enumerator inside `Feature*` (`overloadableEnums, strictEffects, unicodeOperators`). No other compiler file mentions the identifier.
2. **No reader.** Enumerating every site that tests membership in `conf.features` / `c.config.features` yields readers for `vtables`, `codeReordering`, `strictDefs`, `strictCaseObjects`, `strictFuncs`, `views`, `strictNotNil`, `callOperator`, `dotOperators`, `destructor`, `notnil`, `parallel`, `genericsOpenSym`, `openSym`, `dynamicBindSym`, `inferGenericTypes`, `typeBoundOps`, `flexibleOptionalParams`, `compiletimeFFI`, `vmopsDanger`, `allowCast`, `allowInfiniteLoops`, `allowInfiniteRecursion`. `strictEffects` is in none of them. The only places a `Feature` is turned into compiler behaviour are `commands.nim:310` / `:1085` (`--experimental:X` → `conf.features.incl …`) and `pipelines.nim:85` / `pragmas.nim:433` (`{.experimental: "X".}` → `c.features.incl …`) — set insertion only, never a read.
3. **The switch moved to `LegacyFeature`.** `compiler/changelogs/changelog_2_0_0_details.md:104` records "`strictEffects` are no longer experimental. Use `legacy:laxEffects` to keep backward compatibility." In 2.2.10 the effect system is ON unconditionally and the opt-OUT lives in `LegacyFeature.laxEffects` (`options.nim:246`), read at `sempass2.nim:664, 761, 778, 1127`. The in-source pragmas that remain (`lib/std/private/globs.nim:16`, `lib/pure/options.nim:73`, `lib/pure/algorithm.nim:155`, `lib/pure/collections/sequtils.nim:93`) are themselves inert for the same reason — they set a flag nobody reads.
4. **Empirical A/B.** A source with a genuine effect violation (`proc impure = writeFile(...)` called from a `{.raises: [].}` proc) was compiled twice with `--warning:Effect --warningAsError:Effect`, once without and once with `--experimental:strictEffects`. Both runs emitted byte-identical diagnostics and exited 1. Separately, `static: echo compileOption("experimental", "strictEffects")` printed `false` by default and `true` when the flag was passed — so the flag IS accepted and recorded in the config set, it simply has no effect on any diagnostic.

### 31.3 Consequence

Effect enforcement in Axiom does not come from `--experimental:strictEffects`. It comes from the unconditional 2.x effect system plus `config/effects.nims:77-79`:

```
switch("warningAsError", "Effect")        # Effect 위반 → 항상 컴파일 에러
if getEnv("ALLOW_WARNINGS") != "true":
  switch("warningAsError", "Effect")      # Defense-in-depth (redundant but harmless)
```

Removing the flag would therefore change nothing about Axiom's effect enforcement — which is exactly why flag removal was judged out of scope for this workstream and left in place.

### 31.4 Policy

- **Required**: treat `--experimental:strictEffects` as dead configuration. Any argument that depends on it ("strict effects are on because we set the flag") is invalid.
- **Required**: when reasoning about effect coverage, cite the unconditional 2.x effect system and the `warningAsError:Effect` switch, never the experimental flag.
- **Note**: the flag is inert, not erroneous. The compiler accepts it without warning and without failing the build, so its presence is harmless — it is a documentation hazard, not a build hazard.

### 31.5 Debt binding

None required. AGENTS.md §0.5c's dual binding (`DEBT#` marker + `{.axiomDebt: …}` pragma) applies to in-source comments; this record is documentation-only and lives entirely in `docs/spec/`.

---

*Last updated: 2026-10-04*
