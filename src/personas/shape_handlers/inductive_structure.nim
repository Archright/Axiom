## Shape handler for goals requiring induction on inductive types.

import core/trusted/layer_declaration
axiomLayer "infrastructure"
import personas/strategy_registry

{.push raises: [CatchableError].}

func handleInductiveStructure*(): seq[JudgeStrategy] {.
    registerShapeHandler(gsInductiveStructure), raises: [].} =
  @[jsGrind, jsAesop, jsSimp]

{.pop}
