import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## State Ledger Types — Fixed-size binary layout for cross-process pipeline state.
##
## The GateLedger is a deterministic, mmap-compatible binary file that stores
## the entire pipeline state computed by the parent process. Children mmap it
## read-only for zero-cost access to dirtyHash, buildEnvHash, and per-gate
## cache keys — eliminating redundant git subprocess calls and file I/O.
##
## v27: Proactive State Ledger replaces reactive recomputation in L2 children.
## v4: Added stagingTreeHash for content-addressed prepare-commit-msg verification.
##
## Binary layout: LedgerHeader(64) + WorkspaceState(160) + GateState[N](N×128) + CRC32(8)
## Total depends on AxiomLedgerCap from topology (ledger slot capacity 57).

import core/crypto/hash_kernel
from static_project_matrix import AxiomLedgerCap

# ─── Constants ────────────────────────────────────────────────────────────────

const
  LedgerMagic* = 0x4158474C'u32
    ## "AXGL" — Axiom Gate Ledger. Used for integrity validation.
  LedgerVersion* = 4'u16
    ## Binary layout version. Increment on layout change.
    ## v4: Added stagingTreeHash to WorkspaceState and padding rebalance.
    ## v3: Added deferredAt + deferredStage to GateStateEntry (9 bytes from reserved).
  LedgerHeaderSize* = 64
    ## Fixed header size in bytes.
  LedgerWorkspaceSize* = 160
    ## Fixed workspace state size in bytes.
    ## v4: 128 → 160 (+32 bytes for stagingTreeHash + field reorder).
  LedgerGateEntrySize* = 128
    ## Fixed per-gate entry size in bytes.
  MaxStagedFiles* = 512
    ## Maximum staged files tracked in a single ledger.

# ─── Enums ────────────────────────────────────────────────────────────────────

type
  LedgerStage* = enum
    ## Gate execution stage — maps to GateStage enum in types.nim.
    lsPreCommit = 0'u8
    lsPrePush = 1'u8
    lsManual = 2'u8
    lsCi = 3'u8

  LedgerGateResult* = enum
    ## Gate execution result — compact uint8 representation.
    lgrUnknown = 0'u8   ## Not yet executed
    lgrPass = 1'u8      ## Gate passed
    lgrFail = 2'u8      ## Gate failed
    lgrSkip = 3'u8      ## Skipped (cache hit or unaffected)
    lgrDeferred = 4'u8  ## Deferred to CI (tier-2 in pre-push)

# ─── Fixed-Size Structs ──────────────────────────────────────────────────────
# Field order is intentional: 8-byte aligned fields first, then 4-byte, then 1-byte.
# This eliminates implicit alignment padding and guarantees exact sizeof.

type
  LedgerHeader* = object
    ## File header — identifies and validates the ledger.
    ## 64 bytes total. Fields ordered to avoid alignment gaps.
    magic*: uint32              ## 0x4158474C ("AXGL")
    version*: uint16            ## Layout version
    headerSize*: uint16         ## Always 64
    totalSize*: int64           ## Total file size in bytes
    epoch*: uint32              ## Cache epoch
    gateCount*: uint16          ## Number of gate entries
    stagedCount*: uint16        ## Number of staged files at creation
    padding*: array[40, uint8]  ## Reserved — must be zero

  WorkspaceState* = object
    ## Parent-computed workspace state — the Single Source of Truth.
    ## 160 bytes total (v4). Children read this via mmap instead of calling git.
    dirtyHash*: HashValue       ## SHA-256(git diff --stat ++ git status --porcelain)
    ruleHash*: HashValue        ## SHA-256(config.nims ++ architecture_debt.json)
    buildEnvHash*: HashValue    ## SHA-256(config.nims + nimble + debt + NimVersion + ...)
    stagingTreeHash*: HashValue ## git write-tree SHA at pre-commit gate time (v4)
    timestamp*: int64           ## Unix epoch seconds — when parent computed this state
    baseCommit*: array[20, uint8] ## Git SHA-1 of HEAD (raw bytes, not hex)
    stage*: uint8               ## LedgerStage value
    mode*: uint8                ## GateRunMode value (0=incremental, 1=exhaustive)
    padding*: array[2, uint8]   ## Alignment padding

  GateStateEntry* = object
    ## Per-gate state — pre-computed cache key and execution result.
    ## 128 bytes total. Indexed by position (matching gate registry order).
    ## Field order: 8-byte aligned fields first, then 4-byte, then 1-byte.
    cacheKey*: HashValue        ## Pre-computed composite lock hash (32 bytes)
    lastTimestamp*: int64       ## Unix epoch — when this gate last ran (8 bytes)
    deferredAt*: int64          ## Unix epoch — when this gate was deferred (0 = not deferred)
    gateIdHash*: uint32         ## SHA-256-derived hash of gate ID string (collision-free for 68 gates)
    execTimeMs*: int32          ## Execution time in milliseconds
    result*: uint8              ## LedgerGateResult value
    tier*: uint8                ## Gate tier (1=L1 meta, 2=L2 functional)
    deferredStage*: uint8       ## Stage that deferred this gate (LedgerStage value)
    reserved*: array[69, uint8] ## Reserved — must be zero

  GateLedger* = object
    ## The complete ledger — header + workspace + gate states + checksum.
    ## Written atomically by parent, mmap'd read-only by children.
    header*: LedgerHeader
    workspace*: WorkspaceState
    gates*: array[AxiomLedgerCap, GateStateEntry]
    checksum*: uint32           ## CRC32 of all preceding bytes
    padding*: array[4, uint8]   ## Align to 8-byte boundary

