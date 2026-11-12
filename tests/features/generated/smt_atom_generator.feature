@generated @critical
Feature: smt_atom_generator
  # generated | src/core/encoding/smt_atom_generator.nim | core | critical

  Scenario: module compiles without errors
    Given the module "core/encoding/smt_atom_generator" is loaded
    Then compilation should succeed

  Scenario: exported types have valid defaults
    Given the module exports types (none)
    Then each type should be instantiable via default(T)

  Scenario: module respects import boundary
    Given the module "core/encoding/smt_atom_generator" is loaded
    Then it should not directly import "core/trusted/" or "core/types/"
    And all internal imports should go through forwarding stubs

  Scenario: exported funcs declare exception contracts
    Given the module exports funcs smtGteZero, smtLtLen, smtStrLtLen, smtNonZero, smtStrLenPos, smtSeqLenPos
    Then each func should have {.raises: [].} or {.raises: [CatchableError].}

  Scenario: func smtGteZero is callable
    Given the module "core/encoding/smt_atom_generator" is loaded
    Then func smtGteZero should return a valid value

  Scenario: func smtLtLen is callable
    Given the module "core/encoding/smt_atom_generator" is loaded
    Then func smtLtLen should return a valid value

  Scenario: func smtStrLtLen is callable
    Given the module "core/encoding/smt_atom_generator" is loaded
    Then func smtStrLtLen should return a valid value

  Scenario: func smtNonZero is callable
    Given the module "core/encoding/smt_atom_generator" is loaded
    Then func smtNonZero should return a valid value

  Scenario: func smtStrLenPos is callable
    Given the module "core/encoding/smt_atom_generator" is loaded
    Then func smtStrLenPos should return a valid value

  Scenario: func smtSeqLenPos is callable
    Given the module "core/encoding/smt_atom_generator" is loaded
    Then func smtSeqLenPos should return a valid value
