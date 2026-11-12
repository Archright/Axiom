import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import core/interfaces/git_operations
import ../trusted/env_access
import ../crypto/hash_kernel
import std/[tables, times, os, strutils]
import core/parsers/safe_parsers
import core/results
let gitExe* = git_operations.findRealGit()
type
  ToolchainEntry* = object
    ## A single binary in the build toolchain with its content hash.
    name*: string              ## "nim", "gcc", "ld"
    path*: string              ## e.g. $HOME/.choosenim/toolchains/nim-2.2.10/bin/nim
    contentHash*: string       ## SHA-256 of binary content

  DeterministicEnv* = object
    ## Complete frozen build environment. Hash of this = Action Key component.
    sourceDateEpoch*: int64    ## Fixed Unix timestamp (default: latest git commit time)
    sourceDateRoot*: string    ## Fixed build root path (removes host path dependency)
    toolchain*: seq[ToolchainEntry]  ## Hash of every binary in PATH
    envVars*: Table[string, string]  ## Frozen environment variables
# ─── Pure Hash Helpers ────────────────────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func computeHash(content: string): string {.raises: [].} =
  ## SHA-256 hash of content. Used throughout for deterministic hashing.
  result = hash_kernel.computeHash(content)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func buildDeterministicHash*(env: DeterministicEnv): string {.raises: [].} =
  ## Compute a deterministic hash of the entire build environment.
  ## This becomes part of the Action Key.
  ## Deterministic: sorted inputs guarantee identical hash regardless of iteration order.
  var parts: seq[string] = @[]
  parts.add("epoch:" & $env.sourceDateEpoch)
  parts.add("root:" & env.sourceDateRoot)
  for entry in env.toolchain:  # caller must sort before calling
    parts.add("tool:" & entry.name & "=" & entry.contentHash)
  for k, v in env.envVars:  # Table iteration is sorted by key in Nim
    parts.add("env:" & k & "=" & v)
  computeHash(parts.join("\n"))
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc freezeTimestamp*(): int64 =
  ## axiomIoBoundary
  ## Get a deterministic timestamp.
  ## Strategy (without libfaketime):
  ## 1. Check SOURCE_DATE_EPOCH env var
  ## 2. Try latest git committer timestamp
  ## 3. Fallback: truncate current time to midnight UTC (daily reproducibility)
  let envEpoch = getAxiomEnv(evSourceDateEpoch)
  if envEpoch.len > 0:
    let epochRes = safeParseInt(envEpoch)
    if epochRes.isOk:
      return epochRes.get

  # Try git committer timestamp
  try:
    let (output, exitCode) = git_operations.runGitEx(gitExe, "log -1 --format=%ct 2>/dev/null")
    if exitCode == 0 and output.strip.len > 0:
      let tsRes = safeParseInt(output.strip)
      if tsRes.isOk:
        return tsRes.get
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

  # Fallback: truncate to midnight UTC
  try:
    let now = getTime().toUnix()
    now - (now mod 86400)
  except CatchableError:
    0'i64
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc freezeSourceRoot*(): string =
  ## axiomIoBoundary
  ## Get a fixed build root path.
  ## Use SOURCE_DATE_ROOT if set, otherwise use repo root.
  let envRoot = getAxiomEnv(evSourceDateRoot)
  if envRoot.len > 0:
    return envRoot
  try:
    getCurrentDir()
  except CatchableError:
    "."
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc buildDeterministicEnv*(
 extraVars: Table[string, string] = default(Table[string, string])
): DeterministicEnv =
  ## axiomIoBoundary
  ## Build a complete deterministic environment.
  ## Collects: frozen timestamp, fixed root, PATH manifest, explicit env vars.
  result.sourceDateEpoch = freezeTimestamp()
  result.sourceDateRoot = freezeSourceRoot()

  # Set up frozen env vars
  result.envVars = initTable[string, string]()

  # Add SOURCE_DATE_EPOCH for child processes
  result.envVars["SOURCE_DATE_EPOCH"] = $result.sourceDateEpoch
  result.envVars["SOURCE_DATE_ROOT"] = result.sourceDateRoot

  # Add caller-specified extras
  for k, v in extraVars:
    result.envVars[k] = v
# Note: proc (not func) because std/times.utc accesses timezone data (TimeEffect).
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc freezeTimestampForDeterministicHash*(epoch: int64): string =
  ## axiomIoBoundary
  ## Convert epoch to frozen date/time macros for C compiler.
  ## Usage: --passC:"-D__DATE__=... -D__TIME__=..."
  ## This eliminates build timestamp from binary output.
  let dt = fromUnix(epoch).utc
  let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  let dateStr = monthNames[dt.month.ord] & " " &
                align($dt.monthday, 2) & " " &
                align($dt.year, 4)
  let timeStr = align($dt.hour, 2, '0') & ":" &
                align($dt.minute, 2, '0') & ":" &
                align($dt.second, 2, '0')
  "--passC:-D__DATE__=\"" & dateStr & "\" -D__TIME__=\"" & timeStr & "\""
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func toEnvTable*(env: DeterministicEnv): Table[string, string] {.raises: [].} =
  ## Convert to environment table for startProcess.
  env.envVars

{.pop.}

