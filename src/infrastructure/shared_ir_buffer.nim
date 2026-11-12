import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Shared IR Buffer — mmap-based Zero-Copy IPC for Lean 4 Worker Verification
##
## Provides shared-memory regions for passing IR (Intermediate Representation)
## payloads between the orchestrator and Lean 4 verification workers via POSIX
## shared memory objects (shm_open / mmap). The layout is:
##
##   ┌──────────────────┐  offset 0
##   │ SharedIRHeader   │  64 bytes (8-byte aligned)
##   ├──────────────────┤  offset irOffset (8-byte aligned)
##   │ IR payload       │  irSize bytes
##   ├──────────────────┤  offset resultOffset (8-byte aligned)
##   │ Result slot      │  ResultSlotSize bytes (4096)
##   └──────────────────┘
##
## All offsets and sizes are 8-byte aligned to satisfy both mmap granularity
## and Lean 4 FFI alignment requirements.
##
## Design invariants:
##   1. Header magic is 0x41584952 ("AXIR") — validated on open
##   2. All I/O procs carry {.axiomEffect: IOEffect.} — core is effect-free
##   3. Zero-copy: IR bytes are read directly from mmap, not copied into seq
##      (readIRBytes* is the exception — it returns a seq for callers that need
##      owned data; the hot path uses direct pointer access via data field)

import std/[strutils]
import posix
import core/axiom_pragmas
import core/trusted/shared_ir_types

axiomIoBoundary()

# Local FFI declarations — posix module mmap/munmap signatures are
# ambiguous in Nim 2.2.10; override with explicit pointer-typed procs.
proc mmap(start: pointer, length: csize_t, prot: cint, flags: cint,
          fd: cint, offset: int): pointer {.importc, header: "<sys/mman.h>", tags: [].}
proc munmap(start: pointer, length: int): cint {.importc, header: "<sys/mman.h>", tags: [].}

# ══════════════════════════════════════════════════════════════════════════════
# Constants
# ══════════════════════════════════════════════════════════════════════════════

const
  HeaderMagic*     = 0x41584952'u32  ## "AXIR" — ASCII little-endian
  HeaderVersion*   = 1'u32
  HeaderSize*      = 64              ## Fixed 64-byte header (8-byte aligned)
  ResultSlotSize*  = 4096            ## 4 KiB result slot (one mmap page)

  # Status codes written into SharedIRHeader.status
  StatusPending*   = 0'i32
  StatusOK*        = 1'i32
  StatusError*     = 2'i32
  StatusTimeout*   = 3'i32

# ══════════════════════════════════════════════════════════════════════════════
# Types
# ══════════════════════════════════════════════════════════════════════════════

# SharedIRHeader is imported from core/trusted/shared_ir_types (DSL-generated).

type
  SharedIRBuffer* = object
    ## Handle to a mmap-backed shared memory region.
    ## Create via createSharedIRBuffer* or openSharedIRBuffer*.
    ## Always call closeSharedIRBuffer* to release resources.
    fd*: cint          ## File descriptor from shm_open
    data*: pointer     ## Base address of mmap region
    size*: int          ## Total mmap size in bytes

# ══════════════════════════════════════════════════════════════════════════════
# Compile-Time Layout Verification
# ══════════════════════════════════════════════════════════════════════════════

static:
  doAssert sizeof(SharedIRHeader) == 64, "SharedIRHeader must be exactly 64 bytes"
  doAssert HeaderSize mod 8 == 0, "HeaderSize must be 8-byte aligned"
  doAssert ResultSlotSize mod 8 == 0, "ResultSlotSize must be 8-byte aligned"

# ══════════════════════════════════════════════════════════════════════════════
# Pure Helpers — {.raises: [].}
# ══════════════════════════════════════════════════════════════════════════════

func align8*(n: int): int {.raises: [].} =
  ## Round `n` up to the next 8-byte boundary.
  ## If already aligned, returns `n` unchanged.
  ## Used for mmap offset alignment and Lean 4 FFI compatibility.
  (n + 7) and not 7

