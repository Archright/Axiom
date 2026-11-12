import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Error classification and recovery policy determination.
## Maps exceptions and Leanstral results to ErrorClass and RecoveryAction.

import std/strutils
import core/resilience/error_context
import core/resilience/resilience_config

type
  AbortScope* = enum
    asNone = "none"
    asLocal = "local"
    asGlobal = "global"

  RecoveryPolicy* = object
    action*: RecoveryAction
    abortScope*: AbortScope
    maxRetries*: int
    backoffBaseMs*: int
    backoffMaxMs*: int
    reason*: string

  RecoveryResult*[T] = object
    value*: T
    abortScope*: AbortScope
    errorClass*: ErrorClass
    attempts*: int

  LeanstralResultLike* = object
    ## Minimal Leanstral result for classification (avoids import from verification/)
    success*: bool
    timedOut*: bool
    theoremSource*: string
    confidence*: float
    error*: string

func classifyError*(e: ref CatchableError): ErrorClass {.noSideEffect.} =
  ## Classify an exception into an ErrorClass.
  let msg = e.msg.toLowerAscii()
  if msg.contains("timed out") or msg.contains("timeout") or
     msg.contains("network") or msg.contains("connection"):
    return ecTransient
  if msg.contains("429") or msg.contains("rate limit"):
    return ecRateLimited
  if msg.contains("inconsistent") or msg.contains("contradiction"):
    return ecLogic
  if msg.contains("no space") or msg.contains("permission denied") or
     msg.contains("read-only") or msg.contains("out of memory"):
    return ecSystem
  # Default: treat unknown as transient (safe to retry)
  ecTransient

func classifyFromLeanstral*(lr: LeanstralResultLike): ErrorClass {.noSideEffect.} =
  ## Classify a Leanstral response into an ErrorClass.
  if not lr.success:
    if lr.timedOut:
      return ecTransient
    if lr.theoremSource.len == 0:
      return ecValidation
    return ecTransient
  # success but low quality
  if lr.theoremSource.len < 5:
    return ecValidation
  if lr.confidence < 0.3:
    return ecValidation
  ecTransient  # shouldn't reach here for successful results

func mapClassToAbortScope*(class: ErrorClass): AbortScope {.noSideEffect.} =
  ## Map ErrorClass to AbortScope for Fail-Fast behavior.
  ## ecLogic = node-level problem (invariant inconsistency) → Local Abort
  ## ecSystem = system-level problem (filesystem/memory) → Global Abort
  ## ecTransient/ecRateLimited/ecValidation = retryable → No Abort
  case class
  of ecLogic: asLocal
  of ecSystem: asGlobal
  of ecTransient, ecRateLimited, ecValidation: asNone

func mapClassToAction*(class: ErrorClass): RecoveryAction {.noSideEffect.} =
  ## Map ErrorClass to default RecoveryAction.
  case class
  of ecTransient: raRetry
  of ecRateLimited: raRetry
  of ecValidation: raRetryWithDegradedPrompt
  of ecLogic: raLocalAbort
  of ecSystem: raGlobalAbort

func determineRecovery*(
  class: ErrorClass;
  attemptCount: int;
  config: ResilienceConfig
): RecoveryPolicy {.noSideEffect.} =
  ## Determine recovery policy based on error class, attempt count, and config.
  let scope = mapClassToAbortScope(class)
  let action = mapClassToAction(class)

  if scope != asNone:
    # Non-retryable: immediate abort
    return RecoveryPolicy(
      action: action,
      abortScope: scope,
      maxRetries: 0,
      backoffBaseMs: 0,
      backoffMaxMs: 0,
      reason: "Fail-Fast: " & $class & " requires immediate " & $scope & " abort"
    )

  # Retryable
  let backoffMult = if class == ecRateLimited: config.rateLimitBackoffMultiplier else: 1
  RecoveryPolicy(
    action: action,
    abortScope: asNone,
    maxRetries: config.retryMaxAttempts - attemptCount,
    backoffBaseMs: config.retryBaseDelayMs * backoffMult,
    backoffMaxMs: config.retryMaxDelayMs,
    reason: "Retryable: " & $class & " (attempt " & $attemptCount & "/" & $config.retryMaxAttempts & ")"
  )

{.pop.}
