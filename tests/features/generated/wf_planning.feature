@generated @medium
Feature: wf_planning
  # generated | src/cli/wf_planning.nim | cli | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "cli/wf_planning" is loaded
    Then all exported types should be instantiable
