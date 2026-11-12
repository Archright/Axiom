{.push raises: [].}

## Unit tests for cli/report_cli.nim
##
## Covers all exported pure funcs and file-system procs using temp dirs.
## runReportCli is excluded because it depends on deep verification
## infrastructure (report_engine, proof_state_builder) that cannot be
## meaningfully unit-tested in isolation.

import std/json
import std/os
import std/sequtils
import std/strutils
import std/times
import std/unittest

import cli/cli_types
import cli/report_cli
import core/results

# ---------------------------------------------------------------------------
# Suite 1 — renderReportStdoutLines
# ---------------------------------------------------------------------------

suite "renderReportStdoutLines":
  test "emitJson=true with non-empty outputJson returns JSON in a single-element seq":
    let output = AxCommandCliResult(
      outputJson: "{\"ok\":true}", logLines: @[], exitCode: 0, emitJson: true)
    let lines = renderReportStdoutLines(output)
    check lines.len == 1
    check lines[0] == "{\"ok\":true}"

  test "emitJson=true but empty outputJson falls back to logLines":
    let output = AxCommandCliResult(
      outputJson: "", logLines: @["line1", "line2"], exitCode: 0, emitJson: true)
    let lines = renderReportStdoutLines(output)
    check lines == @["line1", "line2"]

  test "emitJson=false returns logLines as-is":
    let output = AxCommandCliResult(
      outputJson: "{\"x\":1}", logLines: @["a", "b", "c"], exitCode: 0, emitJson: false)
    let lines = renderReportStdoutLines(output)
    check lines == @["a", "b", "c"]

  test "empty logLines and emitJson=false yields empty seq":
    let output = AxCommandCliResult(
      outputJson: "", logLines: @[], exitCode: 0, emitJson: false)
    let lines = renderReportStdoutLines(output)
    check lines.len == 0

# ---------------------------------------------------------------------------
# Suite 2 — renderReportStderrLines
# ---------------------------------------------------------------------------

suite "renderReportStderrLines":
  test "always returns logLines regardless of emitJson":
    let o1 = AxCommandCliResult(
      outputJson: "", logLines: @["err"], exitCode: 0, emitJson: true)
    check renderReportStderrLines(o1) == @["err"]
    let o2 = AxCommandCliResult(
      outputJson: "", logLines: @["err"], exitCode: 0, emitJson: false)
    check renderReportStderrLines(o2) == @["err"]

  test "empty logLines yields empty seq":
    let output = AxCommandCliResult(
      outputJson: "", logLines: @[], exitCode: 0, emitJson: false)
    check renderReportStderrLines(output).len == 0

  test "multiple log lines preserved in order":
    let output = AxCommandCliResult(
      outputJson: "", logLines: @["first", "second", "third"], exitCode: 0, emitJson: false)
    check renderReportStderrLines(output) == @["first", "second", "third"]

# ---------------------------------------------------------------------------
# Suite 3 — renderOutputBlock
# ---------------------------------------------------------------------------

suite "renderOutputBlock":
  test "empty lines yields empty string":
    check renderOutputBlock(@[]) == ""

  test "single line ends with newline":
    check renderOutputBlock(@["hello"]) == "hello\n"

  test "multiple lines joined with newlines and trailing newline":
    let s = renderOutputBlock(@["a", "b", "c"])
    check s == "a\nb\nc\n"

  test "line with special characters preserved":
    let s = renderOutputBlock(@["key=val", "{\"json\":true}"])
    check s == "key=val\n{\"json\":true}\n"

  test "empty string elements are still joined":
    let s = renderOutputBlock(@["", "", ""])
    check s == "\n\n\n"

# ---------------------------------------------------------------------------
# Suite 4 — usesAxShortcutJsonFlag
# ---------------------------------------------------------------------------

suite "usesAxShortcutJsonFlag":
  test "detects --json flag":
    check usesAxShortcutJsonFlag(@["prove", "--json"]) == true

  test "no --json flag returns false":
    check usesAxShortcutJsonFlag(@["prove", "--limit", "10"]) == false

  test "empty args returns false":
    check usesAxShortcutJsonFlag(@[]) == false

  test "--json at start of args":
    check usesAxShortcutJsonFlag(@["--json", "report"]) == true

  test "partial match like --json-pretty does not trigger":
    check usesAxShortcutJsonFlag(@["--json-pretty"]) == false

  test "multiple flags including --json":
    check usesAxShortcutJsonFlag(@["--json", "--clean", "resilience"]) == true

# ---------------------------------------------------------------------------
# Suite 5 — renderAxShortcutStdoutLines
# ---------------------------------------------------------------------------

