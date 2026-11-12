Feature: Formal Text Diff Classification
  As a gate system
  I want to classify git diff changes by type
  So that pragma-only or comment-only changes skip unnecessary spec requirements

  Background:
    Given a diff text input

  Scenario: Whitespace-only changes are classified as ckWhitespace
    When the diff contains only whitespace changes
    Then the classification should be "ckWhitespace"

  Scenario: Single-line comment changes are classified as ckComment
    When the diff contains only single-line comment changes
    Then the classification should be "ckComment"

  Scenario: Multi-line comment changes are classified as ckComment
    When the diff contains only multi-line comment changes (#[ ]#)
    Then the classification should be "ckComment"

  Scenario: Nested multi-line comments are handled correctly
    When the diff contains nested multi-line comments (#[ #[ ]# ]#)
    Then the classification should be "ckComment"

  Scenario: Pragma-only changes are classified as ckPragma
    When the diff contains only {.push raises: [].} pragma changes
    Then the classification should be "ckPragma"

  Scenario: Multi-line pragma blocks are tracked via FSM
    When the diff contains a {.push .} block spanning multiple lines
    Then the classification should be "ckPragma"

  Scenario: Logic changes are classified as ckLogic
    When the diff contains actual code changes (proc, let, var, etc.)
    Then the classification should be "ckLogic"

  Scenario: Mixed changes default to ckLogic (conservative)
    When the diff contains both pragma and logic changes
    Then the classification should be "ckLogic"

  Scenario: Ambiguous changes default to ckLogic (safe fallback)
    When the diff contains any unclassifiable content
    Then the classification should be "ckLogic"
