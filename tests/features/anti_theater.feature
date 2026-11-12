Feature: Anti-Theater Gate — Theater Prohibition Enforcement
  As the Axiom integrity engine
  I want to detect theater signatures in git staged additions
  So that code that claims guarantees without substance is blocked at commit time

  Background:
    Given the Anti-Theater Gate module is available
    And the gate is configured for pre-commit scanning

  Scenario: Untagged `except: discard` in Nim source fails the gate
    Given a .nim file with a staged addition of "except: discard"
    When the anti-theater gate runs on the staged diff
    Then the gate reports a S2 violation
    And the gate exits with code 1

  Scenario: Tagged `except: discard` with best-effort tag passes
    Given a .nim file with a staged addition of "except: discard # axiom:best-effort(refactor pending)"
    When the anti-theater gate runs on the staged diff
    Then the gate reports no S2 violation
    And the gate exits with code 0

  Scenario: `|| true` in Makefile without tag fails the gate
    Given a Makefile with a staged addition of "  || true"
    When the anti-theater gate runs on the staged diff
    Then the gate reports a C violation
    And the gate exits with code 1

  Scenario: `check true` in test file without tag fails the gate
    Given a test .nim file with a staged addition of "check true"
    When the anti-theater gate runs on the staged diff
    Then the gate reports a S1 violation
    And the gate exits with code 1

  Scenario: Clean change with no theater signatures passes
    Given a .nim file with a staged addition of "result = validate(input)"
    When the anti-theater gate runs on the staged diff
    Then the gate reports no violations
    And the gate exits with code 0

  Scenario: `|| rm -rf` in Makefile is flagged as a known-dangerous swallow
    Given a Makefile with a staged addition of "  command || rm -rf build/"
    When the anti-theater gate runs on the staged diff
    Then the gate reports a C violation
    And the gate exits with code 1

  Scenario: `|| exit 1` in Makefile is not flagged (fail-closed, not a swallow)
    Given a Makefile with a staged addition of "  command || exit 1"
    When the anti-theater gate runs on the staged diff
    Then the gate reports no violations
    And the gate exits with code 0
