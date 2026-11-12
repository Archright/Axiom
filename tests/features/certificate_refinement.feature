@legacy
Feature: Certificate Refinement Source Patching

  Background:
    Given the Axiom CLI is available

  Scenario: Apply amount-balance constraint to source
    Given a Nim source containing a function with amount and balance parameters
    And refinement suggestions include "amount <= balance"
    When applyRefinementSuggestionsToSource is invoked
    Then the result changed flag should be true
    And the updated source should contain "assert amount <= balance"

  Scenario: Skip source without matching suggestions
    Given a Nim source with no amount or balance parameters
    And refinement suggestions include "non-negative bound"
    When applyRefinementSuggestionsToSource is invoked
    Then the result changed flag should be false
    And the appliedConstraints list should be empty
