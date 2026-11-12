@legacy
Feature: Hard-Mode requires Lean proof

  Scenario: certGreen requires a linked Lean proof artifact
    Given a Lean proof artifact exists for node "core/example.nim::safeAdd"
    And the certificate stores the artifact SHA-256 hash
    When verifyProofLinkage checks the node
    Then the proof linkage result should be accepted

  Scenario: missing or mismatched Lean proof artifact is rejected
    Given no Lean proof artifact exists for node "core/example.nim::missing"
    When verifyProofLinkage checks the node
    Then the proof linkage result should be rejected
    Given a Lean proof artifact exists for node "core/example.nim::tampered"
    And the certificate stores a different SHA-256 hash
    When verifyProofLinkage checks the node
    Then the proof linkage result should be rejected
