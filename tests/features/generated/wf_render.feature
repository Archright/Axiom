@generated @medium
Feature: wf_render
  # generated | src/cli/wf_render.nim | cli | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "cli/wf_render" is loaded
    Then all exported types should be instantiable
