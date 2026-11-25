## Gap 3 of #474 — the gate must cross-check the nimtry sidecar's own
## arithmetic instead of trusting the producer.
##
## nimtry_cli derives total/error/warning from one `violations` seq, so
## total == error + warning holds by construction *at the writer*. The sidecar
## is a plain gitignored file, so a hand-written or foreign payload lands on the
## consumer unverified; before this check a forged `{"total_violations": 0}`
## was accepted as a valid measurement. Every inconsistent payload must read as
## -1 (UNMEASURED), never as a count.

import std/[json, os, unittest]
import gate/runners/debt_integrity_gate

const SidecarRel = "data/nimtry_live_count.json"

proc writeSidecar(root, content: string) =
  createDir(root / "data")
  writeFile(root / SidecarRel, content)

proc consistent(total, errors, warnings: int): string =
  $(%*{"total_violations": total,
       "error_violations": errors,
       "warning_violations": warnings,
       "generated_at": "2026-01-01T00:00:00Z"})

let
  testRoot = getTempDir() / ("axiom_sidecar_consistency_" & $getCurrentProcessId())

suite "nimtry sidecar consistency (Gap 3 of #474)":

  setup:
    if dirExists(testRoot): removeDir(testRoot)
    createDir(testRoot / "data")

  teardown:
    if dirExists(testRoot): removeDir(testRoot)

  test "a self-consistent payload is admitted as its total":
    writeSidecar(testRoot, consistent(4371, 368, 4003))
    check countNimtryActiveViolations(testRoot) == 4371

  test "zero violations is admitted only when the parts are zero too":
    writeSidecar(testRoot, consistent(0, 0, 0))
    check countNimtryActiveViolations(testRoot) == 0

  test "counts that do not sum are UNMEASURED, not a count":
    writeSidecar(testRoot, consistent(4370, 1, 1))
    check countNimtryActiveViolations(testRoot) == -1

  test "parts missing entirely are UNMEASURED (the pre-fix forged zero)":
    writeSidecar(testRoot, """{"total_violations": 0}""")
    check countNimtryActiveViolations(testRoot) == -1

  test "one part missing is UNMEASURED":
    writeSidecar(testRoot, """{"total_violations": 5, "error_violations": 5}""")
    check countNimtryActiveViolations(testRoot) == -1

  test "non-integer parts are UNMEASURED":
    writeSidecar(testRoot, """{"total_violations": 5, "error_violations": "5", "warning_violations": 0}""")
    check countNimtryActiveViolations(testRoot) == -1

  test "a non-object payload is UNMEASURED":
    writeSidecar(testRoot, """[1, 2, 3]""")
    check countNimtryActiveViolations(testRoot) == -1

  test "a negative total is UNMEASURED":
    writeSidecar(testRoot, consistent(-1, -2, 1))
    check countNimtryActiveViolations(testRoot) == -1

  test "torn or invalid JSON is UNMEASURED":
    writeSidecar(testRoot, """{"total_violations": 4370, "error_viol""")
    check countNimtryActiveViolations(testRoot) == -1

  test "an absent sidecar is UNMEASURED (unchanged fail-closed contract)":
    check countNimtryActiveViolations(testRoot) == -1
