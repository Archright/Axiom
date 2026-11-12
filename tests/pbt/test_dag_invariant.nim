{.push raises: [].}
## PBT: DAG Acyclicity Invariant
## Property: hasCycle(generatedDAG) == false for all generated DAGs.
## @basic tier — runs in every CI push.

import std/[tables, unittest]
import core/testing/pbt_engine
import core/testing/generators

suite "PBT: DAG Topological Invariant":
  test "Generated DAGs are always acyclic (200 iterations)":
    let dagGen = genDAG(maxNodes = 20)
    let acyclic = proc(g: DagGraph): bool = not hasCycle(g)
    let result = checkProperty(dagGen, acyclic, iterations = 200,
                                tier = PbtBasic,
                                verbosity = PbtSilent)
    check result.passed == true
    if not result.passed:
      echo "[PBT-FAILED] DAG acyclicity violated. Seed: ", result.seed
      echo "[PBT-FAILED] Counter-example: ", result.counterExample
    else:
      echo "[PBT-SEED] DAG acyclicity: 200 DAGs verified. Seed: ", result.seed

  test "DAG adjacency matches edges":
    let dagGen = genDAG(maxNodes = 10)
    let consistent = proc(g: DagGraph): bool =
      # Every edge (src, dst) should appear in adjacency[src]
      for e in g.edges:
        let neighbors = g.adjacency.getOrDefault(e.src)
        if e.dst notin neighbors:
          return false
      return true
    let result = checkProperty(dagGen, consistent, iterations = 100,
                                verbosity = PbtSilent)
    check result.passed == true

{.pop.}
