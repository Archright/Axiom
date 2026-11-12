import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

import std/os
import std/strutils
import core/results
import core/parsers/safe_parsers
import gate/gate_types
import gate/runners/gateway_test_runner
import core/axiom_pragmas
import infrastructure/logger
import infrastructure/logging_facade


# axiomIoBoundary

proc main() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if paramCount() < 3:
    logInfo("gateway_test_gate", "Usage: gateway_test_gate <repoRoot> <mode> <maxJobs>")
    quit(1)
  let repoRoot = paramStr(1)
  let modeStr = paramStr(2).toLowerAscii()
  let mode =
    if modeStr in ["incremental", "inc", "grmincremental", "pre-commit"]:
      grmIncremental
    elif modeStr in ["exhaustive", "full", "grmexhaustive", "pre-push"]:
      grmExhaustive
    else:
      logError("gateway_test_gate", "[gateway_test_gate] ERROR: invalid mode '" & paramStr(2) & "'; expected incremental|full|pre-commit|pre-push")
      quit(1)
  let maxJobsRes = safeParseInt(paramStr(3))
  if not maxJobsRes.isOk:
    logInfo("gateway_test_gate", "Invalid maxJobs: " & paramStr(3))
    quit(1)
  let maxJobs = maxJobsRes.get()
  let res = runGatewayTest(repoRoot, mode, maxJobs)
  logger.info (if res.ok: "PASS" else: "FAIL") & " " & res.name
  if not res.ok and res.stderr.len > 0:
    logInfo("gateway_test_gate", res.stderr)
  if not res.ok and res.stdout.len > 0:
    logInfo("gateway_test_gate", res.stdout)
  quit(if res.ok: 0 else: 1)

when isMainModule: main()

{.pop.}
