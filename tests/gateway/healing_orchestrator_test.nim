## healing_orchestrator_test.nim — Gateway test for healing orchestrator.
##
## Scenario 1: Self-test mode validates all 3 gates with synthetic data.
## Scenario 2: Full pipeline processes proof state and writes gate_history.

import std/[json, os, strutils]
import verification/orchestrator/healing_orchestrator
from core/utils/repo_root import findRepoRoot

# axiomIoBoundary

let
  projectRoot = findRepoRoot()
  historyPath = getHomeDir() / ".axiom" / "gate_history.jsonl"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc cleanupHistory() =
  ## Remove any healing-orchestrator entries from gate_history for test isolation.
  if not fileExists(historyPath):
    return
  let content = readFile(historyPath)
  var kept: seq[string] = @[]
  for line in content.splitLines():
    let trimmed = line.strip()
    if trimmed.len == 0:
      continue
    try:
      let entry = parseJson(trimmed)
      let gateId = entry{"gateId"}.getStr("")
      if gateId != GateId:
        kept.add(trimmed)
    except CatchableError:
      kept.add(trimmed)
  writeFile(historyPath, kept.join("\n") & "\n")

# ---------------------------------------------------------------------------
# Scenario 1: Self-test validates 3-gate pipeline
# ---------------------------------------------------------------------------

proc scenarioSelfTest() =
  ## The --self-test binary mode runs 11 internal checks.
  ## This scenario verifies it passes.
  cleanupHistory()
  let exitCode = runSelfTest()
  doAssert exitCode == 0,
    "healing-orchestrator --self-test failed with exit code " & $exitCode

# ---------------------------------------------------------------------------
# Scenario 2: Full pipeline with synthetic proof state
# ---------------------------------------------------------------------------

proc scenarioFullPipeline() =
  ## Create a synthetic proof state with one failing node,
  ## run the pipeline, and verify gate_history.jsonl is written.
  cleanupHistory()

  # Write synthetic proof state
  let proofDir = projectRoot / "logs"
  if not dirExists(proofDir):
    createDir(proofDir)
  let proofPath = proofDir / "ax_proof_state.json"
  let synthetic = %*{
    "summary": {"verificationCompletionRate": 50.0},
    "verificationQueue": [
      {
        "nodeId": "solver/construct_arithmetic.nim::add",
        "label": "construct_arithmetic.nim::add",
        "interfaceDistance": 0,
        "topologyScore": 100,
        "centralityScore": 90,
        "couplingScore": 80,
        "complexityScore": 5,
        "childNodeCount": 0,
        "dependentNodeCount": 10,
        "branchCount": 2,
        "nestingDepth": 3,
        "logicalDepth": 2,
        "diagnosticLabels": ["type_mismatch", "result"],
        "remediationHint": "result = add(x, y) when no_overflow",
        "mathematicalRationale": "line 42: `result` depends on `x` and `y` values, overflow bound at `max_val`"
      },
      {
        "nodeId": "core/parser.nim::parse_ok",
        "label": "parser.nim::parse_ok",
        "interfaceDistance": 1,
        "topologyScore": 50,
        "centralityScore": 40,
        "couplingScore": 30,
        "complexityScore": 2,
        "childNodeCount": 0,
        "dependentNodeCount": 5,
        "branchCount": 0,
        "nestingDepth": 1,
        "logicalDepth": 1,
        "diagnosticLabels": [],
        "remediationHint": "",
        "mathematicalRationale": ""
      }
    ],
    "structuralBottlenecks": [],
    "repairPriorityDependencies": [],
    "diagnostics": []
  }
  writeFile(proofPath, $synthetic)

  # Run pipeline (not self-test — reads actual proof state file)
  let exitCode = runHealingPipeline(projectRoot, selfTest = false)

  # The failing node has a good hint (has symbols, line refs, non-vacuous)
  # so the pipeline should pass
  doAssert exitCode == 0,
    "Full pipeline should pass for well-formed hint, got exit=" & $exitCode

  # Verify gate_history.jsonl was written
  doAssert fileExists(historyPath),
    "gate_history.jsonl should exist after pipeline run"

  # Verify status entry
  var foundStatus = false
  let historyContent = readFile(historyPath)
  for line in historyContent.splitLines():
    let trimmed = line.strip()
    if trimmed.len == 0:
      continue
    try:
      let entry = parseJson(trimmed)
      if entry.hasKey("gateId") and entry["gateId"].getStr() == GateId:
        if entry.hasKey("status") and entry["status"].getStr() == "pass":
          foundStatus = true
    except CatchableError:
      discard
  doAssert foundStatus,
    "gate_history.jsonl should contain a pass status for healing-orchestrator"

  # Cleanup
  cleanupHistory()
  if fileExists(proofPath):
    removeFile(proofPath)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

when isMainModule:
  scenarioSelfTest()
  scenarioFullPipeline()
  echo "All healing_orchestrator tests passed."
