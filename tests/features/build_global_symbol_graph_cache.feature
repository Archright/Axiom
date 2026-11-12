@legacy
Feature: buildGlobalSymbolGraph caching with compound cache key

  The symbol graph builder must cache per-srcRoot so that isolated test directories
  do not interfere with each other, and must use an in-memory lazy provider to
  avoid redundant file I/O within the same process.

  Scenario: verifyCertificates uses srcRoot-scoped cache file
    Given a temp srcRoot directory with .nim files
    When verifyCertificates is called with that srcRoot
    Then a cache file named global_symbol_graph.<hash>.cache.json is created
    And a second call with the same srcRoot hits the in-memory cache

  Scenario: freeze graph cache is read-only
    Given an incremental GlobalSymbolGraph cache with edge contributions
    When buildGlobalSymbolGraph is called with freezeGraphCache=true
    Then the existing cache file must not be overwritten by a partial graph

  Scenario: verifyCertificates prefers fresh global symbol graph SSOT
    Given logs/global_symbol_graph.json is newer than all source files
    When verifyCertificates loads graph state
    Then it must use the SSOT snapshot before srcRoot-scoped cache files
