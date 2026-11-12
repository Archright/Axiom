import std/[sequtils, unittest, os, strutils]

import core/topology/topology_engine
import cli/wf_planning

suite "topology operator declarations":
  test "backtick-delimited Nim operators are proof targets":
    let symbols = scanTopologySource("core/operator_sample.nim", """
func `%`*(value: int): int =
  value

proc `$`*(value: int): string =
  $value

template `??`*[T](value: T): T =
  value
""")
    let names = symbols.mapIt(it.functionName)
    check "%" in names
    check "$" in names
    check "??" in names

  test "operator nodes without semantic hints do not get metadata-only SMT":
    let formula = buildAxProofExpectedFormula("core/results.nim::??", 0, 1)
    check formula == ""

suite "Hard Gate (Anti-Tautology Topology)":
  test "updateBoundaryKinds processes functions without crash":
    ## Uses real temp file so parseNimRes works with compiler config.
    let tmpFile = getTempDir() / "axiom_test_topology_$$$.nim"
    tmpFile.writeFile("""func trivialFunc(s: string): int =
  s.len

func meaningfulFunc(x: int): int =
  if x > 0: x else: 0
""")
    try:
      var symbols = scanTopologySource(tmpFile, readFile(tmpFile))
      updateBoundaryKinds(symbols, readFile(tmpFile))
      check symbols.len == 2
      let names = symbols.mapIt(it.functionName)
      check "trivialFunc" in names
      check "meaningfulFunc" in names
    finally:
      if fileExists(tmpFile): removeFile(tmpFile)

  test "buildTopologyAnalysis produces verification queue":
    let tmpFile = getTempDir() / "axiom_test_topology2_$$$.nim"
    tmpFile.writeFile("""func trivialFunc(s: string): int =
  s.len

func meaningfulFunc(x: int): int =
  if x > 0: x else: 0
""")
    try:
      var symbols = scanTopologySource(tmpFile, readFile(tmpFile))
      updateBoundaryKinds(symbols, readFile(tmpFile))
      let analysis = buildTopologyAnalysis(symbols)
      check analysis.verificationQueue.len > 0
    finally:
      if fileExists(tmpFile): removeFile(tmpFile)
