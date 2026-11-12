@manual
Feature: Policy Validator — Self-Validating Policy Enforcement

  As an Axiom developer
  I want policy files to be automatically validated, deduplicated, and normalized
  So that human errors like duplicates or format violations never corrupt the SSOT

  Background:
    Given the policy validator binary exists at "bin/policy_validator"
    And the impure modules file exists at "src/verification/.physically_impure_modules"
    And the allowed imports file exists at "src/allowed_imports.lock"

  Scenario: Policy validator passes on clean policy files
    When I run "bin/policy_validator"
    Then the exit code is 0
    And stdout contains "[policy-validator] PASS"

  Scenario: Policy validator detects duplicate modules in impure modules file
    Given the impure modules file contains a duplicate module entry
    When I run "bin/policy_validator"
    Then the exit code is 1
    And stderr contains "duplicate module"

  Scenario: Policy validator detects malformed allowed_imports.lock entry
    Given the allowed imports file contains a line without "/org/project" prefix
    When I run "bin/policy_validator"
    Then the exit code is 1
    And stderr contains "malformed entry"

  Scenario: Policy validator --fix deduplicates impure modules file
    Given the impure modules file contains duplicate entries
    When I run "bin/policy_validator --fix"
    Then the exit code is 0
    And the impure modules file contains only unique sorted module names

  Scenario: Policy validator --fix preserves header comment in impure modules file
    Given the impure modules file has a valid header comment
    When I run "bin/policy_validator --fix"
    Then the impure modules file still contains the header comment
