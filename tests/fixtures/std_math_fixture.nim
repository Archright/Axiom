import core/axiom_pragmas

# 1. Tier 1 대상 (단순 산술 / 항등식)
proc addIdent*(x: int): int {.axiom: "result == x".} =
  x + 0

# 2. Tier 1.5 대상 (seq[T] 구조적 귀납법)
proc sumList*(xs: seq[int]): int {.axiom: "result >= 0".} =
  var s = 0
  for x in xs: s += abs(x)
  s

# 3. Tier 3 (Z3 BMC) 대상 (Bounded Invariant)
proc boundedInc*(x: int): int {.axiom: "x < 100 ==> result < 101".} =
  x + 1
