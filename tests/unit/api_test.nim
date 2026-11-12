import std/unittest
import api

# src/api.nim forwarding stub re-exports src/api/api.nim's pure sorter
# constructors. These tests exercise the round-trip determinism of the
# forwarded SorterNodeId accessors (not a vacuous importability check).
suite "api forwarding surface":
  test "verificationSorterNodeId round-trips to its raw string":
    let raw = "Core/verify/resolveNodeOutcome"
    check verificationSorterNodeIdString(initVerificationSorterNodeId(raw)) == raw
    check verificationSorterNodeIdString(
      initVerificationSorterNodeId(raw)) ==
      verificationSorterNodeIdString(initVerificationSorterNodeId(raw))

  test "distinct raw strings produce distinct node ids":
    let a = initVerificationSorterNodeId("module/a")
    let b = initVerificationSorterNodeId("module/b")
    check verificationSorterNodeIdString(a) != verificationSorterNodeIdString(b)
    check verificationSorterNodeIdString(a) == "module/a"
