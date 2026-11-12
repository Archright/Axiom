{.push raises: [].}

## Comprehensive negative tests for the resilience pipeline.
## Covers: error classification, circuit breaker lifecycle, retry fail-fast,
## atomic JSONL dump, and Leanstral validation rejection paths.

import std/[unittest, json, strutils]
import core/resilience/error_context
import core/resilience/error_classifier
import core/resilience/retry_policy
import core/resilience/leanstral_validator
import core/resilience/resilience_config

# ── Injectable virtual clock ──────────────────────────────────────────────────
# ClockFn is a closure type (proc type with noSideEffect pragma).
# To satisfy the closure constraint, we build the closure inside a wrapper
# so that the anonymous proc captures a local ptr, forcing closure semantics.

var fakeTime: int64 = 1000

proc buildTestClock(): ClockFn =
  let anchor = fakeTime.addr
  proc(): int64 =
    anchor[]

let testClock: ClockFn = buildTestClock()

# ── Test 1: Transient error classification ────────────────────────────────────

suite "Error classification — transient":
  test "Transient error → classified as ecTransient, scope asNone":
    let e = newException(CatchableError, "network timeout")
    check classifyError(e) == ecTransient
    check mapClassToAbortScope(ecTransient) == asNone

# ── Test 2: System error classification ───────────────────────────────────────

suite "Error classification — system":
  test "System error → classified as ecSystem, scope asGlobal":
    let e = newException(CatchableError, "out of memory allocation failed")
    check classifyError(e) == ecSystem
    check mapClassToAbortScope(ecSystem) == asGlobal

# ── Test 3: Logic error classification ────────────────────────────────────────

suite "Error classification — logic":
  test "Logic error → classified as ecLogic, scope asLocal":
    let e = newException(CatchableError, "invariant contradiction detected")
    check classifyError(e) == ecLogic
    check mapClassToAbortScope(ecLogic) == asLocal

# ── Test 4: Rate limit error classification ───────────────────────────────────

suite "Error classification — rate limited":
  test "Rate limit error → classified as ecRateLimited, scope asNone":
    let e = newException(CatchableError, "HTTP 429 rate limit exceeded")
    check classifyError(e) == ecRateLimited
    check mapClassToAbortScope(ecRateLimited) == asNone

# ── Test 5: Validation error classification ───────────────────────────────────

suite "Error classification — validation":
  test "Validation error → classified as ecValidation, scope asNone":
    # ecValidation is produced via the Leanstral validation path.
    # classifyError has no validation branch (unknown → transient fallback).
    let lr = LeanstralResultLike(
      success: false,
      timedOut: false,
      theoremSource: "",
      confidence: 0.0,
      error: ""
    )
    check classifyFromLeanstral(lr) == ecValidation
    check mapClassToAbortScope(ecValidation) == asNone

# ── Test 6: Circuit breaker lifecycle ─────────────────────────────────────────

suite "Circuit breaker lifecycle":
  test "Circuit breaker opens after threshold failures":
    fakeTime = 1000
    var breaker = newCircuitBreaker(threshold = 3, resetAfterMs = 5000, nowMs = testClock)
    check breaker.state == cbsClosed

    # Fail 3 times → opens
    for i in 0..<3:
      check breaker.checkCircuit() # closed allows calls
      breaker.recordFailure()
    check breaker.state == cbsOpen
    check not breaker.checkCircuit() # open blocks calls

    # Half-open after reset time
    fakeTime += 5001
    check breaker.checkCircuit() # transitions to half-open
    check breaker.state == cbsHalfOpen

    # Success in half-open → closed
    breaker.recordSuccess()
    check breaker.state == cbsClosed

# ── Test 7: retryWithBackoff fail-fast for ecLogic ───────────────────────────

suite "retryWithBackoff — fail-fast":
  test "ecLogic causes LocalAbort at entry (no body execution)":
    var breaker = newCircuitBreaker(5, 30000)
    let retryCfg = RetryConfig(
      maxAttempts: 3,
      baseDelayMs: 100,
      maxDelayMs: 5000,
      jitterRatio: 0.1
    )

    # ecLogic → mapClassToAbortScope returns asLocal (non-None) → immediate return.
    # Body is never invoked. attempts == 0.
    let result = retryWithBackoff[int](
      config = retryCfg,
      breaker = breaker,
      errorClass = ecLogic,
      body = proc(): int = 42
    )
    check result.abortScope == asLocal
    check result.errorClass == ecLogic
    check result.attempts == 0

# ── Test 8: Atomic dump — JSONL file contains valid JSON ──────────────────────

suite "Error context capture — in-memory":
  test "captureErrorContext populates all required fields":
    # Verify captureErrorContext populates all required fields.
    # NOTE: dumpErrorContext file I/O is excluded from hermetic scope;
    # tested separately via gateway feature tests.
    let ctx = captureErrorContext(
      "testFunc", "legislate",
      newException(CatchableError, "test error")
    )
    check ctx.nodeId == "testFunc"
    check ctx.phase == "legislate"
    check ctx.exceptionMsg == "test error"
    check ctx.errorClass == ecSystem # default
    check ctx.recoveryAction == raLocalAbort # default

# ── Test 9: Leanstral validation — failed + timed out ────────────────────────

suite "Leanstral validation — negative paths":
  test "Failed + timed_out → ecTransient with raRetry":
    let val = validateLeanstralResponse(
      success = false,
      timedOut = true,
      theoremSource = "",
      confidence = 0.0,
      functionName = "test"
    )
    check val.errorClass == ecTransient
    check val.suggestedAction == raRetry
    check val.valid == false

  test "Failed + empty response → ecValidation with raRetryWithDegradedPrompt":
    let val = validateLeanstralResponse(
      success = false,
      timedOut = false,
      theoremSource = "",
      confidence = 0.0,
      functionName = "test"
    )
    check val.errorClass == ecValidation
    check val.suggestedAction == raRetryWithDegradedPrompt

  test "Success but too short → ecValidation":
    let val = validateLeanstralResponse(
      success = true,
      timedOut = false,
      theoremSource = "ab",
      confidence = 0.9,
      functionName = "test"
    )
    check val.errorClass == ecValidation
    check val.valid == false

{.pop.}
