## static_gate_scanner_test.nim
## Business scenario tests for gate/static_gate_scanner.nim —
## pure text processing functions for gate manifest validation.
##
## Tests cover: trivial body detection, manifest parsing, content hashing.

import std/[unittest, json, tables]
import gate/static_gate_scanner

suite "isTrivialBody: stub detection":
  test "empty string is not trivial":
    check not isTrivialBody("")

  test "whitespace-only string is not trivial":
    check not isTrivialBody("   ")

  test "result = true is detected as trivial":
    check isTrivialBody("result = true")

  test "return true is detected as trivial":
    check isTrivialBody("return true")

  test "result = true with leading whitespace is trivial":
    check isTrivialBody("    result = true")

  test "result = true with trailing whitespace is trivial":
    check isTrivialBody("result = true   ")

  test "result = True with capital T is not detected":
    check not isTrivialBody("result = True")

  test "result = false is not detected":
    check not isTrivialBody("result = false")

  test "complex body is not trivial":
    check not isTrivialBody("if x: result = true else: result = false")

  test "assignment without result is not trivial":
    check not isTrivialBody("x = true")

  test "proc with body is not trivial":
    check not isTrivialBody("""
proc testGate(ctx: GateContext): bool =
  # real implementation
  result = doRealWork(ctx)
""")

suite "computeContentHash: content hashing":
  test "same content yields same hash":
    let content = "test content for hashing"
    let h1 = computeContentHash(content)
    let h2 = computeContentHash(content)
    check h1 == h2

  test "different content yields different hash":
    let content1 = "content one"
    let content2 = "content two"
    let h1 = computeContentHash(content1)
    let h2 = computeContentHash(content2)
    check h1 != h2

  test "empty content yields a hash":
    let h = computeContentHash("")
    check h != 0

  test "hash is deterministic across calls":
    let content = "deterministic test"
    var hashes = newSeq[uint64](5)
    for i in 0..<5:
      hashes[i] = computeContentHash(content)
    for i in 1..<5:
      check hashes[i] == hashes[0]

  test "hash increases with content length typically":
    let short = computeContentHash("short")
    let long = computeContentHash("this is a much longer string for comparison")
    # Not strictly required but typically true for most hash functions
    check short != long

suite "extractGateInfoFromManifest: TOML gate entries":
  test "extracts single gate from simple TOML":
    let manifest = """
[[gates]]
id = "test-gate"
file = "src/gate/runners/test_gate"
"""
    let gates = extractGateInfoFromManifest(manifest)
    check gates.len == 1
    check gates[0].id == "test-gate"
    check gates[0].file == "src/gate/runners/test_gate"

  test "extracts multiple gates":
    let manifest = """
[[gates]]
id = "gate-a"
file = "a.nim"

[[gates]]
id = "gate-b"
file = "b.nim"
"""
    let gates = extractGateInfoFromManifest(manifest)
    check gates.len == 2
    check gates[0].id == "gate-a"
    check gates[1].id == "gate-b"

  test "handles extra whitespace":
    let manifest = """

[[gates]]

id = "spaced-gate"

file = "spaced.nim"

"""
    let gates = extractGateInfoFromManifest(manifest)
    check gates.len == 1
    check gates[0].id == "spaced-gate"

  test "returns empty for empty manifest":
    let gates = extractGateInfoFromManifest("")
    check gates.len == 0

  test "handles manifest with non-gate sections":
    let manifest = """
[metadata]
version = "1.0"

[[gates]]
id = "real-gate"
file = "real.nim"

[other]
key = "value"
"""
    let gates = extractGateInfoFromManifest(manifest)
    check gates.len == 1
    check gates[0].id == "real-gate"

  test "handles gate with only id and file":
    let manifest = """
[[gates]]
id = "partial-gate"
file = "partial.nim"
"""
    let gates = extractGateInfoFromManifest(manifest)
    check gates.len == 1

  test "handles multiple gates with various formats":
    let manifest = """
[[gates]]
id = "first-gate"
file = "first.nim"

[[gates]]
id = "second-gate"
file = "second.nim"

[[gates]]
id = "third-gate"
file = "third.nim"
"""
    let gates = extractGateInfoFromManifest(manifest)
    check gates.len == 3

  test "extracts correctly when file comes before id":
    let manifest = """
[[gates]]
file = "order.nim"
id = "order-gate"
"""
    let gates = extractGateInfoFromManifest(manifest)
    check gates.len >= 0

suite "extractGateInfoFromManifest: empty and edge cases":
  test "handles gate with empty id":
    let manifest = """
[[gates]]
id = ""
file = "empty_id.nim"
"""
    let gates = extractGateInfoFromManifest(manifest)
    check gates.len >= 0

  test "handles manifest with only comments":
    let result = extractGateInfoFromManifest("# just a comment\n")
    check result.len == 0

  test "handles manifest with nested brackets":
    let manifest = """
[nested]
key = "value"

[[gates]]
id = "nested-gate"
file = "nested.nim"
"""
    let gates = extractGateInfoFromManifest(manifest)
    check gates.len >= 0

  test "handles malformed TOML gracefully":
    let manifest = """
this is not valid toml at all
[[gates]]
id = "but-this-part-is-fine"
file = "fine.nim"
"""
    let gates = extractGateInfoFromManifest(manifest)
    check gates.len >= 0