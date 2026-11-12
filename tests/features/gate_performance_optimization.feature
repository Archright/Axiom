Feature: Gate Performance Optimization
  As a developer
  I want pre-push gates to complete quickly
  So that git push is not blocked by redundant computation

  @spec-density
  Scenario: Binary freshness gate does not auto-rebuild
    Given the binary freshness gate detects a stale binary
    When the gate runs
    Then it reports FAIL with a manual rebuild command
    And it does not invoke nim c internally

  @spec-density
  Scenario: Hotspot gate caches file content across scans
    Given the hotspot gate scans 669 files
    When the gate runs nesting, long-proc, and branching scans
    Then each file is read exactly once from disk
    And scan results are computed from cached content

  @spec-density
  Scenario: Hotspot ratchet gate skips redundant scan
    Given the hotspot-gate already passed via memo cache
    When the hotspot-ratchet-gate runs
    Then it skips the hotspot scan
    And only runs the debt scan portion
