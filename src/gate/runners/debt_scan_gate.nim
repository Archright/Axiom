import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## debt_scan_gate.nim — Architecture Debt Scan Gate
##
## Scans staged changes for architecture debt violations.
## The gate PASSES when no NEW debt is introduced beyond the established baseline.
##
## Debt indicators checked:
##   1. Bare `except:` clause (no exception type specified)
##   2. Deprecated `tree_sitter_bridge` import
##   3. `check true` always-pass stub pattern
##
## Approved exemptions in docs/DEBT_REGISTRY.md are honored:
##   Lines matching `### [Exemption APPROVED] <path>` exclude the file.
##
## Baseline: open debt entries count from data/debt_registry.json.
##   New debt = any violation in staged files not covered by an exemption.
##   If new debt found AND baseline open count would increase → FAIL.
##
## Thread safety: each gate writes ONLY to its own GateResult — no shared mutable state.
##
## See: Plan v13-Absolute, tests/features/debt_scan_gate.feature

import gate/gate_contract
import gate/gate_types
import gate/utils/gate_safety_macro
import gate/utils/macro_dispatcher
import std/[json, strutils, os, times]

# ─── Debt Indicators ──────────────────────────────────────────────────────

const deprecatedImports* = [
  "tree_sitter_bridge",
]

func containsBareExcept*(content: string): bool {.raises: [].} =
  ## Detect bare `except:` clause — no exception type after the keyword.
  ## Matches "except:" on its own line (possibly preceded by whitespace).
  ## Does NOT match "except CatchableError:" or "except ValueError:".
  let lines = content.split("\n")
  for line in lines:
    let trimmed = line.strip()
    if trimmed.len < 7:
      continue
    if trimmed == "except:":
      return true
    # Also match "except:\n" (line ending with colon, no exception type)
    if trimmed.startsWith("except:") and trimmed.len == 7:
      return true
  return false

func containsDeprecatedImport*(content: string): bool {.raises: [].} =
  ## Detect import of deprecated modules.
  for dep in deprecatedImports:
    if content.contains("import " & dep) or content.contains("import " & dep):
      return true
  return false

func containsAlwaysPassStub*(content: string): bool {.raises: [].} =
  ## Detect `check true` pattern (always-pass stub).
  ## Matches "check true" on its own line.
  let lines = content.split("\n")
  for line in lines:
    let trimmed = line.strip()
    if trimmed == "check true":
      return true
  return false

func relativizePath*(path, base: string): string {.raises: [].} =
  ## Convert an absolute walkDir path into a repo-relative path (`src/...`)
  ## matching the notation used in docs/DEBT_REGISTRY.md exemptions.
  ## Returns the normalized path unchanged when it is not under `base`.
  if path.len > base.len and path.startsWith(base):
    var rel = path[base.len .. ^1]
    if rel.startsWith("/") or rel.startsWith("\\"):
      rel = rel[1 .. ^1]
    return rel
  return path

# ─── Exemption Checking ───────────────────────────────────────────────────

proc loadExemptionText*(repoRoot: string): string {.raises: [CatchableError].} =
  ## Load docs/DEBT_REGISTRY.md content for exemption scanning.
  ## Returns empty string if file is missing (conservative: no exemptions).
  let path = repoRoot / "docs" / "DEBT_REGISTRY.md"
  try:
    result = readFile(path)
  except CatchableError:
    result = ""

func isExempted*(filePath: string, exemptionText: string): bool {.raises: [].} =
  ## Check if a file is listed as an approved exemption in DEBT_REGISTRY.md.
  ## Matches lines like: `### [Exemption APPROVED] src/gate/foo.nim`
  if exemptionText.len == 0:
    return false
  # Normalize path separators so both absolute and relative paths match the
  # repo-relative notation used in DEBT_REGISTRY.md (`src/...`).
  let normalized = filePath.replace('\\', '/')
  let marker = "### [Exemption APPROVED] " & normalized
  return exemptionText.contains(marker)

# ─── Baseline Loading ─────────────────────────────────────────────────────

proc countOpenDebtEntries*(repoRoot: string): int {.raises: [CatchableError].} =
  ## Count open entries in data/debt_registry.json.
  ## An entry is open if status is NOT "closed" and NOT "REMEDIATED".
  ## Returns 0 if the JSON file is missing or unparseable (conservative).
  let path = repoRoot / "data" / "debt_registry.json"
  try:
    let content = readFile(path)
    let root = parseJson(content)
    let entries = root{"entries"}
    if entries.isNil or entries.kind != JArray:
      return 0
    for entry in entries.items:
      let status = entry{"status"}
      if not status.isNil and status.kind == JString:
        let s = status.getStr()
        if s != "closed" and s != "REMEDIATED" and s != "CLOSED":
          result += 1
  except CatchableError:
    result = 0

# ─── Single-File Scan ─────────────────────────────────────────────────────

proc scanFileForDebt*(filePath: string): tuple[hasDebt: bool, reasons: seq[string]] {.raises: [CatchableError].} =
  ## Scan a single file for debt indicators.
  ## Returns (hasDebt, list of reasons) — empty reasons = clean.
  result = (false, @[])
  if not filePath.endsWith(".nim"):
    return
  try:
    let content = readFile(filePath)
    if containsBareExcept(content):
      result.hasDebt = true
      result.reasons.add("bare except: clause")
    if containsDeprecatedImport(content):
      result.hasDebt = true
      result.reasons.add("deprecated import")
    if containsAlwaysPassStub(content):
      result.hasDebt = true
      result.reasons.add("check true stub")
  except CatchableError: # axiom:best-effort(readFile failure in debt scan)
    discard

