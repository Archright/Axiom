import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [ValueError, IOError, OSError].}

import core/json/std_redirect
import core/pure/json_parse
import core/trusted/monad
import std/json except parseJson
# axiomIoBoundary

## Trusted JSON — wraps std/json, return value must be AxiomSafe[T].
## This guarantees at compile time that JSON parse results have passed the gateway.

## Parse JSON string and return verified JsonNode.
func parseTrustedJson*(raw: string): AxiomSafe[JsonNode] {.raises: [ValueError, IOError, OSError].} =
  let node = pureParseJson(raw)
  seal(node)

## Serialize AxiomSafe[JsonNode] to JSON string.
func serializeTrustedJson*(safe: AxiomSafe[JsonNode]): string {.inline.} =
  $unsafeReveal(safe)

## Typed accessor that can verify required field existence at compile time.
## (Extensible via macro in the future)
func getTrustedField*(safe: AxiomSafe[JsonNode]; field: string): AxiomSafe[JsonNode] {.raises: [KeyError].} =
  let node = unsafeReveal(safe)
  if not node.hasKey(field):
    raise newException(KeyError, "Missing field: " & field)
  seal(node[field])
{.pop.}
