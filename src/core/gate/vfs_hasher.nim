import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [CatchableError].}

## VFS Hasher — Streaming SHA-256 Sequential Hashing
##
## Provides hashFile (streaming, 8KB chunks) and hashFiles (batch sequential).
## Malebolgia parallel dispatch removed due to SIGSEGV in alloc.nim
## addToSharedFreeList() — OS signal cannot be caught by try/except.
## Sequential hashing of ~500 files completes in <2s on modern hardware.
##
## See: docs/spec/vfs_hasher_quirks.md for full rationale.

import std/os
import std/tables
import checksums/sha2
import core/axiom_pragmas

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc toHex(digest: ShaDigest_256): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Convert raw SHA-256 digest to lowercase hex string.
  const hexChars = "0123456789abcdef"
  result = newString(64)
  for i in 0..<32:
    result[i * 2] = hexChars[int(digest[i].byte shr 4)]
    result[i * 2 + 1] = hexChars[int(digest[i].byte and 0x0f)]

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc hashFile*(absPath: string): string {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Streaming SHA-256 of a file. 8KB chunks, no full readFile.
  ## absPath MUST be absolute. Raises IOError if file cannot be opened.
  var ctx = initSha(Sha_256)
  var buf: array[8192, char]
  var f: File
  if not open(f, absPath, fmRead):
    raise newException(IOError, "Cannot open file: " & absPath)
  defer: f.close()
  while true:
    let n = readChars(f, buf)
    if n == 0:
      break
    ctx.update(buf.toOpenArray(0, n - 1))
  var digest: ShaDigest_256
  discard ctx.digest(digest)
  digest.toHex()

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc hashFiles*(repoRoot: string; workQueue: seq[tuple[path: string, size: int64, mtime: int64]]):
 tuple[hashes: Table[string, string]; errors: seq[string]] =
  ## Sequential batch SHA-256 hashing. Deterministic, crash-safe.
  ## Replaces parallelHash which used malebolgia (SIGSEGV in thread pool).
  result.hashes = initTable[string, string]()
  result.errors = @[]
  for fi in workQueue:
    let absPath = repoRoot / fi.path
    try:
      let h = hashFile(absPath)
      if h.len > 0:
        result.hashes[fi.path] = h
      else:
        result.errors.add(fi.path)
    except CatchableError:
      result.errors.add(fi.path)

# Backward compatibility aliases — callers should migrate to hashFiles
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc sequentialHash*(repoRoot: string; workQueue: seq[tuple[path: string, size: int64, mtime: int64]]):
 tuple[hashes: Table[string, string]; errors: seq[string]] =
  hashFiles(repoRoot, workQueue)

{.pop.}

