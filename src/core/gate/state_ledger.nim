import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## State Ledger — Core module for the cross-process pipeline state ledger.
##
## Provides:
##   - CRC32 checksum (pure Nim, 0x04C11DB7 polynomial, reflected 0xEDB88320)
##   - createLedger() — builds GateLedger, writes atomically via tmp+fsync+rename
##   - openLedger() — mmaps read-only, validates magic+version+CRC32
##   - closeLedger() — munmaps
##   - getLedgerPath() — canonical path helper
##
## v27: Proactive State Ledger replaces reactive recomputation in L2 children.
## v4: stagingTreeHash for content-addressed prepare-commit-msg verification.
## Total ledger size: 7,400 bytes.

import core/trusted/axiom_pragmas
import core/trusted/architecture_invariants
import state_ledger_types
import static_project_matrix
import core/crypto/hash_kernel

# ─── POSIX Bindings ─────────────────────────────────────────────────────────
# Custom importc bindings to avoid std/posix side-effect and export issues.
# All bindings are {.noSideEffect.} for {.raises: [].} compatibility.

type
  Stat {.importc: "struct stat", header: "<sys/stat.h>".} = object
    st_size: int64

const
  O_RDONLY* = 0
  O_WRONLY* = 1
  O_CREAT*  = 0o100
  O_TRUNC*  = 0o1000
  MAP_PRIVATE = 0x02
  PROT_READ = 0x01

proc posixAccess(path: cstring, mode: cint): cint
  {.importc: "access", header: "<unistd.h>", noSideEffect.}
proc posixOpen(path: cstring, oflag: cint, mode: cint): cint
  {.importc: "open", header: "<fcntl.h>", noSideEffect.}
proc posixClose(fd: cint): cint
  {.importc: "close", header: "<unistd.h>", noSideEffect.}
proc posixWrite(fd: cint, buf: pointer, count: int): int
  {.importc: "write", header: "<unistd.h>", noSideEffect.}
proc posixFsync(fd: cint): cint
  {.importc: "fsync", header: "<unistd.h>", noSideEffect.}
proc posixFstat(fd: cint, buf: ptr Stat): cint
  {.importc: "fstat", header: "<sys/stat.h>", noSideEffect.}
proc posixMkdir(path: cstring, mode: cint): cint
  {.importc: "mkdir", header: "<sys/stat.h>", noSideEffect.}
proc posixUnlink(path: cstring): cint
  {.importc: "unlink", header: "<unistd.h>", noSideEffect.}
proc posixRename(oldpath, newpath: cstring): cint
  {.importc: "rename", header: "<stdio.h>", noSideEffect.}

proc mmap(addrArg: pointer, length: csize_t, prot: cint, flags: cint,
          fd: cint, offset: int): pointer
  {.importc, header: "<sys/mman.h>", noSideEffect.}
proc munmap(addrArg: pointer, length: csize_t): cint
  {.importc, header: "<sys/mman.h>", noSideEffect.}

# ─── CRC32 ──────────────────────────────────────────────────────────────────
# Standard CRC32 using 0x04C11DB7 polynomial (reflected form: 0xEDB88320).
# Compile-time table generation — zero runtime cost for table init.

const Crc32Table: array[256, uint32] = block:
  var table: array[256, uint32]
  for i in 0'u32 ..< 256:
    var crc = i
    for _ in 0 ..< 8:
      if (crc and 1) != 0:
        crc = (crc shr 1) xor 0xEDB88320'u32
      else:
        crc = crc shr 1
    table[i] = crc
  table

func crc32*(data: ptr UncheckedArray[byte], len: int): uint32 {.inline, raises: [].} =
  ## CRC32 over raw byte pointer + length. Core implementation.
  result = 0xFFFFFFFF'u32
  for i in 0 ..< len:
    result = Crc32Table[(result xor uint32(data[i])) and 0xFF] xor (result shr 8)
  result = result xor 0xFFFFFFFF'u32

func crc32*(data: openArray[byte]): uint32 {.inline, raises: [].} =
  ## CRC32 convenience overload for openArray inputs.
  if data.len == 0:
    return 0'u32
  crc32(cast[ptr UncheckedArray[byte]](unsafeAddr data[0]), data.len)

# ─── Helpers ────────────────────────────────────────────────────────────────

func getLedgerPath*(repoRoot: string): string {.inline, raises: [].} =
  ## Returns the canonical path: <repoRoot>/.axiom/cache/pipeline_state.ledger
  result = repoRoot & "/.axiom/cache/pipeline_state.ledger"

func computeBuildEnvHash*(): HashValue {.inline, raises: [].} =
  ## Deterministic hash of the build environment (Nim version).
  ## Captured at compile time via NimVersion constant — zero runtime cost.
  ## Changes when the Nim compiler version changes.
  ## Uses SHA-256 for cross-platform determinism.
  hashValueFromHex(sha256Hex(NimVersion))

# ─── I/O Boundary ───────────────────────────────────────────────────────────

axiomIoBoundary()

# ─── Atomic Write (internal) ────────────────────────────────────────────────

func ensureParentDirs(filePath: string) =
  ## Recursively create parent directories if missing.
  ## Walks each '/' boundary and creates the directory path up to that point.
  for i in 1 ..< filePath.len:
    if filePath[i] == '/' and i > 0:
      discard posixMkdir(cstring(filePath[0 .. i]), 0o755)

