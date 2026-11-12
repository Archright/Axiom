Feature: drnim Gate — Nim Check Fallback for Core Modules
  As the gate infrastructure,
  the drnim_gate must verify core module syntax and semantics
  via nim check as a fallback when full drnim analysis is unavailable.

  Background:
    Given the drnim gate targets core BMC and result types

  # ── Core module verification ─────────────────────────────────────

  Scenario: drnim checks core module syntax
    Given src/core/bmc_race.nim and src/core/types/results.nim exist
    When the drnim gate runs nim check on each target
    Then all targets pass syntax and semantic verification

  # ── Environment handling ─────────────────────────────────────────

  Scenario: drnim handles missing Z3 gracefully
    Given nim check's gorge() has a PATH quirk with Z3 detection
    When the drnim gate runs nim check with -d:allowMissingZ3
    Then the check completes without hermetic Z3 failure

  # ── Project boundary ─────────────────────────────────────────────

  Scenario: drnim skips when axiom.nimble is missing
    Given a directory without axiom.nimble
    When the drnim gate runs
    Then it returns immediately without error
