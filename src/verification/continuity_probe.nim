import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

func continuityProductionProbe*(x: int): int =
  let doubled = x * 2
  if doubled > 100:
    return 0
  doubled

func continuityProbeSaturation*(x: int): int =
  if x < 0:
    return 0
  x
