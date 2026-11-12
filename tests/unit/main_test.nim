{.push raises: [CatchableError].}

## Unit tests for src/cli/main.nim — covers computeSourceTreeHash, the
## deterministic source fingerprint used by the engine self-bootstrap check
## (checkAndSelfBootstrap compares it against the compile-time BuildSourceHash).
## hotspot-coverage-gate requires the most-churned source module to be backed
## by a test; these are behavioral assertions on the module's own pure logic,
## not compiler-guaranteed behaviors (§0.7).

import std/[unittest, os, times]
import cli/main

suite "computeSourceTreeHash":
  test "deterministic: identical tree → identical hash across calls":
    let tmpDir = getTempDir() / "axiom_main_test_" & $epochTime().int
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    writeFile(tmpDir / "alpha.nim", "echo(1)\n")
    writeFile(tmpDir / "beta.nim", "echo(2)\n")
    let h1 = computeSourceTreeHash(tmpDir)
    let h2 = computeSourceTreeHash(tmpDir)
    check h1.len > 0
    check h1 == h2

  test "content change → hash change":
    let tmpDir = getTempDir() / "axiom_main_test_" & $epochTime().int
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    writeFile(tmpDir / "alpha.nim", "echo(1)\n")
    let before = computeSourceTreeHash(tmpDir)
    writeFile(tmpDir / "alpha.nim", "echo(41)\n")
    let after = computeSourceTreeHash(tmpDir)
    check before != after

  test "generated/ subtree is excluded from the fingerprint":
    let tmpDir = getTempDir() / "axiom_main_test_" & $epochTime().int
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    writeFile(tmpDir / "alpha.nim", "echo(1)\n")
    let withoutGenerated = computeSourceTreeHash(tmpDir)
    createDir(tmpDir / "generated")
    writeFile(tmpDir / "generated" / "synth.nim", "echo(999)\n")
    let withGenerated = computeSourceTreeHash(tmpDir)
    check withGenerated == withoutGenerated

  test "non-nim files do not affect the fingerprint":
    let tmpDir = getTempDir() / "axiom_main_test_" & $epochTime().int
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    writeFile(tmpDir / "alpha.nim", "echo(1)\n")
    let before = computeSourceTreeHash(tmpDir)
    writeFile(tmpDir / "notes.txt", "not code\n")
    let after = computeSourceTreeHash(tmpDir)
    check after == before

  test "adding a nim file → hash change":
    let tmpDir = getTempDir() / "axiom_main_test_" & $epochTime().int
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    writeFile(tmpDir / "alpha.nim", "echo(1)\n")
    let before = computeSourceTreeHash(tmpDir)
    writeFile(tmpDir / "gamma.nim", "echo(3)\n")
    let after = computeSourceTreeHash(tmpDir)
    check before != after

{.pop.}
