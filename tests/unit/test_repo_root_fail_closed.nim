## findRepoRoot fail-closed exhaustion — DEBT#550 regression tests.
##
## SSOT: src/core/utils/repo_root.nim (findRepoRoot contract — anchor walk +
## exhaustion semantics) + data/debt_registry.json DEBT#550 (the measured
## defect: a binary outside the repo walks getAppDir() up to "/" where
## `parentDir("/") == ""`, and the `"" / ".axiom_root"` probe degenerates to a
## CWD-relative match, returning "" as the "root" — report-side VKD admission
## collapses) + Q-013 (docs/spec/nim_2_2_10_stdlib_quirks.md: parentDir("/")
## returns "" and `"" / anchor` probes the CWD; Nim stdlib docs:
## `joinPath("", "lib") == "lib"`).
##
## Measured here:
##   1. A binary compiled OUTSIDE the repo — the make test-fast layout
##      (-o:/tmp/opencode/ax-utNN, run with CWD = repo root) — resolves the
##      repo root via findRepoRoot()'s default getAppDir() walk, never "".
##   2. An explicit tree-external startDir with repo CWD (the exact DEBT#550
##      degenerate path) resolves the CWD root, not "".
##   3. Exhaustion with no anchor anywhere keeps the documented legacy
##      one-level-up fallback (behavior preservation).
##   4. AXIOM_ROOT still wins, with trailing-slash normalization.

import std/[os, unittest]
import ../../src/core/utils/repo_root

suite "findRepoRoot — DEBT#550 fail-closed exhaustion":

  test "tree-external binary (default getAppDir walk) resolves the repo root, never \"\"":
    # RED under the defect when the binary lives outside the repo (make
    # test-fast's -o:/tmp/opencode layout): the walk degenerates at "" and
    # returns "". Green when the walk resolves the CWD (repo) root.
    let orig = getEnv("AXIOM_ROOT", "")
    if orig.len > 0: delEnv("AXIOM_ROOT")
    defer:
      if orig.len > 0: putEnv("AXIOM_ROOT", orig)
    let root = findRepoRoot()  # default startDir = getAppDir()
    check root.len > 0
    check root == repoRootConst()

  test "explicit tree-external startDir + repo CWD resolves the CWD root (DEBT#550 degenerate path)":
    let orig = getEnv("AXIOM_ROOT", "")
    if orig.len > 0: delEnv("AXIOM_ROOT")
    defer:
      if orig.len > 0: putEnv("AXIOM_ROOT", orig)
    let here = getCurrentDir()
    defer: setCurrentDir(here)
    # The warm-journal test-harness scenario: binary/startDir outside the
    # repo, CWD pinned to the repo root (which carries .axiom_root).
    setCurrentDir(repoRootConst())
    let startDir = getTempDir() / "ax_debt550_no_anchor_start"
    createDir(startDir)
    let root = findRepoRoot(startDir)
    check root.len > 0
    check root == repoRootConst()

  test "exhaustion with no anchor anywhere keeps the legacy one-level-up fallback":
    let orig = getEnv("AXIOM_ROOT", "")
    if orig.len > 0: delEnv("AXIOM_ROOT")
    defer:
      if orig.len > 0: putEnv("AXIOM_ROOT", orig)
    let here = getCurrentDir()
    defer: setCurrentDir(here)
    # CWD carries no anchor either: the walk, the CWD check, and the fallback
    # are all exercised — the documented "one level up from startDir" wins.
    let noAnchorCwd = getTempDir() / "ax_debt550_no_anchor_cwd"
    createDir(noAnchorCwd)
    setCurrentDir(noAnchorCwd)
    let startDir = getTempDir() / "ax_debt550_no_anchor_start"
    createDir(startDir)
    check findRepoRoot(startDir) == parentDir(startDir)

  test "AXIOM_ROOT wins, trailing slashes normalized":
    let orig = getEnv("AXIOM_ROOT", "")
    defer:
      if orig.len > 0: putEnv("AXIOM_ROOT", orig)
      else: delEnv("AXIOM_ROOT")
    putEnv("AXIOM_ROOT", "/opt/axiom-debt550///")
    check findRepoRoot("/definitely/not/a/tree") == "/opt/axiom-debt550"
