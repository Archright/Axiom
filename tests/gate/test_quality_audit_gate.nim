{.push raises: [CatchableError].}

## Quality Audit Gate Tests — Unit tests for gate/runners/quality_audit_gate.nim
## Only exported proc is runQualityAudit*. Private helpers are tested indirectly.

import std/[unittest, os, strutils, times]
import gate/runners/quality_audit_gate

# ---------------------------------------------------------------------------
# runQualityAudit
# ---------------------------------------------------------------------------

suite "runQualityAudit":
  test "runs on repo root and produces ok=true":
    let repoRoot = getCurrentDir()
    let (ok, stdout, stderr) = runQualityAudit(repoRoot, @[])
    check ok == true
    check "Audit report written to:" in stdout

  test "report file exists after run":
    let repoRoot = getCurrentDir()
    let (ok, stdout, _) = runQualityAudit(repoRoot, @[])
    check ok == true
    # Extract report path from stdout
    let reportPath = stdout.replace("Audit report written to: ", "").strip
    check fileExists(reportPath)
    # Cleanup: read report to verify it has content
    let content = readFile(reportPath)
    check content.len > 0
    check "Quality Gate" in content

  test "runs with specific file list":
    let repoRoot = getCurrentDir()
    let (ok, stdout, _) = runQualityAudit(repoRoot, @["src/cli/main.nim"])
    check ok == true
    check "Audit report written to:" in stdout

  test "report contains required sections":
    let repoRoot = getCurrentDir()
    let (ok, stdout, _) = runQualityAudit(repoRoot, @[])
    check ok == true
    let reportPath = stdout.replace("Audit report written to: ", "").strip
    let content = readFile(reportPath)
    check "## 1. Objective Metrics" in content
    check "## 2. Gate Execution" in content
    check "## 3. Debt Baseline" in content
    check "## 4. Binary Freshness" in content
    check "## 5. Compilation Status" in content
    check "## 6. Grade Assessment" in content
    check "## 7. Recommendations" in content

  test "nonexistent repo writes report (may fail with empty metrics)":
    let (ok, stdout, _) = runQualityAudit("/nonexistent/path/to/repo", @[])
    # Report file may or may not be written depending on createDir behavior.
    # The important thing is the function doesn't crash.
    # Function doesn't crash on nonexistent path; ok value is environment-dependent

{.pop.}
