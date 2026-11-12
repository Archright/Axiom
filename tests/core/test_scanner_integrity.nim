## Tests for scanner.nim integrity semantics
##
## Per §0.7: only business scenarios, NOT compiler-guaranteed behaviors.

import std/[os, unittest, tables]
import core/observer/scanner
export scanner

suite "scanner integrity — unreadable file handling":

  test "hash failure tracked as exclusion":
    let tmpDir = getTempDir() / "axiom_scanner_hash_test_" & $getCurrentProcessId()
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let subDir = tmpDir / "src"
    createDir(subDir)
    writeFile(subDir / "valid.nim", "proc bar(): int = 2")
    let pm = scanProject(tmpDir, scanDirs = @["src"])
    check pm.fileCount == 1
    check pm.files["src/valid.nim"].contentHash.len > 0
    check pm.sourceHash.len > 0
    check pm.excludedCount == 0

  test "excludedCount is zero for clean scan":
    let tmpDir = getTempDir() / "axiom_scanner_clean_" & $getCurrentProcessId()
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let subDir = tmpDir / "src"
    createDir(subDir)
    writeFile(subDir / "a.nim", "proc a(): int = 1")
    writeFile(subDir / "b.nim", "proc b(): int = 2")
    let pm = scanProject(tmpDir, scanDirs = @["src"])
    check pm.fileCount == 2
    check pm.excludedCount == 0
    check pm.sourceHash.len > 0
