@generated @medium
Feature: topology_cli
  # generated | src/cli/commands/topology_cli.nim | cli | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "cli/commands/topology_cli" is loaded
    Then all exported types should be instantiable
