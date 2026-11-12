@legacy
Feature: Lean LSP Client — Type Safety and Error Boundary
  Verifies that the Lean LSP client infrastructure maintains type
  integrity, proper error wrapping, and correct negative-test generation.

  Background:
    Given the Axiom CLI is built at "bin/ax"
    And lean_lsp module exists at "src/verification/lean_lsp.nim"

  Scenario: AxiomLspError wraps CatchableError correctly
    Given an AxiomLspError instance
    When it is caught as CatchableError
    Then the message preserves the original cause

  Scenario: LeanSearchResult initializes with safe defaults
    Given a default LeanSearchResult
    When fields are inspected
    Then succeeded is false
    And attempts is 0
    And finalTactic is empty
    And diagnostics is empty

  Scenario: LeanCompilerResult initializes with safe defaults
    Given a default LeanCompilerResult
    When fields are inspected
    Then verified is false
    And exitCode is 0
    And diagnostics is empty

  Scenario: buildNegativeTestSource transforms theorem correctly
    Given a valid Lean theorem source with ":= by"
    When buildNegativeTestSource is called
    Then the result replaces the conclusion with False
    And the proof block is preserved

  Scenario: buildNegativeTestSource returns empty for non-theorem
    Given a source string without ":= by"
    When buildNegativeTestSource is called
    Then the result is an empty string
