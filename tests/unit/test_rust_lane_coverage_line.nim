## Issue #219 — the rust lane's ADDRESSABILITY log line (log channel only).
##
## The PRODUCER half of this feature (llbcFunDeclCoverage: the document's
## fun_decl count, the addressable names, the CLOSED-label skip tally) is
## pinned next to the walk that produces it — the impl-identity suite of
## `tests/unit/test_llbc_to_canonical.nim`, where `llbcFunDeclNamePaths` is
## already tested against the same fixture. This file pins the other half: the
## ONE line the lane prints (`rustLaneCoverageLine`) on its EXISTING log
## channel (`[AXIOM][rust-lane] …` → ProofReport.logLines → stderr).
##
## Why this is its own file: no existing unit suite imports `cli/rust_lane_cli`
## for log formatting (`test_lane_module_resolution.nim` covers module binding,
## `test_merge_cli.nim` covers admission), and the end-to-end stderr assertion
## lives in `tests/gateway/rust_lane_cli_acceptance_test.nim`, which needs the
## pinned charon and skips without it. This suite is the fast-lane coverage of
## the labels themselves.
##
## WHAT THE LINE MUST NOT DO: it does not re-print the raw fun_decl count (the
## run-coverage line's `total=` owns that number) and it does not reuse the
## word `addressable` (that landed word is the SELECTED candidate set, post
## `--target`). `named` and `skipped` are the two facts only this axis carries,
## and `named + skipped == coverage total` closes by construction.
##
## Runs standalone (not in the gateway feature glob):
##   nim c -r --hints:off tests/unit/test_rust_lane_coverage_line.nim

import std/[json, os, strutils, unittest]

import cli/rust_lane_cli
import verification/llbc_to_canonical

const ImplFixturePath = currentSourcePath().parentDir().parentDir() /
    "fixtures" / "rust" / "axiom_impl_probe" / "axiom_impl_probe.llbc"

proc bucketTexts(cover: LlbcFunDeclCoverage): seq[string] =
  ## The ledger as printable buckets, in the producer's fixed vocabulary order.
  for s in cover.skippedByReason:
    result.add(s.reason & "=" & $s.count)

suite "issue #219 — the lane's printed addressability line":

  let cover = llbcFunDeclCoverage(parseFile(ImplFixturePath))
  let line = rustLaneCoverageLine(cover)

  test "presence: ONE line on the lane log channel, verbatim — the two " &
      "numbers plus the reason breakdown":
    check line.startsWith("[AXIOM][rust-lane] ")
    check bucketTexts(cover) == @["impl-owner-unaddressable=1"]
    check line == "[AXIOM][rust-lane] addressability: named=7 skipped=1 " &
      "(impl-owner-unaddressable=1)"

  test "arithmetic: skipped is DERIVED from the two counts, never reported " &
      "independently":
    check line.contains("named=" & $cover.names.len & " skipped=" &
      $(cover.funDecls - cover.names.len))
    check cover.names.len + (cover.funDecls - cover.names.len) == cover.funDecls

  test "no skips → no empty parenthetical; a measured but empty document " &
      "still reports a closing zero ledger":
    let clean = LlbcFunDeclCoverage(measured: true, funDecls: 1,
      names: @[LlbcFunDeclNamePath(fullName: "a::b", lastSegment: "b")])
    check rustLaneCoverageLine(clean) ==
      "[AXIOM][rust-lane] addressability: named=1 skipped=0"
    let empty = LlbcFunDeclCoverage(measured: true, funDecls: 0)
    check rustLaneCoverageLine(empty) ==
      "[AXIOM][rust-lane] addressability: named=0 skipped=0"

  test "the addressability axis stays apart from the run-coverage line: no " &
      "re-printed total, no reused `addressable`":
    check line.contains("addressability: named=")
    check not line.contains("fun_decls=")    # `coverage: total=` owns that
    # the run-coverage key is spelled " addressable=" (a space before it);
    # the reason label `unaddressable=` must not trip this guard
    check not line.contains(" addressable=") # that word is the SELECTED set
    check not line.contains("attempted=")
    check not line.contains("coverage:")