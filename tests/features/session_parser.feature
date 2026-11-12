@legacy
Feature: Session Parser
  AxiomSession construction and invariant extraction.

  Scenario: makeAxiomSession creates valid session with required fields
  Scenario: makeAxiomSession validates updatedAt >= createdAt
  Scenario: hasMessages returns false for empty session
  Scenario: hasArtifacts returns false for empty session
  Scenario: extractInvariantRuleFromNaturalText parses constraint text
