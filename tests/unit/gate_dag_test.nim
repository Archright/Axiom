## gate_dag_test.nim
## Business scenario tests for gate/gate_dag.nim — the dependency-aware
## scheduling system for L2 functional gates.
##
## gate_dag.nim is critical infrastructure used by orchestrator_hook_part2.nim
## (#1 hotspot, 38 changes). The DAG determines which gates execute in parallel,
## which execute sequentially, and which are skipped when upstream gates fail.
## Tests cover: DAG construction, topological ordering, affected gate discovery,
## failure propagation, and pattern-based matching.

import std/[unittest, strutils, tables, sets]
import gate/gate_dag
import gate/gate_contract

# ══════════════════════════════════════════════════════════════════════════════
# Business Scenario: DAG Construction from Gate Manifest
# The orchestrator builds a dependency graph from GateConfig.after fields
# declared in gate_manifest.json. Wrong construction = incorrect scheduling.
# ══════════════════════════════════════════════════════════════════════════════

suite "buildGateDag: dependency graph construction":
  test "no dependencies produces flat graph":
    let gates = @[
      GateConfig(id: "a"),
      GateConfig(id: "b"),
      GateConfig(id: "c")
    ]
    let dag = buildGateDag(gates)
    # All gates should have in-degree 0
    check dag.inDegree["a"] == 0
    check dag.inDegree["b"] == 0
    check dag.inDegree["c"] == 0

  test "linear chain creates correct in-degrees":
    let gates = @[
      GateConfig(id: "a"),
      GateConfig(id: "b", after: @["a"]),
      GateConfig(id: "c", after: @["b"])
    ]
    let dag = buildGateDag(gates)
    check dag.inDegree["a"] == 0
    check dag.inDegree["b"] == 1
    check dag.inDegree["c"] == 1

  test "diamond dependency":
    let gates = @[
      GateConfig(id: "a"),
      GateConfig(id: "b", after: @["a"]),
      GateConfig(id: "c", after: @["a"]),
      GateConfig(id: "d", after: @["b", "c"])
    ]
    let dag = buildGateDag(gates)
    check dag.inDegree["a"] == 0
    check dag.inDegree["b"] == 1
    check dag.inDegree["c"] == 1
    check dag.inDegree["d"] == 2
    # adjacency: a -> [b, c], b -> [d], c -> [d]
    check "b" in dag.adjacency["a"]
    check "c" in dag.adjacency["a"]
    check "d" in dag.adjacency["b"]
    check "d" in dag.adjacency["c"]

  test "external dependency reference is ignored (not in gate set)":
    let gates = @[
      GateConfig(id: "b", after: @["nonexistent"])
    ]
    let dag = buildGateDag(gates)
    check dag.inDegree["b"] == 0  # external ref ignored

  test "empty gate list produces empty DAG":
    let dag = buildGateDag(@[])
    check dag.adjacency.len == 0
    check dag.inDegree.len == 0

# ══════════════════════════════════════════════════════════════════════════════
# Business Scenario: Topological Layer Ordering
# Kahn's algorithm groups gates into layers. Gates in the same layer
# can run in parallel. Layers execute sequentially.
# ══════════════════════════════════════════════════════════════════════════════

suite "topologicalLayers: parallel execution groups":
  test "no dependencies → all gates in layer 0":
    let gates = @[
      GateConfig(id: "a"),
      GateConfig(id: "b"),
      GateConfig(id: "c")
    ]
    let dag = buildGateDag(gates)
    let layers = dag.topologicalLayers()
    check layers.len == 1
    check layers[0].len == 3

  test "linear chain produces sequential layers":
    let gates = @[
      GateConfig(id: "a"),
      GateConfig(id: "b", after: @["a"]),
      GateConfig(id: "c", after: @["b"])
    ]
    let dag = buildGateDag(gates)
    let layers = dag.topologicalLayers()
    check layers.len == 3
    check layers[0] == @["a"]
    check layers[1] == @["b"]
    check layers[2] == @["c"]

  test "diamond: b and c in same layer after a":
    let gates = @[
      GateConfig(id: "a"),
      GateConfig(id: "b", after: @["a"]),
      GateConfig(id: "c", after: @["a"]),
      GateConfig(id: "d", after: @["b", "c"])
    ]
    let dag = buildGateDag(gates)
    let layers = dag.topologicalLayers()
    check layers.len == 3
    check layers[0] == @["a"]
    # b and c can be in either order within the layer
    check layers[1].len == 2
    check "b" in layers[1]
    check "c" in layers[1]
    check layers[2] == @["d"]

  test "parallel independent gates in single layer":
    let gates = @[
      GateConfig(id: "x"),
      GateConfig(id: "y"),
      GateConfig(id: "z")
    ]
    let dag = buildGateDag(gates)
    let layers = dag.topologicalLayers()
    check layers.len == 1
    check layers[0].len == 3

