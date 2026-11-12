Feature: DiscoveryPolicy — deterministic source-file filtering for topology scanning
  As the Integrity Engine,
  I want a deterministic policy that filters source files by extension and path,
  So that only valid Nim source files enter the verification pipeline and C compiler artifacts are excluded.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: accept valid Nim source files
    Given the default nimSourcePolicy is loaded
    When I call isValidSourceNode for "src/cli/axiom_engine.nim"
    Then the result is true
    When I call isValidSourceNode for "config.nims"
    Then the result is true

  Scenario: reject non-Nim source files
    Given the default nimSourcePolicy is loaded
    When I call isValidSourceNode for "some/path/file.c"
    Then the result is false
    When I call isValidSourceNode for "scripts/helper.py"
    Then the result is false
    When I call isValidSourceNode for "frontend/app.js"
    Then the result is false

  Scenario: reject files with no extension
    Given the default nimSourcePolicy is loaded
    When I call isValidSourceNode for "Makefile"
    Then the result is false
    When I call isValidSourceNode for "LICENSE"
    Then the result is false

  Scenario: reject files in excluded directories
    Given the default nimSourcePolicy is loaded
    When I call isValidSourceNode for ".nimcache_gate_hook/@m..@sgate_registry.nim.c"
    Then the result is false
    When I call isValidSourceNode for "nimcache/file.c"
    Then the result is false
    When I call isValidSourceNode for ".nimcache/file.c"
    Then the result is false
    When I call isValidSourceNode for "build/nimcache_check/file.c"
    Then the result is false
    When I call isValidSourceNode for "vendor/z3/lib.nim"
    Then the result is false
    When I call isValidSourceNode for ".lake/packages/something.nim"
    Then the result is false
    When I call isValidSourceNode for ".git/hooks/pre-commit.nim"
    Then the result is false
    When I call isValidSourceNode for "logs/evidence/proof.nim"
    Then the result is false
    When I call isValidSourceNode for "bin/some_binary.nim"
    Then the result is false
    When I call isValidSourceNode for "node_modules/package/index.nim"
    Then the result is false
    When I call isValidSourceNode for "semantic_proofs/proof.nim"
    Then the result is false
    When I call isValidSourceNode for "experimental/test.nim"
    Then the result is false

  Scenario: extension matching is case-insensitive
    Given the default nimSourcePolicy is loaded
    When I call isValidSourceNode for "src/core/engine.NIM"
    Then the result is true
    When I call isValidSourceNode for "src/core/engine.CPP"
    Then the result is false

  Scenario: custom policy overrides default behavior
    Given a custom policy with extensions [".rs", ".go"] and excluded paths ["target", "vendor"]
    When I call isValidSourceNode for "src/main.rs"
    Then the result is true
    When I call isValidSourceNode for "cmd/app.go"
    Then the result is true
    When I call isValidSourceNode for "src/main.nim"
    Then the result is false
    When I call isValidSourceNode for "vendor/lib.rs"
    Then the result is false

  Scenario: determinism — same input always produces same output
    Given the default nimSourcePolicy is loaded
    When I call isValidSourceNode for "src/core/engine.nim" repeatedly 100 times
    Then all results are true
    When I call isValidSourceNode for ".nimcache_gate_hook/file.c" repeatedly 100 times
    Then all results are false
