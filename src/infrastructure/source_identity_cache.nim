import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Source-tree identity cache — the I/O gather + local acceleration cache for
## the SourceCoherence tree digest (VS-1).
##
## Contract (docs/spec/artifact_determinism.md):
##   - The digest is ALWAYS recomposed from the live walked path set; the cache
##     may only supply per-file content digests.
##   - A per-file digest is reused only when the kernel-provided stat identity
##     (dev, ino, size, mtime_ns, ctime_ns, mode) matches AND the entry is not
##     "racily clean" (git racy-git rule: timestamps in the same second as the
##     cache write may have changed after the read, so rehash once).
##   - Unreadable source = fail-closed (raise). Corrupt/untrusted cache =
##     discard and recompute. Cache write failure is ignored (speed only).
##   - Same-UID processes are INSIDE the trust boundary (DEBT#524): this cache
##     does NOT defend against a same-UID writer forging it. The cache is never
##     evidence and never a verdict input.
##
## Non-posix platforms have no trustworthy stat identity -> the cached entry
## point falls back to a full read+digest.

import std/[os, strutils, json, times, algorithm, tables]

import core/trusted/axiom_pragmas
import core/utils/build_provenance

when defined(posix):
  import std/posix

axiomIoBoundary()

const
  SourceIdentitySchema* = "axiom-source-identity/1"
  SourceIdentityCacheRelPath* = ".axiom/cache/source_tree_identity.json"
  PosixSecondsToNs = 1_000_000_000'i64

type
  StatIdentity* = object
    ## Kernel-provided identity of one source file (lstat, no symlink follow).
    dev*, ino*, size*: int64
    mtimeNs*, ctimeNs*: int64
    mode*: int64
    kind*: string

  SourceIdentityStats* = object
    reused*, rehashed*, racy*: int

  CacheEntry = object
    relPath: string
    ident: StatIdentity
    digest: string

  CacheFile = object
    writtenAtNs: int64
    entries: seq[CacheEntry]

  RestatHook* = proc(path: string) {.closure, raises: [].}
    ## Test seam: called exactly once per file, after the first stat and before
    ## the content read. Production passes nil (it exists so the
    ## scan-time-mutation path can be exercised deterministically).

