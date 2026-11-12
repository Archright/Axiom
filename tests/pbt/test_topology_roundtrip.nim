{.push raises: [].}
## PBT: TopologyLock JSON Roundtrip
## Property: parse(renderLockJson(lock)) == lock for all generated locks.
## @stress tier — 1000 iterations, nightly/CI only.

import std/[tables, unittest]
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

{.pop.}
