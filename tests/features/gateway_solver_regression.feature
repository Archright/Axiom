@legacy
@executable
@gateway @regression @solver
Feature: Gateway Solver Test Regression Fixes
  Fixes for remaining gateway_solver_test failures to achieve 0 FAILED.

  Scenario: Semantic payload workflow reports verified on Linux
    Given a semantic payload workflow runs on Linux
    When the fake lean command executes for compiler verification
    Then the negative mutation test must fail to prevent vacuous proofs
    And the workflow exit code must be 0
    And the proof state status must be "verified"

  Scenario: Natural language constraint parses spaced expressions
    Given a natural language constraint "balance is always at_least 0"
    When the expression parser normalizes the input
    Then compact string matching must find "always" and "at_least"
    And the parser must return a min-value invariant rule

  Scenario: Integrity loop counts stack reads from stacktop function calls
    Given a Bitcoin script opcode block contains "stacktop(-1)"
    When the integrity refinement loop tokenizes the block body
    Then stacktop must be counted as a stack read
    And the opcode block stackReads must be greater than 0

  Scenario: Apply-refinement matches function headers with parentheses
    Given a Nim proc signature contains "withdraw*(balance: int; amount: int)"
    When apply-refinement scans for function headers
    Then the header must be detected via literal parenthesis search
    And constraint asserts must be inserted into the function body

  Scenario: lean4_provider_test compiles after SolverStatus symbol import
    Given tests/unit/lean4_provider_test.nim references solverSat
    When nim check evaluates the test module
    Then it should compile without undeclared identifier errors
    And core/domain_types should be explicitly imported

  Scenario: buildMinimalSmt generates check-sat for scan-to-workflow conversion
    Given a scan output is converted to workflow payload
    When buildMinimalSmt generates SMT for a node
    Then the output should contain "(check-sat)"

  Scenario: convertScanToWorkflowPayload prefixes modulePath with src
    Given a scan nodeId is "core/a.nim::foo"
    When convertScanToWorkflowPayload extracts modulePath
    Then the modulePath should be "src/core/a.nim"

  Scenario: Lean4Provider returns solverUnknown for invalid payload
    Given a Lean4Provider with empty leanExe
    When prove is called with payload "def"
    Then the status should be solverUnknown
