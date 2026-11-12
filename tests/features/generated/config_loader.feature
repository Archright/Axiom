@generated @medium
Feature: config_loader
  # generated | src/cli/config_loader.nim | cli | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "cli/config_loader" is loaded
    Then all exported types should be instantiable
