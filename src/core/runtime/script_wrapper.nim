import core/trusted/layer_declaration
axiomLayer "domain"
import core/runtime/axiom_task
import core/schema/task_schema
import core/types/results
import std/[tables, times]

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  ScriptKind* = enum
    skShell = "sh"
    skPython = "python3"

  ScriptWrapper* = object
    ## Strangler Fig wrapper for non-Nim scripts.
    ## When `nimEquivalent` is set, the Nim version is called directly.
    ## Otherwise, the original script is executed via subprocess.
    id*: TaskId
    title*: string
    state*: TaskState
    deps*: seq[TaskId]
    resourceClass*: ResourceClass
    costWeight*: float
    blockedBy*: seq[TaskId]
    scriptPath*: string          ## Path to original script
    scriptType*: ScriptKind      ## Interpreter to use
    nimEquivalent*: string       ## Path to Nim replacement (empty = not ported)
# ---------------------------------------------------------------------------
# Constructor
# ---------------------------------------------------------------------------

func newScriptWrapper*(
    id: TaskId, title: string, scriptPath: string,
    scriptType: ScriptKind = skShell,
    deps: seq[TaskId] = @[],
    resourceClass: ResourceClass = rcDefault,
    costWeight: float = 1.0,
    nimEquivalent: string = ""
): ScriptWrapper {.raises: [].} =
  ## Construct a new ScriptWrapper with sensible defaults.
  ScriptWrapper(
    id: id, title: title, state: tsPending, deps: deps,
    resourceClass: resourceClass, costWeight: costWeight,
    scriptPath: scriptPath, scriptType: scriptType,
    nimEquivalent: nimEquivalent
  )

# ---------------------------------------------------------------------------
# Execution (Strangler Fig dispatch)
# ---------------------------------------------------------------------------
func execute*(wrapper: ScriptWrapper, ctx: RuntimeContext): TaskResult {.raises: [].} =
  ## Execute script via Strangler Fig pattern.
  ## If nimEquivalent is set, call the Nim version directly.
  ## Otherwise, invoke the original script via interpreter subprocess.
  if wrapper.nimEquivalent.len > 0:
    # Nim port exists — call directly
    let execResult = ctx.ioExec(wrapper.nimEquivalent, @[])
    if execResult.isOk:
      TaskResult(taskId: wrapper.id, state: tsCompleted,
                 output: execResult.get(), timestamp: now())
    else:
      TaskResult(taskId: wrapper.id, state: tsFailed,
                 violations: @[execResult.error()], timestamp: now())
  else:
    # Not ported yet — invoke original script via interpreter
    let interpreter = $wrapper.scriptType
    let execResult = ctx.ioExec(interpreter, @[wrapper.scriptPath])
    if execResult.isOk:
      TaskResult(taskId: wrapper.id, state: tsCompleted,
                 output: execResult.get(), timestamp: now())
    else:
      TaskResult(taskId: wrapper.id, state: tsFailed,
                 violations: @[execResult.error()], timestamp: now())

# ---------------------------------------------------------------------------
# AxiomTask Concept Satisfiers (field accessors)
# ---------------------------------------------------------------------------
func id*(w: ScriptWrapper): TaskId = w.id
func title*(w: ScriptWrapper): string = w.title
func state*(w: ScriptWrapper): TaskState = w.state
func deps*(w: ScriptWrapper): seq[TaskId] = w.deps
func resourceClass*(w: ScriptWrapper): ResourceClass = w.resourceClass
func costWeight*(w: ScriptWrapper): float = w.costWeight
func blockedBy*(w: ScriptWrapper): seq[TaskId] = w.blockedBy
func canRun*(w: ScriptWrapper, completed: Table[TaskId, TaskState]): bool {.raises: [].} =
  ## Check if this script task can run given current DAG state.
  canRun(w.deps, w.blockedBy, completed)
