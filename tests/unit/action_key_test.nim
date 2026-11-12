{.push raises: [CatchableError].}

## Action Key Unit Tests
## Verifies deterministic hashing of all action-affecting aspects (Bazel model).

import std/[strutils, tables, unittest]
import gate/action_key

suite "ActionKey":
  test "computeActionKey is deterministic for identical inputs":
    let inputs = {"src/a.nim": "hash_a", "src/b.nim": "hash_b"}.toTable
    let env = @[("CC", "gcc-13"), ("CFLAGS", "-O2")]
    let k1 = computeActionKey(inputs, "path_manifest_v1", 1700000000, "nim c -d:release", env)
    let k2 = computeActionKey(inputs, "path_manifest_v1", 1700000000, "nim c -d:release", env)
    check string(k1) == string(k2)

  test "different input hashes produce different keys":
    let inputs1 = {"src/main.nim": "hash_v1"}.toTable
    let inputs2 = {"src/main.nim": "hash_v2"}.toTable
    let env = @[("CC", "gcc")]
    let k1 = computeActionKey(inputs1, "", 100, "nim c", env)
    let k2 = computeActionKey(inputs2, "", 100, "nim c", env)
    check string(k1) != string(k2)

  test "different commands produce different keys":
    let inputs = {"src/main.nim": "h1"}.toTable
    let env = @[("CC", "gcc")]
    let k1 = computeActionKey(inputs, "", 100, "nim c -d:release", env)
    let k2 = computeActionKey(inputs, "", 100, "nim c -d:debug", env)
    check string(k1) != string(k2)

  test "different sourceDateEpoch produces different keys":
    let inputs = {"src/main.nim": "h1"}.toTable
    let env = @[("CC", "gcc")]
    let k1 = computeActionKey(inputs, "", 100, "nim c", env)
    let k2 = computeActionKey(inputs, "", 200, "nim c", env)
    check string(k1) != string(k2)

  test "different pathManifestHash produces different keys":
    let inputs = {"src/main.nim": "h1"}.toTable
    let env = @[("CC", "gcc")]
    let k1 = computeActionKey(inputs, "toolchain_v1", 100, "nim c", env)
    let k2 = computeActionKey(inputs, "toolchain_v2", 100, "nim c", env)
    check string(k1) != string(k2)

  test "input path order does not affect key (sorted internally)":
    let inputs1 = {"b.nim": "hb", "a.nim": "ha"}.toTable
    let inputs2 = {"a.nim": "ha", "b.nim": "hb"}.toTable
    let env = @[("CC", "gcc")]
    let k1 = computeActionKey(inputs1, "", 100, "cmd", env)
    let k2 = computeActionKey(inputs2, "", 100, "cmd", env)
    check string(k1) == string(k2)

  test "shortKey truncates to requested length":
    let inputs = {"f.nim": "h"}.toTable
    let k = computeActionKey(inputs, "", 0, "cmd", @[])
    let shortened = shortKey(k, 8)
    check shortened.len == 8
    check string(k).startsWith(shortened)

  test "shortKey returns full key when len exceeds key length":
    let inputs = {"f.nim": "h"}.toTable
    let k = computeActionKey(inputs, "", 0, "cmd", @[])
    let shortened = shortKey(k, 256)
    check shortened == string(k)

  test "empty inputs still produces a valid hash key":
    let k = computeActionKey(initTable[string, string](), "", 0, "", @[])
    check string(k).len > 0
    # SHA-256 produces a 64-char hex string
    check string(k).len == 64

  test "computeHash returns consistent SHA-256 hex":
    let h1 = computeHash("hello world")
    let h2 = computeHash("hello world")
    check h1 == h2
    check h1.len == 64
    # Known SHA-256 of "hello world"
    check h1 == "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"

  test "computeActionKeyFromManifest is deterministic":
    let k1 = computeActionKeyFromManifest(
      @["src/main.nim", "src/lib.nim"],
      @["build/main"],
      "nim c",
      @[("CC", "gcc")],
      "toolchain_v1",
      1700000000
    )
    let k2 = computeActionKeyFromManifest(
      @["src/main.nim", "src/lib.nim"],
      @["build/main"],
      "nim c",
      @[("CC", "gcc")],
      "toolchain_v1",
      1700000000
    )
    check string(k1) == string(k2)

  test "computeActionKeyFromManifest differs from computeActionKey":
    let inputs = {"src/main.nim": "h1"}.toTable
    let manifestK = computeActionKeyFromManifest(
      @["src/main.nim"], @["build/main"],
      "nim c", @[], "", 0
    )
    let fullK = computeActionKey(
      inputs, "", 0, "nim c", @[]
    )
    check string(manifestK) != string(fullK)
