@legacy
@executable
@z3 @integrity @stability
Feature: Z3 Solver Process Integrity and Stability
  The Z3 persistent process pool must clean up workers on exit and
  must not deadlock under concurrent load.

  Background:
    Given the Z3 persistent pool is initialized with worker processes

  Rule: Z3 worker processes must terminate on normal process exit
    Scenario: After ax prove completes
      Given ax prove has run
      When the parent process exits normally
      Then no orphaned z3 -smt2 -in processes remain

  Rule: Z3 worker pool must not deadlock under parallel load
    Scenario: Running ax prove with max worker count
      Given the machine has 8+ CPU cores
      When ax prove is executed with workerCount set to the default cap
      Then the orchestration loop completes without hanging
      And all proof requests either succeed or timeout gracefully

  Rule: Parallel semaphore tickets must not leak
    Scenario: A proof request fails mid-execution
      Given a solver task is in progress
      When an exception occurs during proof execution
      Then the solver semaphore ticket is released via defer
      And subsequent tasks can acquire the ticket
