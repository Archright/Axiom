## dag_executor.nim — DAG execution engine with level-based parallelism
##
## Executes a TaskDag by processing topological levels sequentially.
## Within each level, independent tasks are executed via their TaskExecutor
## closures. External commands use startProcess for process-level isolation.
##
## Persistence: DAG state is saved as JSON Lines to logs/task_dag_state.jsonl
## using atomic_ops.atomicWrite for crash safety.

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}
# axiomIoBoundary

import std/[os, json, times, strutils, monotimes, tables]
import core/results
import core/boundary/axiom_pragmas_boundary
import core/task_schema
import engine/task_dag
import engine/atomic_ops

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const MaxConcurrentL2* = 4  ## Reuse from gate layer — max parallel tasks
const DefaultStatePath* = "logs/task_dag_state.jsonl"

# ---------------------------------------------------------------------------
# Persistence: JSON Lines serialization (pure helpers)
# ---------------------------------------------------------------------------

func escapeJsonString*(s: string): string {.raises: [].} =
  ## Escape a string for safe embedding in JSON.
  result = ""
  for c in s:
    case c
    of '\\': result.add("\\\\")
    of '"': result.add("\\\"")
    of '\n': result.add("\\n")
    of '\r': result.add("\\r")
    of '\t': result.add("\\t")
    else: result.add(c)

func serializeJsonArray*(items: seq[string]): string {.raises: [].} =
  ## Serialize a seq[string] to a JSON array string.
  result = "["
  for i, item in items:
    if i > 0: result.add(",")
    result.add("\"" & escapeJsonString(item) & "\"")
  result.add("]")

func serializeNodeState*(node: TaskNode): string {.raises: [].} =
  ## Serialize a TaskNode's execution state to a JSON line.
  ## Does not serialize the executor closure (not serializable).
  let statusStr = case node.state
    of tsPending: "pending"
    of tsRunning: "running"
    of tsCompleted: "success"
    of tsFailed:  "failed"
    of tsBlocked: "blocked"
    of tsSkipped: "skipped"

  "{" &
    "\"id\":\"" & escapeJsonString($node.id) & "\"," &
    "\"status\":\"" & statusStr & "\"," &
    "\"hash\":\"" & escapeJsonString(node.hash) & "\"," &
    "\"duration\":" & $node.duration & "," &
    "\"outputs\":" & serializeJsonArray(node.outputs) & "," &
    "\"inputs\":" & serializeJsonArray(node.inputs) &
  "}"

func serializeDagState*(dag: TaskDag): string {.raises: [].} =
  ## Serialize entire DAG state as JSON Lines (one line per node).
  var lines: seq[string] = @[]
  for node in dag.nodes:
    lines.add(serializeNodeState(node))
  lines.join("\n") & "\n"

# ---------------------------------------------------------------------------
# Persistence: I/O operations
# ---------------------------------------------------------------------------

proc saveDagState*(dag: TaskDag, path: string = DefaultStatePath): Result[void, string] {.
    axiomEffect: IOEffect, tags: [ReadIOEffect, WriteIOEffect, RootEffect].} =
  ## Persist DAG state atomically as JSON Lines.
  let content = serializeDagState(dag)
  let dir = parentDir(path)
  if dir.len > 0 and not dirExists(dir):
    try:
      createDir(dir)
    except OSError as e:
      return err("failed to create log dir: " & e.msg)
  atomicWrite(path, content)

proc loadDagState*(path: string = DefaultStatePath): Result[string, string] {.
    axiomEffect: IOEffect, tags: [ReadIOEffect].} =
  ## Load persisted DAG state from JSON Lines file.
  if not fileExists(path):
    return err("state file not found: " & path)
  try:
    ok(readFile(path))
  except IOError as e:
    err("loadDagState: cannot read " & path & ": " & e.msg)
  except OSError as e:
    err("loadDagState: OS error reading " & path & ": " & e.msg)

# ---------------------------------------------------------------------------
# Task execution
# ---------------------------------------------------------------------------

