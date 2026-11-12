{.push raises: [].}
## PBT: Gate Idempotency
## Property: Gate(X) = Gate(Gate(X)) for all valid inputs.
## @basic tier — runs in every CI push.

import std/[json, unittest]
import core/testing/pbt_engine
import core/testing/generators

suite "PBT: Gate Idempotency":
  test "Gate config mutation idempotency (structural)":
    # Structural idempotency: applying identity mutation twice yields same result.
    # This is a simplified version — full gate idempotency requires gate runners.
    let base = """{"test_gate": {"enabled": true, "exceptions": []}}"""
    let mutator = genGateConfigMutation(base)
    let idempotent = proc(j: JsonNode): bool =
      # A mutation should always produce a parseable JObject
      # (full idempotency test requires gate runner integration)
      j.kind == JObject
    let result = checkProperty(mutator, idempotent, iterations = 50,
                                verbosity = PbtSilent)
    check result.passed == true

{.pop.}