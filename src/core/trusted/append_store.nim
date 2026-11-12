import core/trusted/layer_declaration
axiomLayer "trusted"
{.push raises: [].}

import std/json
import std/strutils
import std/os
import std/tables
import std/posix
import core/utils/io_utils
import core/axiom_pragmas

## Generic durable atomic file primitive.
##
## This module holds NO domain semantics (no claim/solver/certificate knowledge).
## Trust semantics live in `trust_commit.nim`; domain JSON serialization lives in
## `claim_store_append.nim`. Dependency direction:
##
##   trust_commit -> append_store -> filesystem
##
## Durability contract (I6): appendRecord performs
##   write(tmp) -> fsync(tmp) -> rename(tmp, path) -> fsync(parentDir)
## so a single appended record is either fully present or fully absent after a
## crash — the atomic rename is the commit marker.

when defined(windows):
  proc fsyncDirHandle(dir: string): bool {.inline.} =
    true  # Windows: directory fsync not applicable (existing attestation pattern)
else:
  const O_DIRECTORYFlags {.importc: "O_DIRECTORY", header: "<fcntl.h>".}: cint = 0
  proc fsyncDirHandle(dir: string): bool {.raises: [], axiomEffect: IOEffect.} =
    ## POSIX directory fsync after rename — power-failure durability.
    let dfd = open(cstring(dir), O_RDONLY or O_DIRECTORYFlags)
    if dfd < 0:
      return false
    defer: discard close(dfd)
    fsync(dfd) == 0

proc fsyncFileHandle(path: string): bool {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## POSIX fsync of an already-written file's data + metadata before rename.
  when defined(windows):
    true
  else:
    let fd = open(cstring(path), O_RDONLY)
    if fd < 0:
      return false
    defer: discard close(fd)
    fsync(fd) == 0

proc syncedFile(path: string): bool {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## File-level fsync gate; on non-POSIX we accept the write (no sync primitive).
  when defined(windows):
    true
  else:
    fsyncFileHandle(path)

type AppendStoreKind* = enum
  skClaims
  skSolver

func storeDir*(baseDir: string; kind: AppendStoreKind): string =
  case kind
  of skClaims: baseDir & "/claims"
  of skSolver: baseDir & "/solver"

proc appendRecord*(path: string; line: string): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Append one record atomically and durably. A rename-committed final file is
  ## the commit point; a crash before rename leaves only `.tmp` (ignored on the
  ## next read), and after rename the record is durable.
  let tmpPath = path & ".tmp"
  # Fail-closed (I5): if the existing store file cannot be read, do NOT silently
  # fall back to an empty baseline — a read failure here means we must not risk
  # overwriting prior committed records. Return false and leave the file intact.
  let existing = if fileExists(path):
    let res = readFileOpt(path)
    if not res.ok:
      return false
    res.value
  else:
    ""
  let combined = existing & line & "\n"
  if not writeFileOpt(tmpPath, combined).ok:
    return false
  if not syncedFile(tmpPath):
    return false
  if not moveFileOpt(tmpPath, path).ok:
    try:
      removeFile(tmpPath)
    except CatchableError:  # axiom:best-effort("best-effort temp cleanup; original failure already returned false")
      discard
    return false
  if not fsyncDirHandle(parentDir(path)):
    return false
  true

proc writeRecord*(path: string; content: string): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Write one immutable record to a fresh file durably. Unlike appendRecord,
  ## never reads an existing destination — safe for single-record journal files
  ## (file == one record). Same write(tmp)->fsync->rename->fsync(parentDir)
  ## durability chain. Caller guarantees single-writer immutability.
  let tmpPath = path & ".tmp"
  if not writeFileOpt(tmpPath, content).ok:
    return false
  if not syncedFile(tmpPath):
    try:
      removeFile(tmpPath)
    except CatchableError:  # axiom:best-effort("best-effort temp cleanup; original failure already returned false")
      discard
    return false
  if not moveFileOpt(tmpPath, path).ok:
    try:
      removeFile(tmpPath)
    except CatchableError:  # axiom:best-effort("best-effort temp cleanup; original failure already returned false")
      discard
    return false
  if not fsyncDirHandle(parentDir(path)):
    return false
  true

proc readRecords*(path: string): seq[string] {.axiomDecision(id = "DECISION-0635", reason = "Read records from append-store file with early-return validation", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v33").} =
  if not fileExists(path):
    return @[]
  let res = readFileOpt(path)
  if not res.ok:
    return @[]
  let content = res.value
  if content.len == 0:
    return @[]
  let lines = content.splitLines()
  if content.endsWith("\n"):
    if lines.len > 0 and lines[^1] == "":
      lines[0 .. ^2]
    else:
      lines
  else:
    if lines.len > 0:
      lines[0 .. ^2]
    else:
      @[]

func claimIdUniqueness*(records: seq[string]): bool {.inline.} =
  var seen: Table[string, bool]
  for record in records:
    if record.len == 0:
      continue
    let key = "\"claimId\":\""
    let start = record.find(key)
    if start < 0:
      continue
    let valueStart = start + key.len
    let endPos = record.find('"', valueStart)
    if endPos < 0:
      continue
    let id = record[valueStart .. endPos - 1]
    if seen.hasKey(id):
      return false
    seen[id] = true
  true

{.pop.}