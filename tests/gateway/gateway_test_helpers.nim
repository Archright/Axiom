## Shared BDD test infrastructure for the gateway test suite.
## Provides BddCtx, BDD step procs, environment utilities, and external runners.

import std/[unittest, options, os, osproc, strutils, json, asyncdispatch, sequtils, algorithm]

when defined(windows):
  import std/winlean

import core/types/results
import core/gateway/gateway
import core/bmc/bmc_race
import core/api/axiom_api
import core/session/session_parser
import cli/commands/observability
import cli/cli_types

export unittest, options, os, osproc, strutils, json, asyncdispatch, sequtils, algorithm
export cli_types

func observabilityTexts*(observabilityResult: ObservabilityCliResult): seq[string] {.nosideeffect.} =
  observabilityResult.lines

when defined(windows):
  const testUtf8CodePage = 65001'u32

  func setConsoleOutputCP(codePage: cuint): WINBOOL {.
    stdcall, dynlib: "kernel32", importc: "SetConsoleOutputCP".}

  func setConsoleCP(codePage: cuint): WINBOOL {.
    stdcall, dynlib: "kernel32", importc: "SetConsoleCP".}

let testOutputEncodingInitialized {.used.} = block:
  when defined(windows):
    discard setConsoleOutputCP(cuint(testUtf8CodePage))
    discard setConsoleCP(cuint(testUtf8CodePage))
  true

const
  financeInitialState* = 100
  financeInputDelta* = 70

proc countExactLine*(content: string; line: string): int =
  for current in content.splitLines():
    if current == line:
      inc result

func quoteCommandPath(raw: string): string {.nosideeffect.} =
  "\"" & raw.replace("\"", "\"\"") & "\""

proc writeFakeLeanCommand*(tempRoot: string; shouldVerify: bool): string =
  when defined(windows):
    let scriptPath = joinPath(tempRoot, if shouldVerify: "fake_lean_ok.ps1" else: "fake_lean_fail.ps1")
    let scriptBody =
      if shouldVerify:
        "param([string]$artifactPath)\nif ($artifactPath -like "*negative*") { exit 1 }\nexit 0\n"
      else:
        "param([string]$artifactPath)\nWrite-Output ($artifactPath + ':1:1: error: synthetic lean failure')\nexit 1\n"
    writeFile(scriptPath, scriptBody)
    "powershell -NoProfile -ExecutionPolicy Bypass -File " & quoteCommandPath(scriptPath)
  else:
    let scriptPath = joinPath(tempRoot, if shouldVerify: "fake_lean_ok.sh" else: "fake_lean_fail.sh")
    let scriptBody =
      if shouldVerify:
        """#!/bin/bash
if echo "$1" | grep -q "negative"; then
  exit 1
fi
exit 0
"""
      else:
        """#!/bin/bash
echo "$1:1:1: error: synthetic lean failure"
exit 1
"""
    writeFile(scriptPath, scriptBody)
    "bash " & quoteCommandPath(scriptPath)

proc writeFakeLeanGoalFailureCommand*(tempRoot: string): string =
  when defined(windows):
    let scriptPath = joinPath(tempRoot, "fake_lean_unsolved_goals.ps1")
    let scriptBody =
      "param([string]$artifactPath)\n" &
      "Write-Output ($artifactPath + ':1:1: error: unsolved goals')\n" &
      "Write-Output '⊢ Invariant (Transition amount balance)'\n" &
      "Write-Output 'h : amount <= balance'\n" &
      "Write-Output 'goal: balance >= 0'\n" &
      "exit 1\n"
    writeFile(scriptPath, scriptBody)
    "powershell -NoProfile -ExecutionPolicy Bypass -File " & quoteCommandPath(scriptPath)
  else:
    let scriptPath = joinPath(tempRoot, "fake_lean_unsolved_goals.sh")
    let scriptBody =
      "#!/bin/bash\n" &
      "echo \"$1:1:1: error: unsolved goals\"\n" &
      "echo '⊢ Invariant (Transition amount balance)'\n" &
      "echo 'h : amount <= balance'\n" &
      "echo 'goal: balance >= 0'\n" &
      "exit 1\n"
    writeFile(scriptPath, scriptBody)
    "bash " & quoteCommandPath(scriptPath)

proc runExternalNimCheck*(workingDir: string; sourceFileName: string): tuple[output: string, exitCode: int] =
  execCmdEx(
    "nim check --hints:off " & quoteCommandPath(sourceFileName),
    workingDir = workingDir
  )

proc runExternalNimProgram*(workingDir: string; sourceFileName: string): tuple[output: string, exitCode: int] =
  execCmdEx(
    "nim c -r --hints:off --verbosity:0 " & quoteCommandPath(sourceFileName),
    workingDir = workingDir
  )

proc runFinanceReferenceBmc*(): BmcVerdict {.raises: [].} =
  verifyRaceConditionWithDelta(financeInitialState, financeInputDelta)

proc verifyFinanceReferenceRace*(): Result[BmcVerificationResponse, AxiomError] {.raises: [].} =
  axiom_api.verifyRaceCondition(financeInitialState, financeInputDelta)

proc envSnapshot*(name: string): Option[string] =
  if existsEnv(name):
    some(getEnv(name))
  else:
    none(string)

