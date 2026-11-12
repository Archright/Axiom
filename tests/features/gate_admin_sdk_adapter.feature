Feature: Gate Admin SDK Adapter
  Bridges gate_admin_validate to the ICommandValidator SDK interface.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: AxiomCommandValidator allows an idempotent command
    Given an idempotent command "echo hello"
    When I call validateCommand with the command
    Then the result should be allowed
    And the effect should be oeIdempotent

  Scenario: AxiomCommandValidator blocks a mutated command
    Given a mutation command "rm -rf /tmp/build"
    When I call validateCommand with the command
    Then the result should be blocked
    And the reason should be "blocked by gate_admin circuit breaker"

  Scenario: Effect mapping preserves ordinal layout
    Given an OpEffect oeIdempotent
    When I convert it to SDK CommandEffect
    Then the CommandEffect ordinal should match

  Scenario: recordCommand stores command in the ring buffer
    Given an AxiomCommandValidator instance
    When I call recordCommand with "git push"
    Then recentCommands should contain "git push"
