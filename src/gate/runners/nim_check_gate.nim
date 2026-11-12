import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

import std/os
import std/strutils
import core/results
import core/parsers/safe_parsers
import gate/gate_types
import gate/runners/nim_check_runner
import core/axiom_pragmas
import infrastructure/logger
import infrastructure/logging_facade


# axiomIoBoundary

proc expandResponseFile(path: string): seq[string] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let content = readFile(path)
  for line in content.splitLines():
    let trimmed = line.strip()
    if trimmed.len > 0:
      result.add(trimmed)

proc main() {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  # Every child `nim check` spawned by this gate must skip hermeticPreBuild
  # housekeeping: that block is single-process / sequential and unsafe to run
  # concurrently per worker. Declaring it at the process level (not via the
  # caller) keeps the parallel path hermetic-safe regardless of invocation site.
  putEnv("AXIOM_HERMETIC_BUILDING", "1")
  if paramCount() < 3:
    logInfo("nim_check_gate", "Usage: nim_check_gate <repoRoot> <mode> <maxJobs> [files...|@filelist.txt]")
    quit(1)
  let repoRoot = paramStr(1)
  let modeStr = paramStr(2).toLowerAscii()
  let mode =
    if modeStr in ["incremental", "inc", "grmincremental", "pre-commit"]:
      grmIncremental
    elif modeStr in ["exhaustive", "full", "grmexhaustive", "pre-push"]:
      grmExhaustive
    else:
      logError("nim_check_gate", "[nim_check_gate] ERROR: invalid mode '" & paramStr(2) & "'; expected incremental|full")
      quit(1)
  let parsed = safeParseInt(paramStr(3))
  let maxJobs = if parsed.isOk: parsed.get() else: 4
  var files: seq[string] = @[]
  for i in 4 .. paramCount():
    let arg = paramStr(i)
    if arg.startsWith("@"):
      if arg.len <= 1:
        logError("nim_check_gate", "[nim_check_gate] ERROR: empty response file path")
        quit(1)
      files.add(expandResponseFile(arg[1 .. ^1]))
    else:
      files.add(arg)
  let res = runNimCheck(repoRoot, mode, maxJobs, files)
  if res.stdout.len > 0:
    logger.info res.stdout
  if res.stderr.len > 0:
    logInfo("nim_check_gate", res.stderr)
  logger.info (if res.ok: "PASS" else: "FAIL") & " " & res.name
  quit(if res.ok: 0 else: 1)

{.pop.}

when isMainModule: main()
