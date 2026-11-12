import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import std/json except parseJson
import core/pure/json_parse
import core/trusted/axiom_pragmas

proc safeParseJson*(input: string): JsonNode {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Parse JSON string safely; return empty JObject on failure.
  try:
    result = pureParseJson(input)
  except CatchableError:
    result = newJObject()

{.pop.}
