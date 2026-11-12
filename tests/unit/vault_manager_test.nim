import std/unittest
import std/json
import std/strutils
import core/vault/vault_manager_spec
import core/results

suite "sanitizeVaultToken contract":
  test "replaces special chars with underscore":
    check sanitizeVaultToken("../etc/passwd") == "___etc_passwd"

  test "replaces slashes with underscore":
    check sanitizeVaultToken("a/b/c") == "a_b_c"

  test "preserves alphanumeric":
    check sanitizeVaultToken("abc123") == "abc123"

suite "axiomSpecFileName contract":
  test "includes sanitized module and function name":
    let spec = initAxiomSpec("src/mod.nim", "withdraw", "abc123", "")
    let fname = axiomSpecFileName(spec)
    check fname.contains("withdraw")
    check fname.endswith(".json")

  test "ignores smtlib2 content in file name":
    let spec1 = initAxiomSpec("src/mod.nim", "withdraw", "abc123", "placeholder")
    let spec2 = initAxiomSpec("src/mod.nim", "withdraw", "abc123", "(assert true)")
    check axiomSpecFileName(spec1) == axiomSpecFileName(spec2)

suite "axiomSpecToJsonNode contract":
  test "serializes function name":
    let spec = initAxiomSpec("mod.nim", "transfer", "", "")
    let node = axiomSpecToJsonNode(spec)
    check node["functionName"].getStr() == "transfer"

  test "serializes fingerprint":
    let spec = initAxiomSpec("mod.nim", "foo", "hash789", "")
    let node = axiomSpecToJsonNode(spec)
    check node["fingerprint"].getStr() == "hash789"

suite "parseAxiomSpec contract":
  test "rejects missing functionName":
    let node = %*{ "fingerprint": "abc" }
    let result = parseAxiomSpec(node)
    check result.isErr()
