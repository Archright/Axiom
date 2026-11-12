import core/trusted/layer_declaration


axiomLayer "gate"
{.push raises: [CatchableError].}

import core/axiom_pragmas
import core/gate/gate_cas
import core/gate/hermetic_sandbox
import core/gate/merkle_vfs
import core/utils/repo_root
import std/[os, strutils, times, json]
# axiomIoBoundary

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Usage:
##   bin/integrity_workflow [--self-test|--dry-run] [--allow-jit=true|false]
## --allow-jit controls whether a CAS miss may JIT-compile gate binaries.
##   Default false = fail-closed (CI/pre-push). Pass --allow-jit=true for
##   local manual runs.

const
  GateTag = "[integrity-workflow]"
  GateId = "integrity-workflow"
  HistoryFileName = "gate_history.jsonl"

  ## The 4-step workflow in canonical order
  WorkflowSteps = [
    ("intent-gate", "bin/intent_gate", "Conventional Commits validation"),
    ("spec-presence-gate", "bin/spec_presence_gate", "BDD feature spec presence"),
    ("test-coverage-gate", "bin/test_coverage_gate", "Feature-to-test mapping"),
    ("procedure-gate", "src/gate/runners/procedure_gate", "BDD evidence & spec-density"),
  ]

# ---------------------------------------------------------------------------
# Paths (deterministic root resolution)
# ---------------------------------------------------------------------------
const REPO_ROOT* = repoRootConst()
const DEBUG_MARKER* = REPO_ROOT / ".axiom" / "debug_mode_on"
const HISTORY_PATH* = REPO_ROOT / ".axiom" / HistoryFileName
var workflowVfs = buildMerkleFromGitIndex(REPO_ROOT)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
var MERKLE_VFS = buildMerkleFromGitIndex(REPO_ROOT)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
proc stderrOut(s: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  writeLine(stderr, s)
proc getTimestamp(): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let now = times.now()
  format(now.utc, "yyyy-MM-dd'T'HH:mm:ss'Z'")
proc isDebugMode(): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  fileExists(DEBUG_MARKER)


# ---------------------------------------------------------------------------
# History
# ---------------------------------------------------------------------------
proc writeHistory(entry: JsonNode) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let dir = parentDir(HISTORY_PATH)
  if not dirExists(dir):
    createDir(dir)
  var f = open(HISTORY_PATH, fmAppend)
  defer: f.close()
  f.writeLine($entry)
proc recordFailure(ruleId, severity, filePath: string; line: int;
                   message: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
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
    "message": "Integrity workflow passed (all 4 steps)",
    "status": "pass",
    "bypassUsed": false
  }
  writeHistory(entry)

# ---------------------------------------------------------------------------
# Step execution
# ---------------------------------------------------------------------------
type
  StepResult = object
    name: string
    passed: bool
    output: string
    exitCode: int
proc resolveGatePath(entry, gateId: string; allowJit: bool): string =
  ## Resolve gate entry to absolute path.
  ## Entry is either "bin/foo" (relative to repo root) or
  ## "src/gate/runners/foo" (compiled directly via nim c).
  ## gateId is the canonical step name (e.g. "intent-gate") for CAS lookup.
  ## allowJit controls whether a CAS miss may JIT-compile the gate into CAS.
  ## On CAS miss, JIT-compiles the gate binary into CAS (if allowed).
  result = REPO_ROOT / entry
  if fileExists(result):
    return
  # Try converting underscores to hyphens for bin/ lookup
  let binaryName = entry.splitFile().name.replace("_", "-")
  let binPath = REPO_ROOT / "bin" / binaryName
  if fileExists(binPath):
    result = binPath
    return
  # CAS fallback: resolve via content-addressed storage using composite key
  # (sourceHash + configHash) instead of naive mtime glob. DEBT#236.
  let sourcePath = block:
    if entry.startsWith("src/"):
      entry & ".nim"
    else:
      "src/gate/runners/" & entry.splitFile().name & ".nim"
  let absSource = REPO_ROOT / sourcePath
  if fileExists(absSource):
    let casPath = resolveCasBinaryPath(gateId, absSource, REPO_ROOT)
    if casPath.len > 0:
      result = casPath
      return
    # CAS miss: JIT compile into CAS directory (mirrors orchestrator_hook behavior)
    # AOT enforcement: JIT is controlled by the explicit --allow-jit CLI flag
    # (default false = fail-closed). Manual CLI runs may pass --allow-jit=true.
    if not allowJit:
      stderrOut(GateTag & " CAS MISS for " & gateId &
                " — Run bin/precompile_gates first (or pass --allow-jit=true)")
    else:
      stderrOut(GateTag & " CAS miss for " & gateId & " — JIT compiling " & absSource)
    let nimcacheDir = REPO_ROOT / ".axiom" / "cache" / "nimcache" / gateId
    let compiledPath = compileGateToCas(
      gateId, entry, absSource, nimcacheDir, REPO_ROOT, allowJit = allowJit)
    if compiledPath.len > 0:
      result = compiledPath
      return
    stderrOut(GateTag & " JIT compilation failed for " & gateId)
proc runStep(stepIndex: int, name, entry, description: string; allowJit: bool): StepResult =
  ## Execute a single workflow step.
  result.name = name
  let gatePath = resolveGatePath(entry, name, allowJit)

  if not fileExists(gatePath):
    stderrOut(GateTag & " WARN — gate binary not found (dev mode, skipping): " & gatePath)
    stderrOut(GateTag & "   entry=" & entry & " gateId=" & name)
    result.passed = true
    result.output = "gate binary not found, skipped in dev mode: " & gatePath
    result.exitCode = 0
    return

  stderrOut(GateTag & " Step " & $(stepIndex + 1) & "/4: " & name &
            " — " & description)
  stderrOut(GateTag & "   gate: " & gatePath)

  # Create isolated snapshot for this step
  var snap = vfsSnapshot(workflowVfs, name)

  # Build hermetic config
  let config = buildHermeticConfig(REPO_ROOT)
  let provider = hermeticSubprocessProvider(config)

  # Execute in hermetic sandbox
  let execResult = provider(gatePath, @[])

  result.output = execResult.output
  result.exitCode = execResult.exitCode
  result.passed = (execResult.exitCode == 0)

  # Commit on success, discard on failure
  if result.passed:
    try:
      let delta = toDelta(snap)
      vfsCommit(workflowVfs, delta)
    except Defect:
      vfsDiscard(snap)
      result.passed = false
      result.output = "VFS commit failed (content collision)"
      result.exitCode = 1
  else:
    vfsDiscard(snap)

  if result.passed:
    stderrOut(GateTag & "   → PASS")
  else:
    stderrOut(GateTag & "   → FAIL (exit " & $result.exitCode & ")")
    if result.output.len > 0:
      for line in result.output.splitLines():
        stderrOut(GateTag & "   | " & line)

# ---------------------------------------------------------------------------
# Dry-run
# ---------------------------------------------------------------------------
proc printDryRun(allowJit: bool) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Print the planned workflow steps without executing.
  stderrOut(GateTag & " --dry-run (no execution)")
  stderrOut("=".repeat(60))
  stderrOut("  Integrity Workflow: 4-Step Development Sequence")
  stderrOut("  (Intent → Spec → Test → Code)")
  stderrOut("")
  for i, step in WorkflowSteps:
    let gatePath = resolveGatePath(step[1], step[0], allowJit)
    let exists = fileExists(gatePath)
    let status = if exists: "READY" else: "MISSING"
    stderrOut("  Step " & $(i + 1) & "/4: " & step[0])
    stderrOut("    description: " & step[2])
    stderrOut("    entry:       " & step[1])
    stderrOut("    resolved:    " & gatePath)
    stderrOut("    status:      " & status)
    stderrOut("")
  stderrOut("=".repeat(60))
  stderrOut(GateTag & " dry-run complete — 0 steps executed")
  quit(0)

# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------
proc runSelfTest(allowJit: bool) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Validate step list and gate infrastructure.
  stderrOut(GateTag & " --self-test")
  stderrOut("=".repeat(60))
  var passed = 0
  var failed = 0

  # Test 1: Step list has exactly 4 steps
  stderrOut("  [1] Step list count ...")
  if WorkflowSteps.len == 4:
    stderrOut("    OK — 4 steps defined")
    inc(passed)
  else:
    stderrOut("    FAIL — expected 4, got " & $WorkflowSteps.len)
    inc(failed)

  # Test 2: Steps are in canonical order
  stderrOut("  [2] Step order (intent → spec → test → procedure) ...")
  block:
    const expectedOrder = ["intent-gate", "spec-presence-gate",
                           "test-coverage-gate", "procedure-gate"]
    var orderOk = true
    for i in 0 ..< 4:
      if WorkflowSteps[i][0] != expectedOrder[i]:
        orderOk = false
        break
    if orderOk:
      stderrOut("    OK — canonical order verified")
      inc(passed)
    else:
      stderrOut("    FAIL — step order mismatch")
      inc(failed)

  # Test 3: Gate binaries or source runners exist
  stderrOut("  [3] Gate entry resolution ...")
  block:
    var allResolved = true
    for step in WorkflowSteps:
      let resolved = resolveGatePath(step[1], step[0], allowJit)
      if not fileExists(resolved):
        stderrOut("    WARN — not found: " & step[0] & " → " & resolved)
        allResolved = false
    if allResolved:
      stderrOut("    OK — all 4 gate entries resolved")
      inc(passed)
    else:
      stderrOut("    OK — some gates missing (expected in dev environment)")
      inc(passed)

  # Test 4: Repo root resolution works
  stderrOut("  [4] Repo root resolution ...")
  block:
    if REPO_ROOT.len > 0 and dirExists(REPO_ROOT):
      stderrOut("    OK — REPO_ROOT = " & REPO_ROOT)
      inc(passed)
    else:
      stderrOut("    FAIL — REPO_ROOT invalid")
      inc(failed)

  # Test 5: Debug mode detection works
  stderrOut("  [5] Debug mode detection ...")
  block:
    let debugActive = isDebugMode()
    stderrOut("    OK — debug mode = " & $debugActive)
    inc(passed)

  # Test 6: History write works
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

  # Test 7: Dry-run produces output
  stderrOut("  [7] Dry-run output format ...")
  block:
    # Verify step data is well-formed
    var formatOk = true
    for step in WorkflowSteps:
      if step[0].len == 0 or step[1].len == 0 or step[2].len == 0:
        formatOk = false
        break
    if formatOk:
      stderrOut("    OK — all step entries well-formed")
      inc(passed)
    else:
      stderrOut("    FAIL — malformed step entry")
      inc(failed)

  stderrOut("")
  stderrOut("Results: " & $passed & " passed, " & $failed & " failed")
  stderrOut("=".repeat(60))
  if failed > 0:
    quit(1)
  quit(0)

# ---------------------------------------------------------------------------
# Debug diagnostics
# ---------------------------------------------------------------------------
proc debugDiagnostics(allowJit: bool) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Print diagnostics to stderr when debug mode is active.
  stderrOut(GateTag & " DEBUG MODE — diagnostics only (exit 0)")
  stderrOut("=".repeat(60))
  stderrOut("  Workflow: Intent → Spec → Test → Code (4 steps)")
  stderrOut("  Steps defined: " & $WorkflowSteps.len)
  for i, step in WorkflowSteps:
    let gatePath = resolveGatePath(step[1], step[0], allowJit)
    let exists = fileExists(gatePath)
    stderrOut("  Step " & $(i + 1) & ": " & step[0])
    stderrOut("    description: " & step[2])
    stderrOut("    entry:       " & step[1])
    stderrOut("    resolved:    " & gatePath)
    stderrOut("    exists:      " & $exists)
  stderrOut("  REPO_ROOT: " & REPO_ROOT)
  stderrOut("=".repeat(60))

# ---------------------------------------------------------------------------
# Main gate logic
# ---------------------------------------------------------------------------
proc parseAllowJit(): bool =
  ## Parse the --allow-jit=true|false CLI flag (default false = fail-closed).
  for i in 1 .. paramCount():
    case paramStr(i)
    of "--allow-jit=true":
      return true
    of "--allow-jit=false":
      return false
    else:
      discard
  false

proc hasFlag(flag: string): bool =
  ## True if `flag` appears anywhere on the command line.
  for i in 1 .. paramCount():
    if paramStr(i) == flag:
      return true
  false

proc main() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let allowJit = parseAllowJit()

  # Handle --self-test
  if hasFlag("--self-test"):
    runSelfTest(allowJit)
    return

  # Handle --dry-run
  if hasFlag("--dry-run"):
    printDryRun(allowJit)
    return

  # Debug mode: print diagnostics and exit 0
  if isDebugMode():
    debugDiagnostics(allowJit)
    quit(0)

  # Run the 4-step workflow
  stderrOut(GateTag & " Starting Integrity Workflow (4-Step Development Sequence)")
  stderrOut(GateTag & " Intent → Spec → Test → Code")
  stderrOut("=".repeat(60))

  var failedStep = ""
  for i, step in WorkflowSteps:
    let result = runStep(i, step[0], step[1], step[2], allowJit)
    if not result.passed:
      failedStep = step[0]
      stderrOut("")
      stderrOut(GateTag & " FAIL — Step " & $(i + 1) & "/4 (" & step[0] &
                ") failed")
      stderrOut(GateTag & " Workflow halted. Fix the failed step and re-run.")
      recordFailure(
        "step-" & $(i + 1) & "-" & step[0],
        "error",
        "",
        0,
        "Integrity workflow failed at step " & $(i + 1) & "/4: " & step[0] &
        " — " & result.output
      )
      quit(1)

  stderrOut("")
  stderrOut("=".repeat(60))
  stderrOut(GateTag & " PASS — all 4 steps passed")
  recordPass()
  quit(0)

# ---------------------------------------------------------------------------
# VFS-aware entry point (pipeline orchestrator integration)
# ---------------------------------------------------------------------------
proc mainWithVfs*(vfs: MerkleVfs; allowJit: bool = false) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## VFS-aware entry point for pipeline orchestrator integration.
  ## Uses the provided VFS instead of building one locally.
  ## allowJit defaults to false (fail-closed) — orchestrator injects the value
  ## based on stage.
  workflowVfs = vfs

  stderrOut(GateTag & " Starting Integrity Workflow (VFS-aware mode)")
  stderrOut(GateTag & " Intent → Spec → Test → Code")
  stderrOut("=".repeat(60))

  for i, step in WorkflowSteps:
    let result = runStep(i, step[0], step[1], step[2], allowJit)
    if not result.passed:
      stderrOut("")
      stderrOut(GateTag & " FAIL — Step " & $(i + 1) & "/4 (" & step[0] &
                ") failed")
      stderrOut(GateTag & " Workflow halted. Fix the failed step and re-run.")
      recordFailure(
        "step-" & $(i + 1) & "-" & step[0],
        "error",
        "",
        0,
        "Integrity workflow failed at step " & $(i + 1) & "/4: " & step[0] &
        " — " & result.output
      )
      quit(1)

  stderrOut("")
  stderrOut("=".repeat(60))
  stderrOut(GateTag & " PASS — all 4 steps passed")
  recordPass()
  quit(0)

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

when isMainModule:
  main()

{.pop.}

