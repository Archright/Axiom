@generated @medium
Feature: wf_state_parsing
  # generated | src/cli/wf_state_parsing.nim | cli | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "cli/wf_state_parsing" is loaded
    Then all exported types should be instantiable
