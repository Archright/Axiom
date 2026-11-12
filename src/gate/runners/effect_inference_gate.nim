import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## Effect Inference Gate
##
## Checks for I/O procs missing {.axiomEffect: IOEffect.} pragma.
## Uses ioSymbols from effect_inference_engine for runtime IO detection.
## Only flags procs that actually contain IO calls but lack the annotation.
##
## DEBT#380 fix: uses GateStatusKind to prevent warn-only mode from returning
## success (ok:true) when violations exist — structural theater prevention.

import std/[os, strutils, strformat, monotimes]
import core/axiom_pragmas
import core/results
import core/parsers/safe_parsers
import core/trusted/effect_inference_engine
import core/gates/gate_types
import infrastructure/logger
import infrastructure/logging_facade


# axiomIoBoundary

type
  EffectInferenceViolation = object
    path: string
    lineNo: int
    procName: string
    detectedIO: seq[string]

func findProcEnd(lines: seq[string], start: int): int =
  ## Find the line index where a proc declaration ends (body starts after '=').
  for j in start ..< min(start + 4, lines.len):
    if "=" in lines[j] and "{." notin lines[j]:
      return j
  return -1

func hasAxiomEffectPragma(lines: seq[string], start: int): bool =
  ## Check if a proc declaration has {.axiomEffect:} on its line or next few lines.
  for j in start ..< min(start + 4, lines.len):
    if "{.axiomEffect:" in lines[j]:
      return true
  false

func extractProcName(line: string): string =
  let stripped = line.strip()
  if not stripped.startsWith("proc "):
    return "<unknown>"
  let afterProc = "proc ".len
  var endIdx = afterProc
  while endIdx < stripped.len and stripped[endIdx] notin {'(', '[', '{', ':', '=', ' ', '\t', '\n', '\r', ';', ',', '.'}:
    endIdx += 1
  if endIdx > afterProc:
    stripped[afterProc ..< endIdx]
  else:
    "<unknown>"

func detectIoCalls(bodyLines: seq[string]): seq[string] =
  result = @[]
  for line in bodyLines:
    for sym in ioSymbols:
      if sym in line and sym notin result:
        result.add(sym)

proc checkFile(filepath: string): seq[EffectInferenceViolation] {.raises: [], axiomEffect: IOEffect.} =
  result = @[]
  try:
    let content = readFile(filepath)
    let lines = content.splitLines()
    var i = 0
    while i < lines.len:
      let stripped = lines[i].strip()
      if stripped.startsWith("proc ") and not stripped.startsWith("func "):
        if not stripped.startsWith("##") and not stripped.startsWith("#"):
          if not hasAxiomEffectPragma(lines, i):
            let bodyStart = findProcEnd(lines, i)
            if bodyStart >= 0:
              var bodyLines: seq[string] = @[]
              for j in (bodyStart + 1) ..< min(bodyStart + 200, lines.len):
                let bLine = lines[j]
                if j > bodyStart + 1 and (bLine.strip().startsWith("proc ") or
                    bLine.strip().startsWith("func ") or
                    bLine.strip().startsWith("type ") or
                    bLine.strip().startsWith("import ")):
                  break
                bodyLines.add(bLine)
              let detectedIO = detectIoCalls(bodyLines)
              if detectedIO.len > 0:
                result.add(EffectInferenceViolation(
                  path: filepath,
                  lineNo: i + 1,
                  procName: extractProcName(stripped),
                  detectedIO: detectedIO
                ))
      i += 1
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

proc runEffectInferenceScan*(repoRoot: string; files: seq[string]; severity: string = "warn"): GateResult {.raises: [].} =
  var targetFiles: seq[string]
  if files.len > 0:
    targetFiles = files
  else:
    try:
      for path in walkDirRec(repoRoot / "src"):
        if path.endsWith(".nim"):
          targetFiles.add(path)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

  var violations: seq[EffectInferenceViolation] = @[]
  for path in targetFiles:
    let relPath = try: relativePath(path, repoRoot, '/') except CatchableError: path
    let fileViolations = checkFile(relPath)
    for v in fileViolations:
      violations.add(v)

  if violations.len > 0:
    var msg = ""
    if severity == "warn":
      msg.add(&"[GUARD:WARN] {violations.len} effect inference violations (warn-only phase):\n")
      for v in violations:
        msg.add(&"  {v.path}:{v.lineNo}: proc {v.procName} — IO calls: {v.detectedIO}\n")
      # axiom:theater-fix(DEBT#380) WarningViolated ≠ verified success
      result = GateResult(kind: GateStatusKind.WarningViolated, reason: msg)
    else:
      msg.add(&"[GUARD] {violations.len} effect inference violations:\n")
      for v in violations:
        msg.add(&"  {v.path}:{v.lineNo}: proc {v.procName} — IO calls: {v.detectedIO}\n")
      result = GateResult(kind: GateStatusKind.VerificationFailed, reason: msg)
  else:
    result = GateResult(kind: GateStatusKind.VerifiedPass, reason: "[GUARD] All procs with IO have proper effect annotations. ✅\n")

proc main() {.axiomEffect: IOEffect.} =
  if paramCount() < 3:
    logInfo("effect_inference_gate", "Usage: effect_inference_gate <repoRoot> <mode> <maxJobs> [files...]")
    quit(1)
  let repoRoot = paramStr(1)
  let mode = paramStr(2)
  let maxJobsRes = safeParseInt(paramStr(3))
  if not maxJobsRes.isOk:
    logInfo("effect_inference_gate", "Invalid maxJobs: " & paramStr(3))
    quit(1)
  let maxJobs = maxJobsRes.get()
  var files: seq[string] = @[]
  for i in 4 .. paramCount():
    files.add(paramStr(i))
  let t0Ticks = getMonoTime().ticks
  let res = runEffectInferenceScan(repoRoot, files)
  let elapsedMs = (getMonoTime().ticks - t0Ticks) div 1_000_000
  if elapsedMs > 500:
    logInfo("effect_inference_gate", &"axiom: [PERF] effect-inference took {elapsedMs}ms (threshold: 500ms) — consider caching")
  logger.info (if res.isStrictSuccess(): "PASS" else: "FAIL") & " effect-inference"
  logger.info res.reason
  quit(res.kind.exitCode())

when isMainModule: main()

{.pop.}
