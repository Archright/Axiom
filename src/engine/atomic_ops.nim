## atomic_ops.nim — Atomic file operations for the Task DAG engine
##
## Provides crash-safe file writes (write-to-temp + fsync + rename),
## POSIX file locking via `flock(2)`, and error-lifted POSIX `rename(2)`.
##
## All procs live at the I/O boundary and lift OS errors into Result[T, string].
## Temp files are created in the same directory as the target to guarantee
## same-filesystem rename (POSIX requirement).

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}
# axiomIoBoundary

import core/axiom_pragmas
import std/os
import std/posix
import core/results

# ---------------------------------------------------------------------------
# POSIX low-level bindings (not re-exported by std/posix on Linux)
# ---------------------------------------------------------------------------

const
  LOCK_EX* = cint(2)   ## Exclusive lock
  LOCK_UN* = cint(8)   ## Unlock

  O_CREAT*  = cint(0o100)
  O_WRONLY* = cint(0o1)
  O_RDWR*   = cint(0o2)
  O_TRUNC*  = cint(0o1000)
  O_APPEND* = cint(0o2000)

  S_IRUSRW* = Mode(0o600)  ## rw-------
  S_IRGRP*  = Mode(0o040)  ## r--------
  S_IWGRP*  = Mode(0o020)  ## -w-------

proc c_flock(fd: cint, operation: cint): cint {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], importc: "flock", header: "<sys/file.h>", sideEffect.}

proc c_rename(oldpath: cstring, newpath: cstring): cint {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], importc: "rename", header: "<stdio.h>", sideEffect.}

proc c_fsync(fd: cint): cint {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], importc: "fsync", header: "<unistd.h>", sideEffect.}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc osError(context: string): string  {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Build a descriptive error string from the current errno.
  let code = posix.errno
  let msg = $posix.strerror(code)
  context & " (errno=" & $code & ": " & msg & ")"

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

proc atomicWrite*(path: string, content: string): Result[void, string] {.axiomEffect: IOEffect.} =

  ## Write `content` to `path` atomically.
  ##
  ## 1. Create temp file in same directory as `path` (same-filesystem guarantee).
  ## 2. Write content via POSIX write(2).
  ## 3. fsync to durable storage.
  ## 4. Rename temp → target (atomic on POSIX).
  ##
  ## On any failure the temp file is cleaned up and an error returned.
  let dir = parentDir(path)
  if dir.len == 0:
    return err("atomicWrite: empty directory for path: " & path)

  # Ensure target directory exists
  if not dirExists(dir):
    try:
      createDir(dir)
    except CatchableError as e:
      return err("atomicWrite: createDir " & dir & ": " & e.msg)

  # Temp file in same directory: .axiom_atomic_<basename>_<pid>
  let baseName = extractFilename(path)
  let tmpName = ".axiom_atomic_" & baseName & "_" & $posix.getpid()
  let tmpPath = dir / tmpName

  # Step 1: open + write
  let fd = posix.open(tmpPath.cstring,
                      O_CREAT or O_WRONLY or O_TRUNC,
                      S_IRUSRW or S_IRGRP or S_IWGRP)
  if fd < 0:
    let msg = osError("atomicWrite: open " & tmpPath)
    return err(msg)

  var writeOk = true
  if content.len > 0:
    let written = posix.write(fd, unsafeAddr content[0], content.len)
    if written < content.len:
      writeOk = false

  if not writeOk:
    discard posix.close(fd)
    discard posix.unlink(tmpPath.cstring)
    let msg = osError("atomicWrite: write " & tmpPath)
    return err(msg)

  # Step 2: fsync then close
  discard c_fsync(fd)
  discard posix.close(fd)

  # Step 3: atomic rename
  let rc = c_rename(tmpPath.cstring, path.cstring)
  if rc != 0:
    discard posix.unlink(tmpPath.cstring)
    let msg = osError("atomicWrite: rename " & tmpPath & " → " & path)
    return err(msg)

  Result[void, string](ok: true)

proc safeRename*(source: string, dest: string): Result[void, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## POSIX rename(2) wrapper with error lifting.
  ## Atomically moves `source` to `dest` (same-filesystem required).
  if source.len == 0:
    return err("safeRename: empty source path")
  if dest.len == 0:
    return err("safeRename: empty dest path")

  let rc = c_rename(source.cstring, dest.cstring)
  if rc != 0:
    let msg = osError("safeRename: " & source & " → " & dest)
    return err(msg)

  Result[void, string](ok: true)

proc withFlock*[T](lockPath: string, body: proc(): T {.gcsafe.}): Result[T, string] {.axiomEffect: IOEffect.} =
  ## POSIX flock(2) wrapper — exclusive lock with automatic release.
  ##
  ## Opens (or creates) `lockPath`, acquires an exclusive lock, runs `body`,
  ## releases the lock, and closes the fd. The lock is released even if
  ## `body` raises.
  if lockPath.len == 0:
    return err("withFlock: empty lock path")

  let dir = parentDir(lockPath)
  if dir.len > 0 and not dirExists(dir):
    return err("withFlock: parent directory does not exist: " & dir)

  let fd = posix.open(lockPath.cstring,
                      O_CREAT or O_RDWR,
                      S_IRUSRW or S_IRGRP or S_IWGRP)
  if fd < 0:
    let msg = osError("withFlock: open " & lockPath)
    return err(msg)

  # Acquire exclusive lock (blocking)
  let lockRc = c_flock(fd, LOCK_EX)
  if lockRc != 0:
    discard posix.close(fd)
    let msg = osError("withFlock: flock LOCK_EX " & lockPath)
    return err(msg)

  # Run body; release lock + close fd in all cases
  var bodyResult: T
  var bodyError: string
  var raised = false
  try:
    bodyResult = body()
  except CatchableError as e:
    bodyError = e.msg
    raised = true
  finally:
    discard c_flock(fd, LOCK_UN)
    discard posix.close(fd)

  if raised:
    return err("withFlock: body raised: " & bodyError)
  return ok(bodyResult)

{.pop.}

