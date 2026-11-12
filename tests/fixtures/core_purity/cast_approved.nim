## cast_approved — the escape hatch carries BOTH structural approvals:
## a `## [SEE:` annotation on the preceding line and a minimal enclosing `func`
## declaring `{.noSideEffect.}`. Expect zero violations.
import core/trusted/layer_declaration
axiomLayer "domain"

func pureWrap*(s: string): string {.noSideEffect, raises: [].} =
  ## [SEE: docs/spec/nim_effect_system_quirks.md §cast_noSideEffect]
  {.cast(noSideEffect).}:
    result = s