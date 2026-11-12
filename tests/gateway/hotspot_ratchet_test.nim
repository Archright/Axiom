{.push raises: [CatchableError].}
import std/unittest
import std/json
import gate/runners/hotspot_gate

suite "hotspot ratchet":
  test "baseline allows pre-existing hotspots":
    let baseline = %* {"metrics": {"hotspot": {"byFile": {"src/gate/runners.nim": {"deepNesting": 999}}}}}
    writeFile("tests/gateway/fixtures/hotspot_baseline.json", $baseline)
    let loaded = loadBaseline("tests/gateway/fixtures/hotspot_baseline.json")
    check loaded{"metrics"}{"hotspot"}{"byFile"}.len == 1

  test "missing file in baseline is treated as new":
    let baseline = %* {"metrics": {"hotspot": {"byFile": {}}}}
    check isNewHotspot(baseline, "src/new_file.nim", "deepNesting", 3) == true

  test "existing file at same count is NOT new":
    let baseline = %* {"metrics": {"hotspot": {"byFile": {"src/gate/runners.nim": {"deepNesting": 5}}}}}
    check isNewHotspot(baseline, "src/gate/runners.nim", "deepNesting", 5) == false

  test "existing file with increased count IS new":
    let baseline = %* {"metrics": {"hotspot": {"byFile": {"src/gate/runners.nim": {"deepNesting": 5}}}}}
    check isNewHotspot(baseline, "src/gate/runners.nim", "deepNesting", 6) == true

  test "existing file with decreased count is NOT new":
    let baseline = %* {"metrics": {"hotspot": {"byFile": {"src/gate/runners.nim": {"deepNesting": 5}}}}}
    check isNewHotspot(baseline, "src/gate/runners.nim", "deepNesting", 3) == false

  test "zero count on new file is NOT new":
    let baseline = %* {"metrics": {"hotspot": {"byFile": {}}}}
    check isNewHotspot(baseline, "src/clean.nim", "deepNesting", 0) == false

  test "oversized baseline falls back to full scan":
    var big = "{\"metrics\":{\"hotspot\":{\"byFile\":{"
    for i in 0 ..< 100_000: big.add("\"f" & $i & "\":{},")
    big.add("\"last\":{}}}}}")
    writeFile("tests/gateway/fixtures/oversized_baseline.json", big)
    let loaded = loadBaseline("tests/gateway/fixtures/oversized_baseline.json")
    check loaded.len == 0
{.pop.}
