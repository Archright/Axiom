import std/[os, strutils]
import core/results
import core/gate/trust_commit_scope_scan
import gate/gate_contract
import gate/gate_types
import gate/utils/gate_safety_macro
import gate/runners/trust_commit_scope_gate

var failures = 0

proc expect(cond: bool; msg: string) =
  if not cond:
    inc failures
    echo "  FAIL: " & msg

var tmpCounter = 0
proc nextTmpDir(): string =
  inc tmpCounter
  getTempDir() / "axiom_scope_gate_test" & "_" & $getCurrentProcessId() & "_" & $tmpCounter

# --- Helper: build a minimal InProcessGateContext ---
proc makeCtx*(repoRoot: string; stagedFiles: seq[string] = @[]): InProcessGateContext =
  InProcessGateContext(
    repoRoot: repoRoot,
    stagedFiles: stagedFiles,
    gateId: "trust-commit-scope",
    epoch: 0,
    dirtyHash: "",
    subtreeRoot: "",
    stage: 0,
    maxJobs: 1,
    passFilenames: false,
    effectiveTimeoutMs: 30000)

# --- Helper: build a minimal GateConfig ---
proc makeGateConfig*(): GateConfig =
  GateConfig(
    id: "trust-commit-scope",
    name: "trust-commit-scope",
    layer: glFunctional,
    entry: "trust_commit_scope_gate",
    executionMode: "interpreted",
    stages: {gsPreCommit, gsPrePush, gsManual},
    weight: gwMedium,
    severity: gsError,
    hermeticity: ghHermetic,
    tier: 1)

# --- Positive case: append_store.writeRecord is allowed (no findings) ---
proc testAllowedWriterNotFlagged() =
  let d = nextTmpDir()
  if not dirExists(d):
    createDir(d)
  let fixture = d / "positive_fixture.nim"
  writeFile(fixture, """
    let ok = append_store.writeRecord(journalPath, jsonContent)
    """)
  let res = scanForDirectWrites(d)
  expect(
    res.ok and res.value.len == 0,
    "positive case: append_store.writeRecord should not be flagged; got " &
      $res.value.len & " findings")

# --- I7-A/I7-B: raw writeFile to data/trusted/journal is flagged ---
proc testAuthoritativeBypassFlagged() =
  let d = nextTmpDir()
  if not dirExists(d):
    createDir(d)
  let fixture = d / "negative_fixture.nim"
  writeFile(fixture, """
proc evil(baseDir: string) =
  writeFile(baseDir / "data/trusted/journal/commit.json", "{}")
""")
  let res = scanForDirectWrites(d)
  expect(
    res.ok and res.value.len >= 1,
    "negative case: raw writeFile to data/trusted/journal should be flagged; got " &
      $res.value.len & " findings")
  if res.ok and res.value.len >= 1:
    expect(
      res.value[0].call == "writeFile",
      "negative case: finding call should be 'writeFile', got '" &
        res.value[0].call & "'")

# --- Gate runner via stagedFiles: clean file returns ok/empty ---
proc testGateRunCleanViaStagedFiles() =
  let d = nextTmpDir()
  if not dirExists(d):
    createDir(d)
  let fixture = d / "clean.nim"
  writeFile(fixture, """
    discard append_store.appendRecord(storePath, claimLine)
    """)
  let ctx = makeCtx(d, stagedFiles = @[fixture])
  let gate = makeGateConfig()
  let result = run(gate, ctx)
  expect(
    result.ok,
    "gate run on clean staged file should return ok=true; got ok=" & $result.ok &
      ", stdout=" & result.stdout)

# --- Gate runner via stagedFiles: authoritative write returns ok=false (fail-closed) ---
proc testGateRunAuthoritativeWriteFlaggedViaStagedFiles() =
  let d = nextTmpDir()
  if not dirExists(d):
    createDir(d)
  let fixture = d / "bad.nim"
  writeFile(fixture, """
proc evil(baseDir: string) =
  writeFile(baseDir / "data/trusted/journal/commit.json", "{}")
""")
  let ctx = makeCtx(d, stagedFiles = @[fixture])
  let gate = makeGateConfig()
  let result = run(gate, ctx)
  expect(
    not result.ok,
    "gate run on authoritative write should return ok=false (fail-closed); got ok=" & $result.ok)
  expect(
    result.failureReason.len > 0,
    "gate run on authoritative write should have a failureReason; got empty")

# --- Gate runner: derived cert write returns ok=true (exempt, not fail-closed) ---
proc testGateRunDerivedWriteOk() =
  let d = nextTmpDir()
  if not dirExists(d):
    createDir(d)
  let fixture = d / "derived.nim"
  writeFile(fixture, """
proc writeCert() =
  writeFile("src/verification/certificates/proof.json", y)
""")
  let ctx = makeCtx(d, stagedFiles = @[fixture])
  let gate = makeGateConfig()
  let result = run(gate, ctx)
  expect(
    result.ok,
    "gate run on derived certificate write should return ok=true; got ok=" & $result.ok)

# --- Mixed case: allowed + authoritative bypass in same dir ---
proc testMixedDirectory() =
  let d = nextTmpDir()
  if not dirExists(d):
    createDir(d)
  writeFile(d / "allowed.nim", """
    discard append_store.appendRecord(storePath, claimLine)
    """)
  writeFile(d / "forbidden.nim", """
proc evil(baseDir: string) =
  writeFile(baseDir / "data/trusted/journal/commit.json", "{}")
""")
  let res = scanForDirectWrites(d)
  expect(
    res.ok and res.value.len == 1,
    "mixed case: exactly one finding expected (authoritative write), got " &
      $res.value.len & " findings")
  if res.ok and res.value.len >= 1:
    expect(
      res.value[0].call == "writeFile",
      "mixed case: finding should be 'writeFile', got '" &
        res.value[0].call & "'")

# --- Run all ---
echo "  trust_commit_scope_gate tests:"
testAllowedWriterNotFlagged()
testAuthoritativeBypassFlagged()
testMixedDirectory()
testGateRunCleanViaStagedFiles()
testGateRunAuthoritativeWriteFlaggedViaStagedFiles()
testGateRunDerivedWriteOk()

if failures == 0:
  echo "    ALL PASSED"
else:
  echo "    FAILED: " & $failures & " assertion(s)"
  quit(1)
