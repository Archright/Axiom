@generated @medium
Feature: wf_semantic
  # generated | src/cli/wf_semantic.nim | cli | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "cli/wf_semantic" is loaded
    Then all exported types should be instantiable
