@legacy
Feature: Contract Extractor Modular Decomposition
  As an Axiom developer
  I want contract_extractor.nim to follow SOLID principles
  So that each module has <= 15 functions and single responsibility

  Background:
    Given the project builds successfully

  Scenario: Each extracted module has <= 15 functions
    Given the contract_extractor.nim has been decomposed into 7 modules
    When I count functions in each module
    Then contract_types.nim has <= 15 symbols
    And contract_param_util.nim has <= 15 functions
    And smt_atom_generator.nim has <= 15 functions
    And contract_text_extractor.nim has <= 15 functions
    And contract_ast_extractor.nim has <= 15 functions
    And smtlib2_util.nim has <= 15 functions
    And smtlib2_sanitizer.nim has <= 15 functions
    And contract_extractor.nim facade has <= 15 functions

  Scenario: Type Purity Filter sanitizes garbage-in SMT patterns
    Given a contract with numeric literals in and/or context
    When contractToSmtlib2 is called
    Then the output contains (not (= literal 0)) instead of bare literals

  Scenario: Bool in numeric comparison is rewritten to true
    Given a contract with a Bool variable in a >= comparison
    When contractToSmtlib2 is called
    Then the output contains (assert true) for that comparison

  Scenario: Incompatible type equality is rewritten to true
    Given a contract with String = Int equality
    When contractToSmtlib2 is called
    Then the output contains (assert true) for that equality

  Scenario: Existing consumers continue to work without modification
    Given recertify_lean.nim imports contract_extractor
    When the project builds
    Then no compilation errors occur

  Scenario: Type-Driven Contract Synthesis generates baseline invariants for nat/uint
    Given a Nim function with signature `proc foo(n: nat; x: uint64)`
    When Axiom extracts contracts for `foo`
    Then the preconditions include `(assert (>= n 0))`
    And the preconditions include `(assert (>= x 0))`

  Scenario: Type-Driven Contract Synthesis generates length invariants for string/seq
    Given a Nim function with signature `proc bar(s: string; a: seq[int])`
    When Axiom extracts contracts for `bar`
    Then the preconditions include `(assert (>= (str.len s) 0))`
    And the preconditions include `(assert (>= (seq.len a) 0))`

  Scenario: AST Rule 8 detects new(result) and injects Result disjunction
    Given a Nim function body containing `new(result)`
    When Axiom performs AST-based extraction
    Then the preconditions include `(assert (or (= result.isOk true) (= result.isErr true)))`

  Scenario: AST Rule 9 detects result.field assignment and injects base invariant
    Given a Nim function body containing `result.kind = ok`
    When Axiom performs AST-based extraction
    Then the preconditions include `(assert (or (= result.isOk true) (= result.isErr true)))`
