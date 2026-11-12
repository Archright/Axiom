Feature: DIP Consumer Dependency Rules Gate
  As an Axiom architect enforcing SOLID principles
  I want to track DIP (Dependency Inversion Principle) consumer counts
  So that dependency growth is visible and gated

  Background:
    Given the dependency rules gate is available

  @core
  Scenario: Consumer count tracking produces JSON output
    Given the src/ directory has modules with consumer counts
    When the DIP consumer tracking runs
    Then data/dip_consumer_counts.json must be written
    And the JSON must contain module name and consumer count pairs

  @gate
  Scenario: Warning on consumer count increase
    Given a previous consumer count snapshot exists
    When a module's consumer count increases
    Then the gate must emit a warning with the delta

  @gate
  Scenario: No warning on consumer count decrease or same
    Given a previous consumer count snapshot exists
    When all modules maintain or decrease their consumer counts
    Then the gate must pass without warnings