# ─── Copy/Sink Guards ────────────────────────────────────────────────────────
# Prevent accidental copying of the ledger. Use ptr GateLedger for access.

func `=copy`*(dest: var GateLedger; src: GateLedger) {.
  error: "GateLedger 복사 금지 — ptr GateLedger 또는 mmap 사용".}
func `=sink`*(dest: var GateLedger; src: GateLedger) {.
  error: "GateLedger 이동 금지 — ptr GateLedger 또는 mmap 사용".}

proc `=copy`*(dest: var LedgerHeader; src: LedgerHeader) {.
  error: "LedgerHeader 복사 금지 — GateLedger의 일부로만 사용".}
proc `=copy`*(dest: var WorkspaceState; src: WorkspaceState) {.
  error: "WorkspaceState 복사 금지 — GateLedger의 일부로만 사용".}
proc `=copy`*(dest: var GateStateEntry; src: GateStateEntry) {.
  error: "GateStateEntry 복사 금지 — GateLedger의 일부로만 사용".}

# ─── Compile-Time Layout Verification ────────────────────────────────────────

static:
  assert sizeof(LedgerHeader) == LedgerHeaderSize,
    "LedgerHeader size mismatch: expected " & $LedgerHeaderSize &
    ", got " & $sizeof(LedgerHeader)
  assert sizeof(WorkspaceState) == LedgerWorkspaceSize,
    "WorkspaceState size mismatch: expected " & $LedgerWorkspaceSize &
    ", got " & $sizeof(WorkspaceState)
  assert sizeof(GateStateEntry) == LedgerGateEntrySize,
    "GateStateEntry size mismatch: expected " & $LedgerGateEntrySize &
    ", got " & $sizeof(GateStateEntry)

# ─── Per-Gate SubtreeRoot Accessors (v2) ─────────────────────────────────────

func getSubtreeRoot*(entry: GateStateEntry): HashValue {.raises: [].} =
  ## Read per-gate subtree root from reserved[0..31].
  ## Returns zeroed HashValue if not set (pre-v2 ledger).
  copyMem(addr result.data[0], unsafeAddr entry.reserved[0], 32)

func setSubtreeRoot*(entry: var GateStateEntry; root: HashValue) {.raises: [].} =
  ## Write per-gate subtree root into reserved[0..31].
  copyMem(addr entry.reserved[0], unsafeAddr root.data[0], 32)

# ─── Per-Gate Deferred Tracking Accessors (v3) ──────────────────────────────

func isDeferred*(entry: GateStateEntry): bool {.inline, raises: [].} =
  ## Returns true if this gate entry has been deferred for background execution.
  entry.result == uint8(lgrDeferred) and entry.deferredAt > 0

func setDeferred*(entry: var GateStateEntry; stage: uint8; timestamp: int64) {.raises: [].} =
  ## Mark this gate entry as deferred for background execution.
  entry.result = uint8(lgrDeferred)
  entry.deferredAt = timestamp
  entry.deferredStage = stage

func clearDeferred*(entry: var GateStateEntry) {.raises: [].} =
  ## Clear deferred state (e.g., after deferred execution completes).
  entry.deferredAt = 0
  entry.deferredStage = 0

# ─── Layout Constants (derived from verified sizes) ───────────────────────────

const
  LedgerGateArraySize* = AxiomLedgerCap * LedgerGateEntrySize
    ## Size of the gate entries array: AxiomLedgerCap × 128 bytes.
  LedgerTotalSize* = LedgerHeaderSize + LedgerWorkspaceSize +
                     LedgerGateArraySize + sizeof(uint32) + 4
    ## Total ledger file size: 64 + 160 + (AxiomLedgerCap × 128) + 4 + 4.

# ─── Lookup Helpers ──────────────────────────────────────────────────────────

func findGateEntry*(ledger: ptr GateLedger; gateIdHash: uint32): ptr GateStateEntry {.
  inline, noSideEffect.} =
  ## Find a gate entry by hash of its ID. Returns nil if not found.
  ## Linear scan is O(AxiomLedgerCap) — negligible for the current gate count.
  for i in 0 ..< int(ledger.header.gateCount):
    if ledger.gates[i].gateIdHash == gateIdHash:
      return addr ledger.gates[i]
  nil

func getDirtyHash*(ledger: ptr GateLedger): ptr HashValue {.
  inline, noSideEffect.} =
  ## Returns pointer to the dirty hash in the workspace state.
  addr ledger.workspace.dirtyHash

func getBuildEnvHash*(ledger: ptr GateLedger): ptr HashValue {.
  inline, noSideEffect.} =
  ## Returns pointer to the build environment hash.
  addr ledger.workspace.buildEnvHash

func getRuleHash*(ledger: ptr GateLedger): ptr HashValue {.
  inline, noSideEffect.} =
  ## Returns pointer to the rule hash.
  addr ledger.workspace.ruleHash

# ─── Staging Tree Hash Accessor (v4) ────────────────────────────────────────

func getStagingTreeHash*(ledger: ptr GateLedger): ptr HashValue {.
  inline, noSideEffect.} =
  ## Returns pointer to the staging tree hash in the workspace state.
  ## Content-addressed git write-tree SHA recorded by pre-commit gates.
  addr ledger.workspace.stagingTreeHash

{.pop.}
