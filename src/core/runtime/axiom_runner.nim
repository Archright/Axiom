import core/trusted/layer_declaration
axiomLayer "domain"
import core/runtime/axiom_task
import core/schema/task_schema
import core/types/results
import std/[tables, times]

# ---------------------------------------------------------------------------
# GateTask Adapter
# ---------------------------------------------------------------------------

type
  GateTask* = object
    ## Adapter: wraps subprocess gate execution as an AxiomTask-compatible type.
    ## Bridges legacy gate script binaries into the unified DAG scheduler.
    ## I/O is injected via RuntimeContext.ioExec — no direct gate/ dependency.
    id*: TaskId
    title*: string
    state*: TaskState
    deps*: seq[TaskId]
    resourceClass*: ResourceClass
    costWeight*: float
    blockedBy*: seq[TaskId]
    legacyPath*: string        ## Path to legacy gate script binary
    updateBaseline*: bool
# ---------------------------------------------------------------------------
# Constructor
# ---------------------------------------------------------------------------

func newGateTask*(id: TaskId, title: string, legacyPath: string,
                  deps: seq[TaskId] = @[],
                  resourceClass: ResourceClass = rcDefault,
                  costWeight: float = 1.0,
                  updateBaseline: bool = false): GateTask {.raises: [].} =
  ## Construct a new GateTask with sensible defaults.
  GateTask(id: id, title: title, state: tsPending, deps: deps,
           resourceClass: resourceClass, costWeight: costWeight,
           legacyPath: legacyPath, updateBaseline: updateBaseline)
# ---------------------------------------------------------------------------
# Execution
# ---------------------------------------------------------------------------
func execute*(task: GateTask, ctx: RuntimeContext): TaskResult {.raises: [].} =
  ## Execute legacy gate script via RuntimeContext.ioExec (DI pattern).
  ## No direct dependency on gate/lib/runner_common — I/O is injected.
  var args: seq[string] = @[]
  if task.updateBaseline: args.add("--update-baseline")
  if ctx.verbose: args.add("--verbose")

  let execResult = ctx.ioExec(task.legacyPath, args)
  if execResult.isOk:
    TaskResult(taskId: task.id, state: tsCompleted,
               output: execResult.get(), timestamp: now())
  else:
    TaskResult(taskId: task.id, state: tsFailed,
               violations: @[execResult.error()], timestamp: now())

# ---------------------------------------------------------------------------
# AxiomTask Concept Satisfiers (field accessors)
# ---------------------------------------------------------------------------
func id*(task: GateTask): TaskId = task.id
func title*(task: GateTask): string = task.title
func state*(task: GateTask): TaskState = task.state
func deps*(task: GateTask): seq[TaskId] = task.deps
func resourceClass*(task: GateTask): ResourceClass = task.resourceClass
func costWeight*(task: GateTask): float = task.costWeight
func blockedBy*(task: GateTask): seq[TaskId] = task.blockedBy
func canRun*(task: GateTask, completed: Table[TaskId, TaskState]): bool {.raises: [].} =
  ## Check if this gate task can run given current DAG state.
  canRun(task.deps, task.blockedBy, completed)
