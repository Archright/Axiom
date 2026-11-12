## Unit test for postfix export-marker handling in frontier selection.
##
## Regression for the WP4-b crash where the eligibility gate in
## `axiom_engine.nim` stripped two trailing characters (`bare[0 ..< bare.len-2]`)
## from a function name, raising `value out of range: -1` when it met a lone
## `"*"` operator-symbol node (e.g. `stew/interval_set.nim::*` from an exported
## operator override ``func `*`*[...]``) during a full-frontier eligibility pass.
##
## The fix extracts a single guarded canonical strip helper
## (`stripPostfixExportMarker`) that:
##   - strips exactly one trailing `*` (matching `candidate_eligibility.nim`.
##     `admissibility.nim`, `ir_pipeline_runner.nim:1122`), and
##   - leaves a lone `"*"` (a real operator name) and an empty string unchanged,
##     so it never raises a range defect.
##
## This distinguishes "export marker removal" from "real operator name".

import std/[unittest, tables]
import core/sorter/sorter_core
import cli/frontier_selection

suite "stripPostfixExportMarker":

  # -----------------------------------------------------------------------
  # Plain identifier / export-marker cases
  # -----------------------------------------------------------------------

  test "plain name unchanged":
    check stripPostfixExportMarker("name") == "name"

  test "single trailing export marker stripped":
    check stripPostfixExportMarker("foo*") == "foo"
    check stripPostfixExportMarker("decodedLength*") == "decodedLength"
    check stripPostfixExportMarker("encodedLength*") == "encodedLength"

  # -----------------------------------------------------------------------
  # Export marker must strip exactly ONE character (not two)
  # -----------------------------------------------------------------------

  test "single marker strips exactly one char (not two)":
    ## `name*` (len 5) must yield `name`, never `nam` (the old `-2` bug).
    check stripPostfixExportMarker("name*") == "name"
    check stripPostfixExportMarker("ab*") == "ab"

  # -----------------------------------------------------------------------
  # Operator-symbol names (backtick-quoted) + export marker
  # -----------------------------------------------------------------------

  test "backtick operator with export marker -> operator only":
    check stripPostfixExportMarker("`+`*") == "`+`"
    check stripPostfixExportMarker("`*`*") == "`*`"
    check stripPostfixExportMarker("`==`*") == "`==`"

  test "lone operator name (no export marker) unchanged":
    check stripPostfixExportMarker("*") == "*"
    check stripPostfixExportMarker("+") == "+"

  # -----------------------------------------------------------------------
  # Edge cases the old slicing raised on — must be safe (no defect)
  # -----------------------------------------------------------------------

  test "lone '*': no crash, returned unchanged":
    ## The WP4-b crash input: `fnName == "*"`. Old code did
    ## `bare[0 ..< bare.len-2]` = `bare[0 ..< -1]` -> RangeDefect.
    ## New code must return "*" safely.
    check stripPostfixExportMarker("*") == "*"

  test "empty string: no crash, returned unchanged":
    check stripPostfixExportMarker("") == ""

  # -----------------------------------------------------------------------
  # Integration: selectFrontierNodes eligibility gate must not crash on "*"
  # -----------------------------------------------------------------------

  test "full-frontier eligibility gate survives a lone '*' node":
    ## A topology like `interval_set.nim::*` produces nodeFnIdx entry "*".
    ## When --target is not found, selectFrontierNodes iterates the full
    ## frontier and calls isEligible(fnName) for every node. A real registry
    ## lookup for "*" misses (no such entry), so the node must be safely
    ## excluded without any range defect.
    let frontier = @[sorterNodeId("opStar"), sorterNodeId("good")]
    var nodeFnIdx = initTable[string, string]()
    nodeFnIdx["opStar"] = "*"
    nodeFnIdx["good"] = "decodedLength"
    let nodeModuleIdx = initTable[string, string]()

    # isEligible mirrors the engine closure: strip marker, then registry
    # check (we model the registry as only containing "decodedLength").
    let isEligible = proc(fnName, modulePath: string): bool {.raises: [].} =
      let bare = stripPostfixExportMarker(fnName)
      bare == "decodedLength"

    # --target=unknown is not found, so selectFrontierNodes falls back to the
    # full frontier and calls isEligible on every node (incl. the "*" one).
    let result = selectFrontierNodes(frontier, "unknownTarget", nodeFnIdx,
      nodeModuleIdx, 0, isEligible)

    # No crash; only the decodedLength node survives eligibility.
    check result.len == 1
    check sorterNodeIdString(result[0]) == "good"

  test "explicitly-targeted '*' returns unchanged and is safely excluded":
    ## A user targeting the operator itself gets the operator name back; with
    ## no such registry entry it is not a proof candidate, so it is excluded
    ## (not crashed on).
    let frontier = @[sorterNodeId("opStar")]
    var nodeFnIdx = initTable[string, string]()
    nodeFnIdx["opStar"] = "*"
    let nodeModuleIdx = initTable[string, string]()
    let isEligible = proc(fnName, modulePath: string): bool {.raises: [].} =
      false  # "*" is not a registry proof candidate
    let result = selectFrontierNodes(frontier, "*", nodeFnIdx, nodeModuleIdx, 0, isEligible)
    check result.len == 0
