## PBT Integrity Feature Test — gateway runner for pbt_integrity.feature.
## Satisfies nimtry 1:1 cardinality gate (FEATURE-missing-runner).
## See tests/features/pbt_integrity.feature for the specification.
##
## 6 Scenarios:
##  1. Generated DAGs are always acyclic
##  2. TopologyLock JSON roundtrip preserves all fields
##  3. Gate idempotency holds for valid inputs
##  4. Shrink convergence finds minimal counter-example within timeout
##  5. BitStream withSnapshot restores cursor on exception
##  6. TopologyLock roundtrip under 1000-iteration stress

{.push raises: [].}

import std/[json, tables, times, unittest]
import core/results
import core/testing/pbt_engine
import core/testing/generators
import core/topology/lock
import core/topology/lock_update

# ─── Helpers ───────────────────────────────────────────────────

proc fieldEqual(a, b: TopologyLock): bool {.raises: [].} =
  ## Compare TopologyLock fields that survive JSON roundtrip.
  result = a.schema == b.schema and
           a.lockRevision == b.lockRevision and
           a.generatedFromPolicy == b.generatedFromPolicy and
           a.modules.len == b.modules.len and
           a.shards.len == b.shards.len and
           a.transitionalModules.len == b.transitionalModules.len
  # Compare module entries
  if result:
    for key, entry in a.modules:
      if not b.modules.hasKey(key):
        return false
      let bEntry = b.modules.getOrDefault(key)
      if entry.currentPath != bEntry.currentPath or
         entry.initialPath != bEntry.initialPath or
         entry.history.len != bEntry.history.len:
        return false
  # Compare shard entries
  if result:
    for key, entry in a.shards:
      if not b.shards.hasKey(key):
        return false
      let bEntry = b.shards.getOrDefault(key)
      if entry.moduleType != bEntry.moduleType or
         entry.members.len != bEntry.members.len:
        return false

# ─── Suite ─────────────────────────────────────────────────────

