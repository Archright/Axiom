@legacy
Feature: Vault Index Synchronization
  As a developer
  I want the vault index to remain consistent across all CLI commands
  So that ASI calculations are deterministic and certificates are not lost

  Background:
    Given the project has 1368 certificates in src/verification/certificates/
    And the vault index is empty

  @deprecated
  Scenario: ax prove --heal preserves vault entries with stale symbol graph snapshot
    Given a stale global_symbol_graph.json snapshot with bare filename modulePaths exists
    When I run "ax prove --heal --limit 10"
    Then the vault index should contain 1368 entries
    And the ASI should be 1.0000

  @deprecated
  Scenario: ax report populates vault index correctly
    When I run "ax report --calculate-asi"
    Then the vault index should contain 1368 entries
    And the ASI should be 1.0000

  Scenario: ax prove preserves vault index across inline heal
    Given the vault index has been populated by ax report
    When I run "ax prove"
    Then the vault index should contain 1368 entries
    And the ASI should be 1.0000

  Scenario: vault sync uses uint64 primitive hash set for ORC safety
    Given certificates exist with modulePath "core/json_utils.nim" and functionName "getOrDefault"
    When the vault sync runs
    Then removeUnseenVaultEntries should preserve matching entries
    And no ORC-managed string references should remain in the seenKeys set

  @deprecated
  Scenario: mtime-only change does not invalidate symbol graph cache
    Given the symbol graph cache has been built
    When a source file is touched without content change
    And I run "ax prove --heal --limit 10"
    Then buildGlobalSymbolGraph should report cached=true
    And the vault index should contain 1368 entries

  @deprecated
  Scenario: heal-on-prove updates cache merkle root after source write
    Given ax prove has run and modified source via inline heal
    When I run "ax prove --heal --limit 10"
    Then buildGlobalSymbolGraph should report cached=true
    And the total verifyCertificates time should be under 3 seconds
