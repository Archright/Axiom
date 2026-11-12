{.push raises: [CatchableError].}

## Atomic Deploy Unit Tests
## Verifies Nix-profile generation model: atomic symlink swap, generation tracking, rollback.

import std/[os, strutils, times, unittest]
import core/gate/atomic_deploy

var testDir: string
var origDir: string

proc setup() =
  origDir = getCurrentDir()
  testDir = getTempDir() / "axiom_atomic_deploy_test_" & $epochTime().int
  createDir(testDir)
  setCurrentDir(testDir)

proc teardown() =
  setCurrentDir(origDir)
  removeDir(testDir)

suite "AtomicDeploy":
  setup()

  test "nextGenerationNumber starts at 1 for empty dir":
    if dirExists(GenerationsDir): removeDir(GenerationsDir)
    if fileExists(CurrentLink) or symlinkExists(CurrentLink): removeFile(CurrentLink)
    initDeploy()
    check nextGenerationNumber() == 1

  test "deploy creates generation file and current symlink":
    if dirExists(GenerationsDir): removeDir(GenerationsDir)
    if fileExists(CurrentLink) or symlinkExists(CurrentLink): removeFile(CurrentLink)
    initDeploy()

    deploy("abc123def456", "pipeline-test-001")
    check fileExists(GenerationsDir / "001")
    let genContent = readFile(GenerationsDir / "001")
    check "abc123def456" in genContent
    check "pipeline-test-001" in genContent
    check symlinkExists(CurrentLink) or fileExists(CurrentLink)
    check getCurrentHash() == "abc123def456"

  test "multiple deploys increment generation numbers":
    if dirExists(GenerationsDir): removeDir(GenerationsDir)
    if fileExists(CurrentLink) or symlinkExists(CurrentLink): removeFile(CurrentLink)
    initDeploy()

    deploy("hash_v1", "pipeline-001")
    deploy("hash_v2", "pipeline-002")
    deploy("hash_v3", "pipeline-003")

    check nextGenerationNumber() == 4
    check getCurrentHash() == "hash_v3"
    check fileExists(GenerationsDir / "001")
    check fileExists(GenerationsDir / "002")
    check fileExists(GenerationsDir / "003")

  test "deploy overwrites current atomically":
    if dirExists(GenerationsDir): removeDir(GenerationsDir)
    if fileExists(CurrentLink) or symlinkExists(CurrentLink): removeFile(CurrentLink)
    initDeploy()

    deploy("first_hash", "p1")
    check getCurrentHash() == "first_hash"
    deploy("second_hash", "p2")
    check getCurrentHash() == "second_hash"

  test "listGenerations returns sorted generation list":
    if dirExists(GenerationsDir): removeDir(GenerationsDir)
    if fileExists(CurrentLink) or symlinkExists(CurrentLink): removeFile(CurrentLink)
    initDeploy()

    deploy("hash_alpha", "p1")
    deploy("hash_beta", "p2")
    let gens = listGenerations()
    check gens.len == 2
    check gens[0].number == 1
    check gens[0].storeHash == "hash_alpha"
    check gens[1].number == 2
    check gens[1].storeHash == "hash_beta"

  test "rollback reverts to previous generation":
    if dirExists(GenerationsDir): removeDir(GenerationsDir)
    if fileExists(CurrentLink) or symlinkExists(CurrentLink): removeFile(CurrentLink)
    initDeploy()

    deploy("hash_v1", "p1")
    deploy("hash_v2", "p2")
    check getCurrentHash() == "hash_v2"

    rollback()
    let currentHash = getCurrentHash()
    check currentHash == "hash_v1"
    let gens = listGenerations()
    check gens.len == 3  # original 2 + rollback re-deploy

  test "getCurrentHash returns empty when no deployment":
    if dirExists(GenerationsDir): removeDir(GenerationsDir)
    if fileExists(CurrentLink) or symlinkExists(CurrentLink): removeFile(CurrentLink)
    check getCurrentHash() == ""

teardown()
