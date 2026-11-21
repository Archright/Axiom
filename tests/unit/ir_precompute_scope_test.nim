## VS-IR-PRECOMPUTE-SCOPE regression: fetch widening vs execution budget.
##
## ADR-0011 widens the FETCH scope so the VKD ratchet can see every kernel
## candidate; `--limit` is the proof-attempt budget
## (admissible_candidate_selection §5). Phase 10 therefore hands the executor
## the request-key intersection of the pool — never the whole pool — and a
## PROVIDED empty scope is terminal (it must not fall back to the wide
## selection, which would resurrect every sliced-away candidate).

import std/[os, sets, strutils, unittest]
import core/axiom_pragmas
import core/trusted/axiom_ir
import verification/batch_uap/ir_pipeline_runner
import verification/batch_uap/loop_driver

proc ve(modulePath, name: string): ValidatedIrEntry =
  ValidatedIrEntry(
    entry: RuntimeAxiomEntry(name: name, sourcePath: modulePath),
    funcDef: IRFuncDef(name: name))

let testCwd = getCurrentDir()

suite "IR precompute execution scope":
  test "intersection keeps pool order, not key order":
    let pool = @[ve("src/a.nim", "alpha"), ve("src/b.nim", "beta"),
                 ve("src/c.nim", "gamma"), ve("src/d.nim", "delta")]
    var keys = initHashSet[string]()
    keys.incl("src/d.nim::delta")
    keys.incl("src/a.nim::alpha")
    let scoped = scopeIrEntriesToRequiredKeys(pool, keys, testCwd)
    check scoped.len == 2
    check scoped[0].entry.name == "alpha"
    check scoped[1].entry.name == "delta"

  test "empty required set executes nothing":
    let pool = @[ve("src/a.nim", "alpha"), ve("src/b.nim", "beta")]
    check scopeIrEntriesToRequiredKeys(pool, initHashSet[string](), testCwd).len == 0

  test "the full key set is the identity slice":
    let pool = @[ve("src/a.nim", "alpha"), ve("src/b.nim", "beta")]
    var keys = initHashSet[string]()
    for v in pool:
      keys.incl(v.entry.sourcePath & "::" & v.entry.name)
    let scoped = scopeIrEntriesToRequiredKeys(pool, keys, testCwd)
    check scoped.len == pool.len
    for i in 0 ..< pool.len:
      check scoped[i].entry.name == pool[i].entry.name

  test "absolute sourcePath matches its normalized repo-relative key":
    ## `scopedIrResultForNode` normalizes the result module before comparing
    ## it against the node's module, so a kernel entry registered with an
    ## absolute line-info filename must still execute when the request names
    ## the repo-relative module.
    let absPath = testCwd / "src" / "core" / "x.nim"
    let pool = @[ve(absPath, "kernelUnit")]
    var keys = initHashSet[string]()
    keys.incl("src/core/x.nim::kernelUnit")
    check scopeIrEntriesToRequiredKeys(pool, keys, testCwd).len == 1

  test "absolute path outside the cwd normalizes fail-closed":
    let pool = @[ve("/elsewhere/src/core/x.nim", "kernelUnit")]
    var keys = initHashSet[string]()
    keys.incl("src/core/x.nim::kernelUnit")
    check scopeIrEntriesToRequiredKeys(pool, keys, "/repo").len == 0

  test "raw spelling matches the errclassObservationIndex key rule":
    ## The JRPC lane keys observations by the RAW sourcePath
    ## (`errclassResultKey`), so the slice must accept the raw spelling too.
    let pool = @[ve("subject/p.nim", "p_errclass_control_02")]
    var keys = initHashSet[string]()
    keys.incl("subject/p.nim::p_errclass_control_02")
    check scopeIrEntriesToRequiredKeys(pool, keys, testCwd).len == 1

  test "provided-empty scope is terminal, not a wide-selection fallback":
    ## Wiring guard: the pre-computed branch must gate on the PROVIDED flag.
    ## Gating on `.len > 0` re-runs the entire pool when the slice is empty.
    let src = readFile("src/verification/batch_uap/loop_driver.nim")
    check src.contains("elif preComputedIrProvided or preComputedIrResults.len > 0:")
    check not src.contains("elif preComputedIrResults.len > 0:")