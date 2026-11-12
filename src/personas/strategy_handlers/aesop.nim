## Strategy handler for aesop (structured auto).

import core/trusted/layer_declaration
axiomLayer "infrastructure"
import personas/strategy_registry

{.push raises: [CatchableError].}

func handleAesop*(): string {.
    registerStrategyHandler(jsAesop), raises: [].} =
  "aesop"

{.pop}
