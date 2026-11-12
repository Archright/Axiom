## verification_probe.nim — Runtime Read Instrumentation Probe (Audit Tool)
##
## Runs the verification-auditor gate under strace-style syscall tracing
## and emits a structured list of runtime reads (file paths opened with
## their mode, existence/stat checks, subprocess spawns, cwd, env).
##
## THIS IS AN AUDIT PROBE, not the semantic model. It surfaces what the
## kernel actually reads at runtime; the classification of those reads
## into dependency kinds lives in src/verification/verification_dependency.nim
## and the typed pipeline in src/verification/observation_pipeline.nim.
##
## Usage:
##   nim c -r tools/ci/verification_probe.nim <repoRoot> <sha>
##
## The probe:
##   1. Creates a detached worktree: git worktree add --detach <WT> <sha>
##   2. Runs strace -e trace=file,desc,process on the gate runner
##   3. Parses the strace output into RawObservation records
##   4. Emits JSON lines to stdout
##
## Determinism: the syscall trace is best-effort observation; the probe
## surfaces whatever strace reports. Completeness claims are conservative.

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}

import std/[os, osproc, strutils, json, parseopt, times, algorithm, sugar]
import std/[sets, tables]

# ---------------------------------------------------------------------------
# Read class — mirrors verification_dependency.nim ReadClass for the probe
# ---------------------------------------------------------------------------

type
  ProbeReadClass* = enum
    prcModuleContent    ## Content of a source module (*.nim).
    prcModuleExistence  ## Existence check of a file/directory.
    prcTestGateway      ## Presence of tests/gateway fixtures.
    prcManualFeature    ## @manual feature presence.
    prcBaseline         ## Baseline data.
    prcLockFile         ## Lock file (topology.lock).
    prcPolicy           ## Policy config (config/gates.json etc.).
    prcCommitId         ## Commit identifier (git HEAD).
    prcTimestamp        ## Timestamp / self-generated metadata.
    prcHistory          ## History / replay artifacts.
    prcGateOutput       ## Artifact the gate writes.
    prcEnvVar           ## Environment variable influence.
    prcCwd              ## Current working directory.
    prcCompilerSubprocess ## Compiler subprocess invocation.
    prcOther            ## Any other runtime read not in the list above.

func `$`*(rc: ProbeReadClass): string {.raises: [].} =
  case rc
  of prcModuleContent:    "module_content"
  of prcModuleExistence:  "module_existence"
  of prcTestGateway:      "test_gateway"
  of prcManualFeature:    "manual_feature"
  of prcBaseline:         "baseline"
  of prcLockFile:         "lock_file"
  of prcPolicy:           "policy"
  of prcCommitId:         "commit_id"
  of prcTimestamp:        "timestamp"
  of prcHistory:          "history"
  of prcGateOutput:       "gate_output"
  of prcEnvVar:           "env_var"
  of prcCwd:              "cwd"
  of prcCompilerSubprocess: "compiler_subprocess"
  of prcOther:            "other"

# ---------------------------------------------------------------------------
# RawObservation — a single observed runtime read
# ---------------------------------------------------------------------------

type
  RawObservation* = object
    ## Unvalidated raw read from the strace probe.
    path*: string          ## Path opened or checked.
    readClass*: ProbeReadClass  ## Best-effort classification by path pattern.
    mode*: string          ## Syscall mode (open flags, stat, etc.).
    syscall*: string       ## Syscall name (openat, stat, access, etc.).
    success*: bool         ## Whether the syscall succeeded.
    timestamp*: string     ## Observation timestamp.

func `$`*(obs: RawObservation): string {.raises: [].} =
  ## Serialize a RawObservation to a compact string.
  let status = if obs.success: "ok" else: "fail"
  result = "path=" & obs.path & " readClass=" & $obs.readClass &
    " syscall=" & obs.syscall & " mode=" & obs.mode & " status=" & status

