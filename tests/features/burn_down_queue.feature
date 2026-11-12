Feature: Burn-down Queue
  Combines git churn, test existence, and SAD into a priority score.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: Priority score is edit count times risk multiplier
    Given a module with editCount 10 and no test
    When I compute the priority score
    Then the score should be 30.0

  Scenario: findTestFile returns matching test path
    Given a module named "my_module"
    And a test file "tests/unit/my_module_test.nim" exists
    When I call findTestFile with "my_module"
    Then the result should be "tests/unit/my_module_test.nim"

  Scenario: findTestFile returns empty when no test exists
    Given a module named "orphan_module"
    And no test file exists for "orphan_module"
    When I call findTestFile with "orphan_module"
    Then the result should be ""

  Scenario: HotspotTier is critical when no test exists
    Given a module has no test
    When I compute the tier
    Then the tier should be htCritical

  Scenario: HotspotTier is low when SAD is above 15%
    Given a module has a test with SAD 0.20
    When I compute the tier
    Then the tier should be htLow

  Scenario: buildPriorityQueue sorts by priority descending
    Given churn data with two modules having edit counts 5 and 20
    When I build the priority queue
    Then the first entry should have the higher edit count
