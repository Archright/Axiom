@legacy
@executable
Feature: Legislator Persona — LLM-Only Invariant Drafting
  As an Axiom verification engineer
  I want the Legislator persona to draft loop invariants via LLM
  So that verification has mathematically sound invariants to check against

  Background:
    Given the Axiom engine is initialized

  Scenario: Persona layer mapping is correct
    Given the Legislator persona kind pkLegislator
    When the LayerMapping is consulted
    Then the layer must be plkScribe (Layer 3)

  Scenario: LegislatorArtifact construction preserves all fields
    Given a LegislatorArtifact with baselineInvariant, refinedInvariant, and activeInvariant
    When the artifact fields are read
    Then baselineInvariant must match the input
    And refinedInvariant must match the input
    And activeInvariant must match the input

  Scenario: CounterExamplePayload construction
    Given a CounterExamplePayload with nodeId, failedInvariant, and leanDiagnostic
    When the payload fields are read
    Then nodeId must match
    And failedInvariant must match
    And leanDiagnostic must match

  Scenario: LegislatorArtifact embeds ScribeArtifact
    Given a LegislatorArtifact with an embedded ScribeArtifact
    When the scribeArtifact field is read
    Then it must be a valid ScribeArtifact with default values

  Scenario: Evolution reasoning reflects LLM proposal
    Given a LegislatorArtifact with evolutionReasoning "llm-proposed"
    When the evolutionReasoning field is read
    Then it must equal "llm-proposed"
