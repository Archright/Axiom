## Topology gate operations — shared between CLI dispatch and gate runners.
##
## Extracted from cli/commands/topology_cli.nim to eliminate the
## gate → cli layer violation.  Both cli/commands/topology_cli and
## gate/runners/topology_policy_gate import from here instead of
## creating a circular dependency.

import core/trusted/layer_declaration
axiomLayer "domain"
import core/results
import core/topology/[policy, lock, suggest, apply, lock_update]
import std/os
import infrastructure/logging_facade
import core/axiom_pragmas
# axiomIoBoundary

const
  topologyPolicyPath* = "topology_policy.json"
  topologyLockPath* = "topology.lock"
  topologyDeclPath* = "topology.json"

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc runTopologyCheck*(policyPath, lockPath: string): int {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let policyRes = parseTopologyPolicy(policyPath)
  if policyRes.isErr:
    logError("gate_ops", policyRes.error)
    return 1
  let lockRes = parseTopologyLock(lockPath)
  if lockRes.isErr:
    logError("gate_ops", lockRes.error)
    return 1
  let auditRes = runTopologyAuditWithSuggestions(policyRes.get, lockRes.get)
  if auditRes.isErr:
    logError("gate_ops", auditRes.error)
    return 1
  let auditResult = auditRes.get

  # check is the strict subset: lock compliance only
  let lockKinds = ["lock_orphan", "lock_missing", "transitional_expired", "suppression_expired"]
  var errors: seq[AuditViolation] = @[]
  for v in auditResult.violations:
    if v.kind in lockKinds:
      errors.add(v)

  if errors.len == 0:
    logInfo("gate_ops", "[PASS] Topology check: lock and filesystem are aligned.")
    return 0

  for v in errors:
    logWarn("gate_ops", formatSuggestionHuman(v))
  return 1

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc runTopologySyncLock*(lockPath, policyPath: string;
                          args: seq[string] = @[]): int {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Auto-synchronize topology.lock with the filesystem.
  ## --apply: add orphans, remove stale, bump revision, save.
  ## default: dry-run mode, report only.
  if not fileExists(lockPath):
    logError("topology_cli", "[ERROR] Lock file not found: " & lockPath)
    return 2
  var apply = false
  for a in args:
    if a == "--apply":
      apply = true
    elif a == "--dry-run":
      apply = false
  let lockRes = parseTopologyLock(lockPath)
  if lockRes.isErr:
    logError("gate_ops", lockRes.error)
    return 2
  var lock = lockRes.get
  let prevRevision = lock.lockRevision
  let report = reconcileLockModel(lock, "src", dryRun = not apply)
  if apply:
    writeFile(lockPath, renderLockJson(lock))
    logInfo("gate_ops", "[SYNC] topology.lock updated: revision " & $prevRevision & " -> " & $lock.lockRevision)
  else:
    logInfo("gate_ops", "[DRY-RUN] Would add: " & $report.added.len & " orphans, " & $report.warnings.len & " stale entries")
    logInfo("gate_ops", "Run with --apply to modify lock")
  logInfo("gate_ops", "[RECONCILE] added=" & $report.added.len & " warnings=" & $report.warnings.len & " unchanged=" & $report.unchanged)
  return 0
