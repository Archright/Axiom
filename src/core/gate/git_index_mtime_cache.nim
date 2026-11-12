import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [CatchableError].}

## Git Index Mtime Cache — O(1) fast-path for VFS cache invalidation.
##
## The Git index file (.git/index or $GIT_INDEX_FILE) mtime changes
## whenever files are staged/unstaged/committed. By caching the index mtime
## alongside the VFS cache fingerprint, we can skip loading the binary VfsCache
## entirely when the Git index hasn't changed.
##
## Design:
##   - Resolve git index path (env var override or default .git/index)
##   - Stat once for mtime (single syscall)
##   - Compare against persisted mtime to decide cache validity
##   - Fallback to normal VFS build on any I/O error

import core/io/io_utils
import core/trusted/env_types
import std/json
import std/os
import std/times
import core/axiom_pragmas

type
  GitIndexMtimeEntry* = object
    ## Persisted Git index mtime snapshot.
    gitIndexMtime*: int64    ## Last known mtime of the Git index file
    vfsCachePath*: string    ## Path to the VFS cache that was built from this index

const
  cacheFileName* = "git_index_mtime.json"

# ─── Git Index Path Resolution ────────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func resolveGitIndexPath*(repoRoot: string): string =
  ## Resolve the Git index file path.
  ## Priority: $GIT_INDEX_FILE env var → default .git/index
  let envOverride = getAxiomEnv(evGitIndexFile, "")
  if envOverride.len > 0:
    return envOverride
  repoRoot / ".git" / "index"

# ─── Mtime Stat ───────────────────────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc getGitIndexMtime*(repoRoot: string): int64 {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Get current Git index file mtime as Unix timestamp.
  ## Returns 0 if file doesn't exist or stat fails.
  let idxPath = resolveGitIndexPath(repoRoot)
  try:
    result = getLastModificationTime(idxPath).toUnix()
  except CatchableError:
    result = 0

# ─── Cache Path ───────────────────────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func mtimeCachePath*(repoRoot: string): string =
  ## Path to the Git index mtime cache JSON file.
  repoRoot / ".axiom" / "cache" / cacheFileName

# ─── Load / Save ──────────────────────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc loadMtimeCache*(repoRoot: string): GitIndexMtimeEntry {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Load the persisted Git index mtime. Returns empty entry on any error.
  let path = mtimeCachePath(repoRoot)
  try:
    if not fileExists(path):
      return result
    let content = readFile(path)
    let node = parseJson(content)
    if node.kind != JObject:
      return result
    result.gitIndexMtime = node{"gitIndexMtime"}.getBiggestInt(0).int64
    result.vfsCachePath = node{"vfsCachePath"}.getStr("")
  except CatchableError:
    discard  # Corrupt cache → treat as empty  # axiom:best-effort(ioboundary catch)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc saveMtimeCache*(repoRoot: string; mtime: int64; vfsCachePath: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Persist the Git index mtime atomically (tmp+rename).
  let path = mtimeCachePath(repoRoot)
  try:
    let dir = path.parentDir()
    if not dirExists(dir):
      createDir(dir)
    let tmpPath = path & ".tmp"
    let node = %*{
      "gitIndexMtime": mtime,
      "vfsCachePath": vfsCachePath
    }
    writeFile(tmpPath, pretty(node) & "\n")
    discard moveFileOpt(tmpPath, path)
  except CatchableError:
    discard  # Best-effort  # axiom:best-effort(ioboundary catch)

# ─── Cache Hit Check ──────────────────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc isCacheValid*(repoRoot: string): bool =
  ## Check if the Git index has changed since the last VFS build.
  ## Returns true if the index mtime matches the cached mtime AND the
  ## VFS cache file still exists. O(1) stat + O(1) JSON parse.
  let currentMtime = getGitIndexMtime(repoRoot)
  if currentMtime == 0:
    return false  # Git index doesn't exist
  let cached = loadMtimeCache(repoRoot)
  if cached.gitIndexMtime != currentMtime:
    return false  # Index changed
  if cached.vfsCachePath.len == 0:
    return false  # No VFS cache recorded
  if not fileExists(cached.vfsCachePath):
    return false  # VFS cache was deleted
  return true

{.pop.}
