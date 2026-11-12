## Strategy handler for the simplifier.

import core/trusted/layer_declaration
axiomLayer "infrastructure"
import personas/strategy_registry

{.push raises: [CatchableError].}

func handleSimp*(): string {.
    registerStrategyHandler(jsSimp), raises: [].} =
  "simp"

{.pop}
