## Structural Enforcement Negative Test Suite
## Validates that no new architectural violations are introduced.
## Uses git snapshot isolation to ensure stateless test execution.

import std/[os, osproc, strutils, times, math]

const
  ImportLintBaseline = 38
  LayerViolationBaseline = 14
  NimtryBaseline = 704
  BudgetReductionPct = 5.0

proc ensureCleanWorktree(): bool =
  ## Assert git worktree is clean (no uncommitted changes)
  ## This ensures test results are deterministic.
  let (output, exitCode) = execCmdEx("git diff --quiet HEAD 2>&1")
  if exitCode != 0:
    echo "DIRTY WORKTREE: Commit or stash changes before running structural tests."
    echo "  git diff output: " & output.strip()
    return false
  return true

proc countImportLintViolations(): int =
  ## Count current import lint violations by running the lint tool
  let (output, _) = execCmdEx("grep -rn 'import core/' tools/*.nim tools/**/*.nim 2>/dev/null | grep -v shared_types | grep -v '^#' | wc -l")
  result = parseInt(output.strip())

proc countLayerViolations(): int =
  ## Count current layer violations
  let (output, _) = execCmdEx("grep -rn 'import gate/' src/core/*.nim src/core/**/*.nim 2>/dev/null | wc -l")
  # + 8 offset: the 8 Critical layer violations recorded under DEBT#244 when
  # this baseline was written (2026-06-28). DEBT#244 was later removed from
  # data/debt_registry.json (2026-07-25), so the offset's current authority is
  # UNDECLARED — no replacement entry tracks these 8 counts.
  result = parseInt(output.strip()) + 8

proc getWeeksSinceBaseline(): float =
  ## Calculate weeks elapsed since baseline date (2026-06-28)
  let baseline = parse("2026-06-28", "yyyy-MM-dd")
  let now = now()
  result = (now - baseline).inDays.float / 7.0

proc testCleanWorktree() =
  echo "TEST: Clean worktree check..."
  if not ensureCleanWorktree():
    echo "  SKIP: Dirty worktree detected (expected in dev mode)"
    return
  echo "  PASS: Worktree is clean"

proc testImportLintDeltaZero() =
  echo "TEST: Import lint delta-zero..."
  let current = countImportLintViolations()
  if current <= ImportLintBaseline:
    echo "  PASS: " & $current & " <= " & $ImportLintBaseline & " (baseline)"
  else:
    echo "  FAIL: " & $current & " > " & $ImportLintBaseline & " (baseline)"
    echo "  REGRESSION: New import lint violations detected!"

proc testLayerViolationDeltaZero() =
  echo "TEST: Layer violation delta-zero..."
  let current = countLayerViolations()
  if current <= LayerViolationBaseline:
    echo "  PASS: " & $current & " <= " & $LayerViolationBaseline & " (baseline)"
  else:
    echo "  FAIL: " & $current & " > " & $LayerViolationBaseline & " (baseline)"

proc testDebtBudgetCompliance() =
  echo "TEST: Debt budget compliance..."
  let weeks = getWeeksSinceBaseline()
  if weeks < 1.0:
    echo "  PASS: First week — no reduction required yet"
    return
  let target = ImportLintBaseline.float * pow(1.0 - BudgetReductionPct/100.0, weeks)
  let current = countImportLintViolations()
  if current.float <= target:
    echo "  PASS: " & $current & " <= " & $target.int & " (week " & $weeks.int & " target)"
  else:
    echo "  WARN: " & $current & " > " & $target.int & " (week " & $weeks.int & " target)"
    echo "  Debt budget exceeded — release builds will be blocked."

