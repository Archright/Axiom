Feature: Summary Cache Benchmark

  Scenario: Warm cache is faster than cold cache
    Given a set of Nim source files
    When the AST hash is computed cold (no cache)
    And the AST hash is computed warm (cached)
    Then the warm path is at least 3x faster than the cold path
    And the benchmark results are written to docs/evidence/summary_cache_benchmark.json

  Scenario: Cache hit returns identical hash
    Given a source file with a known AST hash
    When the same source is hashed again
    Then the hash matches the previous result
