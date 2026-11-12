## Gate Manifest v2 — Unit Tests
## Verifies validation, path extraction, overlap detection, and collision finding.

import std/[tables, strutils, unittest]
import gate/gate_manifest_v2

suite "GateManifest validation":
  test "validateManifest passes for valid manifest with inputs and outputs":
    let m = manifest(
      id = "compile-gate",
      inputs = @[
        input("src/main.nim"),
        input("src/utils.nim")
      ],
      outputs = @[
        output("bin/ax")
      ],
      command = "nim c -o:bin/ax src/main.nim"
    )
    let errors = validateManifest(m)
    check errors.len == 0

  test "validateManifest catches empty ID":
    let m = manifest(
      id = "",
      inputs = @[input("src/main.nim")],
      outputs = @[output("bin/ax")]
    )
    let errors = validateManifest(m)
    check errors.len > 0
    check "Manifest ID is empty" in errors[0]

  test "validateManifest catches duplicate input paths":
    let m = manifest(
      id = "dup-input-gate",
      inputs = @[
        input("src/main.nim"),
        input("src/main.nim")
      ],
      outputs = @[output("bin/ax")]
    )
    let errors = validateManifest(m)
    var foundDup = false
    for e in errors:
      if "Duplicate input path" in e:
        foundDup = true
    check foundDup

  test "validateManifest catches duplicate output paths":
    let m = manifest(
      id = "dup-output-gate",
      inputs = @[input("src/main.nim")],
      outputs = @[
        output("bin/ax"),
        output("bin/ax")
      ]
    )
    let errors = validateManifest(m)
    var foundDup = false
    for e in errors:
      if "Duplicate output path" in e:
        foundDup = true
    check foundDup

  test "validateManifest catches input-output overlap":
    let m = manifest(
      id = "overlap-gate",
      inputs = @[input("build/data.bin")],
      outputs = @[output("build/data.bin")]
    )
    let errors = validateManifest(m)
    var foundOverlap = false
    for e in errors:
      if "inputs and outputs" in e:
        foundOverlap = true
    check foundOverlap

  test "validateManifest passes for manifest with no inputs or outputs":
    let m = manifest(id = "passthrough-gate")
    let errors = validateManifest(m)
    check errors.len == 0

suite "GateManifest path extraction":
  test "outputPaths extracts all output paths":
    let m = manifest(
      id = "test",
      outputs = @[
        output("bin/ax"),
        output("build/report.json")
      ]
    )
    let paths = outputPaths(m)
    check paths.len == 2
    check "bin/ax" in paths
    check "build/report.json" in paths

  test "inputPaths extracts all input paths":
    let m = manifest(
      id = "test",
      inputs = @[
        input("src/a.nim"),
        input("src/b.nim"),
        input("data/config.json")
      ]
    )
    let paths = inputPaths(m)
    check paths.len == 3
    check "src/a.nim" in paths
    check "src/b.nim" in paths
    check "data/config.json" in paths

  test "outputPaths returns empty for manifest with no outputs":
    let m = manifest(id = "no-outputs")
    let paths = outputPaths(m)
    check paths.len == 0

suite "GateManifest overlap detection":
  test "hasOutputOverlap detects shared output path":
    let a = manifest(
      id = "gate-a",
      outputs = @[output("bin/shared")]
    )
    let b = manifest(
      id = "gate-b",
      outputs = @[output("bin/shared")]
    )
    check hasOutputOverlap(a, b) == true

  test "hasOutputOverlap returns false for disjoint outputs":
    let a = manifest(
      id = "gate-a",
      outputs = @[output("bin/a")]
    )
    let b = manifest(
      id = "gate-b",
      outputs = @[output("bin/b")]
    )
    check hasOutputOverlap(a, b) == false

  test "hasInputOutputDependency detects producer-consumer link":
    let producer = manifest(
      id = "compile",
      outputs = @[output("build/types.nim")]
    )
    let consumer = manifest(
      id = "lint",
      inputs = @[input("build/types.nim")]
    )
    check hasInputOutputDependency(producer, consumer) == true

  test "hasInputOutputDependency returns false when no link":
    let a = manifest(
      id = "gate-a",
      outputs = @[output("bin/a")]
    )
    let b = manifest(
      id = "gate-b",
      inputs = @[input("src/b.nim")]
    )
    check hasInputOutputDependency(a, b) == false

suite "GateManifest edge and collision detection":
  test "findOutputCollisions finds unordered output collision":
    let a = manifest(
      id = "gate-a",
      outputs = @[output("bin/shared")]
    )
    let b = manifest(
      id = "gate-b",
      outputs = @[output("bin/shared")]
    )
    var afterEdges = initTable[string, seq[string]]()
    # No edges between a and b → collision
    let collisions = findOutputCollisions(@[a, b], afterEdges)
    check collisions.len >= 1
    check "gate-a" in collisions[0]
    check "gate-b" in collisions[0]

  test "findOutputCollisions returns empty when ordering edge exists":
    let a = manifest(
      id = "gate-a",
      outputs = @[output("bin/shared")]
    )
    let b = manifest(
      id = "gate-b",
      outputs = @[output("bin/shared")]
    )
    var afterEdges = initTable[string, seq[string]]()
    afterEdges["gate-b"] = @["gate-a"]  # b depends on a → ordered
    let collisions = findOutputCollisions(@[a, b], afterEdges)
    check collisions.len == 0

  test "findMissingEdges detects missing dependency edge":
    let producer = manifest(
      id = "compile",
      outputs = @[output("build/types.nim")]
    )
    let consumer = manifest(
      id = "lint",
      inputs = @[input("build/types.nim")]
    )
    var afterEdges = initTable[string, seq[string]]()
    # consumer does NOT declare compile in after → missing edge
    let missing = findMissingEdges(@[producer, consumer], afterEdges)
    check missing.len >= 1
    check "compile" in missing[0]
    check "lint" in missing[0]

  test "findMissingEdges returns empty when edge is declared":
    let producer = manifest(
      id = "compile",
      outputs = @[output("build/types.nim")]
    )
    let consumer = manifest(
      id = "lint",
      inputs = @[input("build/types.nim")]
    )
    var afterEdges = initTable[string, seq[string]]()
    afterEdges["lint"] = @["compile"]
    let missing = findMissingEdges(@[producer, consumer], afterEdges)
    check missing.len == 0

suite "GateManifest constructor helpers":
  test "input helper sets optional flag":
    let req = input("src/main.nim")
    check req.optional == false
    let opt = input("data/optional.json", optional = true)
    check opt.optional == true

  test "output helper sets fixedHash":
    let floating = output("bin/test")
    check floating.fixedHash.len == 0
    let fixed = output("deps/lib.nar", fixedHash = "abc123sha")
    check fixed.fixedHash == "abc123sha"

  test "manifest helper wires env variables":
    let m = manifest(
      id = "env-gate",
      env = @[("NIM_CACHE", "/tmp/nimcache"), ("DEBUG", "1")]
    )
    check m.env.len == 2
    check m.env[0] == ("NIM_CACHE", "/tmp/nimcache")
    check m.env[1] == ("DEBUG", "1")