# ---------------------------------------------------------------------------
# Path → ReadClass mapping (best-effort classification)
# ---------------------------------------------------------------------------

func classifyPath*(path: string): ProbeReadClass {.raises: [].} =
  ## Best-effort classification of a file path into a ProbeReadClass.
  ## This is an audit probe heuristic — the authoritative classification
  ## lives in verification_dependency.nim. The probe surfaces the read;
  ## the pipeline classifies it.
  let p = path.replace('\\', '/')
  if p.contains("src/") and p.endsWith(".nim"):
    prcModuleContent
  elif p.contains("tests/gateway"):
    prcTestGateway
  elif p.contains("verification_auditor_baseline") or p.contains("baseline"):
    prcBaseline
  elif p.contains("topology.lock") or p.contains(".lock"):
    prcLockFile
  elif p.contains("gates.json") or p.contains("config/"):
    prcPolicy
  elif p.contains(".axiom") or p.contains("cache"):
    prcGateOutput
  else:
    prcOther

# ---------------------------------------------------------------------------
# Strace output parsing
# ---------------------------------------------------------------------------

type
  StraceEntry* = object
    syscall*: string
    path*: string
    mode*: string
    result*: string
    errno*: string

func parseStraceLine*(line: string): StraceEntry {.raises: [].} =
  ## Parse a single strace output line into a StraceEntry.
  ## Best-effort; returns an empty entry on parse failure.
  let trimmed = line.strip()
  if trimmed.len == 0: return StraceEntry()

  # Typical strace line: openat(AT_FDCWD, "/path/to/file", O_RDONLY) = 3
  # or stat("/path/to/file", {st_mode=S_IFREG, ...}) = 0
  # or <... execve("/path", ["arg"], ...) = 0>

  let openParen = trimmed.find('(')
  let closeParen = trimmed.find(')')
  if openParen < 0 or closeParen < 0: return StraceEntry()

  let syscall = trimmed.substr(0, openParen).strip()
  let args = trimmed.substr(openParen + 1, closeParen - 1)
  let afterParen = trimmed[closeParen + 1 .. ^1].strip()
  let resultStr = if afterParen.startsWith("="): afterParen[1 .. ^1].strip()
                  elif afterParen.startsWith("<"): "<...>"
                  else: afterParen

  # Extract the first path argument (quoted string)
  var path = ""
  var mode = ""
  let quoteStart = args.find('"')
  if quoteStart >= 0:
    let quoteEnd = args.find('"', quoteStart + 1)
    if quoteEnd >= 0:
      path = args[quoteStart + 1 .. quoteEnd - 1]
    # Mode: look for O_ flags or numeric mode after the path
    let rest = args[quoteEnd + 1 .. ^1]
    for part in rest.split(","):
      let trimmed = part.strip()
      if trimmed.startsWith("O_") or trimmed.startsWith("S_") or trimmed.startsWith("AT_"):
        mode = trimmed
        break

  let success = not resultStr.startsWith("-") and resultStr != "?"

  StraceEntry(syscall: syscall, path: path, mode: mode,
              result: resultStr, errno: "")

# ---------------------------------------------------------------------------
# Probe runner
# ---------------------------------------------------------------------------

func isRelevantSyscall*(syscall: string): bool {.raises: [].} =
  ## Return true if the syscall is a relevant runtime read to trace.
  case syscall
  of "openat", "open", "stat", "lstat", "fstat", "access", "faccessat",
     "readlink", "readlinkat", "newfstatat", "chdir", "getcwd",
     "clone", "fork", "execve", "execv", "getenv":
    true
  else:
    false

func observationFromStraceEntry*(entry: StraceEntry; timestamp: string): RawObservation {.raises: [].} =
  ## Convert a parsed strace entry into a RawObservation.
  let readClass = classifyPath(entry.path)
  RawObservation(
    path: entry.path,
    readClass: readClass,
    mode: entry.mode,
    syscall: entry.syscall,
    success: entry.result != "-" and entry.result != "?",
    timestamp: timestamp
  )

