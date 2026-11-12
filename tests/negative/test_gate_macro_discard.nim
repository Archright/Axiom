import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

import gate/framework/gate_macro

gate badExceptDiscard:
  try:
    discard
  except:
    discard

{.pop.}
