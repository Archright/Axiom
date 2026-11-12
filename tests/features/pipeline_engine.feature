@pipeline-engine
Feature: Unified Deterministic Pipeline Engine
  Single-pass project scanning, AST caching, deterministic state hashing,
  incremental gate dispatch, and build integration for the Axiom integrity
  proof engine.

  Background:
    Given the Axiom system is initialized

  # ── Scanner / ProjectMap ──────────────────────────────────────────────

  Scenario: Single-pass scanner creates ProjectMap
    Given "src/core/observer/scanner.nim" exists
    When the scanner runs over all source directories
    Then every source file is present in the ProjectMap exactly once
    And each entry has a valid SHA-256 content hash

  Scenario: Scanner excludes build artifacts and caches
    Given "src/core/observer/scanner.nim" exists
    When the scanner runs with default exclusions
    Then "build/" directory contents are absent from the ProjectMap
    And "nimcache/" directory contents are absent from the ProjectMap

  # ── AST Caching ──────────────────────────────────────────────────────

  Scenario: AST cache reuses IdentCache and ConfigRef across files
    Given "src/core/observer/ast_builder.nim" exists
    Then AST builder shares a single IdentCache across parses
    And AST builder shares a single ConfigRef across parses

  Scenario: Parse-once semantics prevent redundant AST construction
    Given a source file has been parsed in the current session
    When the same source file is requested again
    Then the cached AST is returned without re-parsing

  # ── State Hashing ────────────────────────────────────────────────────

  Scenario: StateHash combines source, config, and gate hashes
    Given "src/core/observer/state_hash.nim" exists
    When StateHash is computed for the project
    Then it incorporates the source content hash
    And it incorporates the config hash
    And it incorporates the gate source hash

  Scenario: Identical project state produces identical StateHash
    Given the project state is unchanged
    When StateHash is computed twice
    Then both hashes are equal

  Scenario: State change in any component changes StateHash
    Given a valid baseline StateHash exists
    When a source file is modified
    Then the recomputed StateHash differs from the baseline

  # ── Incremental State Persistence ────────────────────────────────────

  Scenario: State is persisted to .axiom_state.json
    Given the pipeline has completed a full run
    Then ".axiom_state.json" should exist at the project root

  Scenario: Unchanged state skips re-execution
    Given ".axiom_state.json" matches the current project state
    When the pipeline is invoked again
    Then all gates are skipped and the run completes in sub-second time

  Scenario: State drift triggers incremental re-execution
    Given ".axiom_state.json" does not match the current project state
    When the pipeline is invoked
    Then only source-dependent gates are re-executed

  # ── Gate Orchestrator ────────────────────────────────────────────────

  Scenario: Pipeline orchestrator dispatches in-process gates
    Given "src/gate/pipeline_orchestrator.nim" exists
    When a gate registered as GateFunc is dispatched
    Then it executes in-process without spawning a child process

  Scenario: Pipeline orchestrator dispatches external gates
    Given "src/gate/pipeline_orchestrator.nim" exists
    When a gate registered as an external binary is dispatched
    Then it executes as a separate process and its exit code is captured

  # ── Incremental Dispatch ─────────────────────────────────────────────

  Scenario: Source-only changes re-run only source-dependent gates
    Given only source files have changed since last run
    When the pipeline performs incremental dispatch
    Then import-encapsulation gate is re-executed
    And logging-policy gate is re-executed
    And config-only gates are skipped

  # ── CLI Entry Point ──────────────────────────────────────────────────

  Scenario: Pipeline runner accepts limit flag
    When I run "ax prove --limit 10"
    Then the exit code should be 0

  Scenario: Pipeline runner accepts workers flag
    When I run "ax prove --workers 4"
    Then the exit code should be 0

  Scenario: Pipeline runner shows help
    When I run "ax help"
    Then the exit code should be 0

  # ── Build Integration ────────────────────────────────────────────────

  Scenario: Build observer bridge translates ProjectMap for build.nim
    Given "tools/build_observer_bridge.nim" exists
    And "tools/build.nim" exists
    When the observer bridge is invoked
    Then ProjectMap data is available to the build system

  Scenario: Full pipeline run completes with zero errors
    When I run "tools/pipeline_runner.nim"
    Then the exit code should be 0
    And the output should contain "PASSED"

  # ── Gate 0: Sync Protocol Enforcement ─────────────────────────────────

  Scenario: Gate 0 blocks pipeline on detached HEAD
    Given the git HEAD is detached
    When createPipelineContext is called
    Then an AssertionDefect is raised with message containing "Detached HEAD"

  Scenario: Gate 0 blocks pipeline on uncommitted changes
    Given the working tree has uncommitted changes
    When createPipelineContext is called
    Then an AssertionDefect is raised with message containing "Uncommitted changes"

  Scenario: Gate 0 blocks pipeline without sync authorization
    Given axiom.sync-authorized is not set in git config
    And the current branch is not "main"
    When createPipelineContext is called
    Then an AssertionDefect is raised with message containing "Sync protocol violation"

  Scenario: Gate 0 passes with sync authorization
    Given axiom.sync-authorized is set to "true" in git config
    And the working tree is clean
    When createPipelineContext is called
    Then PipelineContext is created successfully with repoState populated

  # ── DAG Scheduler ────────────────────────────────────────────────────

  Scenario: DAG builder groups independent gates into same layer
    Given a set of gate configs with no dependencies
    When buildDAG is called
    Then all gates are in a single layer

  Scenario: DAG builder respects after dependencies
    Given gate B has "after": ["A"]
    When buildDAG is called
    Then gate A is in layer 0
    And gate B is in layer 1

  Scenario: DAG builder detects cycles
    Given gate A has "after": ["B"] and gate B has "after": ["A"]
    When buildDAG is called
    Then an empty result is returned

  Scenario: DAG execution runs layers sequentially
    Given a 3-layer DAG
    When executeDAG is called with failFast=true
    Then layer 0 completes before layer 1 starts
    And layer 1 completes before layer 2 starts

  Scenario: DAG execution stops on failure with failFast
    Given a 2-layer DAG where layer 0 has a failing gate
    When executeDAG is called with failFast=true
    Then layer 1 is not executed

  # ── PipelineContext Immutability ──────────────────────────────────────

  Scenario: PipelineContext is value type (object not ref object)
    Given PipelineContext is defined as object
    When assigned to a new variable
    Then the new variable is an independent copy

  Scenario: PipelineContext includes GitMetadata
    Given a PipelineContext is created
    Then repoState field contains currentBranch
    And repoState field contains headHash
    And repoState field contains syncBranchToken
