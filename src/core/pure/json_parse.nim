## [SEE: nim_effect_system_quirks.md §1.1, §8, §9.1]
## Pure wrapper for std/json.parseJson.
## Quirk: std/json.parseJson is `proc` (heap alloc + raises) but ORC makes
## heap alloc non-logical side effect. Also, stdlib's parseJson lacks proper
## raises annotation (§7 — raises IOError unlisted). This wrapper corrects
## both deficiencies so callers in src/core/ can be declared as `func`.
## Only src/core/ should import this module; other layers use stdlib directly.

import core/trusted/layer_declaration
axiomLayer "domain"
import std/json as stdJson
{.push raises: [].}
# axiomIoBoundary

func pureParseJson*(s: string): JsonNode {.noSideEffect, raises: [ValueError, IOError, OSError].} =
  ## Parse JSON string with noSideEffect guarantee.
  ## Safety: input is a string parameter (no external state mutation).
  ## Raises: ValueError on malformed JSON, IOError/OSError per stdlib quirk (§7).
  ## [SEE: nim_effect_system_quirks.md §9.1]
  {.cast(noSideEffect).}:
    result = stdJson.parseJson(s)

{.pop}
