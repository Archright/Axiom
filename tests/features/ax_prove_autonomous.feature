@legacy
@cli @invisible-observability
Feature: ax prove auto-detects stale certificates
  ax prove performs a lightweight pre-flight scan for certificates already
  marked certStale in the vault index. Detected stale nodes are enqueued
  for reproof automatically without requiring a separate command.

  Rule: ax prove auto-detects stale certificates before orchestration
    Scenario: Vault index contains certStale entries
      Given the vault index has at least one certStale entry
      When I run "ax prove --limit 10"
      Then stderr contains "Auto-detected"
      And stderr contains "stale certificates, enqueueing for reproof"
      And the exit code is 0

  Rule: ax prove completes with no stale when vault is clean
    Scenario: All certificates are fingerprint-aligned
      Given the vault index contains no certStale entries
      When I run "ax prove --limit 10"
      Then stderr does not contain "stale certificates, enqueueing for reproof"
      And the exit code is 0