suite "renderAxShortcutStdoutLines":
  test "emitJson=true with non-empty outputJson returns JSON":
    let output = AxCommandCliResult(
      outputJson: "{\"v\":1}", logLines: @[], exitCode: 0, emitJson: false)
    let lines = renderAxShortcutStdoutLines(output, emitJson = true)
    check lines.len == 1
    check lines[0] == "{\"v\":1}"

  test "emitJson=true but empty outputJson returns empty seq":
    let output = AxCommandCliResult(
      outputJson: "", logLines: @[], exitCode: 0, emitJson: false)
    let lines = renderAxShortcutStdoutLines(output, emitJson = true)
    check lines.len == 0

  test "emitJson=false always returns empty seq":
    let output = AxCommandCliResult(
      outputJson: "{\"v\":1}", logLines: @[], exitCode: 0, emitJson: true)
    let lines = renderAxShortcutStdoutLines(output, emitJson = false)
    check lines.len == 0

# ---------------------------------------------------------------------------
# Suite 6 — renderAxShortcutStderrLines
# ---------------------------------------------------------------------------

suite "renderAxShortcutStderrLines":
  test "always returns logLines regardless of emitJson":
    let output = AxCommandCliResult(
      outputJson: "", logLines: @["stderr-line"], exitCode: 0, emitJson: false)
    check renderAxShortcutStderrLines(output, emitJson = true) == @["stderr-line"]
    check renderAxShortcutStderrLines(output, emitJson = false) == @["stderr-line"]

  test "empty logLines yields empty seq":
    let output = AxCommandCliResult(
      outputJson: "", logLines: @[], exitCode: 0, emitJson: false)
    check renderAxShortcutStderrLines(output, emitJson = true).len == 0

# ---------------------------------------------------------------------------
# Suite 7 — archiveStaleProofState (filesystem)
# ---------------------------------------------------------------------------

suite "archiveStaleProofState":
  test "no-op when proof state file does not exist":
    let tmpDir = getTempDir() / "axiom_test_archive_" & $epochTime()
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    archiveStaleProofState(tmpDir)

  test "no-op when file is fresh (age < 24h)":
    let tmpDir = getTempDir() / "axiom_test_archive_fresh_" & $epochTime()
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let proofPath = tmpDir / "logs" / "ax_proof_state.json"
    createDir(proofPath.parentDir)
    writeFile(proofPath, "{}")
    archiveStaleProofState(tmpDir)
    check fileExists(proofPath)

  test "archives file when older than 24 hours":
    let tmpDir = getTempDir() / "axiom_test_archive_stale_" & $epochTime()
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let proofPath = tmpDir / "logs" / "ax_proof_state.json"
    createDir(proofPath.parentDir)
    writeFile(proofPath, "{}")
    let staleTime = getTime() - initDuration(hours = 48)
    setLastModificationTime(proofPath, staleTime)
    archiveStaleProofState(tmpDir)
    check not fileExists(proofPath)
    var foundStale = false
    for kind, path in walkDir(tmpDir / "logs"):
      if kind == pcFile and ".stale." in path:
        foundStale = true
        break
    check foundStale

# ---------------------------------------------------------------------------
# Suite 8 — renderResilienceSummary (filesystem)
# ---------------------------------------------------------------------------

