## task_dag.nim_test.nim — Smoke tests for Task DAG engine
##
## Tests: DAG construction, cycle detection, topological sort, execution.

import std/[unittest, tables]
import core/types/results
import core/task_schema
import engine/task_dag

# ---------------------------------------------------------------------------
# Test helpers
# ---------------------------------------------------------------------------

proc noopExecutor(inputs: seq[string]): Result[seq[string], string] {.
    raises: [CatchableError].} =
  ## No-op executor that passes inputs through as outputs.
  ok(inputs)

proc failExecutor(inputs: seq[string]): Result[seq[string], string] {.
    raises: [CatchableError].} =
  ## Executor that always fails.
  err("intentional failure")

proc appendExecutor(suffix: string): TaskExecutor =
  ## Create an executor that appends a suffix to each input.
  proc(inputs: seq[string]): Result[seq[string], string] {.
      raises: [CatchableError].} =
    var outputs: seq[string] = @[]
    for inp in inputs:
      outputs.add(inp & suffix)
    ok(outputs)

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

suite "TaskId":
  test "toTaskId and $ round-trip":
    let id = toTaskId("task-1")
    check $id == "task-1"

  test "TaskId equality":
    check toTaskId("a") == toTaskId("a")
    check toTaskId("a") != toTaskId("b")

suite "TaskDag construction":
  test "newTaskDag creates empty DAG":
    var dag = newTaskDag()
    check dag.nodes.len == 0
    check dag.adjacency.len == 0

  test "addNode adds single node":
    var dag = newTaskDag()
    let node = TaskNode(
      id: toTaskId("t1"),
      inputs: @["in1"],
      outputs: @[],
      dependsOn: @[],
      executor: noopExecutor,
      state: tsPending
    )
    let r = dag.addNode(node)
    check r.isOk()
    check dag.nodes.len == 1
    check dag.nodes[0].id == toTaskId("t1")

  test "addNode rejects duplicate id":
    var dag = newTaskDag()
    let n1 = TaskNode(id: toTaskId("t1"), inputs: @[], outputs: @[],
                       dependsOn: @[], executor: noopExecutor, state: tsPending)
    let n2 = TaskNode(id: toTaskId("t1"), inputs: @[], outputs: @[],
                       dependsOn: @[], executor: noopExecutor, state: tsPending)
    check dag.addNode(n1).isOk()
    let r = dag.addNode(n2)
    check r.isErr()

  test "addNode with dependencies":
    var dag = newTaskDag()
    let n1 = TaskNode(id: toTaskId("t1"), inputs: @[], outputs: @[],
                       dependsOn: @[], executor: noopExecutor, state: tsPending)
    let n2 = TaskNode(id: toTaskId("t2"), inputs: @[], outputs: @[],
                       dependsOn: @[toTaskId("t1")], executor: noopExecutor,
                       state: tsPending)
    check dag.addNode(n1).isOk()
    check dag.addNode(n2).isOk()
    check dag.adjacency["t1"].len == 1  # t1 has t2 as dependent

suite "Cycle detection":
  test "no cycle in linear chain":
    var dag = newTaskDag()
    check dag.addNode(TaskNode(id: toTaskId("a"), inputs: @[], outputs: @[],
                       dependsOn: @[], executor: noopExecutor, state: tsPending)).isOk()
    check dag.addNode(TaskNode(id: toTaskId("b"), inputs: @[], outputs: @[],
                       dependsOn: @[toTaskId("a")], executor: noopExecutor,
                       state: tsPending)).isOk()
    check dag.addNode(TaskNode(id: toTaskId("c"), inputs: @[], outputs: @[],
                       dependsOn: @[toTaskId("b")], executor: noopExecutor,
                       state: tsPending)).isOk()
    let cycles = dag.detectCycles()
    check cycles.len == 0

  test "detects simple 2-node cycle":
    var dag = newTaskDag()
    check dag.addNode(TaskNode(id: toTaskId("a"), inputs: @[], outputs: @[],
                       dependsOn: @[toTaskId("b")], executor: noopExecutor,
                       state: tsPending)).isOk()
    check dag.addNode(TaskNode(id: toTaskId("b"), inputs: @[], outputs: @[],
                       dependsOn: @[toTaskId("a")], executor: noopExecutor,
                       state: tsPending)).isOk()
    let cycles = dag.detectCycles()
    check cycles.len > 0

suite "Validation":
  test "valid DAG passes":
    var dag = newTaskDag()
    check dag.addNode(TaskNode(id: toTaskId("a"), inputs: @[], outputs: @[],
                       dependsOn: @[], executor: noopExecutor, state: tsPending)).isOk()
    check dag.addNode(TaskNode(id: toTaskId("b"), inputs: @[], outputs: @[],
                       dependsOn: @[toTaskId("a")], executor: noopExecutor,
                       state: tsPending)).isOk()
    check dag.validateDag().isOk()

  test "missing dependency detected":
    var dag = newTaskDag()
    check dag.addNode(TaskNode(id: toTaskId("b"), inputs: @[], outputs: @[],
                       dependsOn: @[toTaskId("nonexistent")], executor: noopExecutor,
                       state: tsPending)).isOk()
    let r = dag.validateDag()
    check r.isErr()

  test "cycle detected during validation":
    var dag = newTaskDag()
    check dag.addNode(TaskNode(id: toTaskId("a"), inputs: @[], outputs: @[],
                       dependsOn: @[toTaskId("b")], executor: noopExecutor,
                       state: tsPending)).isOk()
    check dag.addNode(TaskNode(id: toTaskId("b"), inputs: @[], outputs: @[],
                       dependsOn: @[toTaskId("a")], executor: noopExecutor,
                       state: tsPending)).isOk()
    let r = dag.validateDag()
    check r.isErr()

