## Debt Scan Gate Feature Test.
## See tests/features/debt_scan_gate.feature for the specification.
##
## Verifies the debt scan gate:
##   - Module compiles and exports runDebtScan
##   - Clean files pass the scan (no debt detected)
##   - Bare except: clauses cause a FAIL
##   - A hand-written `### [Exemption APPROVED]` marker does NOT suppress a
##     finding: the projection generator never emits that marker (DEBT#486),
##     and the gate no longer scans for it.

import std/[unittest, os, strutils, times]
import gate/runners/debt_scan_gate

suite "Debt Scan Gate":
  setup:
    let tmpDir = getTempDir() / "axiom_debt_scan_test_" & $epochTime().int
    createDir(tmpDir / "src")

  teardown:
    removeDir(tmpDir)

  test "runDebtScan passes on a clean small file":
    ## Given a .nim file under 500 lines with no debt indicators
    ## When runDebtScan is invoked
    ## Then it returns true (PASS)
    writeFile(tmpDir / "src" / "clean.nim", "echo \"hello world\"\n")
    check runDebtScan(tmpDir, @[]) == true

  test "runDebtScan fails on bare except clause":
    ## Given a .nim file containing a bare except: clause
    ## When runDebtScan is invoked
    ## Then it returns false (FAIL) — bare except violates policy
    let badCode = "try:\n  discard\nexcept:\n  discard\n"
    writeFile(tmpDir / "src" / "bad.nim", badCode)
    check runDebtScan(tmpDir, @[]) == false

  test "runDebtScan ignores a hand-written markdown exemption marker":
    ## Given a .nim file with bare except and a DEBT_REGISTRY.md containing the
    ## former `### [Exemption APPROVED] <path>` marker
    ## When runDebtScan is invoked
    ## Then it still returns false — the gate has no markdown exemption path
    ##      (the projection generator never emits that marker; DEBT#486)
    let badCode = "try:\n  discard\nexcept:\n  discard\n"
    writeFile(tmpDir / "src" / "exempted.nim", badCode)
    createDir(tmpDir / "docs")
    writeFile(tmpDir / "docs" / "DEBT_REGISTRY.md",
      "### [Exemption APPROVED] src/exempted.nim\n" &
      "| **Reason** | legacy code being ported |\n")
    check runDebtScan(tmpDir, @[]) == false

  test "runDebtScan still passes a clean file when the marker file is present":
    ## Given a clean .nim file and a DEBT_REGISTRY.md carrying the former marker
    ## When runDebtScan is invoked
    ## Then it returns true — unrelated markdown text does not create findings
    writeFile(tmpDir / "src" / "clean.nim", "echo \"hello world\"\n")
    createDir(tmpDir / "docs")
    writeFile(tmpDir / "docs" / "DEBT_REGISTRY.md",
      "### [Exemption APPROVED] src/clean.nim\n")
    check runDebtScan(tmpDir, @[]) == true

  test "runDebtScan passes on empty file list with no src directory":
    ## Given a repo root with no src/ directory and no explicit files
    ## When runDebtScan is invoked with empty file list
    ## Then it returns true — nothing to scan
    let emptyDir = tmpDir / "empty"
    createDir(emptyDir)
    check runDebtScan(emptyDir, @[]) == true

  test "runDebtScan detects deprecated tree_sitter_bridge import":
    ## Given a .nim file importing the deprecated tree_sitter_bridge module
    ## When runDebtScan is invoked
    ## Then it returns false (FAIL)
    let tsbCode = "import tree_sitter_bridge\nproc foo() = discard\n"
    writeFile(tmpDir / "src" / "deprecated_import.nim", tsbCode)
    check runDebtScan(tmpDir, @[]) == false
