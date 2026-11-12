@legacy
Feature: Refinement Type System and Liquid Inference
  As a verification engineer
  I want variables to carry SMT predicates as part of their types
  So that loop invariants are derived from types rather than searched

  Scenario: Integer literal gets exact equality refinement type
    Given a variable declaration "var i = 0"
    When liquid inference scans the AST
    Then the inferred type for i should be Int{v | v == 0}

  Scenario: Loop variable widens from exact constant to lower bound
    Given a for loop "for i in 0 ..< n"
    When liquid inference performs Pass 2 widening
    Then the type for i should relax from Int{v | v == 0} to Nat

  Scenario: Loop variable acquires upper bound from condition
    Given a while loop "while i < n"
    And i has been widened to Nat
    When liquid inference performs Pass 3 bound extraction
    Then the type for i should be Int{v | v >= 0 ∧ v < n}

  @deprecated
  Scenario: Liquid refinements feed symbolic invariant synthesis
    Given liquid inference has inferred a loop variable type Int{v | v >= 0}
    When verify-certificates --symbolic synthesizes loop invariants
    Then the liquid predicate should be provided as a Layer 6 invariant candidate
    And the SMT initiation context should include the liquid refinement assertion

  Scenario: Unknown variable falls back to unknown refinement type
    Given a variable name not in the inference environment
    When getRefinementType is queried
    Then the result should be Unknown

  Scenario: SExpr converts to Lean 4 infix syntax correctly
    Given an SExpr representing "a >= 0"
    When sExprToLean is called
    Then the output should be "(a ≥ 0)"

  Scenario: Project builds with all Phase 6 modules
    Given src/core/refinement_types.nim and src/core/type_system/liquid_inference.nim exist
    When nim c src/cli/ax.nim executes
    Then compilation should succeed without errors

  Scenario: Structural induction strategy generates valid Lean 4 proposition
    Given a recursive function with case branches
    When the structural induction strategy generates a semantic hint
    Then the leanProposition should be a valid forall proposition
    And it should not contain the unknown identifier "structural_induction"

  Scenario: Heal pipeline soft-fails from invalid static hint to next strategy
    Given a node where structural induction generates invalid Lean syntax
    When executeHealNode runs the strategy loop
    Then saveHint should reject the invalid proposition
    And the loop should continue to the next strategy without marking the node unverifiable
    And the failure diagnostic should be captured for later Leanstral context

  Scenario: Leanstral receives prior static failure context on invocation
    Given all four static strategies have failed validation for a node
    When tryLeanstralSelfCorrection is invoked
    Then the prompt should contain the accumulated kernel feedback from previous attempts
    And the prompt should instruct the model to avoid the previously failed tactic
