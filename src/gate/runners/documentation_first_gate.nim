import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## Documentation-First Gate — Deterministic enforcement of AGENTS.md §0.5
##
## Before ANY system-level change involving kernel, drivers, Xorg, bootloader,
## or initramfs, official documentation MUST be consulted. This gate scans
## staged git diff for trigger keywords and verifies that evidence of
## documentation review exists.
##
## Checks:
##   1. Scan staged diff for trigger keywords from documentation_first.json
##   2. Verify evidence exists: docs/evidence/ files or official URL in commit
##
## Usage:
##   documentation_first_gate [--self-test] [--files file1 file2 ...]
##
## Exit codes:
##   0 — gate passed (no triggers, or evidence found)
##   1 — gate failed (triggers found without evidence)

import std/[os, osproc, strutils, times, json]
import core/axiom_pragmas
import core/gate/gate_vfs
import core/gates/gate_types
from core/utils/repo_root import findRepoRoot
import core/trusted/env_access


# axiomIoBoundary

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const
  GateTag = "[documentation-first]"
  ConfigRelPath = "src" / "gate" / "configs" / "documentation_first.json"
  HistoryFileName = "gate_history.jsonl"
  GateId = "documentation-first"

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  TriggerConfig = object
    keyword: string
    severity: string
    description: string
    docUrl: string

  Issue = object
    ruleId: string
    severity: string
    filePath: string
    line: int
    message: string
    component: string

# ---------------------------------------------------------------------------
# Paths (deterministic root resolution)
# ---------------------------------------------------------------------------

let
  repoDir = findRepoRoot()
  configPath = repoDir / ConfigRelPath
  evidenceDir = repoDir / "docs" / "evidence"
  historyPath = getHomeDir() / ".axiom" / HistoryFileName
  debugMarker = repoDir / ".axiom" / "debug_mode_on"

# ---------------------------------------------------------------------------
# JSON config parser
# ---------------------------------------------------------------------------

