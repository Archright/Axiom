## Shape handler for classification-failed or empty goal sources.

import core/trusted/layer_declaration
axiomLayer "infrastructure"
import personas/strategy_registry

{.push raises: [CatchableError].}

func handleUnknown*(): seq[JudgeStrategy] {.
    registerShapeHandler(gsUnknown), raises: [].} =
  @[jsLlmFallback]

{.pop}
