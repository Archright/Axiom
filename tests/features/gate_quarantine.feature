Feature: Gate Quarantine Wrapper
  As a developer
  I want gate failures from known upstream bugs to be quarantined
  So that pre-commit is not blocked by issues outside our control

  Background:
    Given the quarantine manifest exists at "data/gate_exceptions.json"

  Scenario: Quarantined gate failure is converted to KNOWN_ISSUE
    Given a gate "nimtry-gate" is registered in the quarantine manifest with an unexpired TTL
    When the inner gate runner exits with non-zero code
    Then the quarantine wrapper prints "converted to KNOWN_ISSUE"
    And the wrapper exits with code 0

  Scenario: Non-quarantined gate failure is preserved
    Given a gate is NOT in the quarantine manifest
    When the inner gate runner exits with code 1
    Then the wrapper exits with code 1

  Scenario: Quarantine entry TTL expiry forces re-evaluation
    Given a quarantine entry with expires "2020-01-01"
    When the wrapper checks the manifest
    Then the entry is treated as expired
    And the wrapper exits with the original non-zero code

  Scenario: Quarantined gate PASS is passed through unchanged
    Given a gate "nimtry-gate" is quarantined
    When the inner gate runner exits with code 0
    Then the wrapper passes through exit 0 unchanged
    And no quarantine message is printed

  Scenario: Wrapper catches IndexDefect crash from subprocess
    Given the inner gate crashes with IndexDefect
    When the subprocess returns a non-zero exit code
    Then the quarantine wrapper converts the crash to KNOWN_ISSUE
    And the wrapper exits with code 0
