@generated @medium
Feature: observability
  # generated | src/cli/commands/observability.nim | cli | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "cli/commands/observability" is loaded
    Then all exported types should be instantiable