## Build the strace command string to trace the verification-auditor gate.
func buildStraceCmd*(wtPath: string; gateArgs: seq[string]): string {.raises: [].} =
  ## Construct the strace command line. Traces file, descriptor, and
  ## process syscalls. Best-effort observation — not a completeness claim.
  let args = @["strace", "-e", "trace=file,desc,process", "-f",
               "-o", wtPath / "probe_trace.log",
               "--", "nim", "c", "--hints:off", "-r",
               "src/gate/runners/verification_auditor_gate.nim",
               wtPath, "full", "2"]
  args.join(" ")

## Create a detached worktree and run the probe.
proc runProbe*(repoRoot: string; sha: string): seq[RawObservation] {.raises: [CatchableError].} =
  ## Create a detached worktree, run the gate under strace, and
  ## return the collected RawObservation records.
  ##
  ## Convention: git worktree add --detach <WT> <sha>.
  let wtName = "probe-wt-" & $getTime().toUnix
  let wtPath = repoRoot / wtName

  # Create detached worktree
  let wtCmd = "git worktree add --detach " & wtPath & " " & sha
  let (wtOut, wtCode) = execCmdEx(wtCmd, workingDir = repoRoot)
  if wtCode != 0:
    raise newException(OSError, "Failed to create worktree: " & wtOut)

  try:
    # Build and run the strace command
    let straceCmd = buildStraceCmd(wtPath, @[])
    let (traceOut, traceCode) = execCmdEx(straceCmd, workingDir = repoRoot)
    discard traceOut
    discard traceCode
    discard traceCode

    # Parse the strace trace file
    let traceFile = wtPath / "probe_trace.log"
    var observations: seq[RawObservation] = @[]
    if fileExists(traceFile):
      let lines = readFile(traceFile).splitLines()
      let now = $now().utc
      for line in lines:
        let entry = parseStraceLine(line)
        if entry.syscall.len > 0 and isRelevantSyscall(entry.syscall):
          let obs = observationFromStraceEntry(entry, now)
          observations.add(obs)

    observations
  finally:
    # Clean up the worktree (best-effort)
    try:
      discard execCmdEx("git worktree remove --force " & wtPath, workingDir = repoRoot)
    except CatchableError:
      discard  # axiom:best-effort(observation capture best-effort - verdict unaffected)

## Emit the probe results as JSON lines.
proc emitProbe*(observations: seq[RawObservation]) {.raises: [CatchableError].} =
  ## Output RawObservation records as JSON lines to stdout.
  for obs in observations:
    let j = %*{
      "path": obs.path,
      "readClass": $obs.readClass,
      "syscall": obs.syscall,
      "mode": obs.mode,
      "success": obs.success,
      "timestamp": obs.timestamp
    }
    echo j

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

proc printHelp() {.raises: [].} =
  echo "Usage: verification_probe <repoRoot> <sha>"
  echo "Runtime read instrumentation probe for the verification-auditor gate."
  echo "Creates a detached worktree and runs strace on the gate runner."

proc main() =
  var repoRoot = ""
  var sha = ""
  var p = initOptParser(commandLineParams())
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdArgument:
      if repoRoot == "": repoRoot = p.val
      elif sha == "": sha = p.val
      else: echo "Unexpected argument: " & p.val
    of cmdShortOption, cmdLongOption:
      case p.key
      of "help", "h": printHelp(); quit(0)
      else: discard

  if repoRoot == "" or sha == "":
    echo "Error: repoRoot and sha are required."
    printHelp()
    quit(1)

  if not dirExists(repoRoot):
    echo "Error: repoRoot does not exist: " & repoRoot
    quit(1)

  let observations = runProbe(repoRoot, sha)
  emitProbe(observations)
  echo "# Total observations: " & $observations.len
  quit(0)

when isMainModule:
  try: main()
  except CatchableError as e: echo "[ERROR] ", e.msg; quit(1)