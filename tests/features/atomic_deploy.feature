Feature: Atomic Deploy — symlink-swap generation tracking
  As the Hermetic Build Engine,
  I want atomic symlink-based deployment with generation tracking,
  So that rollbacks are instantaneous and generation history is preserved.

  Background:
    Given the Axiom gate infrastructure is initialized
    And a temporary test directory exists

  Scenario: deployGeneration creates symlink at target path
    Given a build output directory "out/gen-42" exists
    When I call deployGeneration with generation 42
    Then a symlink exists at the active deploy path
    And the symlink points to "out/gen-42"

  Scenario: rollback reverts to the previous generation
    Given generation 41 is the current active deployment
    And generation 42 is deployed as the active deployment
    When I call rollback
    Then the active deploy symlink points to generation 41
    And the generation counter is decremented

  Scenario: generationPath returns the correct filesystem path
    Given the deploy root is ".axiom/deploy"
    When I query generationPath for generation 7
    Then the returned path is ".axiom/deploy/gen-7"
    And the path does not contain trailing separators
