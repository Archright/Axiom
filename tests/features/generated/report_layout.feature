@generated @medium
Feature: report_layout
  # generated | src/cli/report_layout.nim | cli | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "cli/report_layout" is loaded
    Then all exported types should be instantiable
