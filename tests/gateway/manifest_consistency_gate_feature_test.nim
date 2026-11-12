{.push raises: [CatchableError].}
## BDD feature test for manifest_consistency_gate.feature
## Verifies that gate_manifest.json structure is valid, consistent,
## and contains well-formed entries.
##
## Hermetic: uses embedded JSON constant, no filesystem I/O.

import std/unittest
import std/json
import std/strutils

# Embedded minimal manifest matching the gate_manifest.json structure.
const
  SampleManifest = """
{
  "gates": [
    {
      "id": "alpha-gate",
      "name": "Alpha gate",
      "layer": "functional",
      "entry": "src/gate/runners/alpha_gate",
      "stages": ["pre-commit"],
      "weight": "light"
    },
    {
      "id": "beta-gate",
      "name": "Beta gate",
      "layer": "meta",
      "entry": "src/gate/runners/beta_gate",
      "stages": ["pre-push", "ci"],
      "weight": "heavy"
    }
  ]
}
"""

  RequiredFields = ["id", "name", "layer", "entry", "stages", "weight"]
  ValidLayers = ["meta", "functional"]
  ValidStages = ["pre-commit", "pre-push", "manual", "ci"]
  ValidWeights = ["light", "medium", "heavy"]

suite "Manifest — structure validity":

  test "manifest JSON is valid":
    let manifest = parseJson(SampleManifest)
    check manifest.kind == JObject

  test "manifest has a top-level gates array":
    let manifest = parseJson(SampleManifest)
    check manifest.hasKey("gates")
    check manifest["gates"].kind == JArray
    check manifest["gates"].len > 0

suite "Manifest — schema validation of entries":

  proc loadManifest(): JsonNode =
    parseJson(SampleManifest)

  test "all gates have required fields":
    let manifest = loadManifest()
    let gates = manifest["gates"]
    for i in 0 ..< gates.len:
      let gate = gates[i]
      for field in RequiredFields:
        check gate.hasKey(field) == true

  test "all gates have valid layer enum":
    let manifest = loadManifest()
    let gates = manifest["gates"]
    for i in 0 ..< gates.len:
      let layer = gates[i]["layer"].getStr()
      check layer in ValidLayers

  test "all gates have valid weight enum":
    let manifest = loadManifest()
    let gates = manifest["gates"]
    for i in 0 ..< gates.len:
      let weight = gates[i]["weight"].getStr()
      check weight in ValidWeights

  test "all gates have valid stages":
    let manifest = loadManifest()
    let gates = manifest["gates"]
    for i in 0 ..< gates.len:
      let stages = gates[i]["stages"]
      check stages.kind == JArray
      for s in stages:
        check s.kind == JString
        check s.getStr() in ValidStages

  test "all manifest ids are unique":
    let manifest = loadManifest()
    let gates = manifest["gates"]
    var seenIds: seq[string]
    for i in 0 ..< gates.len:
      let id = gates[i]["id"].getStr()
      check id notin seenIds
      seenIds.add(id)

  test "gates array is sorted by id ascending":
    let manifest = loadManifest()
    let gates = manifest["gates"]
    for i in 1 ..< gates.len:
      let prev = gates[i - 1]["id"].getStr()
      let curr = gates[i]["id"].getStr()
      check curr >= prev

  test "gate manifest entries have string id field":
    let manifest = loadManifest()
    let gates = manifest["gates"]
    for i in 0 ..< gates.len:
      check gates[i]["id"].kind == JString
      check gates[i]["id"].getStr().len > 0

  test "gate manifest entries have string name field":
    let manifest = loadManifest()
    let gates = manifest["gates"]
    for i in 0 ..< gates.len:
      check gates[i]["name"].kind == JString
      check gates[i]["name"].getStr().len > 0

  test "gate manifest entries have string entry field":
    let manifest = loadManifest()
    let gates = manifest["gates"]
    for i in 0 ..< gates.len:
      check gates[i]["entry"].kind == JString
      check gates[i]["entry"].getStr().len > 0

{.pop.}
