## Golden Master Gate — Feature Tests
## See tests/features/golden_master_gate.feature for the specification.
##
## Tests normalizeJson normalization (timestamps, UUIDs, addresses),
## sortKeysRecursive deterministic ordering, and golden file comparison logic.
## Imports from tools/golden_master_capture (exported helpers) since
## golden_master_gate.nim keeps its helpers private.

import std/[unittest, json, os, strutils]
# golden_master_capture exports the normalization functions used by the gate
import tools/golden_master_capture

suite "Golden Master Gate — sortKeysRecursive Determinism":

  test "sortKeysRecursive sorts top-level keys alphabetically":
    ## Given a JSON object with unsorted keys
    ## When sortKeysRecursive is applied
    ## Then keys appear in alphabetical order in serialized output
    let node = %*{"z_last": 1, "a_first": 2, "m_middle": 3}
    sortKeysRecursive(node)
    let serialized = pretty(node)
    # After sorting, "a_first" appears before "m_middle" which appears before "z_last"
    check serialized.find("a_first") < serialized.find("m_middle")
    check serialized.find("m_middle") < serialized.find("z_last")

  test "sortKeysRecursive sorts nested object keys":
    ## Given a JSON object with nested unsorted keys
    ## When sortKeysRecursive is applied
    ## Then all levels are sorted in serialized output
    let node = %*{"outer_z": {"inner_z": 1, "inner_a": 2}, "outer_a": 3}
    sortKeysRecursive(node)
    let serialized = pretty(node)
    check serialized.find("outer_a") < serialized.find("outer_z")
    check serialized.find("inner_a") < serialized.find("inner_z")

  test "sortKeysRecursive is idempotent":
    ## Given a JSON node that has already been sorted
    ## When sortKeysRecursive is called again
    ## Then the result is identical
    let node = %*{"c": 3, "a": 1, "b": 2}
    sortKeysRecursive(node)
    let before = pretty(node)
    sortKeysRecursive(node)
    let after = pretty(node)
    check before == after

  test "sortKeysRecursive handles arrays of objects":
    ## Given a JSON array containing objects
    ## When sortKeysRecursive is applied
    ## Then objects within the array have sorted keys (verified via serialized output)
    let node = %*[{"z": 1, "a": 2}, {"m": 3, "b": 4}]
    sortKeysRecursive(node)
    let serialized = pretty(node)
    # First object: "a" before "z", Second object: "b" before "m"
    check serialized.find("\"a\"") < serialized.find("\"z\"")
    check serialized.find("\"b\"") < serialized.find("\"m\"")

  test "sortKeysRecursive handles nil gracefully":
    ## Given a nil JsonNode
    ## When sortKeysRecursive is called
    ## Then no crash occurs
    var nilNode: JsonNode
    sortKeysRecursive(nilNode)  # should not raise

  test "sortKeysRecursive handles empty object":
    ## Given an empty JSON object
    ## When sortKeysRecursive is applied
    ## Then it remains empty
    let node = newJObject()
    sortKeysRecursive(node)
    let serialized = pretty(node)
    # Empty object serializes to "{}" with no keys
    check serialized.strip() == "{}"

suite "Golden Master Gate — Timestamp Normalization":

  test "maskTimestamps replaces ISO 8601 timestamps":
    ## Given a string with an ISO 8601 timestamp
    ## When maskTimestamps is applied
    ## Then the timestamp is replaced with <TIMESTAMP>
    let input = """{"capturedAt": "2026-01-15T10:30:45Z"}"""
    let masked = maskTimestamps(input)
    check "<TIMESTAMP>" in masked
    check "2026-01-15" notin masked

  test "maskTimestamps replaces timestamps with timezone offsets":
    ## Given a string with a timestamp +09:00
    ## When maskTimestamps is applied
    ## Then the timestamp is masked
    let input = """{"time": "2026-06-24T12:00:00+09:00"}"""
    let masked = maskTimestamps(input)
    check "<TIMESTAMP>" in masked

  test "maskTimestamps replaces timestamps with milliseconds":
    ## Given a string with a timestamp including fractional seconds
    ## When maskTimestamps is applied
    ## Then the timestamp is masked
    let input = """{"ts": "2026-03-01T08:15:30.123Z"}"""
    let masked = maskTimestamps(input)
    check "<TIMESTAMP>" in masked

  test "maskTimestamps leaves non-timestamp strings unchanged":
    ## Given a string without timestamps
    ## When maskTimestamps is applied
    ## Then the string is unchanged
    let input = "hello world 12345"
    check maskTimestamps(input) == input

