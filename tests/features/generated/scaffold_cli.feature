@generated @medium
Feature: scaffold_cli
  # generated | src/cli/scaffold_cli.nim | cli | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "cli/scaffold_cli" is loaded
    Then all exported types should be instantiable
