Feature: Pure Path — side-effect-free path manipulation utilities
  As the Axiom core engine,
  I want pure functions for joining, normalizing, and splitting paths,
  So that path logic can run without I/O effects.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: join combines segments into a normalized path
    Given path segments "src" and "core" and "main.nim"
    When I call purePathJoin on the segments
    Then the result is "src/core/main.nim"

  Scenario: normalize resolves redundant separators
    Given a path "src//core/../core/main.nim"
    When I call purePathNormalize
    Then the result is "src/core/main.nim"
