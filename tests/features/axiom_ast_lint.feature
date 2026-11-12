Feature: Axiom AST Lint — compile-time guard-rail linter
  As the Integrity Engine compile-time layer,
  I want an AST linter that enforces annotation and hygiene invariants at compile time,
  So that gate-internal code cannot regress on effect/raises annotation discipline.

  Background:
    Given the Axiom AST lint macros are available at compile time
    And a module under src/ is being compiled

  Scenario: FFI pragma detection on shield modules
    Given a module annotated with the axiom FFI shield pragma
    When the AST linter scans the module for FFI usage
    Then the module is recognized as a shield module
    And fileHasFfiPragma returns true

  Scenario: effect-hint scan rejects unannotated I/O procs
    Given a proc that performs I/O without an axiomEffect annotation
    When runEffectHintsScan runs over the module
    Then the scan reports a violation
    And the proc is flagged for missing axiomEffect

  Scenario: cast/no-side-effect doc scan enforces documentation
    Given a cast that claims noSideEffect without a doc comment
    When runCastDocScan runs over the module
    Then the scan reports a documentation violation

  Scenario: repo root resolution is deterministic
    Given a module compiled inside the Axiom workspace
    When findRepoRootCt is evaluated at compile time
    Then it resolves the same .axiom_root anchor on every build