suite "renderResilienceSummary":
  test "missing directory returns header with message":
    let lines = renderResilienceSummary("/nonexistent/path/axiom_test_resil")
    check lines.len == 2
    check lines[0] == "=== Resilience Summary ==="
    check "No dump directory found" in lines[1]

  test "empty directory returns zero errors":
    let tmpDir = getTempDir() / "axiom_test_resil_empty_" & $epochTime()
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let lines = renderResilienceSummary(tmpDir)
    check lines.len == 2
    check "Total errors: 0" in lines[1]

  test "parses single jsonl entry":
    let tmpDir = getTempDir() / "axiom_test_resil_single_" & $epochTime()
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    writeFile(tmpDir / "errors.jsonl",
      """{"errorClass":"Timeout","recoveryAction":"retry","timestamp":"2026-01-01T00:00:00Z","nodeId":"nodeA"}""")
    let lines = renderResilienceSummary(tmpDir)
    let joined = lines.join("\n")
    check "Total errors: 1" in joined
    check "Timeout" in joined
    check "retry" in joined
    check "nodeA" in joined

  test "counts multiple entries with same error class":
    let tmpDir = getTempDir() / "axiom_test_resil_multi_" & $epochTime()
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let content = [
      """{"errorClass":"Timeout","recoveryAction":"retry","timestamp":"2026-01-01T00:00:00Z","nodeId":"n1"}""",
      """{"errorClass":"Timeout","recoveryAction":"retry","timestamp":"2026-01-02T00:00:00Z","nodeId":"n2"}""",
      """{"errorClass":"OOM","recoveryAction":"skip","timestamp":"2026-01-03T00:00:00Z","nodeId":"n3"}""",
    ].join("\n")
    writeFile(tmpDir / "dump.jsonl", content)
    let lines = renderResilienceSummary(tmpDir)
    let joined = lines.join("\n")
    check "Total errors: 3" in joined
    check "By class:" in joined
    check "By action:" in joined

  test "tracks last error by timestamp":
    let tmpDir = getTempDir() / "axiom_test_resil_last_" & $epochTime()
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let content = [
      """{"errorClass":"Old","recoveryAction":"skip","timestamp":"2026-01-01T00:00:00Z","nodeId":"old_node"}""",
      """{"errorClass":"New","recoveryAction":"retry","timestamp":"2026-06-15T12:00:00Z","nodeId":"new_node"}""",
    ].join("\n")
    writeFile(tmpDir / "dump.jsonl", content)
    let lines = renderResilienceSummary(tmpDir)
    let joined = lines.join("\n")
    check "Last error:" in joined
    check "new_node" in joined
    check "New" in joined

  test "skips malformed json lines":
    let tmpDir = getTempDir() / "axiom_test_resil_malform_" & $epochTime()
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let content = [
      "not json at all",
      """{"errorClass":"OK","recoveryAction":"retry","timestamp":"2026-01-01T00:00:00Z","nodeId":"n1"}""",
    ].join("\n")
    writeFile(tmpDir / "bad.jsonl", content)
    let lines = renderResilienceSummary(tmpDir)
    let joined = lines.join("\n")
    check "Total errors: 1" in joined

  test "skips entries with missing fields (defaults to unknown)":
    let tmpDir = getTempDir() / "axiom_test_resil_defaults_" & $epochTime()
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    writeFile(tmpDir / "minimal.jsonl",
      """{"timestamp":"2026-01-01T00:00:00Z"}""")
    let lines = renderResilienceSummary(tmpDir)
    let joined = lines.join("\n")
    check "Total errors: 1" in joined
    check "unknown" in joined

  test "skips non-jsonl files in directory":
    let tmpDir = getTempDir() / "axiom_test_resil_filter_" & $epochTime()
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    writeFile(tmpDir / "readme.txt", "ignore me")
    writeFile(tmpDir / "dump.jsonl",
      """{"errorClass":"X","recoveryAction":"Y","timestamp":"2026-01-01T00:00:00Z","nodeId":"n1"}""")
    let lines = renderResilienceSummary(tmpDir)
    let joined = lines.join("\n")
    check "Total errors: 1" in joined

  test "empty lines in jsonl are skipped":
    let tmpDir = getTempDir() / "axiom_test_resil_emptylines_" & $epochTime()
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    writeFile(tmpDir / "dump.jsonl",
      "\n\n\n{\"errorClass\":\"A\",\"recoveryAction\":\"B\",\"timestamp\":\"2026-01-01T00:00:00Z\",\"nodeId\":\"n1\"}\n\n")
    let lines = renderResilienceSummary(tmpDir)
    let joined = lines.join("\n")
    check "Total errors: 1" in joined

# ---------------------------------------------------------------------------
# Suite 9 — cleanResilienceLogs (filesystem)
# ---------------------------------------------------------------------------

suite "cleanResilienceLogs":
  test "missing directory returns header with message":
    let lines = cleanResilienceLogs("/nonexistent/path/axiom_test_clean_resil")
    check lines.len == 2
    check lines[0] == "=== Resilience Cleanup ==="
    check "No dump directory found" in lines[1]

  test "deletes files older than maxAgeHours":
    let tmpDir = getTempDir() / "axiom_test_clean_old_" & $epochTime()
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let oldFile = tmpDir / "old.jsonl"
    writeFile(oldFile, "{}")
    let staleTime = getTime() - initDuration(hours = 80)
    setLastModificationTime(oldFile, staleTime)
    let lines = cleanResilienceLogs(tmpDir, maxAgeHours = 72, maxCount = 500)
    let joined = lines.join("\n")
    check "Deleted 1 file(s)" in joined
    check not fileExists(oldFile)

  test "keeps files newer than maxAgeHours":
    let tmpDir = getTempDir() / "axiom_test_clean_new_" & $epochTime()
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let newFile = tmpDir / "fresh.jsonl"
    writeFile(newFile, "{}")
    discard cleanResilienceLogs(tmpDir, maxAgeHours = 72, maxCount = 500)
    check fileExists(newFile)

  test "deletes oldest files when count exceeds maxCount":
    let tmpDir = getTempDir() / "axiom_test_clean_count_" & $epochTime()
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    for i in 0 ..< 5:
      let f = tmpDir / ("file_" & $i & ".jsonl")
      writeFile(f, "{}")
      let t = getTime() - initDuration(seconds = 5 * (5 - i))
      setLastModificationTime(f, t)
    let lines = cleanResilienceLogs(tmpDir, maxAgeHours = 72, maxCount = 3)
    let joined = lines.join("\n")
    check "Deleted 2 file(s)" in joined
    var count = 0
    for kind, path in walkDir(tmpDir):
      if kind == pcFile and path.endsWith(".jsonl"):
        inc count
    check count == 3

  test "non-jsonl files are never touched":
    let tmpDir = getTempDir() / "axiom_test_clean_nonjsonl_" & $epochTime()
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    let txtFile = tmpDir / "notes.txt"
    writeFile(txtFile, "keep me")
    let staleTime = getTime() - initDuration(hours = 80)
    setLastModificationTime(txtFile, staleTime)
    discard cleanResilienceLogs(tmpDir, maxAgeHours = 72, maxCount = 500)
    check fileExists(txtFile)

  test "zero maxCount deletes all eligible fresh files":
    let tmpDir = getTempDir() / "axiom_test_clean_zero_" & $epochTime()
    createDir(tmpDir)
    defer: removeDir(tmpDir)
    for i in 0 ..< 3:
      writeFile(tmpDir / ("f" & $i & ".jsonl"), "{}")
    let lines = cleanResilienceLogs(tmpDir, maxAgeHours = 72, maxCount = 0)
    let joined = lines.join("\n")
    check "Deleted 3 file(s)" in joined

