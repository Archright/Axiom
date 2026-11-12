import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Zero-Catch JSON parsing wrapper.
##
## All parseJson exceptions are quarantined here.
## Callers receive Result; no try/except needed at call sites.

import std/json except parseJson
import core/pure/json_parse
import core/types/results
import core/trusted/axiom_pragmas

# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert ast_parse_failed_isolated)"
proc safeParseJson*(raw: string): Result[JsonNode, string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Parse JSON string into JsonNode, returning Result instead of raising.
  try:
    ok(pureParseJson(raw))
  except CatchableError:
    err("JSON parse failed: " & getCurrentExceptionMsg())

proc safeParseJsonFile*(path: string): Result[JsonNode, string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read file and parse JSON, returning Result instead of raising.
  let raw = try: readFile(path) except CatchableError: ""
  if raw.len == 0:
    return err("Failed to read or empty file: " & path)
  safeParseJson(raw)

{.pop.}
