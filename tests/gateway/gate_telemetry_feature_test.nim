## Gate Run Telemetry Feature Test — Structured Execution Log Pipeline (v3)
## See tests/features/gate_telemetry.feature for the specification.
##
## Contract: Zero-Jitter telemetry, in-memory collection, batch flush, JSONL output.

import std/[unittest, os, times, json, strutils]
import gate/utils/gate_run_logger

suite "Gate Run Telemetry — Zero-Jitter Pipeline":
  setup:
    let tmpDir = getTempDir() / "axiom_telemetry_test_" & $epochTime().int
    createDir(tmpDir / ".axiom" / "gate_runs")
    # Override the working directory for tests
    let origDir = getCurrentDir()
    setCurrentDir(tmpDir)

  teardown:
    setCurrentDir(origDir)
    removeDir(tmpDir)

  test "initContext creates valid RunContext":
    ## Scenario: initContext creates a valid RunContext
    ## Given a stage name and file count
    ## When I call initContext
    ## Then the context has non-empty fields
    let ctx = initContext("pre-commit", 5, 0)
    check ctx.stage == "pre-commit"
    check ctx.stagedFiles == 5
    check ctx.epoch >= 0

  test "initTelemetry creates empty buffer":
    ## Scenario: initTelemetry creates an empty buffer
    ## Given a RunContext
    ## When I call initTelemetry
    ## Then the buffer has no records
    let ctx = initContext("pre-commit", 5, 0)
    let buf = initTelemetry(ctx)
    check buf.records.len == 0

  test "logGate adds record to buffer":
    ## Scenario: logGate adds a record to the buffer
    ## Given a TelemetryBuffer
    ## When I call logGate
    ## Then the buffer contains the record
    var buf = initTelemetry(initContext("pre-commit", 5, 0))
    logGate(buf, "test-gate", "pass", 1_000_000)
    check buf.records.len == 1
    check buf.records[0].gateId == "test-gate"
    check buf.records[0].result == "pass"
    check buf.records[0].durationNs == 1_000_000

  test "logGate preserves all fields":
    ## Scenario: logGate preserves all fields
    ## Given a TelemetryBuffer with various fields
    ## When I call logGate with all parameters
    ## Then all fields are stored correctly
    var buf = initTelemetry(initContext("pre-commit", 5, 0))
    logGate(buf, "my-gate", "fail", 2_500_000, cached = false, tier = 1, outputFile = "/tmp/output.log")
    check buf.records.len == 1
    check buf.records[0].gateId == "my-gate"
    check buf.records[0].result == "fail"
    check buf.records[0].durationNs == 2_500_000
    check buf.records[0].cached == false
    check buf.records[0].tier == 1
    check buf.records[0].outputFile == "/tmp/output.log"

  test "logGate with default values":
    ## Scenario: logGate with default values
    ## Given a TelemetryBuffer
    ## When I call logGate with minimal parameters
    ## Then default values are applied
    var buf = initTelemetry(initContext("pre-commit", 5, 0))
    logGate(buf, "test-gate", "pass", 1_000_000)
    check buf.records[0].cached == false
    check buf.records[0].tier == 1
    check buf.records[0].outputFile == ""

  test "flushToDisk creates JSONL file":
    ## Scenario: flushToDisk creates JSONL history file
    ## Given a TelemetryBuffer with records
    ## When I call flushToDisk
    ## Then the history JSONL file is created with valid JSON
    var buf = initTelemetry(initContext("pre-commit", 5, 0))
    logGate(buf, "test-gate-1", "pass", 1_000_000)
    logGate(buf, "test-gate-2", "fail", 2_000_000)
    flushToDisk(buf)

    let historyPath = ".axiom/gate_history.jsonl"
    check fileExists(historyPath)
    let content = readFile(historyPath)
    let lines = content.strip().splitLines()
    check lines.len == 2

    # Verify first record — toJsonl is flat (no nested ctx)
    let j1 = parseJson(lines[0])
    check j1["gateId"].getStr() == "test-gate-1"
    check j1["result"].getStr() == "pass"
    check j1["durationNs"].getInt() == 1_000_000
    check j1["stage"].getStr() == "pre-commit"

    # Verify second record
    let j2 = parseJson(lines[1])
    check j2["gateId"].getStr() == "test-gate-2"
    check j2["result"].getStr() == "fail"
    check j2["durationNs"].getInt() == 2_000_000

  test "flushToDisk creates summary file":
    ## Scenario: flushToDisk creates summary JSON file
    ## Given a TelemetryBuffer with records
    ## When I call flushToDisk
    ## Then the summary JSON file is created in .axiom/gate_runs/
    var buf = initTelemetry(initContext("pre-commit", 5, 0))
    logGate(buf, "test-gate", "pass", 1_000_000)
    flushToDisk(buf)

    let summaryDir = ".axiom/gate_runs"
    check dirExists(summaryDir)
    # Check that at least one summary file exists
    var found = false
    for kind, path in walkDir(summaryDir):
      if path.endsWith(".json"):
        found = true
        let j = parseJson(readFile(path))
        check j["stage"].getStr() == "pre-commit"
        check j["gatesTotal"].getInt() == 1
        break
    check found

  test "flushToDisk preserves buffer after flush":
    ## Scenario: flushToDisk preserves the buffer for post-flush inspection
    ## Given a TelemetryBuffer with records
    ## When I call flushToDisk
    ## Then the buffer records are preserved (not cleared)
    var buf = initTelemetry(initContext("pre-commit", 5, 0))
    logGate(buf, "test-gate", "pass", 1_000_000)
    check buf.records.len == 1
    flushToDisk(buf)
    check buf.records.len == 1
    check buf.records[0].gateId == "test-gate"

  test "flushToDisk does nothing on empty buffer":
    ## Scenario: flushToDisk does nothing on empty buffer
    ## Given an empty TelemetryBuffer
    ## When I call flushToDisk
    ## Then no files are created
    var buf = initTelemetry(initContext("pre-commit", 5, 0))
    flushToDisk(buf)
    check not fileExists(".axiom/gate_history.jsonl")

  test "multiple flushes append to history":
    ## Scenario: multiple flushes append to history
    ## Given multiple flushes
    ## When I call flushToDisk multiple times
    ## Then the history file contains all records
    var buf1 = initTelemetry(initContext("pre-commit", 5, 0))
    logGate(buf1, "gate-1", "pass", 1_000_000)
    flushToDisk(buf1)

    var buf2 = initTelemetry(initContext("pre-push", 3, 0))
    logGate(buf2, "gate-2", "fail", 2_000_000)
    flushToDisk(buf2)

    let historyPath = ".axiom/gate_history.jsonl"
    check fileExists(historyPath)
    let lines = readFile(historyPath).strip().splitLines()
    check lines.len == 2

  test "gcOldRuns removes old summaries":
    ## Scenario: gcOldRuns removes old summary files
    ## Given old summary files
    ## When I call gcOldRuns
    ## Then old files are removed
    let cacheDir = tmpDir / ".axiom"
    let runsDir = cacheDir / "gate_runs"
    createDir(runsDir)
    let oldFile = runsDir / "2020-01-01_00-00-00_pre-commit.json"
    writeFile(oldFile, """{"stage":"pre-commit","records":[]}""")

    # Set the file to be old (31 days ago)
    let oldTime = getTime() - initDuration(days = 31)
    setLastModificationTime(oldFile, oldTime)

    gcOldRuns(cacheDir, maxAge = 30)
    check not fileExists(oldFile)

  test "gcOldRuns preserves recent summaries":
    ## Scenario: gcOldRuns preserves recent summary files
    ## Given recent summary files
    ## When I call gcOldRuns
    ## Then recent files are preserved
    let cacheDir = tmpDir / ".axiom"
    let runsDir = cacheDir / "gate_runs"
    createDir(runsDir)
    let recentFile = runsDir / "2025-01-01_00-00-00_pre-commit.json"
    writeFile(recentFile, """{"stage":"pre-commit","records":[]}""")

    gcOldRuns(cacheDir, maxAge = 30)
    check fileExists(recentFile)

  test "toJsonl produces valid JSON with flat structure":
    ## Scenario: toJsonl produces valid JSON
    ## Given a GateRunRecord and RunContext
    ## When I call toJsonl
    ## Then the output is valid JSON with expected fields (flat, no nested ctx)
    let ctx = initContext("pre-commit", 5, 0)
    let record = GateRunRecord(
      gateId: "test-gate",
      result: "pass",
      durationNs: 1_000_000,
      cached: false,
      tier: 1,
      outputFile: ""
    )
    let jsonl = toJsonl(record, ctx)
    let j = parseJson(jsonl)
    check j["gateId"].getStr() == "test-gate"
    check j["result"].getStr() == "pass"
    check j["durationNs"].getInt() == 1_000_000
    check j["tier"].getInt() == 1
    # Flat structure: stage/commit/branch are top-level
    check j["stage"].getStr() == "pre-commit"
    check j.hasKey("commit")
    check j.hasKey("branch")

  test "toJsonl escapes special characters":
    ## Scenario: toJsonl escapes special characters
    ## Given a record with special characters
    ## When I call toJsonl
    ## Then special characters are properly escaped
    let ctx = initContext("pre-commit", 5, 0)
    let record = GateRunRecord(
      gateId: "test" & "\"" & "gate",
      result: "pass\nfail",
      durationNs: 1_000_000,
      cached: false,
      tier: 1,
      outputFile: ""
    )
    let jsonl = toJsonl(record, ctx)
    let j = parseJson(jsonl)
    check j["gateId"].getStr() == "test\"gate"
    check j["result"].getStr() == "pass\nfail"

  test "bottleneck tracking in buffer":
    ## Scenario: logGate tracks the bottleneck gate
    ## Given multiple gates with different durations
    ## When I call logGate
    ## Then the bottleneck is the slowest gate
    var buf = initTelemetry(initContext("pre-commit", 5, 0))
    logGate(buf, "fast-gate", "pass", 1_000_000)
    logGate(buf, "slow-gate", "pass", 5_000_000)
    logGate(buf, "medium-gate", "pass", 3_000_000)
    check buf.bottleneck == "slow-gate"
    check buf.bottleneckNs == 5_000_000
    check buf.totalDurationNs == 9_000_000