# ══════════════════════════════════════════════════════════════════════════════
# Business Scenario: Affected Gate Discovery
# Only gates whose filesPattern matches changed files should execute.
# Plus transitive dependents through after edges.
# ══════════════════════════════════════════════════════════════════════════════

suite "matchesFilesPattern: pattern matching":
  test "empty pattern always matches":
    let gate = GateConfig(id: "catch-all", filesPattern: "")
    check gate.matchesFilesPattern(@["any/file.nim"])

  test "matching pattern triggers gate":
    let gate = GateConfig(id: "core-gate", filesPattern: "src/core")
    check gate.matchesFilesPattern(@["src/core/types.nim"])
    check not gate.matchesFilesPattern(@["src/cli/main.nim"])

  test "pipe-separated pattern matches any component":
    let gate = GateConfig(id: "multi", filesPattern: "src/core|src/gate")
    check gate.matchesFilesPattern(@["src/core/types.nim"])
    check gate.matchesFilesPattern(@["src/gate/gate_memo.nim"])
    check not gate.matchesFilesPattern(@["tests/unit/x_test.nim"])

  test "no changed files means no match":
    let gate = GateConfig(id: "g", filesPattern: "src/core")
    check not gate.matchesFilesPattern(@[])

suite "findAffectedGates: transitive propagation":
  test "directly affected gate is found":
    let gates = @[
      GateConfig(id: "a", filesPattern: "src/core"),
      GateConfig(id: "b", filesPattern: "src/cli")
    ]
    let dag = buildGateDag(gates)
    let affected = dag.findAffectedGates(@["src/core/types.nim"], gates)
    check "a" in affected
    check "b" notin affected

  test "dependent of affected gate is also affected (transitive)":
    let gates = @[
      GateConfig(id: "a", filesPattern: "src/core"),
      GateConfig(id: "b", after: @["a"], filesPattern: "src/cli")
    ]
    let dag = buildGateDag(gates)
    let affected = dag.findAffectedGates(@["src/core/types.nim"], gates)
    check "a" in affected
    check "b" in affected  # transitive: b depends on a

  test "non-dependent of affected gate is not affected":
    let gates = @[
      GateConfig(id: "a", filesPattern: "src/core"),
      GateConfig(id: "b", filesPattern: "src/cli")  # no dependency on a
    ]
    let dag = buildGateDag(gates)
    let affected = dag.findAffectedGates(@["src/core/types.nim"], gates)
    check "a" in affected
    check "b" notin affected

  test "multi-level transitive propagation":
    let gates = @[
      GateConfig(id: "a", filesPattern: "src/core"),
      GateConfig(id: "b", after: @["a"]),
      GateConfig(id: "c", after: @["b"])
    ]
    let dag = buildGateDag(gates)
    let affected = dag.findAffectedGates(@["src/core/types.nim"], gates)
    check "a" in affected
    check "b" in affected
    check "c" in affected

  test "empty changed files returns empty affected set":
    let gates = @[
      GateConfig(id: "a", filesPattern: "src/core")
    ]
    let dag = buildGateDag(gates)
    let affected = dag.findAffectedGates(@[], gates)
    check affected.len == 0

# ══════════════════════════════════════════════════════════════════════════════
# Business Scenario: Failure Propagation
# When a gate fails, all downstream dependents must be skipped.
# Wrong propagation = cascading failures or unnecessary re-runs.
# ══════════════════════════════════════════════════════════════════════════════

suite "propagateFailures: cascading skip":
  test "single failure propagates to direct dependents":
    let gates = @[
      GateConfig(id: "a"),
      GateConfig(id: "b", after: @["a"]),
      GateConfig(id: "c", after: @["a"])
    ]
    let dag = buildGateDag(gates)
    var failed = initHashSet[string]()
    failed.incl("a")
    let skipped = dag.propagateFailures(failed)
    check "a" in skipped  # failed gate itself
    check "b" in skipped  # dependent of a
    check "c" in skipped  # dependent of a

  test "failure in middle of chain propagates forward":
    let gates = @[
      GateConfig(id: "a"),
      GateConfig(id: "b", after: @["a"]),
      GateConfig(id: "c", after: @["b"])
    ]
    let dag = buildGateDag(gates)
    var failed = initHashSet[string]()
    failed.incl("b")
    let skipped = dag.propagateFailures(failed)
    check "b" in skipped
    check "c" in skipped  # dependent of b
    check "a" notin skipped  # a is upstream, not affected

  test "diamond failure propagates to all downstream":
    let gates = @[
      GateConfig(id: "a"),
      GateConfig(id: "b", after: @["a"]),
      GateConfig(id: "c", after: @["a"]),
      GateConfig(id: "d", after: @["b", "c"])
    ]
    let dag = buildGateDag(gates)
    var failed = initHashSet[string]()
    failed.incl("a")
    let skipped = dag.propagateFailures(failed)
    check skipped.len == 4  # all gates affected

  test "no failures means no skips":
    let gates = @[
      GateConfig(id: "a"),
      GateConfig(id: "b", after: @["a"])
    ]
    let dag = buildGateDag(gates)
    var failed = initHashSet[string]()
    let skipped = dag.propagateFailures(failed)
    check skipped.len == 0

