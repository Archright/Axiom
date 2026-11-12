## Shape handler for structural/definitional equality goals (a = b).

import core/trusted/layer_declaration
axiomLayer "infrastructure"
import personas/strategy_registry

{.push raises: [CatchableError].}

func handleEquality*(): seq[JudgeStrategy] {.
    registerShapeHandler(gsEquality), raises: [].} =
  @[jsDecide, jsRfl, jsSimp, jsNativeDecide]

{.pop}
