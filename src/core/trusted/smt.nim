import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}


import core/types/results
import core/types/domain_types

type
  SmtRangeSpec* = object
    theoremName*: string
    lowerBound*: int
    upperBound*: int
    queryTag*: string

func initSmtRangeSpec*(
  theoremName: string;
  lowerBound: int;
  upperBound: int;
  queryTag: string
): Result[SmtRangeSpec, AxiomError] {.inline.} =
  if theoremName.len == 0 or queryTag.len == 0:
    return Result[SmtRangeSpec, AxiomError](ok: false, err: axiomErrEmptyString)
  if lowerBound > upperBound:
    return Result[SmtRangeSpec, AxiomError](ok: false, err: axiomErrInvalidValue)
  Result[SmtRangeSpec, AxiomError](ok: true, value: SmtRangeSpec(
    theoremName: theoremName,
    lowerBound: lowerBound,
    upperBound: upperBound,
    queryTag: queryTag
  ))

{.pop.}

{.pop.}
