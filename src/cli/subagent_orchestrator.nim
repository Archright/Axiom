## subagent_orchestrator.nim — Deterministic Plan Validation & Execution Schedule
##
## Converts the subagent-driven-development skill into deterministic infrastructure.
## Reads a plan markdown file, validates required review stages, and outputs a
## structured JSON execution schedule.
##
## Usage:
##   bin/subagent-orchestrator <plan-file>          — validate plan and output schedule
##   bin/subagent-orchestrator --self-test          — run built-in validation tests
##   bin/subagent-orchestrator --self-test-plan <path>  — validate a specific plan file
##
## Exit codes:
##   0  success (or debug mode active / bypass token set)
##   1  validation failure or error

import core/trusted/layer_declaration
axiomLayer "presentation"
import core/axiom_pragmas
import core/utils/repo_root
import gate/debug_mode_state
import std/json
import std/os
import std/strutils
import std/times
# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const
  GATE_ID = "subagent-orchestrator"
  HISTORY_PATH = ".axiom/gate_history.jsonl"
  REQUIRED_STAGES = [
    "implementer",
    "spec-reviewer",
    "quality-reviewer",
    "final-integration-reviewer"
  ]
  # Templates embedded at compile time via staticRead
  GOOD_PLAN_TEMPLATE = staticRead("config/templates/good_plan.md")
  BAD_PLAN_TEMPLATE_MISSING_STAGE = staticRead("config/templates/bad_plan_missing_stage.md")
  BAD_PLAN_TEMPLATE_NO_TASKS = staticRead("config/templates/bad_plan_no_tasks.md")
