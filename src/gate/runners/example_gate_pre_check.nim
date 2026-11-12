import core/trusted/layer_declaration
axiomLayer "gate"

## example_gate_pre_check.nim — Gate0: Pre-check gate (no dependencies)
##
## Demonstrates the first gate in the Phase 3A dependency chain:
##   Gate0 (pre-check) -> Gate1 (validate) -> Gate2 (report)
##
## This gate has no dependencies and runs first in the DAG.

import gate/gate_registry

proc preCheckRunner(ctx: GateContext): bool {.nimcall, gcsafe, raises: [].} =
  echo "[Gate0: pre-check] Validating repository at: ", ctx.repoRoot
  true
