@generated @medium
Feature: action_interpreter_cli
  # generated | src/cli/action_interpreter_cli.nim | cli | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "cli/action_interpreter_cli" is loaded
    Then all exported types should be instantiable
