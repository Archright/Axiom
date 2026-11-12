@legacy
@executable
Feature: Scribe Persona — Lean 4 Theorem Synthesis
  As an Axiom verification engineer
  I want the Scribe persona to synthesize Lean 4 theorems via LLM
  So that invariants are formally verified by the Lean kernel

  Background:
    Given the Axiom engine is initialized

  Scenario: Persona layer mapping is correct
    Given the Scribe persona kind pkScribe
    When the LayerMapping is consulted
    Then the layer must be plkScribe (Layer 3)

  Scenario: ScribeArtifact default construction
    Given a default ScribeArtifact
    When the fields are read
    Then verified must be false
    And theoremSource must be empty
    And tacticTrace must be empty

  Scenario: ScribeArtifact verified state
    Given a ScribeArtifact with verified=true and a theoremSource
    When the fields are read
    Then verified must be true
    And theoremSource must contain the source content

  Scenario: ScribeArtifact embeds into LegislatorArtifact
    Given a LegislatorArtifact containing a ScribeArtifact
    When the scribeArtifact is accessed
    Then its fields must be independently verifiable

  Scenario: Tactic trace sequence preservation
    Given a ScribeArtifact with multiple tactic trace entries
    When the tacticTrace is read
    Then all entries must be present in order
