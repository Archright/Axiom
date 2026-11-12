## Feature Macro Unit Tests — Gherkin Parser
##
## Tests the compile-time Gherkin parser with inline content.

import std/[unittest, tables]
import core/test_support/feature_macro

suite "Gherkin Parser — parseFeature":

  test "parses Feature name":
    let content = """
Feature: Test Feature
  Some description

  Scenario: Simple test
    Given a precondition
    When an action happens
    Then a result occurs
"""
    let f = parseFeature(content)
    check f.name == "Test Feature"
    check f.scenarios.len == 1
    check f.scenarios[0].name == "Simple test"

  test "parses Given/When/Then steps with correct keywords":
    let content = """
Feature: Keyword Parsing

  Scenario: Step keywords
    Given a setup step
    When an action step
    Then a verification step
    And an additional step
    But a contrasting step
"""
    let f = parseFeature(content)
    check f.scenarios[0].steps.len == 5
    check f.scenarios[0].steps[0].keyword == skGiven
    check f.scenarios[0].steps[1].keyword == skWhen
    check f.scenarios[0].steps[2].keyword == skThen
    check f.scenarios[0].steps[3].keyword == skAnd
    check f.scenarios[0].steps[4].keyword == skBut

  test "normalizes step text by stripping keyword prefix":
    let content = """
Feature: Text Normalization

  Scenario: Strip keywords
    Given   a  setup  step
    When the system processes input
    Then the output is correct
"""
    let f = parseFeature(content)
    check f.scenarios[0].steps[0].text == "a setup step"
    check f.scenarios[0].steps[1].text == "the system processes input"
    check f.scenarios[0].steps[2].text == "the output is correct"

  test "captures line numbers":
    let content = """Feature: Line Tracking

  Scenario: Track lines
    Given step one
    When step two
    Then step three
"""
    let f = parseFeature(content)
    check f.scenarios[0].line == 3
    check f.scenarios[0].steps[0].line == 4
    check f.scenarios[0].steps[1].line == 5
    check f.scenarios[0].steps[2].line == 6

  test "parses tags on feature and scenarios":
    let content = """
@feature-tag
Feature: Tagged Feature

  @smoke @critical
  Scenario: Tagged scenario
    Given a tagged step
"""
    let f = parseFeature(content)
    check "@feature-tag" in f.tags
    check f.scenarios.len == 1
    check "@smoke" in f.scenarios[0].tags
    check "@critical" in f.scenarios[0].tags

  test "parses Background section":
    let content = """
Feature: With Background

  Background:
    Given a shared setup
    And another shared step

  Scenario: First scenario
    When action one
    Then result one

  Scenario: Second scenario
    When action two
    Then result two
"""
    let f = parseFeature(content)
    check f.background.len == 2
    check f.background[0].text == "a shared setup"
    check f.background[1].text == "another shared step"
    check f.scenarios.len == 2
    check f.scenarios[0].steps.len == 2
    check f.scenarios[1].steps.len == 2

  test "parses multiple scenarios":
    let content = """
Feature: Multi Scenario

  Scenario: First
    Given step A
    Then step B

  Scenario: Second
    Given step C
    Then step D

  Scenario: Third
    Given step E
"""
    let f = parseFeature(content)
    check f.scenarios.len == 3
    check f.scenarios[0].name == "First"
    check f.scenarios[1].name == "Second"
    check f.scenarios[2].name == "Third"

  test "handles empty lines and comments":
    let content = """
Feature: Comments

  # This is a comment

  Scenario: With comments
    Given a step
    # Another comment
    Then a result
"""
    let f = parseFeature(content)
    check f.scenarios.len == 1
    check f.scenarios[0].steps.len == 2

  test "Scenario Outline is parsed":
    let content = """
Feature: Outline Test

  Scenario Outline: Parameterized
    Given a value <x>
    When processed
    Then result is <y>
"""
    let f = parseFeature(content)
    check f.scenarios.len == 1
    check f.scenarios[0].name == "Parameterized"

suite "Step Mapping":

  test "registerStep and matchStep roundtrip":
    var mapping = initTable[string, string]()
    registerStep(mapping, "a PBT engine with seed-based deterministic generation", "setupPbtEngine")
    let step = TestStep(keyword: skGiven, text: "a PBT engine with seed-based deterministic generation", line: 1)
    check matchStep(step, mapping) == "setupPbtEngine"

  test "matchStep returns empty for unmapped step":
    var mapping = initTable[string, string]()
    let step = TestStep(keyword: skGiven, text: "unknown step", line: 1)
    check matchStep(step, mapping) == ""

  test "matchStep is case-insensitive":
    var mapping = initTable[string, string]()
    registerStep(mapping, "A PBT Engine", "setupPbtEngine")
    let step = TestStep(keyword: skGiven, text: "a pbt engine", line: 1)
    check matchStep(step, mapping) == "setupPbtEngine"
