## Benchmark: Loop Case — 루프 불변식 필요
## SV-COMP category: LoopInvariant
## Expected: provenLayer ∈ {plkL2Cegar, plkL3Scribe}
## 이 함수는 루프 불변식 없이는 증명 불가능한 안전성을 가진다.

func loopSum*(n: int): int =
  ## Precondition: n >= 0
  ## Postcondition: result >= 0
  ## Loop Invariant: sum >= 0 ∧ 0 <= i <= n
  var i = 0
  var sum = 0
  while i < n:
    sum += 1
    i += 1
  return sum
