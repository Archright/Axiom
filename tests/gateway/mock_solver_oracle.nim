{.push raises: [].}

## Mock Solver Oracle — CEGAR FSM 결정론적 검증용
##
## 실제 Z3 솔버 없이 CEGAR 분기 로직을 검증하기 위한 Mock 구현.
## ARC/ORC 안전: ref object + {.acyclic.} 패턴 사용.
## 단일 스레드 테스트 러너 전용.

import verification/cegar_engine  # CegarZ3CheckFn; re-exports cegar_types
import core/orchestrator/cegar_types  # CegarEngineVerdict, CegarEngineResult

type
  MockSolverMode* = enum
    msmAlwaysProven       ## 모든 쿼리에 true 반환 (cegarProven)
    msmAlwaysRefuted      ## 모든 쿼리에 false 반환 (cegarCounterexample)
    msmFirstRefute        ## 첫 쿼리만 false, 이후 true (refinement 시뮬레이션)
    msmTimeout            ## 타임아웃 시뮬레이션

  MockState {.acyclic.} = ref object
    ## ORC cycle collector 최적화: self-referential fields 없음
    callCount*: int

proc createMockZ3Check*(mode: MockSolverMode): CegarZ3CheckFn {.raises: [].} =
  ## Mock Z3 solver 생성. ARC/ORC 안전: closure가 ref object를 캡처.
  ## proc (not func): ref object heap allocation은 side effect.
  case mode
  of msmAlwaysProven:
    result = proc(query: string): bool {.closure, gcsafe, raises: [CatchableError].} =
      true
  of msmAlwaysRefuted:
    result = proc(query: string): bool {.closure, gcsafe, raises: [CatchableError].} =
      false
  of msmFirstRefute:
    let state = MockState(callCount: 0)
    result = proc(query: string): bool {.closure, gcsafe, raises: [CatchableError].} =
      state.callCount.inc
      if state.callCount == 1:
        return false   # 첫 쿼리: counterexample
      return true      # 이후: proven
  of msmTimeout:
    result = proc(query: string): bool {.closure, gcsafe, raises: [CatchableError].} =
      raise newException(CatchableError, "timeout")

func mockCegarEngineResult*(mode: MockSolverMode): CegarEngineResult {.raises: [].} =
  ## Mock CEGAR 엔진 결과 생성 (FSM 테스트용)
  case mode
  of msmAlwaysProven:
    CegarEngineResult(
      verdict: cegarProven,
      iterations: 1,
      elapsedMs: 0'i64
    )
  of msmAlwaysRefuted:
    CegarEngineResult(
      verdict: cegarCounterexample,
      iterations: 1,
      elapsedMs: 0'i64
    )
  of msmFirstRefute:
    CegarEngineResult(
      verdict: cegarProven,
      iterations: 2,
      elapsedMs: 0'i64
    )
  of msmTimeout:
    CegarEngineResult(
      verdict: cegarBudgetExceeded,
      iterations: 0,
      elapsedMs: 30000'i64
    )

{.pop.}