func calculateLayout*(irSize: int): (int, int, int) {.raises: [].} =
  ## Compute the memory layout for a shared IR buffer.
  ##
  ## Returns:
  ##   (totalSize, irOffset, resultOffset)
  ##
  ## Layout:
  ##   [0 .. HeaderSize)                          — SharedIRHeader (64 bytes)
  ##   [irOffset .. irOffset+irSize)              — IR payload
  ##   [resultOffset .. resultOffset+ResultSlotSize) — Result slot
  let irOff = align8(HeaderSize)
  let resOff = align8(irOff + irSize)
  let total = resOff + ResultSlotSize
  (total, irOff, resOff)

func newSharedIRHeader*(irOffset, irSize, resultOffset: int): SharedIRHeader {.raises: [].} =
  ## Create a new SharedIRHeader with the given layout offsets.
  ## Sets magic, version, headerSize, and clears padding.
  SharedIRHeader(
    magic: HeaderMagic,
    version: HeaderVersion,
    headerSize: uint32(HeaderSize),
    status: StatusPending,
    irOffset: uint64(irOffset),
    irSize: uint64(irSize),
    resultOffset: uint64(resultOffset),
    resultSize: uint64(ResultSlotSize),
    padding: default(array[16, byte])
  )

# ══════════════════════════════════════════════════════════════════════════════
# I/O Procs — mmap lifecycle
# ══════════════════════════════════════════════════════════════════════════════

proc createSharedIRBuffer*(name: string, irSize: int): SharedIRBuffer {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], raises: [IOError].} =
  ## Create a new POSIX shared memory object and mmap it with read/write access.
  ##
  ## Steps: shm_open(O_CREAT|O_RDWR) → ftruncate → mmap(PROT_READ|PROT_WRITE)
  ##
  ## `name` must start with '/' (POSIX requirement), e.g. "/axiom_ir_0".
  ## The caller must later call closeSharedIRBuffer* and unlinkSharedIRBuffer*.
  let (totalSize, irOff, resOff) = calculateLayout(irSize)

  let shmName = if name[0] == '/': name else: "/" & name

  # shm_open with create + read/write
  let fd = shm_open(cstring(shmName), O_CREAT or O_RDWR, 0o600)
  if fd < 0:
    raise newException(IOError, "shm_open failed for " & shmName)

  # Size the shared memory region
  if ftruncate(fd, totalSize.int) < 0:
    discard close(fd)
    discard shm_unlink(cstring(shmName))
    raise newException(IOError, "ftruncate failed for " & shmName)

  # Map into process address space
  let base = mmap(
    nil,
    totalSize.csize_t,
    PROT_READ or PROT_WRITE,
    MAP_SHARED,
    fd,
    0
  )
  if base == MAP_FAILED:
    discard close(fd)
    discard shm_unlink(cstring(shmName))
    raise newException(IOError, "mmap failed for " & shmName)

  SharedIRBuffer(fd: fd, data: base, size: totalSize)

proc openSharedIRBuffer*(name: string, size: int): SharedIRBuffer {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], raises: [IOError].} =
  ## Open an existing POSIX shared memory object created by another process.
  ##
  ## shm_open(O_RDWR) → mmap(PROT_READ|PROT_WRITE).
  ## Validates the header magic before returning.
  let shmName = if name[0] == '/': name else: "/" & name

  let fd = shm_open(cstring(shmName), O_RDWR, 0)
  if fd < 0:
    raise newException(IOError, "shm_open(O_RDWR) failed for " & shmName)

  let base = mmap(
    nil,
    size.csize_t,
    PROT_READ or PROT_WRITE,
    MAP_SHARED,
    fd,
    0
  )
  if base == MAP_FAILED:
    discard close(fd)
    raise newException(IOError, "mmap failed for " & shmName)

  # Validate header magic
  let header = cast[ptr SharedIRHeader](base)
  if header.magic != HeaderMagic:
    discard munmap(base, size)
    discard close(fd)
    raise newException(IOError, "Invalid shared IR buffer magic: expected AXIR")

  SharedIRBuffer(fd: fd, data: base, size: size)

# ══════════════════════════════════════════════════════════════════════════════
# I/O Procs — Header read/write
# ══════════════════════════════════════════════════════════════════════════════

proc writeHeader*(buf: SharedIRBuffer, irSize: int, irOffset, resultOffset: int) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Write a SharedIRHeader at offset 0 of the buffer.
  ## Sets magic, version, headerSize, offsets, and initial status=Pending.
  let header = newSharedIRHeader(irOffset, irSize, resultOffset)
  let dst = cast[ptr UncheckedArray[byte]](buf.data)
  let src = unsafeAddr header
  copyMem(dst, src, HeaderSize)

