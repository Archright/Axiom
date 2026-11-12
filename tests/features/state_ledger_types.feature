@v27
Feature: State Ledger Types — Fixed-Size Binary Layout
  Defines the binary layout for the cross-process pipeline state ledger.
  All types have compile-time size assertions ensuring deterministic layout.

  Background:
    Given the Axiom project uses Nim 2.2.10 with ARC memory management

  Scenario: LedgerHeader is exactly 64 bytes
    Given LedgerHeader contains magic, version, headerSize, totalSize, epoch, gateCount, reserved
    When sizeof(LedgerHeader) is evaluated
    Then the result is 64

  Scenario: WorkspaceState is exactly 160 bytes
    Given WorkspaceState contains dirtyHash, ruleHash, buildEnvHash, baseCommit, timestamp, stage, mode, reserved
    When sizeof(WorkspaceState) is evaluated
    Then the result is 160

  Scenario: GateStateEntry is exactly 128 bytes
    Given GateStateEntry contains gateIdHash, cacheKey, result, tier, reserved
    When sizeof(GateStateEntry) is evaluated
    Then the result is 128

  Scenario: GateLedger is exactly 7,400 bytes
    Given GateLedger contains header, workspace, 56 gate entries, and checksum
    When sizeof(GateLedger) is evaluated
    Then the result is 7400

  Scenario: hashValueFromHex round-trips correctly
    Given a 64-char hex string "0123456789abcdef" repeated 4 times
    When hashValueFromHex converts it to HashValue
    And hashValueToHex converts it back
    Then the result equals the original hex string

  Scenario: sha1HexToBytes converts 40-char hex to 20 bytes
    Given a 40-char hex string "da39a3ee5e6b4b0d3255bfef95601890afd80709"
    When sha1HexToBytes is called
    Then the result is a 20-byte array
    And byte[0] is 0xda and byte[1] is 0x39