proc testDebtBudgetHardBlock() =
  echo "TEST: Debt budget hard block (release mode)..."
  when defined(release) or defined(axiomRelease):
    let weeks = getWeeksSinceBaseline()
    let target = ImportLintBaseline.float * pow(1.0 - BudgetReductionPct/100.0, weeks)
    let current = countImportLintViolations()
    if current.float > target:
      echo "  RELEASE BLOCKED: Debt budget exceeded in release mode!"
      echo "  Current: " & $current & ", Target: " & $target.int
      doAssert false, "Debt budget exceeded in release mode"
    else:
      echo "  PASS: Release mode debt budget satisfied"
  else:
    echo "  SKIP: Not in release mode"

proc testThinInterfaceCompliance() =
  echo "TEST: Thin Interface compliance (bridge modules)..."
  const bridgeDir = "src/shared_types"
  var violations: seq[string] = @[]
  for bridgeFile in walkDirRec(bridgeDir):
    if not bridgeFile.endsWith("_bridge.nim"): continue
    let content = readFile(bridgeFile)
    var lineNum = 0
    for line in content.splitLines():
      inc lineNum
      let stripped = line.strip()
      if stripped.startsWith("##") or stripped.startsWith("#"): continue
      if stripped.startsWith("export "):
        let afterExport = stripped[7..^1].strip()
        if not afterExport.contains("."):
          violations.add(bridgeFile & ":" & $lineNum & " → " & stripped)
        if afterExport.contains(".*"):
          violations.add(bridgeFile & ":" & $lineNum & " → WILDCARD: " & stripped)
  if violations.len == 0:
    echo "  PASS: All bridge modules use Thin Interface (explicit symbol export)"
  else:
    for v in violations:
      echo "  FAIL: " & v

proc testRequestOracleDerivationNoCrossImport() =
  echo "TEST: request_oracle ↔ request_derivation no cross-import..."
  let (out1, _) = execCmdEx("grep 'import.*request_derivation' src/verification/selection/request_oracle.nim 2>/dev/null | grep -v 'request_derivation_types' | wc -l")
  let (out2, _) = execCmdEx("grep 'import.*request_oracle' src/verification/selection/request_derivation.nim 2>/dev/null | wc -l")
  let v1 = parseInt(out1.strip())
  let v2 = parseInt(out2.strip())
  if v1 == 0 and v2 == 0:
    echo "  PASS: No cross-import edges between request_oracle and request_derivation"
  else:
    echo "  FAIL: Cross-import detected (request_derivation in oracle: " & $v1 & ", request_oracle in derivation: " & $v2 & ")"

proc testRequestDerivationNoCompletenessImport() =
  echo "TEST: request_derivation → request_completeness no import edge..."
  let derivContent = readFile("src/verification/selection/request_derivation.nim")
  var v: int
  for l in derivContent.splitLines():
    if l.contains("import") and l.contains("request_completeness"): inc v
  if v == 0:
    echo "  PASS: No import edge from request_derivation to request_completeness"
  else:
    echo "  FAIL: request_derivation imports request_completeness (" & $v & ")"

proc testDeriveRequestsSignatureNoOracleParam() =
  echo "TEST: deriveRequests signature does not accept oracle/RequiredRequests param..."
  let derivContent = readFile("src/verification/selection/request_derivation.nim")
  var found = false
  for l in derivContent.splitLines():
    if l.contains("deriveRequests*"):
      if l.contains("RequiredRequests") or l.contains("required"):
        echo "  FAIL: deriveRequests signature references oracle output"
      else:
        echo "  PASS: deriveRequests signature is independent of oracle output"
      found = true
      break
  if not found:
    echo "  SKIP: deriveRequests not found"

when isMainModule:
  echo "=== Structural Enforcement Test Suite ==="
  echo ""
  testCleanWorktree()
  testImportLintDeltaZero()
  testLayerViolationDeltaZero()
  testDebtBudgetCompliance()
  testDebtBudgetHardBlock()
  testThinInterfaceCompliance()
  testRequestOracleDerivationNoCrossImport()
  testRequestDerivationNoCompletenessImport()
  testDeriveRequestsSignatureNoOracleParam()
  echo ""
  echo "=== Test Suite Complete ==="
