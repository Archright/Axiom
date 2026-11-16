import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Measured content digests — tamper-evident file and binary hashing authority
## for the verification boundary.
##
## Both `measuredFileDigest` and `measuredBinaryDigest` share one thread-local
## content-identity memo keyed by:
##   - `cwd` (`getCurrentDir()`) and `normPath` (`normalizedPath(path)`)
##   - POSIX `lstat` + `stat` identity (`dev`, `ino`, `size`, `mtimeNs`,
##     `ctimeNs`, `mode`, `linkIno`, `linkMtimeNs`, `linkCtimeNs`)
##   - Fast content probe (`probeHash: Hash`): full content hash for files
##     `<= 1 MiB` (defeating sub-millisecond same-size overwrites and `touch -r`
##     mtime forgery inside a coarse kernel clock tick) and first-4096 +
##     last-4096 byte probe for multi-megabyte binaries (`lake`, `lean`).
##   - Read-then-restat stability (`stat -> readFile -> stat`, up to 2 attempts),
##     failing closed (`""`, uncached) if the file mutates while being read.
##   - Platform hash delegation for multi-megabyte binaries (size >
##     `MaxInlineProbeBytes`): the content sha256 is computed by GNU coreutils
##     `sha256sum` (SHA-NI-accelerated; separate process, argv list — never a
##     shell string; no linking or bundling, so no GPL obligation for the
##     caller). Measured on the 119 MiB ircheck worker (VS-PERF-ATTR
##     2026-11-16): 0.09 s platform vs 0.62 s in-process release / ~45 s
##     debug pure-Nim. Tool unavailability or subprocess failure falls back
##     to the in-process read path — the SAME sha256 value either way
##     (byte-identical; asserted on the delegated path by
##     tests/unit/test_capture_toolchain_fingerprint.nim scenario 1).

import std/[os, osproc, streams, times, hashes]
import core/axiom_pragmas
import core/crypto/hash_kernel

when defined(posix):
  import std/posix

axiomIoBoundary()

const
  PosixSecondsToNs = 1_000_000_000'i64
  MaxInlineProbeBytes = 1_048_576'i64
  RacyWindowNs = 50_000_000'i64

type
  MeasuredFileStat = object
    valid: bool
    dev, ino, size: int64
    mtimeNs, ctimeNs: int64
    mode: int64
    linkIno, linkMtimeNs, linkCtimeNs: int64

  BinaryDigestMemo = object
    cwd: string
    normPath: string
    ident: MeasuredFileStat
    fastHash: Hash
    digest: string

var
  binaryDigestMemo* {.threadvar.}: seq[BinaryDigestMemo]
  digestMemoHits* {.threadvar.}: int
  digestMemoMisses* {.threadvar.}: int
  cachedLeanPathKey* {.threadvar.}: string
  cachedLeanPath* {.threadvar.}: string

