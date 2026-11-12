@generated @critical
Feature: smt_to_lean_translate
  # generated | src/core/encoding/smt_to_lean_translate.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/encoding/smt_to_lean_translate" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/encoding/smt_to_lean_translate" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs assemblePrimitiveProof, buildLeanProofFromSmtlib2, translateZ3ProofTraceToLeanTactics, extractZ3ProofTrace, sanitizeLeanSource, z3OutputToSolverStatus, generateLeanTheorem, generateAndWriteLeanTheorem
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func assemblePrimitiveProof is callable
    Given the module "core/encoding/smt_to_lean_translate" is loaded
    Then func assemblePrimitiveProof should return a valid value

  Scenario: func buildLeanProofFromSmtlib2 is callable
    Given the module "core/encoding/smt_to_lean_translate" is loaded
    Then func buildLeanProofFromSmtlib2 should return a valid value

  Scenario: func translateZ3ProofTraceToLeanTactics is callable
    Given the module "core/encoding/smt_to_lean_translate" is loaded
    Then func translateZ3ProofTraceToLeanTactics should return a valid value

  Scenario: func extractZ3ProofTrace is callable
    Given the module "core/encoding/smt_to_lean_translate" is loaded
    Then func extractZ3ProofTrace should return a valid value

  Scenario: func sanitizeLeanSource is callable
    Given the module "core/encoding/smt_to_lean_translate" is loaded
    Then func sanitizeLeanSource should return a valid value

  Scenario: func z3OutputToSolverStatus is callable
    Given the module "core/encoding/smt_to_lean_translate" is loaded
    Then func z3OutputToSolverStatus should return a valid value

  # +2 more scenarios (types+funcs) omitted to stay under 50 lines
