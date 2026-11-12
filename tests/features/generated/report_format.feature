@generated @medium
Feature: report_format
  # generated | src/cli/report_format.nim | cli | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "cli/report_format" is loaded
    Then all exported types should be instantiable
