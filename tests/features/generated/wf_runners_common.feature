@generated @medium
Feature: wf_runners_common
  # generated | src/cli/wf_runners_common.nim | cli | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "cli/wf_runners_common" is loaded
    Then all exported types should be instantiable
