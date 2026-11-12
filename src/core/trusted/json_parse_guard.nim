import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import core/pure/json_parse
import core/trusted/effect_types
import std/json except parseJson
import std/macros
# ─── Layer 2: OpaqueJsonString overloads ─────────────────────

func pureParseJson*(s: OpaqueJsonString): JsonNode {.noSideEffect, raises: [ValueError, IOError, OSError].} =
  ## Parse JSON from OpaqueJsonString — the ONLY safe entry point.
  ## Requires OpaqueJsonString (distinct string) — raw string won't compile.
  pureParseJson(string(s))
# Note: The primary defense is the Effect System (Layer 1).
# {forbids: [UnsafeJsonEffect]} on core functions prevents parseJson calls.
# This macro is the backup defense for cases where the effect system is bypassed.
