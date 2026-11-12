@legacy
Feature: Information Entropy-based Proof Grading
  As an Axiom verification pipeline
  I want the vacuity gate to grade proofs by information gain
  So that trivial constraints (length >= 0) are rejected while strong constraints (x == 5) pass

  Background:
    Given the Axiom proof vacuity gate is loaded
    And `validateVacuityParts` is the entry point

  Scenario: High information gain bypasses semantic term count gate
    Given a SemanticHint with `informationGain = 15.0`
    And `semanticTermCount = 1`
    When `validateSemanticHintVacuity` is called
    Then the entropy gate should pass
    And the decision should be `accepted = true` (assuming other gates pass)

  Scenario: Low information gain and low term count fails gate
    Given a SemanticHint with `informationGain = 0.0`
    And `semanticTermCount = 1`
    When `validateSemanticHintVacuity` is called
    Then the entropy gate should fail
    And the rejection reason should contain "information gain"

  Scenario: String length constraint has low information gain
    Given a parameter `s: string` with constraint `(>= (str.len s) 0)`
    When `computeInformationGain` is called
    Then the result should be less than 2.0

  Scenario: Integer equality has high information gain
    Given a parameter `x: int` with constraint `(= x 5)`
    When `computeInformationGain` is called
    Then the result should be greater than 10.0

  Scenario: Bool equality has moderate information gain
    Given a parameter `b: bool` with constraint `(= b true)`
    When `computeInformationGain` is called
    Then the result should be greater than 0.0
    And the result should be less than or equal to 1.0

  Scenario: Information-gain-weighted ASI reflects proof quality
    Given a FunctionCertificate with `informationGain = 15.0` and `status = certGreen`
    And another FunctionCertificate with `informationGain = 0.0` and `status = certGreen`
    And an AsiUniverse with `totalFunctions = 100`
    When `computeInformationGainWeightedAsi` is called
    Then the high-IG certificate should contribute more than the zero-IG certificate
    And the resulting ASI should be greater than a flat-count ASI

  Scenario: Missing certificates default to baseline weight in IG-weighted ASI
    Given 10 FunctionCertificates each with `informationGain = 5.0` and `status = certGreen`
    And an AsiUniverse with `totalFunctions = 20`
    When `computeInformationGainWeightedAsi` is called
    Then the denominator should include 10 baseline weights for missing certs
    And the coverage should be approximately 0.5
