@legacy
@cli @invisible-observability
Feature: Compact transitionLog in ax_proof_state.json
  Every proof state entry maintains a capped history of status transitions
  directly inside the JSON document, eliminating the need for external query tools.

  @deprecated
  Rule: transitionLog is present after ax prove or ax report --sync-state
    Scenario: ax prove updates transitionLog
      When I run "ax prove --limit 10"
      Then logs/ax_proof_state.json contains transitionLog in every entry
      And each transitionLog has at most 10 entries

    Scenario: transitionLog caps at 10 entries
      Given a node has 10 existing transitionLog entries
      When its status changes again
      Then the oldest entry is removed
      And the new entry is appended

    Scenario: renderRecentBatchContext tolerates missing transitionLog
      Given a proof state entry lacks transitionLog
      When ax report renders recent batch context
      Then no segmentation fault occurs
      And the output shows 0 status changes
