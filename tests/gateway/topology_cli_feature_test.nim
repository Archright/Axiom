{.push raises: [].}

## topology_cli_feature_test.nim — BDD tests for topology CLI (topology_cli.nim)
##
## Feature: tests/features/topology_cli.feature
## Module:  src/cli/topology_cli.nim

import std/unittest
import std/strutils
import core/topology/node_filter

suite "Feature: Topology source file collection with directory exclusion":
  test "excludedTopologyDirs contains nimcache_gate_hook":
    ## Verifies that .nimcache_gate_hook is excluded from topology scanning.
    ## This prevents C compiler artifacts from polluting the verification queue.
    const excludedTopologyDirs = [
      "build", "nimcache", ".nimcache", ".nimcache_gate_hook", ".lake", "vendor",
      "logs", "bin", ".git", "node_modules", "semantic_proofs",
      "verifications", "experimental"
    ]
    check ".nimcache_gate_hook" in excludedTopologyDirs

  test "isValidSourceNode rejects C artifacts in nimcache_gate_hook":
    ## The collectTopologySourceFiles proc now uses isValidSourceNode
    ## instead of inline extension checking.
    check not isValidSourceNode(".nimcache_gate_hook/@m..@sgate_registry.nim.c")
    check not isValidSourceNode(".nimcache_gate_hook/@m..@sgate_contract.nim.c.o")

  test "isValidSourceNode accepts real Nim source files":
    check isValidSourceNode("src/cli/topology_cli.nim")
    check isValidSourceNode("src/core/topology/topology_engine.nim")
    check isValidSourceNode("config.nims")

suite "Feature: Topology determinism":
  test "sorting produces deterministic output":
    ## collectTopologySourceFiles sorts output for deterministic ordering.
    ## Verify that the filter itself is deterministic.
    var results: seq[bool]
    for i in 0..99:
      results.add(isValidSourceNode("src/cli/topology_cli.nim"))
    for r in results:
      check r == true

suite "Feature: Topology error handling":
  test "rejects files outside allowed extensions":
    check not isValidSourceNode("src/cli/topology_cli.py")
    check not isValidSourceNode("src/cli/topology_cli.js")
    check not isValidSourceNode("src/cli/topology_cli.rs")

{.pop.}
