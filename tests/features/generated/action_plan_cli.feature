@generated @medium
Feature: action_plan_cli
  # generated | src/cli/action_plan_cli.nim | cli | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "cli/action_plan_cli" is loaded
    Then all exported types should be instantiable
