import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

import gate/framework/gate_macro

gate badCast:
  var x: int = 42
  let y = cast[float](x)

{.pop.}
