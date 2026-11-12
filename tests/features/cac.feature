@legacy
Feature: Content-Addressable Cache
  Cache validation uses certificate fingerprints, not file modification times.
  Immune to comment-only source changes.

  Scenario: Cache is valid when fingerprints match
    Given asi_cache.json has certFingerprints matching certificate vault
    When isAsiCacheValid is called
    Then result is true

  Scenario: Cache is invalid when fingerprint differs
    Given certificate vault fingerprint differs from cache
    When isAsiCacheValid is called
    Then result is false