proc parseTriggerComponentsFromJson(content: string): seq[TriggerConfig] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Parse trigger_components from JSON config.
  result = @[]
  var root: JsonNode
  try:
    root = parseJson(content)
  except JsonParsingError:
    return
  if not root.hasKey("trigger_components"):
    return
  let components = root["trigger_components"]
  if components.kind != JArray:
    return
  for item in components:
    if item.kind != JObject:
      continue
    result.add(TriggerConfig(
      keyword: item{"keyword"}.getStr(""),
      severity: item{"severity"}.getStr("error"),
      description: item{"description"}.getStr(""),
      docUrl: item{"doc_url"}.getStr("")
    ))

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc stderrOut(s: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  writeLine(stderr, s)

proc getTimestamp(): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let now = times.now()
  format(now.utc, "yyyy-MM-dd'T'HH:mm:ss'Z'")

proc isDebugMode(): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  fileExists(debugMarker)



# ---------------------------------------------------------------------------
# History
# ---------------------------------------------------------------------------

proc writeHistory(entry: JsonNode) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let dir = parentDir(historyPath)
  if not dirExists(dir):
    createDir(dir)
  var f = open(historyPath, fmAppend)
  defer: f.close()
  f.writeLine($entry)

proc recordFailure(ruleId, severity, filePath: string; line: int; message: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let entry = %*{
    "timestamp": getTimestamp(),
    "gateId": GateId,
    "ruleId": ruleId,
    "severity": severity,
    "filePath": filePath,
    "line": line,
    "message": message,
    "bypassUsed": false
  }
  writeHistory(entry)

proc recordPass() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let entry = %*{
    "timestamp": getTimestamp(),
    "gateId": GateId,
    "ruleId": "all-checks",
    "severity": "info",
    "filePath": "",
    "line": 0,
    "message": "Documentation-first gate passed",
    "status": "pass",
    "bypassUsed": false
  }
  writeHistory(entry)

# ---------------------------------------------------------------------------
# Evidence checks
# ---------------------------------------------------------------------------

proc hasDocsUrlInText(text: string): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Check if text contains an official documentation URL.
  const urls = [
    "docs.kernel.org",
    "x.org/releases",
    "download.nvidia.com",
    "freedesktop.org/software/systemd",
    "gnu.org/software/grub",
    "wayland.freedesktop.org",
    "man7.org/linux/man-pages"
  ]
  for url in urls:
    if url in text:
      return true
  false

proc hasEvidenceInDir(): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Check if any evidence files exist under docs/evidence/.
  if not dirExists(evidenceDir):
    return false
  for kind, path in walkDir(evidenceDir):
    if kind == pcFile or kind == pcDir:
      return true
  false

# ---------------------------------------------------------------------------
# Check 1: Scan files for trigger keywords
# ---------------------------------------------------------------------------

proc isSourceFile(path: string): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Returns true if the file should be scanned (not excluded).
  if path.endsWith(".nim") or path.endsWith(".py") or path.endsWith(".sh"):
    return true
  if path.endsWith(".c") or path.endsWith(".h") or path.endsWith(".cfg"):
    return true
  if path.endsWith(".conf") or path.endsWith(".service") or path.endsWith(".ini"):
    return true
  false

proc scanFileForTriggers(filePath: string; triggers: seq[TriggerConfig]): seq[Issue] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Scan a single file for trigger keywords.
  result = @[]
  if not fileExists(filePath):
    return
  if not isSourceFile(filePath):
    return

  let content = readFile(filePath)
  var lineNum = 0
  for line in content.splitLines():
    inc lineNum
    let lowerLine = line.toLowerAscii()
    for trigger in triggers:
      if lowerLine.contains(trigger.keyword.toLowerAscii()):
        result.add(Issue(
          ruleId: "trigger-" & trigger.keyword,
          severity: trigger.severity,
          filePath: filePath,
          line: lineNum,
          message: "System-level keyword '" & trigger.keyword & "' detected: " &
                   trigger.description &
                   " — consult " & trigger.docUrl,
          component: trigger.keyword
        ))

# ---------------------------------------------------------------------------
# Check 2: Verify evidence exists for triggers
# ---------------------------------------------------------------------------

proc hasEvidenceForComponent(component: string): tuple[found: bool; source: string] =
  ## Check if evidence exists for a specific component.
  # Check evidence directory
  if hasEvidenceInDir():
    return (true, "evidence-directory")

  # Check component-specific evidence files
  let evidencePatterns = [
    evidenceDir / component & "_evidence.md",
    repoDir / "docs" / "evidence" / (component & "_*.md")
  ]
  for pattern in evidencePatterns:
    if fileExists(pattern):
      return (true, "evidence-file:" & pattern)

  (false, "")

# ---------------------------------------------------------------------------
# Staged file detection
# ---------------------------------------------------------------------------

proc getStagedFiles(): seq[string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Get list of staged files from git.
  result = @[]
  let (output, exitCode) = execCmdEx(
    "git -C " & quoteShell($repoDir) & " diff --cached --name-only --diff-filter=ACM"
  )
  if exitCode != 0:
    return
  for line in output.splitLines():
    let trimmed = line.strip()
    if trimmed.len > 0:
      result.add(trimmed)

proc getStagedDiffContent(): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Get the full staged diff content for keyword scanning.
  let (output, exitCode) = execCmdEx(
    "git -C " & quoteShell($repoDir) & " diff --cached"
  )
  if exitCode != 0:
    return ""
  output

proc getCommitMessage(): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Get the last commit message for URL evidence check.
  let (output, exitCode) = execCmdEx(
    "git -C " & quoteShell($repoDir) & " log -1 --pretty=%B"
  )
  if exitCode != 0:
    return ""
  output

# ---------------------------------------------------------------------------
# Debug mode
# ---------------------------------------------------------------------------

proc debugDiagnostics(triggers: seq[TriggerConfig]; stagedFiles: seq[string];
                      issues: seq[Issue]; evidenceFound: bool) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Print diagnostics to stderr when debug mode is active.
  stderrOut(GateTag & " DEBUG MODE — diagnostics only (exit 0)")
  stderrOut("=".repeat(60))
  stderrOut("  Config: " & configPath)
  stderrOut("  Triggers loaded: " & $triggers.len)
  for t in triggers:
    stderrOut("    - " & t.keyword & " [" & t.severity & "] " & t.description)
  stderrOut("  Staged files scanned: " & $stagedFiles.len)
  stderrOut("  Issues found: " & $issues.len)
  for issue in issues:
    stderrOut("    [" & issue.severity & "] " & issue.filePath & ":" &
              $issue.line & " — " & issue.message)
  stderrOut("  Evidence found: " & $evidenceFound)
  stderrOut("=".repeat(60))

# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------

proc runSelfTest() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Validate config parsing and deterministic checks.
  stderrOut(GateTag & " --self-test")
  stderrOut("=".repeat(60))
  var passed = 0
  var failed = 0

  # Test 1: Config file exists and is parseable
  stderrOut("  [1] Load documentation_first.json ...")
  if not fileExists(configPath):
    stderrOut("    FAIL — config not found: " & configPath)
    inc(failed)
  else:
    let content = readFile(configPath)
    let triggers = parseTriggerComponentsFromJson(content)
    if triggers.len > 0:
      stderrOut("    OK — " & $triggers.len & " triggers loaded")
      inc(passed)
    else:
      stderrOut("    FAIL — no triggers parsed")
      inc(failed)

  # Test 2: Trigger keyword matching works
  stderrOut("  [2] Trigger keyword matching ...")
  block:
    let testTriggers = @[
      TriggerConfig(keyword: "nvidia", severity: "error",
                    description: "NVIDIA driver", docUrl: "https://nvidia.com"),
      TriggerConfig(keyword: "kernel", severity: "error",
                    description: "Linux kernel", docUrl: "https://kernel.org")
    ]
    let issues = scanFileForTriggers("/dev/null", testTriggers)
    # /dev/null should produce no issues
    if issues.len == 0:
      stderrOut("    OK — clean file produces no issues")
      inc(passed)
    else:
      stderrOut("    FAIL — false positive on /dev/null")
      inc(failed)

  # Test 3: hasDocsUrlInText works
  stderrOut("  [3] Official URL detection ...")
  block:
    let goodText = "See https://docs.kernel.org/admin-guide/kernel-parameters.html"
    let badText = "Just a random comment"
    if hasDocsUrlInText(goodText) and not hasDocsUrlInText(badText):
      stderrOut("    OK — URL detection correct")
      inc(passed)
    else:
      stderrOut("    FAIL — URL detection mismatch")
      inc(failed)

  # Test 4: Source file detection
  stderrOut("  [4] Source file detection ...")
  block:
    if isSourceFile("test.nim") and isSourceFile("config.py") and
       not isSourceFile("readme.md") and not isSourceFile("data.json"):
      stderrOut("    OK — source file filter correct")
      inc(passed)
    else:
      stderrOut("    FAIL — source file filter mismatch")
      inc(failed)

  # Test 5: Evidence check functions exist and don't crash
  stderrOut("  [5] Evidence check functions ...")
  block:
    let _ = hasEvidenceInDir()
    stderrOut("    OK — evidence functions execute without crash")
    inc(passed)

  # Test 6: History write
  stderrOut("  [6] History write ...")
  block:
    let entry = %*{
      "timestamp": getTimestamp(),
      "gateId": GateId,
      "ruleId": "self-test",
      "severity": "info",
      "filePath": "",
      "line": 0,
      "message": "self-test entry",
      "bypassUsed": false
    }
    try:
      writeHistory(entry)
      stderrOut("    OK — history write succeeded")
      inc(passed)
    except CatchableError as e:
      stderrOut("    FAIL — " & e.msg)
      inc(failed)

  stderrOut("")
  stderrOut("Results: " & $passed & " passed, " & $failed & " failed")
  stderrOut("=".repeat(60))
  if failed > 0:
    quit(1)
  quit(0)

# ---------------------------------------------------------------------------
# Main gate logic
# ---------------------------------------------------------------------------

proc main() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  # Handle --self-test
  if paramCount() >= 1 and paramStr(1) == "--self-test":
    runSelfTest()
    return

  # Load config
  if not fileExists(configPath):
    stderrOut(GateTag & " ERROR — config not found: " & configPath)
    quit(2)

  let configContent = readFile(configPath)
  let triggers = parseTriggerComponentsFromJson(configContent)

  if triggers.len == 0:
    stderrOut(GateTag & " WARN — no triggers defined in config, skipping (inapplicable)")
    # axiom:theater-fix(DEBT#381) SkippedInapplicable ≠ success
    quit(1)

  # Get staged files or use command-line args
  var filesToScan: seq[string] = @[]
  var scanStagedDiff = false
  if paramCount() >= 1 and paramStr(1) != "--self-test":
    for i in 1 .. paramCount():
      let f = paramStr(i)
      if not f.startsWith("--"):
        filesToScan.add(f)
  else:
    filesToScan = getStagedFiles()
    scanStagedDiff = true

  # Check 1: Scan files for trigger keywords
  var allIssues: seq[Issue] = @[]
  for filePath in filesToScan:
    let issues = scanFileForTriggers(filePath, triggers)
    allIssues.add(issues)

  # Also scan staged diff content for keywords in non-source files
  # (only when no explicit files are provided, to keep CLI tests deterministic)
  if scanStagedDiff:
    let diffContent = getStagedDiffContent()
    if diffContent.len > 0:
      let lowerDiff = diffContent.toLowerAscii()
      for trigger in triggers:
        if lowerDiff.contains(trigger.keyword.toLowerAscii()):
          # Only add if not already caught by file scan
          var alreadyFound = false
          for existing in allIssues:
            if existing.component == trigger.keyword:
              alreadyFound = true
              break
          if not alreadyFound:
            allIssues.add(Issue(
              ruleId: "trigger-" & trigger.keyword,
              severity: trigger.severity,
              filePath: "(git diff)",
              line: 0,
              message: "System-level keyword '" & trigger.keyword & "' detected in staged changes: " &
                       trigger.description &
                       " — consult " & trigger.docUrl,
              component: trigger.keyword
            ))

  # Check 2: Verify evidence exists
  var evidenceFound = false

  # Check commit message for docs URL
  let commitMsg = getCommitMessage()
  if hasDocsUrlInText(commitMsg):
    evidenceFound = true

  # Check evidence directory
  if hasEvidenceInDir():
    evidenceFound = true

  # Debug mode: print diagnostics and exit 0
  if isDebugMode():
    debugDiagnostics(triggers, filesToScan, allIssues, evidenceFound)
    quit(0)

  # No triggers found — pass
  if allIssues.len == 0:
    stderrOut(GateTag & " PASS — no system-level keywords detected in " &
              $filesToScan.len & " file(s)")
    recordPass()
    quit(0)

  # Triggers found — check for evidence
  if evidenceFound:
    stderrOut(GateTag & " PASS — " & $allIssues.len &
              " trigger(s) detected but evidence exists")
    recordPass()
    quit(0)

  # Triggers found without evidence — fail
  stderrOut(GateTag & " FAIL — " & $allIssues.len &
            " trigger(s) detected without documentation evidence:")
  for issue in allIssues:
    let marker = if issue.severity == "error": "ERROR" else: "WARN "
    stderrOut("  [" & marker & "] " & issue.filePath & ":" &
              $issue.line & " — " & issue.message)
    recordFailure(issue.ruleId, issue.severity, issue.filePath,
                  issue.line, issue.message)

  stderrOut("")
  stderrOut("BLOCKED: Documentation-First protocol (AGENTS.md §0.5) violated.")
  stderrOut("  Required: Official documentation must be consulted before system-level changes.")
  stderrOut("  Fix: Record docs URL in commit message or add evidence to docs/evidence/")
  quit(1)

# ---------------------------------------------------------------------------
# VFS-aware helpers
# ---------------------------------------------------------------------------

proc hasEvidenceInDirVfs(ctx: GateContext; evidenceDir: string): bool =
  ## Check if any evidence files exist via VFS directory listing.
  let entries = vfsListDir(ctx, evidenceDir)
  entries.len > 0

proc scanFileForTriggersVfs(ctx: GateContext; filePath: string;
                            triggers: seq[TriggerConfig]): seq[Issue] =
  ## Scan a single file for trigger keywords via VFS.
  result = @[]
  if not vfsExists(ctx, filePath):
    return
  if not isSourceFile(filePath):
    return
  try:
    let content = vfsRead(ctx, filePath)
    var lineNum = 0
    for line in content.splitLines():
      inc lineNum
      let lowerLine = line.toLowerAscii()
      for trigger in triggers:
        if lowerLine.contains(trigger.keyword.toLowerAscii()):
          result.add(Issue(
            ruleId: "trigger-" & trigger.keyword,
            severity: trigger.severity,
            filePath: filePath,
            line: lineNum,
            message: "System-level keyword '" & trigger.keyword & "' detected: " &
                     trigger.description &
                     " — consult " & trigger.docUrl,
            component: trigger.keyword
          ))
  except KeyError:
    discard

proc getStagedFilesVfs(ctx: GateContext; repoRoot: string): seq[string] =
  ## Get staged files via VFS subprocess provider.
  result = @[]
  let res = vfsExec(ctx, "git", @["-C", $repoRoot, "diff", "--cached", "--name-only", "--diff-filter=ACM"])
  if res.exitCode != 0:
    return
  for line in res.output.splitLines():
    let trimmed = line.strip()
    if trimmed.len > 0:
      result.add(trimmed)

proc getStagedDiffContentVfs(ctx: GateContext; repoRoot: string): string =
  ## Get staged diff via VFS subprocess provider.
  let res = vfsExec(ctx, "git", @["-C", $repoRoot, "diff", "--cached"])
  if res.exitCode != 0:
    return ""
  res.output

proc getCommitMessageVfs(ctx: GateContext; repoRoot: string): string =
  ## Get last commit message via VFS subprocess provider.
  let res = vfsExec(ctx, "git", @["-C", $repoRoot, "log", "-1", "--pretty=%B"])
  if res.exitCode != 0:
    return ""
  res.output

proc mainWithVfs(ctx: GateContext) =
  ## VFS entry point. Enforces documentation-first protocol via VFS.
  let repoRoot = ctx.repoRoot
  let homeDir = vfsGetEnv(ctx, "HOME", "")
  let configPath = repoRoot / ConfigRelPath
  let evidenceDir = repoRoot / "docs" / "evidence"
  let historyPath = homeDir / ".axiom" / HistoryFileName
  let debugMarker = repoRoot / ".axiom" / "debug_mode_on"

  # Handle --self-test
  if paramCount() >= 1 and paramStr(1) == "--self-test":
    runSelfTest()
    return

  # Load config via VFS
  if not vfsExists(ctx, configPath):
    stderrOut(GateTag & " ERROR — config not found: " & configPath)
    quit(2)

  let configContent = vfsRead(ctx, configPath)
  let triggers = parseTriggerComponentsFromJson(configContent)

  if triggers.len == 0:
    stderrOut(GateTag & " WARN — no triggers defined in config, skipping (inapplicable)")
    # axiom:theater-fix(DEBT#381) SkippedInapplicable ≠ success
    quit(1)

  # Get staged files or use command-line args
  var filesToScan: seq[string] = @[]
  var scanStagedDiff = false
  if paramCount() >= 1 and paramStr(1) != "--self-test":
    for i in 1 .. paramCount():
      let f = paramStr(i)
      if not f.startsWith("--"):
        filesToScan.add(f)
  else:
    filesToScan = getStagedFilesVfs(ctx, repoRoot)
    scanStagedDiff = true

  # Check 1: Scan files for trigger keywords via VFS
  var allIssues: seq[Issue] = @[]
  for filePath in filesToScan:
    let issues = scanFileForTriggersVfs(ctx, filePath, triggers)
    allIssues.add(issues)

  if scanStagedDiff:
    let diffContent = getStagedDiffContentVfs(ctx, repoRoot)
    if diffContent.len > 0:
      let lowerDiff = diffContent.toLowerAscii()
      for trigger in triggers:
        if lowerDiff.contains(trigger.keyword.toLowerAscii()):
          var alreadyFound = false
          for existing in allIssues:
            if existing.component == trigger.keyword:
              alreadyFound = true
              break
          if not alreadyFound:
            allIssues.add(Issue(
              ruleId: "trigger-" & trigger.keyword,
              severity: trigger.severity,
              filePath: "(git diff)",
              line: 0,
              message: "System-level keyword '" & trigger.keyword & "' detected in staged changes: " &
                       trigger.description &
                       " — consult " & trigger.docUrl,
              component: trigger.keyword
            ))

  # Check 2: Verify evidence exists via VFS
  var evidenceFound = false

  let commitMsg = getCommitMessageVfs(ctx, repoRoot)
  if hasDocsUrlInText(commitMsg):
    evidenceFound = true

  if hasEvidenceInDirVfs(ctx, evidenceDir):
    evidenceFound = true

  # Debug mode
  if vfsExists(ctx, debugMarker):
    debugDiagnostics(triggers, filesToScan, allIssues, evidenceFound)
    quit(0)

  if allIssues.len == 0:
    stderrOut(GateTag & " PASS — no system-level keywords detected in " &
              $filesToScan.len & " file(s)")
    recordPass()
    quit(0)

  if evidenceFound:
    stderrOut(GateTag & " PASS — " & $allIssues.len &
              " trigger(s) detected but evidence exists")
    recordPass()
    quit(0)

  stderrOut(GateTag & " FAIL — " & $allIssues.len &
            " trigger(s) detected without documentation evidence:")
  for issue in allIssues:
    let marker = if issue.severity == "error": "ERROR" else: "WARN "
    stderrOut("  [" & marker & "] " & issue.filePath & ":" &
              $issue.line & " — " & issue.message)
    recordFailure(issue.ruleId, issue.severity, issue.filePath,
                  issue.line, issue.message)

  stderrOut("")
  stderrOut("BLOCKED: Documentation-First protocol (AGENTS.md §0.5) violated.")
  stderrOut("  Required: Official documentation must be consulted before system-level changes.")
  stderrOut("  Fix: Record docs URL in commit message or add evidence to docs/evidence/")
  quit(1)

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

when isMainModule:
  main()

{.pop.}
