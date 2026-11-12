Feature: Compile-Time Structural Safety Enforcement
  Compile-time macro that validates structural invariants at build time,
  replacing runtime AST inspection with deterministic Nim macro analysis.

  Background:
    Given the project uses Nim 2.2.10 compiler
    And config.nims injects enforce_structural_safety globally

  Scenario: ref object with proc field is rejected at compile time
    Given a module defining a ref object with a proc/func field
    When the module is compiled with the structural safety macro
    Then compilation should fail with a structural safety violation

  Scenario: func with var parameter is rejected at compile time
    Given a func declaration with a var parameter
    When the module is compiled with the structural safety macro
    Then compilation should fail with a func-var violation

  Scenario: core module importing gate layer is rejected
    Given a core module that imports a gate/runner module
    When the module is compiled with the structural safety macro
    Then compilation should fail with an import boundary violation

  Scenario: pure data types pass structural safety check
    Given a module with only distinct types and value-type fields
    When the module is compiled with the structural safety macro
    Then compilation should succeed without violations

Feature: Pure Nim Freshness Guard
  Hash-based source freshness check for gate runner binaries,
  eliminating external shell dependencies from the build pipeline.

  Background:
    Given the buildGateRunners task is defined in config.nims

  Scenario: gate binaries are rebuilt on source hash mismatch
    Given a gate runner source file has changed since last build
    When buildGateRunners is executed
    Then the affected binary should be rebuilt
    And the new hash should be saved to .axiom/cache/gate_hashes.json

  Scenario: gate binaries are skipped when source is unchanged
    Given all gate runner source hashes match the saved hashes
    When buildGateRunners is executed
    Then no binaries should be rebuilt
    And the hash file should remain unchanged

  Scenario: missing binary triggers rebuild regardless of hash
    Given a gate runner binary does not exist
    When buildGateRunners is executed
    Then the binary should be rebuilt from source

  Scenario: no external shell commands are used
    Given the buildGateRunners task runs
    When checking for freshness
    Then only std/hashes should be used (no sha256sum or sha256)
