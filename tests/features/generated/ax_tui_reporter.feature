@generated @medium
Feature: ax_tui_reporter
  # generated | src/ui/ax_tui_reporter.nim | ui | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "ui/ax_tui_reporter" is loaded
    Then all exported types should be instantiable