proc executeTask*(dag: var TaskDag, taskIdx: int): Result[void, string] {.
    axiomEffect: IOEffect, tags: [ReadIOEffect, WriteIOEffect, ExecIOEffect, TimeEffect, RootEffect].} =
  ## Execute a single task by index. Updates node status and timing.
  let startTime = getMonoTime()
  let taskId = dag.nodes[taskIdx].id

  # Mark running
  let r1 = dag.updateNodeState(taskId, tsRunning)
  if r1.isErr(): return err(r1.error)

  # Execute via closure
  let executor: TaskExecutor = dag.nodes[taskIdx].executor
  if executor == nil:
    let elapsed = (getMonoTime() - startTime).inMicroseconds.float / 1_000_000.0
    let r2 = dag.updateNodeState(taskId, tsFailed, elapsed)
    if r2.isErr(): discard
    return err("task " & $taskId & ": nil executor")

  try:
    let res = executor(dag.nodes[taskIdx].inputs)
    let elapsed = (getMonoTime() - startTime).inMicroseconds.float / 1_000_000.0

    if res.isOk():
      dag.nodes[taskIdx].outputs = res.get()
      let r3 = dag.updateNodeState(taskId, tsCompleted, elapsed)
      if r3.isErr(): return err(r3.error)
      Result[void, string](ok: true)
    else:
      let r4 = dag.updateNodeState(taskId, tsFailed, elapsed)
      if r4.isErr(): discard
      err("task " & $taskId & " failed: " & res.error)
  except CatchableError as e:
    let elapsed = (getMonoTime() - startTime).inMicroseconds.float / 1_000_000.0
    let r5 = dag.updateNodeState(taskId, tsFailed, elapsed)
    if r5.isErr(): discard
    err("task " & $taskId & " exception: " & e.msg)

# ---------------------------------------------------------------------------
# executeDag: main entry point
# ---------------------------------------------------------------------------

proc executeDag*(dag: var TaskDag, parallelism: int = MaxConcurrentL2): Result[void, string] {.
    axiomEffect: IOEffect, tags: [ReadIOEffect, WriteIOEffect, ExecIOEffect, TimeEffect, RootEffect].} =
  ## Execute the entire DAG level by level.
  ##
  ## 1. Validate DAG (no cycles, all deps exist)
  ## 2. topologicalSort for level-based execution
  ## 3. For each level, execute tasks sequentially via closures
  ## 4. Save state after each level
  ## 5. If any task fails, stop and return error
  ##
  ## The `parallelism` parameter is a hint for external executor concurrency.
  ## TaskExecutor closures run in-process; for true parallelism,
  ## closures should use startProcess internally.

  # 1. Validate
  let validation = dag.validateDag()
  if validation.isErr():
    return err("DAG validation failed: " & validation.error)

  # 2. Topological sort
  let sortResult = dag.topologicalSort()
  if sortResult.isErr():
    return err("topological sort failed: " & sortResult.error)

  let layers = sortResult.get()
  dag.executionOrder = layers

  # 3. Execute level by level
  for layerIdx, layer in layers:
    for taskId in layer:
      let nodeIdx = dag.findNodeById(taskId)
      if nodeIdx < 0:
        return err("internal error: task " & $taskId & " not found in nodes")

      # Skip tasks already completed (for resume scenarios)
      if dag.nodes[nodeIdx].state == tsCompleted:
        continue
      if dag.nodes[nodeIdx].state == tsSkipped:
        continue

      # Check if any dependency failed → skip this task
      var depFailed = false
      for depId in dag.nodes[nodeIdx].dependsOn:
        let depIdx = dag.findNodeById(depId)
        if depIdx >= 0 and dag.nodes[depIdx].state == tsFailed:
          depFailed = true
          break
      if depFailed:
        let r6 = dag.updateNodeState(taskId, tsSkipped)
        if r6.isErr(): discard
        continue

      # Execute the task
      let execResult = dag.executeTask(nodeIdx)
      if execResult.isErr():
        # Save state on failure before returning
        let r7 = dag.saveDagState()
        if r7.isErr(): discard
        return execResult

    # Save state after each level completes
    let saveResult = dag.saveDagState()
    if saveResult.isErr():
      return err("failed to save state after level " & $layerIdx & ": " & saveResult.error)

  Result[void, string](ok: true)

# ---------------------------------------------------------------------------
# replay: re-run a single task and its dependency chain
# ---------------------------------------------------------------------------

