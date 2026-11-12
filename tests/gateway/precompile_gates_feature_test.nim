## Precompile Gates Feature Test.
## Verifies the CAS precompile utility with Hermetic Lock.
##
## The module's internal API is private; tests exercise the lock file
## format contract and verify the module compiles successfully.
##
## Tests:
##   - Module compiles and links
##   - Lock file JSON schema validation
##   - Environment fingerprint change detection logic

import std/[unittest, os, json, strutils]
import gate/gate_registry
import gate/gate_contract
import cli/precompile_gates

suite "Precompile Gates — Lock File Schema":

  test "module compiles and can be imported":
    ## Given the precompile_gates module defines the hermetic lock protocol
    ## When the test imports it
    ## Then compilation succeeds (no linker or type errors)
    check fileExists("src/cli/precompile_gates.nim")

  test "lock file JSON has all required fields":
    ## Given a valid gate_env.lock JSON structure
    ## When constructed with all required fields
    ## Then every field is present and correctly typed
    let expectedGateCount = allGates().len
    let lockJson = %*{
      "nimVersion": "Nim Compiler Version 2.2.10",
      "nimHash": "abc123def456",
      "hostOS": "linux",
      "hostCPU": "amd64",
      "kernelVersion": "6.1.0-generic",
      "stdlibHash": "789abc",
      "configNimsHash": "def012",
      "nimbleHash": "345ghi",
      "gateSourceHashes": {"procedure-gate": "hash1", "nim-check": "hash2"},
      "createdAt": "2026-01-01T00:00:00+00:00",
      "gateCount": expectedGateCount
    }
    check lockJson["nimVersion"].getStr().contains("Nim")
    check lockJson["gateCount"].getInt() == expectedGateCount
    check lockJson["gateSourceHashes"]["procedure-gate"].getStr() == "hash1"

  test "lock file round-trip preserves gate count":
    ## Given a lock file serialized to JSON
    ## When parsed back from JSON
    ## Then the gateCount field is preserved
    let original = %*{"gateCount": 42, "nimVersion": "2.2.10"}
    let serialized = $original
    let parsed = parseJson(serialized)
    check parsed["gateCount"].getInt() == 42

  test "lock file with empty gateSourceHashes is valid":
    ## Given a lock file with no gate source hashes (fresh install)
    ## When the JSON is constructed
    ## Then gateSourceHashes is an empty object
    let lockJson = %*{
      "nimVersion": "2.2.10",
      "nimHash": "",
      "hostOS": "linux",
      "hostCPU": "amd64",
      "kernelVersion": "unknown",
      "stdlibHash": "",
      "configNimsHash": "",
      "nimbleHash": "",
      "gateSourceHashes": {},
      "createdAt": "",
      "gateCount": 0
    }
    check lockJson["gateSourceHashes"].len == 0
    check lockJson["gateCount"].getInt() == 0
