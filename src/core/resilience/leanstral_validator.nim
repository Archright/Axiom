import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Leanstral response validation — contract enforcement.
## Validates LLM responses before accepting them as proof artifacts.

import std/strutils
import core/resilience/error_context

type
  LeanstralValidation* = object
    valid*: bool
    reason*: string
    suggestedAction*: RecoveryAction
    errorClass*: ErrorClass

func containsMarkdownNoise(s: string): bool {.noSideEffect.} =
  ## Check if string contains markdown formatting that shouldn't be in an invariant.
  s.contains("```") or s.contains("**") or s.contains("## ") or
  s.contains("- ") or s.contains("1. ") or s.contains("> ")

func validateLeanstralResponse*(
  success: bool;
  timedOut: bool;
  theoremSource: string;
  confidence: float;
  functionName: string
): LeanstralValidation {.noSideEffect.} =
  ## Validate a Leanstral response and suggest recovery action.

  # Case 1: Failed + timed out → transient, retry
  if not success and timedOut:
    return LeanstralValidation(
      valid: false,
      reason: "Leanstral timed out for " & functionName,
      suggestedAction: raRetry,
      errorClass: ecTransient
    )

  # Case 2: Failed + empty → validation error, retry with degraded prompt
  if not success and theoremSource.len == 0:
    return LeanstralValidation(
      valid: false,
      reason: "Leanstral returned empty response for " & functionName,
      suggestedAction: raRetryWithDegradedPrompt,
      errorClass: ecValidation
    )

  # Case 3: Failed + has some content → might be partial, retry
  if not success:
    return LeanstralValidation(
      valid: false,
      reason: "Leanstral failed with partial output for " & functionName,
      suggestedAction: raRetry,
      errorClass: ecTransient
    )

  # Case 4: Success but too short → suspect garbage
  if theoremSource.len < 5:
    return LeanstralValidation(
      valid: false,
      reason: "Leanstral response too short (" & $theoremSource.len & " chars) for " & functionName,
      suggestedAction: raRetryWithDegradedPrompt,
      errorClass: ecValidation
    )

  # Case 5: Success but low confidence
  if confidence < 0.3:
    return LeanstralValidation(
      valid: false,
      reason: "Low confidence (" & $confidence & ") for " & functionName,
      suggestedAction: raRetryWithDegradedPrompt,
      errorClass: ecValidation
    )

  # Case 6: Success but contains markdown noise → sanitize
  if theoremSource.containsMarkdownNoise():
    return LeanstralValidation(
      valid: false,
      reason: "Markdown noise detected in response for " & functionName,
      suggestedAction: raRetry,
      errorClass: ecTransient
    )

  # Case 7: Valid response
  LeanstralValidation(
    valid: true,
    reason: "Valid response for " & functionName,
    suggestedAction: raRetry,  # not used when valid=true
    errorClass: ecTransient    # not used when valid=true
  )

{.pop.}
