import core/trusted/layer_declaration
axiomLayer "infrastructure"
# DELEGATE MODULE — all public procs routed through infrastructure/logging_facade.
# Kept for backward compatibility of call sites. Do not add new code here.

import core/trusted/axiom_pragmas
import infrastructure/logging_facade as lf

axiomIoBoundary()

proc debug*(msg: string) {.raises: [], axiomEffect: IOEffect, refines: "src/infrastructure/logger_shadow.nim".} =
  lf.logMessage(lf.llDebug, "logger", msg)

proc info*(msg: string) {.raises: [], axiomEffect: IOEffect.} =
  lf.logMessage(lf.llInfo, "logger", msg)

proc warn*(msg: string) {.raises: [], axiomEffect: IOEffect.} =
  lf.logMessage(lf.llWarn, "logger", msg)

proc error*(msg: string) {.raises: [], axiomEffect: IOEffect.} =
  lf.logMessage(lf.llError, "logger", msg)

proc fatal*(msg: string) {.raises: [], axiomEffect: IOEffect.} =
  lf.logMessage(lf.llFatal, "logger", msg)
