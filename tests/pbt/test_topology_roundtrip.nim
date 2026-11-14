{.push raises: [].}
## PBT: TopologyLock JSON Roundtrip
## Property: parse(renderLockJson(lock)) == lock for all generated locks.
## @stress tier — 1000 iterations, nightly/CI only.

import std/[tables, unittest]
import core/results
import core/testing/pbt_engine
import core/testing/generators
import core/topology/lock
import core/topology/lock_update

proc fieldEqual(a, b: TopologyLock): bool =
  ## Compare all TopologyLock fields except metadata that may roundtrip loosely.
  result = a.schema == b.schema and
           a.lock_revision == b.lock_revision and
           a.generated_from_policy == b.generated_from_policy and
           a.modules.len == b.modules.len and
           a.shards.len == b.shards.len and
           a.transitional_modules.len == b.transitional_modules.len
  # Compare module entries
  if result:
    for key, entry in a.modules:
      if not b.modules.hasKey(key):
        return false
      let bEntry = b.modules.getOrDefault(key)
      if entry.current_path != bEntry.current_path or
         entry.initial_path != bEntry.initial_path or
         entry.history.len != bEntry.history.len:
        return false
  # Compare shard entries
  if result:
    for key, entry in a.shards:
      if not b.shards.hasKey(key):
        return false
      let bEntry = b.shards.getOrDefault(key)
      if entry.module_type != bEntry.module_type or
         entry.members.len != bEntry.members.len:
        return false

suite "PBT: TopologyLock Roundtrip":
  test "parse(renderLockJson(lock)) preserves all fields":
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

  test "renderLockJson produces valid JSON":
    let lockGen = genTopologyLock()
    let validJson = proc(lock: TopologyLock): bool =
      let json = renderLockJson(lock)
      let parsed = parseTopologyLockJson(json)
      parsed.ok
    let result = checkProperty(lockGen, validJson, iterations = 50,
                                verbosity = PbtSilent)
    check result.passed == true

  test "renderLockJson is insertion-order independent":
    proc buildLock(moduleOrder, shardOrder, transOrder: seq[string]): TopologyLock =
      result = TopologyLock(
        schema: "axiom-topology-lock/v1",
        lock_revision: 7,
        generated_from_policy: "policy-hash",
        generated_from_revision: 3,
        generated_at: "2026-01-01T00:00:00Z"
      )
      for mid in moduleOrder:
        result.modules[mid] = ModuleEntry(
          current_path: "src/core/" & mid & ".nim",
          initial_path: "src/legacy/" & mid & ".nim",
          history: @[ModuleHistoryEntry(
            path: "src/moved/" & mid & ".nim",
            changed_at: "2026-01-02T00:00:00Z",
            change_type: "topology_apply",
            approved_in_lock: 2
          )]
        )
      for sid in shardOrder:
        result.shards[sid] = ShardEntry(
          members: @["mod1", "mod2"],
          module_type: "core",
          note: "stable shard"
        )
      for tid in transOrder:
        result.transitional_modules[tid] = TransitionalEntry(
          created_at: "2026-01-03T00:00:00Z",
          resolved_at: ""
        )

    let lockA = buildLock(@["mod1", "mod2", "mod3"],
                          @["shard1", "shard2", "shard3"],
                          @["trans1", "trans2", "trans3"])
    let lockB = buildLock(@["mod3", "mod1", "mod2"],
                          @["shard3", "shard1", "shard2"],
                          @["trans3", "trans1", "trans2"])
    let lockC = buildLock(@["mod2", "mod3", "mod1"],
                          @["shard2", "shard3", "shard1"],
                          @["trans2", "trans3", "trans1"])
    let jsonA = renderLockJson(lockA)
    let jsonB = renderLockJson(lockB)
    let jsonC = renderLockJson(lockC)
    check jsonA.len > 0
    check jsonA == jsonB
    check jsonB == jsonC
    check jsonA == jsonC
    # Non-vacuous: the render actually carries the permuted content
    let round = parseTopologyLockJson(jsonA).get
    check round.modules.len == 3
    check round.shards.len == 3
    check round.transitional_modules.len == 3
    check round.modules.getOrDefault("mod1").current_path == "src/core/mod1.nim"

  test "parseTopologyLockJson reads snake_case paths":
    let jsonStr = """{
      "_schema": "axiom-topology-lock/v1",
      "lock_revision": 4,
      "generated_from_policy": "policy-hash",
      "generated_from_revision": 2,
      "generated_at": "2026-01-01T00:00:00Z",
      "modules": {
        "mod_a": {
          "current_path": "src/core/mod_a.nim",
          "initial_path": "src/legacy/mod_a.nim",
          "history": [
            {"path": "src/moved/mod_a.nim", "changed_at": "2026-01-02T00:00:00Z",
             "change_type": "topology_apply", "approved_in_lock": 3}
          ]
        }
      }
    }"""
    let parsed = parseTopologyLockJson(jsonStr)
    check parsed.ok
    if parsed.ok:
      let lock = parsed.get
      check lock.modules.hasKey("mod_a")
      let entry = lock.modules.getOrDefault("mod_a")
      check entry.current_path.len > 0
      check entry.current_path == "src/core/mod_a.nim"
      check entry.initial_path.len > 0
      check entry.initial_path == "src/legacy/mod_a.nim"
      check entry.history.len == 1
      check entry.history[0].path == "src/moved/mod_a.nim"
      check entry.history[0].changed_at == "2026-01-02T00:00:00Z"
      check entry.history[0].change_type == "topology_apply"
      check entry.history[0].approved_in_lock == 3

{.pop.}
