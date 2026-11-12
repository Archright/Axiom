Feature: Overlay Mount (3-tier fallback)
  As the hermetic build engine
  I need a layered filesystem isolation mechanism that cascades from OverlayFS to hardlinks to copy
  So that gates execute in hermetic file environments with the best available isolation

  Background:
    Given the Axiom gate infrastructure is initialized
    And a temporary test directory exists

  Scenario: detectBestTier returns the highest available isolation tier
    Given the system capabilities are probed
    When I call detectBestTier
    Then the returned tier is one of OverlayFS, Hardlink, or Copy
    And the returned tier reflects the best isolation available on this system

  Scenario: mountForGate creates an overlay workdir
    Given the best available mount tier is determined
    When I call mountForGate for a specific gate
    Then a work directory is created under the temporary test directory
    And the work directory is ready for file operations
    And the mount metadata records the gate identifier

  Scenario: cleanupMount removes the mount point
    Given a mount has been created for a gate
    When I call cleanupMount for that gate
    Then the mount work directory no longer exists
    And the mount metadata is removed from the registry
