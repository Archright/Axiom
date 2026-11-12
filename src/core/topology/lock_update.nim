## Topology Lock Updater — Pure lock model transformation.
## Accepts a TopologyLock model + moves + timestamp, returns updated JSON string.
## No filesystem I/O; caller (infrastructure) handles read/write.

import core/trusted/layer_declaration
axiomLayer "domain"
import std/[json, tables]
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
  var modulesObj = newJObject()
  for mid, entry in lock.modules:
    var historyArr = newJArray()
    for h in entry.history:
      historyArr.add(%*{
        "path": h.path,
        "changedAt": h.changedAt,
        "changeType": h.changeType,
        "approvedInLock": h.approvedInLock
      })
    modulesObj[mid] = %*{
      "currentPath": entry.currentPath,
      "initialPath": entry.initialPath,
      "history": historyArr
    }

  var shardsObj = newJObject()
  for sid, shard in lock.shards:
    shardsObj[sid] = %*{
      "members": shard.members,
      "type": shard.moduleType,          # JSON key matches parser expectation
      "note": shard.note
    }

  var transitionalObj = newJObject()
  for tid, tm in lock.transitionalModules:
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