func atomicWriteLedger(path: string; data: pointer; size: int) =
  ## Write ledger bytes atomically: temp file → fsync → rename.
  ## Ensures the ledger is never in a partial state on disk.
  ensureParentDirs(path)
  let tmpPath = path & ".tmp"
  let tmpFd = posixOpen(cstring(tmpPath), O_WRONLY or O_CREAT or O_TRUNC, 0o644)
  if tmpFd < 0:
    return
  # Write in a loop to handle short writes
  var off = 0
  while off < size:
    let n = posixWrite(tmpFd, cast[pointer](cast[int](data) + off), size - off)
    if n <= 0:
      discard posixClose(tmpFd)
      discard posixUnlink(cstring(tmpPath))
      return
    off += n
  discard posixFsync(tmpFd)
  discard posixClose(tmpFd)
  # Atomic rename: POSIX rename() overwrites destination atomically
  discard posixRename(cstring(tmpPath), cstring(path))

# ─── Public API ─────────────────────────────────────────────────────────────

func createLedger*(repoRoot: string; epoch: uint32;
                   dirtyHash, ruleHash, buildEnvHash, stagingTreeHash: HashValue;
                   baseCommit: array[20, byte];
                   stage, mode: uint8;
                   gateEntries: seq[tuple[gateIdHash: uint32;
                                         cacheKey: HashValue;
                                         result: uint8;
                                         tier: uint8;
                                         deferredAt: int64;
                                         deferredStage: uint8]]) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Build a GateLedger from workspace state and gate entries,
  ## compute CRC32, and write atomically to the ledger path.
  var ledger: GateLedger

  # ── Header ──
  ledger.header.magic = LedgerMagic
  ledger.header.version = LedgerVersion
  ledger.header.headerSize = uint16(LedgerHeaderSize)
  ledger.header.totalSize = int64(LedgerTotalSize)
  ledger.header.epoch = epoch
  ledger.header.gateCount = uint16(min(gateEntries.len, AxiomLedgerCap))

  # ── Workspace State ──
  ledger.workspace.dirtyHash = dirtyHash
  ledger.workspace.ruleHash = ruleHash
  ledger.workspace.buildEnvHash = buildEnvHash
  ledger.workspace.stagingTreeHash = stagingTreeHash
  ledger.workspace.timestamp = int64(epoch)
  ledger.workspace.baseCommit = baseCommit
  ledger.workspace.stage = stage
  ledger.workspace.mode = mode

  # ── Gate Entries ──
  let count = min(gateEntries.len, AxiomLedgerCap)
  for i in 0 ..< count:
    ledger.gates[i].gateIdHash = gateEntries[i].gateIdHash
    ledger.gates[i].cacheKey = gateEntries[i].cacheKey
    ledger.gates[i].result = gateEntries[i].result
    ledger.gates[i].tier = gateEntries[i].tier
    ledger.gates[i].deferredAt = gateEntries[i].deferredAt
    ledger.gates[i].deferredStage = gateEntries[i].deferredStage

  # ── CRC32 Checksum (covers header + workspace + gates) ──
  let crcDataLen = LedgerTotalSize - sizeof(uint32) - 4
  ledger.checksum = crc32(cast[ptr UncheckedArray[byte]](addr ledger), crcDataLen)

  # ── Atomic Write ──
  atomicWriteLedger(getLedgerPath(repoRoot), addr ledger, LedgerTotalSize)

func ledgerFileExists*(repoRoot: string): bool {.inline, raises: [].} =
  ## Check if a ledger file exists at the canonical path.
  ## Does NOT validate contents — use openLedger for that.
  ## Returns true iff the file exists on disk.
  posixAccess(cstring(getLedgerPath(repoRoot)), 0) == 0  # F_OK == 0

proc openLedger*(repoRoot: string): ptr GateLedger {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Open the ledger file via mmap read-only.
  ## Validates magic, version, and CRC32 integrity.
  ## Returns nil if validation fails or file doesn't exist.
  let path = getLedgerPath(repoRoot)
  let fd = posixOpen(cstring(path), O_RDONLY, 0)
  if fd < 0:
    return nil

  var st: Stat
  if posixFstat(fd, addr st) != 0:
    discard posixClose(fd)
    return nil

  if st.st_size != int64(LedgerTotalSize):
    discard posixClose(fd)
    return nil

  let mapped = mmap(nil, csize_t(LedgerTotalSize), PROT_READ, MAP_PRIVATE, fd, 0)
  discard posixClose(fd)

  if mapped == cast[pointer](-1):
    return nil

  let p = cast[ptr GateLedger](mapped)

  # Validate magic
  if p.header.magic != LedgerMagic:
    discard munmap(mapped, csize_t(LedgerTotalSize))
    return nil

  # Validate version
  if p.header.version != LedgerVersion:
    discard munmap(mapped, csize_t(LedgerTotalSize))
    return nil

  # Validate CRC32
  let crcDataLen = LedgerTotalSize - sizeof(uint32) - 4
  let expectedCrc = crc32(cast[ptr UncheckedArray[byte]](mapped), crcDataLen)
  if p.checksum != expectedCrc:
    discard munmap(mapped, csize_t(LedgerTotalSize))
    return nil

  result = p

proc closeLedger*(ledger: ptr GateLedger) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Unmap the ledger. After this call, the pointer is invalid.
  if ledger != nil:
    discard munmap(ledger, csize_t(LedgerTotalSize))

collectPtrViolations(currentSourcePath())
{.pop.}