# ---------------------------------------------------------------------------
# Suite 10 — Path resolution procs
# ---------------------------------------------------------------------------

suite "resolveAxUxProofStatePath":
  test "with cwdOverride builds correct path":
    let r = resolveAxUxProofStatePath("/tmp/test_axiom")
    check r.endsWith("logs/ux-proof-state.json")
    check r.startsWith("/")

  test "without cwdOverride uses current dir":
    let r = resolveAxUxProofStatePath("")
    check r.endsWith("logs/ux-proof-state.json")

suite "resolveAxStatePath":
  test "with non-empty override returns absolute path of override":
    let r = resolveAxStatePath("/tmp/test_axiom/my_state.json")
    check r == absolutePath("/tmp/test_axiom/my_state.json")

  test "with relative override returns absolute path":
    let r = resolveAxStatePath("relative/state.json")
    check r.isAbsolute

# ---------------------------------------------------------------------------
# Suite 11 — Cross-function integration
# ---------------------------------------------------------------------------

suite "report_cli integration":
  test "renderReportStdoutLines + renderOutputBlock round-trip":
    let output = AxCommandCliResult(
      outputJson: "", logLines: @["line1", "line2"], exitCode: 0, emitJson: false)
    let stdoutLines = renderReportStderrLines(output)
    let s = renderOutputBlock(stdoutLines)
    check s == "line1\nline2\n"

  test "usesAxShortcutJsonFlag + renderAxShortcutStdoutLines":
    let args = @["--json"]
    let emitJson = usesAxShortcutJsonFlag(args)
    let output = AxCommandCliResult(
      outputJson: "{\"data\":42}", logLines: @[], exitCode: 0, emitJson: false)
    let lines = renderAxShortcutStdoutLines(output, emitJson)
    check lines.len == 1
    check lines[0] == "{\"data\":42}"

  test "renderAxShortcutStdoutLines with no json flag":
    let output = AxCommandCliResult(
      outputJson: "{\"data\":42}", logLines: @[], exitCode: 0, emitJson: true)
    let lines = renderAxShortcutStdoutLines(output, emitJson = false)
    check lines.len == 0

# ---------------------------------------------------------------------------
# Suite 12 — report flag contract (the removed --no-cert-sync flag)
# ---------------------------------------------------------------------------
#
# `ax report` never synchronizes certificates: it reads the persisted proof
# state and projects canonical VKD from the TrustCommit journal. The
# --no-cert-sync flag died together with the certificate-convergence path, so
# it selects NO report behaviour — the report is a pure function of its
# persisted state document. This suite pins that inertness: a stale caller
# that still passes the flag gets exactly the same report as one that does
# not, and the flag can never turn certificate synchronization back on.

suite "report flag contract":
  test "the removed --no-cert-sync flag is inert — it selects no report behaviour":
    let withoutFlag = runReportCli(@["--state-file", "no-such-state.json"])
    let withFlag = runReportCli(@["--no-cert-sync", "--state-file", "no-such-state.json"])
    check withoutFlag.isErr()
    check withFlag.isErr()
    check withFlag.error == withoutFlag.error

  test "the report is driven by the persisted state document, not by flags":
    let missingState = runReportCli(@["--state-file", "no-such-state.json"])
    check missingState.isErr()
    check "no-such-state.json" in missingState.error

{.pop.}