# ─── Public API (tested by debt_scan_gate_feature_test.nim) ────────────────

proc runDebtScan*(repoRoot: string, files: seq[string]): bool {.raises: [CatchableError].} =
  ## Public API: scan files for architecture debt violations.
  ## Returns true (PASS) when no NEW debt is introduced.
  ##
  ## When files is empty, scans all .nim files under repoRoot/src/.
  ## Otherwise scans only the provided file paths.
  let exemptionText = loadExemptionText(repoRoot)
  discard countOpenDebtEntries(repoRoot)
  var filesToScan: seq[string]

  if files.len == 0:
    let srcDir = repoRoot / "src"
    if not dirExists(srcDir):
      return true
    # Scan all .nim files recursively under src/
    proc walkRec(dir: string) =
      for kind, path in walkDir(dir):
        if kind == pcFile and path.endsWith(".nim"):
          filesToScan.add(path)
        elif kind == pcDir:
          walkRec(path)
    if dirExists(srcDir):
      walkRec(srcDir)
  else:
    filesToScan = files

  # Deduplicate and check each file
  var newDebtCount = 0
  var seenFiles: seq[string] = @[]

  for f in filesToScan:
    if f in seenFiles:
      continue
    seenFiles.add(f)
    let relPath = relativizePath(f, repoRoot)
    if isExempted(relPath, exemptionText):
      continue
    let scanResult = if fileExists(f): scanFileForDebt(f) else: (false, @[])
    if scanResult.hasDebt:
      newDebtCount += 1

  # PASS if no new debt found
  if newDebtCount == 0:
    return true

  # FAIL: new debt found — check if this would increase the baseline
  # Conservative: any new debt = FAIL (the change-set introduces debt)
  return false

# ─── Gate Runner Interface ────────────────────────────────────────────────

proc run*(gate: GateConfig, ctx: InProcessGateContext): GateResult {.raises: [CatchableError].} =
  ## Gate runner interface for the in-process dispatch macro.
  ## Scans staged files for architecture debt violations.
  let repoRoot = ctx.repoRoot
  let stagedFiles = ctx.stagedFiles
  let passed = runDebtScan(repoRoot, stagedFiles)

  if passed:
    result = GateResult(
      ok: true,
      name: "debt-scan-gate",
      stdout: "No new architecture debt violations detected.",
      stderr: "",
      duration: initDuration())
  else:
    let exemptionText = loadExemptionText(repoRoot)
    var violationDetails: seq[string] = @[]
    var filesToScan = if stagedFiles.len > 0: stagedFiles else: @[]
    if filesToScan.len == 0:
      let srcDir = repoRoot / "src"
      if dirExists(srcDir):
        proc walkRec(dir: string) =
          for kind, path in walkDir(dir):
            if kind == pcFile and path.endsWith(".nim"):
              filesToScan.add(path)
            elif kind == pcDir:
              walkRec(path)
        walkRec(srcDir)
    for f in filesToScan:
      let relPath = relativizePath(f, repoRoot)
      if isExempted(relPath, exemptionText):
        continue
      let scanResult = if fileExists(f): scanFileForDebt(f) else: (false, @[])
      if scanResult.hasDebt:
        violationDetails.add(f & ": " & scanResult.reasons.join(", "))
    result = GateResult(
      ok: false,
      name: "debt-scan-gate",
      stdout: "New architecture debt violations detected:\n" & violationDetails.join("\n"),
      stderr: "",
      failureCategory: fcValidation,
      failureReason: "Debt baseline exceeded: new violations in " & $violationDetails.len & " file(s)",
      duration: initDuration())

# ─── Compile-Time Registration ───────────────────────────────────────────────
registerGate("debt-scan-gate", run)

# ─── Standalone Entry (DEBT#497 follow-up) ──────────────────────────────────

proc main() {.raises: [CatchableError].} =
  ## Real standalone entry: every AOT link of this module now carries the
  ## actual judgment. Previously the module was registerGate-only, so a
  ## standalone link produced an empty 31,872-byte exit-0 binary — the
  ## subprocess CAS path executed nothing and reported PASS (DEBT#497
  ## measured hollow-CAS shape). The debt-scan-gate id is retired (merged
  ## into debt-integrity-gate) and unwired from manifest.d, so it cannot be
  ## dispatched in-process (DEBT#270 manifest↔runner 1:1 invariant); a real
  ## main is the closure for its hollow-CAS exposure.
  let ctx = InProcessGateContext(
    repoRoot: getCurrentDir(),
    stagedFiles: @[],
    gateId: "debt-scan-gate",
    epoch: 0,
    dirtyHash: "",
    subtreeRoot: "",
    stage: 0,
    maxJobs: 1,
    passFilenames: false,
    effectiveTimeoutMs: 0)
  let res = run(GateConfig(), ctx)
  stdout.write(res.stdout)
  quit(if res.ok: 0 else: 1)

when isMainModule:
  main()

{.pop.}
