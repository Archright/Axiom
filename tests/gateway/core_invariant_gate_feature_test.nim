## Core Invariant Gate Feature Test.
## See tests/features/core_invariant_gate.feature for the specification.
##
## Verifies the isCoreDirectChild path classifier and that the module
## compiles with its key exports accessible. The gate scans direct children
## of src/core/ for forbidden I/O primitives.

import std/[unittest, os, strutils]
import gate/runners/core_invariant_gate

suite "Core Invariant Gate — isCoreDirectChild":
  test "direct child .nim file is recognized":
    check isCoreDirectChild("src/core/types.nim") == true

  test "non-.nim file is rejected":
    check isCoreDirectChild("src/core/types.py") == false

  test "subdirectory nested file is rejected":
    check isCoreDirectChild("src/core/topology/types.nim") == false

  test "file outside src/core/ is rejected":
    check isCoreDirectChild("src/cli/main.nim") == false

  test "empty string is rejected":
    check isCoreDirectChild("") == false

  test "src/core/ directory prefix without file is rejected":
    check isCoreDirectChild("src/core/") == false

  test "absolute path containing src/core/ is handled":
    check isCoreDirectChild("/home/user/project/src/core/types.nim") == true

  test "absolute path to subdirectory is rejected":
    check isCoreDirectChild("/home/user/project/src/core/sub/mod.nim") == false

  test "file with src/core in name but wrong path is rejected":
    check isCoreDirectChild("lib/src/core_foo.nim") == false

suite "Core Invariant Gate — checkFile on clean core module":
  test "checkFile returns empty violations for a clean file":
    ## Write a temporary clean .nim file with only imports.
    let tmpPath = getTempDir() / "axiom_test_core_clean.nim"
    writeFile(tmpPath, "import std/strutils\n\nfunc add(a, b: int): int = a + b\n")
    let violations = checkFile(tmpPath)
    check violations.len == 0
    removeFile(tmpPath)

  test "checkFile detects readFile( in core module":
    let tmpPath = getTempDir() / "axiom_test_core_readfile.nim"
    writeFile(tmpPath, "let content = readFile(\"data.json\")\n")
    let violations = checkFile(tmpPath)
    check violations.len == 1
    removeFile(tmpPath)

  test "checkFile detects writeFile( in core module":
    let tmpPath = getTempDir() / "axiom_test_core_writefile.nim"
    writeFile(tmpPath, "writeFile(\"output.txt\", \"hello\")\n")
    let violations = checkFile(tmpPath)
    check violations.len == 1
    removeFile(tmpPath)

  test "checkFile detects execProcess( in core module":
    let tmpPath = getTempDir() / "axiom_test_core_execproc.nim"
    writeFile(tmpPath, "let out = execProcess(\"ls\")\n")
    let violations = checkFile(tmpPath)
    check violations.len == 1
    removeFile(tmpPath)

  test "checkFile detects startProcess( in core module":
    let tmpPath = getTempDir() / "axiom_test_core_startproc.nim"
    writeFile(tmpPath, "let p = startProcess(\"ls\")\n")
    let violations = checkFile(tmpPath)
    check violations.len == 1
    removeFile(tmpPath)

  test "checkFile detects 'when isMainModule' in core module":
    let tmpPath = getTempDir() / "axiom_test_core_whenmain.nim"
    writeFile(tmpPath, "when isMainModule:\n  echo \"hello\"\n")
    let violations = checkFile(tmpPath)
    check violations.len == 1
    removeFile(tmpPath)

  test "checkFile skips comment lines containing forbidden patterns":
    let tmpPath = getTempDir() / "axiom_test_core_comment.nim"
    writeFile(tmpPath, "# readFile(\"skipme\")\n# writeFile(\"skipme\")\n")
    let violations = checkFile(tmpPath)
    check violations.len == 0
    removeFile(tmpPath)

  test "checkFile detects multiple violations in one file":
    let tmpPath = getTempDir() / "axiom_test_core_multi.nim"
    writeFile(tmpPath,
      "let c = readFile(\"a\")\n" &
      "writeFile(\"b\", c)\n" &
      "when isMainModule:\n  echo 1\n")
    let violations = checkFile(tmpPath)
    check violations.len >= 3
    removeFile(tmpPath)
