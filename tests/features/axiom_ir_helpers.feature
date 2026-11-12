@legacy
Feature: Axiom Core IR Helper Constructors
  Provides concise constructors and pretty-printers for building Axiom Core
  IR trees. All operations are pure-functional with no side effects.

  Background:
    Given the Axiom system is initialized

  Scenario: irLit creates integer literal expression
    When irLit is called with an integer value
    Then the result is an IRExpr of kind irLit

  Scenario: irVar creates variable reference
    When irVar is called with a name and type
    Then the result is an IRExpr of kind irVar

  Scenario: Pretty-printing produces valid output
    When irPretty is called on any IRExpr
    Then the output is a non-empty string
