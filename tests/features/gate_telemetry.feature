Feature: Gate Run Telemetry — Structured Execution Log Pipeline (v3)

  As a developer
  I want structured telemetry data from gate executions
  So that I can identify bottlenecks and optimize CI pipeline performance

  Background:
    Given the Axiom-core project is initialized
    And the `.axiom/cache/` directory exists

  Scenario: initContext captures boot-time metadata once
    When the gate pipeline starts with stage "pre-commit" and 5 staged files
    Then the RunContext contains stage, commit, branch, stagedFiles, epoch, and timestamp
    And the git repository is queried exactly once

  Scenario: logGate appends records to memory without I/O
    Given a TelemetryBuffer
    When I log a gate "test-gate" with result "pass" and duration 1000000ns
    Then the buffer contains 1 record
    And the record has gateId="test-gate", result="pass", durationNs=1000000

  Scenario: logGate tracks the bottleneck gate
    Given a TelemetryBuffer
    When I log gates with durations 1ms, 5ms, 3ms
    Then the bottleneck is the gate with 5ms duration
    And totalDurationNs equals the sum of all durations

  Scenario: flushToDisk writes JSONL history file atomically
    Given a TelemetryBuffer with 3 gate records
    When I call flushToDisk
    Then `.axiom/cache/gate_history.jsonl` contains 3 JSON lines
    And each line is valid JSON with gateId, result, durationNs, stage, commit fields
    And the file uses append mode (existing records are preserved)

  Scenario: flushToDisk writes run summary via temp+rename
    Given a TelemetryBuffer with gate records
    When I call flushToDisk
    Then a summary file exists in `.axiom/cache/gate_runs/`
    And the summary contains gatesTotal, gatesPassed, gatesFailed, topBottleneck
    And no `.tmp` files remain after the operation

  Scenario: flushToDisk is a no-op on empty buffer
    Given an empty TelemetryBuffer
    When I call flushToDisk
    Then no files are created

  Scenario: gcOldRuns removes summary files older than 30 days
    Given summary files with modification dates 31 days ago
    When I call gcOldRuns with maxAge=30
    Then the old files are removed

  Scenario: gcOldRuns preserves recent summary files
    Given summary files with recent modification dates
    When I call gcOldRuns with maxAge=30
    Then the recent files are preserved

  Scenario: toJsonl uses zero-allocation streaming serialization
    Given a GateRunRecord with special characters in gateId
    When I call toJsonl
    Then the output is valid JSON
    And special characters (quotes, newlines, control chars) are escaped
    And no intermediate heap allocations occur (streaming appendEscapedJson)

  Scenario: analyze_gate_bottlenecks reports top-N slowest gates
    Given gate telemetry data in `.axiom/cache/gate_history.jsonl`
    When I run `bin/analyze_gate_bottlenecks --top=5`
    Then the output shows the 5 slowest gates by mean duration
    And the output includes cache hit rate and pass/fail statistics
