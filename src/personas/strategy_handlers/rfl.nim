## Strategy handler for reflexivity (definitional equality).

import core/trusted/layer_declaration
axiomLayer "infrastructure"
import personas/strategy_registry

{.push raises: [CatchableError].}

func handleRfl*(): string {.
    registerStrategyHandler(jsRfl), raises: [].} =
  "rfl"

{.pop}
