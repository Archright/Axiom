Feature: Axiom Defaults — tier-specific exception hygiene templates
  As the Axiom build system,
  I want reusable {.push raises} templates per architectural tier,
  So that exception hygiene is enforced consistently without boilerplate.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: axiomCoreDefaults enforces raises: []
    Given a module that uses axiomCoreDefaults
    When a proc without {.raises: [].} is compiled
    Then the compiler raises an error

  Scenario: axiomGateDefaults allows CatchableError
    Given a module that uses axiomGateDefaults
    When a proc with {.raises: [CatchableError].} is compiled
    Then compilation succeeds

  Scenario: axiomCliDefaults allows Exception
    Given a module that uses axiomCliDefaults
    When a proc with {.raises: [Exception].} is compiled
    Then compilation succeeds
