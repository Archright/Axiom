@legacy
Feature: Generalized Colon Filter
  As an Axiom developer
  I want all Nim type annotations stripped from Lean source
  So that Lean 4 'unexpected token :' syntax errors are eliminated

  Scenario: Custom types are stripped
    Given a Lean source line "let sym : NimTopologySymbol = getSymbol()"
    When sanitizeLeanSource is called
    Then the output contains "let sym :="
    And "NimTopologySymbol" is absent

  Scenario: Generic compound types are stripped
    Given a Lean source line "let s : NimSeq (NimString) = emptySeq()"
    When sanitizeLeanSource is called
    Then the output contains "let s :="

  Scenario: seq[T] types are stripped
    Given a Lean source line "var items : seq[string] = @[]"
    When sanitizeLeanSource is called
    Then the output contains "var items :="

  Scenario: Stray colons are flagged
    Given a Lean source with a stray colon in a def block
    When sanitizeLeanSource is called
    Then the output contains a sanity warning
