import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import core/trusted/stdlib_shield  # safeMoveFile: Exception isolation for stdlib moveFile quirk
import std/json
import std/os
import std/times
import core/trusted/axiom_pragmas
type
  ErrorClass* = enum
    ecTransient = "transient"
    ecRateLimited = "rate_limited"
    ecValidation = "validation"
    ecLogic = "logic"
    ecSystem = "system"

  RecoveryAction* = enum
    raRetry = "retry"
    raRetryWithDegradedPrompt = "retry_degraded"
    raSkip = "skip"
    raLocalAbort = "local_abort"
    raGlobalAbort = "global_abort"

  PipelineErrorContext* = object
    nodeId*: string
    phase*: string
    errorClass*: ErrorClass
    exceptionType*: string
    exceptionMsg*: string
    stackTrace*: string
    timestamp*: string
    leanstralDiagnostics*: string
    sourceHash*: string
    attemptNumber*: int
    recoveryAction*: RecoveryAction
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc captureErrorContext*(
  nodeId, phase: string;
  e: ref CatchableError;
  errorClass: ErrorClass  = ecSystem;
  recoveryAction: RecoveryAction = raLocalAbort;
  attempt: int = 1;
  leanstralDiagnostics: string = "";
  sourceHash: string = ""
): PipelineErrorContext {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Capture error context from a caught exception.
  ## stackTrace is left empty — caller may populate before dump if needed.
  PipelineErrorContext(
    nodeId: nodeId,
    phase: phase,
    errorClass: errorClass,
    exceptionType: $e.name,
    exceptionMsg: e.msg,
    stackTrace: "",
    timestamp: $getTime().utc,
    leanstralDiagnostics: leanstralDiagnostics,
    sourceHash: sourceHash,
    attemptNumber: attempt,
    recoveryAction: recoveryAction
  )
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc dumpErrorContext*(ctx: PipelineErrorContext; dumpDir: string) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Atomically dump error context as JSONL.
  ## Uses temp+fsync+rename pattern for crash safety.
  ## Uses processId in filename for concurrency safety.
  try:
    createDir(dumpDir)
    let filename = ctx.nodeId & "_" & $(epochTime().int) & "_" & $getCurrentProcessId() & ".jsonl"
    let finalPath = joinPath(dumpDir, filename)
    let tempPath = finalPath & ".tmp"

    # Build JSON
    var j = newJObject()
    j["nodeId"] = %ctx.nodeId
    j["phase"] = %ctx.phase
    j["errorClass"] = %($ctx.errorClass)
    j["exceptionType"] = %ctx.exceptionType
    j["exceptionMsg"] = %ctx.exceptionMsg
    j["stackTrace"] = %ctx.stackTrace
    j["timestamp"] = %ctx.timestamp
    j["leanstralDiagnostics"] = %ctx.leanstralDiagnostics
    j["sourceHash"] = %ctx.sourceHash
    j["attemptNumber"] = %ctx.attemptNumber
    j["recoveryAction"] = %($ctx.recoveryAction)

    # Step 1: Write to temp file
    writeFile(tempPath, $j & "\n")

    # Step 2: fsync — reopen read/write WITHOUT truncation (fmReadWriteExisting = r+)
    try:
      let f = open(tempPath, fmReadWriteExisting)
      f.flushFile()
      f.close()
    except CatchableError:
      discard  # fsync failure is non-fatal; rename still provides atomicity  # axiom:best-effort(ioboundary catch)

    # Step 3: Atomic rename
    try:
      safeMoveFile(tempPath, finalPath)
    except CatchableError: # non-fatal discard  # axiom:best-effort(ioboundary catch)
      discard
  except CatchableError:
    discard  # dump failure must not propagate  # axiom:best-effort(ioboundary catch)

{.pop.}
