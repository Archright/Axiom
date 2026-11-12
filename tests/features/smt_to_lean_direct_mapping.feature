@legacy
Feature: SMT-to-Lean Direct Mapping Foundation
  As an Axiom verification pipeline
  I want Z3 proof traces to be collected and simple SMT patterns mapped to Lean tactics
  So that future Wave 8 reconstruction has raw material and basic inequalities pass immediately

  Background:
    Given the Axiom SMT-to-Lean bridge is loaded
    And Z3 is available on the system path

  Scenario: Linear arithmetic inequality emits linarith tactic
    Given an SMT assertion `(> x 5)`
    When `assemblePrimitiveProof` is called
    Then the result should contain `linarith`

  Scenario: String length assertion emits exact hypothesis
    Given an SMT assertion `(>= (str.len s) 0)`
    When `assemblePrimitiveProof` is called
    Then the result should contain `exact`

  Scenario: Conjunction emits constructor + bullet proofs
    Given an SMT assertion `(and (> x 5) (< x 10))`
    When `assemblePrimitiveProof` is called
    Then the result should contain `constructor`
    And the result should contain `·`

  Scenario: SMT-LIB2 produces valid Lean theorem skeleton
    Given an SMT-LIB2 query with `(declare-const x Int)` and `(assert (> x 5))`
    When `buildLeanProofFromSmtlib2` is called
    Then the output should contain `theorem`
    And the output should contain `import Std`
    And the output should contain a `by` block

  Scenario: Z3 proof trace is collected on unsat result
    Given a valid SemanticHint with an unsatisfiable negation
    When `extractZ3ProofTrace` is called
    Then a non-empty proof trace string should be returned
    And the trace should start with `(` (s-expression)

  Scenario: Z3 proof trace file is persisted by saveHint
    Given a valid SemanticHint that passes all gates
    When `saveHint` completes successfully
    Then a file named `<safeId>_z3_proof.txt` should exist in `logs/evidence/`

  Scenario: Disjunction pattern emits aesop tactic
    Given an SMT assertion `(or (> x 5) (< x 0))`
    When `assemblePrimitiveProof` is called
    Then the result should contain `aesop`

  Scenario: Implication pattern emits intro + linarith
    Given an SMT assertion `(=> (> x 0) (> x -1))`
    When `assemblePrimitiveProof` is called
    Then the result should contain `intro`
    And the result should contain `linarith`

  Scenario: Negation pattern emits intro + contradiction
    Given an SMT assertion `(not (> x x))`
    When `assemblePrimitiveProof` is called
    Then the result should contain `intro`
    And the result should contain `contradiction`

  Scenario: Arithmetic equality emits linarith
    Given an SMT assertion `(= x y)` with declared Int variables
    When `assemblePrimitiveProof` is called
    Then the result should contain `linarith`

  Scenario: Z3 proof trace is extracted when proof=true
    Given a Z3 solver output containing `unsat` followed by an s-expression proof
    When `extractZ3ProofTrace` is called
    Then the returned trace should be non-empty
    And the trace should start with `(`

  Scenario: Proof trace decompiles to Lean proof script
    Given a Z3 proof trace `(proof (rewrite (= x x)) (mp ...))`
    When `buildLeanProofScriptFromTrace` is called
    Then the output should contain `by`
    And the output should contain at least one tactic

  Scenario: Rewrite step decompiles to rw tactic
    Given a Z3 proof node `rewrite` with rule `add_comm`
    When `z3ProofNodeToLeanTactic` is called
    Then the result should contain `rw [add_comm]`

  Scenario: Quantifier instantiation decompiles to specialize
    Given a Z3 proof node `quant-inst` with witness `n`
    When `z3ProofNodeToLeanTactic` is called
    Then the result should contain `specialize n`

  Scenario: Unit resolution decompiles to cases
    Given a Z3 proof node `unit-resolution` with children
    When `z3ProofNodeToLeanTactic` is called
    Then the result should contain `cases`
