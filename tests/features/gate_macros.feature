Feature: Gate Macros — Compile-Time Gate Registration and Context Lifecycle
  As the gate hook architecture
  I want a compile-time macro for safe gate registration
  So that only verified gate runners can participate in the in-process dispatch

  Background:
    Given the gate_macros module is available

  Scenario: registerGate macro verifies AST whitelist
    Given a gate runner proc with only allowed AST nodes
    When registerGate is called with a gate ID and the runner
    Then the macro expands without compilation errors
    And the gate is registered in the in-process dispatch registry

  Scenario: registerGate macro rejects disallowed AST nodes
    Given a gate runner proc containing disallowed AST constructs
    When registerGate is called with a gate ID and the runner
    Then the compilation fails with an AST whitelist violation

  Scenario: GateRunContext is a pure value type
    Then GateRunContext should not be a ref type
    And GateRunContext should not be a ptr type
    And GateRunContext is safe for malebolgia spawn

  Scenario: clone increases ARC ref count for structural sharing
    Given a GateRunContext with vfsRefCount=1
    When clone is called on the context
    Then the cloned context has vfsRefCount=2
    And the cloned context has isShared=true

  Scenario: AuditEntry captures gate execution metadata
    Given a gate ID string "test-gate"
    When initAuditEntry is called with the gate ID
    Then the entry has the correct gateId
    And the startTime is set to the current time
    And the exitCode is -1 (not yet finalized)
