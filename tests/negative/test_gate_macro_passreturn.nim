import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

import gate/framework/gate_macro

gate badExceptReturnPass:
  try:
    raise newException(ValueError, "test")
  except:
    return Pass

{.pop.}
