import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## PATH Binary Manifest — Wave 7A Hermetic Build Engine
##
## Collects SHA-256 hashes of every executable in PATH.
## This ensures toolchain changes (compiler upgrades, linker changes)
## automatically invalidate Action Key cache.
##
## Bazel toolchain rules model: PATH/JAVA_HOME dependency is explicit.
## Nix /nix/store model: tools are store items with content hashes.

import std/[os, algorithm, strutils, times]
import ../trusted/env_access
import ../crypto/hash_kernel
import core/axiom_pragmas

type
  PathManifestEntry* = object
    ## A single executable found in PATH.
    name*: string              ## Binary name ("nim", "gcc")
    path*: string              ## Full path ("/usr/bin/gcc")
    contentHash*: string       ## SHA-256 of binary content
    mtime*: float              ## Last modified time (for cache invalidation)

  PathManifest* = object
    ## Complete snapshot of all executables in PATH.
    entries*: seq[PathManifestEntry]
    hash*: string              ## Deterministic hash of entire manifest

# ─── Pure Hash Helpers ────────────────────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func computeHash(content: string): string {.raises: [].} =
  ## SHA-256 hash of content. Used for manifest hashing.
  result = hash_kernel.computeHash(content)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func cmpEntryName(a, b: PathManifestEntry): int {.raises: [].} =
  ## Deterministic comparison for sorting manifest entries by name.
  cmp(a.name, b.name)

# ─── I/O: Binary Hashing ─────────────────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc hashBinary(path: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## axiomIoBoundary
  ## Compute SHA-256 of a binary file.
  ## For large binaries, hash first 4KB + file size (performance trade-off).
  ## For small binaries (<4KB), hash entire content.
  try:
    let content = readFile(path)
    if content.len <= 4096:
      return computeHash(content)
    else:
      # Hash first 4KB + size for large binaries
      return computeHash(content[0..4095] & $content.len)
  except CatchableError:
    return ""

# ─── I/O: PATH Manifest Collection ──────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc collectPathManifest*(pathEnv: string = ""): PathManifest {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## axiomIoBoundary
  ## Collect SHA-256 hashes of all executables in PATH.
  ## pathEnv: explicit PATH string. If empty, uses system PATH.
  result.entries = @[]

  let pathDirs = if pathEnv.len > 0: pathEnv.split(":")
                 else: getAxiomEnv(evPath).split(":")

  for dir in pathDirs:
    if dir.len == 0 or not dirExists(dir):
      continue
    try:
      for kind, entry in walkDir(dir):
        # Only process regular files and symlinks to files (skip directories)
        if kind notin {pcFile, pcLinkToFile}:
          continue
        try:
          # Only hash executables (user execute bit)
          if fpUserExec notin getFilePermissions(entry):
            continue
          let info = getFileInfo(entry)
          let name = extractFilename(entry)
          let hash = hashBinary(entry)
          if hash.len > 0:
            result.entries.add(PathManifestEntry(
              name: name,
              path: entry,
              contentHash: hash,
              mtime: float(info.lastWriteTime.toUnix())
            ))
        except CatchableError:
          continue
    except CatchableError:
      continue

  # Sort by name for determinism — identical input must produce identical order
  result.entries.sort(cmpEntryName)

  # Compute manifest hash from sorted entries
  var parts: seq[string] = @[]
  for entry in result.entries:
    parts.add(entry.name & ":" & entry.contentHash)
  result.hash = computeHash(parts.join("\n"))

# ─── I/O: Cache Persistence ─────────────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc cachePathManifest*(manifest: PathManifest, cachePath: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## axiomIoBoundary
  ## Cache manifest hash to disk for fast subsequent reads.
  ## Cache invalidation: compare mtime of all binaries.
  try:
    let dir = cachePath.parentDir()
    if dir.len > 0 and not dirExists(dir):
      createDir(dir)
    writeFile(cachePath, manifest.hash)
  except CatchableError:
    discard  # Best-effort persistence  # axiom:best-effort(ioboundary catch)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc loadCachedPathManifest*(cachePath: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## axiomIoBoundary
  ## Load cached manifest hash. Returns "" if cache miss.
  try:
    readFile(cachePath)
  except CatchableError:
    ""

{.pop.}

