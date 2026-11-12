Feature: Precompile Gate Binaries — Hermetic Lock-file Verification
  As the build infrastructure,
  precompile_gates must eliminate CAS JIT compilation cold-start times
  (15-64s) by pre-compiling all gate binaries with environment fingerprint
  verification via a hermetic lock file.

  Background:
    Given the lock file path is ".axiom/cache/gate_env.lock"
    And all gate source paths are discoverable from gate_registry

  # ── Environment fingerprint matching ─────────────────────────────

  Scenario: Skip compilation when all environment hashes match
    Given the lock file exists with current environment hashes
    And no gate source files have changed since lock creation
    When precompile_gates is invoked
    Then no compilation is performed
    And exit code is 0

  Scenario: Recompile all gates when environment changes
    Given the lock file exists
    And the Nim compiler version has changed
    When precompile_gates is invoked
    Then all gate binaries are recompiled
    And the lock file is updated with new hashes

  Scenario: Recompile only affected gates when source changes
    Given the lock file exists with current environment hashes
    And only gate source file "nimtry.nim" has changed
    When precompile_gates is invoked
    Then only the "nimtry" gate binary is recompiled
    And other gate binaries remain unchanged

  # ── Lock file integrity ──────────────────────────────────────────

  Scenario: Lock file contains SHA-256 hashes for each gate
    Given precompile_gates has successfully run
    When the lock file is read
    Then it contains a JSON object with gate IDs as keys
    And each entry has a "sourceHash" field (SHA-256)
    And each entry has a "binaryHash" field (SHA-256)
    And each entry has an "envFingerprint" field

  Scenario: Corrupted lock file triggers full recompilation
    Given the lock file exists but contains invalid JSON
    When precompile_gates is invoked
    Then all gate binaries are recompiled from scratch
    And the lock file is rewritten

  # ── Exit codes ───────────────────────────────────────────────────

  Scenario: Exit code 0 when all gates compile successfully
    Given all gate source files are valid
    When precompile_gates is invoked
    Then exit code is 0

  Scenario: Exit code 1 when any gate fails to compile
    Given a gate source file has a syntax error
    When precompile_gates is invoked
    Then exit code is 1
    And stderr contains the failing gate's name and error
