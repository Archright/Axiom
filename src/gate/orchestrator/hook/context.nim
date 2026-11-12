## context.nim — State, environment, context management for orchestrator hook.
## (domain: context)

import core/trusted/layer_declaration
axiomLayer "gate"
import gate/orchestrator_types
import gate/gate_contract  # for EnvDependency, EnvContextSnapshot
import core/trusted/env_access  # for getAxiomEnv
import core/parsers/safe_parsers  # for safeParseInt
import std/json  # for parseFile
import std/os  # for fileExists, extractFilename
import std/tables  # for initTable
import core/results  # for isOk, Result
import std/strutils  # for split, strip, join, endsWith, contains
import infrastructure/git_config  # for getGitConfig

# ---------------------------------------------------------------------------
# Phase F: Semantic Memoization — module-level Salsa DB pointer
# ---------------------------------------------------------------------------
var gSalsaDbPtr* {.threadvar.}: pointer
proc setSalsaDbPtr*(db: pointer) {.raises: [].} =
  gSalsaDbPtr = db

# ---------------------------------------------------------------------------
# In-Memory Session Journal
# ---------------------------------------------------------------------------
proc newSessionJournal*(): SessionJournal {.raises: [].} =
  SessionJournal(entries: initTable[string, GateRunRecord]())

proc recordResult*(journal: SessionJournal; gateId: string; record: GateRunRecord) {.raises: [].} =
  journal.entries[gateId] = record

proc isFailed*(journal: SessionJournal; gateId: string): bool {.raises: [].} =
  let rec = journal.entries.getOrDefault(gateId)
  rec.status in {grsFailed, grsTimeout, grsCrash}

proc loadGateSla*(gateId: string; forCommit: bool = false): int {.raises: [CatchableError].} =
  let envOverride = getAxiomEnv(evTimeoutSla)
  if envOverride.len > 0:
    let parsed = safeParseInt(envOverride)
    if parsed.isOk(): return parsed.get() * 1000

  let slaPath = "tools/config/gate_sla.json"
  if not fileExists(slaPath):
    if forCommit:
      return 5_000
    return 120_000

  try:
    let sla = parseFile(slaPath)
    if forCommit:
      let commitBuffer = sla{"commit_buffer_sec"}.getInt(0)
      if sla{"gates"}.hasKey(gateId):
        let gateTimeout = sla{"gates"}{gateId}{"timeout_sec"}.getInt(5)
        return (gateTimeout + commitBuffer) * 1000
      return (sla{"commit_default_timeout_sec"}.getInt(5) + commitBuffer) * 1000

    let buffer = sla{"orchestrator_buffer_sec"}.getInt(30)
    if sla{"gates"}.hasKey(gateId):
      let gateTimeout = sla{"gates"}{gateId}{"timeout_sec"}.getInt(120)
      return (gateTimeout + buffer) * 1000
    return (sla{"default_timeout_sec"}.getInt(120) + buffer) * 1000
  except CatchableError:
    if forCommit:
      return 5_000
    return 120_000

# ---------------------------------------------------------------------------
# Gate name normalization and source path resolution
# Delegated to the SSOT module core/gate/gate_resolver; re-exported so all
# existing call sites (executor, memo, gateway) keep resolving unchanged.
# ---------------------------------------------------------------------------
import core/gate/gate_resolver
export gate_resolver

# ---------------------------------------------------------------------------
# File pattern filtering and data file resolution
# ---------------------------------------------------------------------------
func filterByPattern*(changedFiles: seq[string]; filesPattern: string): seq[string] =
  if filesPattern.len == 0:
    return changedFiles
  let patterns = filesPattern.split('|')
  result = @[]
  for f in changedFiles:
    for p in patterns:
      if f.contains(p.strip()):
        result.add(f)
        break

proc resolveDataFiles*(filesPattern: string): seq[string] {.raises: [].} =
  if filesPattern.len == 0:
    return @[]
  let tokens = filesPattern.split('|')
  result = @[]
  for t in tokens:
    let token = t.strip()
    if token.len == 0 or token.endsWith('/') or token.contains('*'):
      continue
    if fileExists(token):
      result.add(token)

# ---------------------------------------------------------------------------
# Environment context capture
# ---------------------------------------------------------------------------
proc captureContext*(deps: seq[EnvDependency]): Result[EnvContextSnapshot, EnvError] {.raises: [CatchableError].} =
  var snapshot = EnvContextSnapshot(values: initTable[string, string]())
  for dep in deps:
    let val = case dep.kind
      of dkGitConfig: getGitConfig(dep.key)
      of dkEnvVar: getEnv(dep.key, "")
    snapshot.values[dep.key] = val
  ok(snapshot)
