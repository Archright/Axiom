{.push raises: [CatchableError].}

## test_invariant_anchor_fail_closed.nim — DEBT#533 fail-closed anchor contract.
##
## The regression this guards: treating a missing `data/expected_invariant_hash.txt`
## as a "cold start" and deriving the anchor from the tree under test lets one
## change both `src/core/trusted/architecture_invariants.nim` and its reference
## hash and still observe "Invariant hash: OK". The mutant that restores that
## branch (anchor-missing -> iavOk) must fail every assertion below.
##
## The adjudication is tested as a pure function, so this suite never spawns the
## hermetic orchestrator and never touches the working repository.

import std/unittest

import core/utils/build_provenance

const
  HashA = "3da71963b18c1988ff17fb6547b99b05d19ada8f5aa2a954f08857e5949e92e6"
  HashB = "0000000000000000000000000000000000000000000000000000000000000000"

suite "judgeInvariantAnchor — fail-closed anchor adjudication (DEBT#533)":

  test "missing anchor fails even when the source hash is self-consistent":
    # The exact exploit: the tree provides a hash of itself, the anchor is gone.
    check judgeInvariantAnchor(true, false, HashA, "") == iavAnchorMissing

  test "missing anchor is not satisfied by an empty expected hash":
    check judgeInvariantAnchor(true, false, "", "") == iavAnchorMissing

  test "missing invariant source fails":
    check judgeInvariantAnchor(false, true, HashA, HashA) == iavInvariantsMissing

  test "missing invariant source outranks a missing anchor":
    check judgeInvariantAnchor(false, false, "", "") == iavInvariantsMissing

  test "matching hash is ok":
    check judgeInvariantAnchor(true, true, HashA, HashA) == iavOk

  test "mismatched hash fails":
    check judgeInvariantAnchor(true, true, HashA, HashB) == iavMismatch

  test "whitespace is never normalized into a match":
    # Trimming is the caller's contract; the adjudicator compares verbatim, so a
    # blank-padded anchor cannot be laundered into agreement here.
    check judgeInvariantAnchor(true, true, HashA, HashA & " ") == iavMismatch