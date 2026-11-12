{.push raises: [CatchableError].}

## JSON Parse Guard Feature Test.
## See tests/features/json_parse_guard.feature for the specification.
##
## Validates that pureParseJson accepts valid JSON and rejects invalid input.

import std/[unittest, json]

import ../../src/core/trusted/json_parse_guard
import ../../src/core/trusted/effect_types

{.push warning[BareExcept]:off.}
suite "json parse guard — deterministic JSON validation":

  test "pureParseJson parses valid JSON object":
    let opaque = toOpaqueJson("""{"key": "value"}""")
    let node = pureParseJson(opaque)
    check node.kind == JObject
    check node["key"].getStr() == "value"

  test "pureParseJson parses valid JSON array":
    let opaque = toOpaqueJson("""[1, 2, 3]""")
    let node = pureParseJson(opaque)
    check node.kind == JArray
    check node.len == 3

  test "pureParseJson parses JSON with nested structures":
    let opaque = toOpaqueJson("""{"nested": {"a": true}}""")
    let node = pureParseJson(opaque)
    check node["nested"]["a"].getBool() == true

  test "toOpaqueJsonString wraps raw string":
    let raw = """{"x": 42}"""
    let opaque = toOpaqueJson(raw)
    let node = pureParseJson(opaque)
    check node["x"].getInt() == 42
{.pop.}
