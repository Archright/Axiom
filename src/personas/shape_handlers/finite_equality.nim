## Shape handler for decidable equality on finite/enum types.

import core/trusted/layer_declaration
axiomLayer "infrastructure"
import personas/strategy_registry

{.push raises: [CatchableError].}

func handleFiniteEquality*(): seq[JudgeStrategy] {.
    registerShapeHandler(gsFiniteEquality), raises: [].} =
  @[jsDecide, jsNativeDecide]

{.pop}
