## Strategy handler for LLM fallback (Leanstral).

import core/trusted/layer_declaration
axiomLayer "infrastructure"
import personas/strategy_registry

{.push raises: [CatchableError].}

func handleLlmFallback*(): string {.
    registerStrategyHandler(jsLlmFallback), raises: [].} =
  "sorry"

{.pop}
