@legacy
Feature: Lean Reserved Identifier Filter
  As an Axiom developer
  I want Lean reserved words filtered from variable declarations
  So that Leanstral does not generate invalid variable (import : α) declarations

  Scenario: import is filtered to v_import
    Given sanitizeLeanIdentifierName is called with "import"
    Then the result is "v_import"

  Scenario: Std and Bridge keywords are filtered
    Given sanitizeLeanIdentifierName is called with "Std"
    Then the result is "v_Std"
