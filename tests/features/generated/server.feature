@generated @medium
Feature: server
  # generated | src/mcp/server.nim | mcp | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "mcp/server" is loaded
    Then all exported types should be instantiable
