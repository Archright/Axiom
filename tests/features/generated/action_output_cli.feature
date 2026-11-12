@generated @medium
Feature: action_output_cli
  # generated | src/cli/action_output_cli.nim | cli | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "cli/action_output_cli" is loaded
    Then all exported types should be instantiable
