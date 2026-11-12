## Strategy handler for grind (congruence + arithmetic).

import core/trusted/layer_declaration
axiomLayer "infrastructure"
import personas/strategy_registry

{.push raises: [CatchableError].}

func handleGrind*(): string {.
    registerStrategyHandler(jsGrind), raises: [].} =
  "grind"

{.pop}
