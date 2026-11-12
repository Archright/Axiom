import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Retry policy with exponential backoff and circuit breaker.
## Circuit breaker uses injectable clock for deterministic testing.

import std/monotimes
import std/times
import std/os
import core/resilience/error_context
import core/resilience/error_classifier
import ../utils/axiom_clock
import core/trusted/axiom_pragmas

type
  RetryConfig* = object
    maxAttempts*: int
    baseDelayMs*: int
    maxDelayMs*: int
    jitterRatio*: float

  CircuitBreakerState* = enum
    cbsClosed       # normal operation
    cbsOpen         # circuit tripped, reject all
    cbsHalfOpen     # testing window, allow 1 probe

  ClockFn* = proc(): int64 {.noSideEffect, raises: [].}

  CircuitBreaker* = object
    state*: CircuitBreakerState
    failureCount*: int
    threshold*: int
    resetAfterMs*: int
    lastFailureMono*: int64
    probeSuccessCount*: int
    nowMs*: ClockFn

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc defaultClockMs*(clk: SystemClock): int64 {.inline, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect], axiomEffect: IOEffect.} =
  ## System clock: monotonic time in milliseconds.
  (getMonoTime().ticks div 1_000_000).int64

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func defaultClockMs*(clk: DeterministicClock): int64 {.inline, noSideEffect.} =
  ## Deterministic clock: virtual monotonic time in milliseconds.
  clk.mono div 1_000_000

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func newCircuitBreaker*(threshold, resetAfterMs: int;
                        nowMs: ClockFn = nil): CircuitBreaker {.noSideEffect.} =
  CircuitBreaker(
    state: cbsClosed,
    failureCount: 0,
    threshold: threshold,
    resetAfterMs: resetAfterMs,
    lastFailureMono: 0,
    probeSuccessCount: 0,
    nowMs: nowMs
  )

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc getNowMs(breaker: CircuitBreaker, clk: SystemClock): int64 {.inline, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect], axiomEffect: IOEffect.} =
  if breaker.nowMs != nil: breaker.nowMs()
  else: defaultClockMs(clk)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc checkCircuit*(breaker: var CircuitBreaker): bool {.tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect], axiomEffect: IOEffect.} =
  ## Check if circuit allows a request. Returns true if allowed.
  case breaker.state
  of cbsClosed:
    true
  of cbsOpen:
    let elapsed = getNowMs(breaker, SystemClock()) - breaker.lastFailureMono
    if elapsed >= breaker.resetAfterMs.int64:
      breaker.state = cbsHalfOpen
      breaker.probeSuccessCount = 0
      true
    else:
      false
  of cbsHalfOpen:
    true  # allow probe request

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func recordSuccess*(breaker: var CircuitBreaker) {.noSideEffect.} =
  case breaker.state
  of cbsHalfOpen:
    breaker.probeSuccessCount += 1
    if breaker.probeSuccessCount >= 1:  # single probe success closes circuit
      breaker.state = cbsClosed
      breaker.failureCount = 0
  of cbsClosed:
    breaker.failureCount = 0
  of cbsOpen:
    discard  # shouldn't happen

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc recordFailure*(breaker: var CircuitBreaker) {.tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect], axiomEffect: IOEffect.} =
  breaker.failureCount += 1
  breaker.lastFailureMono = getNowMs(breaker, SystemClock())
  case breaker.state
  of cbsHalfOpen:
    breaker.state = cbsOpen  # probe failed → back to open
  of cbsClosed:
    if breaker.failureCount >= breaker.threshold:
      breaker.state = cbsOpen
  of cbsOpen:
    discard  # already open

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func computeBackoffMs*(config: RetryConfig; attempt: int;
                       isRateLimited: bool = false): int {.noSideEffect.} =
  ## Compute exponential backoff delay with jitter.
  ## attempt is 0-based.
  let baseMult = if isRateLimited: 3 else: 1
  let base = config.baseDelayMs * baseMult
  let exponential = base * (1 shl attempt)  # base * 2^attempt
  let capped = min(exponential, config.maxDelayMs)
  # Add deterministic jitter based on attempt (no random needed)
  let jitter = (capped.float * config.jitterRatio * (attempt.float / config.maxAttempts.float)).int
  capped + jitter

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func retryWithBackoff*[T](
  config: RetryConfig;
  breaker: var CircuitBreaker;
  errorClass: ErrorClass;
  body: proc(): T {.raises: [].}
): RecoveryResult[T] =
  ## Execute body with retry logic and circuit breaker.
  ## Fail-Fast: ecLogic → asLocal (node abort), ecSystem → asGlobal (pipeline abort).
  ## Returns RecoveryResult with abortScope signal for caller.

  # Fail-Fast guard
  let scope = mapClassToAbortScope(errorClass)
  if scope != asNone:
    return RecoveryResult[T](
      abortScope: scope,
      errorClass: errorClass,
      attempts: 0
    )

  # Retryable path
  var lastErrorClass = errorClass
  for attempt in 0 ..< config.maxAttempts:
    # Check circuit breaker
    if not checkCircuit(breaker):
      return RecoveryResult[T](
        abortScope: asLocal,  # circuit open = local abort
        errorClass: ecTransient,
        attempts: attempt
      )

    try:
      let value = body()
      recordSuccess(breaker)
      return RecoveryResult[T](
        value: value,
        abortScope: asNone,
        errorClass: ecTransient,
        attempts: attempt + 1
      )
    except CatchableError as e:
      lastErrorClass = classifyError(e)
      recordFailure(breaker)

      # Check if error escalated to non-retryable
      let newScope = mapClassToAbortScope(lastErrorClass)
      if newScope != asNone:
        return RecoveryResult[T](
          abortScope: newScope,
          errorClass: lastErrorClass,
          attempts: attempt + 1
        )

      # Backoff before retry (skip on last attempt)
      if attempt < config.maxAttempts - 1:
        let delayMs = computeBackoffMs(config, attempt, lastErrorClass == ecRateLimited)
        sleep(delayMs)

  # All retries exhausted
  RecoveryResult[T](
    abortScope: asLocal,
    errorClass: lastErrorClass,
    attempts: config.maxAttempts
  )

{.pop.}
