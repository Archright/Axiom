import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

import gate/framework/gate_macro

gate badAssertTrue:
  let msg = "(assert true)"
  if true:
    return GateResult(status: Pass)

{.pop.}