proc restoreEnv*(name: string; value: Option[string]) =
  if value.isSome():
    putEnv(name, value.get())
  else:
    delEnv(name)

type
  BddCtx* = object
    sessionJson*: string
    proofJson*: string
    storedSessionId*: string
    lastCapture*: Result[CaptureSessionResponse, AxiomError]
    lastGenerateProof*: Result[GenerateProofResponse, AxiomError]
    lastInspectTrace*: Result[InspectTraceResponse, AxiomError]
    lastExportProof*: Result[ExportProofResponse, AxiomError]
    lastTarget*: string

proc givenAxiomSessionRequest*(ctx: var BddCtx; json: string) =
  ctx.sessionJson = json

proc givenProofArtifact*(ctx: var BddCtx; json: string) =
  ctx.proofJson = json

proc givenStoredSessionId*(ctx: var BddCtx; sessionId: string) =
  ctx.storedSessionId = sessionId

proc whenCaptureSessionCalled*(ctx: var BddCtx) =
  ctx.lastCapture = captureSession(ctx.sessionJson)
  if ctx.lastCapture.isOk():
    ctx.storedSessionId = ctx.lastCapture.get().sessionId

proc whenGenerateProofCalledWithSessionId*(ctx: var BddCtx) =
  ctx.lastGenerateProof = generateProofFromSessionId(ctx.storedSessionId)

proc whenGenerateProofCalledWithSession*(ctx: var BddCtx) =
  ctx.lastGenerateProof = generateProofFromSession(ctx.sessionJson)

proc whenInspectTraceCalled*(ctx: var BddCtx) =
  ctx.lastInspectTrace = inspectTrace(ctx.proofJson)

proc whenExportProofCalled*(ctx: var BddCtx; target: string; simulateNetworkFailure: bool = false) =
  ctx.lastTarget = target
  ctx.lastExportProof = exportProof(ctx.proofJson, target, simulateNetworkFailure)

proc thenStoredIsTrue*(ctx: BddCtx) =
  check ctx.lastCapture.isOk()
  check ctx.lastCapture.get().stored == true

proc thenResponseHasSessionId*(ctx: BddCtx) =
  check ctx.lastCapture.isOk()
  check ctx.lastCapture.get().sessionId.len > 0

proc thenResponseHasProof*(ctx: BddCtx) =
  check ctx.lastGenerateProof.isOk()
  check verdictString(ctx.lastGenerateProof.get().proof.verdict).len > 0
  check traceRefString(ctx.lastGenerateProof.get().proof.witness.traceRef).len > 0
  check certificateIdString(ctx.lastGenerateProof.get().proof.certificate.id).len > 0

proc thenResponseHasTraceUrl*(ctx: BddCtx) =
  check ctx.lastInspectTrace.isOk()
  check ctx.lastInspectTrace.get().traceUrl.len > 0
  check ctx.lastInspectTrace.get().traceRef.len > 0

proc thenResponseHasWitnessTraceRef*(ctx: BddCtx; expected: string) =
  check ctx.lastInspectTrace.isOk()
  check ctx.lastInspectTrace.get().traceRef == expected

proc thenResponseHasNormalizedTraceSummary*(
  ctx: BddCtx;
  expectedTraceRef: string;
  expectedPathSignature: string;
  expectedVulnerabilityKind: string;
  expectedViolatedProperty: string;
  expectedEvolutionReasoning: string
) =
  check ctx.lastInspectTrace.isOk()
  let trace = ctx.lastInspectTrace.get()
  check trace.traceRef == expectedTraceRef
  check trace.pathSignature == expectedPathSignature
  check trace.vulnerabilityKind == expectedVulnerabilityKind
  check trace.violatedProperty == expectedViolatedProperty
  check trace.evolutionReasoning == expectedEvolutionReasoning
  check trace.branchPoints == @["balance < amount", "amount == 0"]

proc thenResponseHasUrl*(ctx: BddCtx) =
  check ctx.lastExportProof.isOk()
  check ctx.lastExportProof.get().url.len > 0

proc thenErrorIs*(ctx: BddCtx; expected: AxiomError) =
  check ctx.lastGenerateProof.isErr()
  check ctx.lastGenerateProof.error == expected

proc thenExportErrorIs*(ctx: BddCtx; expected: AxiomError) =
  check ctx.lastExportProof.isErr()
  check ctx.lastExportProof.error == expected

proc thenErrorMessageContains*(ctx: BddCtx; a: string; b: string) =
  check ctx.lastGenerateProof.isErr()
  let msg = describeError(ctx.lastGenerateProof.error)
  check msg.contains(a)
  check msg.contains(b)

proc thenExportErrorMessageContains*(ctx: BddCtx; a: string; b: string) =
  check ctx.lastExportProof.isErr()
  let msg = describeError(ctx.lastExportProof.error, ctx.lastTarget)
  check msg.contains(a)
  check msg.contains(b)

proc runVerifyWorkflow*(): VerifyWorkflowCliResult =
  ## Execute `ax verify-workflow` CLI and capture its JSON output.
  let (output, exitCode) = execCmdEx("ax verify-workflow", input = "")
  result.outputJson = output
  result.exitCode = exitCode
  result.logLines = output.splitLines()
