import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## LLM Response Guard — Pre-processing and safe JSON parsing for LLM output.
##
## LLM responses frequently contain markdown code fences, leading/trailing
## prose, or other noise around the actual payload. This module provides
## deterministic stripping and safe JSON parsing for LLM outputs.
##
## Used by:
##   - personas/legislator_feedback.nim (retry loop with parse guard)
##   - personas/judge_shadow_mode.nim (graceful fallback on parse failure)
##
## [SEE: nim_effect_system_quirks.md §1.1 — parseJson side effect]

import std/strutils
import std/json
import core/boundary/results_boundary

func stripMarkdownCodeBlock*(raw: string): string =
  ## Extract content between first '{' and last '}' from LLM output.
  ## Handles markdown code fences (```json ... ```), leading prose, etc.
  ## Returns the original string if no braces are found.
  let firstBrace = raw.find('{')
  let lastBrace = raw.rfind('}')
  if firstBrace < 0 or lastBrace < 0 or firstBrace >= lastBrace:
    return raw
  raw[firstBrace .. lastBrace]

func stripLeadingTrailingNoise*(raw: string): string =
  ## Strip markdown fences, whitespace, and non-JSON noise from LLM output.
  ## Primary extraction strategy: find JSON payload via brace delimiters.
  var cleaned = raw.strip()
  cleaned = stripMarkdownCodeBlock(cleaned)
  cleaned.strip()

# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
proc safeParseJson*(raw: string): Result[JsonNode, string] =
  ## Strip markdown noise then parse as JSON, returning Result.
  ## Proc (not func) because std/json.parseJson has side effects.
  ## [SEE: nim_effect_system_quirks.md §1.1]
  let cleaned = stripLeadingTrailingNoise(raw)
  if cleaned.len == 0:
    return err("LLM response is empty after noise stripping")
  try:
    ok(parseJson(cleaned))
  except CatchableError:
    err("JSON parse failed: " & getCurrentExceptionMsg())

func buildRetryPrompt*(errorReason: string; originalPrompt: string): string =
  ## Generate a retry prompt that includes specific error feedback.
  ## Tells the LLM exactly what went wrong so it can self-correct.
  "Your previous response could not be parsed: " & errorReason & "\n\n" &
  "Please respond with ONLY the valid output expression. " &
  "No markdown fences, no explanation, no prose.\n\n" &
  "Original request:\n" & originalPrompt

{.pop.}
