@legacy
@executable
Feature: SWAT Persona — BMC Fast-Path Layer 1 Verification
  As an Axiom verification engineer
  I want the SWAT persona to perform bounded model checking
  So that loop-free functions are verified quickly before deeper analysis

  Background:
    Given the Axiom engine is initialized

  Scenario: Persona layer mapping is correct
    Given the SWAT persona kind pkSwat
    When the LayerMapping is consulted
    Then the layer must be plkSwat (Layer 1)

  Scenario: VulnerabilityHit case object for integer overflow
    Given a VulnerabilityHit with kind vkIntegerOverflowUnderflow
    When the hit fields are read
    Then the kind must be vkIntegerOverflowUnderflow
    And ioInfo must be accessible

  Scenario: AnnotatedHit construction
    Given an AnnotatedHit with sat=true and a violatedProperty
    When the fields are read
    Then sat must be true
    And violatedProperty must match

  Scenario: SwatArtifact construction with vulnerability hits
    Given a SwatArtifact with a list of vulnerability hits
    When the vulnerabilityHits are read
    Then the count must match
    And each hit must have valid fields

  Scenario: NegativeInvariantScan construction
    Given a NegativeInvariantScan with hasVulnerability=false
    When the fields are read
    Then hasVulnerability must be false
    And hits must be empty
