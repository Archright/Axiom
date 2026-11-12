## compile_time_checks — Runtime equivalents of config.nims heavy checks
##
## Phase D: Moved from config.nims (compile-time NimScript) to runtime gate
## module. These checks previously ran on EVERY `nim c` invocation via
## config.nims, adding significant overhead. Now they only execute when the
## gate framework invokes them (pre-commit / pre-push).
##
## Checks migrated:
##   1. Import Encapsulation — grep-based import boundary scan
##   2. SRP Import-Prefix — debt registry prefix count check
##   3. Golden Data Integrity — git status/diff on data/golden/
##   4. Guard the Guard — SHA256 hash verification of architecture_invariants.nim
##
## Each check is a standalone proc that returns CheckResult.
## This module can be imported by gate runners or compiled standalone.
##
## GateTag: [compile-time-checks]

import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

import core/interfaces/git_operations
import std/[os, strutils, json, osproc]
import core/axiom_pragmas
# axiomIoBoundary

const
  GateTag = "[compile-time-checks]"

type
  CheckResult* = object
    passed*: bool
    violations*: seq[string]

# ── 1. Import Encapsulation Check ────────────────────────────────────────────
# Previously: config.nims lines 126-187
# Core modules must not import from gate/, cli/, or verification/.
# gate/, engine/ must not import core/ trusted types directly.
# Uses readFile + string matching instead of shell grep for runtime use.

func findImportViolations(content: string; dir: string;
                          pattern: string): seq[string] =
  ## Scan file content for "import <pattern>" occurrences.
  ## Returns matched lines as violation messages.
  result = @[]
  let needle = "import " & pattern
  var lineNum = 0
  for line in content.splitLines():
    inc lineNum
    let stripped = line.strip()
    # Skip comments
    if stripped.startsWith("#"): continue
    if needle in stripped:
      result.add(dir & ":" & $lineNum & ": " & stripped)

proc checkImportEncapsulation*(): CheckResult {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Import Encapsulation Gate — runtime equivalent.
  ## Checks forbidden import patterns using data/forbidden_imports.json (SSOT)
  ## plus hardcoded fallback rules.
  result = CheckResult(passed: true, violations: @[])

  # Skip if recursive import parsing
  if getEnv("AxiomParsingImports").len > 0:
    return

  # ── Source direction: data-driven rules from JSON ──
  var rulesLoaded = false
  let jsonPath = "data/forbidden_imports.json"
  if fileExists(jsonPath):
    try:
      let rulesJson = parseJson(readFile(jsonPath))
      for rule in rulesJson["rules"]:
        let source = rule["source"].getStr()
        for patNode in rule["forbidden"]:
          let pattern = patNode.getStr()
          # Scan all .nim files under source directory
          if not dirExists(source): continue
          for kind, path in walkDir(source):
            if kind != pcFile: continue
            if not path.endsWith(".nim"): continue
            try:
              let content = readFile(path)
              let hits = findImportViolations(content, path, pattern)
              for hit in hits:
                result.violations.add(
                  "IMPORT ENCAPSULATION VIOLATION: " & source &
                  " → " & pattern & "\n  " & hit)
            except CatchableError:
              discard  # axiom:best-effort(ioboundary catch)
      rulesLoaded = true
    except CatchableError:
      discard  # JSON parse failed — fall through to hardcoded rules  # axiom:best-effort(ioboundary catch)

  # Fallback: hardcoded rules if data file unavailable
  if not rulesLoaded:
    for dir in @["src/gate/", "src/engine/", "src/cli/", "src/verification/"]:
      for pattern in @["core/trusted/", "core/types/"]:
        if not dirExists(dir): continue
        for kind, path in walkDir(dir):
          if kind != pcFile: continue
          if not path.endsWith(".nim"): continue
          try:
            let content = readFile(path)
            let hits = findImportViolations(content, path, pattern)
            for hit in hits:
              result.violations.add(
                "IMPORT ENCAPSULATION VIOLATION: " & dir &
                " → " & pattern & "\n  " & hit &
                " (fallback mode)")
          except CatchableError:
            discard  # axiom:best-effort(ioboundary catch)

  # Core direction: core/ must not import from gate/, cli/, verification/
  let coreForbidden = ["import gate/", "import cli/", "import verification/",
                       "from gate/", "from cli/", "from verification/"]
  if dirExists("src/core/"):
    for kind, path in walkDir("src/core/"):
      if kind != pcFile: continue
      if not path.endsWith(".nim"): continue
      # Skip application and boundary subdirs
      if path.contains("/application/") or path.contains("/boundary/"): continue
      try:
        let content = readFile(path)
        var lineNum = 0
        for line in content.splitLines():
          inc lineNum
          let stripped = line.strip()
          if stripped.startsWith("#"): continue
          for pat in coreForbidden:
            if pat in stripped:
              result.violations.add(
                "[FAIL] [ImportEncapsulation] " & path & ":" & $lineNum & ": " & stripped)
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)

  # Inbound: engine/, gate/ must not import core/ schema or topology directly
  let inboundForbidden = @["import core/schema/", "from core/schema/",
                           "import core/topology/", "from core/topology/"]
  for checkDir in @["src/engine/", "src/gate/"]:
    if not dirExists(checkDir): continue
    for kind, path in walkDir(checkDir):
      if kind != pcFile: continue
      if not path.endsWith(".nim"): continue
      try:
        let content = readFile(path)
        var lineNum = 0
        for line in content.splitLines():
          inc lineNum
          let stripped = line.strip()
          if stripped.startsWith("#"): continue
          for pat in inboundForbidden:
            if pat in stripped:
              result.violations.add(
                "[FAIL] [ImportEncapsulation:inbound] " & path & ":" & $lineNum & ": " & stripped)
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)

  if result.violations.len > 0:
    result.passed = false

