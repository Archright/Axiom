@legacy
@cli @invisible-observability
Feature: Heal scheduler prioritizes reproofRequired nodes
  Nodes explicitly marked for reproof via auto-detect or sync-state are
  scheduled before all other unverified nodes, ensuring stale certificates
  are resolved as quickly as possible.

  Rule: reproofRequired nodes run before stale, CEGAR, and unattempted tiers
    Scenario: reproofRequired node exists in proof state workflow
      Given the proof state workflow.reproofRequired contains a node
      When the heal scheduler builds the batch
      Then that node is scheduled before non-reproofRequired nodes
      And its heal tier is treated as highest priority
