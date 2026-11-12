@generated @medium
Feature: execution_policy
  # generated | src/cli/execution_policy.nim | cli | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "cli/execution_policy" is loaded
    Then all exported types should be instantiable
