## Negative test for effect pragma consistency.
## A func declares {.axiomEffect: IoEffect.} — this is a violation.
## nimtry effect-pragma-consistency should FAIL on this file.

import core/trusted/axiom_pragmas

{.push raises: [].}

func badIo*(x: int): int {.axiomEffect: IoEffect.} =
  ## func but declares IoEffect — VIOLATION.
  ## A func cannot have side effects.
  x + 1
