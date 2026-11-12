@legacy
Feature: ASI Event Sourcing Replayer
  Replays stream.jsonl status_changed events to reconstruct ASI at any point.

  Scenario: Empty stream returns no snapshots
  Scenario: Single verification produces one ASI change
  Scenario: Ledger builds from replay output
