Feature: Golden Master Gate
  As an Axiom operator maintaining verification baselines
  I want a golden master gate that compares current output against saved snapshots
  So that unintentional behavioral changes are caught at commit time

  Background:
    Given the golden master gate is available
    And golden files exist in data/golden/

  @core
  Scenario: Pass when current output matches golden file
    Given a module with a golden file in data/golden/
    When the golden master gate runs
    Then the gate must pass

  @core
  Scenario: Fail when current output diverges from golden file
    Given a module whose output no longer matches its golden file
    When the golden master gate runs
    Then the gate must fail with a diff summary

  @core
  Scenario: Auto-capture mode creates missing golden files
    Given a module without a golden file
    When the golden master gate runs in capture mode
    Then a new golden file must be created in data/golden/

  @determinism
  Scenario: Golden files use deterministic JSON formatting
    Given a golden file produced by the capture tool
    When the file is read
    Then all JSON keys must be alphabetically sorted
    And all timestamps must be normalized to <TIMESTAMP>
    And all UUIDs must be normalized to <UUID>
