import std/[unittest, os, osproc]
import ../../src/core/types/results
import ../../src/core/judge/lean_replay

## Fail-closed sorry gate tests for runLeanReplay (docs/spec/lean_sorry_gate.md).
##
## The replay now parses the collected `#print axioms` section and rejects the
## verdict (isValid=false) when it lists `sorryAx`/`Lean.sorryAx` or any axiom
## outside the builtin allowlist {Classical.choice, Quot.sound, propext, funext}.

let hasLean = (execCmdEx("which lean 2>/dev/null").exitCode == 0)

suite "Lean replay sorry gate (fail-closed)":
  test "clean provable theorem is accepted (isValid=true)":
    if hasLean:
      let src = """theorem sorry_gate_clean : 1 + 1 = 2 := by
  decide
"""
      let res = runLeanReplay("clean_note", src)
      check res.isOk
      check res.get().isValid == true
    else:
      echo "SKIP: lean not available"

  test "theorem proved with sorry is rejected (isValid=false)":
    if hasLean:
      let src = """theorem sorry_gate_vacuity : 2 + 2 = 5 := by
  sorry
"""
      let res = runLeanReplay("sorry_note", src)
      check res.isOk
      check res.get().isValid == false
    else:
      echo "SKIP: lean not available"

  test "unit: sorryGateValid rejects any non-allowlisted axiom":
    ## Pure-function tests do not require Lean at runtime.
    check sorryGateValid(false, @[]) == true               # section absent -> not enforced
    check sorryGateValid(true, @[]) == true                # present, no axioms -> valid
    check sorryGateValid(true, @["propext", "Quot.sound"]) == true
    check sorryGateValid(true, @["Classical.choice"]) == true
    check sorryGateValid(true, @["funext"]) == true
    check sorryGateValid(true, @["sorryAx"]) == false
    check sorryGateValid(true, @["Lean.sorryAx"]) == false
    check sorryGateValid(true, @["Some.Other.axiom"]) == false
    check sorryGateValid(true, @["propext", "sorryAx"]) == false

  test "unit: parsePrintedAxioms extracts the bracketed dependency list":
    let (present, axioms) = parsePrintedAxioms("'x' depends on axioms: [propext, Classical.choice, Quot.sound]")
    check present == true
    check axioms == @["propext", "Classical.choice", "Quot.sound"]
    let (presentNoAx, noAxioms) = parsePrintedAxioms("'x' does not depend on any axioms")
    check presentNoAx == true
    check noAxioms.len == 0
    let (absent, empty) = parsePrintedAxioms("just some output\nno axioms section")
    check absent == false
    check empty.len == 0
