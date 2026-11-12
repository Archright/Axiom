import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}
## Toolchain Lock Verifier — in-process module
## Reads data/toolchain_lock.json and verifies binary SHA-256 hashes.
## Parallel hash computation + mtime/size cache for O(1) repeat verification.

import std/[json, os, posix, strutils]
import checksums/sha2
import malebolgia
import safe_move

# ── Shared types via project SSOT (works both standalone and as library) ──
import shared_types/shared_types

type
  ToolResult = object
    name: string
    hash: string
    err: string

proc hashFileStreaming(path: string): string {.axiomEffect: IOEffect.} =
  ## O(1) 메모리 스트리밍 해시 — 64KB 버퍼로 syscall 횟수 최소화
  var hasher = initSha_256()
  var f: File
  if not open(f, path, fmRead):
    raise newException(IOError, "cannot open: " & path)
  try:
    var buffer: array[65536, char]
    while true:
      let bytesRead = f.readBuffer(addr buffer[0], 65536)
      if bytesRead == 0: break
      hasher.update(buffer.toOpenArray(0, bytesRead - 1))
  finally:
    f.close()
  result = $hasher.digest()

proc getFileStats(path: string): tuple[mtime: int64, size: int64] =
  var st: Stat
  if stat(path.cstring, st) == 0:
    return (st.st_mtime.int64, st.st_size.int64)
  return (0, 0)

proc expandLockPath(p: string): string {.axiomEffect: IOEffect.} =
  ## Publication trees scrub $HOME to "<user-home>"; resolve it back for local verification.
  const homeToken = "<user-home>"
  if p.startsWith(homeToken):
    getHomeDir() / p[homeToken.len .. ^1]
  else:
    p

proc hashOneTool(binPath: string, resultPtr: ptr ToolResult) {.gcsafe.} =
  try:
    if not fileExists(binPath):
      resultPtr[] = ToolResult(name: "", err: "binary not found: " & binPath)
    else:
      resultPtr[] = ToolResult(hash: hashFileStreaming(binPath))
  except CatchableError as e:
    resultPtr[] = ToolResult(err: e.msg)

proc verifyToolchainLock*(projectRoot: string): Result[void, string] {.axiomEffect: IOEffect.} =
  ## Verify toolchain binaries match data/toolchain_lock.json.
  ## Uses mtime+size cache + parallel hash for repeat verification.
  try:
    let lockPath = projectRoot / "data" / "toolchain_lock.json"
    if not fileExists(lockPath):
      return Result[void, string](ok: true)

    let lockData = parseFile(lockPath)
    let cachePath = projectRoot / ".axiom" / "toolchain_cache.json"
    var cache = if fileExists(cachePath):
      try: parseFile(cachePath)
      except CatchableError: newJObject()
    else: newJObject()

    let tools = ["nim", "z3", "lean", "lake"]

    # 1단계: 캐시 미스 대상 선별 (mtime + size + hash 검증)
    var missTools: seq[string] = @[]
    for toolName in tools:
      if toolName notin lockData: continue
      let binPath = expandLockPath(lockData[toolName]["path"].getStr())
      let expectedHash = lockData[toolName]["binary_sha256"].getStr()
      let (currentMtime, currentSize) = getFileStats(binPath)

      if toolName in cache and
         cache[toolName]["mtime"].getBiggestInt() == currentMtime and
         cache[toolName]["size"].getBiggestInt() == currentSize and
         cache[toolName]["hash"].getStr() == expectedHash:
        continue

      missTools.add(toolName)

    # 2단계: 캐시 미스된 자원만 병렬 해시 계산
    if missTools.len > 0:
      var results = newSeq[ToolResult](missTools.len)
      var m = createMaster()

      m.awaitAll:
        for i, toolName in missTools:
          let binPath = expandLockPath(lockData[toolName]["path"].getStr())
          m.spawn hashOneTool(binPath, addr results[i])

      # 결과 검증 및 캐시 업데이트
      var cacheChanged = false
      for i, toolName in missTools:
        if results[i].err.len > 0: return err(results[i].err)
        let expectedHash = lockData[toolName]["binary_sha256"].getStr()
        if results[i].hash != expectedHash:
          return err(toolName & " hash mismatch: expected " & expectedHash[0..7] &
                     "..., got " & results[i].hash[0..7] & "...")

        let binPath = expandLockPath(lockData[toolName]["path"].getStr())
        let (currentMtime, currentSize) = getFileStats(binPath)
        cache[toolName] = %*{
          "mtime": currentMtime,
          "size": currentSize,
          "hash": expectedHash
        }
        cacheChanged = true

      # 3단계: 원자적 파일 쓰기 (writeFile + rename)
      if cacheChanged:
        let tmpPath = cachePath & ".tmp"
        try:
          writeFile(tmpPath, cache.pretty())
          try: safeMoveFile(tmpPath, cachePath)
          except FileMoveError: discard
        except CatchableError:
          discard  # cache write failure is non-fatal

    return Result[void, string](ok: true)
  except CatchableError as e:
    return err("toolchain_verify exception: " & e.msg)

when isMainModule:
  proc findRoot(): string =
    var dir = getCurrentDir()
    while dir.len > 1:
      if fileExists(dir / ".axiom_root"): return dir
      dir = parentDir(dir)
    result = ""

  proc main() =
    let root = findRoot()
    if root.len == 0:
      echo "ERROR: .axiom_root not found"
      quit(1)
    let res = verifyToolchainLock(root)
    if res.isErr:
      echo "TOOLCHAIN MISMATCH: " & res.error
      quit(1)
    echo "Toolchain lock verified OK"

  main()

{.pop.}