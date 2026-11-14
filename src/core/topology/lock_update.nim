## Topology Lock Updater — Pure lock model transformation.
## Accepts a TopologyLock model + moves + timestamp, returns updated JSON string.
## No filesystem I/O; caller (infrastructure) handles read/write.

import core/trusted/layer_declaration
axiomLayer "domain"
import std/[algorithm, json, tables]
import core/topology/lock
import core/topology/plan
{.push raises: [].}
# axiomIoBoundary

export lock, plan

func updateLockModel*(lock: TopologyLock; moves: seq[MoveOp];
                      nowStr: string): TopologyLock {.raises: [].} =
  ## Pure: update lock model paths and append history entries.
  result = lock
  var oldToNew = initTable[string, string]()
  for m in moves:
    oldToNew[m.fromPath] = m.toPath

  if oldToNew.len == 0:
    return

  let nextRevision = result.lockRevision + 1

  for mid, entry in result.modules.mpairs:
    if oldToNew.hasKey(entry.currentPath):
      let newPath = oldToNew.getOrDefault(entry.currentPath)
      entry.history.add(ModuleHistoryEntry(
        path: newPath,
        changedAt: nowStr,
        changeType: "topology_apply",
        approvedInLock: nextRevision
      ))
      entry.currentPath = newPath

  result.lockRevision = nextRevision
  result.generatedAt = nowStr

func renderLockJson*(lock: TopologyLock): string {.raises: [].} =
  ## Pure: render a TopologyLock model to JSON string.
  ## Key order is canonical (sorted per table) so output is insertion-order independent.
  var moduleIds: seq[string] = @[]
  for mid in lock.modules.keys:
    moduleIds.add(mid)
  moduleIds.sort()

  var modulesObj = newJObject()
  for mid in moduleIds:
    let entry = lock.modules.getOrDefault(mid)
    var historyArr = newJArray()
    for h in entry.history:
      historyArr.add(%*{
        "path": h.path,
        "changed_at": h.changedAt,
        "change_type": h.changeType,
        "approved_in_lock": h.approvedInLock
      })
    modulesObj[mid] = %*{
      "current_path": entry.currentPath,
      "initial_path": entry.initialPath,
      "history": historyArr
    }

  var shardIds: seq[string] = @[]
  for sid in lock.shards.keys:
    shardIds.add(sid)
  shardIds.sort()

  var shardsObj = newJObject()
  for sid in shardIds:
    let shard = lock.shards.getOrDefault(sid)
    shardsObj[sid] = %*{
      "members": shard.members,
      "type": shard.moduleType,          # JSON key matches parser expectation
      "note": shard.note
    }

  var transitionalIds: seq[string] = @[]
  for tid in lock.transitionalModules.keys:
    transitionalIds.add(tid)
  transitionalIds.sort()

  var transitionalObj = newJObject()
  for tid in transitionalIds:
    let tm = lock.transitionalModules.getOrDefault(tid)
    transitionalObj[tid] = %*{
      "created_at": tm.createdAt,
      "resolved_at": tm.resolvedAt
    }

  let j = %*{
    "_schema": lock.schema,
    "lock_revision": lock.lockRevision,
    "generated_from_policy": lock.generatedFromPolicy,
    "generated_from_revision": lock.generatedFromRevision,
    "generated_at": lock.generatedAt,
    "modules": modulesObj,
    "shards": shardsObj,
    "transitional_modules": transitionalObj
  }

  result = j.pretty

{.pop}
