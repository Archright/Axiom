import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
## Typestate FSM for Proof Status
## ============================================================
## 미정의 전이는 타입 불일치로 컴파일 에러.
## case 문, Result[_, UnreachableTransition], 72개 패턴 매칭 불필요.
## ============================================================

type
  AxProofUnattempted* = distinct string
    ## 미시도 — 증명 시작 전 초기 상태

  AxProofInProgress* = distinct string
    ## 증명 진행 중 — Lean 커널에 요청 전달됨

  AxProofVerified* = distinct string
    ## Lean 커널 검증 완료 (Hard Truth)

  AxProofCounterEx* = distinct string
    ## 반례 발견 (SAT)

  AxProofTimedOut* = distinct string
    ## 타임아웃

  AxProofUnverifiable* = distinct string
    ## 검증 불가 (구조적 한계)

  AxProofBlocked* = distinct string
    ## 차단됨 (의존성 누락 등)

  AxProofVacuous* = distinct string
    ## 공허 모순

  AxProofUnknown* = distinct string
    ## 알 수 없음 (demote/reverify 대상)

# ─────────────────────────────────────────────────────────────
# 생성자 — 유일한 진입점
# ─────────────────────────────────────────────────────────────

func beginProof*(): AxProofUnattempted {.inline.} =
  AxProofUnattempted("")

# ─────────────────────────────────────────────────────────────
# 합법적 전이 함수 — 미정의 전이는 컴파일 에러
# ─────────────────────────────────────────────────────────────

# Unattempted → InProgress (증명 시작)
func start*(s: AxProofUnattempted): AxProofInProgress {.inline.} =
  AxProofInProgress(string(s))

# InProgress → Verified (성공)
func succeed*(s: AxProofInProgress): AxProofVerified {.inline.} =
  AxProofVerified(string(s))

# InProgress → CounterExample (반례 발견)
func counterExample*(s: AxProofInProgress): AxProofCounterEx {.inline.} =
  AxProofCounterEx(string(s))

# InProgress → TimedOut
func timeout*(s: AxProofInProgress): AxProofTimedOut {.inline.} =
  AxProofTimedOut(string(s))

# InProgress → Unverifiable (구조적 한계)
func unverifiable*(s: AxProofInProgress): AxProofUnverifiable {.inline.} =
  AxProofUnverifiable(string(s))

# InProgress → Blocked (의존성 누락)
func markBlocked*(s: AxProofInProgress): AxProofBlocked {.inline.} =
  AxProofBlocked(string(s))

# InProgress → Vacuous (공허 모순)
func vacuous*(s: AxProofInProgress): AxProofVacuous {.inline.} =
  AxProofVacuous(string(s))

# 실패 상태 → Unattempted (재시도)
func retry*(s: AxProofTimedOut): AxProofUnattempted {.inline.} =
  AxProofUnattempted("")

func retry*(s: AxProofCounterEx): AxProofUnattempted {.inline.} =
  AxProofUnattempted("")

func retry*(s: AxProofUnverifiable): AxProofUnattempted {.inline.} =
  AxProofUnattempted("")

func retry*(s: AxProofVacuous): AxProofUnattempted {.inline.} =
  AxProofUnattempted("")

# Blocked → Unattempted (해제)
func unblock*(s: AxProofBlocked): AxProofUnattempted {.inline.} =
  AxProofUnattempted("")

# Verified → Unknown (pseudo_verified demote)
func demote*(s: AxProofVerified): AxProofUnknown {.inline.} =
  AxProofUnknown("")

# Unknown → Unattempted (재검증)
func reverify*(s: AxProofUnknown): AxProofUnattempted {.inline.} =
  AxProofUnattempted("")

# ─────────────────────────────────────────────────────────────
# 검증 함수
# ─────────────────────────────────────────────────────────────

func isTerminal*(s: AxProofVerified): bool {.inline.} = true
func isTerminal*(s: AxProofCounterEx): bool {.inline.} = true
func isTerminal*(s: AxProofTimedOut): bool {.inline.} = true
func isTerminal*(s: AxProofUnverifiable): bool {.inline.} = true
func isTerminal*(s: AxProofBlocked): bool {.inline.} = true
func isTerminal*(s: AxProofVacuous): bool {.inline.} = true
func isTerminal*(s: AxProofUnknown): bool {.inline.} = true
func isTerminal*(s: AxProofUnattempted): bool {.inline.} = false
func isTerminal*(s: AxProofInProgress): bool {.inline.} = false

func isVerified*(s: AxProofVerified): bool {.inline.} = true
func isVerified*(s: AxProofUnattempted | AxProofInProgress | AxProofCounterEx |
                  AxProofTimedOut | AxProofUnverifiable | AxProofBlocked |
                  AxProofVacuous | AxProofUnknown): bool {.inline.} = false

# ─────────────────────────────────────────────────────────────
# 카노니컬 직렬화 (메모리 레이아웃 독립적)
# ─────────────────────────────────────────────────────────────

func stateName*(s: AxProofUnattempted): string = "unattempted"
func stateName*(s: AxProofInProgress): string = "in_progress"
func stateName*(s: AxProofVerified): string = "verified"
func stateName*(s: AxProofCounterEx): string = "counter_example"
func stateName*(s: AxProofTimedOut): string = "timed_out"
func stateName*(s: AxProofUnverifiable): string = "unverifiable"
func stateName*(s: AxProofBlocked): string = "blocked"
func stateName*(s: AxProofVacuous): string = "vacuous_contradiction"
func stateName*(s: AxProofUnknown): string = "unknown"

# ─────────────────────────────────────────────────────────────
# 전이 이름 (감사 로그용)
# ─────────────────────────────────────────────────────────────

func transitionName*(src: AxProofUnattempted, dst: AxProofInProgress): string = "start"
func transitionName*(src: AxProofInProgress, dst: AxProofVerified): string = "succeed"
func transitionName*(src: AxProofInProgress, dst: AxProofCounterEx): string = "counter_example"
func transitionName*(src: AxProofInProgress, dst: AxProofTimedOut): string = "timeout"
func transitionName*(src: AxProofInProgress, dst: AxProofUnverifiable): string = "unverifiable"
func transitionName*(src: AxProofInProgress, dst: AxProofBlocked): string = "markBlocked"
func transitionName*(src: AxProofInProgress, dst: AxProofVacuous): string = "vacuous"
func transitionName*(src: AxProofTimedOut, dst: AxProofUnattempted): string = "retry"
func transitionName*(src: AxProofCounterEx, dst: AxProofUnattempted): string = "retry"
func transitionName*(src: AxProofUnverifiable, dst: AxProofUnattempted): string = "retry"
func transitionName*(src: AxProofVacuous, dst: AxProofUnattempted): string = "retry"
func transitionName*(src: AxProofBlocked, dst: AxProofUnattempted): string = "unblock"
func transitionName*(src: AxProofVerified, dst: AxProofUnknown): string = "demote"
func transitionName*(src: AxProofUnknown, dst: AxProofUnattempted): string = "reverify"
