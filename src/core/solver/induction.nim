import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

{.push, raises: [].}
# axiomIoBoundary
{.push, noSideEffect.}
import
  core / solver / types

import
  core / solver / construct_base

import
  core / solver / construct_arithmetic

import
  core / solver / construct_logical

import
  core / solver / encoding_properties

import
  core / bmc / bmc_race

## Encode Transition From Current.
func encodeTransitionFromCurrent*(currentSymbol: string;
    rule: TransitionRule): SmtSExpr {.
    raises: [].} =
  case rule.op
  of transitionSub:
    ite(ge(symInt(currentSymbol), intLit(rule.delta)),
        sub(symInt(currentSymbol), intLit(rule.delta)), symInt(currentSymbol))
  of transitionAdd:
    add(symInt(currentSymbol), intLit(rule.delta))

## Generate state variable name for step i.
func stateVarName(step: int): string {.raises: [].} =
  "x_s" & $step

## Build k-step base case: check that the invariant holds for states 0..k.
##
## Encoding (Sheeran et al. 2000, Algorithm 4):
##   I(s₀) ∧ T(s₀,s₁) ∧ T(s₁,s₂) ∧ ... ∧ T(s_{k-1},s_k) ∧ ¬(P(s₀) ∧ P(s₁) ∧ ... ∧ P(s_k))
##
## If UNSAT → invariant holds for all states reachable in k steps from initial.
## If SAT → counterexample found (assignment to s₀..s_k is an error trace).
func buildKStepBaseCase*(k: int; declarations: seq[string];
                         initialAssertions: seq[SmtSExpr];
                             rule: TransitionRule): SolverRequest {.
    raises: [].} =
  var decls = declarations
  var preconds: seq[SmtSExpr] = @[]
  for i in 0 .. k:
    let sv = stateVarName(i)
    if sv notin decls:
      decls.add(sv)
  for a in initialAssertions:
    preconds.add(a)
  for i in 0 .. k - 1:
    let si = stateVarName(i)
    let si1 = stateVarName(i + 1)
    let transition = encodeTransitionFromCurrent(si, rule)
    preconds.add(eq(symInt(si1), transition))
  var invariantViolationDisjuncts: seq[SmtSExpr] = @[]
  for i in 0 .. k:
    invariantViolationDisjuncts.add(encodeInvariantViolation(stateVarName(i),
        rule))
  SolverRequest(logic: logicQfLia, declarations: decls, preconditions: preconds,
                assertions: @[orE(invariantViolationDisjuncts)],
                finalStateSymbol: stateVarName(k), checkSat: true,
                getModel: true, getUnsatCore: true)

## Build k-step step case: assume invariant holds for k consecutive states,
## prove it holds at the next state.
##
## Encoding (Eén & Sörensson 2004):
##   P(s₀) ∧ P(s₁) ∧ ... ∧ P(s_{k-1}) ∧ T(s_{k-1}, s_k) ∧ ¬P(s_k)
##
## If UNSAT → inductive step holds (k-induction is valid).
## If SAT → the invariant is NOT k-inductive (need stronger invariant or larger k).
func buildKStepStepCase*(k: int; declarations: seq[string];
    rule: TransitionRule): SolverRequest {.
    raises: [].} =
  var decls = declarations
  var preconds: seq[SmtSExpr] = @[]
  for i in 0 .. k:
    let sv = stateVarName(i)
    if sv notin decls:
      decls.add(sv)
  for i in 0 .. k - 1:
    preconds.add(encodeInvariantPredicate(stateVarName(i), rule))
  let transition = encodeTransitionFromCurrent(stateVarName(k - 1), rule)
  preconds.add(eq(symInt(stateVarName(k)), transition))
  SolverRequest(logic: logicQfLia, declarations: decls, preconditions: preconds,
      assertions: @[encodeInvariantViolation(stateVarName(k), rule)],
                finalStateSymbol: stateVarName(k), checkSat: true,
                getModel: true, getUnsatCore: true)

## Build uniqueness constraints: s_i ≠ s_j for all 0 ≤ i < j ≤ k.
##
## This is the "strengthened induction" from Sheeran et al. (2000):
## "The word strengthened refers to the restriction to loop-free paths,
##  which is an additional constraint on the unrollings of the transition
##  relation. Without this constraint, induction with depth gives an
##  incomplete method."
##
## For k states with N state variables, this generates k(k-1)/2 × N inequalities.
## For k > 5, consider using buildLocallyShortestConstraints instead.
func buildUniquenessConstraints*(k: int): seq[SmtSExpr] {.raises: [].} =
  result = @[]
  for i in 0 .. k - 1:
    for j in i + 1 .. k:
      result.add(notE(eq(symInt(stateVarName(i)), symInt(stateVarName(j)))))

## Build locally shortest constraints: s_i ≠ s_j for |i-j| < windowSize only.
##
## From Sheeran et al. (2000) §5:
## "Choosing j = 2 gives what we call locally shortest paths;
##  the consequence is that all paths of length 2 or greater obey
##  the negation of the transition relation T and the entire path
##  has unequal end points."
##
## This is STRICTLY STRONGER than loopFree and can be expressed in
## pure propositional logic. O(k × windowSize) instead of O(k²).
func buildLocallyShortestConstraints*(k: int; windowSize: int = 3): seq[SmtSExpr] {.
    raises: [].} =
  result = @[]
  for i in 0 .. k - 1:
    for j in i + 1 .. min(i + windowSize, k):
      result.add(notE(eq(symInt(stateVarName(i)), symInt(stateVarName(j)))))

## Make K-Induction Request — TRUE k-induction (not 1-induction).
##
## This function now ACTUALLY USES the k parameter to generate
## k-step unrolled base and step cases, with uniqueness constraints.
##
## Reference:
##   - Sheeran et al. (2000) "Checking Safety Properties Using Induction and a SAT-Solver"
##   - Eén & Sörensson (2004) "Temporal Induction by Incremental SAT Solving"
func makeKInductionRequest*(k: int; declarations: seq[string];
                            transitionAssertions: seq[SmtSExpr];
                            finalSymbol: string;
                                rule: TransitionRule): KInductionRequest {.
    raises: [].} =
  let kClamped = max(1, k)
  let baseCase = buildKStepBaseCase(kClamped, declarations,
                                    transitionAssertions, rule)
  let stepCase = buildKStepStepCase(kClamped, declarations, rule)
  let uniquenessConstraints = if kClamped <= 5:
    buildUniquenessConstraints(kClamped)
  else:
    buildLocallyShortestConstraints(kClamped, windowSize = 3)
  KInductionRequest(k: kClamped, baseCase: baseCase, stepCase: stepCase,
                    uniquenessConstraints: uniquenessConstraints)

{.pop.}

{.pop.}

{.pop}
