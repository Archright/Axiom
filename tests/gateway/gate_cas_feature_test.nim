## Gate CAS Feature Test — content-addressable storage for gate binaries.
## See tests/features/gate_cas.feature for the specification.
##
## Contract: store/retrieve by content hash, resolveCasBinaryPath returns absolute path.

import std/[unittest, os, times]
import core/gate/gate_cas

suite "Gate CAS — content-addressable storage":
  setup:
    let tmpDir = getTempDir() / "axiom_cas_test_" & $epochTime().int
    createDir(tmpDir / ".axiom" / "cache" / "gates")

  teardown:
    removeDir(tmpDir)

  test "resolveCasBinaryPath returns empty string when no entry exists":
    ## Scenario: resolveCasBinaryPath returns empty for missing entry
    ## Given no CAS entry for a gate
    ## When I call resolveCasBinaryPath
    ## Then the result is an empty string (CAS miss)
    let path = resolveCasBinaryPath("nonexistent-gate", "/tmp/fake.nim", tmpDir)
    check path.len == 0

  test "storeContentToCas and casContentByHash round-trip":
    ## Scenario: store and retrieve content by hash
    ## Given binary content
    ## When I call storeContentToCas then casContentByHash
    ## Then the lookup returns the stored content
    let content = "fake binary content"
    let hash = storeContentToCas(content, tmpDir)
    check hash.len > 0
    let found = casContentByHash(hash, tmpDir)
    check found.len > 0
    check found == content
