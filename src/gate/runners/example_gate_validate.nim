import core/trusted/layer_declaration
axiomLayer "gate"

## example_gate_validate.nim — Gate1: Validate gate (depends on Gate0)
##
## Demonstrates the second gate in the Phase 3A dependency chain:
##   Gate0 (pre-check) -> Gate1 (validate) -> Gate2 (report)
##
## This gate depends on pre-check completing successfully first.

import gate/gate_registry

proc validateRunner(ctx: GateContext): bool {.nimcall, gcsafe, raises: [].} =
  echo "[Gate1: validate] Checking ", ctx.stagedFiles.len, " staged files"
  true
