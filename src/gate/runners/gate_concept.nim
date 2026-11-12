import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## gate_concept.nim — AxiomGate concept definition
##
## All gate runners that participate in compile-time macro dispatch
## must satisfy this concept. The concept ensures:
##   1. The runner accepts a GateExecutionContext (value type)
##   2. The runner returns a GateResult

import gate/gate_contract
import gate/utils/gate_safety_macro

type AxiomGate* = concept g
  ## Interface for compile-time registered gate runners.
  ## Each gate module must export a `proc run*(ctx: InProcessGateContext): GateResult`
  ## and call `registerGate("gate-id", run)` at module top level.
  g.run(InProcessGateContext) is GateResult

{.pop.}
