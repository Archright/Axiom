{.push raises: [].}

## Tests for DiscoveryPolicy — source file filtering for topology scanning.

import std/unittest
import core/topology/node_filter

suite "DiscoveryPolicy - extension filtering":
  test "accepts .nim source file in src/":
    check isValidSourceNode("src/cli/axiom_engine.nim")

  test "accepts .nims config file":
    check isValidSourceNode("config.nims")

  test "rejects .c file (not Nim source)":
    check not isValidSourceNode("some/path/file.c")

  test "rejects .c.o object file":
    check not isValidSourceNode("some/path/file.c.o")

  test "rejects .py file (language ban)":
    check not isValidSourceNode("scripts/helper.py")

  test "rejects .js file":
    check not isValidSourceNode("frontend/app.js")

  test "rejects file with empty extension":
    check not isValidSourceNode("Makefile")

  test "rejects file with no extension":
    check not isValidSourceNode("LICENSE")

suite "DiscoveryPolicy - path exclusion":
  test "rejects .c file in nimcache_gate_hook":
    check not isValidSourceNode(".nimcache_gate_hook/@m..@sgate_registry.nim.c")

  test "rejects .c file in nimcache directory":
    check not isValidSourceNode("nimcache/file.c")

  test "rejects .c file in .nimcache directory":
    check not isValidSourceNode(".nimcache/file.c")

  test "rejects .c file in build directory":
    check not isValidSourceNode("build/nimcache_check/file.c")

  test "rejects .nim file in vendor directory":
    check not isValidSourceNode("vendor/z3/lib.nim")

  test "rejects .nim file in .lake directory":
    check not isValidSourceNode(".lake/packages/something.nim")

  test "rejects .nim file in .git directory":
    check not isValidSourceNode(".git/hooks/pre-commit.nim")

  test "rejects .nim file in logs directory":
    check not isValidSourceNode("logs/evidence/proof.nim")

  test "rejects .nim file in bin directory":
    check not isValidSourceNode("bin/some_binary.nim")

  test "rejects .nim file in node_modules directory":
    check not isValidSourceNode("node_modules/package/index.nim")

  test "rejects .nim file in semantic_proofs directory":
    check not isValidSourceNode("semantic_proofs/proof.nim")

  test "rejects .nim file in experimental directory":
    check not isValidSourceNode("experimental/test.nim")

suite "DiscoveryPolicy - determinism":
  test "same input always gives same output (100 iterations)":
    for i in 0..99:
      check isValidSourceNode("src/core/engine.nim")
      check not isValidSourceNode(".nimcache_gate_hook/file.c")

  test "case-insensitive extension matching":
    check isValidSourceNode("src/core/engine.NIM")
    check not isValidSourceNode("src/core/engine.CPP")

suite "DiscoveryPolicy - custom policy":
  test "custom policy with different extensions":
    let customPolicy = DiscoveryPolicy(
      includeExtensions: @[".rs", ".go"],
      excludePaths: @["target", "vendor"]
    )
    check isValidSourceNode("src/main.rs", customPolicy)
    check isValidSourceNode("cmd/app.go", customPolicy)
    check not isValidSourceNode("src/main.nim", customPolicy)
    check not isValidSourceNode("vendor/lib.rs", customPolicy)

  test "custom policy with empty exclusions":
    let openPolicy = DiscoveryPolicy(
      includeExtensions: @[".nim"],
      excludePaths: @[]
    )
    check isValidSourceNode("vendor/z3/lib.nim", openPolicy)
    check isValidSourceNode("build/output.nim", openPolicy)
