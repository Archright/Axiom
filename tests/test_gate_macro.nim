import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

import gate/framework/gate_macro

gate passingGate:
  if true:
    return GateResult(status: Pass)
  else:
    return GateResult(status: Fail, message: "unreachable")

{.pop.}
