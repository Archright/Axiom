Feature: Gate Hook Orchestrator — Sequential Execution with startProcess Batching
  As the git hook infrastructure,
  the orchestrator_hook must execute gate runners in order using
  startProcess batching with 4-layer resource defense, replacing
  malebolgia concurrency per OOM root cause analysis.

  Background:
    Given the orchestrator_hook binary is compiled
    And the gate registry is loaded from gate_manifest.json

  # ── Pre-commit execution ─────────────────────────────────────────

  Scenario: Pre-commit hook runs all registered pre-commit gates
    Given files are staged in git
    When the orchestrator_hook runs in pre-commit mode
    Then all gates with stage gsPreCommit are executed sequentially
    And gate results are logged to gate_history.jsonl

  Scenario: Pre-commit gate failure blocks the commit
    Given a gate returns non-zero exit code
    When the orchestrator_hook runs in pre-commit mode
    Then the hook exits with code 1
    And git commit is aborted

  # ── Pre-push execution ───────────────────────────────────────────

  Scenario: Pre-push hook runs all registered pre-push gates
    Given a push is attempted
    When the orchestrator_hook runs in pre-push mode
    Then all gates with stage gsPrePush are executed

  # ── Resource defense stack ───────────────────────────────────────

  Scenario: Gate processes are spawned with resource limits
    When a gate runner is spawned via startProcess
    Then CPU time is bounded
    And memory usage is bounded
    And wall-clock timeout is enforced

  # ── Sequential execution ─────────────────────────────────────────

  Scenario: Gates execute sequentially, not in parallel
    Given multiple gates are registered for the same stage
    When the orchestrator_hook runs
    Then each gate starts only after the previous gate completes
    And no malebolgia threads are spawned

  # ── Gate skip on dependency failure ──────────────────────────────

  Scenario: Dependent gates are skipped when prerequisite fails
    Given gate B declares after=["A"] in gate_manifest.json
    And gate A fails during execution
    When the orchestrator_hook processes the gate list
    Then gate B is skipped and not executed
