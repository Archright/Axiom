## Gate Manifest Schema — Structural Validation Test
##
## Verifies that ``src/gate/gate_manifest.json`` satisfies its schema:
##   1. File exists and is valid JSON
##   2. Top-level ``gates`` field is an array
##   3. Every gate has required fields
##   4. Enum fields have valid values
##   5. All ids are unique
##   6. Gates array is sorted by id ascending
##   7. Every runner entry has a corresponding .nim file

import std/[unittest, json, os, algorithm, strutils]

const
  ManifestPath = "src/gate/gate_manifest.json"
  SchemaPath = "src/gate/gate_manifest.schema.json"
  RunnersDir = "src/gate/runners"

  RequiredFields = ["id", "name", "layer", "entry", "stages", "weight"]
  ValidLayers = ["meta", "functional"]
  ValidStages = ["pre-commit", "pre-push", "manual", "ci"]
  ValidWeights = ["light", "medium", "heavy"]

# ---------------------------------------------------------------------------
# Test suite
# ---------------------------------------------------------------------------

suite "Gate Manifest Schema":

  test "manifest file exists":
    check fileExists(ManifestPath)

  test "manifest is valid JSON":
    let raw = readFile(ManifestPath)
    let node = parseJson(raw)
    check node.kind == JObject

  test "gates field is an array":
    let raw = readFile(ManifestPath)
    let root = parseJson(raw)
    check root.hasKey("gates")
    check root["gates"].kind == JArray

  test "every gate has required fields":
    let root = parseJson(readFile(ManifestPath))
    for gate in root["gates"]:
      for field in RequiredFields:
        check gate.hasKey(field)

  test "layer values are only meta or functional":
    let root = parseJson(readFile(ManifestPath))
    for gate in root["gates"]:
      if gate.hasKey("layer"):
        check gate["layer"].getStr() in ValidLayers

  test "weight values are only light, medium, or heavy":
    let root = parseJson(readFile(ManifestPath))
    for gate in root["gates"]:
      if gate.hasKey("weight"):
        check gate["weight"].getStr() in ValidWeights

  test "stages items are only valid stage values":
    let root = parseJson(readFile(ManifestPath))
    for gate in root["gates"]:
      if gate.hasKey("stages"):
        for s in gate["stages"]:
          check s.kind == JString
          check s.getStr() in ValidStages

  test "all gate ids are unique":
    let root = parseJson(readFile(ManifestPath))
    var seen: seq[string]
    for gate in root["gates"]:
      let id = gate["id"].getStr()
      check id notin seen
      seen.add(id)

  test "gates array is sorted by id ascending":
    let root = parseJson(readFile(ManifestPath))
    for i in 1 ..< root["gates"].len:
      let prev = root["gates"][i - 1]["id"].getStr()
      let curr = root["gates"][i]["id"].getStr()
      check prev <= curr

  test "every runners entry has a corresponding .nim file":
    let root = parseJson(readFile(ManifestPath))
    for gate in root["gates"]:
      let entry = gate["entry"].getStr()
      if entry.startsWith(RunnersDir & "/"):
        let nimFile = entry & ".nim"
        check fileExists(nimFile)
