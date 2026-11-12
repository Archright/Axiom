import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## Logging IoC Hub
## Core modules import THIS instead of infrastructure/logging_facade directly.
## Composition Root (pipeline_dispatch.nim) injects the real implementation.
## Default loggers route to infrastructure/logging_facade.

import infrastructure/logging_facade as lf

type LoggerProc* = proc(level, msg: string) {.nimcall, gcsafe, raises: [].}

proc defaultLogInfo(level, msg: string) {.nimcall, gcsafe, raises: [].} =
  lf.logMessage(lf.llInfo, "hub", msg)

proc defaultLogError(level, msg: string) {.nimcall, gcsafe, raises: [].} =
  lf.logMessage(lf.llError, "hub", msg)

var logInfoAction* {.global.}: LoggerProc = defaultLogInfo
var logErrorAction* {.global.}: LoggerProc = defaultLogError

var isLoggingInjected {.global.}: bool = false
var isIoCLocked {.global.}: bool = false

proc lockIoCRegistry*() =
  isIoCLocked = true

proc injectLogger*(logger: LoggerProc) =
  if isIoCLocked:
    raise newException(Defect, "[Axiom IoC-FATAL] Registry locked. Re-injection forbidden.")
  if isLoggingInjected:
    raise newException(Defect, "Axiom IoC Violation: Logger already injected.")
  logInfoAction = logger
  isLoggingInjected = true

template logInfo*(msg: string) =
  logInfoAction("INFO", msg)

template logInfo*(module, msg: string) =
  ## Backward-compatible overload — ignores module, passes msg only
  logInfoAction("INFO", msg)

template logError*(msg: string) =
  logErrorAction("ERROR", msg)

{.pop.}
