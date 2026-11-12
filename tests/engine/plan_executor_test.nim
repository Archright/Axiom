## plan_executor_test.nim — Tests for plan executor boundary

import std/unittest
import tables
import core/task_schema
import core/types/results
import core/types/execution_plan
import engine/task_dag
import engine/plan_executor

proc noopExecutor(inputs: seq[string]): Result[seq[string], string] =
  ok(inputs)

suite "planToTaskDag determinism":
  test "same plan + inputs produce identical DAG structure":
    var plan = ExecutionPlan(
      mode: umSelected,
      selectedUnitIds: @["unit1", "unit2"],
      planIdentity: PlanIdentity(
        selectionDigest: "sel", changeSetDigest: "", graphDigest: "",
        universeDigest: "", policyDigest: "", planDigest: "plan"
      ),
      planDigest: "test"
    )
    let inputs = PlanTaskInputs(
      universe: @["unit1", "unit2"],
      unitInputs: initTable[string, seq[string]](),
      unitDependencies: initTable[string, seq[TaskId]](),
      unitExecutors: initTable[string, TaskExecutor]()
    )
    let dag = planToTaskDag(plan, inputs)
    check dag.nodes.len == 2

  test "umSelected creates DAG with only selected units":
    var plan = ExecutionPlan(
      mode: umSelected,
      selectedUnitIds: @["A", "B"],
      planIdentity: PlanIdentity(
        selectionDigest: "sel", changeSetDigest: "", graphDigest: "",
        universeDigest: "", policyDigest: "", planDigest: "plan"
      ),
      planDigest: "test"
    )
    let inputs = PlanTaskInputs(
      universe: @["A", "B", "C", "D"],
      unitInputs: initTable[string, seq[string]](),
      unitDependencies: initTable[string, seq[TaskId]](),
      unitExecutors: initTable[string, TaskExecutor]()
    )
    let dag = planToTaskDag(plan, inputs)
    check dag.nodes.len == 2

  test "umFull creates DAG with all universe units":
    var plan = ExecutionPlan(
      mode: umFull,
      selectedUnitIds: @[],
      planIdentity: PlanIdentity(
        selectionDigest: "sel", changeSetDigest: "", graphDigest: "",
        universeDigest: "", policyDigest: "", planDigest: "plan"
      ),
      planDigest: "test"
    )
    let inputs = PlanTaskInputs(
      universe: @["X", "Y", "Z"],
      unitInputs: initTable[string, seq[string]](),
      unitDependencies: initTable[string, seq[TaskId]](),
      unitExecutors: initTable[string, TaskExecutor]()
    )
    let dag = planToTaskDag(plan, inputs)
    check dag.nodes.len == 3

  test "umFull vs umSelected produce different DAGs":
    var planSelected = ExecutionPlan(
      mode: umSelected,
      selectedUnitIds: @["A", "B"],
      planIdentity: PlanIdentity(
        selectionDigest: "sel", changeSetDigest: "", graphDigest: "",
        universeDigest: "", policyDigest: "", planDigest: "plan"
      ),
      planDigest: "test"
    )
    var planFull = ExecutionPlan(
      mode: umFull,
      selectedUnitIds: @[],
      planIdentity: PlanIdentity(
        selectionDigest: "sel", changeSetDigest: "", graphDigest: "",
        universeDigest: "", policyDigest: "", planDigest: "plan"
      ),
      planDigest: "test"
    )
    let inputs = PlanTaskInputs(
      universe: @["A", "B", "C"],
      unitInputs: initTable[string, seq[string]](),
      unitDependencies: initTable[string, seq[TaskId]](),
      unitExecutors: initTable[string, TaskExecutor]()
    )
    let dagSelected = planToTaskDag(planSelected, inputs)
    let dagFull = planToTaskDag(planFull, inputs)
    check dagSelected.nodes.len == 2
    check dagFull.nodes.len == 3

suite "executePlan integration":
  test "executes DAG with deterministic results on repeat runs":
    var plan = ExecutionPlan(
      mode: umSelected,
      selectedUnitIds: @["t1", "t2"],
      planIdentity: PlanIdentity(
        selectionDigest: "sel", changeSetDigest: "", graphDigest: "",
        universeDigest: "", policyDigest: "", planDigest: "plan"
      ),
      planDigest: "test"
    )
    var execs = initTable[string, TaskExecutor]()
    execs["t1"] = noopExecutor
    execs["t2"] = noopExecutor
    let inputs = PlanTaskInputs(
      universe: @["t1", "t2"],
      unitInputs: initTable[string, seq[string]](),
      unitDependencies: initTable[string, seq[TaskId]](),
      unitExecutors: execs
    )
    let result1 = executePlan(plan, inputs)
    check result1.isOk()
    let result2 = executePlan(plan, inputs)
    check result2.isOk()

  test "executes DAG with dependencies correctly (dependency order enforced)":
    var plan = ExecutionPlan(
      mode: umSelected,
      selectedUnitIds: @["t1", "t2"],
      planIdentity: PlanIdentity(
        selectionDigest: "sel", changeSetDigest: "", graphDigest: "",
        universeDigest: "", policyDigest: "", planDigest: "plan"
      ),
      planDigest: "test"
    )
    var order: seq[string]
    var execs = initTable[string, TaskExecutor]()
    execs["t1"] = proc(inputs: seq[string]): Result[seq[string], string] =
      order.add("t1")
      ok(inputs)
    execs["t2"] = proc(inputs: seq[string]): Result[seq[string], string] =
      order.add("t2")
      ok(inputs)
    var deps = initTable[string, seq[TaskId]]()
    deps["t2"] = @[toTaskId("t1")]
    let inputs = PlanTaskInputs(
      universe: @["t1", "t2"],
      unitInputs: initTable[string, seq[string]](),
      unitDependencies: deps,
      unitExecutors: execs
    )
    let result = executePlan(plan, inputs)
    check result.isOk()
    check order.find("t1") < order.find("t2")

  test "umFull runs all universe units, not just selected":
    ## umFull must ignore selectedUnitIds — the plan's mode is the only
    ## selection signal the executor may act on.
    var plan = ExecutionPlan(
      mode: umFull,
      selectedUnitIds: @["A"],
      planIdentity: PlanIdentity(
        selectionDigest: "sel", changeSetDigest: "", graphDigest: "",
        universeDigest: "", policyDigest: "", planDigest: "plan"
      ),
      planDigest: "test"
    )
    let inputs = PlanTaskInputs(
      universe: @["A", "B", "C"],
      unitInputs: initTable[string, seq[string]](),
      unitDependencies: initTable[string, seq[TaskId]](),
      unitExecutors: initTable[string, TaskExecutor]()
    )
    let dag = planToTaskDag(plan, inputs)
    check dag.nodes.len == 3

suite "executor boundary - no selection logic":
  test "planToTaskDag uses only plan data":
    var plan = ExecutionPlan(
      mode: umSelected,
      selectedUnitIds: @["unit1"],
      planIdentity: PlanIdentity(
        selectionDigest: "sel", changeSetDigest: "", graphDigest: "",
        universeDigest: "", policyDigest: "", planDigest: "plan"
      ),
      planDigest: "test"
    )
    let inputs = PlanTaskInputs(
      universe: @["unit1", "unit2", "unit3"],
      unitInputs: initTable[string, seq[string]](),
      unitDependencies: initTable[string, seq[TaskId]](),
      unitExecutors: initTable[string, TaskExecutor]()
    )
    let dag = planToTaskDag(plan, inputs)
    check dag.nodes.len == 1
    check dag.nodes[0].id == toTaskId("unit1")