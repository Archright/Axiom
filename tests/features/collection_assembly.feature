@legacy
Feature: Collection and Assembly Import Architecture
  As an Axiom developer
  I want imports captured from body and relocated to file top
  So that Lean 4 import positioning errors are eliminated

  Scenario: Body imports are captured and removed
    Given a Lean body containing "import Std.Tactic"
    When sanitizeLeanSource is called
    Then the import is captured in the returned list
    And the import is removed from the body

  Scenario: Zone ordering puts imports before variables
    Given static and dynamic imports with variables
    When assembleZones is called
    Then all imports appear before variable declarations
