@generated @medium
Feature: ax_workflow_cli
  # generated | src/cli/ax_workflow_cli.nim | cli | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "cli/ax_workflow_cli" is loaded
    Then all exported types should be instantiable
