/-
  POSIX Fork FFI — Lean 4 bindings for Zygote daemon process model.

  Provides Lean wrappers around POSIX fork(2) and prctl(PR_SET_PDEATHSIG)
  for the Zygote daemon pattern: a long-lived parent process that forks
  per verification request.

  Design rationale (AGENTS.md §0.2):
    - Ideal: Direct POSIX primitives, zero abstraction
    - Elegant: Same @[extern] pattern as IR.ShmFFI
    - Fundamental: prctl must be called in child AFTER fork (Linux clears
      PDEATHSIG on fork per prctl(2) man page)
    - Deterministic: identical state → identical behavior

  Usage in Zygote daemon (LeanWorker --daemon):
    1. Parent calls forkProcess → gets child PID
    2. In child (pid == 0): call setPDeathSig(SIGKILL=9) to auto-kill
       child if parent dies
    3. Child runs verification, exits
    4. Parent calls waitpid to collect zombie
-/

namespace IR.ForkFFI

-- ═══════════════════════════════════════════════════════════════════════════
--  §1  Constants
-- ═══════════════════════════════════════════════════════════════════════════

/-- SIGKILL — sent to child when parent dies (prctl PR_SET_PDEATHSIG). -/
def SIGKILL : UInt32 := 9

-- ═══════════════════════════════════════════════════════════════════════════
--  §2  C FFI Declarations
-- ═══════════════════════════════════════════════════════════════════════════

/-- Fork the current process.
    Returns IO UInt32:
      parent receives child PID (> 0)
      child receives 0
      failure → IO.error -/
@[extern "lean_fork_process"]
opaque forkProcess : IO UInt32

/-- Set the parent-death signal for this process.
    Must be called in the CHILD after fork — Linux clears PDEATHSIG on fork.
    `sig` is the signal number (e.g. 9 for SIGKILL).
    Returns IO UInt32: 0 on success, IO.error on failure. -/
@[extern "lean_set_pdeathsig"]
opaque setPDeathSig (sig : UInt32) : IO UInt32

/-- Reap all zombie child processes using waitpid(WNOHANG).
    Non-blocking — returns immediately even if no children have exited.
    Returns IO UInt32: the number of children reaped. -/
@[extern "lean_reap_children"]
opaque reapChildren : BaseIO UInt32

-- ═══════════════════════════════════════════════════════════════════════════
--  §3  High-level Wrappers
-- ═══════════════════════════════════════════════════════════════════════════

/-- Fork and set the parent-death signal to SIGKILL.
    Convenience wrapper for the Zygote daemon child path:
    forkProcess → setPDeathSig(SIGKILL).
    Returns the child PID. In the child context, the caller should
    use the returned value to branch (0 = child, nonzero = parent). -/
def forkChildWithDeathSig : IO UInt32 := do
  let pid ← forkProcess
  if pid == 0 then
    -- Child: re-arm parent-death signal (Linux clears it on fork)
    let _ ← setPDeathSig SIGKILL
  pure pid

end IR.ForkFFI
