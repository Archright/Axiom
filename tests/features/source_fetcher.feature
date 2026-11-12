Feature: Nix fixed-output model and fetchAndVerify
  As the Hermetic Build Engine
  I want a source fetcher that follows the Nix fixed-output discipline
  So that external dependencies are fetched, verified, and reproducible

  Background:
    Given the Axiom gate infrastructure is initialized
    And a temporary test directory exists

  Scenario: fetchAndVerify returns input hash on success
    Given a valid fetcher configuration with a reachable URL
    And the expected content hash matches the fetched content
    When fetchAndVerify is called
    Then the fetch succeeds
    And the returned input hash equals the expected hash

  Scenario: lockfile generation produces valid JSON
    Given a successful fetch with source metadata
    When the lockfile is generated from the fetch result
    Then the lockfile is valid JSON
    And the lockfile contains the source URL, hash, and fetcher type

  Scenario: unknown fetcher type returns unsupported error
    Given a fetcher configuration with an unrecognized fetcher type
    When fetchAndVerify is called
    Then the fetch fails with an unsupported fetcher error
    And the error message includes the unrecognized type name
