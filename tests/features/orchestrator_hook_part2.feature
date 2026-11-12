Feature: Orchestrator Hook Part 2 — L2 Parallel Dispatch
  As an Axiom operator
  I want the orchestrator to dispatch L2 gates in parallel with output capture
  So that gate execution is fast and failure logs are preserved

  Background:
    Given the Axiom gate infrastructure is initialized
    And the gate manifest defines L2 gates

  Scenario: L2 gates spawn with poStdErrToStdOut
    When the orchestrator dispatches L2 gates
    Then each L2 process should capture stdout and stderr into outputLog
    And the process should use poStdErrToStdOut option

  Scenario: completed L2 gate output is captured
    Given an L2 gate process has completed with exit code 1
    When pollL2GatesWithTimeout detects the completed process
    Then the captured output should be written to .axiom/cache/gate_output/{gateId}.log

  Scenario: passed L2 gate output file is cleaned up
    Given an L2 gate process has completed with exit code 0
    When pollL2GatesWithTimeout detects the completed process
    Then the gate output file should be deleted

  Scenario: timed-out L2 gate output is captured
    Given an L2 gate process has exceeded its timeout
    When pollL2GatesWithTimeout detects the timeout
    Then the process should be killed
    And remaining output should be written to .axiom/cache/gate_output/{gateId}.log

  Scenario: cgroups wrapping respects AXIOM_LOW_OVERHEAD
    Given AXIOM_LOW_OVERHEAD=1 is set
    When the orchestrator wraps a child command
    Then the command should not be wrapped with systemd-run

  Scenario: post-layer sweep uses SessionJournal instead of loadGateMemo
    Given a gate failed with fcPermanent in the current session
    When the post-layer sweep checks for failures
    Then the gate is found in the SessionJournal as failed
    And the gate is added to failedGates without querying the file-based memo

  Scenario: final report sweep includes timing data from SessionJournal
    Given an L2 gate completed with exit code 1 in 793ms
    When the final report sweep builds GateReport entries
    Then the report includes elapsedMs=793 and the actual failReason
    And the report includes the correct failureCategory from the journal
