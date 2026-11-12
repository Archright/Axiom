## Shape handler for linear arithmetic goals (Nat/Int, +, -, *, ≤, ≥).

import core/trusted/layer_declaration
axiomLayer "infrastructure"
import personas/strategy_registry

{.push raises: [CatchableError].}

func handleLinearArithmetic*(): seq[JudgeStrategy] {.
    registerShapeHandler(gsLinearArithmetic), raises: [].} =
  @[jsOmega, jsDecide, jsSimpOmega]

{.pop}
