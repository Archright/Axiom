import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}

import core/axiom_pragmas
import core/trusted/env_access
import core/utils/repo_root
import gate/policy_loader
import gate_admin_validate
import std/json
import std/os
import std/osproc
import std/strutils
import std/times
# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

let
  axiomRootDir = findRepoRoot()
  statePath = axiomRootDir / ".axiom" / "gate_admin_state.json"
  logPath = axiomRootDir / "logs" / "gate_admin.jsonl"
  historyPath = getHomeDir() / ".axiom" / "gate_history.jsonl"

# Make log path available to validation submodule
gate_admin_validate.overrideLogPath = logPath

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
proc stderrOut(s: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  writeLine(stderr, s)
proc getTimestamp(): string =
  format(now().utc, "yyyy-MM-dd'T'HH:mm:ss'Z'")
proc getcurrentUser(): string {.raises: [].} =
  let user = getAxiomEnv(evUser)
  if user.len > 0: user
  else: "unknown"

proc isEnabled(state: JsonNode; gateId: string): bool {.raises: [].} =
  try:
    if not state.hasKey("gates"):
      return false
    let gates = state["gates"]
    if not gates.hasKey(gateId):
      return false
    let entry = gates[gateId]
    if not entry.hasKey("enabled"):
      return false
    entry["enabled"].getBool()
  except KeyError:
    false

proc logAction(action, gateId: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let dir = parentDir(logPath)
  if not dirExists(dir):
    createDir(dir)
  let entry = %*{
    "timestamp": getTimestamp(),
    "action": action,
    "gateId": gateId,
    "user": getcurrentUser()
  }
  var f = open(logPath, fmAppend)
  defer: f.close()
  f.write($entry & "\n")
proc loadGateIdsFromManifest(): seq[string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result = @[]
  for g in allGates():
    result.add(g.id)

# ---------------------------------------------------------------------------
# State management
# ---------------------------------------------------------------------------
proc loadState(): JsonNode {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if fileExists(statePath):
    return parseJson(readFile(statePath))
  %*{"gates": {}}
proc saveState(state: JsonNode) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let dir = parentDir(statePath)
  if not dirExists(dir):
    createDir(dir)
  writeFile(statePath, $state)
# ---------------------------------------------------------------------------
# History
# ---------------------------------------------------------------------------
proc getLastStatus(gateId: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if not fileExists(historyPath):
    return "unknown"
  let content = readFile(historyPath)
  var lastStatus = "unknown"
  for line in content.splitLines():
    let trimmed = line.strip()
    if trimmed.len == 0:
      continue
    try:
      let entry = parseJson(trimmed)
      if entry.hasKey("gateId") and entry["gateId"].getStr() == gateId:
        if entry.hasKey("status"):
          lastStatus = entry["status"].getStr()
    except JsonParsingError:
      discard
  lastStatus

# ---------------------------------------------------------------------------
# Validate — thin wrappers around gate_admin_validate
# ---------------------------------------------------------------------------
proc cmdValidate(cmd: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Validate a Bash command. Exit 2 on block, 0 on allow.
  let rc = validateCommand(cmd)
  if rc != 0:
    stderrOut("[gate_admin] BLOCKED: no-op/repeated Bash command. Use Read/Grep/Glob/MCP tools instead.")
  quit(rc)
proc cmdValidateStdin() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read JSON from stdin, extract tool_input.command, and validate it.
  let rc = validateStdin()
  if rc != 0:
    stderrOut("[gate_admin] BLOCKED: no-op/repeated Bash command. Use Read/Grep/Glob/MCP tools instead.")
  quit(rc)

# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------
proc cmdList() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let gateIds = loadGateIdsFromManifest()
  let state = loadState()
  if gateIds.len == 0:
    stderrOut("No gates found in manifest.")
    quit(1)
  for gid in gateIds:
    let enabled = isEnabled(state, gid)
    let label = if enabled: "enabled" else: "disabled"
    echo gid & " [" & label & "]"
proc cmdStatus(gateId: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let status = getLastStatus(gateId)
  echo gateId & ": " & status
proc cmdEnable(gateId: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var state = loadState()
  if not state.hasKey("gates"):
    state["gates"] = %*{}
  state["gates"][gateId] = %*{"enabled": true}
  saveState(state)
  logAction("enable", gateId)
  echo "Enabled: " & gateId
proc cmdDisable(gateId: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var state = loadState()
  if not state.hasKey("gates"):
    state["gates"] = %*{}
  state["gates"][gateId] = %*{"enabled": false}
  saveState(state)
  logAction("disable", gateId)
  echo "Disabled: " & gateId

# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------
proc cmdSelfTest() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  stderrOut("gate_admin --self-test")
  stderrOut("=".repeat(50))
  var passed = 0
  var failed = 0

  # Test 1: Load and validate policy_schema.json
  stderrOut("  [1] Loading policy_schema.json ...")
  try:
    let policy = loadPolicy()
    if policy.ruleCount() > 0:
      stderrOut("    OK — " & $policy.ruleCount() & " rules loaded")
      inc(passed)
    else:
      stderrOut("    FAIL — no rules found")
      inc(failed)
  except CatchableError as e:
    stderrOut("    FAIL — " & e.msg)
    inc(failed)

  # Test 2: Load gate IDs from manifest
  stderrOut("  [2] Loading gate IDs from manifest ...")
  let gateIds = loadGateIdsFromManifest()
  if gateIds.len > 0:
    stderrOut("    OK — " & $gateIds.len & " gates found")
    inc(passed)
  else:
    stderrOut("    FAIL — no gates found")
    inc(failed)

  # Test 3: Status query returns "unknown" for non-existent gate
  stderrOut("  [3] Status query for non-existent gate ...")
  let status = getLastStatus("__nonexistent_gate__")
  if status == "unknown":
    stderrOut("    OK — returned 'unknown'")
    inc(passed)
  else:
    stderrOut("    FAIL — returned '" & status & "'")
    inc(failed)

  # Test 4: Enable/disable cycle
  let testGate = "__test_gate_admin__"
  stderrOut("  [4] Enable/disable cycle for '" & testGate & "' ...")
  try:
    cmdEnable(testGate)
    let state1 = loadState()
    if isEnabled(state1, testGate):
      cmdDisable(testGate)
      let state2 = loadState()
      if not isEnabled(state2, testGate):
        stderrOut("    OK — enable/disable cycle works")
        inc(passed)
      else:
        stderrOut("    FAIL — gate still enabled after disable")
        inc(failed)
    else:
      stderrOut("    FAIL — gate not enabled after enable")
      inc(failed)
    # Clean up test state
    var state = loadState()
    if state.hasKey("gates") and state["gates"].hasKey(testGate):
      state["gates"].delete(testGate)
      saveState(state)
  except CatchableError as e:
    stderrOut("    FAIL — " & e.msg)
    inc(failed)

  # Test 5: Query rules for a gate
  stderrOut("  [5] Query rules for a gate ...")
  try:
    let policy = loadPolicy()
    var foundAny = false
    for gid in gateIds:
      let rules = policy.getRulesForGate(gid)
      if rules.len > 0:
        foundAny = true
        break
    if foundAny:
      stderrOut("    OK — rules found for at least one gate")
    else:
      stderrOut("    OK — no gate-linked rules (schema has no gateIds yet)")
    inc(passed)
  except CatchableError as e:
    stderrOut("    FAIL — " & e.msg)
    inc(failed)

  # Test 6: validate ':' → blocked (exit 2)
  stderrOut("  [6] validate ':' (no-op colon) ...")
  let colonResult = execCmdEx("bin/gate_admin validate ':'")
  if colonResult.exitCode == 2:
    stderrOut("    OK — blocked with exit 2")
    inc(passed)
  else:
    stderrOut("    FAIL — expected exit 2, got " & $colonResult.exitCode)
    inc(failed)

  # Test 7: validate 'bin/gate_hook pre-commit' → allowed (exit 0)
  stderrOut("  [7] validate 'bin/gate_hook pre-commit' (real command) ...")
  let realResult = execCmdEx("bin/gate_admin validate 'bin/gate_hook pre-commit'")
  if realResult.exitCode == 0:
    stderrOut("    OK — allowed with exit 0")
    inc(passed)
  else:
    stderrOut("    FAIL — expected exit 0, got " & $realResult.exitCode)
    inc(failed)

  # Test 8: validate '' → blocked (exit 2)
  stderrOut("  [8] validate '' (empty command) ...")
  let emptyResult = execCmdEx("bin/gate_admin validate ''")
  if emptyResult.exitCode == 2:
    stderrOut("    OK — blocked with exit 2")
    inc(passed)
  else:
    stderrOut("    FAIL — expected exit 2, got " & $emptyResult.exitCode)
    inc(failed)

  # Test 9: validate 'true' → blocked (exit 2)
  stderrOut("  [9] validate 'true' (shell no-op) ...")
  let trueResult = execCmdEx("bin/gate_admin validate 'true'")
  if trueResult.exitCode == 2:
    stderrOut("    OK — blocked with exit 2")
    inc(passed)
  else:
    stderrOut("    FAIL — expected exit 2, got " & $trueResult.exitCode)
    inc(failed)

  # Test 10: validate 'echo' → blocked (exit 2)
  stderrOut("  [10] validate 'echo' (shell no-op) ...")
  let echoResult = execCmdEx("bin/gate_admin validate 'echo'")
  if echoResult.exitCode == 2:
    stderrOut("    OK — blocked with exit 2")
    inc(passed)
  else:
    stderrOut("    FAIL — expected exit 2, got " & $echoResult.exitCode)
    inc(failed)

  stderrOut("")
  stderrOut("Results: " & $passed & " passed, " & $failed & " failed")
  stderrOut("=".repeat(50))
  if failed > 0:
    quit(1)
  quit(0)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

when isMainModule:
  if paramCount() < 1:
    stderrOut("Usage: gate_admin <command> [args]")
    stderrOut("Commands: list, status <gate-id>, enable <gate-id>, disable <gate-id>,")
    stderrOut("          validate <command>, --validate-stdin, --self-test")
    stderrOut("")
    stderrOut("Options:")
    stderrOut("  validate <command>   Validate a Bash command (exit 0=allow, 2=block)")
    stderrOut("  --validate-stdin     Read JSON from stdin, extract tool_input.command, validate")
    quit(1)

  let cmd = paramStr(1)
  case cmd
  of "--self-test":
    cmdSelfTest()
  of "list":
    cmdList()
  of "status":
    if paramCount() < 2:
      stderrOut("Usage: gate_admin status <gate-id>")
      quit(1)
    cmdStatus(paramStr(2))
  of "enable":
    if paramCount() < 2:
      stderrOut("Usage: gate_admin enable <gate-id>")
      quit(1)
    cmdEnable(paramStr(2))
  of "disable":
    if paramCount() < 2:
      stderrOut("Usage: gate_admin disable <gate-id>")
      quit(1)
    cmdDisable(paramStr(2))
  of "validate":
    if paramCount() < 2:
      stderrOut("Usage: gate_admin validate <command>")
      quit(1)
    cmdValidate(paramStr(2))
  of "--validate-stdin":
    cmdValidateStdin()
  else:
    stderrOut("Unknown command: " & cmd)
    quit(1)

{.pop.}
