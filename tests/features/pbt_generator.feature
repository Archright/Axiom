Feature: PBT Generator (Nim)

  Scenario: Generate PBT test modules from source
    Given a set of Nim source modules in src/
    When the pbt_generator tool is invoked
    Then PBT test stub files are generated for each module
    And the generated files compile without errors

  Scenario: Deterministic output
    Given the same source modules
    When the pbt_generator is invoked twice
    Then the output is identical both times
