@generated @medium
Feature: wf_state_vacuity
  # generated | src/cli/wf_state_vacuity.nim | cli | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "cli/wf_state_vacuity" is loaded
    Then all exported types should be instantiable
