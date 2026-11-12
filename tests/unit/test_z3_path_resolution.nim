## Z3 binary path resolution — pure, spawn-free, and independent of whether a
## Z3 binary exists on the machine running it.
##
## `resolveZ3Path()` (src/core/types/z3_solver_config.nim) is the SSOT for
## locating the Z3 executable. Consumers must ask it instead of hardcoding a
## developer's absolute path. These tests pin that contract, including the
## fall-through behaviour that keeps a stale `AXIOM_Z3_PATH` from being handed
## to the solver as if it were usable.

import std/[unittest, os]
import core/trusted/env_types
import core/types/z3_solver_config

suite "Z3 path resolution (pure — no solver spawn)":
  test "never resolves to an empty path":
    # The chain ends in a bare `"z3"` PATH lookup, so the result is always a
    # non-empty candidate string — callers never have to defend against "".
    check resolveZ3Path().len > 0

  test "AXIOM_Z3_PATH wins when it names an existing file":
    let saved = getAxiomEnv(evZ3Path)
    defer: setAxiomEnv(evZ3Path, saved)
    let sentinel = getAppFilename()
    check fileExists(sentinel)
    setAxiomEnv(evZ3Path, sentinel)
    check resolveZ3Path() == sentinel

  test "a stale AXIOM_Z3_PATH is not returned to the caller":
    # The core anti-hardcode property: an AXIOM_Z3_PATH pointing at a path that
    # does not exist must fall through the priority chain, not be forwarded to
    # the solver. Resolution and launchability stay separate decisions.
    let saved = getAxiomEnv(evZ3Path)
    defer: setAxiomEnv(evZ3Path, saved)
    let stale = "/nonexistent/axiom-z3-sentinel"
    setAxiomEnv(evZ3Path, stale)
    let resolved = resolveZ3Path()
    check resolved != stale
    check resolved.len > 0
