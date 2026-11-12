import std/[unittest, strutils, os]

suite "Auto-Injected Axiom Hints":
  test "emptyTimeoutDiagnosis has depth >= 0 hint":
    let source = readFile("src/core/diagnostics_engine.nim")
    let procIdx = source.find("func emptyTimeoutDiagnosis*()")
    check procIdx > 0
    let preceding = source[max(0, procIdx - 300) ..< procIdx]
    check preceding.contains("@axiom-hint: lean=\"depth >= 0\"")

  test "sTrue has depth >= 0 hint":
    let source = readFile("src/core/symbolic_engine.nim")
    let procIdx = source.find("func sTrue*()")
    check procIdx > 0
    let preceding = source[max(0, procIdx - 300) ..< procIdx]
    check preceding.contains("@axiom-hint: lean=\"depth >= 0\"")

  test "sFalse has depth >= 0 hint":
    let source = readFile("src/core/symbolic_engine.nim")
    let procIdx = source.find("func sFalse*()")
    check procIdx > 0
    let preceding = source[max(0, procIdx - 300) ..< procIdx]
    check preceding.contains("@axiom-hint: lean=\"depth >= 0\"")
