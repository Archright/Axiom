import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}
# axiomIoBoundary

import std/[tables, sequtils, strutils]
import core/boundary/axiom_pragmas_boundary
import core/task_schema
import core/types/results
import core/types/execution_plan
import engine/task_dag
import engine/dag_executor

# ---------------------------------------------------------------------------
# PlanTaskInputs — materialization data for building a TaskDag from a plan.
#
# The executor does NOT interpret selection. All "which units, why" decisions
# live in the ExecutionPlan; PlanTaskInputs supplies only the material details
# (executor closures, dependency structure, input data) needed to materialize
# the DAG.
# ---------------------------------------------------------------------------

type
  PlanTaskInputs* = object
    universe*: seq[string]                    ## all unit IDs (for umFull mode)
    unitInputs*: Table[string, seq[string]]   ## unitId → executor inputs
    unitDependencies*: Table[string, seq[TaskId]]  ## unitId → dependsOn
    unitExecutors*: Table[string, TaskExecutor]  ## unitId → executor closure

# ---------------------------------------------------------------------------
# planToTaskDag — pure builder: immutable ExecutionPlan → fully-materialized TaskDag
# ---------------------------------------------------------------------------

func planToTaskDag*(plan: ExecutionPlan; inputs: PlanTaskInputs): TaskDag {.
    raises: [].} =
  ## Convert an immutable ExecutionPlan into a fully-materialized TaskDag.
  ## Deterministic: same plan + inputs → identical DAG.
  ## The builder does all interpretation ONCE, before any execution.
  var dag = newTaskDag()

  let unitIds = case plan.mode
    of umFull: inputs.universe
    of umSelected: plan.selectedUnitIds

  for unitId in unitIds:
    let node = TaskNode(
      id: toTaskId(unitId),
      inputs: inputs.unitInputs.getOrDefault(unitId, @[]),
      outputs: @[],
      dependsOn: inputs.unitDependencies.getOrDefault(unitId, @[]),
      executor: inputs.unitExecutors.getOrDefault(unitId, nil),
      state: tsPending,
      hash: "",
      duration: 0.0
    )
    discard dag.addNode(node)

  result = dag

# ---------------------------------------------------------------------------
# executePlan — dumb runner entry point
# ---------------------------------------------------------------------------

proc executePlan*(plan: ExecutionPlan; inputs: PlanTaskInputs): Result[void, string] {.
    axiomEffect: IOEffect, tags: [ReadIOEffect, WriteIOEffect, ExecIOEffect, TimeEffect, RootEffect].} =
  ## Execute an immutable ExecutionPlan.
  ##
  ## Boundary invariant: the executor is a dumb runner — it does not import,
  ## reference, or compute selection logic, universe eligibility, or
  ## skipped-because-unaffected reasoning. Selection decisions live entirely in
  ## the ExecutionPlan; this function materializes the DAG and runs it with
  ## structural dependency ordering only.
  var dag = planToTaskDag(plan, inputs)
  executeDag(dag)

{.pop.}
  # G1 S3 verification vehicle — code-change PR to trigger ci-bootstrap lane (docs PRs are mode=none)
