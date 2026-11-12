@legacy
@cli @invisible-observability
Feature: Certificate solverMeta persistence
  Every certificate written by the heal pipeline includes solver metadata
  for post-hoc audit and debugging.

  Rule: Certificates contain solverMeta after heal
    @deprecated
    Scenario: ax prove --heal successfully verifies a node
      When I run "ax prove --heal --force --limit 1 --filter <nodeId>"
      Then the certificate JSON for that node contains "solverMeta"
      And solverMeta.leanCompilerVerified is true
      And solverMeta.vacuityChecked is true
      And solverMeta.lastVerifiedAt is a valid ISO-8601 timestamp
