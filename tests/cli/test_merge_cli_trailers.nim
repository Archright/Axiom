{.push raises: [CatchableError].}

## Unit tests for merge_cli additions:
##
##   * trustSurfaceMatch — predicate reuse contract
##
## Network is never touched; the trust-surface classification is exercised
## through the pure func only.

import std/[osproc, os, strutils, unittest, options, streams]

import cli/merge_cli
import cli/cli_types

# ---------------------------------------------------------------------------
# trustSurfaceMatch — reuse contract (no logic copy)
# ---------------------------------------------------------------------------

suite "trustSurfaceMatch — bind-side classification":
  test "workflow file is a hit":
    let h = trustSurfaceMatch(".github/workflows/auto_merge.yml", "",
                              TrustSurfaceTombstones)
    check h.isSome
    check h.get.path == ".github/workflows/auto_merge.yml"

  test "docs file is clean":
    check trustSurfaceMatch("docs/evidence/anything.md", "",
                            TrustSurfaceTombstones).isNone

  test "rename source is also a hit":
    let h = trustSurfaceMatch("docs/moved.md", ".github/workflows/ci.yml",
                              TrustSurfaceTombstones)
    check h.isSome
    check h.get.renamedFrom == ".github/workflows/ci.yml"

{.pop.}