# ── 2. SRP Import-Prefix Gate ────────────────────────────────────────────────
# Previously: config.nims lines 189-228
# Files must import from ≤3 distinct domain prefixes.
# Reads pre-computed counts from data/architecture_debt.json (zero shell overhead).

proc checkSrpImportPrefix*(): CheckResult {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## SRP Import-Prefix Gate — runtime equivalent.
  ## Checks that no file imports from more than 3 distinct domain prefixes.
  result = CheckResult(passed: true, violations: @[])

  const debtPath = "data/architecture_debt.json"
  const maxPrefixes = 3

  if not fileExists(debtPath):
    result.violations.add(
      "[WARN] [SRP] (bootstrap) architecture_debt.json not found — skipping SRP check")
    result.passed = true  # Warning only in bootstrap mode
    return

  try:
    let debtJson = parseJson(readFile(debtPath))

    # Build exempt set from "exempt" key (grandfathered legacy violations).
    # BUG FIX: Previously built from same "entries" array being checked,
    # making `file in debtFiles` always true — gate could never fail.
    var exemptFiles: seq[string] = @[]
    if debtJson.hasKey("exempt") and debtJson["exempt"].kind == JArray:
      for item in debtJson["exempt"]:
        exemptFiles.add(item.getStr())

    # Check entries with count > maxPrefixes against exempt list
    var legacyCount = 0
    for entry in debtJson["entries"]:
      let file = entry["file"].getStr()
      let count = entry["count"].getInt()
      if count > maxPrefixes:
        if file in exemptFiles:
          # Legacy exempt — file grandfathered in debt registry
          legacyCount += 1
        else:
          # New file violation NOT in exempt list → ERROR
          result.violations.add(
            "[FAIL] [SRP] NEW FILE must have ≤" & $maxPrefixes &
            " domain prefixes: " & file & ": " & $count & " prefixes")

    if legacyCount > 0:
      result.violations.add(
        "[WARN] [SRP] (legacy) " & $legacyCount & " file(s) with >" &
        $maxPrefixes & " prefixes (grandfathered in exempt list)")

  except CatchableError:
    result.violations.add("[WARN] [SRP] Failed to parse architecture_debt.json")

  if result.violations.len > 0:
    # Check if any violation is an actual error (not just a warning)
    for v in result.violations:
      if v.startsWith("[FAIL]"):
        result.passed = false
        break

# ── 3. Golden Data Integrity Gate ────────────────────────────────────────────
# Previously: config.nims lines 230-244
# Verifies data/golden/ files are committed and match current HEAD.

proc checkGoldenDataIntegrity*(): CheckResult {.tags: [AxiomIOEffect, IOEffect, RootEffect], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Golden Data Integrity Gate — runtime equivalent.
  ## Verifies data/golden/ files are committed and match HEAD.
  result = CheckResult(passed: true, violations: @[])

  if not dirExists("data/golden/"):
    result.violations.add("[WARN] [GoldenData] data/golden/ directory not found")
    return

  # Check for uncommitted changes
  try:
    let (goldenDirty, exitCode) = git_operations.runGit("status --porcelain data/golden/")
    if exitCode == 0 and goldenDirty.strip().len > 0:
      result.violations.add(
        "[FAIL] [GoldenData] data/golden/ has uncommitted changes:\n" &
        goldenDirty)
  except CatchableError:
    result.violations.add("[WARN] [GoldenData] git status failed")

  # Check for differences from HEAD
  try:
    let (goldenDiff, exitCode) = git_operations.runGit("diff --name-only HEAD -- data/golden/")
    if exitCode == 0 and goldenDiff.strip().len > 0:
      result.violations.add(
        "[FAIL] [GoldenData] golden data differs from HEAD:\n" &
        goldenDiff)
  except CatchableError:
    result.violations.add("[WARN] [GoldenData] git diff failed")

  if result.violations.len > 0:
    for v in result.violations:
      if v.startsWith("[FAIL]"):
        result.passed = false
        break

# ── 4. Guard the Guard — Architecture Invariants Integrity ───────────────────
# Previously: config.nims lines 276-300
# Verifies that architecture_invariants.nim has not been tampered with.

proc checkGuardTheGuard*(): CheckResult {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Guard the Guard — runtime equivalent.
  ## Verifies architecture_invariants.nim SHA256 matches expected hash.
  result = CheckResult(passed: true, violations: @[])

  const hashFile = "data/expected_invariant_hash.txt"
  const invariantPath = "src/core/trusted/architecture_invariants.nim"

  if not fileExists(hashFile):
    result.violations.add("[WARN] [GuardTheGuard] expected_invariant_hash.txt not found")
    return

  if not fileExists(invariantPath):
    result.violations.add("[FAIL] [GuardTheGuard] architecture_invariants.nim not found")
    result.passed = false
    return

  try:
    let expectedHash = readFile(hashFile).strip()
    if expectedHash.len == 0:
      result.violations.add("[WARN] [GuardTheGuard] expected hash file is empty")
      return

    let (output, exitCode) = execCmdEx("sha256sum " & invariantPath)
    if exitCode == 0:
      let stripped = output.strip()
      if stripped.len == 0:
        result.violations.add("[WARN] [GuardTheGuard] sha256sum returned empty output")
      else:
        let actualHash = stripped.split(' ')[0]
        if actualHash != expectedHash:
          result.violations.add(
            "[FAIL] [GuardTheGuard] architecture_invariants.nim hash mismatch!\n" &
            "  Expected: " & expectedHash & "\n" &
            "  Actual:   " & actualHash & "\n" &
            "  If you intentionally modified the invariants, " &
            "update data/expected_invariant_hash.txt")
          result.passed = false
    else:
      result.violations.add("[WARN] [GuardTheGuard] sha256sum command failed")
  except CatchableError as e:
    result.violations.add("[WARN] [GuardTheGuard] error: " & e.msg)

# ── Aggregate Runner ─────────────────────────────────────────────────────────

proc runAllChecks*(): CheckResult {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Run all four checks and aggregate results.
  ## Returns combined CheckResult with all violations.
  result = CheckResult(passed: true, violations: @[])

  let importCheck = checkImportEncapsulation()
  if not importCheck.passed: result.passed = false
  result.violations.add(importCheck.violations)

  let srpCheck = checkSrpImportPrefix()
  if not srpCheck.passed: result.passed = false
  result.violations.add(srpCheck.violations)

  let goldenCheck = checkGoldenDataIntegrity()
  if not goldenCheck.passed: result.passed = false
  result.violations.add(goldenCheck.violations)

  let guardCheck = checkGuardTheGuard()
  if not guardCheck.passed: result.passed = false
  result.violations.add(guardCheck.violations)

# ── Main Entry Point ─────────────────────────────────────────────────────────

proc main() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Standalone entry point — run all checks and exit with appropriate code.
  let checkName = getEnv("AXIOM_CHECK", "all")
  var result: CheckResult

  case checkName
  of "import-encapsulation":
    result = checkImportEncapsulation()
  of "srp":
    result = checkSrpImportPrefix()
  of "golden-data":
    result = checkGoldenDataIntegrity()
  of "guard-the-guard":
    result = checkGuardTheGuard()
  else:
    result = runAllChecks()

  if not result.passed:
    for v in result.violations:
      stderr.writeLine(GateTag, " ", v)
    quit(1)
  else:
    # Print warnings even on pass
    for v in result.violations:
      stderr.writeLine(GateTag, " ", v)
    stderr.writeLine(GateTag, " PASS — All checks passed")
    quit(0)

when isMainModule:
  main()

{.pop.}