proc replay*(dag: var TaskDag, taskId: TaskId): Result[void, string] {.
    axiomEffect: IOEffect, tags: [ReadIOEffect, WriteIOEffect, ExecIOEffect, TimeEffect, RootEffect].} =
  ## Re-run a single task and re-execute all its dependencies from scratch.
  ## Non-dependent tasks are preserved.

  let targetIdx = dag.findNodeById(taskId)
  if targetIdx < 0:
    return err("task not found: " & $taskId)

  # Collect all ancestors that need re-execution
  var toReexec = initTable[string, bool]()
  var stack = @[taskId]
  while stack.len > 0:
    let current = stack.pop()
    let currentIdx = dag.findNodeById(current)
    if currentIdx < 0:
      continue
    toReexec[$current] = true
    # Add all dependencies of this task to the re-execution set
    for depId in dag.nodes[currentIdx].dependsOn:
      if $depId notin toReexec:
        stack.add(depId)

  # Reset status of tasks in the re-execution set
  for nodeIdx in 0..<dag.nodes.len:
    if $dag.nodes[nodeIdx].id in toReexec:
      dag.nodes[nodeIdx].state = tsPending
      dag.nodes[nodeIdx].outputs = @[]
      dag.nodes[nodeIdx].duration = 0.0

  # Re-sort and execute only the affected portion
  let sortResult = dag.topologicalSort()
  if sortResult.isErr():
    return err("topological sort failed: " & sortResult.error)

  let layers = sortResult.get()
  for layer in layers:
    for tid in layer:
      if $tid notin toReexec:
        continue

      let nodeIdx = dag.findNodeById(tid)
      if nodeIdx < 0:
        continue

      let execResult = dag.executeTask(nodeIdx)
      if execResult.isErr():
        let r8 = dag.saveDagState()
        if r8.isErr(): discard
        return execResult

    let r9 = dag.saveDagState()
    if r9.isErr(): return err(r9.error)

  Result[void, string](ok: true)

# ---------------------------------------------------------------------------
# resume: restore DAG state and continue from failed nodes
# ---------------------------------------------------------------------------

proc resume*(dag: var TaskDag): Result[void, string] {.
    axiomEffect: IOEffect,
    tags: [ReadIOEffect, WriteIOEffect, ExecIOEffect, TimeEffect, RootEffect],
    axiomNestingDepth: 10.} =
  ## Restore DAG state from persistence and continue from failed nodes.
  ## Loads the JSON Lines state file, restores node statuses, and
  ## re-executes only failed/pending tasks whose dependencies succeeded.

  let loadResult = loadDagState()
  if loadResult.isErr():
    return err("cannot load state: " & loadResult.error)

  let stateContent = loadResult.get()

  # Parse JSON Lines and restore status
  for line in stateContent.splitLines():
    let trimmed = line.strip()
    if trimmed.len == 0:
      continue
    try:
      let state = parseJson(trimmed)
      let nodeId = toTaskId(state["id"].getStr())
      let statusStr = state["status"].getStr()
      let duration = state["duration"].getFloat()

      let status = case statusStr
        of "pending": tsPending
        of "running": tsRunning  # Treat pending (crash recovery)
        of "success": tsCompleted
        of "failed":  tsFailed
        of "blocked": tsBlocked
        of "skipped": tsSkipped
        else: tsPending

      let idx = dag.findNodeById(nodeId)
      if idx >= 0:
        dag.nodes[idx].state = status
        dag.nodes[idx].duration = duration
        if status == tsRunning:
          # Crash recovery: running → pending (restart)
          dag.nodes[idx].state = tsPending
        # Restore outputs if present
        if state.hasKey("outputs"):
          var outputs: seq[string] = @[]
          for outVal in state["outputs"]:
            outputs.add(outVal.getStr())
          dag.nodes[idx].outputs = outputs
    except CatchableError as e:
      continue

  # Re-execute from where we left off
  let sortResult = dag.topologicalSort()
  if sortResult.isErr():
    return err("topological sort failed: " & sortResult.error)

  let layers = sortResult.get()
  for layer in layers:
    for tid in layer:
      let idx = dag.findNodeById(tid)
      if idx < 0:
        continue

      # Only re-run pending or failed tasks
      let status = dag.nodes[idx].state
      if status != tsPending and status != tsFailed:
        continue

      # Check if all dependencies succeeded
      var allDepsOk = true
      for depId in dag.nodes[idx].dependsOn:
        let depIdx = dag.findNodeById(depId)
        if depIdx >= 0 and dag.nodes[depIdx].state != tsCompleted:
          allDepsOk = false
          break

      if not allDepsOk:
        let r10 = dag.updateNodeState(tid, tsSkipped)
        if r10.isErr(): discard
        continue

      let execResult = dag.executeTask(idx)
      if execResult.isErr():
        let r11 = dag.saveDagState()
        if r11.isErr(): discard
        return execResult

    let r12 = dag.saveDagState()
    if r12.isErr(): return err(r12.error)

  Result[void, string](ok: true)

{.pop.}
