Feature: Effect Isolation and Fingerprint Versioning
  As an Axiom operator
  I want I/O effects to be abstracted rather than blocking verification
  So that no verified node becomes a blind spot after source changes

  Scenario: I/O functions generate partial hints instead of none
    Given a Nim function containing writeFile or execCmd
    When BoundaryExtractor analyzes the function
    Then a SemanticHint is returned with completeness bcPartialHavoc
    And the proposition includes external_io_isolated
