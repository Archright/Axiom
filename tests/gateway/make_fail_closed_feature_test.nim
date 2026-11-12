{.push raises: [CatchableError].}

## make_fail_closed — semantic regression test pair for DEBT#436.
## Asserts that a verification command whose exit status is non-zero
## propagates as non-zero (CI fail-closed), and that appending a
## cleanup swallow (|| rm -rf) to a failing command makes it return 0
## — documenting the legacy bug that DEBT#436 removed.
## Also performs a static anchor check on the repo's real Makefile.

import std/[unittest, os, osproc, strutils]

suite "make_fail_closed — semantic regression":
  let tmpDir = "/tmp/ax_mfc_test"

  setup:
    if dirExists(tmpDir):
      removeDir(tmpDir)
    createDir(tmpDir)

  teardown:
    if dirExists(tmpDir):
      removeDir(tmpDir)

  test "failing verification without swallow propagates non-zero exit":
    let makefilePath = tmpDir / "Makefile"
    writeFile(makefilePath, "SHELL := /bin/bash\n\nverify:\n\ttest 1 -eq 2\n")
    let (output, exitCode) = execCmdEx("make -f " & quoteShell(makefilePath) & " verify")
    check exitCode != 0

  test "failing verification with || rm -rf swallow returns zero (legacy bug)":
    let makefilePath = tmpDir / "Makefile"
    writeFile(makefilePath, "SHELL := /bin/bash\n\nverify:\n\ttest 1 -eq 2 || rm -rf " & tmpDir & "/junk\n")
    let (output, exitCode) = execCmdEx("make -f " & quoteShell(makefilePath) & " verify")
    check exitCode == 0

  test "static anchor: verification recipes (test-unit / test-vc-pipeline) have no || rm -rf swallow":
    ## DEBT#436 anchor. The original subject was the ci-unit-tests block,
    ## removed at the CI=0 cutover; the same verification invocations now
    ## live in the test-unit and test-vc-pipeline recipes. The invariant is
    ## unchanged: the Makefile lines invoking these verification files must
    ## exist and must not carry a `|| rm -rf` cleanup swallow.
    let makefilePath = "Makefile"
    let lines = readFile(makefilePath).splitLines()
    var foundProofInjector = false
    var foundVcComplete = false

    for line in lines:
      if line.contains("test_proof_injector.nim"):
        foundProofInjector = true
        check not line.contains("|| rm -rf")
      if line.contains("test_vc_complete.nim"):
        foundVcComplete = true
        check not line.contains("|| rm -rf")

    check foundProofInjector
    check foundVcComplete

{.pop.}