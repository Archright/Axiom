@legacy
Feature: SMT-to-Lean Type-Aware Translation
  As an Axiom verification pipeline
  I want malformed SMT patterns from contract extractor and axiom-hints to be sanitized
  So that generated Lean evidence compiles even when human-written hints contain type mismatches

  Background:
    Given the Axiom SMT-to-Lean bridge is loaded
    And the type-aware translator is active

  Scenario: option.isNone equality emits true
    Given an SMT assertion `(= (option.isNone x) true)`
    When `smtExprToLeanExpr` is called with type map
    Then the result should contain `true`

  Scenario: Incompatible type equality emits true
    Given an SMT assertion `(= opencodePath fallback)` where opencodePath is String and fallback is Int
    When `smtExprToLeanExpr` is called with type map
    Then the result should be `true`

  Scenario: Negative literal compared with Nat emits true
    Given an SMT assertion `(= exitCode -1)` where exitCode is Nat
    When `smtExprToLeanExpr` is called with type map
    Then the result should be `true`

  Scenario: Bool comparison with numeric emits true
    Given an SMT assertion `(>= emitJson 0)` where emitJson is Bool
    When `smtExprToLeanExpr` is called with type map
    Then the result should be `true`

  Scenario: Numeric less than String length appends dot length
    Given an SMT assertion `(< i args)` where args is String
    When `smtExprToLeanExpr` is called with type map
    Then the result should contain `args.length`

  Scenario: Bare numeric literal in and is coerced to Prop
    Given an SMT assertion `(and 1 3 5)`
    When `smtExprToLeanExpr` is called
    Then the result should contain `1 ≠ 0`
    And the result should contain `3 ≠ 0`

  Scenario: Reserved keyword function name appends suffix
    Given a function name `initialize`
    When `sanitizeLeanIdentifier` is called
    Then the result should be `initialize_thm`

  Scenario: Bundle deduplication prevents duplicate theorem names
    Given two certificates pointing to the same modulePath and functionName
    When `recertify-lean` builds a bundle
    Then the bundle should contain exactly one theorem for that function
