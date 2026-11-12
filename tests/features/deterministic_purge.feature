@legacy
Feature: Deterministic Purge and Formal Grammar Enforcement
  As an Axiom maintainer
  I want executable code and active contracts to reject ad-hoc inference markers
  So that verification behavior remains grammar-bound and reproducible

  Background:
    Given deterministic purge feature runner is executing

  Scenario: Active code and executable contracts carry no ad-hoc inference markers
    When deterministic purge scans active source roots
    Then no active file should contain banned inference markers
    And proof summarization should receive SMT constraints from explicit kernel replay output
    And Leanstral SMT assertion extraction should use exact SMT assertion lines

  Scenario: Deterministic purge has a dedicated executable runner
    Given file tests/gateway/deterministic_purge_feature_test.nim
    Then file should contain "proc runDeterministicPurgeFeature"
    And file should contain "tests/features/deterministic_purge.feature"
