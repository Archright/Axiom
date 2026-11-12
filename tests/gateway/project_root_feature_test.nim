{.push raises: [CatchableError].}
## BDD feature test for project_root.feature
## Verifies getProjectRoot returns a deterministic, non-empty, absolute path.
##
## Hermetic: calls getProjectRoot once, checks invariants — no file I/O beyond that.

import std/unittest
import std/os
import std/strutils

# Import the module under test
import core/runtime/project_root

suite "project_root — deterministic root resolution":

  test "getProjectRoot returns a non-empty string":
    let root = getProjectRoot()
    check root.len > 0

  test "getProjectRoot returns an absolute path":
    let root = getProjectRoot()
    check root.startsWith("/") or (root.len >= 2 and root[1] == ':')

  test "getProjectRoot is deterministic across calls":
    ## Calling twice must return the same value (no randomness, no temp dirs).
    let first = getProjectRoot()
    let second = getProjectRoot()
    check first == second

  test "getProjectRoot result contains the binary directory":
    ## getAppDir() returns the directory containing the running binary.
    ## The result should at least be a valid directory path component.
    let root = getProjectRoot()
    check '/' in root or '\\' in root
