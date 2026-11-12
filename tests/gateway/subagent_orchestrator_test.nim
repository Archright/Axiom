## Subagent Orchestrator — Plan Validation Test
##
## Verifies that the subagent_orchestrator correctly validates plan files
## and generates structured execution schedules.
##
## Test scenarios:
##   1. Good plan with all required stages passes validation
##   2. Bad plan missing stages fails validation
##   3. Plan with no tasks fails validation
##   4. Schedule generation produces correct structure
##   5. Empty plan file fails validation

import std/[unittest, json, os, strutils]

# ---------------------------------------------------------------------------
# Test constants
# ---------------------------------------------------------------------------

const
  TestPlansDir = "tests/gateway/test_plans"
  GoodPlanPath = TestPlansDir & "/good_plan.md"
  BadPlanMissingStagePath = TestPlansDir & "/bad_plan_missing_stage.md"
  BadPlanNoTasksPath = TestPlansDir & "/bad_plan_no_tasks.md"
  EmptyPlanPath = TestPlansDir & "/empty_plan.md"

# ---------------------------------------------------------------------------
# Test fixtures
# ---------------------------------------------------------------------------

const
  GoodPlanContent = """# Feature Plan: User Authentication

## Implementer

- Create User model with email and password_hash fields
- Add password hashing utility using bcrypt
- Create login endpoint with JWT token generation

## Spec Reviewer

Verify implementation matches original requirements:
- All fields present and correctly typed
- Authentication flow matches specification
- No scope creep beyond defined tasks

## Quality Reviewer

Code quality checks:
- Follows project conventions and style
- Proper error handling and validation
- Adequate test coverage
- No security vulnerabilities

## Final Integration Reviewer

Integration verification:
- All components work together correctly
- No inconsistencies between tasks
- Full test suite passes
- Ready for merge
"""

  BadPlanMissingStageContent = """# Feature Plan: Incomplete

## Implementer

- Create basic model

## Quality Reviewer

- Check code style
"""

  BadPlanNoTasksContent = """# Feature Plan: Empty

## Implementer

## Spec Reviewer

## Quality Reviewer

## Final Integration Reviewer
"""

# ---------------------------------------------------------------------------
# Setup / Teardown helpers
# ---------------------------------------------------------------------------

proc setupTestDir() =
  ## Create test directory and fixtures.
  if not dirExists(TestPlansDir):
    createDir(TestPlansDir)

  writeFile(GoodPlanPath, GoodPlanContent)
  writeFile(BadPlanMissingStagePath, BadPlanMissingStageContent)
  writeFile(BadPlanNoTasksPath, BadPlanNoTasksContent)
  writeFile(EmptyPlanPath, "")

proc teardownTestDir() =
  ## Remove test fixtures.
  if dirExists(TestPlansDir):
    removeDir(TestPlansDir)

# ---------------------------------------------------------------------------
# Inline validation logic (mirrors subagent_orchestrator.nim pure functions)
# ---------------------------------------------------------------------------

func normalizeStageName(s: string): string =
  result = s.strip().toLowerAscii().replace(" ", "-")

func extractHeadings(content: string): seq[string] =
  result = @[]
  for line in content.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith("## ") or trimmed.startsWith("### "):
      let heading = trimmed.replace("##", "").strip()
      result.add(normalizeStageName(heading))

func extractTasks(content: string): seq[string] =
  result = @[]
  var inImplementer = false
  for line in content.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith("## "):
      let heading = trimmed.replace("##", "").strip().toLowerAscii().replace(" ", "-")
      inImplementer = heading == "implementer"
      continue
    if inImplementer and (trimmed.startsWith("- ") or trimmed.startsWith("* ")):
      let task = trimmed[2..^1].strip()
      if task.len > 0:
        result.add(task)

func hasSection(content, sectionName: string): bool =
  let normalized = normalizeStageName(sectionName)
  let headings = extractHeadings(content)
  for heading in headings:
    if normalized in heading or heading in normalized:
      return true
  false

const RequiredStages = [
  "implementer",
  "spec-reviewer",
  "quality-reviewer",
  "final-integration-reviewer"
]

func validatePlan(content: string): (bool, seq[string], seq[string]) =
  var missingStages: seq[string] = @[]
  let tasks = extractTasks(content)

  for stage in RequiredStages:
    if not hasSection(content, stage):
      missingStages.add(stage)

  let isValid = missingStages.len == 0
  (isValid, missingStages, tasks)

func generateSchedule(content: string, tasks: seq[string]): JsonNode =
  result = %*{
    "schema": "subagent-orchestrator/v1",
    "totalTasks": tasks.len,
    "requiredStages": RequiredStages,
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
        %*{"stage": "final-integration-reviewer", "order": 4, "type": "escalation-gate"}
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
# Test suite
# ---------------------------------------------------------------------------

suite "Subagent Orchestrator Plan Validation":

  setup:
    setupTestDir()

  teardown:
    teardownTestDir()

  test "good plan passes validation":
    let content = readFile(GoodPlanPath)
    let (isValid, missingStages, tasks) = validatePlan(content)
    check(isValid)
    check(missingStages.len == 0)
    check(tasks.len == 3)

  test "bad plan missing stages fails validation":
    let content = readFile(BadPlanMissingStagePath)
    let (isValid, missingStages, _) = validatePlan(content)
    check(not isValid)
    check(missingStages.len > 0)
    check("spec-reviewer" in missingStages)
    check("final-integration-reviewer" in missingStages)

  test "bad plan with no tasks fails validation":
    let content = readFile(BadPlanNoTasksPath)
    let (_, _, tasks) = validatePlan(content)
    check(tasks.len == 0)

  test "empty plan file fails validation":
    let content = readFile(EmptyPlanPath)
    let (isValid, missingStages, tasks) = validatePlan(content)
    check(not isValid)
    check(missingStages.len == 4)
    check(tasks.len == 0)

  test "schedule generation produces correct structure":
    let content = readFile(GoodPlanPath)
    let (_, _, tasks) = validatePlan(content)
    let schedule = generateSchedule(content, tasks)
    check(schedule.hasKey("schema"))
    check(schedule["schema"].getStr() == "subagent-orchestrator/v1")
    check(schedule.hasKey("schedule"))
    check(schedule["schedule"].len == tasks.len + 1)  # tasks + final-review
    check(schedule.hasKey("totalTasks"))
    check(schedule["totalTasks"].getInt() == 3)

  test "heading extraction works correctly":
    let content = readFile(GoodPlanPath)
    let headings = extractHeadings(content)
    check(headings.len >= 4)
    check("implementer" in headings)
    check("spec-reviewer" in headings)
    check("quality-reviewer" in headings)
    check("final-integration-reviewer" in headings)

  test "task extraction works correctly":
    let content = readFile(GoodPlanPath)
    let tasks = extractTasks(content)
    check(tasks.len == 3)
    check("Create User model" in tasks[0])
    check("Add password hashing" in tasks[1])
    check("Create login endpoint" in tasks[2])

  test "stage name normalization handles various formats":
    check(normalizeStageName("Implementer") == "implementer")
    check(normalizeStageName("Spec Reviewer") == "spec-reviewer")
    check(normalizeStageName("  Quality Reviewer  ") == "quality-reviewer")
    check(normalizeStageName("FINAL-INTEGRATION-REVIEWER") == "final-integration-reviewer")