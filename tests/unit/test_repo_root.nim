import std/[os, unittest]
import ../../src/core/utils/repo_root

# DEBT#550 regression — findRepoRoot root-resolution contract.
#
# The defect: a binary compiled OUTSIDE the repository tree (make test-fast
# and test-fast-one link test binaries under /tmp/opencode) ran with a
# repository CWD made the upward walk from getAppDir() reach "" (Nim
# `parentDir("/") == ""`), and `fileExists("" / ".axiom_root")` probed the
# CWD relatively — so the EMPTY STRING was returned as the "root" and
# downstream root-identity comparisons split (report-side VKD admission vs
# direct cwd-root projection). Q-013: docs/spec/nim_2_2_10_stdlib_quirks.md.
#
# The contract under test (measured, never assumed):
#   1. any start (default, explicit, empty) yields an absolute, non-empty
#      root — "" is a contract violation that defeats caller-side anchor
#      guards via the same CWD-relative match;
#   2. an out-of-repo start with a repository CWD resolves the repository
#      root through the CWD walk, not a CWD-relative "" probe;
#   3. an anchored absolute start returns the anchor directory;
#   4. with no anchor anywhere the legacy one-level-up fallback applies —
#      still absolute, still never "";
#   5. AXIOM_ROOT injection keeps winning over the walk.

proc anchorAncestor(start: string): string =
  ## Test-local upward anchor walk — independent of the module under test.
  var current = start
  while current.len > 0 and isAbsolute(current):
    if fileExists(current / ".axiom_root"):
      return current
    let parent = parentDir(current)
    if parent.len == 0 or parent == current:
      break
    current = parent
  ""

suite "findRepoRoot contract (DEBT#550)":
  test "default start never returns an empty or relative root":
    let root = findRepoRoot()
    check root.len > 0
    check isAbsolute(root)

  test "out-of-repo start with repository CWD resolves the repository root":
    let expected = anchorAncestor(getCurrentDir())
    if expected.len == 0:
      skip()
    else:
      check findRepoRoot(getTempDir()) == expected
      check findRepoRoot("") == expected
      check fileExists(findRepoRoot(getTempDir()) / ".axiom_root")

  test "absolute start inside an anchored tree returns the anchor directory":
    let base = getTempDir() / ("ax_repo_root_reg_" & $getCurrentProcessId())
    createDir(base / "inner")
    writeFile(base / ".axiom_root", "")
    defer: removeDir(base)
    let resolved = findRepoRoot(base / "inner")
    check resolved == base
    check isAbsolute(resolved)

  test "no anchor anywhere yields the absolute legacy fallback, never empty":
    let base = getTempDir() / ("ax_repo_root_reg_" & $getCurrentProcessId() & "_noanchor")
    createDir(base / "bin")
    defer: removeDir(base)
    let previous = getCurrentDir()
    defer:
      try:
        setCurrentDir(previous)
      except CatchableError:
        discard
    var cwdSwitched = true
    try:
      setCurrentDir(base / "bin")
    except CatchableError:
      cwdSwitched = false
      skip()
    if cwdSwitched:
      # Start walk fails (no anchor above the temp tree); the CWD walk starts
      # at the same directory and fails too; the legacy fallback is one level
      # up from the walk start — absolute, never "".
      check findRepoRoot(base / "bin") == base
      check isAbsolute(findRepoRoot(base / "bin"))
      # Empty start resolves to the (anchor-less) current directory, then the
      # same legacy fallback — the pre-fix code returned "" here.
      check findRepoRoot("") == base
      check isAbsolute(findRepoRoot(""))

  test "AXIOM_ROOT injection wins over the walk":
    let injected = getTempDir() / ("ax_repo_root_env_" & $getCurrentProcessId())
    putEnv("AXIOM_ROOT", injected & "/")
    defer: putEnv("AXIOM_ROOT", "")
    check findRepoRoot() == injected
    check findRepoRoot(getTempDir()) == injected
