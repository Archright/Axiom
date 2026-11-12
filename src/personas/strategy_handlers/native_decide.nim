## Strategy handler for native decide (Lean built-in, no Mathlib).

import core/trusted/layer_declaration
axiomLayer "infrastructure"
import personas/strategy_registry

{.push raises: [CatchableError].}

func handleNativeDecide*(): string {.
    registerStrategyHandler(jsNativeDecide), raises: [].} =
  "native_decide"

{.pop}
