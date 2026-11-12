@legacy
Feature: Nim to Lean Spec Generator
  AST-driven translation from Nim source to Lean 4 structures and definitions.

  Background:
    Given the Axiom CLI is built at "bin/ax"
    And spec_generator module exists at "src/core/spec_generator.nim"
    And tree_sitter_bridge module exists at "src/core/tree_sitter_bridge.nim"

  Scenario: Generic parameters are extracted from type and function declarations
    Given a source with "Bucket[T] = object" and "foldAll[T](values: openArray[T])"
    When generateLeanSpecFromSources is called
    Then the output contains "structure Bucket (T : Type) where"
    And the output contains "def foldAll {T : Type} [Inhabited T]"

  Scenario: Return types are extracted from proc declarations
    Given a source with "proc withdraw(balance: int; amount: Natural): int"
    When generateLeanSpecFromSources is called
    Then the output contains "def withdraw (balance : Int) (amount : Nat) : Int := 0"

  Scenario: I/O side effects are detected via AST identifier traversal
    Given a source with "proc noisy(msg: string): int = echo msg"
    When generateLeanSpecFromSources is called
    Then "noisy" is classified as untrusted
    And warnings contain "I/O call pattern detected"
    And "def noisy" is not present in the generated code

  Scenario: Forward declarations without body are skipped
    Given a source with "func reasoningPathToCborHex(path: ReasoningPath): string" (no body)
    And "func parseLengthField(payload: string; startIndex: int): Result[(int, int), AxiomError] = discard"
    When generateLeanSpecFromSources is called
    Then "def reasoningPathToCborHex" is not present
    And "def parseLengthField" is present

  Scenario: Local type aliases inside templates are excluded
    Given a source with "template localAlias(v: int): untyped = block: type R = typeof(result)"
    When generateLeanSpecFromSources is called
    Then "abbrev R" is not present

  Scenario: Proc types are mapped to Unit
    Given a source with "Sink = proc(event: string) {.gcsafe, closure.}"
    When generateLeanSpecFromSources is called
    Then the output contains "abbrev Sink := Unit"

  Scenario: Tree-sitter partial parses are accepted for exported symbols
    Given a source with exported generic types like "Bucket[T]* = object"
    When generateLeanSpecFromSources is called
    Then tree-sitter parse errors do not abort the translation
    And the output still contains "structure Bucket (T : Type) where"
