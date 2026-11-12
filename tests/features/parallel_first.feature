@legacy
Feature: Parallel-First Formal Sketching Gateway Test
  Auto-generated from parallel_first_test.nim

  Scenario: Parallel-First Formal Sketching Gateway Test
    Given the Axiom system is initialized
    When Parallel-First Formal Sketching Gateway Test
    Then the result should be valid

  Scenario: check isComplexNode("core/ffi_wrapper.nim::callFFI", "") == true
    Given the Axiom system is initialized
    When check isComplexNode("core/ffi_wrapper.nim::callFFI", "") == 
    Then the result should be valid

  Scenario: check isComplexNode("core/events.nim::registerCallback", "") == true
    Given the Axiom system is initialized
    When check isComplexNode("core/events.nim::registerCallback", "")
    Then the result should be valid

  Scenario: check isComplexNode("verification/checker.nim::verifyProof", "") == true
    Given the Axiom system is initialized
    When check isComplexNode("verification/checker.nim::verifyProof",
    Then the result should be valid

  Scenario: check isComplexNode("core/math.nim::add", "proc add(a, b: int): int = a + b") ==
    Given the Axiom system is initialized
    When check isComplexNode("core/math.nim::add", "proc add(a, b: in
    Then the result should be valid

