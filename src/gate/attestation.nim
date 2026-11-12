import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

import core/axiom_pragmas
import std/[json, posix]
import core/results

proc posixRename(oldpath, newpath: cstring): cint {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], importc: "rename", header: "<stdio.h>", noSideEffect.}

const O_DIRECTORY {.importc, header: "<fcntl.h>".}: cint = 0

type
  AttestationManifest* = object
    version*: int                    ## 1
    stage*: string                   ## "pre-commit" | "pre-push" | "ci"
    commitHash*: string              ## git rev-parse HEAD
    treeHash*: string                ## git write-tree — staged index Merkle root
    branch*: string                  ## git rev-parse --abbrev-ref HEAD
    timestamp*: int64                ## Unix epoch
    totalDurationNs*: int64          ## 파이프라인 총 소요시간
    gateCount*: int                  ## 실행된 게이트 수
    passedCount*: int                ## 통과 게이트 수
    failedCount*: int                ## 실패 게이트 수
    cachedCount*: int                ## 캐시 히트 게이트 수
    bottleneckId*: string            ## 가장 느린 게이트 ID
    bottleneckNs*: int64             ## 가장 느린 게이트 소요시간
    contextId*: string               ## AXIOM_GATE_CONTEXT_ID 값
    receiptHash*: string             ## SHA-256(above fields + signing_key)
    binaryFreshnessOk*: bool         ## gate_hook binary freshness
    manifestHash*: string            ## manifest.d content hash

proc toJson*(att: AttestationManifest): JsonNode {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result = newJObject()
  result["version"] = newJInt(att.version)
  result["stage"] = newJString(att.stage)
  result["commitHash"] = newJString(att.commitHash)
  result["treeHash"] = newJString(att.treeHash)
  result["branch"] = newJString(att.branch)
  result["timestamp"] = newJInt(att.timestamp)
  result["totalDurationNs"] = newJInt(att.totalDurationNs)
  result["gateCount"] = newJInt(att.gateCount)
  result["passedCount"] = newJInt(att.passedCount)
  result["failedCount"] = newJInt(att.failedCount)
  result["cachedCount"] = newJInt(att.cachedCount)
  result["bottleneckId"] = newJString(att.bottleneckId)
  result["bottleneckNs"] = newJInt(att.bottleneckNs)
  result["contextId"] = newJString(att.contextId)
  result["receiptHash"] = newJString(att.receiptHash)
  result["binaryFreshnessOk"] = newJBool(att.binaryFreshnessOk)
  result["manifestHash"] = newJString(att.manifestHash)

proc ensureParentDir(dir: cstring): Result[void, string] =
  ## POSIX mkdir, EEXIST treated as success.
  let rc = mkdir(dir, 0o755)
  if rc == 0 or errno == EEXIST: result = Result[void, string](ok: true)
  else: result = Result[void, string](ok: false, err: "mkdir(" & $dir & "): errno=" & $errno)

proc atomicWriteFile(path: cstring; content: string): Result[void, string] {.axiomEffect: IOEffect.} =
  ## POSIX open+write+fsync+close. defer prevents fd leaks.
  if content.len == 0:
    # Empty file: avoid IndexDefect. fsync included (O_CREAT inode = dir metadata change)
    let fd = open(path, O_WRONLY or O_CREAT or O_TRUNC, 0o644)
    if fd < 0: return err("open(" & $path & "): errno=" & $errno)
    defer: discard close(fd)
    if fsync(fd) != 0:
      if errno == EINTR: discard
      else: return err("fsync(" & $path & "): errno=" & $errno)
    return Result[void, string](ok: true)
  let fd = open(path, O_WRONLY or O_CREAT or O_TRUNC, 0o644)
  if fd < 0: return err("open(" & $path & "): errno=" & $errno)
  defer: discard close(fd)
  let basePtr = cast[int](cstring(content))
  var off = 0
  while off < content.len:
    let n = write(fd, cast[pointer](basePtr + off), content.len - off)
    if n < 0:
      if errno == EINTR:
        continue
      return err("write(" & $path & "): errno=" & $errno)
    elif n == 0:
      return err("write(" & $path & "): returned 0 unexpectedly")
    off += n
  if fsync(fd) != 0:
    if errno == EINTR:
      discard
    else:
      return err("fsync(" & $path & "): errno=" & $errno)
  Result[void, string](ok: true)

proc fsyncDirectory(dir: cstring): Result[void, string] {.axiomEffect: IOEffect.} =
  ## Directory fsync after rename — power failure durability.
  when defined(windows):
    Result[void, string](ok: true)
  else:
    let dirFd = open(dir, O_RDONLY or O_DIRECTORY)
    if dirFd < 0: return err("open_dir(" & $dir & "): errno=" & $errno)
    defer: discard close(dirFd)
    if fsync(dirFd) != 0: return err("fsync_dir(" & $dir & "): errno=" & $errno)
    Result[void, string](ok: true)

proc writeAttestation*(att: AttestationManifest; repoRoot: string): Result[void, string] {.axiomEffect: IOEffect.} =
  ## Atomic write: temp + fsync + rename + dir_fsync.
  ## Durability: write → fsync(file) → rename → fsync(dir)
  let dir = repoRoot & "/.axiom"
  let path = dir & "/gate_receipt.json"
  let tmp = path & ".tmp"
  # Manual isErr propagation — ?? macro requires non-void T for .get()
  let r1 = ensureParentDir(cstring(dir))
  if r1.isErr: return err(r1.error)
  let r2 = atomicWriteFile(cstring(tmp), att.toJson().pretty())
  if r2.isErr: return err(r2.error)
  if posixRename(cstring(tmp), cstring(path)) != 0:
    return err("posixRename(" & $tmp & " -> " & $path & "): errno=" & $errno)
  let r3 = fsyncDirectory(cstring(dir))
  if r3.isErr: return err(r3.error)
  Result[void, string](ok: true)

{.pop.}

