@v27
Feature: State Ledger — Cross-Process Pipeline State
  Provides a 7,400-byte binary ledger for zero-cost workspace state
  sharing between parent (L0) and L2 child processes via mmap.

  Background:
    Given the Axiom gate hook is built at "bin/gate_hook"
    And the repo root is identified by ".axiom_root"

  Scenario: Ledger creation writes atomic binary file
    Given a valid workspace with dirtyHash, ruleHash, and buildEnvHash
    When createLedger is called with gate entries
    Then ".axiom/cache/pipeline_state.ledger" is written atomically
    And the file size is exactly 7,400 bytes
    And the file passes CRC32 integrity validation

  Scenario: Ledger mmap read-only returns valid pointer
    Given a ledger file exists at the canonical path
    When openLedger is called
    Then the returned pointer is non-nil
    And the magic field equals 0x4158474C
    And the version field equals 4
    And the CRC32 checksum matches the computed value

  Scenario: Ledger round-trip preserves dirtyHash
    Given a dirtyHash "abcdef0123456789" repeated to 64 chars
    When createLedger writes the hash and openLedger reads it back
    Then hashValueToHex of the read value equals the original hex string

  Scenario: Ledger validation rejects corrupted file
    Given a ledger file with a single byte flipped
    When openLedger is called
    Then the returned pointer is nil
    And no mmap leak occurs

  Scenario: Ledger validation rejects wrong-size file
    Given a ledger file with size 100 bytes
    When openLedger is called
    Then the returned pointer is nil

  Scenario: L2 child reads dirtyHash from ledger instead of computeReceipt
    Given a parent process has created a ledger with dirtyHash
    And AXIOM_STATE_LEDGER_PATH env var points to the ledger
    When the L2 child process calls runSingleGateIfRequested
    Then the child reads dirtyHash via mmap in 0ms
    And computeReceipt is not called (no git subprocess)
