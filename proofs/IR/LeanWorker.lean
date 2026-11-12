/-
  LeanWorker — POSIX shared-memory IR type-checking worker binary.

  Replaces lean_worker.nim with a pure Lean 4 executable. Reads an Axiom
  Core IR from a POSIX shared-memory region, deserializes it via
  AxiomIR.BinaryCodec.deserializeIRExpr, runs MetaM-based type inference
  (Lean.Meta.inferType), and writes the verification result back into the
  shared-memory result slot.

  Protocol:
    argv[1] = shmName   (POSIX shm name, e.g. "/axiom_ir_1234")
    argv[2] = shmSize   (size in bytes as decimal string)

  Exit codes (matching lean_worker.nim):
    0 = Success
    1 = shm_open / header parse failed
    2 = Empty IR (irSize == 0)
    3 = Deserialize failed
    4 = MetaM type-check failed

  Memory layout (shared_ir_buffer.nim):
    [ 0..63]  SharedIRHeader  (64 bytes, packed)
    [irOffset .. irOffset+irSize)  IR payload
    [resultOffset .. resultOffset+resultSize)  Result slot
-/

import IR.AxiomIRExpr
import IR.MetaCheckIR
import IR.ShmFFI
import IR.ForkFFI
import Lean

open IR AxiomIR ShmFFI AxiomMetaCheck IR.ForkFFI

-- ═══════════════════════════════════════════════════════════════════════════
--  §1  Lean Environment Initialization
-- ═══════════════════════════════════════════════════════════════════════════

/-- Initialize the Lean 4 search path and import the Init module.
    Called once at worker startup — subsequent MetaM computations reuse
    the returned environment. -/
def initLeanEnv : IO Lean.Environment := do
  Lean.initSearchPath (← Lean.findSysroot)
  Lean.importModules #[`Init] {} 0

-- ═══════════════════════════════════════════════════════════════════════════
--  §2  Worker Core Logic
-- ═══════════════════════════════════════════════════════════════════════════

/-- Run the IR verification pipeline against a single shared-memory region.

    Steps: open shm → parse header → read IR → deserialize → MetaM check →
    write result → cleanup.  Returns the exit code. -/
def workerProcess (shmName : String) (shmSize : UInt64) : IO UInt32 := do
  -- 1. Open shared memory
  let (fd, addr) ← openSharedMemory shmName shmSize

  -- 2. Read and parse 64-byte header
  let headerBytes ← shmReadBytes addr 0 64
  match SharedIRHeader.parse headerBytes with
  | none =>
    writeStatusToSharedMemory addr 0 StatusError "Invalid header"
    closeSharedMemory fd addr shmSize
    return (1 : UInt32)
  | some header =>
    if header.irSize == 0 then do
      -- 3. Empty IR
      writeStatusToSharedMemory addr header.resultOffset StatusError "Empty IR"
      closeSharedMemory fd addr shmSize
      return (2 : UInt32)
    else do
      -- 4. Read IR bytes from the mmap region
      let irBytes ← readIRFromSharedMemory addr header.irOffset header.irSize

      -- 5. Deserialize IR bytes into IRExpr
      match deserializeIRExpr irBytes with
      | none =>
        writeStatusToSharedMemory addr header.resultOffset StatusError "Deserialize failed"
        closeSharedMemory fd addr shmSize
        return (3 : UInt32)
      | some ir =>
        -- 6. Initialize Lean environment (once per worker lifetime)
        let env ← initLeanEnv

        -- 7. Type-check via Lean.Meta.inferType
        let success ← checkExpr env ir

        -- 8. Write status + message to the result slot
        if success then
          writeStatusToSharedMemory addr header.resultOffset StatusOK "OK"
        else
          writeStatusToSharedMemory addr header.resultOffset StatusError "Type-check failed"

        -- 9. Cleanup
        closeSharedMemory fd addr shmSize
        return (if success then (0 : UInt32) else 4)

-- ═══════════════════════════════════════════════════════════════════════════
--  §3  Daemon Mode (Zygote stdin loop)
-- ═══════════════════════════════════════════════════════════════════════════

/-- Internal daemon loop — processes one stdin line, then recurses.
    Reaps zombie children before each iteration. -/
private partial def daemonLoopAux : IO Unit := do
  -- 1. Reap zombie children before processing the next request
  let reaped ← reapChildren
  if reaped > 0 then
    IO.eprint s!"[zygote] reaped {reaped} zombie(s)\n"

  -- 2. Read a line from stdin
  let line ← (← IO.getStdin).getLine
  if line.isEmpty then
    -- EOF — exit the daemon loop
    pure ()
  else
    let trimmed := line.trim
    -- 3. Parse "shmName shmSize" from the line
    match trimmed.splitOn " " with
    | [shmName, shmSizeStr] =>
      match shmSizeStr.toNat? with
      | some n =>
        let _exitCode ← workerProcess shmName n.toUInt64
        daemonLoopAux  -- recurse for next request
      | none =>
        IO.eprint s!"[daemon] Invalid shmSize: {shmSizeStr}\n"
        daemonLoopAux
    | _ =>
      IO.eprint s!"[daemon] Expected 'shmName shmSize', got: {trimmed}\n"
      daemonLoopAux

/-- Daemon stdin loop — reads "shmName shmSize" lines from stdin,
    processes each IR, and reaps zombie children between iterations.

    Each iteration:
      1. Reap any zombie children (non-blocking)
      2. Read one line from stdin
      3. Parse shmName and shmSize
      4. Process the IR via workerProcess

    Exits when stdin reaches EOF. -/
def daemonLoop : IO Unit := daemonLoopAux

-- ═══════════════════════════════════════════════════════════════════════════
--  §4  Entry Point
-- ═══════════════════════════════════════════════════════════════════════════

/-- Lean native worker — reads IR from POSIX shared memory, type-checks
    via MetaM, and writes the result back to the shared memory region.

    Modes:
      --daemon        Long-lived Zygote daemon; reads requests from stdin
      --check-file <path>  Decode a serialized IRExpr from a file, meta-check
                           it, exit 0 (pass) / 1 (decode or check failure) /
                           2 (unreadable) — certification-continuity Phase 3.5
      shmName shmSize Single-shot mode (default)

    All error paths write a StatusError to the result slot (when possible)
    and return the appropriate exit code. -/
def main (args : List String) : IO UInt32 := do
  match args with
  | ["--daemon"] =>
    daemonLoop
    return (0 : UInt32)
  | ["--daemon", _prog] =>
    daemonLoop
    return (0 : UInt32)
  | ["--check-file", path] => AxiomMetaCheck.checkIRFile path
  | [_prog, "--check-file", path] => AxiomMetaCheck.checkIRFile path
  | [_prog, shmName, shmSizeStr] =>
    match shmSizeStr.toNat? with
    | some n => workerProcess shmName n.toUInt64
    | none =>
      IO.eprint s!"Invalid shmSize: {shmSizeStr}\n"
      return (1 : UInt32)
  | [shmName, shmSizeStr] =>
    match shmSizeStr.toNat? with
    | some n => workerProcess shmName n.toUInt64
    | none =>
      IO.eprint s!"Invalid shmSize: {shmSizeStr}\n"
      return (1 : UInt32)
  | _ =>
    IO.eprint "Usage: worker [--daemon] <shmName> <shmSize>\n"
    return (1 : UInt32)
