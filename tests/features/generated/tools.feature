@generated @medium
Feature: tools
  # generated | src/mcp/tools.nim | mcp | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "mcp/tools" is loaded
    Then all exported types should be instantiable
