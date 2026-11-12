@generated @medium
Feature: mcp_params
  # generated | src/mcp/mcp_params.nim | mcp | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "mcp/mcp_params" is loaded
    Then all exported types should be instantiable
