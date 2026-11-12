## axiom_task.nim — Universal task interface for CLI, MCP, orchestrator.
##
## Unifies the 3-way type split (task_schema, task_dag, runner_common)
## behind a single concept + runtime types.
##
## Architecture: Runtime module in src/core/runtime/.
## Imports: std/*, core/types/results, core/schema/task_schema (SOC-compliant).

import core/trusted/layer_declaration
axiomLayer "domain"
import std/[tables, times]
import core/types/results
import core/schema/task_schema
{.push raises: [].}

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  IoExecutor* = proc(cmd: string, args: seq[string],
                      input: string = ""): Result[string, string] {.gcsafe.}
    ## Abstract I/O executor — wraps subprocess calls behind a pure interface.

  RuntimeContext* = object
    ## Centralized context replacing scattered parameters.
    ioExec*: IoExecutor
    repoRoot*: string
    verbose*: bool
    dryRun*: bool
    timeout*: Duration

  TaskResult* = object
    ## Standardized task execution output.
    taskId*: TaskId
    state*: TaskState
    output*: string
    violations*: seq[string]
    duration*: Duration
    timestamp*: DateTime

# ---------------------------------------------------------------------------
# AxiomTask Concept
# ---------------------------------------------------------------------------

type
  AxiomTask* = concept t
    ## Universal task interface — any type satisfying this concept
    ## can be scheduled by the DAG engine regardless of origin
    ## (CLI gate runner, MCP handler, orchestrator spec).
    t.id is TaskId
    t.title is string
    t.state is TaskState
    t.deps is seq[TaskId]
    t.resourceClass is ResourceClass
    t.costWeight is float
    t.blockedBy is seq[TaskId]
    t.execute(RuntimeContext) is TaskResult
    t.canRun(Table[TaskId, TaskState]) is bool

# ---------------------------------------------------------------------------
# TaskResult Constructors
# ---------------------------------------------------------------------------

func ok*(taskId: TaskId, output: string = ""): TaskResult {.gcsafe, raises: [].} =
  ## Construct a successful TaskResult.
  TaskResult(taskId: taskId, state: tsCompleted, output: output, timestamp: now())

func fail*(taskId: TaskId, violations: seq[string]): TaskResult {.gcsafe, raises: [].} =
  ## Construct a failed TaskResult with violation details.
  TaskResult(taskId: taskId, state: tsFailed, violations: violations, timestamp: now())

# ---------------------------------------------------------------------------
# Dependency Resolution
# ---------------------------------------------------------------------------

func canRun*(deps: seq[TaskId], blockedBy: seq[TaskId],
             completed: Table[TaskId, TaskState]): bool {.gcsafe, raises: [].} =
  ## Check if a task can run given the current completion state.
  ## Returns false if any dependency is incomplete or any blocker is active.
  for dep in deps:
    if completed.getOrDefault(dep) != tsCompleted:
      return false
  for blocker in blockedBy:
    if completed.getOrDefault(blocker) in {tsRunning, tsFailed}:
      return false
  true

{.pop}
