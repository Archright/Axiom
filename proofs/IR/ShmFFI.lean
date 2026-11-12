/-
  POSIX Shared Memory FFI — Lean 4 bindings for Zero-Copy Worker IPC.

  Provides Lean wrappers around POSIX shm_open / mmap / munmap / close /
  shm_unlink, plus helpers for reading and writing the SharedIRHeader layout
  defined in src/infrastructure/shared_ir_buffer.nim.

  Shared memory layout (all offsets 8-byte aligned):
    ┌──────────────────┐  offset 0
    │ SharedIRHeader   │  64 bytes (packed)
    ├──────────────────┤  offset irOffset
    │ IR payload       │  irSize bytes
    ├──────────────────┤  offset resultOffset
    │ Result slot      │  resultSize bytes (4096)
    └──────────────────┘

  Header field offsets (little-endian):
    [ 0] magic        uint32   0x41584952 ("AXIR")
    [ 4] version      uint32   1
    [ 8] headerSize   uint32   64
    [12] status       int32    0=pending 1=ok 2=error 3=timeout
    [16] irOffset     uint64
    [24] irSize       uint64
    [32] resultOffset uint64
    [40] resultSize   uint64
    [48] padding      16 bytes
-/

import Generated.SharedIRHeader

namespace IR.ShmFFI

-- ═══════════════════════════════════════════════════════════════════════════
--  §1  Constants  (mirror src/infrastructure/shared_ir_buffer.nim)
-- ═══════════════════════════════════════════════════════════════════════════

/-- Magic bytes "AXIR" stored as little-endian uint32. -/
def HeaderMagic     : UInt32 := 0x41584952
/-- Protocol version — bump when the header layout changes. -/
def HeaderVersion   : UInt32 := 1
/-- Fixed header size in bytes (64, 8-byte aligned). -/
def HeaderSize      : UInt32 := 64
/-- Default result-slot size (4 KiB, one mmap page). -/
def ResultSlotSize  : UInt64 := 4096

/-- Status: operation still in progress. -/
def StatusPending   : UInt32 := 0
/-- Status: verification completed successfully. -/
def StatusOK        : UInt32 := 1
/-- Status: verification failed with an error. -/
def StatusError     : UInt32 := 2
/-- Status: verification exceeded the time budget. -/
def StatusTimeout   : UInt32 := 3

/-- POSIX O_CREAT (Linux value). -/
def O_CREAT : UInt32 := 0x40
/-- POSIX O_RDWR. -/
def O_RDWR  : UInt32 := 2
/-- Default permission mode for shm_open (owner read/write). -/
def SHM_MODE : UInt32 := 0o600

-- ═══════════════════════════════════════════════════════════════════════════
--  §2  SharedIRHeader — parsed from the first 64 bytes of the region
-- ═══════════════════════════════════════════════════════════════════════════

-- SharedIRHeader is imported from Generated.SharedIRHeader (DSL-generated).
open AxiomIR in
abbrev SharedIRHeader := AxiomIR.SharedIRHeader

-- ═══════════════════════════════════════════════════════════════════════════
--  §3  Byte-level helpers (little-endian, portable across architectures)
-- ═══════════════════════════════════════════════════════════════════════════

/-- Read a little-endian uint32 starting at `offset` in `data`. -/
private def readUInt32LE (data : ByteArray) (offset : Nat) : UInt32 :=
  let b0 := (data.get! offset).toUInt32
  let b1 := (data.get! (offset + 1)).toUInt32
  let b2 := (data.get! (offset + 2)).toUInt32
  let b3 := (data.get! (offset + 3)).toUInt32
  b0 ||| (b1 <<< 8) ||| (b2 <<< 16) ||| (b3 <<< 24)

/-- Read a little-endian uint8 starting at `offset` in `data`. -/
private def readUInt8LE (data : ByteArray) (offset : Nat) : UInt8 :=
  data.get! offset

/-- Read a little-endian uint64 starting at `offset` in `data`. -/
private def readUInt64LE (data : ByteArray) (offset : Nat) : UInt64 :=
  let b0 := (data.get! offset).toUInt64
  let b1 := (data.get! (offset + 1)).toUInt64
  let b2 := (data.get! (offset + 2)).toUInt64
  let b3 := (data.get! (offset + 3)).toUInt64
  let b4 := (data.get! (offset + 4)).toUInt64
  let b5 := (data.get! (offset + 5)).toUInt64
  let b6 := (data.get! (offset + 6)).toUInt64
  let b7 := (data.get! (offset + 7)).toUInt64
  b0 ||| (b1 <<< 8) ||| (b2 <<< 16) ||| (b3 <<< 24) |||
  (b4 <<< 32) ||| (b5 <<< 40) ||| (b6 <<< 48) ||| (b7 <<< 56)

-- ═══════════════════════════════════════════════════════════════════════════
--  §4  SharedIRHeader.parse — pure parser from raw bytes
-- ═══════════════════════════════════════════════════════════════════════════

/-- Parse a `SharedIRHeader` from a 64-byte (or larger) `ByteArray`.

    Returns `none` if the buffer is too short or the magic does not match
    `0x41584952` ("AXIR"). -/
