import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
## Typestate ↔ 카노니컬 문자열 변환
## CLI 레이어 의존 없음 — core 레이어에서 안전하게 사용 가능.
## ============================================================

# 카노니컬 문자열 → Typestate 체크 함수
func isTerminalState*(name: string): bool =
  case name
  of "verified", "counter_example", "timed_out", "unverifiable",
     "blocked", "vacuous_contradiction", "unknown":
    true
  of "unattempted", "in_progress":
    false
  else:
    false

func isVerifiedState*(name: string): bool =
  name == "verified"

# 카노니컬 문자열 검증
func isValidStateName*(name: string): bool =
  case name
  of "unattempted", "in_progress", "verified", "counter_example",
     "timed_out", "unverifiable", "blocked", "vacuous_contradiction", "unknown":
    true
  else:
    false

# 전이 유효성 검증 (문자열 기반 — 레거시 코드 마이그레이션용)
func isValidTransition*(fromState, toState: string): bool =
  ## Returns true if the transition from fromState to toState is valid.
  ## Used by legacy code during migration period.
  case fromState
  of "unattempted":
    toState in ["in_progress"]
  of "in_progress":
    toState in ["verified", "counter_example", "timed_out",
                "unverifiable", "blocked", "vacuous_contradiction"]
  of "verified":
    toState in ["unknown"]
  of "counter_example", "timed_out", "unverifiable", "vacuous_contradiction":
    toState in ["unattempted"]
  of "blocked":
    toState in ["unattempted"]
  of "unknown":
    toState in ["unattempted"]
  else:
    false
