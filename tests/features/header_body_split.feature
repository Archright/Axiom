@legacy
Feature: Header Body Split and Tautology Sentinel Bypass
  As an Axiom developer
  I want sanitizeLeanSource to preserve theorem header colons
  And tautology proofs to bypass the vacuity sentinel
  So that certGreen certificates are generated for type-system guarantees

  Scenario: Theorem header colons are preserved
    Given a Lean source with "theorem foo (x : Int) : x >= 0 := by"
    When sanitizeLeanSource is called
    Then "(x : Int)" is preserved in the output

  Scenario: Body type annotations are stripped  
    Given a Lean body line "let x : Int = 42" after ":= by"
    When sanitizeLeanSource is called
    Then "let x :=" appears in the output

  Scenario: Tautology proof bypasses vacuity sentinel
    Given a SemanticHint with strategy isTautologyProof
    When saveHint is called
    Then the sentinel scan is skipped
    And the hint proceeds to certificate generation

  Scenario: Bridge skeleton is sanitized before Leanstral
    Given a bridge skeleton with Nim type annotations
    When heal_leanstral processes it
    Then sanitizeLeanSource is applied to the skeleton
  Scenario: synthesis engine sanitizes Leanstral output
    Given raw Leanstral output with colon artifacts
    When runLeanstralRound processes it
    Then sanitizeLeanSource is applied before Lean compilation

  Scenario: Nim bracket artifacts are stripped
  Scenario: namespace isolation prevents collisions
  Scenario: semantic eraser 2.0 strips variable from body
  Scenario: for-loop iteration conditions are trivial
  Scenario: tautology proof bypasses vacuity gate in executeHealNode
  Scenario: membership operator is always trivial
  Scenario: function calls without logic are trivial
  Scenario: safe cooldown clearance
  Scenario: opaque types get tautology hint
  Scenario: boolean literals are trivial
  Scenario: quarantine bypass for tautology
  Scenario: Wave M edge case fixes
