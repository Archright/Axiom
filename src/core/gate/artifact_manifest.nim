import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Artifact Manifest — Bazel Action Cache pattern for Axiom gate results.
## Maps commit hashes to gate execution metadata for deterministic baseline comparison.
## Replaces mutable baseline files with immutable commit-scoped lookups.
##
## Store layout:
##   .axiom/cache/manifest/
##   |- ab/
##   |  \- abcdef1234567890abcdef1234567890abcdef12.json
##   |- cd/
##   |  \- ...
##   (Two-level sharding by commit hash prefix — O(1) lookup)
##
## Atomic write: tmp → rename. POSIX rename is atomic; readers always see
## complete old or new state. Immutability: once written, a manifest entry
## for a given commit hash is never modified.

import core/interfaces/git_operations
import std/[json, options, os, osproc, strutils]
import core/trusted/axiom_pragmas
import core/trusted/stdlib_shield

const
  ManifestRelDir* = ".axiom/cache/manifest"
    ## Relative path to the manifest store root.
  ManifestVersion = 1
    ## Schema version for forward-compatible deserialization.

type
  GateResult* = object
    ## Execution metadata for a single gate run.
    gateId*: string
    totalWarnings*: int
    totalErrors*: int
    timestamp*: int64

# ---------------------------------------------------------------------------
# Path Computation
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func manifestPath(repoRoot, commitHash: string): string =
  ## Compute the manifest file path for a given commit hash.
  ## ``<repoRoot>/.axiom/cache/manifest/<hash[:2]>/<hash>.json``
  assert commitHash.len >= 2, "Commit hash too short: " & commitHash
  repoRoot / ManifestRelDir / commitHash[0 .. 1] / commitHash & ".json"

# ---------------------------------------------------------------------------
# Directory Management
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc ensureDir(repoRoot, commitHash: string) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Ensure the manifest shard directory exists.
  try:
    let dir = repoRoot / ManifestRelDir / commitHash[0 .. 1]
    if not dirExists(dir):
      createDir(dir)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

# ---------------------------------------------------------------------------
# Store
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc storeResult*(repoRoot, commitHash: string; gateResult: GateResult)
    {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Store a gate result for a specific commit hash.
  ## Idempotent — overwrites existing result for the same gate.
  ensureDir(repoRoot, commitHash)
  let path = manifestPath(repoRoot, commitHash)
  let tmpPath = path & ".tmp"

  # All I/O and JSON mutations in a single try block.
  # JsonNode [] and []* can raise KeyError; writeFile raises IOError.
  try:
    # Read existing manifest or start fresh
    var manifest: JsonNode
    if fileExists(path):
      manifest = parseJson(readFile(path))
    else:
      manifest = newJObject()

    manifest["version"] = %ManifestVersion
    manifest["commitHash"] = %commitHash

    if "results" notin manifest:
      manifest["results"] = newJObject()

    manifest["results"][gateResult.gateId] = %*{
      "totalWarnings": gateResult.totalWarnings,
      "totalErrors": gateResult.totalErrors,
      "timestamp": gateResult.timestamp
    }

    # Atomic write: temp → rename. POSIX rename is atomic.
    writeFile(tmpPath, manifest.pretty())
    safeMoveFile(tmpPath, path)
  except CatchableError:
    # Cleanup stale temp on failure
    try: removeFile(tmpPath) except CatchableError: discard  # axiom:best-effort(ioboundary catch)

# ---------------------------------------------------------------------------
# Lookup
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc lookupResult*(repoRoot, commitHash, gateId: string): Option[GateResult]
    {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Look up a specific gate result for a commit hash.
  ## Returns ``none(GateResult)`` if not found.
  let path = manifestPath(repoRoot, commitHash)
  if not fileExists(path):
    return none(GateResult)
  try:
    let manifest = parseJson(readFile(path))
    if "results" in manifest and gateId in manifest["results"]:
      let r = manifest["results"][gateId]
      return some(GateResult(
        gateId: gateId,
        totalWarnings: r["totalWarnings"].getInt(),
        totalErrors: r["totalErrors"].getInt(),
        timestamp: r["timestamp"].getInt()
      ))
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  return none(GateResult)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc lookupPreviousResult*(repoRoot, gateId: string): Option[GateResult]
    {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Look up the gate result from the previous commit (HEAD~1).
  ## Uses git to resolve the commit hash, then looks up in the manifest.
  try:
    let gitExe = git_operations.findRealGit()
    let (output, exitCode) = git_operations.runGitEx(gitExe, "-C " & quoteShell(repoRoot) &
                                       " log -1 --format=%H HEAD~1")
    let commitHash = output.strip()
    if exitCode == 0 and commitHash.len == 40:
      return lookupResult(repoRoot, commitHash, gateId)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  return none(GateResult)

# ---------------------------------------------------------------------------
# Commit Resolution
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc currentCommitHash*(repoRoot: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Get the current HEAD commit hash.
  ## Returns empty string if not in a git repo or on detached HEAD.
  try:
    let gitExe = git_operations.findRealGit()
    let (output, exitCode) = git_operations.runGitEx(gitExe, "-C " & quoteShell(repoRoot) &
                                       " log -1 --format=%H HEAD")
    if exitCode == 0 and output.len == 40:
      return output.strip()
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  return ""
