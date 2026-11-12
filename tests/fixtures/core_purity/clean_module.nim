## clean_module — no unapproved side effect, no escape hatch. Expect zero violations.
import core/trusted/layer_declaration
axiomLayer "domain"

type
  Offset* = object
    delta*: int

func shift*(o: Offset, by: int): Offset {.raises: [].} =
  result.delta = o.delta + by