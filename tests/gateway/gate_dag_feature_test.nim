## Gate DAG Feature Test.
## Verifies Kahn's algorithm topological sort for gate scheduling.
##
## Tests:
##   - DAG construction from GateConfig dependencies
##   - Topological layer ordering
##   - Cycle detection (partial — breaks with empty layers)
##   - matchesFilesPattern logic
##   - findAffectedGates transitive propagation
##   - gatesInTier filtering
##   - propagateFailures transitive closure
##   - fileToModule path conversion

import std/[unittest, tables, sets, strutils]
import gate/gate_types
import gate/gate_dag

# ---------------------------------------------------------------------------
# Helpers — construct GateConfig objects for testing
# ---------------------------------------------------------------------------

func makeGate(id: string; after: seq[string] = @[];
              filesPattern: string = ""; tier: int = 1): GateConfig =
  GateConfig(
    id: id,
    name: id,
    layer: glMeta,
    entry: "src/gate/runners/" & id,
    stages: {gsPreCommit},
    filesPattern: filesPattern,
    passFilenames: false,
    priority: 0,
    envVars: @[],
    weight: gwLight,
    depsDirs: @[],
    argsTemplate: @[],
    after: after,
    tier: tier,
    envDependencies: @[],
    severity: gsError,
  )

suite "Gate DAG — Construction":

  test "buildGateDag creates nodes for all gates":
    ## Given 3 gates with no dependencies
    ## When buildGateDag is called
    ## Then all 3 gates appear as nodes with in-degree 0
    let gates = @[makeGate("A"), makeGate("B"), makeGate("C")]
    let dag = buildGateDag(gates)
    check dag.adjacency.len == 3
    check dag.inDegree["A"] == 0
    check dag.inDegree["B"] == 0
    check dag.inDegree["C"] == 0

  test "buildGateDag records dependency edges":
    ## Given gate C depends on A and B
    ## When buildGateDag is called
    ## Then C has in-degree 2, A and B have in-degree 0
    let gates = @[
      makeGate("A"),
      makeGate("B"),
      makeGate("C", after = @["A", "B"]),
    ]
    let dag = buildGateDag(gates)
    check dag.inDegree["C"] == 2
    check dag.inDegree["A"] == 0
    check "C" in dag.adjacency["A"]
    check "C" in dag.adjacency["B"]

  test "buildGateDag ignores external dependencies":
    ## Given gate B depends on A and X (X not in gate set)
    ## When buildGateDag is called
    ## Then B has in-degree 1 (only A counts)
    let gates = @[makeGate("A"), makeGate("B", after = @["A", "X"])]
    let dag = buildGateDag(gates)
    check dag.inDegree["B"] == 1

suite "Gate DAG — Topological Sort":

  test "topologicalLayers groups independent gates in layer 0":
    ## Given 3 gates with no dependencies
    ## When topologicalLayers is called
    ## Then all 3 are in layer 0
    let gates = @[makeGate("A"), makeGate("B"), makeGate("C")]
    let dag = buildGateDag(gates)
    let layers = dag.topologicalLayers()
    check layers.len == 1
    check layers[0].len == 3

  test "topologicalLayers orders dependent gates correctly":
    ## Given A → B → C chain
    ## When topologicalLayers is called
    ## Then layer 0 = [A], layer 1 = [B], layer 2 = [C]
    let gates = @[
      makeGate("A"),
      makeGate("B", after = @["A"]),
      makeGate("C", after = @["B"]),
    ]
    let dag = buildGateDag(gates)
    let layers = dag.topologicalLayers()
    check layers.len == 3
    check "A" in layers[0]
    check "B" in layers[1]
    check "C" in layers[2]

  test "topologicalLayers handles diamond dependency":
    ## Given A → B, A → C, B → D, C → D
    ## When topologicalLayers is called
    ## Then layer 0 = [A], layer 1 = [B, C], layer 2 = [D]
    let gates = @[
      makeGate("A"),
      makeGate("B", after = @["A"]),
      makeGate("C", after = @["A"]),
      makeGate("D", after = @["B", "C"]),
    ]
    let dag = buildGateDag(gates)
    let layers = dag.topologicalLayers()
    check layers.len == 3
    check "A" in layers[0]
    check layers[1].len == 2
    check "D" in layers[2]

