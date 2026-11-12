@legacy
Feature: Gate Types Module
  Memory-aware concurrency utilities and process resource limits.

  Scenario: safeMaxJobs caps based on available memory
  Scenario: safeMaxJobs caps based on CPU core count
  Scenario: setProcessMemoryLimit configures RLIMIT_AS
  Scenario: resetProcessMemoryLimit clears RLIMIT_AS
