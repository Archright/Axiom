## Topology Explainability Engine
## AGENTS.md Topology Contract §Phase A
## Generates ADR-style explanations for any module's topology status.

import core/trusted/layer_declaration
axiomLayer "domain"
import std/[tables, os]
import core/topology/lock, core/topology/policy
{.push raises: [].}
# axiomIoBoundary

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func findModuleByPath*(lock: TopologyLock, targetPath: string): string =
  for mid, meta in lock.modules:
    if meta.currentPath == targetPath:
      return mid
  return ""

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func generateExplanation*(targetPath: string, policy: TopologyPolicy,
                         lock: TopologyLock): string =
  let mid = findModuleByPath(lock, targetPath)
  if mid.len == 0:
    return targetPath & "\nTopology Status:\n  unknown (not in topology.lock)\n"

  result = targetPath & "\nTopology Status:\n"
  let meta = lock.modules.getOrDefault(mid)

  if meta.history.len > 0:
    let last = meta.history[^1]
    result.add("  " & last.changeType & "\n")
  else:
    result.add("  registered\n")

  result.add("\nReason:\n")
  let parentDir = targetPath.parentDir
  if policy.defaults.collapseSingletons and not policy.isException(parentDir):
    result.add("  policy.defaults.collapseSingletons = true\n")
    result.add("  policy.exceptions does not include " & parentDir & "\n")
  else:
    result.add("  standard module placement per topology.lock\n")

  if meta.history.len > 0:
    result.add("\nHistory:\n")
    for h in meta.history:
      result.add("  " & h.changedAt & "\n")
      result.add("    " & h.path & "\n")
      result.add("      ↓\n")
      result.add("    " & meta.currentPath & "\n")
      result.add("    (changeType: " & h.changeType & 
                 ", approvedInLock: " & $h.approvedInLock & ")\n")

  result.add("\nLock Reference:\n")
  result.add("  topology.lock revision " & $lock.lockRevision & "\n")
  result.add("  moduleId: " & mid & "\n")

  if lock.transitionalModules.hasKey(mid):
    let t = lock.transitionalModules.getOrDefault(mid)
    result.add("  transitional: created_at=" & t.createdAt)
    if t.resolvedAt.len > 0:
      result.add(", resolved_at=" & t.resolvedAt & "\n")
    else:
      result.add(" (unresolved)\n")

{.pop}
