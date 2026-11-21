## Unit tests for Z3 lane-attribution telemetry (z3_telemetry.Z3TelemetryRecord).
##
## Pins the attribution contract added for perf/z3-lane-attribution:
##   - every new key is serialized under its snake_case name and round-trips
##     through the JSONL file with its exact value (no key silent-dropped by a
##     serializer edit, no field renamed between record and file);
##   - a zero-initialized record serializes execution_path as "none" — the
##     "no process dispatched" default, chosen so an unattributed row can never
##     be read as a persistent sample;
##   - existing keys keep their meaning (asserted alongside the new ones so a
##     future schema edit that drops one fails here).
##
## No Z3 binary is required: only appendZ3Telemetry (file I/O) is exercised.
## Env isolation: AXIOM_STATE_DIR points at a private temp dir, so the test
## never touches the repo's logs/ or another suite's state.

import std/[json, os, strutils, tempfiles, unittest]
import core/solver/z3_telemetry

const TelemetryRelPath = "logs/z3_telemetry.jsonl"

proc freshStateDir(): string =
  result = createTempDir("axiom_z3_tel_test_", "")
  createDir(result / "logs")

proc readTelemetryLines(stateDir: string): seq[string] =
  let path = stateDir / TelemetryRelPath
  if not fileExists(path):
    return @[]
  for line in readFile(path).splitLines():
    if line.strip().len > 0:
      result.add(line)

suite "Z3TelemetryAttribution":
  test "new attribution keys round-trip through the JSONL file":
    let stateDir = freshStateDir()
    putEnv("AXIOM_STATE_DIR", stateDir)
    defer:
      delEnv("AXIOM_STATE_DIR")
      removeDir(stateDir)

    let record = Z3TelemetryRecord(
      ts: "2026-11-22T00:00:00Z",
      queryType: "ir_pipeline_bmc",
      rlimit: 30_000_000,
      result: "unsat",
      timeMs: 1234,
      memoryMb: 56,
      cegarIters: 0,
      baseCaseResult: "",
      stepCaseResult: "",
      canonicalEnvelopeDigest: "aa11bb22cc33dd44ee55ff6600112233445566778899aabbccddeeff00112233",
      transportPayloadDigest: "ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100",
      workerAcquireMs: 17,
      workerRoundtripMs: 991,
      executionPath: "one_shot_file",
      workerPid: 424242,
      rssBeforeKb: 4096,
      rssAfterKb: 0,
      rssDeltaValid: false,
      getModelRequested: true
    )
    appendZ3Telemetry(record)

    let lines = readTelemetryLines(stateDir)
    check lines.len == 1
    let obj = parseJson(lines[0])

    # New attribution keys: name and value both round-trip.
    check obj["worker_acquire_ms"].getInt() == 17
    check obj["worker_roundtrip_ms"].getInt() == 991
    check obj["execution_path"].getStr() == "one_shot_file"
    check obj["worker_pid"].getInt() == 424242
    check obj["rss_before_kb"].getInt() == 4096
    check obj["rss_after_kb"].getInt() == 0
    check obj["rss_delta_valid"].getBool() == false
    check obj["get_model_requested"].getBool() == true

    # Lane label and the existing keys keep their meaning.
    check obj["query_type"].getStr() == "ir_pipeline_bmc"
    check obj["ts"].getStr() == "2026-11-22T00:00:00Z"
    check obj["rlimit"].getInt() == 30_000_000
    check obj["result"].getStr() == "unsat"
    check obj["time_ms"].getInt() == 1234
    check obj["memory_mb"].getInt() == 56
    check obj["cegar_iters"].getInt() == 0
    check obj["base_case_result"].getStr() == ""
    check obj["step_case_result"].getStr() == ""
    check obj["canonical_envelope_digest"].getStr() ==
      "aa11bb22cc33dd44ee55ff6600112233445566778899aabbccddeeff00112233"
    check obj["transport_payload_digest"].getStr() ==
      "ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100"

  test "default execution_path is \"none\" for a zero-initialized record":
    let stateDir = freshStateDir()
    putEnv("AXIOM_STATE_DIR", stateDir)
    defer:
      delEnv("AXIOM_STATE_DIR")
      removeDir(stateDir)

    # A record built without attribution fields is the "never dispatched"
    # shape: executionPath is the zero string, and the serializer projects it
    # to "none" so no reader mistakes it for a solved lane.
    let record = Z3TelemetryRecord(queryType: "cegar")
    check record.executionPath.len == 0
    check record.workerPid == 0
    appendZ3Telemetry(record)

    let lines = readTelemetryLines(stateDir)
    check lines.len == 1
    let obj = parseJson(lines[0])
    check obj["execution_path"].getStr() == "none"
    check obj["worker_pid"].getInt() == 0
    check obj["rss_delta_valid"].getBool() == false
    check obj["get_model_requested"].getBool() == false

  test "appends accumulate one JSON object per line":
    let stateDir = freshStateDir()
    putEnv("AXIOM_STATE_DIR", stateDir)
    defer:
      delEnv("AXIOM_STATE_DIR")
      removeDir(stateDir)

    appendZ3Telemetry(Z3TelemetryRecord(queryType: "cegar", executionPath: "persistent"))
    appendZ3Telemetry(Z3TelemetryRecord(queryType: "replay", executionPath: "none"))

    let lines = readTelemetryLines(stateDir)
    check lines.len == 2
    check parseJson(lines[0])["query_type"].getStr() == "cegar"
    check parseJson(lines[0])["execution_path"].getStr() == "persistent"
    check parseJson(lines[1])["query_type"].getStr() == "replay"
    check parseJson(lines[1])["execution_path"].getStr() == "none"
