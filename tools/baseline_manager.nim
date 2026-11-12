import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}

## baseline_manager.nim — Baseline-as-a-Version CLI
## Manage gate baselines: update, drift detection, validation.

import std/[os, json, strutils, strformat, tables, times]
import shared_types/shared_types

const BaselineFiles = {
  "debt-reduction": "data/debt_reduction_baseline.json",
  "logging-policy": "data/logging_policy_baseline.json",
  "code-health": "data/code_health_baseline.json",
  "monotonic-whitelist": "data/monotonic_whitelist_baseline.json",
}.toTable

proc findBaseline(gateId: string): string =
  ## Find baseline file path for a gate ID.
  if BaselineFiles.hasKey(gateId):
    return BaselineFiles[gateId]
  # Try pattern match
  for key, path in BaselineFiles.pairs:
    if gateId.contains(key) or key.contains(gateId):
      return path
  ""

proc updateBaseline(repoRoot: string; gateId: string) {.axiomEffect: IoEffect.} =
  ## Promote current measurement to baseline.
  let baselinePath = findBaseline(gateId)
  if baselinePath.len == 0:
    stderr.writeLine(&"[BASELINE] Unknown gate: {gateId}")
    return
  let fullPath = repoRoot / baselinePath
  if not fileExists(fullPath):
    stderr.writeLine(&"[BASELINE] No baseline file: {baselinePath}")
    return
  try:
    let content = readFile(fullPath)
    let j = parseJson(content)
    # Update timestamp
    if j.hasKey("updated_at"):
      j["updated_at"] = %($now().utc())
    if j.hasKey("timestamp"):
      j["timestamp"] = %($now().utc())
    writeFile(fullPath, j.pretty() & "\n")
    stderr.writeLine(&"[BASELINE] Updated {gateId}: {baselinePath}")
  except CatchableError as e:
    stderr.writeLine(&"[BASELINE] Error updating {gateId}: {e.msg}")

proc showDrift(repoRoot: string; gateId: string) {.axiomEffect: IoEffect.} =
  ## Show baseline drift information.
  let baselinePath = findBaseline(gateId)
  if baselinePath.len == 0:
    stderr.writeLine(&"[BASELINE] Unknown gate: {gateId}")
    return
  let fullPath = repoRoot / baselinePath
  if not fileExists(fullPath):
    stderr.writeLine(&"[BASELINE] No baseline file: {baselinePath}")
    return
  try:
    let content = readFile(fullPath)
    let j = parseJson(content)
    stderr.writeLine(&"[BASELINE] {gateId} @ {baselinePath}")
    if j.hasKey("total"):
      stderr.writeLine(&"  total: {j[\"total\"].getInt()}")
    if j.hasKey("count"):
      stderr.writeLine(&"  count: {j[\"count\"].getInt()}")
    if j.hasKey("updated_at"):
      stderr.writeLine(&"  updated_at: {j[\"updated_at\"].getStr()}")
    if j.hasKey("timestamp"):
      stderr.writeLine(&"  timestamp: {j[\"timestamp\"].getStr()}")
  except CatchableError as e:
    stderr.writeLine(&"[BASELINE] Error reading {gateId}: {e.msg}")

proc validateBaselines(repoRoot: string) {.axiomEffect: IoEffect.} =
  ## Validate all baseline files are valid JSON.
  var valid = 0
  var invalid = 0
  for gateId, relPath in BaselineFiles.pairs:
    let fullPath = repoRoot / relPath
    if not fileExists(fullPath):
      stderr.writeLine(&"[BASELINE] MISSING: {gateId} ({relPath})")
      inc invalid
      continue
    try:
      let j = parseJson(readFile(fullPath))
      inc valid
    except CatchableError as e:
      stderr.writeLine(&"[BASELINE] INVALID JSON: {gateId} ({relPath}): {e.msg}")
      inc invalid
  stderr.writeLine(&"[BASELINE] Validation: {valid} valid, {invalid} invalid")

proc main() {.axiomEffect: IoEffect.} =
  let params = commandLineParams()
  if params.len < 1:
    stderr.writeLine("Usage: baseline_manager <update|drift|validate> [gateId]")
    quit(1)

  let repoRoot = getCurrentDir()
  let cmd = params[0]

  case cmd
  of "update":
    if params.len < 2:
      stderr.writeLine("Usage: baseline_manager update <gateId>")
      quit(1)
    updateBaseline(repoRoot, params[1])
  of "drift":
    if params.len < 2:
      stderr.writeLine("Usage: baseline_manager drift <gateId>")
      quit(1)
    showDrift(repoRoot, params[1])
  of "validate":
    validateBaselines(repoRoot)
  else:
    stderr.writeLine(&"Unknown command: {cmd}")
    quit(1)

main()
{.pop.}
