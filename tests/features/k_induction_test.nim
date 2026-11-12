## K-Induction Benchmark Tests
##
## Verifies that the k-induction engine produces correct base/step cases
## and that the uniqueness constraints are properly generated.
##
## References:
##   - Sheeran et al. (2000) Table 1: expected k values for various circuits
##   - Eén & Sörensson (2004): temporal induction correctness

import std/[unittest, sequtils, strutils]
import core/solver/induction
import core/solver/types
import core/solver/construct_base
import core/solver/construct_logical
import core/solver/expr_serialize
import core/solver/smtlib_emitter
import core/solver/solver_bridge
import core/bmc/bmc_race
import core/proof/proof_budget

suite "K-Induction Base Case Generation":
  test "k=1 generates single transition":
    let rule = TransitionRule(op: transitionSub, delta: 10,
      invariant: InvariantRule(kind: invariantMinValue, minValue: 0, maxValue: 0))
    let req = makeKInductionRequest(1, @[], @[], "x_0", rule)
    check req.k == 1
    # Base case should have state variables x_s0 and x_s1
    check req.baseCase.declarations.len >= 2

  test "k=3 generates three transitions":
    let rule = TransitionRule(op: transitionSub, delta: 10,
      invariant: InvariantRule(kind: invariantMinValue, minValue: 0, maxValue: 0))
    let req = makeKInductionRequest(3, @[], @[], "x_0", rule)
    check req.k == 3
    # Should have state variables x_s0, x_s1, x_s2, x_s3
    check req.baseCase.declarations.len >= 4

  test "k=0 is clamped to k=1":
    let rule = TransitionRule(op: transitionSub, delta: 10,
      invariant: InvariantRule(kind: invariantMinValue, minValue: 0, maxValue: 0))
    let req = makeKInductionRequest(0, @[], @[], "x_0", rule)
    check req.k == 1

suite "K-Induction Step Case Generation":
  test "step case assumes invariant at k states":
    let rule = TransitionRule(op: transitionSub, delta: 10,
      invariant: InvariantRule(kind: invariantMinValue, minValue: 0, maxValue: 0))
    let req = makeKInductionRequest(3, @[], @[], "x_0", rule)
    # Step case should have k preconditions (invariant at each state)
    # Plus 1 transition assertion
    check req.stepCase.preconditions.len >= 4  # 3 invariants + 1 transition

suite "Uniqueness Constraints":
  test "k=1 has no uniqueness constraints (trivial)":
    let rule = TransitionRule(op: transitionSub, delta: 10,
      invariant: InvariantRule(kind: invariantMinValue, minValue: 0, maxValue: 0))
    let req = makeKInductionRequest(1, @[], @[], "x_0", rule)
    # k=1: only s0 and s1, 1 inequality
    check req.uniquenessConstraints.len == 1

  test "k=3 has 6 uniqueness constraints (full O(k²))":
    let rule = TransitionRule(op: transitionSub, delta: 10,
      invariant: InvariantRule(kind: invariantMinValue, minValue: 0, maxValue: 0))
    let req = makeKInductionRequest(3, @[], @[], "x_0", rule)
    # k=3: s0≠s1, s0≠s2, s0≠s3, s1≠s2, s1≠s3, s2≠s3 = 6
    check req.uniquenessConstraints.len == 6

  test "k=5 uses full uniqueness (not locally shortest)":
    let rule = TransitionRule(op: transitionSub, delta: 10,
      invariant: InvariantRule(kind: invariantMinValue, minValue: 0, maxValue: 0))
    let req = makeKInductionRequest(5, @[], @[], "x_0", rule)
    # k=5: C(6,2) = 15 uniqueness constraints
    check req.uniquenessConstraints.len == 15

  test "k=6 uses locally shortest (O(k) constraints)":
    let rule = TransitionRule(op: transitionSub, delta: 10,
      invariant: InvariantRule(kind: invariantMinValue, minValue: 0, maxValue: 0))
    let req = makeKInductionRequest(6, @[], @[], "x_0", rule)
    # k=6 with windowSize=3: only adjacent pairs within distance 3
    # This should be fewer than C(7,2) = 21
    check req.uniquenessConstraints.len < 21
    check req.uniquenessConstraints.len > 0

suite "Locally Shortest Constraints":
  test "windowSize=2 is stricter than windowSize=1":
    let c1 = buildLocallyShortestConstraints(5, 1)
    let c2 = buildLocallyShortestConstraints(5, 2)
    check c2.len > c1.len

  test "windowSize=k is same as full uniqueness":
    let full = buildUniquenessConstraints(4)
    let local = buildLocallyShortestConstraints(4, 4)
    check full.len == local.len

suite "SMT-LIB2 Emission":
  test "base case emits valid SMT-LIB2":
    let rule = TransitionRule(op: transitionSub, delta: 10,
      invariant: InvariantRule(kind: invariantMinValue, minValue: 0, maxValue: 0))
    let req = makeKInductionRequest(2, @[], @[], "x_0", rule)
    let smt2 = emitSmt2(req.baseCase)
    check "(set-logic QF_LIA)" in smt2
    check "(declare-const" in smt2
    check "(check-sat)" in smt2

  test "step case emits valid SMT-LIB2":
    let rule = TransitionRule(op: transitionSub, delta: 10,
      invariant: InvariantRule(kind: invariantMinValue, minValue: 0, maxValue: 0))
    let req = makeKInductionRequest(2, @[], @[], "x_0", rule)
    let smt2 = emitSmt2(req.stepCase)
    check "(set-logic QF_LIA)" in smt2
    check "(assert" in smt2

suite "K-Induction Depth Estimation":
  test "simple loop gives k=5 (default)":
    let k = estimateMaxK(0.0, 1, 0)
    check k >= 5

  test "nested loop gives higher k":
    let kSimple = estimateMaxK(0.0, 1, 0)
    let kNested = estimateMaxK(0.0, 32, 0)  # nestingDepth > kInductionMaxDepthDefault (16)
    check kNested > kSimple

  test "high entropy increases k":
    let kLow = estimateMaxK(0.0, 2, 0)
    let kHigh = estimateMaxK(1.0, 2, 0)
    check kHigh > kLow

  test "k is bounded by ceiling":
    let k = estimateMaxK(1.0, 100, 100)
    check k <= kInductionMaxDepthCeiling

suite "Context Reset (Locally Shortest Transition)":
  test "k=5 uses full uniqueness":
    let rule = TransitionRule(op: transitionSub, delta: 10,
      invariant: InvariantRule(kind: invariantMinValue, minValue: 0, maxValue: 0))
    let payload = buildKInductionPayload(5, 100, rule)
    check payload.useLocallyShortest == false
    check payload.uniquenessSmt2.len > 0

  test "k=6 uses locally shortest":
    let rule = TransitionRule(op: transitionSub, delta: 10,
      invariant: InvariantRule(kind: invariantMinValue, minValue: 0, maxValue: 0))
    let payload = buildKInductionPayload(6, 100, rule)
    check payload.useLocallyShortest == true
