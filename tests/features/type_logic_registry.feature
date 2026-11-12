Feature: Type Logic Registry — maps types to their logic shapes
  As the Axiom solver persona,
  I want a registry mapping Lean types to logic shape handlers,
  So that the correct solver strategy is selected per type.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: register and resolve a type shape
    Given a type "Int" registered with shape "linear_arithmetic"
    When I resolve the shape for type "Int"
    Then the resolved shape is "linear_arithmetic"

  Scenario: resolving an unregistered type returns unknown
    Given no shape registered for type "CustomStruct"
    When I resolve the shape for type "CustomStruct"
    Then the resolved shape is "unknown"
