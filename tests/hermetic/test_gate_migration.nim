{.push raises: [CatchableError].}

## Gate Migration Test — Wave 7F-2
##
## Tests that GateManifest v2 types can represent
## existing gate configurations from gate_manifest.json.

import std/[unittest, tables]
import gate/gate_manifest_v2

{.push warning[BareExcept]:off.}
suite "Gate Manifest V2":

  test "Input/Output constructors work":
    let inp = input("src/core/**/*.nim")
    check inp.path == "src/core/**/*.nim"
    check inp.kind == akFile

    let outp = output("bin/gate_runner")
    check outp.path == "bin/gate_runner"
    check outp.kind == akFile

  test "Manifest validation passes for valid manifest":
    let m = manifest("test-gate",
      inputs = @[input("src/**/*.nim"), input("config/*.toml")],
      outputs = @[output("bin/test-gate")])
    let errors = validateManifest(m)
    check errors.len == 0

  test "Manifest validation catches empty gate ID":
    let m = manifest("",
      inputs = @[input("src/**/*.nim")],
      outputs = @[output("bin/test")])
    let errors = validateManifest(m)
    check errors.len > 0

  test "Output collision detection":
    let m1 = manifest("gate-a",
      inputs = @[input("src/a.nim")],
      outputs = @[output("bin/shared")])
    let m2 = manifest("gate-b",
      inputs = @[input("src/b.nim")],
      outputs = @[output("bin/shared")])
    let emptyEdges = initTable[string, seq[string]]()
    let collisions = findOutputCollisions(@[m1, m2], emptyEdges)
    check collisions.len > 0

  test "No collision for different outputs":
    let m1 = manifest("gate-a",
      inputs = @[input("src/a.nim")],
      outputs = @[output("bin/a")])
    let m2 = manifest("gate-b",
      inputs = @[input("src/b.nim")],
      outputs = @[output("bin/b")])
    let emptyEdges = initTable[string, seq[string]]()
    let collisions = findOutputCollisions(@[m1, m2], emptyEdges)
    check collisions.len == 0

  test "Missing edges detection":
    let producer = manifest("gate-build",
      inputs = @[input("src/main.nim")],
      outputs = @[output("bin/built-by-other")])
    let consumer = manifest("gate-test",
      inputs = @[input("bin/built-by-other")],
      outputs = @[output("bin/result")])
    let emptyEdges = initTable[string, seq[string]]()
    let missing = findMissingEdges(@[producer, consumer], emptyEdges)
    check missing.len > 0

  test "Valid edges suppress missing-edge detection":
    let producer = manifest("gate-build",
      inputs = @[input("src/main.nim")],
      outputs = @[output("bin/built-by-other")])
    let consumer = manifest("gate-test",
      inputs = @[input("bin/built-by-other")],
      outputs = @[output("bin/result")])
    var edges: Table[string, seq[string]]
    edges["gate-test"] = @["gate-build"]
    let missing = findMissingEdges(@[producer, consumer], edges)
    check missing.len == 0

  test "Input/Output overlap detection via validation":
    let m = manifest("bad-gate",
      inputs = @[input("shared.txt")],
      outputs = @[output("shared.txt")])
    let errors = validateManifest(m)
    check errors.len > 0

{.pop.}
