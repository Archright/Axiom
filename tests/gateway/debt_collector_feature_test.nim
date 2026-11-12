{.push raises: [CatchableError].}
## BDD feature test for debt_collector.feature
## Verifies axiomCollect macro, path invariant detection, and debt hint emission.
##
## Hermetic: all tests use embedded strings and compile-time checks, no I/O.

import std/unittest
import std/strutils

# Import the module under test
import core/trusted/debt_collector

suite "debt_collector — compile-time debt scanning":

  test "AbsolutePathPatterns contains expected prefixes":
    ## Verify the pattern list covers all known absolute path styles.
    check AbsolutePathPatterns.len >= 4
    check "/home/" in AbsolutePathPatterns
    check "/Users/" in AbsolutePathPatterns
    check "C:\\" in AbsolutePathPatterns
    check "/root/" in AbsolutePathPatterns

  test "AbsolutePathPatterns does not contain relative paths":
    ## Ensure no relative path patterns sneak in.
    for pat in AbsolutePathPatterns:
      check pat.startsWith("/") or pat.startsWith("C")

  test "axiomCollect without -d:axiomScan is a no-op":
    ## Scenario: axiomCollect without -d:axiomScan is a no-op
    ## Given a module containing a hardcoded path
    ## When I compile without -d:axiomScan
    ## Then compilation succeeds without debt hints
    axiomCollect:
      let path = "/home/user/project"
      check path.len > 0

  test "axiomCollect is a macro":
    ## Verify axiomCollect is callable as a macro.
    ## Without -d:axiomScan it should be a transparent pass-through.
    axiomCollect:
      proc dummyProc(): int = 42
      check dummyProc() == 42
