## Benchmark: Pointer Case — 시퀀스 접근 안전성
## SV-COMP category: MemorySafety
## Expected: provenLayer == plkL1Bmc
## 이 함수는 bounds check를 포함하여 메모리 안전성을 보장한다.

func safeAccess*(arr: seq[int]; idx: int): int =
  ## Precondition: arr.len > 0
  ## Postcondition: (0 <= idx < arr.len) → result == arr[idx]
  if idx >= 0 and idx < arr.len:
    return arr[idx]
  else:
    return -1