func readHeader*(buf: SharedIRBuffer): SharedIRHeader {.raises: [].} =
  ## Read the SharedIRHeader from offset 0 of the buffer.
  cast[ptr SharedIRHeader](buf.data)[]

# ══════════════════════════════════════════════════════════════════════════════
# I/O Procs — IR payload
# ══════════════════════════════════════════════════════════════════════════════

proc writeIRBytes*(buf: SharedIRBuffer, data: openArray[byte], irOffset: int) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Write IR payload bytes into the shared memory region at `irOffset`.
  let dst = cast[pointer](cast[int](buf.data) + irOffset)
  copyMem(dst, unsafeAddr data[0], data.len)

proc readIRBytes*(buf: SharedIRBuffer): seq[byte] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read the IR payload from shared memory using offsets stored in the header.
  ## Returns a copy of the IR bytes — callers needing zero-copy access should
  ## use `buf.data` directly with the offsets from `readHeader()`.
  let header = buf.readHeader()
  let irOff = int(header.irOffset)
  let irLen = int(header.irSize)
  result = newSeq[byte](irLen)
  if irLen > 0:
    let src = cast[pointer](cast[int](buf.data) + irOff)
    copyMem(addr result[0], src, irLen)

# ══════════════════════════════════════════════════════════════════════════════
# I/O Procs — Result slot
# ══════════════════════════════════════════════════════════════════════════════

proc writeResult*(buf: SharedIRBuffer, status: int32, result: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Write status + result string into the result slot.
  ##
  ## Layout within the result slot:
  ##   [0..3]  — int32 status (4 bytes, native endian)
  ##   [4..7]  — int32 resultLen (4 bytes, native endian)
  ##   [8..]   — raw result bytes (resultLen bytes)
  let header = buf.readHeader()
  let resOff = int(header.resultOffset)
  let base = cast[int](buf.data) + resOff

  # Write status (first 4 bytes)
  var statusVal = status
  copyMem(cast[pointer](base), addr statusVal, sizeof(int32))

  # Write result length (next 4 bytes)
  var resultLen = int32(result.len)
  copyMem(cast[pointer](base + 4), addr resultLen, sizeof(int32))

  # Write result bytes (after length)
  if result.len > 0:
    copyMem(cast[pointer](base + 8), unsafeAddr result[0], result.len)

  # Update header status
  var updatedHeader = header
  updatedHeader.status = status
  let hdrDst = cast[ptr UncheckedArray[byte]](buf.data)
  copyMem(hdrDst, unsafeAddr updatedHeader, HeaderSize)

proc readResult*(buf: SharedIRBuffer): (int32, string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read status + result string from the result slot.
  ##
  ## Returns (status, resultText). If the result slot is empty or the length
  ## field exceeds ResultSlotSize, returns (StatusPending, "").
  let header = buf.readHeader()
  let status = header.status

  let resOff = int(header.resultOffset)
  let base = cast[int](buf.data) + resOff

  # Read result length
  var resultLen: int32 = 0
  copyMem(addr resultLen, cast[pointer](base + 4), sizeof(int32))

  if resultLen <= 0 or resultLen > (ResultSlotSize - 8).int32:
    return (status, "")

  # Read result bytes
  var resultStr = newString(int(resultLen))
  if resultLen > 0:
    copyMem(addr resultStr[0], cast[pointer](base + 8), int(resultLen))

  (status, resultStr)

# ══════════════════════════════════════════════════════════════════════════════
# I/O Procs — Teardown
# ══════════════════════════════════════════════════════════════════════════════

proc closeSharedIRBuffer*(buf: SharedIRBuffer) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Unmap the shared memory region and close the file descriptor.
  ## Does NOT unlink the shared memory object — call unlinkSharedIRBuffer*
  ## separately when the object should be removed from the namespace.
  if not isNil(buf.data) and buf.size > 0:
    discard munmap(buf.data, buf.size)
  if buf.fd >= 0:
    discard close(buf.fd)

proc unlinkSharedIRBuffer*(name: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Remove the POSIX shared memory object from the namespace.
  ## Safe to call after all processes have closed their mappings.
  let shmName = if name[0] == '/': name else: "/" & name
  discard shm_unlink(cstring(shmName))

{.pop.}
