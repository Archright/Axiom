{.push raises: [].}
import core/trusted/layer_declaration
axiomLayer "domain"
import core/trusted/axiom_pragmas_lite
import std/times

## ── CoreLogSink hook ─────────────────────────────────────────────────────────
## Dependency-inversion hook: infrastructure/ injects a structured logger here
## without core/ importing infrastructure/. See logging_facade.nim for the injector.
type CoreLogSink* = proc(level: int, module: string, msg: string) {.nimcall, noSideEffect.}
proc defaultCoreLogSink(level: int, module: string, msg: string) {.noSideEffect.} = discard
var coreLogSink* {.threadvar.}: CoreLogSink
coreLogSink = defaultCoreLogSink

var coreDebugMode {.threadvar.}: bool
# NOTE: {.threadvar.}는 스레드별 독립 복사본.
# 각 스레드 초기화 시 setCoreDebugMode()를 호출해야 합니다.
proc setCoreDebugMode*(enabled: bool) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  coreDebugMode = enabled
proc propagateDebugMode*(enabled: bool) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## 멀티스레드 환경에서 모든 워커 스레드에 디버그 모드 전파.
  ## 스레드 초기화 루틴에서 호출해야 합니다.
  coreDebugMode = enabled
template coreLog*(msg: string) =
  ## 코어 로직 내 로깅. 부작용을 격리하여 상위 전이를 차단.
  ##
  ## [WARN] SAFETY: 인자 평가는 cast 블록 외부에서 일어납니다.
  ##    호출부의 부작용은 컴파일러에게 검증됩니다.
  block:
    let evaluatedMsg = msg  # 호출부의 부작용은 여기서 먼저 컴파일러에게 검증받음
    ## [SEE: docs/spec/nim_effect_system_quirks.md §cast_noSideEffect]
    {.cast(noSideEffect).}:
      if coreDebugMode:
        coreLogSink(0, "CORE", evaluatedMsg)
template coreTimestamp*(): float =
  ## 코어 로직 내 타임스탬프. 부작용을 격리.
  block:
    let ts = epochTime()  # 호출부에서 평가
    ## [SEE: docs/spec/nim_effect_system_quirks.md §cast_noSideEffect]
    {.cast(noSideEffect).}:
      ts
template coreEnv*(key: string): string =
  ## 코어 로직 내 환경변수 접근. 부작용을 격리.
  block:
    let envKey = key  # 호출부에서 평가
    ## [SEE: docs/spec/nim_effect_system_quirks.md §cast_noSideEffect]
    {.cast(noSideEffect).}:
      getEnv(envKey)
template coreEnvExists*(key: string): bool =
  ## 코어 로직 내 환경변수 존재 확인. 부작용을 격리.
  block:
    let envKey = key  # 호출부에서 평가
    ## [SEE: docs/spec/nim_effect_system_quirks.md §cast_noSideEffect]
    {.cast(noSideEffect).}:
      existsEnv(envKey)