# ---------------------------------------------------------------------------
# Self-Test
# ---------------------------------------------------------------------------
proc stderrOut(s: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  writeLine(stderr, s)
proc getTimestamp(): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  format(now().utc, "yyyy-MM-dd'T'HH:mm:ss'Z'")
# ---------------------------------------------------------------------------
# Gate History
# ---------------------------------------------------------------------------
proc normalizeStageName(s: string): string =
  ## Normalize stage names for matching (lowercase, strip, replace spaces with hyphens).
  result = s.strip().toLowerAscii().replace(" ", "-")

# ---------------------------------------------------------------------------
# Gate History
# ---------------------------------------------------------------------------
proc writeGateHistory(ruleId, severity, filePath, message: string; line: int = 0) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Write failure entry to ~/.axiom/gate_history.jsonl
  let dir = parentDir(HISTORY_PATH)
  if not dirExists(dir):
    createDir(dir)
  let entry = %*{
    "timestamp": getTimestamp(),
    "gateId": GATE_ID,
    "ruleId": ruleId,
    "severity": severity,
    "filePath": filePath,
    "line": line,
    "message": message,
    "bypassUsed": false
  }
  var f = open(HISTORY_PATH, fmAppend)
  try:
    f.writeLine($entry)
  finally:
    f.close()
# ---------------------------------------------------------------------------
# Execution Schedule Generation
# ---------------------------------------------------------------------------
proc extractHeadings(content: string): seq[string] =
  ## Extract all markdown headings (## and ###) from content.
  ## Returns normalized heading text.
  result = @[]
  for line in content.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith("## ") or trimmed.startsWith("### "):
      let heading = trimmed.replace("##", "").strip()
      result.add(normalizeStageName(heading))
proc extractTasks(content: string): seq[string] =
  ## Extract task items from the Implementer section only.
  ## Only list items under ## Implementer heading are considered implementation tasks.
  result = @[]
  var inImplementer = false
  for line in content.splitLines():
    let trimmed = line.strip()
    # Check for section headings
    if trimmed.startsWith("## "):
      let heading = trimmed.replace("##", "").strip().toLowerAscii().replace(" ", "-")
      inImplementer = heading == "implementer"
      continue
    # Extract tasks only from Implementer section
    if inImplementer and (trimmed.startsWith("- ") or trimmed.startsWith("* ")):
      let task = trimmed[2..^1].strip()
      if task.len > 0:
        result.add(task)
proc hasSection(content, sectionName: string): bool =
  ## Check if content contains a section with the given name.
  let normalized = normalizeStageName(sectionName)
  let headings = extractHeadings(content)
  for heading in headings:
    if normalized in heading or heading in normalized:
      return true
  false
proc validatePlan(content: string): (bool, seq[string], seq[string]) =
  ## Validate plan content against required stages.
  ## Returns (isValid, missingStages, foundTasks).
  var missingStages: seq[string] = @[]
  let tasks = extractTasks(content)

  for stage in REQUIRED_STAGES:
    if not hasSection(content, stage):
      missingStages.add(stage)

  let isValid = missingStages.len == 0
  (isValid, missingStages, tasks)

# ---------------------------------------------------------------------------
# Execution Schedule Generation
# ---------------------------------------------------------------------------
proc generateSchedule(content: string, tasks: seq[string]): JsonNode =
  ## Generate a structured execution schedule as JSON.
  result = %*{
    "schema": "subagent-orchestrator/v1",
    "generatedAt": getTimestamp(),
    "totalTasks": tasks.len,
    "requiredStages": REQUIRED_STAGES,
    "schedule": newJArray()
  }

  for i, task in tasks:
    let taskNode = %*{
      "taskId": "task-" & $(i + 1),
      "taskContent": task,
      "stages": [
        %*{"stage": "implementer", "order": 1, "type": "execution"},
        %*{"stage": "spec-reviewer", "order": 2, "type": "revision-gate"},
        %*{"stage": "quality-reviewer", "order": 3, "type": "revision-gate"},
        %*{"stage": "final-integration-reviewer", "order": 4, "type": "escalation-gate", "condition": "all-tasks-complete"}
      ]
    }
    result["schedule"].add(taskNode)

  # Add post-execution review
  result["schedule"].add(%*{
    "taskId": "final-review",
    "taskContent": "Final integration review of all tasks",
    "stages": [
      %*{"stage": "final-integration-reviewer", "order": 1, "type": "escalation-gate"}
    ]
  })

# ---------------------------------------------------------------------------
# Self-Test Templates
# ---------------------------------------------------------------------------
proc getGoodPlan(): string = GOOD_PLAN_TEMPLATE
proc getBadPlanMissingStage(): string = BAD_PLAN_TEMPLATE_MISSING_STAGE
proc getBadPlanNoTasks(): string = BAD_PLAN_TEMPLATE_NO_TASKS

# ---------------------------------------------------------------------------
# Self-Test
# ---------------------------------------------------------------------------
proc cmdSelfTest(projectRoot: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Run built-in validation tests.
  stderrOut("subagent-orchestrator --self-test")
  stderrOut("=".repeat(60))
  var passed = 0
  var failed = 0

  proc check(condition: bool; desc: string) =
    if not condition:
      stderrOut("  FAIL: " & desc)
      inc failed
    else:
      stderrOut("  PASS: " & desc)
      inc passed

  # Test 1: Validate good plan template
  stderrOut("\n[1] Good plan template validation:")
  let goodPlan = getGoodPlan()
  let (isValid, missingStages, tasks) = validatePlan(goodPlan)
  check(isValid, "Good plan passes validation")
  check(missingStages.len == 0, "No missing stages in good plan")
  check(tasks.len > 0, "Tasks extracted from good plan (" & $tasks.len & " found)")

  # Test 2: Bad plan (missing stage) should fail
  stderrOut("\n[2] Bad plan (missing stage) validation:")
  let badPlan1 = getBadPlanMissingStage()
  let (isValid1, missing1, _) = validatePlan(badPlan1)
  check(not isValid1, "Bad plan fails validation")
  check(missing1.len > 0, "Missing stages detected (" & $missing1.len & " missing)")
  check("spec-reviewer" in missing1, "spec-reviewer correctly identified as missing")
  check("final-integration-reviewer" in missing1, "final-integration-reviewer correctly identified as missing")

  # Test 3: Bad plan (no tasks) should fail
  stderrOut("\n[3] Bad plan (no tasks) validation:")
  let badPlan2 = getBadPlanNoTasks()
  let (_, _, tasks2) = validatePlan(badPlan2)
  check(tasks2.len == 0, "No tasks extracted from empty plan")

  # Test 4: Schedule generation
  stderrOut("\n[4] Schedule generation:")
  let schedule = generateSchedule(goodPlan, tasks)
  check(schedule.hasKey("schema"), "Schedule has schema field")
  check(schedule["schema"].getStr() == "subagent-orchestrator/v1", "Schema version correct")
  check(schedule.hasKey("schedule"), "Schedule has schedule field")
  check(schedule["schedule"].len > 0, "Schedule has entries")
  check(schedule.hasKey("totalTasks"), "Schedule has totalTasks field")

  # Test 5: Normalize stage names
  stderrOut("\n[5] Stage name normalization:")
  check(normalizeStageName("Implementer") == "implementer", "Implementer normalizes")
  check(normalizeStageName("Spec Reviewer") == "spec-reviewer", "Spec Reviewer normalizes")
  check(normalizeStageName("  Quality Reviewer  ") == "quality-reviewer", "Quality Reviewer normalizes with spaces")

  # Test 6: Heading extraction
  stderrOut("\n[6] Heading extraction:")
  let headings = extractHeadings(goodPlan)
  check(headings.len >= 4, "At least 4 headings extracted")

  # Test 7: Debug mode check
  stderrOut("\n[7] Debug mode check:")
  let debugActive = isDebugModeActive(projectRoot)
  if debugActive:
    stderrOut("  INFO: Debug mode is active (would exit 0 on failure)")
  else:
    stderrOut("  INFO: Debug mode is inactive")
  passed += 1  # This is informational, always passes

  # Test 8: Gate history write
  stderrOut("\n[8] Gate history write:")
  try:
    writeGateHistory("test-rule", "info", "test.nim", "Self-test verification")
    check(fileExists(HISTORY_PATH), "Gate history file exists")
    passed += 1
  except CatchableError as e:
    stderrOut("  FAIL: " & e.msg)
    inc failed

  # Summary
  stderrOut("\n" & "=".repeat(60))
  stderrOut("Results: " & $passed & " passed, " & $failed & " failed")
  stderrOut("=".repeat(60))
  if failed > 0:
    quit(1)
  quit(0)

# ---------------------------------------------------------------------------
# Plan File Validation
# ---------------------------------------------------------------------------
proc validatePlanFile(projectRoot: string; planPath: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Validate a plan file and output execution schedule.
  let debugActive = isDebugModeActive(projectRoot)

  # Pre-flight gate: file exists?
  if not fileExists(planPath):
    let msg = "Plan file not found: " & planPath
    if debugActive:
      stderrOut("[subagent-orchestrator] DEBUG: " & msg)
      quit(0)
    stderrOut("[subagent-orchestrator] ERROR: " & msg)
    writeGateHistory("plan-file-exists", "error", planPath, msg)
    quit(1)

  # Read and parse plan
  let content = readFile(planPath)
  if content.strip().len == 0:
    let msg = "Plan file is empty: " & planPath
    if debugActive:
      stderrOut("[subagent-orchestrator] DEBUG: " & msg)
      quit(0)
    stderrOut("[subagent-orchestrator] ERROR: " & msg)
    writeGateHistory("plan-not-empty", "error", planPath, msg)
    quit(1)

  # Validate plan
  let (isValid, missingStages, tasks) = validatePlan(content)

  if not isValid:
    let msg = "Plan missing required stages: " & missingStages.join(", ")
    if debugActive:
      stderrOut("[subagent-orchestrator] DEBUG: " & msg)
      stderrOut("[subagent-orchestrator] DEBUG: Required stages are: " & REQUIRED_STAGES.join(", "))
      quit(0)
    stderrOut("[subagent-orchestrator] ERROR: " & msg)
    for stage in missingStages:
      writeGateHistory("required-stage", "error", planPath, "Missing stage: " & stage)
    quit(1)

  if tasks.len == 0:
    let msg = "Plan contains no tasks (no list items found)"
    if debugActive:
      stderrOut("[subagent-orchestrator] DEBUG: " & msg)
      quit(0)
    stderrOut("[subagent-orchestrator] ERROR: " & msg)
    writeGateHistory("plan-has-tasks", "error", planPath, msg)
    quit(1)

  # Generate and output schedule
  let schedule = generateSchedule(content, tasks)
  echo pretty(schedule)

  # Log success
  stderrOut("[subagent-orchestrator] OK: Plan validated successfully (" & $tasks.len & " tasks)")

# ---------------------------------------------------------------------------
# Self-Test Plan Validation
# ---------------------------------------------------------------------------
proc validateSelfTestPlan(projectRoot: string; planPath: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Validate a specific plan file (for external testing).
  validatePlanFile(projectRoot, planPath)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

when isMainModule:
  let projectRoot = findRepoRoot()
  let args = commandLineParams()

  if args.len == 0:
    stderrOut("Usage: subagent-orchestrator <plan-file> | --self-test | --self-test-plan <path>")
    stderrOut("")
    stderrOut("Commands:")
    stderrOut("  <plan-file>             Validate plan and output execution schedule")
    stderrOut("  --self-test             Run built-in validation tests")
    stderrOut("  --self-test-plan <path> Validate a specific plan file")
    quit(1)

  let flag = args[0]

  case flag
  of "--self-test":
    cmdSelfTest(projectRoot)
  of "--self-test-plan":
    if args.len < 2:
      stderrOut("Usage: subagent-orchestrator --self-test-plan <plan-file>")
      quit(1)
    validateSelfTestPlan(projectRoot, args[1])
  else:
    # Treat first argument as plan file path
    validatePlanFile(projectRoot, flag)
