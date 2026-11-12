import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Zero-Catch redirect: forces all parseJson callers to use safeParseJson.
##
## Import this module INSTEAD of std/json to get compile-time enforcement.

import std/json except parseJson
export json except parseJson

import core/json/json_safe
export json_safe.safeParseJson

# Symbol Hijacking: proc with {.error.} fires at CALL time, not definition time.
# This means the module compiles fine, but consumers get a compile-time error
# when they try to call parseJson(). Unlike templates, this avoids ambiguity
# with json_utils.nim's internal parseJson calls (different module scope).
func parseJson*(s: string): JsonNode {.error: "Axiom Zero-Catch Policy: Use parseJsonOpt(raw) or readJsonFile(path) from core/json_utils.".}

{.pop.}
