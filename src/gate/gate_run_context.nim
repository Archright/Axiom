import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

## Gate Run Context — Unified gate execution context with ptr-based read-only views.
##
## Eliminates ARC atomic RC overhead and isolation checks by using raw `pointer`
## for heap-allocated types (MerkleVfs). GateLedger is already a value type with
## copy/sink forbidden; accessed via `ptr GateLedger` from mmap.
##
## Lifetime guarantee:
##   - MerkleVfs: main thread `{.threadvar.}` — process-lifetime, never reassigned.
##     `dispatchAllGates` binds the pointer at its top-level scope.
##   - GateLedger: mmap'd `PROT_READ + MAP_PRIVATE` — process-lifetime, read-only.
##     Created by L0 via atomic temp+fsync+rename. Opened by `openLedger()`.
##
## Thread safety:
##   - In-process gates run on the main thread (sequential dispatch).
##   - `pointer` bypasses ARC reference counting entirely (zero overhead).
##   - `ptr GateLedger` is a raw pointer to mmap'd memory (zero overhead).

import std/tables
import gate/types
import core/crypto/hash_kernel
import core/gate/merkle_vfs
import core/gate/state_ledger_types

type
  VfsHandle* = distinct pointer
    ## Opaque handle to a MerkleVfs (ref object).
    ## Stored as raw pointer to bypass ARC reference counting.
    ## Original ref object lives in main thread's {.threadvar.} — process-lifetime.

  LedgerView* = ptr GateLedger
    ## Read-only pointer to mmap'd GateLedger.
    ## GateLedger is a value type with copy/sink forbidden.
    ## Memory is mmap'd PROT_READ + MAP_PRIVATE — read-only, no msync needed.

  GateRunContext* = object
    ## Unified gate execution context. Value type — cheap to copy.
    ## Contains no `ref` fields → ARC/isolation zero overhead.
    repoRoot*: string
    stagedFiles*: seq[string]
    vfs*: VfsHandle           ## Raw pointer to MerkleVfs — ARC cost 0
    ledger*: LedgerView       ## Raw ptr to mmap'd ledger — ARC cost 0
    epoch*: int
    maxJobs*: int
    precomputedBuildEnvHash*: string   ## Pre-computed build env hash from orchestrator
    stage*: GateStage                  ## Gate execution stage (pre-commit / pre-push / CI)
    salsaDb*: pointer                  ## nil = no Salsa available (Phase F: semantic memoization)

# ─── VFS Accessors ─────────────────────────────────────────────────────────
# Note: Table operations have side effects in Nim 2.2.10 stdlib,
# so VFS accessors use {.raises: [].} without.

func derefVfs(ctx: GateRunContext): MerkleVfs {.inline, raises: [].} =
  ## Recover the MerkleVfs ref from the opaque VfsHandle.
  ## VfsHandle stores the ref value directly (which IS a raw pointer).
  ## ARC overhead is zero: cast bypasses refcount, and the original ref
  ## lives in {.threadvar.} (process-lifetime, never freed).
  cast[MerkleVfs](ctx.vfs)

func vfsRootHash*(ctx: GateRunContext): string {.raises: [].} =
  ## Returns the Merkle root hash of the entire VFS.
  ctx.derefVfs.rootHash

func vfsFileHash*(ctx: GateRunContext; path: string): string {.raises: [].} =
  ## Returns content hash for a file path, or "" if not found.
  if path in ctx.derefVfs.fileIndex:
    let entry = ctx.derefVfs.fileIndex.getOrDefault(path)
    if not entry.isDir:
      return entry.contentHash
  ""

func vfsFileExists*(ctx: GateRunContext; path: string): bool {.raises: [].} =
  ## Returns true if the file exists in the VFS (not a directory).
  if path in ctx.derefVfs.fileIndex:
    let entry = ctx.derefVfs.fileIndex.getOrDefault(path)
    return not entry.isDir
  false

func vfsDirExists*(ctx: GateRunContext; path: string): bool {.raises: [].} =
  ## Returns true if the path is a directory in the VFS.
  if path in ctx.derefVfs.fileIndex:
    let entry = ctx.derefVfs.fileIndex.getOrDefault(path)
    return entry.isDir
  false

func vfsPath*(ctx: GateRunContext): string {.raises: [].} =
  ## Returns the absolute root path of the VFS.
  ctx.derefVfs.rootPath

# ─── Ledger Accessors (ptr dereference — zero-cost) ────────────────────────

func ledgerDirtyHash*(ctx: GateRunContext): HashValue {.noSideEffect, raises: [].} =
  ## Returns the workspace dirty hash from the state ledger.
  ctx.ledger[].workspace.dirtyHash

func ledgerRuleHash*(ctx: GateRunContext): HashValue {.noSideEffect, raises: [].} =
  ## Returns the rule hash from the state ledger.
  ctx.ledger[].workspace.ruleHash

func ledgerBuildEnvHash*(ctx: GateRunContext): HashValue {.noSideEffect, raises: [].} =
  ## Returns the build environment hash from the state ledger.
  ctx.ledger[].workspace.buildEnvHash

func ledgerEpoch*(ctx: GateRunContext): uint32 {.noSideEffect, raises: [].} =
  ## Returns the ledger epoch.
  ctx.ledger[].header.epoch

func ledgerTimestamp*(ctx: GateRunContext): int64 {.noSideEffect, raises: [].} =
  ## Returns the unix timestamp when the parent computed the state.
  ctx.ledger[].workspace.timestamp

# ─── Context Construction ───────────────────────────────────────────────────

func buildVfsHandle*(vfs: MerkleVfs): VfsHandle {.inline, raises: [].} =
  ## Converts a MerkleVfs ref to an opaque handle (raw pointer).
  ## Caller must ensure the original ref stays alive for the handle's lifetime.
  ## Safe when vfs lives in a {.threadvar.} (process-lifetime).
  ## NOTE: MerkleVfs is a `ref object` — it IS a pointer type. We store the
  ## ref value directly. Using `unsafeAddr vfs[]` + `ptr MerkleVfs` in derefVfs
  ## creates double indirection (ptr-to-ref = ptr-to-ptr), causing the `[]`
  ## operator to read the object's first field as a pointer → SIGSEGV.
  cast[VfsHandle](vfs)

func isValid*(handle: VfsHandle): bool {.inline, noSideEffect, raises: [].} =
  ## Returns true if the handle points to a valid (non-nil) MerkleVfs.
  cast[pointer](handle) != nil

func isValid*(view: LedgerView): bool {.inline, noSideEffect, raises: [].} =
  ## Returns true if the ledger view points to valid (non-nil) memory.
  view != nil

# ─── Per-Gate Computation ─────────────────────────────────────────────────────

func vfsComputeSubtreeRoot*(ctx: GateRunContext; filesPattern: string): string {.raises: [].} =
  ## Compute per-gate Merkle subtree root from the VFS handle.
  ## Returns "" if VFS is not available (cache miss fallback).
  if not ctx.vfs.isValid:
    return ""
  ctx.derefVfs.computeSubtreeRoot(filesPattern)
