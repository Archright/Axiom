@generated @medium
Feature: version
  # generated | src/cli/version.nim | cli | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "cli/version" is loaded
    Then all exported types should be instantiable
