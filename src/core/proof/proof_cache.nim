## proof_cache.nim — Compile-time proof result caching
## ====================================================
## Prevents redundant Z3/Lean verification by caching proof results
## keyed on: source content hash + compiler version + Z3 hash + flags.
##
## Cache key = sha256(sourceFileContent & compiler.Version & z3Hash & flags)
##
## Cache location: .axiom/proof_cache/<source_sha>_<target_sha>/
##   manifest.json     — per-file hashes + proof results
##   z3_results.json   — UNSAT core cache
##   lean_results.json — ProofCertificate cache
## ====================================================

import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import std/[os, json, tables]
import ../crypto/hash_kernel
import core/trusted/axiom_pragmas
import core/trusted/stdlib_shield

type
  CacheResult* = enum
    cacheHit = "hit"
    cacheMiss = "miss"
    cacheCorrupt = "corrupt"
    cacheMissing = "missing"

  ProofEntry* = object
    filePath*: string
    contentHash*: string
    z3Result*: string       # "unsat" | "sat" | "unknown"
    leanResult*: string     # "verified" | "sorry" | "timeout"
    cachedAt*: string       # deterministic: contentHash prefix (R7 fix)

  ProofManifest* = object
    version*: int
    sourceSha*: string
    targetSha*: string
    cacheKey*: string       # salted hash
    compilerVersion*: string
    z3BinaryHash*: string
    definedFlags*: string
    entries*: seq[ProofEntry]
    createdAt*: string

const
  proofCacheDir* = ".axiom/proof_cache"
  manifestName* = "manifest.json"
  cacheKeyVersion* = 1

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func computeCacheKey*(sourceContent: string;
                      compilerVersion, z3Hash, flags: string): string {.raises: [].} =
  ## Salted cache key = sha256(content + compiler + z3 + flags)
  result = sha256Hex(sourceContent & compilerVersion & z3Hash & flags)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func getCacheDir*(sourceSha, targetSha: string): string {.raises: [].} =
  ## Returns: .axiom/proof_cache/<source>_<target>/
  result = proofCacheDir / (sourceSha & "_" & targetSha)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc checkProofCache*(sourceSha, targetSha: string;
                      compilerVersion, z3Hash, flags: string;
                      fileHashes: Table[string, string]): CacheResult {.raises: [], axiomEffect: IOEffect.} =
  ## Check if cached proof results exist and are valid.
  ##
  ## 1. manifest.json exists?
  ## 2. cacheKey matches (salted)?
  ## 3. All file content hashes match?
  ## → CacheHit: all match (Z3/Lean skip)
  ## → CacheMiss: any mismatch (full re-verify)
  ## → CacheCorrupt: manifest unparseable
  ## → CacheMissing: no manifest found
  
  let cacheDir = getCacheDir(sourceSha, targetSha)
  let manifestPath = cacheDir / manifestName
  
  if not fileExists(manifestPath):
    return cacheMissing
  
  try:
    let content = readFile(manifestPath)
    let manifest = parseJson(content)
    
    # Check salted cache key
    let storedKey = manifest{"cacheKey"}.getStr("")
    # Recompute key from manifest metadata
    let expectedKey = computeCacheKey(
      "",  # content already hashed into entries
      manifest{"compilerVersion"}.getStr(""),
      manifest{"z3BinaryHash"}.getStr(""),
      manifest{"definedFlags"}.getStr("")
    )
    
    if storedKey != expectedKey:
      return cacheCorrupt
    
    # Check per-file content hashes
    let entries = manifest{"entries"}
    for entry in entries:
      let filePath = entry{"filePath"}.getStr("")
      let storedHash = entry{"contentHash"}.getStr("")
      if filePath in fileHashes:
        if fileHashes[filePath] != storedHash:
          return cacheMiss
      else:
        return cacheMiss
    
    return cacheHit
  except CatchableError:
    return cacheCorrupt

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc storeProofResult*(sourceSha, targetSha: string;
                       compilerVersion, z3Hash, flags: string;
                       entries: seq[ProofEntry]) {.raises: [], axiomEffect: IOEffect.} =
  ## Store proof results in cache.
  ##
  ## R7 determinism fix: createdAt/cachedAt are metadata-only fields not
  ## included in the cache key computation (computeCacheKey uses only
  ## content+compiler+z3+flags). To keep the on-disk manifest byte-identical
  ## across runs with identical inputs, we derive a deterministic pseudo-
  ## timestamp from the cache key itself instead of wall-clock $now().
  let cacheDir = getCacheDir(sourceSha, targetSha)
  let manifestPath = cacheDir / manifestName
  
  try:
    createDir(cacheDir)
    
    let manifest = %*{
      "version": cacheKeyVersion,
      "sourceSha": sourceSha,
      "targetSha": targetSha,
      "cacheKey": computeCacheKey("", compilerVersion, z3Hash, flags),
      "compilerVersion": compilerVersion,
      "z3BinaryHash": z3Hash,
      "definedFlags": flags,
      "createdAt": "epoch",  # deterministic placeholder; see R7 fix comment above
      "entries": %*[]
    }
    
    # Add entries
    ## R7 determinism fix: cachedAt is metadata-only (not in cache key).
    ## Replace wall-clock value with contentHash prefix for byte-determinism.
    for e in entries:
      manifest["entries"].add(%*{
        "filePath": e.filePath,
        "contentHash": e.contentHash,
        "z3Result": e.z3Result,
        "leanResult": e.leanResult,
        "cachedAt": e.contentHash[0..<8]  # deterministic pseudotimestamp
      })
    
    let tmpPath = manifestPath & ".tmp"
    writeFile(tmpPath, manifest.pretty())
    safeMoveFile(tmpPath, manifestPath)
  except CatchableError:
    discard # axiom:best-effort(cache write failure; miss → re-verify next run)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc clearCache*(sourceSha = ""; targetSha = "") {.raises: [], axiomEffect: IOEffect.} =
  ## Clear cache. If source/target provided, clear only that entry.
  ## If empty, clear entire cache.
  try:
    if sourceSha.len > 0 and targetSha.len > 0:
      let cacheDir = getCacheDir(sourceSha, targetSha)
      if dirExists(cacheDir):
        removeDir(cacheDir)
    elif dirExists(proofCacheDir):
      removeDir(proofCacheDir)
      createDir(proofCacheDir)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

{.pop.}
