## cast_unapproved — four escape hatches, each missing one or both approvals.
## Expect four violations, one per site, with the exact missing condition named.
import core/trusted/layer_declaration
axiomLayer "domain"

template wrapTemplate(x: int): int =
  ## [SEE: docs/spec/nim_effect_system_quirks.md §cast_noSideEffect]
  {.cast(noSideEffect).}:
    result = x

func wrapNoPragma(x: int): int {.raises: [].} =
  ## [SEE: docs/spec/nim_effect_system_quirks.md §cast_noSideEffect]
  {.cast(noSideEffect).}:
    result = x

func wrapNoSee(x: int): int {.noSideEffect, raises: [].} =
  {.cast(noSideEffect).}:
    result = x

func wrapNoApproval(x: int): int {.raises: [].} =
  {.cast(noSideEffect).}:
    result = x