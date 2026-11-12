@legacy
Feature: Universal Lean Assembler (ULA)
  As an Axiom developer
  I want all Lean theorem source generation to flow through a single assembler
  So that Lean 4 compatibility fixes (e.g. semicolon stripping, prelude updates) apply uniformly

  Background:
    Given the ULA module "src/translator/universal_assembler.nim" exists

  Scenario: ULA sanitizes Nim semicolons from Lean source
    Given a raw Lean source containing "let a := 1; let b := 2"
    When sanitizeLeanSource is called
    Then the output contains no ";" characters
    And each let-binding appears on its own line

  Scenario: ULA generates prelude with import Std
    When buildLeanPrelude is called
    Then the output contains "import Std"

  Scenario: ULA assembles theorem from SemanticHint
    Given a SemanticHint with proposition "x ≥ 0" and parameter "x : int"
    When buildUniversalLeanSource(nodeId, hint, smtlib2) is called
    Then the output contains "theorem <nodeId>"
    And the output contains "(x : NimInt)"
    And the output contains "x ≥ 0"
    And the output contains ":= by"

  Scenario: ULA assembles theorem from TranslatorContext
    Given a TranslatorContext for function "add" with parameters "a : int", "b : int"
    When buildUniversalLeanSource(ctx) is called
    Then the output contains "import Std"
    And the output contains "theorem add"
    And the output contains "def add"
    And the output contains no ";" characters

  Scenario: Legacy buildLeanQuery is deprecated
    Given a caller imports "src/core/the_judge.nim"
    When buildLeanQuery is invoked
    Then a deprecation warning is emitted pointing to "translator/universal_assembler.nim"

  Scenario: Legacy buildLeanBridge is deprecated
    Given a caller imports "src/verification/ast_to_lean_bridge.nim"
    When buildLeanBridge is invoked
    Then a deprecation warning is emitted pointing to "translator/universal_assembler.nim"
