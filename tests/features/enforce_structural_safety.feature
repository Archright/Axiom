Feature: Compile-Time Structural Safety Enforcement Macro
  Global compile-time macro that validates structural invariants
  at build time, injected via config.nims switch("import").

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
