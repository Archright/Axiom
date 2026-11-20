## tests/unit/test_hotspot_ranker.nim — DEBT#487 regression.
##
## The ranker must read the projection the generator actually emits. This
## suite builds a representative P1 projection through the projection's own
## generator (`generateProjections`), then asserts `rankModules` returns a
## non-empty queue. The pre-fix reader assumed a column the projection never
## produced, so every row failed the Status filter and the queue was empty.
##
## The fixture uses repo-relative module paths (the tool's documented
## "run from the repo root" contract), includes a Title with an escaped pipe
## (cell-shift regression), and a closed entry that must not enter the queue.

import std/[unittest, os, strutils]
import core/debt/debt_registry_projection
import hotspot_ranker

const RankerProjectionFixture = """{
  "entries": [
    {
      "id": "DEBT#9001",
      "severity": "critical",
      "category": "Regression/DEBT#487",
      "description": "open | title with a raw pipe and an escaped \\| pipe",
      "status": "open",
      "files": [
        "src/core/trusted/axiom_ir.nim",
        "src/core/trusted/contract_synthesis.nim"
      ]
    },
    {
      "id": "DEBT#9002",
      "severity": "low",
      "category": "Regression/DEBT#487",
      "description": "closed entry must not be ranked",
      "status": "closed",
      "files": ["src/core/trusted/evidence_capture.nim"]
    }
  ]
}"""

suite "DEBT#487: hotspot_ranker reads the declared P1 projection":

  test "non-empty ranking from a representative projection input":
    let projectionPath = getTempDir() / "ax_hotspot_ranker_debt487_projection.md"
    defer: removeFile(projectionPath)

    let md = generateProjections(RankerProjectionFixture).md
    check "| ID | Severity | Category | Title | Files | Status |" in md
    writeFile(projectionPath, md)

    let ranked = rankModules(projectionPath)

    # Two open references resolve to existing repo modules; the closed entry
    # contributes none. A positional reader yields 0 here.
    check ranked.len == 2

  test "the checked-in projection yields a non-empty ranking":
    ## The live artifact is the representative production input, so the
    ## contract test is not satisfied only by a synthetic fixture.
    let projectionPath = "docs/DEBT_REGISTRY.md"
    if fileExists(projectionPath):
      check rankModules(projectionPath).len > 0
    else:
      skip()