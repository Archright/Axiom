@generated @critical
Feature: smt_to_lean_codegen
  # generated | src/core/encoding/smt_to_lean_codegen.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/encoding/smt_to_lean_codegen" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types Z3ProofNodeKind
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/encoding/smt_to_lean_codegen" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs sexprToZ3ProofNode, z3ProofNodeToLeanExpr, z3ProofNodeToLeanTactic, buildLeanProofScriptFromTrace
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: type Z3ProofNodeKind is instantiable
    Given the module "core/encoding/smt_to_lean_codegen" is loaded
    Then type Z3ProofNodeKind should be instantiable

  Scenario: func sexprToZ3ProofNode is callable
    Given the module "core/encoding/smt_to_lean_codegen" is loaded
    Then func sexprToZ3ProofNode should return a valid value

  Scenario: func z3ProofNodeToLeanExpr is callable
    Given the module "core/encoding/smt_to_lean_codegen" is loaded
    Then func z3ProofNodeToLeanExpr should return a valid value

  Scenario: func z3ProofNodeToLeanTactic is callable
    Given the module "core/encoding/smt_to_lean_codegen" is loaded
    Then func z3ProofNodeToLeanTactic should return a valid value

  Scenario: func buildLeanProofScriptFromTrace is callable
    Given the module "core/encoding/smt_to_lean_codegen" is loaded
    Then func buildLeanProofScriptFromTrace should return a valid value