suite "Topological sort":
  test "linear chain produces correct layers":
    var dag = newTaskDag()
    # a → b → c
    check dag.addNode(TaskNode(id: toTaskId("a"), inputs: @[], outputs: @[],
                       dependsOn: @[], executor: noopExecutor, state: tsPending)).isOk()
    check dag.addNode(TaskNode(id: toTaskId("b"), inputs: @[], outputs: @[],
                       dependsOn: @[toTaskId("a")], executor: noopExecutor,
                       state: tsPending)).isOk()
    check dag.addNode(TaskNode(id: toTaskId("c"), inputs: @[], outputs: @[],
                       dependsOn: @[toTaskId("b")], executor: noopExecutor,
                       state: tsPending)).isOk()

    let r = dag.topologicalSort()
    check r.isOk()
    let layers = r.get()
    check layers.len == 3
    check layers[0].len == 1  # layer 0: a
    check layers[0][0] == toTaskId("a")
    check layers[1][0] == toTaskId("b")
    check layers[2][0] == toTaskId("c")

  test "diamond DAG produces correct layers":
    var dag = newTaskDag()
    #   a
    #  / \
    # b   c
    #  \ /
    #   d
    check dag.addNode(TaskNode(id: toTaskId("a"), inputs: @[], outputs: @[],
                       dependsOn: @[], executor: noopExecutor, state: tsPending)).isOk()
    check dag.addNode(TaskNode(id: toTaskId("b"), inputs: @[], outputs: @[],
                       dependsOn: @[toTaskId("a")], executor: noopExecutor,
                       state: tsPending)).isOk()
    check dag.addNode(TaskNode(id: toTaskId("c"), inputs: @[], outputs: @[],
                       dependsOn: @[toTaskId("a")], executor: noopExecutor,
                       state: tsPending)).isOk()
    check dag.addNode(TaskNode(id: toTaskId("d"), inputs: @[], outputs: @[],
                       dependsOn: @[toTaskId("b"), toTaskId("c")],
                       executor: noopExecutor, state: tsPending)).isOk()

    let r = dag.topologicalSort()
    check r.isOk()
    let layers = r.get()
    check layers.len == 3
    check layers[0].len == 1   # layer 0: a
    check layers[1].len == 2   # layer 1: b, c
    check layers[2].len == 1   # layer 2: d

  test "independent nodes in same layer":
    var dag = newTaskDag()
    # a, b, c — no deps between them
    check dag.addNode(TaskNode(id: toTaskId("a"), inputs: @[], outputs: @[],
                       dependsOn: @[], executor: noopExecutor, state: tsPending)).isOk()
    check dag.addNode(TaskNode(id: toTaskId("b"), inputs: @[], outputs: @[],
                       dependsOn: @[], executor: noopExecutor, state: tsPending)).isOk()
    check dag.addNode(TaskNode(id: toTaskId("c"), inputs: @[], outputs: @[],
                       dependsOn: @[], executor: noopExecutor, state: tsPending)).isOk()

    let r = dag.topologicalSort()
    check r.isOk()
    let layers = r.get()
    check layers.len == 1  # all in layer 0
    check layers[0].len == 3

  test "cycle returns error":
    var dag = newTaskDag()
    check dag.addNode(TaskNode(id: toTaskId("a"), inputs: @[], outputs: @[],
                       dependsOn: @[toTaskId("b")], executor: noopExecutor,
                       state: tsPending)).isOk()
    check dag.addNode(TaskNode(id: toTaskId("b"), inputs: @[], outputs: @[],
                       dependsOn: @[toTaskId("a")], executor: noopExecutor,
                       state: tsPending)).isOk()
    let r = dag.topologicalSort()
    check r.isErr()

suite "TaskExecutor":
  test "noop executor passes through":
    let r = noopExecutor(@["hello", "world"])
    check r.isOk()
    check r.get() == @["hello", "world"]

  test "fail executor returns error":
    let r = failExecutor(@["hello"])
    check r.isErr()

  test "append executor modifies outputs":
    let executor = appendExecutor("-done")
    let r = executor(@["task1", "task2"])
    check r.isOk()
    check r.get() == @["task1-done", "task2-done"]

suite "getNode":
  test "get existing node":
    var dag = newTaskDag()
    let node = TaskNode(id: toTaskId("t1"), inputs: @["x"], outputs: @[],
                         dependsOn: @[], executor: noopExecutor, state: tsPending,
                         hash: "abc123")
    check dag.addNode(node).isOk()
    let r = dag.getNode(toTaskId("t1"))
    check r.isOk()
    check r.get().hash == "abc123"
    check r.get().inputs == @["x"]

  test "get missing node returns error":
    var dag = newTaskDag()
    let r = dag.getNode(toTaskId("nonexistent"))
    check r.isErr()
