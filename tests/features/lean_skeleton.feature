@legacy
Feature: Deterministic Lean Skeleton Injection
  Leanstral receives immutable theorem skeletons with `sorry` placeholders.
  It fills only tactics, preventing type_mismatch and agent behavior errors.

  Background:
    Given lean_skeleton.nim generates skeletons with `:=\n  sorry\n`
    And Leanstral tactic prompt forbids `sorry`/`admit`

  Scenario: Skeleton ends with sorry, not by
    When buildLeanSkeleton is called for any node
    Then result contains ":=\n  sorry\n"
    And result does NOT contain ":= by"

  Scenario: Prompt prohibits sorry and admit
    Given buildLeanstralTacticPrompt is called
    Then prompt contains "NEVER use `sorry`"
    And prompt contains "NEVER invoke tools"

  Scenario: Skeleton preserves theorem signature integrity
    When buildLeanSkeleton is called
    Then result contains "import Std"
    And result contains "theorem"
    And result contains "h_sys"
