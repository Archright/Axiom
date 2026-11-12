## dag_executor_test.nim — Smoke tests for Task DAG executor
##
## Tests pure functions (validateDag, topologicalSort) and
## I/O-bound executeDag with synthetic in-process closures.

import std/[unittest, os]
import core/types/results
import core/task_schema
import engine/task_dag
import engine/dag_executor

# ---------------------------------------------------------------------------
# Helper: create a no-op executor
# ---------------------------------------------------------------------------

proc noopExecutor(outputs: seq[string]): Result[seq[string], string] =
  ok(@["noop_output"])

proc failExecutor(outputs: seq[string]): Result[seq[string], string] =
  err("intentional failure")

proc echoExecutor(outputs: seq[string]): Result[seq[string], string] =
  ok(outputs)

# ---------------------------------------------------------------------------
# Tests: Pure functions
# ---------------------------------------------------------------------------

suite "TaskId":
  test "taskId construction and string conversion":
    let id = toTaskId("task-1")
    check $id == "task-1"

  test "taskId equality":
    let a = toTaskId("x")
    let b = toTaskId("x")
    let c = toTaskId("y")
    check a == b
    check not (a == c)

suite "validateDag":
  test "empty DAG is valid":
    var dag = TaskDag()
    check validateDag(dag).isOk()

  test "single node DAG is valid":
    var dag = TaskDag()
    let node = TaskNode(id: toTaskId("a"), state: tsPending)
    discard addNode(dag, node)
    check validateDag(dag).isOk()

  test "DAG with valid dependencies is valid":
    var dag = TaskDag()
    discard addNode(dag, TaskNode(id: toTaskId("a"), dependsOn: @[], state: tsPending))
    discard addNode(dag, TaskNode(id: toTaskId("b"), dependsOn: @[toTaskId("a")], state: tsPending))
    check validateDag(dag).isOk()

  test "DAG with cycle is invalid":
    var dag = TaskDag()
    discard addNode(dag, TaskNode(id: toTaskId("a"), dependsOn: @[toTaskId("b")], state: tsPending))
    discard addNode(dag, TaskNode(id: toTaskId("b"), dependsOn: @[toTaskId("a")], state: tsPending))
    check validateDag(dag).isErr()

  test "addNode rejects duplicate IDs":
    var dag = TaskDag()
    discard addNode(dag, TaskNode(id: toTaskId("a"), state: tsPending))
    let result = addNode(dag, TaskNode(id: toTaskId("a"), state: tsPending))
    check result.isErr()

suite "topologicalSort":
  test "single node produces one layer":
    var dag = TaskDag()
    discard addNode(dag, TaskNode(id: toTaskId("a"), dependsOn: @[], state: tsPending))
    let result = topologicalSort(dag)
    check result.isOk()
    let layers = result.get()
    check layers.len == 1
    check layers[0].len == 1

  test "linear chain produces correct layers":
    var dag = TaskDag()
    # a -> b -> c
    discard addNode(dag, TaskNode(id: toTaskId("a"), dependsOn: @[], state: tsPending))
    discard addNode(dag, TaskNode(id: toTaskId("b"), dependsOn: @[toTaskId("a")], state: tsPending))
    discard addNode(dag, TaskNode(id: toTaskId("c"), dependsOn: @[toTaskId("b")], state: tsPending))
    let result = topologicalSort(dag)
    check result.isOk()
    let layers = result.get()
    check layers.len == 3
    check layers[0] == @[toTaskId("a")]
    check layers[1] == @[toTaskId("b")]
    check layers[2] == @[toTaskId("c")]

  test "diamond DAG produces correct layers":
    var dag = TaskDag()
    # a -> b, a -> c, b -> d, c -> d
    discard addNode(dag, TaskNode(id: toTaskId("a"), dependsOn: @[], state: tsPending))
    discard addNode(dag, TaskNode(id: toTaskId("b"), dependsOn: @[toTaskId("a")], state: tsPending))
    discard addNode(dag, TaskNode(id: toTaskId("c"), dependsOn: @[toTaskId("a")], state: tsPending))
    discard addNode(dag, TaskNode(id: toTaskId("d"), dependsOn: @[toTaskId("b"), toTaskId("c")], state: tsPending))
    let result = topologicalSort(dag)
    check result.isOk()
    let layers = result.get()
    check layers.len == 3
    check layers[0] == @[toTaskId("a")]
    check toTaskId("b") in layers[1]
    check toTaskId("c") in layers[1]
    check layers[2] == @[toTaskId("d")]

  test "independent nodes in same layer":
    var dag = TaskDag()
    # a, b, c — no dependencies
    discard addNode(dag, TaskNode(id: toTaskId("a"), dependsOn: @[], state: tsPending))
    discard addNode(dag, TaskNode(id: toTaskId("b"), dependsOn: @[], state: tsPending))
    discard addNode(dag, TaskNode(id: toTaskId("c"), dependsOn: @[], state: tsPending))
    let result = topologicalSort(dag)
    check result.isOk()
    let layers = result.get()
    check layers.len == 1
    check layers[0].len == 3

  test "cyclic DAG returns error":
    var dag = TaskDag()
    discard addNode(dag, TaskNode(id: toTaskId("a"), dependsOn: @[toTaskId("b")], state: tsPending))
    discard addNode(dag, TaskNode(id: toTaskId("b"), dependsOn: @[toTaskId("a")], state: tsPending))
    let result = topologicalSort(dag)
    check result.isErr()

