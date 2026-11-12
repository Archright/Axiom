Feature: Architecture Configuration Gate
  As a developer
  I want architecture configuration validation
  So that debt registry remains deterministic

  Scenario: Debt registry has no runtime timestamps
    Given a debt registry JSON file
    When the registry is loaded
    Then it should not contain any runtime-generated timestamp fields

  Scenario: Debt registry determinism
    Given identical source code state
    When the debt registry is generated twice
    Then both outputs should be byte-identical
