import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

## Fine-Grained Merkle Slicing — per-gate input dependency isolation.
## Each gate declares an InputSlice that specifies exactly which files/dirs
## affect its cache key. This replaces the global compositeLockHash approach
## where ANY file change invalidated ALL gates.
##
## Phase 1-C: Infrastructure types + hash computation.
## Phase 2 (Agent E): Full integration into computeGateCacheKey.

import std/[os, strutils, sequtils, algorithm]
import ../core/crypto/hash_kernel
import gate/gate_contract
import core/axiom_pragmas

type
  InputSlice* = object
    kind*: InputSliceKind
    paths*: seq[string]
    excludePatterns*: seq[string]

func toInputSlice*(cfg: GateConfig): InputSlice =
  ## Reconstruct an InputSlice from the flat GateConfig fields.
  ## Falls back to skFilesPattern using the existing filesPattern if
  ## no explicit inputSliceKind is set.
  if cfg.inputSliceKind == skFilesPattern and cfg.inputSlicePaths.len == 0:
    # Default: use existing filesPattern as a filesPattern slice
    return InputSlice(
      kind: skFilesPattern,
      paths: if cfg.filesPattern.len > 0: @[cfg.filesPattern] else: @[],
      excludePatterns: @[]
    )
  InputSlice(
    kind: cfg.inputSliceKind,
    paths: cfg.inputSlicePaths,
    excludePatterns: cfg.inputSliceExclude
  )

func filterByPattern*(files: seq[string], pattern: string): seq[string] =
  ## Filter files by pipe-separated patterns (e.g. "src/|tests/").
  if pattern.len == 0:
    return @[]
  let patterns = pattern.split("|")
  result = @[]
  for f in files:
    for p in patterns:
      if p.len > 0 and f.startsWith(p):
        result.add(f)
        break

func sha256Hex*(data: string): string =
  ## Compute SHA-256 hex digest of arbitrary data.
  result = hash_kernel.sha256Hex(data)

func matchesAnyPattern(path: string, patterns: seq[string]): bool =
  ## Check if path matches any exclude pattern (suffix or substring).
  for pat in patterns:
    if path.endsWith(pat) or path.contains(pat):
      return true
  false

proc computeSliceHash*(slice: InputSlice; changedFiles: seq[string];
                       repoRoot: string): string {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compute a hash representing exactly the inputs this gate depends on.
  ## Returns "always" for skAlways gates (never cached).
  case slice.kind
  of skAlways:
    return "always"
  of skFilesPattern:
    let matched = filterByPattern(changedFiles, slice.paths.join("|"))
    let filtered = matched.filterIt(not it.matchesAnyPattern(slice.excludePatterns))
    return sha256Hex(filtered.sorted().join("\n"))
  of skSubtreeHash:
    # For subtreeHash, hash the content of matching files in the paths
    var hashes: seq[string]
    for path in slice.paths:
      let fullPath = repoRoot / path
      if fileExists(fullPath):
        if not fullPath.matchesAnyPattern(slice.excludePatterns):
          hashes.add(sha256Hex(readFile(fullPath)))
      elif dirExists(fullPath):
        for kind, walkPath in walkDir(fullPath):
          if kind == pcFile and not walkPath.matchesAnyPattern(slice.excludePatterns):
            hashes.add(sha256Hex(readFile(walkPath)))
    return sha256Hex(hashes.sorted().join("\n"))
  of skDataFileHash:
    var hashes: seq[string]
    for path in slice.paths:
      let fullPath = repoRoot / path
      if fileExists(fullPath) and not fullPath.matchesAnyPattern(slice.excludePatterns):
        hashes.add(sha256Hex(readFile(fullPath)))
    return sha256Hex(hashes.sorted().join("\n"))

{.pop.}
