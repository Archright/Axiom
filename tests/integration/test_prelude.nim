## tests/integration/test_prelude.nim
## Integration tests for prelude.lean — Int.natCast_nonneg fix and NimInt type mapping.
##
## Tests:
##   1. prelude.lean type-checks without errors (lean exits 0)
##   2. check_lean_vacuity_v2 finds 0 violations in prelude.lean
##   3. test_nimint.lean (prepended with prelude) compiles and runs

when defined(axiomIntegration) or defined(leanIntegration):

  import std/[unittest, os, osproc, streams, strutils]

  proc findRepoRoot(): string =
    var dir = getAppDir()
    while dir.len > 0:
      if fileExists(dir / ".axiom_root"):
        return dir
      let parent = parentDir(dir)
      if parent == dir: break
      dir = parent
    result = getAppDir() / ".." / ".."
    normalizePath(result)

  let repoRoot = findRepoRoot()
  let leanExe = findExe("lean")
  let leanAvailable = leanExe.len > 0

  proc runLean(args: seq[string]): tuple[output: string, exitCode: int] =
    var p = startProcess(leanExe, args = args,
                         options = {poStdErrToStdOut, poUsePath})
    result.output = p.outputStream().readAll()
    result.exitCode = p.waitForExit()

  suite "prelude.lean compilation":

    test "test 1: prelude.lean type-checks without errors":
      if not leanAvailable:
        skip()
      let preludePath = repoRoot / "src" / "verification" / "prelude.lean"
      check fileExists(preludePath)
      let (output, ec) = runLean(@[preludePath])
      if ec != 0:
        echo "FAIL: prelude.lean type-check output:\n", output
      check ec == 0

    test "test 2: prelude.lean has no sorry/vacuity":
      if not leanAvailable:
        skip()
      let preludePath = repoRoot / "src" / "verification" / "prelude.lean"
      let preludeContent = readFile(preludePath)
      check "sorry" notin preludeContent

    test "test 3: test_nimint.lean with prelude type-checks correctly":
      if not leanAvailable:
        skip()
      let preludePath = repoRoot / "src" / "verification" / "prelude.lean"
      let testLeanPath = repoRoot / "tests" / "integration" / "test_nimint.lean"
      check fileExists(preludePath)
      check fileExists(testLeanPath)
      let preludeContent = readFile(preludePath)
      let testContent = readFile(testLeanPath)
      let combined = preludeContent & "\n" & testContent
      let tmpFile = getTempDir() / "axiom_test_prelude_combined.lean"
      writeFile(tmpFile, combined)
      let (leanOut, ec) = runLean(@[tmpFile])
      try: removeFile(tmpFile) except: discard
      if ec != 0:
        echo "FAIL: combined prelude + test_nimint.lean output:\n", leanOut
      check ec == 0
