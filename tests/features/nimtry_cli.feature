Feature: Axiom nimtry gate CLI (nimtry_cli)
  As a developer
  I want nimtry gate to use per-file content caching with separated policy hash
  So that architecture_debt.json changes don't invalidate all per-file caches

  Background:
    Given the nimtry_cli module is available
    And the nimtry cache directory .nimcache/nimtry/ exists

  Scenario: policyHash excludes architecture_debt.json
    Given the nimtry gate computes policyHash from policy files
    When architecture_debt.json is modified
    Then the policyHash remains unchanged
    And existing per-file caches remain valid

  Scenario: per-file cache invalidation on source change
    Given a cached ModuleFacts for a source file
    When the source file content changes
    Then the sourceHash changes
    And the cache entry is invalidated

  Scenario: per-file cache invalidation on policy change
    Given a cached ModuleFacts for a source file
    When architecture_policy.lock changes
    Then the policyHash changes
    And all per-file caches are invalidated
