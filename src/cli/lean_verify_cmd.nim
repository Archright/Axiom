import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [].}
# axiomIoBoundary

## Lean Verify CLI — Phase 3B
## Connects `ax prove` to Lean build sandbox verification.
## Wraps `verification/lean_build_sandbox.verifyWithSandbox()` with
## CLI-friendly structured output and error reporting.
##
## AGENTS.md §0.6: proc only at I/O boundary.
## AGENTS.md §0.2: Ideal (compile-time), Elegant (native), Fundamental (no stubs), Deterministic.

import std/json
import std/strutils

import verification/lean_build_sandbox

# ═══════════════════════════════════════════════════════════════════════════════
# Types
# ═══════════════════════════════════════════════════════════════════════════════

type
  LeanVerifyResult* = object
    ## Structured result from Lean sandbox verification for CLI integration.
    success*: bool              ## Whether lake build succeeded without sorry
    sorryFound*: bool           ## Whether sorry was detected in Lean output
    axiomsUsed*: seq[string]    ## Axiom names extracted from build output
    exitCode*: int              ## Process exit code from lake build
    outputJson*: string         ## JSON-serialized verification metadata
    logLines*: seq[string]      ## Human-readable log lines for stderr

  LeanVerifyOutcome* = enum
    ## Exhaustive outcome classification for downstream dispatch.
    leanVerifySuccess,          ## Build succeeded, no sorry found
    leanVerifySorryFound,       ## sorry detected — hard fail
    leanVerifyBuildFailed,      ## lake build returned non-zero exit
    leanVerifySandboxFailed     ## Sandbox creation or execution error

# ═══════════════════════════════════════════════════════════════════════════════
# Pure helpers (func)
# ═══════════════════════════════════════════════════════════════════════════════

func classifyOutcome*(sandboxResult: SandboxResult): LeanVerifyOutcome {.raises: [].} =
  ## Classify a SandboxResult into an exhaustive outcome enum.
  if sandboxResult.exitCode == -1 and not sandboxResult.success:
    leanVerifySandboxFailed
  elif sandboxResult.sorryFound:
    leanVerifySorryFound
  elif not sandboxResult.success:
    leanVerifyBuildFailed
  else:
    leanVerifySuccess

func buildVerificationJson*(leanResult: LeanVerifyResult): string {.raises: [].} =
  ## Serialize verification metadata to JSON string.
  let root = newJObject()
  root["gate"] = %"lean-verify"
  root["success"] = %leanResult.success
  root["sorryFound"] = %leanResult.sorryFound
  root["exitCode"] = %leanResult.exitCode

  var axArr = newJArray()
  for ax in leanResult.axiomsUsed:
    axArr.add(%ax)
  root["axiomsUsed"] = axArr

  try: $root.pretty() except CatchableError: "{}"

func buildLogLines*(sandboxResult: SandboxResult): seq[string] {.raises: [].} =
  ## Generate human-readable log lines from a SandboxResult.
  result = @[]
  let outcome = classifyOutcome(sandboxResult)
  case outcome
  of leanVerifySuccess:
    result.add("[lean-verify] PASS — proofs/ directory builds cleanly")
    if sandboxResult.axiomsUsed.len > 0:
      result.add("[lean-verify] axioms used: " & $sandboxResult.axiomsUsed.len)
  of leanVerifySorryFound:
    result.add("[lean-verify] FAIL — sorry found in proofs/ directory")
    # Include lines containing sorry for diagnostic output
    for line in sandboxResult.compilerOutput.splitLines():
      let stripped = line.strip()
      if stripped.contains("sorry"):
        result.add("  " & stripped)
  of leanVerifyBuildFailed:
    result.add("[lean-verify] FAIL — lake build failed (exit code: " & $sandboxResult.exitCode & ")")
    # Include last 10 lines of compiler output for diagnostics
    let allLines = sandboxResult.compilerOutput.splitLines()
    let startIdx = max(0, allLines.len - 10)
    for i in startIdx ..< allLines.len:
      if allLines[i].len > 0:
        result.add("  " & allLines[i])
  of leanVerifySandboxFailed:
    result.add("[lean-verify] FAIL — sandbox creation/execution error")
    if sandboxResult.compilerOutput.len > 0:
      result.add("  " & sandboxResult.compilerOutput)

# ═══════════════════════════════════════════════════════════════════════════════
# I/O procs
# ═══════════════════════════════════════════════════════════════════════════════

proc runLeanVerify*(timeout: int = DefaultBuildTimeout): LeanVerifyResult =
  ## Execute Lean sandbox verification and produce structured CLI output.
  ##
  ## Flow: verifyWithSandbox() → classify → build output
  ## Always produces a valid LeanVerifyResult, even on catastrophic failure.
  var sandboxResult: SandboxResult
  try:
    sandboxResult = verifyWithSandbox(timeout)
  except CatchableError:
    sandboxResult = SandboxResult(
      success: false,
      compilerOutput: "Exception during sandbox verification",
      exitCode: -1
    )

  let logLines = buildLogLines(sandboxResult)
  let leanResult = LeanVerifyResult(
    success: sandboxResult.success and not sandboxResult.sorryFound,
    sorryFound: sandboxResult.sorryFound,
    axiomsUsed: sandboxResult.axiomsUsed,
    exitCode: sandboxResult.exitCode,
    outputJson: "",  # filled below
    logLines: logLines
  )
  # Serialize the full metadata
  var enrichedResult = leanResult
  enrichedResult.outputJson = buildVerificationJson(leanResult)
  enrichedResult

proc runLeanVerifyWithDir*(proofsDir: string;
 timeout: int = DefaultBuildTimeout): LeanVerifyResult =
  ## Verify a specific proofs directory (for testing/CI).
  ## Creates a sandbox from the given directory path.
  var sandboxResult: SandboxResult
  try:
    let sandbox = createSandboxWithUuid()
    if sandbox.sandboxDir.len == 0:
      sandboxResult = SandboxResult(
        success: false,
        compilerOutput: "Error: failed to create sandbox directory",
        exitCode: -1
      )
    else:
      sandboxResult = buildInSandbox(sandbox, timeout)
      destroySandbox(sandbox)
  except CatchableError:
    sandboxResult = SandboxResult(
      success: false,
      compilerOutput: "Exception during sandbox verification",
      exitCode: -1
    )

  let logLines = buildLogLines(sandboxResult)
  let leanResult = LeanVerifyResult(
    success: sandboxResult.success and not sandboxResult.sorryFound,
    sorryFound: sandboxResult.sorryFound,
    axiomsUsed: sandboxResult.axiomsUsed,
    exitCode: sandboxResult.exitCode,
    outputJson: "",
    logLines: logLines
  )
  var enrichedResult = leanResult
  enrichedResult.outputJson = buildVerificationJson(leanResult)
  enrichedResult

{.pop.}