func permMask(p: set[FilePermission]): int64 {.raises: [].} =
  var i = 0
  for fp in FilePermission:
    if fp in p:
      result = result or (1'i64 shl i)
    inc i

proc statIdentity*(path: string): StatIdentity {.
    raises: [CatchableError], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## lstat-based identity. Raises on any stat failure (fail-closed).
  when defined(posix):
    var st: Stat
    if lstat(path.cstring, st) != 0:
      raise newException(IOError, "cannot stat source file: " & path)
    result.dev = int64(st.st_dev)
    result.ino = int64(st.st_ino)
    result.size = int64(st.st_size)
    result.mtimeNs = int64(st.st_mtim.tv_sec) * PosixSecondsToNs + int64(st.st_mtim.tv_nsec)
    result.ctimeNs = int64(st.st_ctim.tv_sec) * PosixSecondsToNs + int64(st.st_ctim.tv_nsec)
    result.mode = int64(st.st_mode)
    let kindBits = int64(st.st_mode) and int64(S_IFMT)
    result.kind = if kindBits == int64(S_IFREG): "file"
                  elif kindBits == int64(S_IFLNK): "link"
                  else: "other"
  else:
    let fi = getFileInfo(path, followSymlink = false)
    result.dev = int64(fi.id.device)
    result.ino = int64(fi.id.file)
    result.size = int64(fi.size)
    result.mtimeNs = fi.lastWriteTime.toUnix * PosixSecondsToNs + fi.lastWriteTime.nanosecond.int64
    result.ctimeNs = fi.creationTime.toUnix * PosixSecondsToNs + fi.creationTime.nanosecond.int64
    result.mode = permMask(fi.permissions)
    result.kind = if fi.kind == pcFile: "file" elif fi.kind == pcLinkToFile: "link" else: "other"

func sameIdentity*(a, b: StatIdentity): bool {.raises: [].} =
  a.dev == b.dev and a.ino == b.ino and a.size == b.size and
    a.mtimeNs == b.mtimeNs and a.ctimeNs == b.ctimeNs and
    a.mode == b.mode and a.kind == b.kind

func isRacy*(ident: StatIdentity; writtenAtNs: int64): bool {.raises: [].} =
  ## git racy-git rule at second granularity: a file whose mtime/ctime second
  ## is the same as (or newer than) the moment the cache was written may have
  ## been modified after the read within one timestamp tick -> rehash once.
  let fileSec = max(ident.mtimeNs, ident.ctimeNs) div PosixSecondsToNs
  let cacheSec = writtenAtNs div PosixSecondsToNs
  fileSec >= cacheSec

proc nowNs(): int64 {.raises: [].} =
  let t = getTime()
  t.toUnix * PosixSecondsToNs + t.nanosecond.int64

when defined(posix):
  proc cacheFileTrusted(path: string): bool {.raises: [].} =
    ## Only a regular file owned by the effective user and not group/other
    ## writable is read. Anything else is treated as absent (recompute).
    var st: Stat
    if lstat(path.cstring, st) != 0:
      return false
    if (int64(st.st_mode) and int64(S_IFMT)) != int64(S_IFREG):
      return false
    if st.st_uid != geteuid():
      return false
    if (int64(st.st_mode) and (int64(S_IWGRP) or int64(S_IWOTH))) != 0:
      return false
    true

proc loadCache(path: string): CacheFile {.raises: [].} =
  when not defined(posix):
    return
  else:
    result = CacheFile()
    if not fileExists(path) or not cacheFileTrusted(path):
      return
    try:
      let node = parseFile(path)
      if node{"schema"}.getStr("") != SourceIdentitySchema:
        return
      if node{"formula"}.getStr("") != BuildSourceHashFormula:
        return
      result.writtenAtNs = parseBiggestInt(node{"writtenAtNs"}.getStr("0"))
      let arr = node{"files"}
      if arr.kind != JArray:
        return
      for f in arr.items:
        result.entries.add(CacheEntry(
          relPath: f{"p"}.getStr(""),
          ident: StatIdentity(
            dev: parseBiggestInt(f{"dev"}.getStr("0")),
            ino: parseBiggestInt(f{"ino"}.getStr("0")),
            size: parseBiggestInt(f{"size"}.getStr("0")),
            mtimeNs: parseBiggestInt(f{"mtimeNs"}.getStr("0")),
            ctimeNs: parseBiggestInt(f{"ctimeNs"}.getStr("0")),
            mode: parseBiggestInt(f{"mode"}.getStr("0")),
            kind: f{"kind"}.getStr("")),
          digest: f{"digest"}.getStr("")))
    except CatchableError:
      result = CacheFile()

when defined(posix):
  proc renamePath(oldPath, newPath: cstring): cint {.
      importc: "rename", header: "<stdio.h>", sideEffect.}
    ## POSIX rename(2): atomic same-filesystem replacement; returns 0 on
    ## success. Deliberately not std/os.moveFile — that proc carries an
    ## unlisted `Exception` raises surface (std/private/osfiles.nim:385), and
    ## this module's cache-write path is best-effort with an empty raises list.

proc saveCache(path: string; cache: CacheFile) {.raises: [].} =
  try:
    let dir = parentDir(path)
    if not dirExists(dir):
      createDir(dir)
    let files = newJArray()
    for e in cache.entries:
      files.add(%*{
        "p": e.relPath,
        "dev": $e.ident.dev,
        "ino": $e.ident.ino,
        "size": $e.ident.size,
        "mtimeNs": $e.ident.mtimeNs,
        "ctimeNs": $e.ident.ctimeNs,
        "mode": $e.ident.mode,
        "kind": e.ident.kind,
        "digest": e.digest})
    let body = %*{
      "schema": SourceIdentitySchema,
      "formula": BuildSourceHashFormula,
      "writtenAtNs": $cache.writtenAtNs,
      "files": files}
    let tmpPath = path & ".tmp." & $getCurrentProcessId()
    writeFile(tmpPath, $body)
    when defined(posix):
      discard chmod(tmpPath.cstring, 0o600)
      if renamePath(tmpPath.cstring, path.cstring) != 0:
        discard tryRemoveFile(tmpPath)
    else:
      moveFile(tmpPath, path)
  except CatchableError:
    discard

proc computeSourceTreeDigestUncached*(srcDir: string): string {.
    raises: [CatchableError], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Full gather + digest (fail-closed). The universe is unchanged from the
  ## pre-vs1 probe: walk srcDir, `.nim` only, exclude `/generated/`, regular
  ## files yielded by walkDirRec. Unreadable files raise.
  var relFiles: seq[tuple[relPath: string, content: string]] = @[]
  for f in walkDirRec(srcDir):
    if f.endsWith(".nim") and not f.contains("/generated/"):
      try:
        relFiles.add((relativePath(f, srcDir, '/'), readFile(f)))
      except CatchableError as e:
        raise newException(OSError, "SourceCoherence FAIL: unreadable source file " & f & " — " & e.msg)
  hashSourceContents(relFiles)

proc readAndDigestStable(path: string; first: StatIdentity):
    tuple[digest: string, ident: StatIdentity] {.
    raises: [CatchableError], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read, then re-stat. A mismatch means the file changed during the read:
  ## retry once, then fail closed (never return a digest of an unstable file).
  var ident = first
  for _ in 0 .. 1:
    let content = readFile(path)
    let after = statIdentity(path)
    if sameIdentity(ident, after):
      return (fileContentDigest(content), after)
    ident = after
  raise newException(IOError, "source file changed while hashing: " & path)

proc computeSourceTreeDigestCachedWithStats*(srcDir, cachePath: string;
    stats: var SourceIdentityStats;
    afterFirstStat: RestatHook = nil): string {.
    raises: [CatchableError], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Incremental gather: per-file digests are reused only under an unchanged
  ## stat identity and a non-racy entry; the outer digest is always recomposed
  ## from the live walk. Writes the refreshed cache (best-effort).
  when not defined(posix):
    stats.rehashed = -1
    return computeSourceTreeDigestUncached(srcDir)
  else:
    let cache = loadCache(cachePath)
    var cached = initTable[string, CacheEntry]()
    for e in cache.entries:
      cached[e.relPath] = e

    var entries: seq[tuple[relPath: string, fileDigest: string]] = @[]
    var fresh: seq[CacheEntry] = @[]

    for f in walkDirRec(srcDir):
      if not (f.endsWith(".nim") and not f.contains("/generated/")):
        continue
      let rel = relativePath(f, srcDir, '/')
      let first = statIdentity(f)
      if afterFirstStat != nil:
        afterFirstStat(f)

      var digest = ""
      var ident = first
      var reused = false
      if cached.hasKey(rel):
        let e = cached[rel]
        if sameIdentity(e.ident, first) and not isRacy(e.ident, cache.writtenAtNs):
          digest = e.digest
          reused = true
        elif sameIdentity(e.ident, first):
          inc stats.racy
      if not reused:
        let stable = readAndDigestStable(f, first)
        digest = stable.digest
        ident = stable.ident
        inc stats.rehashed
      else:
        inc stats.reused

      entries.add((rel, digest))
      fresh.add(CacheEntry(relPath: rel, ident: ident, digest: digest))

    result = sourceTreeDigest(entries)
    # Zero-footprint: rewrite only when the cache would actually change. A
    # fully-reused run leaves the previous file (and its writtenAtNs) intact —
    # the racy rule stays conservative because the older write time can only
    # make more entries racy, never fewer.
    if stats.rehashed > 0 or cache.entries.len != fresh.len:
      saveCache(cachePath, CacheFile(writtenAtNs: nowNs(), entries: fresh))

proc computeSourceTreeDigestCached*(srcDir, cachePath: string;
    afterFirstStat: RestatHook = nil): string {.
    raises: [CatchableError], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var stats: SourceIdentityStats
  computeSourceTreeDigestCachedWithStats(srcDir, cachePath, stats, afterFirstStat)

{.pop.}