import std/unittest
import std/os
import verification/ecosystem_linkage
import core/results

suite "resolveStandardLibraryContract contract":
  test "reads local manifest file when available":
    let tmpDir = getTempDir() / "axiom_test_hub"
    createDir(tmpDir)
    let manifestPath = tmpDir / "io.json"
    writeFile(manifestPath, """{"qualifiedName":"std.io","moduleName":"io","version":"1.2.3","irFingerprint":"sha256:abc123"}""")
    let contractRes = resolveStandardLibraryContract("io", tmpDir)
    check contractRes.isOk()
    let contract = contractRes.get()
    check contract.qualifiedName == "std.io"
    check contract.moduleName == "io"
    check contract.version == "1.2.3"
    check contract.irFingerprint == "sha256:abc123"
    check contract.manifestPath == manifestPath
    removeFile(manifestPath)
    removeDir(tmpDir)

  test "returns Result error when local manifest is missing":
    let contractRes = resolveStandardLibraryContract("nonexistent", "/tmp/nonexistent_dir_12345")
    check contractRes.isErr()
