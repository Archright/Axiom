import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

import core/gate/env_gate

when isMainModule:
  runCheckAndExit()

{.pop.}
