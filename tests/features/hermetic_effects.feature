Feature: Hermetic Effect Tags
  Compiler-tracked side effect classification tags for purity enforcement.

  Scenario: Effect tag types are defined
    Given the hermetic_effects module is imported
    Then FileIO should be available
    And ProcessExec should be available
    And NetworkIO should be available
    And MutableState should be available

  Scenario: Pure proc compiles with empty tags
    Given a proc annotated with {.tags: [].}
    When the proc does not use FileIO, ProcessExec, NetworkIO, or MutableState
    Then the proc should compile successfully

  Scenario: Impure proc fails to compile with empty tags
    Given a proc annotated with {.tags: [].}
    When the proc calls a function tagged with FileIO
    Then the proc should fail to compile

  Scenario: Effect tags are distinct objects
    Given the hermetic_effects module is imported
    Then FileIO should not equal ProcessExec
    And NetworkIO should not equal MutableState
