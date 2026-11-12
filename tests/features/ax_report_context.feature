@legacy
@cli @invisible-observability
Feature: ax report embedded Recent Batch Context
  ax report automatically includes a summary of recent status changes
  without requiring new flags or commands.

  Rule: ax report shows Recent Batch Context on every run
    Scenario: First report after feature activation
      When I run "ax report"
      Then stdout contains "Recent Batch Context:"
      And stdout contains "status change" or "All nodes stable"

    Scenario: Second consecutive report with no changes
      When I run "ax report"
      And I run "ax report" again
      Then stdout contains "Recent Batch Context:"
      And stdout contains "0 status changes"
      And stdout contains "All nodes stable."
