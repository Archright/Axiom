@legacy
Feature: Wave 10 Proof-Driven Compiler
  The PDC (Proof-Driven Compiler) addresses three systemic bottlenecks in the
  verification pipeline: Vacuity Gate over-rejection, bcNoHintComment deadlock,
  and Leanstral synthesis collapse.

  Background:
    Given the Axiom CLI is built at "bin/ax"
    And certificate vault exists at "src/verification/certificates/"
    And proof state exists at "logs/ax_proof_state.json"

  ## Task B: Intrinsic Filter

  Scenario: Intrinsic property bypasses Vacuity Gate
    When BoundaryExtractor generates proposition "string.length >= 0"
    And the proposition matches an intrinsic pattern
    Then isIntrinsicProperty("string.length >= 0") returns true
    And saveHint bypasses validateZeroVacuity for the intrinsic property
    And saveHint bypasses checkSemanticContrast for the intrinsic property
    And saveHint bypasses Lean compiler verification
    And the certificate is saved with status "certIntrinsic"
    And the certificate counts toward verifiedFunctions in ASI calculation

  Scenario: Non-intrinsic property still passes through Vacuity Gate
    When BoundaryExtractor generates proposition "x > 0 and y < x"
    And the proposition does not match any intrinsic pattern
    Then isIntrinsicProperty("x > 0 and y < x") returns false
    And saveHint executes validateZeroVacuity normally
    And saveHint executes checkSemanticContrast normally

  Scenario: Unicode normalization for intrinsic matching
    Given intrinsicFilter has pattern "string-length-nonneg" matching ".length >= 0"
    When input proposition is "str.length ≥ 0" (using Unicode ≥)
    Then normalizeLeanUnicode converts "≥" to ">="
    And isIntrinsicProperty returns true

  ## Task C: Virtual Hint Injection

  @deprecated
  Scenario: BoundaryExtractor hint is persisted as source comment
    When ax prove --heal processes a node with BoundaryExtractor hint
    And injectVirtualHintToSource is called
    Then the source file contains "# @axiom-hint: lean=\"...\" smt=\"...\""
    And the comment appears immediately before the target function declaration

  @deprecated
  Scenario: isHintComment strategy consumes virtual hint on next run
    Given source file "src/core/example.nim" contains "# @axiom-hint: lean=\"prop\" smt=\"smt\""
    When ax prove --heal processes "core/example.nim::someFunc"
    And strategy rotation selects isHintComment
    Then generateSemanticHintWithStrategy returns Some(SemanticHint)
    And the hint has leanProposition "prop" and smtConstraint "smt"

  Scenario: Duplicate virtual hint is not re-injected
    Given source file already has "# @axiom-hint: lean=\"p\" smt=\"q\""
    When injectVirtualHintToSource is called with the same hint
    Then the comment is not duplicated

  ## Task A: Formal Sketching

  Scenario: Deterministic skeleton is generated from SemanticHint
    Given nodeId "core/example.nim::exampleFunc"
    And hint has leanProposition "x >= 0" and smtConstraint "(assert (>= x 0))"
    When buildLeanTheoremSkeleton(nodeId, hint) is called
    Then the result contains "import Std"
    Then the result contains def NimInt, def NimSeq, def NimExcept from prelude
    Then the result contains "variable" declarations
    Then the result contains "theorem" keyword
    Then the result ends with ":= by\n"
    Then the result does NOT contain "exact h_sys"

  Scenario: Tactics-only prompt is generated when lastCandidate is available
    Given tryStrategyRotation returns lastCandidate as Some(SemanticHint)
    When tryLeanstralSelfCorrection is called with lastCandidate
    Then FormalSketching mode is activated
    And buildLeanstralTacticPrompt is used instead of buildLeanstralPromptForHeal
    And the prompt instructs "Generate ONLY the tactics"

  Scenario: Skeleton and tactics are assembled before compiler verification
    Given theoremSkeleton is "import Std\n... := by\n"
    And Leanstral returns tactics "  exact h_sys"
    When runLeanstralRound is called with theoremSkeleton
    Then sourceToCompile is "import Std\n... := by\n  exact h_sys\n"
    And verifyGeneratedLeanSourceWithCompiler receives the assembled source

  Scenario: Fallback to full-source generation when no candidate available
    Given tryStrategyRotation returns lastCandidate as None
    When tryLeanstralSelfCorrection is called
    Then buildLeanstralPromptForHeal is used (full-source generation)
    And theoremSkeleton is empty
    And runLeanstralRound uses original full-source path
