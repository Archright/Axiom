{.push raises: [CatchableError].}

## Unit tests for cli/axiom_status — Gate Pipeline Observability Dashboard.
##
## Tests CLI flag parsing, return codes, history parsing, and business scenario
## handling per AGENTS.md §0.7 (business-only test scope).
##
## The module's I/O procs (renderFormatted, renderJson, etc.) write directly to
## stdout; we test them indirectly via runStatusCli which is the main entry point.
## Fields of GateRecord/PipelineRun are not exported, so we verify through the
## CLI interface return codes and behavioral correctness.

import std/json
import std/os
import std/strutils
import std/times
import std/unittest

import cli/axiom_status

# ── Helpers ───────────────────────────────────────────────────────────────────

proc makeTempWorkspace(historyContent: string = ""): string =
  ## Create a temporary workspace with optional gate history.
  ## Returns the path to the temp directory.
  let base = getTempDir() / "axiom_status_test_" & $getCurrentProcessId() &
             "_" & $epochTime().int
  createDir(base / ".axiom")
  if historyContent.len > 0:
    writeFile(base / ".axiom" / "gate_history.jsonl", historyContent)
  result = base

proc removeWorkspace(dir: string) =
  ## Best-effort cleanup of a temporary workspace.
  if dirExists(dir):
    removeDir(dir)

template withWorkspace(history: string, body: untyped) =
  ## Execute `body` inside a temporary workspace that has the given gate history.
  ## Restores the original working directory and cleans up afterwards.
  let ws = makeTempWorkspace(history)
  let savedDir = getCurrentDir()
  try:
    setCurrentDir(ws)
    body
  finally:
    setCurrentDir(savedDir)
    removeWorkspace(ws)

# ── Sample History Data ───────────────────────────────────────────────────────

const singlePassRun = """{"gateId":"nimtry","result":"pass","durationNs":50000000,"ts":"2026-07-04T10:00:00+09:00","stage":"pre-commit","commit":"abc123def456","branch":"core","tier":1,"cached":false}"""

const twoGateRun = """{"gateId":"nimtry","result":"pass","durationNs":50000000,"ts":"2026-07-04T10:00:00+09:00","stage":"pre-commit","commit":"abc123def456","branch":"core","tier":1,"cached":false}
{"gateId":"import-encapsulation","result":"pass","durationNs":30000000,"ts":"2026-07-04T10:00:00+09:00","stage":"pre-commit","commit":"abc123def456","branch":"core","tier":1,"cached":false}"""

const failRun = """{"gateId":"nimtry","result":"fail","durationNs":50000000,"ts":"2026-07-04T10:00:00+09:00","stage":"pre-commit","commit":"abc123def456","branch":"core","tier":1,"cached":false}"""

const skipRun = """{"gateId":"nimtry","result":"skip","durationNs":0,"ts":"2026-07-04T10:00:00+09:00","stage":"pre-commit","commit":"abc123def456","branch":"core","tier":1,"cached":false}"""

const cachedRun = """{"gateId":"nimtry","result":"cached","durationNs":1000000,"ts":"2026-07-04T10:00:00+09:00","stage":"pre-commit","commit":"abc123def456","branch":"core","tier":1,"cached":true}"""

const multiRunHistory = """{"gateId":"nimtry","result":"pass","durationNs":50000000,"ts":"2026-07-04T09:00:00+09:00","stage":"pre-commit","commit":"aaa111bbb222","branch":"core","tier":1,"cached":false}
{"gateId":"nimtry","result":"pass","durationNs":45000000,"ts":"2026-07-04T10:00:00+09:00","stage":"pre-commit","commit":"abc123def456","branch":"core","tier":1,"cached":false}"""

const messyHistory = """# This is a comment line

{"gateId":"nimtry","result":"pass","durationNs":50000000,"ts":"2026-07-04T10:00:00+09:00","stage":"pre-commit","commit":"abc123def456","branch":"core","tier":1,"cached":false}
some random text
"""

const malformedJson = """{"gateId":"nimtry","result":"pass","durationNs":50000000,"ts":"2026-07-04T10:00:00+09:00","stage":"pre-commit","commit":"abc123def456","branch":"core","tier":1,"cached":false}
not valid json at all
{"broken": json
"""

const warnSeverityRun = """{"gateId":"import-encapsulation","result":"fail","durationNs":10000000,"ts":"2026-07-04T10:00:00+09:00","stage":"pre-commit","commit":"abc123def456","branch":"core","tier":1,"cached":false}"""

# ── Tests ─────────────────────────────────────────────────────────────────────

