@legacy
Feature: Proof Universe Lock Gate
  Merkle verification gate with fast-path timestamp check and slow-path regeneration.

  Scenario: Fresh lock file passes without regeneration
  Scenario: Stale lock triggers proof regeneration
  Scenario: Timeout on regeneration is non-blocking
  Scenario: Missing lock file triggers regeneration
  Scenario: Certificate modification newer than lock triggers regeneration
