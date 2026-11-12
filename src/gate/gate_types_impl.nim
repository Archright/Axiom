import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## gate_types_impl.nim — Utility functions for gate types.
## Separated from gate_contract.nim to maintain single-responsibility.
## All consumers import `gate/gate_types` (forwarding stub) which re-exports this.

import gate/gate_contract
import core/results
import std/strformat
import std/times

## Formats a ``GateResult`` as a human-readable string.
## Shows gate name, pass/fail status, and duration in milliseconds.
proc `$`*(r: GateResult): string =
  if r.ok:
    &"{r.name}: Passed ({r.duration.inMilliseconds}ms)"
  else:
    &"{r.name}: Failed ({r.duration.inMilliseconds}ms) [{r.failureCategory}]"

func gateErr*(code: GateErrorCode; msg: string; gateId: string = ""): GateError =
  GateError(code: code, message: msg, gateId: gateId)

func gateOk*(gr: GateResult): GateOutcome =
  ok(gr)

func gateFail*(code: GateErrorCode; msg: string; gateId: string = ""): GateOutcome =
  err(gateErr(code, msg, gateId))

{.pop.}
