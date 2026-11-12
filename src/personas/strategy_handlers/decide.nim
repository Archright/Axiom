## Strategy handler for decide (typeclass-based decidability).

import core/trusted/layer_declaration
axiomLayer "infrastructure"
import personas/strategy_registry

{.push raises: [CatchableError].}

func handleDecide*(): string {.
    registerStrategyHandler(jsDecide), raises: [].} =
  "decide"

{.pop}
