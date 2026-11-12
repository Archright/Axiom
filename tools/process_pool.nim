import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}

## process_pool.nim — Throttled Worker Process Pool
##
## Limits concurrent subprocess execution to `countProcessors()` workers.
## Uses a sliding-window approach: when at capacity, the oldest running
## process is collected before a new one is spawned.  Results are returned
## in submission order.
##
## Context7-verified: Nim stdlib osproc.startProcess + outputStream for
## subprocess stdout capture.  AGENTS.md §0.6a: bounded concurrency for
## external programs.
##
## Usage:
##   import tools/process_pool
##   let results = runPool(modules, myBuildCmd)

import std/[cpuinfo, osproc, strtabs, os, streams]
import shared_types/shared_types

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  BuildCommand* = object
    ## Structured description of one compiler invocation.
    ##
    ## The field split mirrors the Nim command-line grammar — `nim command
    ## [options] [projectfile] [arguments]`
    ## (<https://nim-lang.org/docs/nimc.html>, "Basic command-line
    ## switches").  Nim treats *everything* after the project file as
    ## run-time arguments: `processArgument` in `compiler/commands.nim`
    ## assigns `config.arguments = cmdLineRest(p)` the moment the project
    ## file is seen, so a `--flag` placed after it is never parsed as a
    ## switch and is rejected unless `--run` was given.  Modelling that
    ## split in the type is what lets `runPool` inject flags without any
    ## caller having to re-derive the ordering rule.
    program*: string
      ## Executable to spawn, e.g. `"nim"`.
    command*: string
      ## Nim sub-command, e.g. `"c"` or `"check"`.  May be empty.
    options*: seq[string]
      ## Compiler switches.  Always rendered *before* `projectFile`.
    projectFile*: string
      ## The main `.nim` file.  May be empty for stdin/projectless builds.
    arguments*: seq[string]
      ## Run-time arguments; only meaningful together with `--run`.

  PoolResult* = object
    ## Outcome of a single subprocess execution.
    module*: string
      ## Module name as submitted to the pool.
    exitCode*: int
      ## Process exit code (0 = success).
    output*: string
      ## Merged stdout + stderr captured from the process.

  ProcessPool* = object
    ## Internal bookkeeping for the sliding-window pool.
    maxWorkers: int
    running: seq[Process]
    modules: seq[string]

# ---------------------------------------------------------------------------
# Command assembly
# ---------------------------------------------------------------------------

func nimcacheFor*(nimcacheBase: string, index: int): string =
  ## Per-module nimcache directory for pool slot `index`.
  ##
  ## Single source of truth for the pool's isolation scheme, so a caller
  ## that needs to reproduce the exact command line (e.g. `--dry-run`)
  ## cannot drift from what `runPool` actually executes.
  nimcacheBase / "mod" & $index

proc withOption*(cmd: BuildCommand, opt: string): BuildCommand =
  ## Return a copy of `cmd` with `opt` appended to its option section.
  ##
  ## Non-mutating so a caller may reuse one command template across every
  ## module without the per-module flags accumulating.
  result = cmd
  result.options = newSeqOfCap[string](cmd.options.len + 1)
  for o in cmd.options:
    result.options.add(o)
  result.options.add(opt)

proc toArgv*(cmd: BuildCommand): seq[string] =
  ## Render to the flat token list handed to `startProcess`
  ## (first element = command, rest = args).
  ##
  ## This is the only place token order is decided, so a switch can never
  ## land after the project file no matter what a caller adds.
  result.add(cmd.program)
  if cmd.command.len > 0:
    result.add(cmd.command)
  for o in cmd.options:
    result.add(o)
  if cmd.projectFile.len > 0:
    result.add(cmd.projectFile)
  for a in cmd.arguments:
    result.add(a)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func workerCount(): int {.raises: [].} =
  ## Determine the number of parallel workers.  At least 1.
  let n = cpuinfo.countProcessors()
  result = max(n, 1)

