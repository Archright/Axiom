@legacy
Feature: Gate Memoization with depsDirs
  Enables memoization for functional gates with empty entry by computing
  a deterministic Merkle root over declared dependency directories (depsDirs).

  Background:
    Given the gate_memo module exists at "src/core/gate_memo.nim"
    And the domain_types module defines GateConfig with depsDirs field

  Scenario: depsDirs computes deterministic Merkle root for directories
    Given a gate config with depsDirs containing "tests/gateway/" and "bin/gateway_test_gate"
    When computeMerkleRootFromPaths is called
    Then the result is a non-empty SHA1 string
    And calling it again produces the identical hash

  Scenario: Composite lock hash accepts pre-computed gate hash
    Given input files ["src/core/gate_memo.nim"]
    And a pre-computed gate hash "abcd1234"
    When computeCompositeLockHash is called with isPath=false
    Then the result differs from the path-based variant
    And the gate hash portion is included verbatim

  Scenario: shouldSkipGate caches results for entry-less gates
    Given a gate with empty entry and populated depsDirs
    And changed files have not been modified
    When shouldSkipGate is called with isPath=false
    Then the cached result is returned on subsequent calls
