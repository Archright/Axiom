@legacy
Feature: Axiomatic Reconstructor generates primitive proofs from SMT-LIB2
  The SMT-LIB2 to Lean 4 bridge must replace sorry with kernel-verifiable
  axioms for all observed assertion patterns.

  Background:
    Given the axiomatic reconstructor is initialized

  Rule: Common inequality patterns produce Nat.zero_le proofs
    Scenario: Depth bound assertion
      Given an SMT assertion "(assert (>= depth 0))"
      When the reconstructor generates a Lean theorem
      Then the theorem contains "Nat.zero_le depth"
      And the theorem does not contain "sorry"

    Scenario: String length assertion
      Given an SMT assertion "(assert (>= (str.len s) 0))"
      When the reconstructor generates a Lean theorem
      Then the theorem contains "Nat.zero_le s.length"
      And the theorem does not contain "sorry"

  Rule: Conjunction patterns produce constructor with subproofs
    Scenario: And assertion with two non-negative bounds
      Given an SMT assertion "(assert (and (>= (str.len raw) 0) (>= startIdx 0)))"
      When the reconstructor generates a Lean theorem
      Then the theorem contains "constructor"
      And the theorem contains "Nat.zero_le"
      And the theorem does not contain "sorry"

    Scenario: And assertion with three conjuncts including nested or
      Given an SMT assertion "(assert (and (>= (str.len node_atom) 0) (>= (seq.len node_children) 0) (or (= node_isList true) (= node_isList false))))"
      When the reconstructor generates a Lean theorem
      Then the theorem contains "constructor"
      And the theorem contains "Nat.zero_le node_atom.length"
      And the theorem contains "Nat.zero_le node_children.length"
      And the theorem contains "simp"
      And the theorem does not contain "sorry"

  Rule: Reflexivity patterns produce Eq.refl proofs
    Scenario: Self-equality assertion
      Given an SMT assertion "(assert (= x x))"
      When the reconstructor generates a Lean theorem
      Then the theorem contains "Eq.refl"
      And the theorem does not contain "sorry"
