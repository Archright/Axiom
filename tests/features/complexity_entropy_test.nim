## Integration tests for Complexity Entropy — adaptive gas allocation.
##
## Tests: computeComplexityEntropy, adaptiveGasCost, redistributeSurplus.
##
## AGENTS.md §0.7: Business-Only Test Scope.

import std/unittest
import core/proof/proof_budget

suite "Complexity Entropy computation":
  test "zero signals produce zero entropy":
    let signals = ComplexitySignals()
    let entropy = computeComplexityEntropy(signals)
    check entropy == 0.0

  test "maximum signals produce maximum entropy":
    let signals = ComplexitySignals(
      topologyScore: 1.0,
      sieveProbability: 1.0,
      cegarIterations: 20,
      cegarStagnationCount: 3,
      z3RejectionCount: 3,
      synergyGeometricMean: 1.0,
      historicalAvgGas: 1.0
    )
    let entropy = computeComplexityEntropy(signals)
    check entropy >= 0.9  # Should be near 1.0

  test "topology-only signal":
    let signals = ComplexitySignals(topologyScore: 0.5)
    let entropy = computeComplexityEntropy(signals)
    # Expected: 0.3 * 0.5 = 0.15
    check entropy > 0.1
    check entropy < 0.2

  test "entropy is clamped to [0, 1]":
    let signals = ComplexitySignals(
      topologyScore: 2.0,  # Over 1.0 — should be clamped
      sieveProbability: 2.0
    )
    let entropy = computeComplexityEntropy(signals)
    check entropy >= 0.0
    check entropy <= 1.0

  test "CEGAR difficulty with max iterations":
    let signals = ComplexitySignals(cegarIterations: 20, cegarStagnationCount: 3, z3RejectionCount: 3)
    let cegarDiff = computeCegarDifficulty(signals)
    check cegarDiff >= 0.95

suite "Adaptive Gas Cost":
  test "low entropy produces low gas cost":
    let cost = adaptiveGasCost(0.1, 8, 4)
    check cost >= 1
    check cost <= 4  # Should be less than fair share

  test "high entropy produces high gas cost":
    let cost = adaptiveGasCost(0.9, 8, 4)
    check cost >= 3
    check cost <= 8  # Should be more than fair share

  test "gas cost is at least 1":
    let cost = adaptiveGasCost(0.0, 8, 100)
    check cost >= 1

  test "gas cost does not exceed total":
    let cost = adaptiveGasCost(1.0, 8, 1)
    check cost <= 8

  test "zero expected nodes returns 1":
    let cost = adaptiveGasCost(0.5, 8, 0)
    check cost == 1

suite "Budget Redistribute Surplus":
  test "surplus returned to budget":
    var budget = ProofBudget(gasRemaining: 3, gasTotal: 8)
    redistributeSurplus(budget, allocatedCost = 4, actualCost = 2, remainingNodes = 2)
    check budget.gasRemaining == 5  # 3 + (4-2) = 5

  test "no surplus when fully consumed":
    var budget = ProofBudget(gasRemaining: 3, gasTotal: 8)
    redistributeSurplus(budget, allocatedCost = 3, actualCost = 3, remainingNodes = 2)
    check budget.gasRemaining == 3  # No change

  test "no redistribution with zero remaining nodes":
    var budget = ProofBudget(gasRemaining: 3, gasTotal: 8)
    redistributeSurplus(budget, allocatedCost = 4, actualCost = 2, remainingNodes = 0)
    check budget.gasRemaining == 3  # No change

suite "Budget Critical Detection":
  test "budget critical at 20%":
    let budget = ProofBudget(gasRemaining: 1, gasTotal: 8)
    check isBudgetCritical(budget) == true  # 1/8 = 12.5% < 20%

  test "budget not critical at 50%":
    let budget = ProofBudget(gasRemaining: 4, gasTotal: 8)
    check isBudgetCritical(budget) == false  # 4/8 = 50% > 20%

  test "empty budget is critical":
    let budget = ProofBudget(gasRemaining: 0, gasTotal: 0)
    check isBudgetCritical(budget) == true