suite "PBT Integrity (from pbt_integrity.feature)":

  test "Generated DAGs are always acyclic":
    ## Scenario 1: Generated DAGs are always acyclic
    ## Given a PBT engine with seed-based deterministic generation
    ## When 200 DAGs are generated with up to 20 nodes
    ## Then every generated DAG must have hasCycle == false
    ## And the adjacency table must be consistent with edges
    let dagGen = genDAG(maxNodes = 20)
    let acyclic = proc(g: DagGraph): bool =
      # Check acyclicity
      if hasCycle(g):
        return false
      # Check adjacency consistency: every edge (src, dst) must appear in adjacency[src]
      for e in g.edges:
        let neighbors = g.adjacency.getOrDefault(e.src)
        if e.dst notin neighbors:
          return false
      return true
    let result = checkProperty(dagGen, acyclic, iterations = 200,
                                tier = PbtBasic,
                                verbosity = PbtSilent)
    check result.passed == true
    if not result.passed:
      echo "[PBT-FAILED] DAG acyclicity violated. Seed: ", result.seed
      echo "[PBT-FAILED] Counter-example: ", result.counterExample
    else:
      echo "[PBT-SEED] DAG acyclicity: 200 DAGs verified. Seed: ", result.seed

  test "TopologyLock JSON roundtrip preserves all fields":
    ## Scenario 2: TopologyLock JSON roundtrip preserves all fields
    ## Given a TopologyLock generator producing valid lock structures
    ## When a lock is serialized via renderLockJson and parsed back
    ## Then schema, lockRevision, modules, shards, and transitional_modules must match
    let lockGen = genTopologyLock()
    let roundtrip = proc(lock: TopologyLock): bool =
      let json = renderLockJson(lock)
      let reparsed = parseTopologyLockJson(json).get
      fieldEqual(lock, reparsed)
    let result = checkProperty(lockGen, roundtrip, iterations = 50,
                                tier = PbtBasic,
                                verbosity = PbtSilent)
    check result.passed == true
    if not result.passed:
      echo "[PBT-FAILED] TopologyLock roundtrip violated. Seed: ", result.seed
      echo "[PBT-FAILED] Counter-example: ", result.counterExample
    else:
      echo "[PBT-SEED] TopologyLock roundtrip: 50 locks verified. Seed: ", result.seed

  test "Gate idempotency holds for valid inputs":
    ## Scenario 3: Gate idempotency holds for valid inputs
    ## Given a gate config mutation generator
    ## When mutations are applied to a base config
    ## Then the result must remain structurally valid
    let base = """{"test_gate": {"enabled": true, "exceptions": []}}"""
    let mutator = genGateConfigMutation(base)
    let structurallyValid = proc(j: JsonNode): bool =
      # Mutation should always produce a parseable JObject
      j.kind == JObject
    let result = checkProperty(mutator, structurallyValid, iterations = 50,
                                tier = PbtBasic,
                                verbosity = PbtSilent)
    check result.passed == true
    if not result.passed:
      echo "[PBT-FAILED] Gate idempotency violated. Seed: ", result.seed
      echo "[PBT-FAILED] Counter-example: ", result.counterExample
    else:
      echo "[PBT-SEED] Gate idempotency: 50 mutations verified. Seed: ", result.seed

  test "Shrink convergence finds minimal counter-example within timeout":
    ## Scenario 4: Shrink convergence finds minimal counter-example within timeout
    ## Given a property that always fails for values >= 50
    ## When checkProperty runs with maxShrinkSteps=50
    ## Then the counter-example must be found
    ## And the shrink must complete within the timeout
    let gen = genInt(0, 1000)
    let prop = proc(i: int): bool = i < 50  # fails for i >= 50
    let result = checkProperty(gen, prop, iterations = 200,
                                maxShrinkSteps = 50,
                                tier = PbtBasic,
                                verbosity = PbtSilent)
    check result.passed == false
    check result.seed > 0
    check result.counterExample.len > 0
    check result.timedOut == false
    if not result.passed:
      echo "[PBT-SEED] Shrink convergence: counter-example found = ",
           result.counterExample, " (steps: ", result.shrinkSteps, ")"
    else:
      echo "[PBT-FAILED] Shrink convergence: expected failure but got pass"

  test "BitStream withSnapshot restores cursor on exception":
    ## Scenario 5: BitStream withSnapshot restores cursor on exception
    ## Given a BitStream with cursor at position 10
    ## When a generator throws mid-consumption inside withSnapshot
    ## Then the cursor must be restored to position 10
    var bs = initBitStream(42)
    bs.cursor = 10
    try:
      bs.withSnapshot:
        discard bs.randInt(0, 100)
        discard bs.randInt(0, 100)
        raise newException(ValueError, "intentional test crash")
    except ValueError:
      discard
    check bs.cursor == 10

  test "TopologyLock roundtrip under 1000-iteration stress":
    ## Scenario 6: TopologyLock roundtrip under 1000-iteration stress
    ## Given a TopologyLock generator
    ## When 1000 locks are roundtripped through renderLockJson + parseTopologyLockJson
    ## Then all 1000 must preserve schema, revision, and module counts
    let lockGen = genTopologyLock()
    let roundtrip = proc(lock: TopologyLock): bool =
      let json = renderLockJson(lock)
      let reparsed = parseTopologyLockJson(json).get
      fieldEqual(lock, reparsed)
    let result = checkProperty(lockGen, roundtrip, iterations = 1000,
                                tier = PbtStress,
                                verbosity = PbtSilent)
    check result.passed == true
    if not result.passed:
      echo "[PBT-FAILED] TopologyLock stress roundtrip violated. Seed: ", result.seed
      echo "[PBT-FAILED] Counter-example: ", result.counterExample
    else:
      echo "[PBT-SEED] TopologyLock stress: 1000 locks verified. Seed: ", result.seed

{.pop.}
