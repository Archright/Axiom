Feature: Axiom Status — Gate Pipeline Observability Dashboard
  As a contributor debugging gate failures,
  the axiom_status module must provide a human-readable summary
  of the most recent pipeline run, so that issues can be triaged quickly.

  Background:
    Given the Axiom gate history is recorded at ".axiom/gate_history.jsonl"
    And the gate manifest is at "src/gate/gate_manifest.json"

  # ── Default status display ────────────────────────────────────────

  Scenario: ax gate status shows latest pipeline run summary
    Given a valid gate_history.jsonl with at least one completed run
    When "ax gate status" is invoked
    Then stdout shows the pipeline run timestamp and overall result
    And each gate's pass/fail status is listed

  Scenario: ax gate status with no history shows empty state
    Given gate_history.jsonl does not exist or is empty
    When "ax gate status" is invoked
    Then stdout indicates no pipeline runs have been recorded

  # ── JSON output mode ─────────────────────────────────────────────

  Scenario: ax gate status --json produces machine-parseable output
    Given a valid gate_history.jsonl with at least one completed run
    When "ax gate status --json" is invoked
    Then stdout is valid JSON
    And the JSON contains a "gates" array with gate results

  # ── History trend ────────────────────────────────────────────────

  Scenario: ax gate status shows pipeline run history
    Given gate_history.jsonl contains 15 pipeline run entries
    When "ax gate status" is invoked
    Then stdout shows a table of recorded pipeline runs
    And each row contains timestamp, result, and gate count

  # ── Per-gate detail ──────────────────────────────────────────────

  Scenario: ax gate status --gate <id> shows detailed gate info
    Given a valid gate_history.jsonl containing gate "nimtry"
    When "ax gate status --gate nimtry" is invoked
    Then stdout shows the gate's last execution result
    And stdout shows the gate's execution duration

  Scenario: ax gate status --gate <id> for unknown gate
    Given a valid gate_history.jsonl
    When "ax gate status --gate nonexistent-gate" is invoked
    Then stderr indicates the gate was not found in history
