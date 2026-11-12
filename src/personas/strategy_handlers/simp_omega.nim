## Strategy handler for combined simp + omega pass.

import core/trusted/layer_declaration
axiomLayer "infrastructure"
import personas/strategy_registry

{.push raises: [CatchableError].}

func handleSimpOmega*(): string {.
    registerStrategyHandler(jsSimpOmega), raises: [].} =
  "simp\n  omega"

{.pop}