def SharedIRHeader.parse (data : ByteArray) : Option SharedIRHeader := do
  guard (data.size ≥ 64)
  let magic := readUInt32LE data 0
  guard (magic == HeaderMagic)
  pure {
    magic        := magic
    version      := readUInt32LE data 4
    headerSize   := readUInt32LE data 8
    status       := (readUInt32LE data 12).toInt32
    irOffset     := readUInt64LE data 16
    irSize       := readUInt64LE data 24
    resultOffset := readUInt64LE data 32
    resultSize   := readUInt64LE data 40
    padding      := fun i => readUInt8LE data (48 + i.val)
  }

-- ═══════════════════════════════════════════════════════════════════════════
--  §5  C FFI Declarations
-- ═══════════════════════════════════════════════════════════════════════════

/-- Open (or create) a POSIX shared-memory object.

    `name` must begin with `/` (POSIX requirement).
    `oflag` and `mode` use platform constants (see `O_CREAT`, `O_RDWR`,
    `SHM_MODE` above).

    Returns the file descriptor on success (≥ 0), or throws an IO error. -/
@[extern "lean_shm_open"]
opaque shmOpen (name : @& String) (oflag : UInt32) (mode : UInt32) : IO Int32

/-- Map `size` bytes of the shared-memory object behind `fd` into the
    caller's address space (PROT_READ|PROT_WRITE, MAP_SHARED).

    Returns the base address as a `UInt64`, or throws an IO error. -/
@[extern "lean_shm_mmap"]
opaque shmMmap (size : UInt64) (fd : Int32) : IO UInt64

/-- Unmap `size` bytes starting at `addr`. -/
@[extern "lean_shm_munmap"]
opaque shmMunmap (addr : UInt64) (size : UInt64) : IO Int32

/-- Close the file descriptor returned by `shmOpen`. -/
@[extern "lean_shm_close"]
opaque shmClose (fd : Int32) : IO Int32

/-- Remove the POSIX shared-memory object from the namespace. -/
@[extern "lean_shm_unlink"]
opaque shmUnlink (name : @& String) : IO Int32

/-- Copy `size` bytes from the mapped region at `addr + offset`
    into a fresh Lean `ByteArray`. -/
@[extern "lean_shm_read_bytes"]
opaque shmReadBytes (addr : UInt64) (offset : UInt64) (size : UInt64) : IO ByteArray

/-- Write a `UInt32` value at byte offset `offset` from `addr`.

    Useful for updating the header status field (offset 12). -/
@[extern "lean_shm_write_status"]
opaque shmWriteStatus (addr : UInt64) (offset : UInt64) (status : UInt32) : IO Unit

/-- Write a status code and result message into the result slot at
    `addr + resultOffset`.

    Slot layout (mirrors Nim `SharedIRBuffer.writeResult`):
      [+0]  int32 status   (4 bytes)
      [+4]  int32 msgLen   (4 bytes)
      [+8]  uint8[] msg    (msgLen bytes) -/
@[extern "lean_shm_write_result"]
opaque shmWriteResult (addr : UInt64) (resultOffset : UInt64)
                      (status : UInt32) (msg : @& String) : IO Unit

-- ═══════════════════════════════════════════════════════════════════════════
--  §6  High-level Wrappers
-- ═══════════════════════════════════════════════════════════════════════════

/-- Open a POSIX shared-memory object by `name` and map `size` bytes.

    Ensures `name` starts with `/`.  Returns `(fd, baseAddress)` on success.

    The caller MUST later call `closeSharedMemory` to release resources. -/
def openSharedMemory (name : String) (size : UInt64) : IO (Int32 × UInt64) := do
  let shmName := match name.toList with
    | '/' :: _ => name
    | _        => "/" ++ name
  let fd ← shmOpen shmName (O_CREAT ||| O_RDWR) SHM_MODE
  if fd < 0 then
    throw (IO.userError s!"shm_open failed for {shmName} (fd={fd})")
  let addr ← shmMmap size fd
  if addr == 0 then
    throw (IO.userError s!"mmap failed for {shmName}")
  pure (fd, addr)

/-- Unmap and close a shared-memory region previously opened with
    `openSharedMemory`. -/
def closeSharedMemory (fd : Int32) (addr : UInt64) (size : UInt64) : IO Unit := do
  let _ ← shmMunmap addr size
  let _ ← shmClose fd

/-- Remove the POSIX shared-memory object from the namespace.

    Safe to call after all processes have unmapped and closed. -/
def unlinkSharedMemory (name : String) : IO Unit := do
  let shmName := match name.toList with
    | '/' :: _ => name
    | _        => "/" ++ name
  let _ ← shmUnlink shmName

/-- Read `irSize` bytes starting at `irOffset` from the mapped region. -/
def readIRFromSharedMemory (addr : UInt64) (irOffset : UInt64) (irSize : UInt64) : IO ByteArray :=
  shmReadBytes addr irOffset irSize

/-- Write a verification result (status code + human-readable message) into
    the result slot, and simultaneously update the header's status field.

    `resultOffset` is the byte offset of the result slot within the mapped
    region (obtained from `SharedIRHeader.parse`). -/
def writeStatusToSharedMemory (addr : UInt64) (resultOffset : UInt64)
                              (status : UInt32) (msg : String) : IO Unit := do
  -- Write status + message into the result slot
  shmWriteResult addr resultOffset status msg
  -- Update header status field (at byte offset 12 from base)
  shmWriteStatus addr 12 status

end IR.ShmFFI
