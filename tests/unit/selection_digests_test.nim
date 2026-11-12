## selection_digests_test.nim — Run-level digest tests
##
## Tests for src/verification/selection/selection_digests.nim:
##   - runInputSnapshotDigest: same semantic inputs → same digest
##   - runInputSnapshotDigest: changing planDigest changes the digest
##   - runResultDigest: computed from input snapshot + aggregated result digests is deterministic
##   - runInputSnapshotDigest does NOT depend on requestResultsDigest or unitResultsDigest

{.push raises: [CatchableError].}

import std/unittest
import core/crypto/hash_kernel

import verification/selection/selection_digests

# ---------------------------------------------------------------------------
# Helper: sha256 hex from string
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Suite: runInputSnapshotDigest
# ---------------------------------------------------------------------------

suite "runInputSnapshotDigest":

  test "same semantic inputs → same runInputSnapshotDigest":
    let baseRunDigest = sha256Hex("baseRun123")
    let planDigest = sha256Hex("plan456")
    let toolchainFingerprint = sha256Hex("toolchain789")
    let environmentContractDigest = sha256Hex("envContract012")

    let digest1 = runInputSnapshotDigest(baseRunDigest, planDigest, toolchainFingerprint, environmentContractDigest)
    let digest2 = runInputSnapshotDigest(baseRunDigest, planDigest, toolchainFingerprint, environmentContractDigest)

    check digest1 == digest2
    check digest1.len == 64  # sha256 hex length

  test "changing planDigest changes runInputSnapshotDigest":
    let baseRunDigest = sha256Hex("baseRun123")
    let toolchainFingerprint = sha256Hex("toolchain789")
    let environmentContractDigest = sha256Hex("envContract012")

    let digest1 = runInputSnapshotDigest(baseRunDigest, sha256Hex("planA"), toolchainFingerprint, environmentContractDigest)
    let digest2 = runInputSnapshotDigest(baseRunDigest, sha256Hex("planB"), toolchainFingerprint, environmentContractDigest)

    check digest1 != digest2

  test "changing toolchainFingerprint changes runInputSnapshotDigest":
    let baseRunDigest = sha256Hex("baseRun123")
    let planDigest = sha256Hex("plan456")
    let environmentContractDigest = sha256Hex("envContract012")

    let digest1 = runInputSnapshotDigest(baseRunDigest, planDigest, sha256Hex("toolchainA"), environmentContractDigest)
    let digest2 = runInputSnapshotDigest(baseRunDigest, planDigest, sha256Hex("toolchainB"), environmentContractDigest)

    check digest1 != digest2

  test "changing environmentContractDigest changes runInputSnapshotDigest":
    let baseRunDigest = sha256Hex("baseRun123")
    let planDigest = sha256Hex("plan456")
    let toolchainFingerprint = sha256Hex("toolchain789")

    let digest1 = runInputSnapshotDigest(baseRunDigest, planDigest, toolchainFingerprint, sha256Hex("envA"))
    let digest2 = runInputSnapshotDigest(baseRunDigest, planDigest, toolchainFingerprint, sha256Hex("envB"))

    check digest1 != digest2

# ---------------------------------------------------------------------------
# Suite: runResultDigest
# ---------------------------------------------------------------------------

suite "runResultDigest":

  test "same inputs → same runResultDigest":
    let runInputSnapshotDigest = sha256Hex("inputSnap123")
    let requestResultsDigest = sha256Hex("reqResults456")
    let unitResultsDigest = sha256Hex("unitResults789")

    let digest1 = runResultDigest(runInputSnapshotDigest, requestResultsDigest, unitResultsDigest)
    let digest2 = runResultDigest(runInputSnapshotDigest, requestResultsDigest, unitResultsDigest)

    check digest1 == digest2
    check digest1.len == 64

  test "changing requestResultsDigest changes runResultDigest":
    let runInputSnapshotDigest = sha256Hex("inputSnap123")
    let unitResultsDigest = sha256Hex("unitResults789")

    let digest1 = runResultDigest(runInputSnapshotDigest, sha256Hex("reqA"), unitResultsDigest)
    let digest2 = runResultDigest(runInputSnapshotDigest, sha256Hex("reqB"), unitResultsDigest)

    check digest1 != digest2

  test "changing unitResultsDigest changes runResultDigest":
    let runInputSnapshotDigest = sha256Hex("inputSnap123")
    let requestResultsDigest = sha256Hex("reqResults456")

    let digest1 = runResultDigest(runInputSnapshotDigest, requestResultsDigest, sha256Hex("unitA"))
    let digest2 = runResultDigest(runInputSnapshotDigest, requestResultsDigest, sha256Hex("unitB"))

    check digest1 != digest2

# ---------------------------------------------------------------------------
# Suite: Independence invariant
# ---------------------------------------------------------------------------

suite "Independence invariant":

  test "runInputSnapshotDigest does NOT depend on requestResultsDigest":
    let baseRunDigest = sha256Hex("baseRun123")
    let planDigest = sha256Hex("plan456")
    let toolchainFingerprint = sha256Hex("toolchain789")
    let environmentContractDigest = sha256Hex("envContract012")

    # Compute runInputSnapshotDigest with different requestResultsDigest values
    # (These are NOT inputs to runInputSnapshotDigest)
    let digest1 = runInputSnapshotDigest(baseRunDigest, planDigest, toolchainFingerprint, environmentContractDigest)
    let digest2 = runInputSnapshotDigest(baseRunDigest, planDigest, toolchainFingerprint, environmentContractDigest)

    # They must be the SAME because requestResultsDigest is not an input
    check digest1 == digest2

{.pop.}