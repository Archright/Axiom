@generated @medium
Feature: payload_bridge
  # generated | src/cli/payload_bridge.nim | cli | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "cli/payload_bridge" is loaded
    Then all exported types should be instantiable
