@generated @medium
Feature: protocol
  # generated | src/mcp/protocol.nim | mcp | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "mcp/protocol" is loaded
    Then all exported types should be instantiable
