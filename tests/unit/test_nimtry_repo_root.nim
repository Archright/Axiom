## The engine's repository-root resolution must not depend on the process CWD.
##
## Regression for the two `getCurrentDir()` call sites in `nimtry_cli` that made
## the scanned tree, the live-count sidecar path and the stripped path identity
## depend on where the binary was invoked from: the same input produced two
## different measurements. `resolveRepoRoot()` anchors on the `.axiom_root` file
## (or `AXIOM_ROOT`), so moving the CWD cannot move the root.

import std/[os, unittest]
import gate/nimtry/nimtry_cli

proc anchoredRoot(): string =
  ## Expected root derived from this source file, so the expectation does not
  ## depend on where the test binary happens to live.
  var d = currentSourcePath().parentDir
  while d.len > 1:
    if fileExists(d / ".axiom_root"):
      return d
    let up = d.parentDir
    if up == d:
      break
    d = up
  ""

suite "nimtry repo root resolution (CWD independence)":

  test "resolveRepoRoot anchors on .axiom_root":
    let expected = anchoredRoot()
    check expected.len > 0
    check resolveRepoRoot() == expected

  test "AXIOM_ROOT injection wins over the anchor walk":
    let tmp = getTempDir() / ("axiom_root_inject_" & $getCurrentProcessId())
    createDir(tmp)
    putEnv("AXIOM_ROOT", tmp)
    try:
      check resolveRepoRoot() == tmp
    finally:
      delEnv("AXIOM_ROOT")
      removeDir(tmp)

  test "moving the CWD does not move the root":
    let before = resolveRepoRoot()
    check before.len > 0
    let elsewhere = getTempDir() / ("axiom_cwd_" & $getCurrentProcessId())
    createDir(elsewhere)
    let saved = getCurrentDir()
    try:
      setCurrentDir(elsewhere)
      check resolveRepoRoot() == before
    finally:
      setCurrentDir(saved)
      removeDir(elsewhere)

  test "the default fallback is not a CWD-relative dot":
    # A "." default would silently make relative paths that leak into the
    # sidecar; the resolution must yield an absolute root.
    check resolveRepoRoot().isAbsolute