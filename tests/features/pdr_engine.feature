Feature: PDR Engine — Property Directed Reachability Solver
  As the verification pipeline,
  the pdr_engine module must provide PDR/IC3 inductive invariant synthesis
  via Z3 fixed-point queries,
  enabling fast safety proofs before CEGAR fallback.

  Background:
    Given the pdr_engine module is used by cegar_engine

  # ── Type definitions ─────────────────────────────────────────────

  Scenario: PdrConfig defines solver parameters
    Given a PdrConfig value
    Then it has maxFrames for PDR depth limit
    And it has z3TimeoutMs for Z3 query timeout
    And it has maxGeneralizeDepth for clause generalization

  Scenario: PdrResult captures solver outcome
    Given a PdrResult value
    Then it has converged indicating success
    And it has inductiveInvariant as seq[string] of SMT-LIB2 expressions
    And it has iterations and elapsedMs for diagnostics
    And it has error for failure messages

  # ── Default constants ────────────────────────────────────────────

  Scenario: DefaultMaxFrames is 20
    Given the DefaultMaxFrames constant
    Then its value is 20

  Scenario: DefaultMaxGeneralizeDepth is 3
    Given the DefaultMaxGeneralizeDepth constant
    Then its value is 3

  # ── runPdrEngine interface ───────────────────────────────────────

  Scenario: runPdrEngine accepts SMT-LIB2 property and returns PdrResult
    Given a property, initial state, and transition relation in SMT-LIB2
    When runPdrEngine is called
    Then a PdrResult is returned
    And the result indicates whether an inductive invariant was found

  # ── CEGAR fallback ───────────────────────────────────────────────

  Scenario: Non-converged PDR falls back to CEGAR
    Given runPdrEngine returns converged=false
    When cegar_engine receives the result
    Then it proceeds with CEGAR iterations
