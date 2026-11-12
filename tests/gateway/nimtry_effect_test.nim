## Positive test for effect pragma consistency.
## All procs with {.axiomEffect: IoEffect.} are procs.
## All funcs with {.axiomEffect: Pure.} are funcs.
## This file should PASS nimtry effect-pragma-consistency.

import core/trusted/axiom_pragmas

{.push raises: [].}

proc ioWork*(x: int): int {.axiomEffect: IOEffect.} =
  ## A proc correctly annotated as IO — this is fine.
  result = x + 1

func pureCalc*(x: int): int {.axiomEffect: Pure.} =
  ## A func correctly annotated as Pure — this is fine.
  x * 2

proc anotherIoOp*(s: string): string {.axiomEffect: IOEffect.} =
  ## Another proc with IO annotation — valid.
  s & "_done"

func pureMath*(a, b: int): int {.axiomEffect: Pure.} =
  ## Pure function — valid.
  a + b

proc unannotated*(x: int): int =
  ## No axiomEffect — should not trigger consistency check.
  x