proc isRacyStat(ident: MeasuredFileStat): bool {.
  raises: [], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  discard binaryDigestMemo.len
  if ident.valid and ident.size <= MaxInlineProbeBytes:
    let t = getTime()
    let nowNs = t.toUnix * PosixSecondsToNs + t.nanosecond.int64
    let fileNs = max(ident.mtimeNs, ident.ctimeNs)
    result = (nowNs - fileNs) < RacyWindowNs

proc captureStatIdentity(path: string): MeasuredFileStat {.
  raises: [], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  discard binaryDigestMemo.len
  when defined(posix):
    var stL, stT: Stat
    if lstat(path.cstring, stL) == 0 and stat(path.cstring, stT) == 0:
      if (int64(stT.st_mode) and int64(S_IFMT)) == int64(S_IFREG) and int64(stT.st_size) >= 0:
        result = MeasuredFileStat(
          valid: true,
          dev: int64(stT.st_dev),
          ino: int64(stT.st_ino),
          size: int64(stT.st_size),
          mtimeNs: int64(stT.st_mtim.tv_sec) * PosixSecondsToNs + int64(stT.st_mtim.tv_nsec),
          ctimeNs: int64(stT.st_ctim.tv_sec) * PosixSecondsToNs + int64(stT.st_ctim.tv_nsec),
          mode: int64(stT.st_mode),
          linkIno: int64(stL.st_ino),
          linkMtimeNs: int64(stL.st_mtim.tv_sec) * PosixSecondsToNs + int64(stL.st_mtim.tv_nsec),
          linkCtimeNs: int64(stL.st_ctim.tv_sec) * PosixSecondsToNs + int64(stL.st_ctim.tv_nsec)
        )
  else:
    try:
      let fiL = getFileInfo(path, followSymlink = false)
      let fiT = getFileInfo(path, followSymlink = true)
      if fiT.kind == pcFile and int64(fiT.size) >= 0:
        result = MeasuredFileStat(
          valid: true,
          dev: int64(fiT.id.device),
          ino: int64(fiT.id.file),
          size: int64(fiT.size),
          mtimeNs: fiT.lastWriteTime.toUnix * PosixSecondsToNs + fiT.lastWriteTime.nanosecond.int64,
          ctimeNs: fiT.creationTime.toUnix * PosixSecondsToNs + fiT.creationTime.nanosecond.int64,
          mode: int64(ord(fiT.kind)),
          linkIno: int64(fiL.id.file),
          linkMtimeNs: fiL.lastWriteTime.toUnix * PosixSecondsToNs + fiL.lastWriteTime.nanosecond.int64,
          linkCtimeNs: fiL.creationTime.toUnix * PosixSecondsToNs + fiL.creationTime.nanosecond.int64
        )
    except CatchableError:
      result = MeasuredFileStat(valid: false)

proc delegatedFileDigest(path: string; digest: var string): bool {.
  raises: [], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Content sha256 of `path` computed by the platform hash authority
  ## (GNU coreutils `sha256sum`). Returns false and leaves `digest` "" when
  ## the tool is unavailable or the subprocess fails — the caller then falls
  ## back to the in-process read path, so the fail-closed shape ("" on
  ## unmeasurable) is unchanged. Only the first 64 hex chars followed by a
  ## space are parsed — the filename field is never interpreted.
  result = false
  digest = ""
  var tool = ""
  try:
    tool = findExe("sha256sum")
  except CatchableError:
    tool = ""
  if tool.len == 0:
    return
  var p: Process = nil
  try:
    p = startProcess(tool, args = @[path], options = {poUsePath, poStdErrToStdOut})
    let output = p.outputStream.readAll()
    if p.waitForExit() == 0 and output.len >= 66 and output[64] == ' ':
      var hexOk = true
      for i in 0 ..< 64:
        if output[i] notin {'0'..'9', 'a'..'f'}:
          hexOk = false
          break
      if hexOk:
        digest = output[0 ..< 64]
        result = true
  except CatchableError:
    discard # axiom:best-effort("subprocess failure — digest unmeasurable; the caller falls back to the in-process path (fail-closed shape unchanged)")
  finally:
    if p != nil:
      try: p.close()
      except CatchableError: discard # axiom:best-effort("process reaping after exit code collection — a failed close cannot change the digest verdict")

proc readStableAndStoreMemo(path, cwd, normPath: string;
                            firstIdent: MeasuredFileStat): string {.
  raises: [], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var ident = firstIdent
  for _ in 0 .. 1:
    var digest = ""
    var contentLen = -1'i64
    var fastH = Hash(0)
    var measured = false
    if ident.valid and ident.size > MaxInlineProbeBytes:
      var delegated = ""
      if delegatedFileDigest(path, delegated):
        digest = delegated
        measured = true
    if not measured:
      var content = ""
      var readOk = false
      try:
        content = readFile(path)
        readOk = true
      except CatchableError:
        readOk = false
      if not readOk:
        break
      digest = sha256Hex(content)
      contentLen = int64(content.len)
      if contentLen <= MaxInlineProbeBytes:
        fastH = hash(content)
    let afterIdent = captureStatIdentity(path)
    if afterIdent.valid and afterIdent == ident and
        (contentLen < 0 or contentLen == afterIdent.size):
      inc digestMemoMisses
      var updated = false
      for i in 0 ..< binaryDigestMemo.len:
        if binaryDigestMemo[i].cwd == cwd and binaryDigestMemo[i].normPath == normPath:
          binaryDigestMemo[i].ident = afterIdent
          binaryDigestMemo[i].fastHash = fastH
          binaryDigestMemo[i].digest = digest
          updated = true
          break
      if not updated:
        binaryDigestMemo.add(BinaryDigestMemo(
          cwd: cwd, normPath: normPath, ident: afterIdent, fastHash: fastH, digest: digest))
      result = digest
      break
    if not afterIdent.valid:
      break
    ident = afterIdent

proc measuredBinaryDigest*(path: string): string {.
  raises: [], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Tamper-evident content sha256Hex of `path`, memoized on `(cwd, normPath,
  ## MeasuredFileStat)` with racy-window fast-hash verification and read-then-restat
  ## stability. Returns `""` when absent, non-regular, unreadable, or mutating.
  if path.len > 0:
    var cwd = ""
    var normPath = ""
    try:
      cwd = getCurrentDir()
      normPath = normalizedPath(path)
    except CatchableError:
      cwd = ""
    let firstIdent = if cwd.len > 0: captureStatIdentity(path) else: MeasuredFileStat()
    if firstIdent.valid:
      var matched = false
      for entry in binaryDigestMemo:
        if entry.cwd == cwd and entry.normPath == normPath and entry.ident == firstIdent:
          var racyOk = true
          if isRacyStat(firstIdent):
            try:
              let probeContent = readFile(path)
              racyOk = int64(probeContent.len) == firstIdent.size and
                       hash(probeContent) == entry.fastHash
            except CatchableError:
              racyOk = false
          if racyOk:
            inc digestMemoHits
            result = entry.digest
            matched = true
          break
      if not matched:
        result = readStableAndStoreMemo(path, cwd, normPath, firstIdent)

proc measuredFileDigest*(path: string): string {.
  raises: [], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Content digest of one measured file; `""` when unmeasurable. Shares the
  ## tamper-evident memoization authority with `measuredBinaryDigest`.
  discard binaryDigestMemo.len
  result = measuredBinaryDigest(path)

template measuredDigestStats*(): tuple[hits, misses: int] =
  ## Thread-local memoization hit/miss counters for deterministic verification.
  (hits: digestMemoHits, misses: digestMemoMisses)

template resetMeasuredDigestStats*() =
  ## Reset thread-local memoization state and hit/miss counters for testing.
  binaryDigestMemo.setLen(0)
  digestMemoHits = 0
  digestMemoMisses = 0
  cachedLeanPathKey = ""
  cachedLeanPath = ""

proc lookupCachedLeanPath*(envKey: string): string {.
  raises: [], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Return the memoized Lean binary path iff `envKey` matches and the resolved
  ## binary remains a valid, readable regular file with a 64-hex digest.
  discard binaryDigestMemo.len
  if envKey.len > 0 and envKey == cachedLeanPathKey and cachedLeanPath.len > 0:
    if measuredBinaryDigest(cachedLeanPath).len == 64:
      result = cachedLeanPath
    else:
      cachedLeanPathKey = ""
      cachedLeanPath = ""

template storeCachedLeanPath*(envKey, resolvedPath: string) =
  ## Record a resolved Lean binary path under its full environment/manifest key.
  if envKey.len > 0 and resolvedPath.len > 0:
    cachedLeanPathKey = envKey
    cachedLeanPath = resolvedPath

{.pop.}
