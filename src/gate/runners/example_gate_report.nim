import core/trusted/layer_declaration
axiomLayer "gate"

## example_gate_report.nim — Gate2: Report gate (depends on Gate1)
##
## Demonstrates the third gate in the Phase 3A dependency chain:
##   Gate0 (pre-check) -> Gate1 (validate) -> Gate2 (report)
##
## This gate depends on validate completing successfully first.

import gate/gate_registry

proc reportRunner(ctx: GateContext): bool {.nimcall, gcsafe, raises: [].} =
  echo "[Gate2: report] Generating gate report for ", ctx.repoRoot
  true
