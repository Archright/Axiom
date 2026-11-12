Feature: Dead Code Detection Gate
  As the Axiom integrity engine,
  I want a gate that detects dead code (unexported procs with zero callers),
  So that unused code is systematically removed and code health improves.

  Background:
    Given the Axiom gate infrastructure is initialized
    And the dead code whitelist is loaded

  Scenario: Dead code with no callers is detected
    Given an unexported proc "internalHelper" defined in "src/core/example.nim"
    And no other file in src/ references "internalHelper"
    And "internalHelper" is not in the whitelist
    When the dead code gate runs
    Then the gate reports dead code for "internalHelper"
    And the gate exits with code 1

  Scenario: Whitelisted symbol is skipped
    Given an unexported proc "shouldSkipGate" defined in "src/core/example.nim"
    And no other file in src/ references "shouldSkipGate"
    And "shouldSkipGate" is in the whitelist with a future expiry
    When the dead code gate runs
    Then the gate does not report dead code for "shouldSkipGate"
    And the gate exits with code 0

  Scenario: Expired whitelist entry triggers warning
    Given an unexported proc "oldHelper" defined in "src/core/example.nim"
    And no other file in src/ references "oldHelper"
    And "oldHelper" is in the whitelist with an expired expiry date
    When the dead code gate runs
    Then the gate emits a warning for expired whitelist entry "oldHelper"
    And the gate still exits with code 0

  Scenario: Exported procs are excluded from dead code check
    Given an exported proc "publicApi" defined in "src/core/example.nim"
    And no other file in src/ references "publicApi"
    When the dead code gate runs
    Then the gate does not report dead code for "publicApi"
    And the gate exits with code 0
