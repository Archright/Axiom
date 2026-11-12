## Unit tests for proof_budget.nim — dual budget system.

import std/[unittest, monotimes]
import core/proof/proof_budget

suite "ProofBudget":
  test "initProofBudget creates budget with correct defaults":
    let budget = initProofBudget()
    check budget.gasRemaining == maxTotalSolverInvocations
    check budget.gasTotal == maxTotalSolverInvocations
    check budget.invocations == 0

  test "consumeGas decrements and returns continue while gas remains":
    var budget = initProofBudget(gasLimit = 3)
    check consumeGas(budget) == pbvContinue
    check budget.gasRemaining == 2
    check budget.invocations == 1
    check consumeGas(budget) == pbvContinue
    check budget.gasRemaining == 1
    check consumeGas(budget) == pbvGasExhausted
    check budget.gasRemaining == 0

  test "checkBudget returns gasExhausted when gas is zero":
    var budget = initProofBudget(gasLimit = 1)
    discard consumeGas(budget)
    check checkBudget(budget) == pbvGasExhausted

  test "checkBudget returns continue when gas remains":
    let budget = initProofBudget(gasLimit = 5)
    check checkBudget(budget) == pbvContinue

  test "gasUsed tracks consumption correctly":
    var budget = initProofBudget(gasLimit = 10)
    check gasUsed(budget) == 0
    discard consumeGas(budget)
    discard consumeGas(budget)
    check gasUsed(budget) == 2

  test "isDeterministicFailure is true only for gasExhausted":
    check isDeterministicFailure(pbvGasExhausted) == true
    check isDeterministicFailure(pbvTimeout) == false
    check isDeterministicFailure(pbvContinue) == false

  test "gas exhaustion reached through checkBudget is a deterministic failure":
    var budget = initProofBudgetFromMono(0, gasLimit = 1)
    discard consumeGas(budget)
    let verdict = checkBudget(budget)
    check verdict == pbvGasExhausted
    check isDeterministicFailure(verdict)

  test "rlimit exhaustion is reported as a deterministic failure":
    var budget = initProofBudgetFromMono(getMonoTime().ticks, gasLimit = 5)
    let verdict = consumeRlimit(budget, budget.rlimitBudget)
    check verdict == pbvGasExhausted
    check isDeterministicFailure(verdict)
    # consumeRlimit is the rlimit verdict authority — checkBudget reads gas and
    # wall clock only, so it must not re-derive (or mask) the rlimit outcome.
    check checkBudget(budget) == pbvContinue

  test "wall-clock expiry is not a deterministic failure (hang-guard abort)":
    let budget = initProofBudgetFromMono(0, gasLimit = 5, wallClockMs = 0)
    let verdict = checkBudget(budget)
    check verdict == pbvTimeout
    check not isDeterministicFailure(verdict)

  test "gas exhaustion outranks an expired wall-clock deadline":
    var budget = initProofBudgetFromMono(0, gasLimit = 1, wallClockMs = 0)
    discard consumeGas(budget)
    let verdict = checkBudget(budget)
    check verdict == pbvGasExhausted
    check isDeterministicFailure(verdict)

  test "constants are reasonable":
    check scribeMaxRounds == 3
    check cegarMaxIterations == 20
    check judgeMaxAttempts == 5
    check maxTotalSolverInvocations == scribeMaxRounds + judgeMaxAttempts
    check MaxGasCostPerNode == 4
    check orchestrationWallClockTimeoutMs > 0
    check nodeWallClockTimeoutMs > 0
