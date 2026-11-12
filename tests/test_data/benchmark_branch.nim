## Benchmark: Branch Case — 조건 분기 + 불변식 방어
## SV-COMP category: ControlFlow
## Expected: provenLayer ∈ {plkL2Cegar, plkL3Scribe, plkL4Judge}
## 이 함수는 3-way 분기를 가지나, 모든 경로가 postcondition (result >= 0)을 만족한다.

func branchGuard*(x: int): int =
  ## Precondition: x >= 0
  ## Postcondition: result >= 0
  if x > 100:
    return x - 50   # safe: x > 100 → x - 50 > 50 >= 0
  elif x > 0:
    return x * 2    # safe: x > 0 → x * 2 > 0
  else:
    return 0        # safe: 0 >= 0