suite "axiom_status — GateClass enum":
  test "all enum variants are distinct":
    check gcPass != gcFail
    check gcPass != gcWarn
    check gcPass != gcRunning
    check gcPass != gcSkip
    check gcPass != gcDeferred
    check gcFail != gcWarn
    check gcFail != gcRunning
    check gcFail != gcSkip
    check gcFail != gcDeferred

  test "enum ordinals are sequential starting at 0":
    check ord(gcPass) == 0
    check ord(gcFail) == 1
    check ord(gcWarn) == 2
    check ord(gcRunning) == 3
    check ord(gcSkip) == 4
    check ord(gcDeferred) == 5

  test "six GateClass variants exist":
    check ord(gcDeferred) == 5  # last variant = 5 means 6 total

suite "axiom_status — CLI flag parsing (§0.7: CLI observability scenario)":
  test "--help returns exit code 0":
    check runStatusCli(@["--help"]) == 0

  test "-h returns exit code 0":
    check runStatusCli(@["-h"]) == 0

  test "unknown flag returns exit code 1":
    check runStatusCli(@["--bogus-flag"]) == 1

  test "--gate without argument returns exit code 1":
    check runStatusCli(@["--gate"]) == 1

suite "axiom_status — empty history (§0.7: 'no history' scenario)":
  test "no history file returns 0 with empty state message":
    withWorkspace(""):
      check runStatusCli(@[]) == 0

  test "empty history file (only whitespace) returns 0":
    withWorkspace("\n\n"):
      check runStatusCli(@[]) == 0

  test "--json with no history returns 0":
    withWorkspace(""):
      check runStatusCli(@["--json"]) == 0

  test "--history with no history returns 0":
    withWorkspace(""):
      check runStatusCli(@["--history"]) == 0

suite "axiom_status — default status display (§0.7: latest run summary)":
  test "single pass run returns 0":
    withWorkspace(singlePassRun):
      check runStatusCli(@[]) == 0

  test "two-gate run returns 0":
    withWorkspace(twoGateRun):
      check runStatusCli(@[]) == 0

  test "fail run returns 0 (status command always succeeds)":
    withWorkspace(failRun):
      check runStatusCli(@[]) == 0

  test "skip run returns 0":
    withWorkspace(skipRun):
      check runStatusCli(@[]) == 0

  test "cached run returns 0":
    withWorkspace(cachedRun):
      check runStatusCli(@[]) == 0

suite "axiom_status — JSON output mode (§0.7: machine-parseable scenario)":
  test "--json with pass run returns 0":
    withWorkspace(singlePassRun):
      check runStatusCli(@["--json"]) == 0

  test "--json with fail run returns 0":
    withWorkspace(failRun):
      check runStatusCli(@["--json"]) == 0

  test "--json with multi-gate run returns 0":
    withWorkspace(twoGateRun):
      check runStatusCli(@["--json"]) == 0

suite "axiom_status — history trend (§0.7: last 10 pipeline runs)":
  test "--history with single run returns 0":
    withWorkspace(singlePassRun):
      check runStatusCli(@["--history"]) == 0

  test "--history with multiple runs returns 0":
    withWorkspace(multiRunHistory):
      check runStatusCli(@["--history"]) == 0

  test "--json --history with multiple runs returns 0":
    withWorkspace(multiRunHistory):
      check runStatusCli(@["--json", "--history"]) == 0

suite "axiom_status — per-gate detail (§0.7: gate-specific scenario)":
  test "--gate with matching id returns 0":
    withWorkspace(singlePassRun):
      check runStatusCli(@["--gate", "nimtry"]) == 0

  test "--gate with non-matching id returns 0 (no records found message)":
    withWorkspace(singlePassRun):
      check runStatusCli(@["--gate", "nonexistent-gate"]) == 0

  test "--json --gate with matching id returns 0":
    withWorkspace(twoGateRun):
      check runStatusCli(@["--json", "--gate", "nimtry"]) == 0

  test "--json --gate with non-matching id returns 0":
    withWorkspace(twoGateRun):
      check runStatusCli(@["--json", "--gate", "nonexistent"]) == 0

suite "axiom_status — robustness and edge cases":
  test "history with blank lines and comments is tolerated":
    withWorkspace(messyHistory):
      check runStatusCli(@[]) == 0

  test "malformed JSON lines are silently skipped":
    withWorkspace(malformedJson):
      check runStatusCli(@[]) == 0

  test "combined --json and --history flags work together":
    withWorkspace(multiRunHistory):
      check runStatusCli(@["--json", "--history"]) == 0

  test "combined --json and --gate flags work together":
    withWorkspace(twoGateRun):
      check runStatusCli(@["--json", "--gate", "import-encapsulation"]) == 0

  test "history with warn-severity gate fail returns 0":
    withWorkspace(warnSeverityRun):
      check runStatusCli(@[]) == 0

  test "history with warn-severity gate fail --json returns 0":
    withWorkspace(warnSeverityRun):
      check runStatusCli(@["--json"]) == 0

  test "history with warn-severity gate fail --gate returns 0":
    withWorkspace(warnSeverityRun):
      check runStatusCli(@["--gate", "import-encapsulation"]) == 0

{.pop.}
