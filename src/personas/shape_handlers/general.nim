## Shape handler for unrecognized but well-formed goals.

import core/trusted/layer_declaration
axiomLayer "infrastructure"
import personas/strategy_registry

{.push raises: [CatchableError].}

func handleGeneral*(): seq[JudgeStrategy] {.
    registerShapeHandler(gsGeneral), raises: [].} =
  @[jsOmega, jsDecide, jsGrind, jsSimpOmega, jsAesop]

{.pop}
