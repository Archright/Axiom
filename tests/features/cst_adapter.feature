@legacy
@executable
Feature: CstAdapter tree-sitter CST parsing
  As an Axiom developer
  I want to parse Nim source code into a concrete syntax tree via tree-sitter
  So that integrity verification can inspect syntax structure without full semantic analysis

  Background:
    Given the Axiom CLI is compiled and available
    And the tree-sitter Nim grammar is vendored

  # ── CstDocument lifecycle ──────────────────────────────────────────────────

  Scenario: Parse valid Nim source — function declaration
    Given embedded Nim source containing a function declaration
    When CstDocument parses the source with the Nim language grammar
    Then the parse succeeds without errors
    And the root node is an internal node (cstInternal)
    And the source text is preserved in the document

  Scenario: Parse valid Nim source — type declaration
    Given embedded Nim source containing a type declaration
    When CstDocument parses the source with the Nim language grammar
    Then the parse succeeds without errors
    And the root node has at least one named child

  Scenario: Parse valid Nim source — enum declaration
    Given embedded Nim source containing an enum declaration
    When CstDocument parses the source with the Nim language grammar
    Then the parse succeeds without errors
    And the root node is named

  Scenario: Parse invalid Nim source — graceful error handling
    Given embedded Nim source with syntax errors
    When CstDocument attempts to parse the source
    Then the document is created without crashing
    And the root node can still be obtained from the document

  # ── Node extraction and navigation ─────────────────────────────────────────

  Scenario: Extract function names from parsed source
    Given embedded Nim source containing function declarations
    When CstDocument parses the source
    And the root node children are enumerated
    Then each child has a valid node type string
    And each child has a valid byte-offset span

  Scenario: TreeSitterCstNode navigation — children and childCount
    Given embedded Nim source with multiple top-level declarations
    When CstDocument parses the source
    And the root node childCount is queried
    Then childCount equals the number of named children
    And calling children returns a sequence of that length

  Scenario: TreeSitterCstNode text extraction
    Given embedded Nim source containing a function declaration
    When CstDocument parses the source
    And the root node text is extracted
    Then the text matches a contiguous slice of the original source

  # ── Byte offset tracking ───────────────────────────────────────────────────

  Scenario: Span byte offsets cover entire source
    Given embedded Nim source of known byte length
    When CstDocument parses the source
    And the root node span is queried
    Then span.start equals 0
    And span.endPos equals the byte length of the source

  Scenario: Child spans are within parent span
    Given embedded Nim source with multiple top-level declarations
    When CstDocument parses the source
    And the root node and its children spans are queried
    Then each child span start is >= the root span start
    And each child span end is <= the root span end

  # ── Graceful degradation ───────────────────────────────────────────────────

  Scenario: Parser unavailability returns error
    Given tree-sitter is not vendored in the build
    When CstDocument attempts to create a new document
    Then the result is an error
    And the error message indicates parser creation failure
