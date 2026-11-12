{.push raises: [].}

## node_filter_feature_test.nim — BDD tests for DiscoveryPolicy (node_filter.nim)
##
## Feature: tests/features/node_filter.feature
## Module:  src/core/topology/node_filter.nim

import std/unittest
import core/topology/node_filter

suite "Feature: DiscoveryPolicy extension filtering":
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

  test "rejects file with empty extension":
    check not isValidSourceNode("Makefile")

suite "Feature: DiscoveryPolicy path exclusion":
  test "rejects .c file in nimcache_gate_hook":
    check not isValidSourceNode(".nimcache_gate_hook/@m..@sgate_registry.nim.c")

  test "rejects .nim file in vendor directory":
    check not isValidSourceNode("vendor/z3/lib.nim")

  test "rejects .nim file in .git directory":
    check not isValidSourceNode(".git/hooks/pre-commit.nim")

  test "rejects .nim file in build directory":
    check not isValidSourceNode("build/nimcache_check/file.nim")

suite "Feature: DiscoveryPolicy determinism":
  test "same input always gives same output (100 iterations)":
    for i in 0..99:
      check isValidSourceNode("src/core/engine.nim")
      check not isValidSourceNode(".nimcache_gate_hook/file.c")

suite "Feature: DiscoveryPolicy custom policy":
  test "custom policy with different extensions":
    let customPolicy = DiscoveryPolicy(
      includeExtensions: @[".rs", ".go"],
      excludePaths: @["target", "vendor"]
    )
    check isValidSourceNode("src/main.rs", customPolicy)
    check not isValidSourceNode("src/main.nim", customPolicy)

{.pop.}