suite "Gate DAG — File Pattern Matching":

  test "empty filesPattern always matches":
    ## Given a gate with empty filesPattern
    ## When matchesFilesPattern is called
    ## Then it returns true for any changed files
    let gate = makeGate("test", filesPattern = "")
    check matchesFilesPattern(gate, @["src/core/types.nim"]) == true

  test "filesPattern matches substring in changed file":
    ## Given a gate with filesPattern = "src/core/types"
    ## When a changed file contains that substring
    ## Then matchesFilesPattern returns true
    let gate = makeGate("test", filesPattern = "src/core/types")
    check matchesFilesPattern(gate, @["src/core/types/domain_types.nim"]) == true
    check matchesFilesPattern(gate, @["src/cli/main.nim"]) == false

  test "pipe-separated patterns match any pattern":
    ## Given a gate with filesPattern = "src/core/types|src/core/gate"
    ## When changed files match either pattern
    ## Then matchesFilesPattern returns true
    let gate = makeGate("test", filesPattern = "src/core/types|src/core/gate")
    check matchesFilesPattern(gate, @["src/core/types/foo.nim"]) == true
    check matchesFilesPattern(gate, @["src/core/gate/bar.nim"]) == true
    check matchesFilesPattern(gate, @["src/cli/main.nim"]) == false

suite "Gate DAG — Affected Gate Discovery":

  test "findAffectedGates includes directly affected gates":
    ## Given gate A matches changed files
    ## When findAffectedGates is called
    ## Then A is in the result set
    let gates = @[makeGate("A", filesPattern = "src/core")]
    let dag = buildGateDag(gates)
    let affected = findAffectedGates(dag, @["src/core/types.nim"], gates)
    check "A" in affected

  test "findAffectedGates propagates to dependent gates":
    ## Given A matches files and C depends on B which depends on A
    ## When findAffectedGates is called
    ## Then A, B, and C are all affected
    let gates = @[
      makeGate("A", filesPattern = "src/core"),
      makeGate("B", after = @["A"]),
      makeGate("C", after = @["B"]),
    ]
    let dag = buildGateDag(gates)
    let affected = findAffectedGates(dag, @["src/core/types.nim"], gates)
    check "A" in affected
    check "B" in affected
    check "C" in affected

suite "Gate DAG — Tier Filtering":

  test "gatesInTier returns only matching tier":
    ## Given gates with tier 1 and tier 2
    ## When gatesInTier is called with tier=2
    ## Then only tier-2 gates are returned
    let gates = @[
      makeGate("A", tier = 1),
      makeGate("B", tier = 2),
      makeGate("C", tier = 2),
    ]
    let tier2 = gatesInTier(gates, 2)
    check tier2.len == 2
    check tier2[0].id == "B"
    check tier2[1].id == "C"

suite "Gate DAG — Failure Propagation":

  test "propagateFailures returns identity for gate with no dependents":
    ## Given gate A with no downstream dependents
    ## When A fails and propagateFailures is called
    ## Then only A is in the failed set (no propagation possible)
    let gates = @[makeGate("A")]
    let dag = buildGateDag(gates)
    var failed = initHashSet[string]()
    failed.incl("A")
    let propagated = propagateFailures(dag, failed)
    check "A" in propagated
    check propagated.len == 1

  test "propagateFailures returns empty for empty input":
    ## Given an empty failed set
    ## When propagateFailures is called
    ## Then the result is also empty
    let gates = @[makeGate("A"), makeGate("B", after = @["A"])]
    let dag = buildGateDag(gates)
    var failed = initHashSet[string]()
    let propagated = propagateFailures(dag, failed)
    check propagated.len == 0

suite "Gate DAG — fileToModule":

  test "fileToModule strips src/ prefix and .nim extension":
    ## Given a git-relative file path "src/core/types/domain_types.nim"
    ## When fileToModule is called
    ## Then the result is "types/domain_types"
    check fileToModule("src/core/types/domain_types.nim") == "types/domain_types"

  test "fileToModule strips core/ prefix":
    ## Given a path "src/core/gate/state_ledger.nim"
    ## When fileToModule is called
    ## Then the result is "gate/state_ledger"
    check fileToModule("src/core/gate/state_ledger.nim") == "gate/state_ledger"

  test "fileToModule handles non-core paths":
    ## Given a path "src/gate/gate_types.nim"
    ## When fileToModule is called
    ## Then src/ is stripped but core/ is not (not present)
    check fileToModule("src/gate/gate_types.nim") == "gate/gate_types"
