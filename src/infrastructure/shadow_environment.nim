import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Shadow Environment — Isolated Environment Variable Management
##
## Provides a sandboxed execution environment for scripts being migrated
## from Python to Nim. Ensures:
##   - Temporary env var overrides are applied and restored after execution
##   - Temp directories are created, tracked, and cleaned up deterministically
##   - No leaking of shadow state into the parent process
##
## All pure logic is `func` (effect-free). I/O procs use `{.axiomIoBoundary.}`
## and are restricted to the outermost boundary.

import std/[os, tables, times]
import core/boundary/axiom_pragmas_boundary

axiomIoBoundary()

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  ShadowEnvironment* = object
    ## Isolated execution environment for shadow script runs.
    ## Tracks env var overrides, exclusions, and temp resources.
    envOverrides*: Table[string, string]
    envExcludes*: seq[string]
    tempDir*: string
    cleanupOnExit*: bool

# ---------------------------------------------------------------------------
# Pure Logic (func)
# ---------------------------------------------------------------------------

func newShadowEnvironment*(
  overrides: Table[string, string],
  excludes: seq[string] = @[],
  cleanupOnExit: bool = true
): ShadowEnvironment {.raises: [].} =
  ## Construct a ShadowEnvironment with the given overrides and exclusions.
  ## Does NOT create temp dirs or apply env — call `init` for that.
  ShadowEnvironment(
    envOverrides: overrides,
    envExcludes: excludes,
    tempDir: "",
    cleanupOnExit: cleanupOnExit
  )

func isExcluded*(env: ShadowEnvironment, key: string): bool {.raises: [].} =
  ## Check whether a key is in the exclusion list.
  for e in env.envExcludes:
    if e == key:
      return true
  false

proc collectOriginalValues*(env: ShadowEnvironment): Table[string, string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Collect the current values for all overridden keys that are not excluded.
  ## This snapshot is used by `withShadow` to restore after execution.
  result = initTable[string, string]()
  for key, _ in env.envOverrides:
    if not env.isExcluded(key):
      let current = getEnv(key)
      if current.len > 0:
        result[key] = current

func activeOverrides*(env: ShadowEnvironment): Table[string, string] {.raises: [].} =
  ## Return only the overrides that are NOT excluded.
  result = initTable[string, string]()
  for key, value in env.envOverrides:
    if not env.isExcluded(key):
      result[key] = value

# ---------------------------------------------------------------------------
# I/O Boundary — Temp Dir & Env Management
# ---------------------------------------------------------------------------

proc makeTempDir*(prefix: string = "axiom_shadow_"): string {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Create a temporary directory under /tmp/ with the given prefix.
  ## Returns the absolute path of the created directory.
  let baseDir = getTempDir()
  let dirName = prefix & $epochTime().int
  let fullPath = baseDir / dirName
  createDir(fullPath)
  fullPath

proc init*(env: var ShadowEnvironment) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Initialize the shadow environment: create temp dir if cleanup is enabled.
  ## Does NOT apply env var overrides — use `withShadow` for that.
  if env.cleanupOnExit:
    env.tempDir = makeTempDir()

proc applyEnvVars*(env: ShadowEnvironment) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Apply all non-excluded env var overrides to the current process.
  for key, value in env.activeOverrides():
    putEnv(key, value)

proc restoreEnvVars*(env: ShadowEnvironment, original: Table[string, string]) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Restore env vars to their original values. Removes keys that had no prior value.
  for key, _ in env.envOverrides:
    if env.isExcluded(key):
      continue
    if key in original:
      putEnv(key, original[key])
    else:
      try:
        delEnv(key)
      except OSError:
        discard  # Best-effort removal

proc cleanup*(env: ShadowEnvironment) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Remove the temp directory and any resources created by this environment.
  if env.tempDir.len > 0 and dirExists(env.tempDir):
    removeDir(env.tempDir)

proc withShadow*[T](
  env: var ShadowEnvironment,
  body: proc(e: ShadowEnvironment): T {.raises: [CatchableError].}
): T {.raises: [CatchableError].} =
  ## Execute a body function within a shadow environment.
  ## Sets env vars, runs the body, then restores original env and cleans up.
  ##
  ## 1. Save original values
  ## 2. Apply overrides
  ## 3. Execute body
  ## 4. Restore originals
  ## 5. Cleanup temp dir
  env.init()
  let original = env.collectOriginalValues()
  env.applyEnvVars()
  try:
    result = body(env)
  except CatchableError:
    raise
  finally:
    env.restoreEnvVars(original)
    if env.cleanupOnExit:
      env.cleanup()

{.pop.}
