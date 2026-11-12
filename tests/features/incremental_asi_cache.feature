@legacy
Feature: Incremental ASI Cache
  As an Axiom developer
  I want ASI calculation to use a filesystem-change cache
  So that repeated `ax report --calculate-asi` calls complete in sub-second time

  Background:
    Given the Axiom project is initialized
    And the certificate vault contains at least one verified certificate

  @deprecated
  Scenario: ASI calculation completes instantly on unchanged codebase
    Given I have already run `ax report --calculate-asi` once
    And no source files or certificates have been modified since
    When I run `ax report --calculate-asi` again
    Then the command should complete in less than 1 second
    And the printed ASI score should equal the previously cached value

  @deprecated
  Scenario: Cache invalidates after source file modification
    Given a valid ASI cache exists at `logs/asi_cache.json`
    When I modify any `.nim` file under `src/`
    And I run `ax report --calculate-asi`
    Then the cache should be detected as stale
    And a full certificate re-scan should execute
    And a new cache should be written after completion

  Scenario: Global symbol graph uses content-hash incremental cache
    Given `buildGlobalSymbolGraph` has been run at least once
    And the incremental cache exists at `/tmp/axiom_global_symbol_graph_inc.json`
    When `buildGlobalSymbolGraph` is called again without source changes
    Then only changed files should be re-parsed
    And the elapsed time should be under 5 seconds (vs 30s cold start)

  Scenario: Incremental graph cache round-trips module contributions
    Given a module `a.nim` with symbols `foo` and `bar`
    And an edge from `foo` to `bar`
    When `saveIncrementalGraphCache` writes the contribution
    And `loadIncrementalGraphCache` reads it back
    Then the hash, symbols, and edges must match exactly
