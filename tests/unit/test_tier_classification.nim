import std/unittest
import core/types/verification_tier

suite "tierFromResults classification":
  test "Z3 unsat + Lean true -> vtDual":
    check tierFromResults(true, true) == vtDual
  test "Z3 sat + Lean true -> vtLeanOnly":
    check tierFromResults(false, true) == vtLeanOnly
  test "Z3 unsat + Lean false -> vtZ3Only":
    check tierFromResults(true, false) == vtZ3Only
  test "Z3 sat + Lean false -> vtNone":
    check tierFromResults(false, false) == vtNone
