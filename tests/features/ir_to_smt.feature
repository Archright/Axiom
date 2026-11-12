@legacy
Feature: IR → SMT-LIB2 Conversion
  Converts Axiom Core IR into valid SMT-LIB2 strings suitable for Z3
  bitvector verification. Maps IR types and operations to SMT-LIB2
  equivalents (bvadd, bvmul, bvslt, ite, etc.).

  Background:
    Given the Axiom system is initialized

  Scenario: IR type to SMT-LIB2 type
    When irTypeToSmt converts irtBitVec64
    Then the result is "(_ BitVec 64)"

  Scenario: Boolean type conversion
    When irTypeToSmt converts irtBool
    Then the result is "Bool"

  Scenario: Arithmetic expression to SMT
    When irExprToSmt converts boAdd
    Then the result contains "bvadd"

  Scenario: Conditional expression to SMT
    When irExprToSmt converts irIf
    Then the result contains "ite"
