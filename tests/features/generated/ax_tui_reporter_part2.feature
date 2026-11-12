@generated @medium
Feature: ax_tui_reporter_part2
  # generated | src/ui/ax_tui_reporter_part2.nim | ui | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "ui/ax_tui_reporter_part2" is loaded
    Then all exported types should be instantiable
