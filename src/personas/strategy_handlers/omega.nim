## Strategy handler for omega (linear arithmetic over Int/Nat).

import core/trusted/layer_declaration
axiomLayer "infrastructure"
import personas/strategy_registry

{.push raises: [CatchableError].}

func handleOmega*(): string {.
    registerStrategyHandler(jsOmega), raises: [].} =
  "omega"

{.pop}
