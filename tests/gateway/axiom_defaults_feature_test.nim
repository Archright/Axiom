{.push raises: [CatchableError].}
## BDD feature test for axiom_defaults.feature
## Verifies tier-specific {.push raises} templates compile correctly
## and produce the expected pragma behavior.
##
## Hermetic: all tests use compile-time checks, no I/O.

import std/unittest
import std/macros

# Import the module under test
import core/trusted/axiom_defaults

suite "axiom_defaults — tier-specific exception hygiene templates":

  test "axiomCoreDefaults is a callable template":
    ## Verify the template exists and can be instantiated.
    ## axiomCoreDefaults pushes {.raises: [].} — procs inside must not raise.
    axiomCoreDefaults:
      proc pureAdd(a, b: int): int = a + b
      check pureAdd(1, 2) == 3

  test "axiomGateDefaults allows CatchableError":
    ## Gate-tier code may raise CatchableError (e.g., Z3 solver failures).
    var caught = false
    axiomGateDefaults:
      proc gateAction(): int {.raises: [CatchableError].} =
        raise newException(CatchableError, "gate failure")
      try:
        discard gateAction()
      except CatchableError:
        caught = true
    check caught

  test "axiomCliDefaults allows Exception":
    ## CLI-tier code may raise Exception (user-facing error handling).
    var caught = false
    axiomCliDefaults:
      proc cliAction(): string {.raises: [Exception].} =
        raise newException(Exception, "cli error")
      try:
        discard cliAction()
      except Exception:
        caught = true
    check caught

  test "axiomCoreDefaults proc can return values":
    axiomCoreDefaults:
      func safeMultiply(a, b: int): int = a * b
      check safeMultiply(3, 7) == 21