proc collectProcess(p: Process, moduleName: string): PoolResult {.
    axiomEffect: IOEffect.} =
  ## Read remaining output from a finished process, close it, and
  ## build the result record.
  let outp = p.outputStream
  var output = ""
  if not outp.isNil:
    while not outp.atEnd:
      output.add(outp.readLine() & "\n")
  let exitCode = p.waitForExit()
  p.close()
  result = PoolResult(
    module: moduleName,
    exitCode: exitCode,
    output: output
  )

proc drainOldest(pool: var ProcessPool): PoolResult {.
    axiomEffect: IOEffect.} =
  ## Wait for the oldest running process and collect its result.
  doAssert pool.running.len > 0, "drainOldest called with empty pool"
  let idx = 0
  let p = pool.running[idx]
  let moduleName = pool.modules[idx]
  result = collectProcess(p, moduleName)
  pool.running.delete(idx)
  pool.modules.delete(idx)

proc drainAll(pool: var ProcessPool): seq[PoolResult] {.
    axiomEffect: IOEffect.} =
  ## Collect every remaining running process (FIFO order).
  while pool.running.len > 0:
    result.add(drainOldest(pool))

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

proc runPool*(modules: seq[string],
              buildCmd: proc(module: string): BuildCommand,
              env: StringTableRef = nil,
              nimcacheBase: string = "build/nimcache_pool"): seq[PoolResult] {.
              axiomEffect: IOEffect.} =
  ## Execute a build command for each module with bounded concurrency.
  ##
  ## `buildCmd` is called per-module and returns the structured
  ## invocation; the pool renders it via `BuildCommand.toArgv`.
  ## Each module receives its own `--nimcache:<nimcacheFor(base, i)>` flag,
  ## injected into the *option* section so it precedes the project file.
  ##
  ## Results are returned in submission order regardless of completion order.
  ## Processes that exit with non-zero codes are still recorded (the caller
  ## inspects `exitCode`).
  if modules.len == 0:
    return

  # Ensure the nimcache parent directory exists.
  createDir(nimcacheBase)

  let maxWorkers = workerCount()
  var pool = ProcessPool(
    maxWorkers: maxWorkers,
    running: @[],
    modules: @[]
  )

  for i, moduleName in modules:
    # Build per-module nimcache path into the option section — never the tail.
    let args = buildCmd(moduleName)
                .withOption("--nimcache:" & nimcacheFor(nimcacheBase, i))
                .toArgv()

    # Throttle: if at capacity, drain the oldest process first.
    if pool.running.len >= pool.maxWorkers:
      result.add(drainOldest(pool))

    # Spawn the new process.
    doAssert args.len >= 1, "buildCmd must return at least a command name"
    let cmd = args[0]
    let cmdArgs = if args.len > 1: args[1 .. ^1] else: @[]
    let p = startProcess(
      command = cmd,
      args = cmdArgs,
      options = {poStdErrToStdOut, poUsePath},
      env = env
    )
    pool.running.add(p)
    pool.modules.add(moduleName)

  # Drain any remaining processes to collect all results.
  result.add(drainAll(pool))

# ---------------------------------------------------------------------------
# Convenience: nim check in parallel
# ---------------------------------------------------------------------------

proc checkModulesParallel*(modules: seq[string],
                           env: StringTableRef = nil,
                           extraFlags: seq[string] = @[
                             "--hints:off",
                             "--warnings:off",
                             "-d:allowMissingZ3"
                           ]): seq[PoolResult] {.
                           axiomEffect: IOEffect.} =
  ## Run `nim check` on multiple modules in parallel.
  ##
  ## Each module is checked with `nim check <flags> <module>`.
  ## Results are returned in submission order.
  proc checkCmd(module: string): BuildCommand =
    BuildCommand(program: "nim", command: "check",
                 options: extraFlags, projectFile: module)

  result = runPool(modules, checkCmd, env = env)
