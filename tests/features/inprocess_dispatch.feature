Feature: In-Process Dispatch — gate runner dispatch + sandbox bridge
  As the Orchestrator,
  I want an in-process dispatcher that routes gate runners and bridges sandbox context,
  So that gates can execute without spawning a full subprocess for every invocation.

  Background:
    Given the orchestrator has resolved a gate run plan
    And the in-process dispatch table is populated from the manifest

  Scenario: dispatch routes a known runner by id
    Given a registered gate runner id "immunity_gate"
    When inprocess_dispatch resolves the runner
    Then the correct runner module is selected
    And the runner executes in-process

  Scenario: missing runner id is reported as an error
    Given an unregistered gate runner id "does-not-exist"
    When inprocess_dispatch resolves the runner
    Then dispatch returns an error result
    And no subprocess is spawned

  Scenario: VFS context is forwarded to the runner
    Given a gate run that carries a VFS GateContext
    When inprocess_dispatch invokes the runner
    Then the runner receives the same VFS root hash
    And file reads go through the VFS bridge