# ══════════════════════════════════════════════════════════════════════════════
# Business Scenario: Tier Filtering
# Gates are partitioned by execution tier: tier 1 runs immediately,
# tier 2 is deferred to post-commit.
# ══════════════════════════════════════════════════════════════════════════════

suite "gatesInTier: tier partitioning":
  test "filter tier 1 gates":
    let gates = @[
      GateConfig(id: "fast", tier: 1),
      GateConfig(id: "slow", tier: 2),
      GateConfig(id: "quick", tier: 1)
    ]
    let tier1 = gates.gatesInTier(1)
    check tier1.len == 2
    check tier1[0].id == "fast"
    check tier1[1].id == "quick"

  test "filter tier 2 gates":
    let gates = @[
      GateConfig(id: "fast", tier: 1),
      GateConfig(id: "slow", tier: 2)
    ]
    let tier2 = gates.gatesInTier(2)
    check tier2.len == 1
    check tier2[0].id == "slow"

  test "no gates in tier returns empty":
    let gates = @[GateConfig(id: "g", tier: 1)]
    check gates.gatesInTier(2).len == 0

# ══════════════════════════════════════════════════════════════════════════════
# Business Scenario: File-to-Module Conversion
# Changed file paths must be converted to module names for import graph
# lookup. Wrong conversion = missed affected gates.
# ══════════════════════════════════════════════════════════════════════════════

suite "fileToModule: path normalization":
  test "core path strips src/core/ prefix and .nim":
    check fileToModule("src/core/types/domain_types.nim") == "types/domain_types"

  test "src/ prefix is stripped for non-core paths":
    check fileToModule("src/cli/axiom_engine.nim") == "cli/axiom_engine"

  test "src/core/ path strips both src/ and core/ prefixes":
    check fileToModule("src/core/hashes.nim") == "hashes"

  test "path without src/ prefix has only .nim removed":
    check fileToModule("standalone.nim") == "standalone"

# ══════════════════════════════════════════════════════════════════════════════
# Business Scenario: Critical Path Analysis (Phase 2.1 Eager Scheduling)
# The critical path determines which gate to schedule first.
# Higher cp = gate is on the longest execution chain = start ASAP.
# ══════════════════════════════════════════════════════════════════════════════

suite "computeCriticalPath: scheduling priority":
  test "flat graph: each gate's cp equals its own weight":
    let gates = @[
      GateConfig(id: "a", weight: gwLight),
      GateConfig(id: "b", weight: gwHeavy),
      GateConfig(id: "c", weight: gwMedium),
    ]
    let dag = buildGateDag(gates)
    let cp = dag.computeCriticalPath(gates)
    check cp["a"] == gwLight.int
    check cp["b"] == gwHeavy.int
    check cp["c"] == gwMedium.int

  test "linear chain: source gate has sum of all downstream weights":
    let gates = @[
      GateConfig(id: "a", weight: gwHeavy),   # cp = 4 + 2 + 1 = 7
      GateConfig(id: "b", weight: gwMedium, after: @["a"]),  # cp = 2 + 1 = 3
      GateConfig(id: "c", weight: gwLight, after: @["b"]),   # cp = 1
    ]
    let dag = buildGateDag(gates)
    let cp = dag.computeCriticalPath(gates)
    check cp["c"] == 1
    check cp["b"] == 3   # 2 + 1
    check cp["a"] == 7   # 4 + 2 + 1

  test "diamond: heavier branch wins critical path":
    let gates = @[
      GateConfig(id: "a", weight: gwLight),                    # source
      GateConfig(id: "b", weight: gwHeavy, after: @["a"]),     # heavy branch
      GateConfig(id: "c", weight: gwLight, after: @["a"]),     # light branch
      GateConfig(id: "d", weight: gwMedium, after: @["b", "c"]), # converges
    ]
    let dag = buildGateDag(gates)
    let cp = dag.computeCriticalPath(gates)
    # d is sink: cp[d] = 2
    check cp["d"] == gwMedium.int
    # b has heavier downstream (d): cp[b] = 4 + 2 = 6
    check cp["b"] == gwHeavy.int + gwMedium.int
    # c has lighter downstream: cp[c] = 1 + 2 = 3
    check cp["c"] == gwLight.int + gwMedium.int
    # a takes max(b_cp, c_cp) = max(6, 3) = 6; cp[a] = 1 + 6 = 7
    check cp["a"] == gwLight.int + gwHeavy.int + gwMedium.int

  test "empty graph returns empty table":
    let dag = buildGateDag(@[])
    let cp = dag.computeCriticalPath(@[])
    check cp.len == 0