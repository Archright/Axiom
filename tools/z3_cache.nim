import core/trusted/layer_declaration
axiomLayer "tools"
import api/tools_facade
import std/[os, osproc, strutils]
import std/[os, strutils, times]
import tools/sha256_native
import safe_move
const
  Z3CacheDir* = ".axiom/z3_cache"
  Z3CacheVersion* = "1.0.0"
func computeCacheKey*(query: string, z3Version: string = ""): string {.raises: [].} =
  ## SHA256(query + z3Version) → 64-char hex digest.
  ## Z3 version must be part of key for cache invalidation on upgrade.
  let input = query & z3Version
  sha256String(input)
func cachePath*(key: string): string {.raises: [].} =
  ## Resolve cache key to file path: .axiom/z3_cache/<key>.res
  Z3CacheDir / key & ".res"
func metaPath*(key: string): string {.raises: [].} =
  ## Resolve cache key to metadata path: .axiom/z3_cache/<key>.meta
  Z3CacheDir / key & ".meta"
proc writeCacheAtomic*(cacheFile: string, content: string) =
  ## Write-Ahead-Rename: write to .tmp then atomic moveFile (POSIX rename).
  ## Safe against concurrent access and process crashes.
  ## I/O boundary proc — exceptions propagate to caller.
  let tmpPath = cacheFile & ".tmp"
  createDir(cacheFile.parentDir)
  writeFile(tmpPath, content)
  safeMoveFile(tmpPath, cacheFile)
proc readCache*(key: string): tuple[found: bool, result: string] =
  ## Read cached Z3 result. Returns (false, "") if not found.
  ## I/O boundary proc — readFile may raise IOError.
  let path = cachePath(key)
  if fileExists(path):
    return (true, readFile(path))
  return (false, "")
proc cacheExists*(key: string): bool =
  ## Check whether a cache entry exists for the given key.
  ## I/O boundary proc — fileExists on cache path.
  fileExists(cachePath(key))
proc writeCache*(key: string, result: string, query: string = "",
                 z3Version: string = "") =
  ## Write Z3 result to cache with metadata sidecar.
  ## I/O boundary proc — exceptions propagate to caller.
  writeCacheAtomic(cachePath(key), result)
  let meta = "{" &
    "\"version\": \"" & Z3CacheVersion & "\"," &
    "\"z3Version\": \"" & z3Version & "\"," &
    "\"queryLen\": " & $query.len & "," &
    "\"resultLen\": " & $result.len &
    "}"
  writeCacheAtomic(metaPath(key), meta)
proc readCacheWithMeta*(key: string): tuple[found: bool, result: string,
                         z3Version: string] =
  ## Read cached Z3 result plus Z3 version from metadata.
  ## Used to verify cache validity against running Z3 version.
  let path = cachePath(key)
  if not fileExists(path):
    return (false, "", "")
  let cachedResult = readFile(path)
  var z3Ver = ""
  let metaP = metaPath(key)
  if fileExists(metaP):
    let meta = readFile(metaP)
    # Extract z3Version from minimal JSON (avoid json import for this)
    const marker = "\"z3Version\": \""
    let idx = meta.find(marker)
    if idx >= 0:
      let start = idx + marker.len
      let endIdx = meta.find("\"", start)
      if endIdx > start:
        z3Ver = meta[start ..< endIdx]
  return (true, cachedResult, z3Ver)

when isMainModule:
  echo "z3_cache: module loaded successfully"
  # Quick self-test of cache key computation
  let key = computeCacheKey("(check-sat)\n", "4.13.0")
  doAssert key.len == 64, "Cache key must be 64-char SHA256 hex"
  echo "z3_cache: self-test passed (key=", key, ")"
  # for safe hash computation
const Z3CacheDir = ".axiom/cache/z3"
proc computeQueryHash*(query: string): string =
  ## Z3 쿼리의 SHA-256 해시 계산
  # Use a simple hash since we can't import checksums in tools context
  var h: int = 5381
  for c in query:
    h = h * 33 + ord(c)
  result = $h
proc cachedZ3Query*(query: string, z3Bin: string = "z3"): string =
  ## Z3 쿼리 실행 with content-addressable caching
  ## 캐시 히트: Z3 프로세스 없이 즉시 반환
  ## 캐시 미스: Z3 실행 후 결과 캐싱
  let queryHash = computeQueryHash(query)
  let cachePath = Z3CacheDir / queryHash & ".res"
  
  if fileExists(cachePath):
    return readFile(cachePath)  # 캐시 히트 — Z3 프로세스 스킵
  
  # 캐시 미스 — Z3 실행 후 결과 캐싱
  let (output, exitCode) = execCmdEx(z3Bin & " -in -smt2", input = query)
  if exitCode == 0:
    createDir(Z3CacheDir)
    writeFile(cachePath, output)
  return output
proc clearCache*() =
  ## 전체 Z3 캐시 무효화
  if dirExists(Z3CacheDir):
    for f in listFiles(Z3CacheDir):
      removeFile(f)
    echo "Z3 cache cleared: " & Z3CacheDir
  else:
    echo "No Z3 cache to clear"
proc cacheStats*() =
  ## 캐시 통계 출력
  if dirExists(Z3CacheDir):
    let files = listFiles(Z3CacheDir)
    echo "Z3 cache entries: " & $files.len
    var totalSize: int64 = 0
    for f in files:
      totalSize += getFileSize(f)
    echo "Z3 cache size: " & $(totalSize div 1024) & " KB"
  else:
    echo "Z3 cache: empty"
