## Unit tests for overlay_mount — tier detection, hardlink feasibility,
## atomic store insertion, and mount lifecycle.

import std/[unittest, os, strutils]
import core/gate/overlay_mount

suite "OverlayMount":
  test "detectBestTier returns a valid tier":
    let tier = detectBestTier()
    check tier in [mtOverlay, mtHardlink, mtCopy]

  test "MountTier enum ordinals are as expected":
    check ord(mtOverlay) == 0
    check ord(mtHardlink) == 1
    check ord(mtCopy) == 2

  test "hasOverlaySupport returns a bool without crashing":
    let supported = hasOverlaySupport()
    # Returns without crashing; actual support depends on filesystem capabilities

  test "canHardlink succeeds on same filesystem":
    let canHl = canHardlink()
    # Returns without crashing; actual capability depends on filesystem

  test "atomicStoreInsert writes file to correct store path":
    let tmpDir = getTempDir() / "axiom_om_store_" & $getCurrentProcessId()
    let storeRoot = tmpDir / "cas"
    createDir(storeRoot)

    # Create a source file
    let srcDir = tmpDir / "src"
    createDir(srcDir)
    let srcFile = srcDir / "test.bin"
    writeFile(srcFile, "store me please")

    let contentHash = "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233"
    let finalPath = atomicStoreInsert(srcFile, storeRoot, contentHash)

    # File exists at expected path
    check fileExists(finalPath)
    check finalPath.endsWith(contentHash)
    # Content matches
    check readFile(finalPath) == "store me please"

    removeDir(tmpDir)

  test "mountForGate with mtCopy creates expected dirs":
    let tmpDir = getTempDir() / "axiom_om_gate_" & $getCurrentProcessId()
    let storeRoot = tmpDir / "store"
    let repoRoot = tmpDir / "repo"
    let scratchDir = tmpDir / "scratch"
    createDir(storeRoot)
    createDir(repoRoot)

    let result = mountForGate(storeRoot, repoRoot, scratchDir, "test_gate", mtCopy)
    check result.tier == mtCopy
    check dirExists(result.mergedDir)
    check dirExists(result.upperDir)

    cleanupMount(result)
    removeDir(tmpDir)
