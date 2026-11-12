@generated @medium
Feature: report_render
  # generated | src/cli/report_render.nim | cli | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "cli/report_render" is loaded
    Then all exported types should be instantiable
