@generated @medium
Feature: wf_state
  # generated | src/cli/wf_state.nim | cli | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "cli/wf_state" is loaded
    Then all exported types should be instantiable
