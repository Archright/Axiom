import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}
## Invalidation Trigger — normalized-content-hash based cache invalidation
##
## Detects whether a source file has changed by comparing SHA-256 hashes of
## normalized content (comments stripped, whitespace collapsed).  Returns a
## coarse-grained result: either the file is unchanged or it changed (no
## symbol-level granularity because tree-sitter was removed).
##
## Performance: O(n) single-pass normalize + SHA-256 instead of O(n log n)
## tree-sitter incremental parse.  No FFI or external parser needed.

import std/sets
import gate/daemon/content_hash

type
  ChangedFile* = object
    ## Record of a file whose normalized content hash changed.
    path*: string        ## File path (for multi-file scenarios)
    oldHash*: string     ## Previous normalized hash (empty = new file)
    newHash*: string     ## Current normalized hash (empty = deleted)

  InvalidationResult* = object
    ## Result of change detection between two source versions.
    changedFiles*: seq[ChangedFile]   ## Files that changed (0 or 1 for single-file)
    affectedSymbols*: HashSet[string] ## Reserved — always empty now
    isStructuralChange*: bool         ## True when content hash differs
    isFullInvalidation*: bool         ## True when we can't narrow scope

func detectChanges*(oldSource, newSource: string): InvalidationResult {.
  raises: [].} =
  ## Detect whether source content changed between two versions.
  ##
  ## Uses normalized content hashing: strips comments, normalizes whitespace,
  ## then compares SHA-256 digests.  Identical semantics (ignoring cosmetic
  ## differences) produce matching hashes.
  ##
  ## Returns coarse-grained result — if hashes differ the whole file is
  ## considered changed; no symbol-level granularity.
  result = InvalidationResult(
    changedFiles: @[],
    affectedSymbols: initHashSet[string](),
    isStructuralChange: false,
    isFullInvalidation: false
  )

  let oldHash = normalizedContentHash(oldSource)
  let newHash = normalizedContentHash(newSource)

  if oldHash == newHash:
    # No semantic change detected
    return

  # Content changed — mark as full invalidation since we can't
  # determine which specific symbols are affected without tree-sitter.
  result.isStructuralChange = true
  result.isFullInvalidation = true
  result.changedFiles.add(ChangedFile(
    path: "",       # Single-file API; path filled by caller
    oldHash: oldHash,
    newHash: newHash
  ))

func getAffectedSymbolNames*(self: InvalidationResult): seq[string] {.
  raises: [].} =
  ## Get sorted list of affected symbol names.
  ## Always returns empty — invalidation is file-level, not symbol-level.
  @[]
