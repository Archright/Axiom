# test_axiom_probe_unknown_not_empty.nim - #367 regression guard.
#
# The canonical `#print axioms` probe used to discard the Lean exit status and
# parse its (possibly empty) stdout, so an unobserved axiom set became the empty
# axiom set and could be certified. UNKNOWN is not EMPTY: only a probe that ran
# to completion may contribute an axiom set, and that set may legitimately be
# empty (a theorem that depends on no axioms reports none).
#
# Execution: nim c --hints:off -r tests/unit/test_axiom_probe_unknown_not_empty.nim

import std/[strutils, unittest]

import core/results
import verification/obligation/canonical_verification

suite "axiom probe outcome (#367)":

  test "a failed probe is an error, never an empty axiom set":
    let r = axiomProbeOutcome(1, "")
    check r.isErr
    check r.error.contains("UNKNOWN")
    check r.error.contains("exit 1")

  test "a launch failure or timeout (-1) is an error":
    let r = axiomProbeOutcome(-1, "")
    check r.isErr
    check r.error.contains("exit -1")

  test "a completed probe that observed no axioms is EMPTY, and that is legal":
    let r = axiomProbeOutcome(0, "'foo' does not depend on any axioms")
    check r.isOk
    check r.get.len == 0

  test "a completed probe reports the axioms it observed":
    let r = axiomProbeOutcome(0, "'t' depends on axioms: [propext, Quot.sound]")
    check r.isOk
    check r.get == @["propext", "Quot.sound"]

  test "the failure text names the two distinct facts":
    check axiomProbeOutcome(2, "").error.contains("UNKNOWN, not empty")
