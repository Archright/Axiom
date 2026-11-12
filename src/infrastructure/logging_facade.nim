## Axiom Logging Facade — SSOT for all project logging.
import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import core/trusted/axiom_pragmas_lite
import core/trusted/core_pure_utils

type LogLevel* = enum
  llDebug = "DEBUG", llInfo = "INFO", llWarn = "WARN", llError = "ERROR", llFatal = "FATAL"

var currentLevel {.threadvar.}: LogLevel
currentLevel = llInfo

proc logMessage*(level: LogLevel; module, msg: string) {.gcsafe, raises: [], refines: "src/infrastructure/logging_facade_shadow.nim", axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if level >= currentLevel:
    try:
      stderr.writeLine "[" & $level & "] " & (if module.len > 0: module & ": " else: "") & msg
    except IOError:
      discard  # swallow — logging must never crash the caller

template logInfo*(module: static[string], msg: string) = logMessage(llInfo, module, msg)
template logWarn*(module: static[string], msg: string) = logMessage(llWarn, module, msg)
template logError*(module: static[string], msg: string) = logMessage(llError, module, msg)
template logDebug*(module: static[string], msg: string) = logMessage(llDebug, module, msg)

proc installCoreLogSink*() =
  ## Inject structured logger into core layer's hook.
  ## Call once at application bootstrap.
  coreLogSink = proc(level: int, module: string, msg: string) {.nimcall, noSideEffect.} =
    ## [SEE: docs/spec/nim_effect_system_quirks.md §cast_noSideEffect]
    {.cast(noSideEffect).}:
      logMessage(llWarn, "CORE", msg)