suite "getNode":
  test "find existing node":
    var dag = TaskDag()
    discard addNode(dag, TaskNode(id: toTaskId("a"), state: tsCompleted))
    let result = dag.getNode(toTaskId("a"))
    check result.isOk()
    check result.get().state == tsCompleted

  test "missing node returns error":
    var dag = TaskDag()
    check dag.getNode(toTaskId("missing")).isErr()

suite "updateNodeState":
  test "update status and duration":
    var dag = TaskDag()
    discard addNode(dag, TaskNode(id: toTaskId("a"), state: tsPending))
    let result = updateNodeState(dag, toTaskId("a"), tsCompleted, 1.5)
    check result.isOk()
    check dag.nodes[0].state == tsCompleted
    check dag.nodes[0].duration == 1.5

# ---------------------------------------------------------------------------
# Tests: executeDag (I/O boundary)
# ---------------------------------------------------------------------------

suite "executeDag":
  test "execute empty DAG succeeds":
    var dag = TaskDag()
    let result = executeDag(dag)
    check result.isOk()

  test "execute single task with noop executor":
    var dag = TaskDag()
    let node = TaskNode(
      id: toTaskId("t1"),
      dependsOn: @[],
      executor: noopExecutor,
      state: tsPending
    )
    discard addNode(dag, node)
    let result = executeDag(dag)
    check result.isOk()
    check dag.nodes[0].state == tsCompleted
    check dag.nodes[0].outputs == @["noop_output"]

  test "execute linear chain":
    var dag = TaskDag()
    discard addNode(dag, TaskNode(
      id: toTaskId("a"), dependsOn: @[], executor: noopExecutor, state: tsPending
    ))
    discard addNode(dag, TaskNode(
      id: toTaskId("b"), dependsOn: @[toTaskId("a")], executor: echoExecutor, state: tsPending
    ))
    let result = executeDag(dag)
    check result.isOk()
    check dag.nodes[0].state == tsCompleted
    check dag.nodes[1].state == tsCompleted

  test "execute stops on failure":
    var dag = TaskDag()
    discard addNode(dag, TaskNode(
      id: toTaskId("a"), dependsOn: @[], executor: failExecutor, state: tsPending
    ))
    discard addNode(dag, TaskNode(
      id: toTaskId("b"), dependsOn: @[toTaskId("a")], executor: noopExecutor, state: tsPending
    ))
    let result = executeDag(dag)
    check result.isErr()

  test "execute diamond DAG":
    var dag = TaskDag()
    discard addNode(dag, TaskNode(
      id: toTaskId("a"), dependsOn: @[], executor: noopExecutor, state: tsPending
    ))
    discard addNode(dag, TaskNode(
      id: toTaskId("b"), dependsOn: @[toTaskId("a")], executor: noopExecutor, state: tsPending
    ))
    discard addNode(dag, TaskNode(
      id: toTaskId("c"), dependsOn: @[toTaskId("a")], executor: noopExecutor, state: tsPending
    ))
    discard addNode(dag, TaskNode(
      id: toTaskId("d"), dependsOn: @[toTaskId("b"), toTaskId("c")], executor: noopExecutor, state: tsPending
    ))
    let result = executeDag(dag)
    check result.isOk()
    for node in dag.nodes:
      check node.state == tsCompleted

  test "execute skips already-success nodes":
    var dag = TaskDag()
    discard addNode(dag, TaskNode(
      id: toTaskId("a"), dependsOn: @[], executor: noopExecutor, state: tsCompleted
    ))
    discard addNode(dag, TaskNode(
      id: toTaskId("b"), dependsOn: @[toTaskId("a")], executor: noopExecutor, state: tsPending
    ))
    let result = executeDag(dag)
    check result.isOk()
    # Node a should remain tsCompleted (not re-executed)
    check dag.nodes[0].state == tsCompleted
    check dag.nodes[1].state == tsCompleted

suite "replay":
  test "replay single task":
    var dag = TaskDag()
    discard addNode(dag, TaskNode(
      id: toTaskId("a"), dependsOn: @[], executor: noopExecutor, state: tsCompleted
    ))
    discard addNode(dag, TaskNode(
      id: toTaskId("b"), dependsOn: @[toTaskId("a")], executor: noopExecutor, state: tsCompleted
    ))
    let result = replay(dag, toTaskId("b"))
    check result.isOk()

  test "replay non-existent task fails":
    var dag = TaskDag()
    check replay(dag, toTaskId("missing")).isErr()

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

suite "cleanup":
  test "remove state file if created":
    var removed = false
    if fileExists("logs/task_dag_state.jsonl"):
      removeFile("logs/task_dag_state.jsonl")
      removed = true
    # If the file existed, verify it was removed
    if removed:
      check not fileExists("logs/task_dag_state.jsonl")