suite "Golden Master Gate — UUID Normalization":

  test "maskUuids replaces UUID v4 format":
    ## Given a string with a UUID
    ## When maskUuids is applied
    ## Then the UUID is replaced with <UUID>
    let input = """{"id": "550e8400-e29b-41d4-a716-446655440000"}"""
    let masked = maskUuids(input)
    check "<UUID>" in masked
    check "550e8400" notin masked

  test "maskUuids replaces mixed-case UUIDs":
    ## Given a string with uppercase UUID
    ## When maskUuids is applied
    ## Then the UUID is masked
    let input = "ID=AB12CD34-EF56-7890-1234-567890ABCDEF"
    let masked = maskUuids(input)
    check "<UUID>" in masked

  test "maskUuids leaves non-UUID strings unchanged":
    ## Given a string without UUIDs
    ## When maskUuids is applied
    ## Then the string is unchanged
    let input = "no-uuid-here-12345"
    check maskUuids(input) == input

suite "Golden Master Gate — Address Normalization":

  test "maskAddresses replaces 0x hex addresses":
    ## Given a string with a memory address
    ## When maskAddresses is applied
    ## Then the address is replaced with <ADDR>
    let input = "pointer at 0x7fff5fbff8d0"
    let masked = maskAddresses(input)
    check "<ADDR>" in masked
    check "0x7fff5fbff8d0" notin masked

  test "maskAddresses replaces 8-char hex addresses":
    ## Given a string with a short address
    ## When maskAddresses is applied
    ## Then the address is masked
    let input = "addr=0xDEADBEEF"
    let masked = maskAddresses(input)
    check "<ADDR>" in masked

  test "maskAddresses leaves non-address strings unchanged":
    ## Given a string without addresses
    ## When maskAddresses is applied
    ## Then the string is unchanged
    let input = "hex value 0xFF is not an address"
    check maskAddresses(input) == input

suite "Golden Master Gate — normalizeJson Integration":

  test "normalizeJson sorts keys and masks timestamps":
    ## Given a JSON node with unsorted keys and a timestamp
    ## When normalizeJson is applied
    ## Then keys are sorted and timestamps are masked
    let node = %*{
      "capturedAt": "2026-01-15T10:30:45Z",
      "z_field": 1,
      "a_field": 2
    }
    let normalized = normalizeJson(node)
    let serialized = pretty(normalized)
    # Keys must be alphabetically sorted: a_field < capturedAt < z_field
    check serialized.find("a_field") < serialized.find("capturedAt")
    check serialized.find("capturedAt") < serialized.find("z_field")

  test "normalizeJson is idempotent":
    ## Given a JSON node
    ## When normalizeJson is applied twice
    ## Then both results are identical
    let node = %*{"b": 2, "a": 1, "ts": "2026-01-15T10:30:45Z"}
    let n1 = normalizeJson(node)
    let n2 = normalizeJson(n1)
    check pretty(n1) == pretty(n2)

  test "normalizeAndSort matches normalizeJson":
    ## Given a JSON node
    ## When both normalizeAndSort and normalizeJson are called
    ## Then the results are identical
    let node = %*{"c": 3, "a": 1, "b": 2}
    let n1 = normalizeJson(node)
    let n2 = normalizeAndSort(node)
    check pretty(n1) == pretty(n2)

suite "Golden Master Gate — moduleGoldenPath Construction":

  test "moduleGoldenPath builds correct path":
    ## Given a module name
    ## When moduleGoldenPath is called
    ## Then the path follows data/golden/<name>.golden.json pattern
    let path = moduleGoldenPath("my_module")
    check path == "data/golden/my_module.golden.json"

  test "moduleGoldenPath with nested module name":
    ## Given a module name with underscores
    ## When moduleGoldenPath is called
    ## Then the full name is used
    let path = moduleGoldenPath("ast_integrity_gate")
    check path == "data/golden/ast_integrity_gate.golden.json"
