import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## Reliability Score Hard Gate — Emergency bypass enforcement
##
## Computes reliability score from bypass_audit.jsonl.
## BLOCKS emergency bypass when score < 80.
## Normal gate runs still pass (with warning when score is low).
##
## This gate is ALWAYS ON and has weight=critical.
## The only way to bypass is to restore reliability score above threshold
## by reducing the number of historical bypasses.
##
## Exit 0 = pass, exit 1 = emergency bypass blocked.

import core/axiom_pragmas
import core/trusted/env_access
import core/trusted/bypass_verify
import infrastructure/bypass_audit
import infrastructure/logging_facade



axiomIoBoundary()

const
  GateTag* = "[reliability-gate]"
  AlwaysOn* = true
  GateId* = "reliability-gate"

proc runGate*(): int =
  ## Main gate logic.
  ## Returns 0 for pass, 1 for hard fail.
  let relReport = computeReliabilityScore()
  let emergencyBypass = isEmergencyBypass()

  if emergencyBypass and relReport.score < HardGateThreshold:
    # HARD FAIL — emergency bypass blocked due to low reliability
    logError("reliability_gate", GateTag & " [GATE-HARD-FAIL] Reliability score " &
                     $relReport.score & " < threshold " & $HardGateThreshold)
    logError("reliability_gate", GateTag & " [GATE-HARD-FAIL] Emergency bypass BLOCKED. " &
                     "Fix underlying issues first. " &
                     "Total bypasses: " & $relReport.totalBypasses)
    return 1

  if relReport.score < HardGateThreshold:
    # Warning only — gates are still running normally, no emergency bypass
    logError("reliability_gate", GateTag & " [WARN] Reliability score " &
                     $relReport.score & " < " & $HardGateThreshold &
                     " (" & $relReport.totalBypasses & " historical bypasses). " &
                     "Emergency bypass would be blocked.")
  else:
    logInfo("reliability_gate", GateTag & " [PASS] Reliability score " &
                     $relReport.score & " (threshold: " & $HardGateThreshold & ")")

  return 0

when isMainModule:
  quit(runGate())

{.pop.}
