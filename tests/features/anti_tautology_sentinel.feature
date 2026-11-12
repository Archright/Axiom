@legacy
@executable
Feature: Anti-Tautology Integrity Sentinel
  As an Axiom engineer
  I want tautological proofs to be isolated as pseudo-verified
  So that ASI is not inflated by meaningless propositions

  Background:
    Given the Axiom engine is initialized
    And the certificate vault is empty

  Scenario: Self-equality tautology is isolated as pseudo-verified
    When a proof proposition "theorem foo (n : Nat) : n = n := by rfl" is submitted
    And the anti-tautology sentinel scans it
    Then the sentinel verdict should be rejected
    And the verdict status should be "certPseudoVerified"
    And the verdict reason should contain "self-equality"

  Scenario: Trivial True proposition is isolated as pseudo-verified
    When a proof proposition "theorem foo : True := by trivial" is submitted
    And the anti-tautology sentinel scans it
    Then the sentinel verdict should be rejected
    And the verdict status should be "certPseudoVerified"
    And the verdict reason should contain "trivially True"

  Scenario: Assert-true SMT constraint is isolated as pseudo-verified
    When a proof proposition "theorem foo (x y : Nat) (h : x > y) : x >= y := by omega" is submitted
    And the SMT constraint is "(assert true)"
    And the anti-tautology sentinel scans it
    Then the sentinel verdict should be rejected
    And the verdict status should be "certPseudoVerified"
    And the verdict reason should contain "vacuous"

  Scenario: Meaningful proposition is accepted
    When a proof proposition "theorem foo (x y : Nat) (h : x > y) : x >= y := by omega" is submitted
    And the SMT constraint is "(assert (>= x y))"
    And the source context contains "x y"
    And the anti-tautology sentinel scans it
    Then the sentinel verdict should be accepted
    And the verdict status should be "certGreen"

  Scenario: ASI calculation excludes pseudo-verified nodes
    Given a certificate with status "certPseudoVerified" exists in the vault
    And a certificate with status "certGreen" exists in the vault
    When ASI is calculated
    Then the pseudo-verified node should not count toward verifiedFunctions
    And the substantive ASI should equal the standard ASI

  @deprecated
  Scenario: Report shows Lack of Substantive Evidence warning
    Given a certificate with status "certPseudoVerified" exists in the vault
    When I run "ax report --calculate-asi"
    Then the output should contain "Lack of Substantive Evidence"
    And the output should contain the count of pseudo-verified nodes
