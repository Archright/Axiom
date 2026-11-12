import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

import gate/utils/gate_safety_macro
import gate/utils/inprocess_dispatch
import std/macros
import std/times
# ─── Type Declarations (forward — used by funcs below) ─────────────────────

type
  AuditEntry* = object
    ## Immutable audit log entry for gate execution.
    ## Created at gate start, finalized at gate end.
    gateId*: string
    startTime*: Time
    endTime*: Time
    exitCode*: int
    output*: string
    sandboxed*: bool       # true if ran in sandbox
    cacheHit*: bool        # true if cache hit (no execution)
    epoch*: int            # gate epoch for cache invalidation

  VfsHandle* = distinct pointer
    ## Opaque VFS handle — same type as flat_vfs.VfsHandle.
    ## Declared here to avoid circular import.

  GateRunOwner* = object
    ## ARC ownership tracking for VFS structural sharing.
    ## FlatVfs (sorted seq): vfsRefCount=0, no ARC involvement.
    ## HamtVfs (Wave 3): vfsRefCount≥1, ARC ref-counted nodes.
    vfsRefCount*: int          # 0 = FlatVfs (no ARC), 1+ = HamtVfs (ARC)
    isShared*: bool            # true = structural sharing with another context
    version*: uint64           # VFS version for synchronization

  GateRunContext* = object
    ## Pure value-type context for gate execution.
    ## All fields are value types — safe for malebolgia spawn.
    ## VfsHandle is distinct pointer (ARC-invisible, zero-cost).
    commitRange*: string
    projectRoot*: string
    vfs*: VfsHandle            # opaque — works for FlatVfs and future HamtVfs
    auditLog*: seq[AuditEntry]
    contextPaths*: seq[string]
    owner*: GateRunOwner       # ARC lifecycle tracking
    epoch*: int                # current gate epoch
    maxJobs*: int              # parallelism limit

# ─── Audit Entry ────────────────────────────────────────────────────────────

func initGateRunContext*(projectRoot: string; vfs: VfsHandle;
                         epoch: int = 0; maxJobs: int = 1): GateRunContext {.raises: [].} =
  ## Create a new gate run context.
  GateRunContext(
    projectRoot: projectRoot,
    vfs: vfs,
    auditLog: @[],
    contextPaths: @[],
    owner: GateRunOwner(vfsRefCount: 1, isShared: false, version: 0),
    epoch: epoch,
    maxJobs: maxJobs
  )
func clone*(ctx: GateRunContext): GateRunContext {.raises: [].} =
  ## Structural sharing — ARC ref count increases.
  ## Use when multiple gates need the same VFS snapshot.
  result = ctx
  result.owner.vfsRefCount += 1
  result.owner.isShared = true
proc initAuditEntry*(gateId: string): AuditEntry {.raises: [].} =
  ## Create a new audit entry with placeholder timestamps.
  AuditEntry(
    gateId: gateId,
    startTime: getTime(),
    endTime: getTime(),
    exitCode: -1,
    output: "",
    sandboxed: false,
    cacheHit: false,
    epoch: 0
  )
proc finalize*(entry: var AuditEntry; exitCode: int; output: string = "";
               sandboxed: bool = false; cacheHit: bool = false) {.raises: [].} =
  ## Finalize an audit entry with execution results.
  entry.exitCode = exitCode
  entry.output = output
  entry.sandboxed = sandboxed
  entry.cacheHit = cacheHit
  entry.endTime = getTime()
func addAuditEntry*(ctx: var GateRunContext; entry: AuditEntry) {.raises: [].} =
  ## Append an audit entry to the context log.
  ctx.auditLog.add(entry)
func registerGateToManifest*(gateId: string; mode: string;
                             passFilenames: bool; canFail: bool) {.raises: [].} =
  ## Runtime helper: record gate metadata for manifest generation.
  ## Called once at orchestrator startup.
  ## No-op at runtime — metadata is collected by the build system.
  discard
macro registerGate*(gateId: static[string]; runner: untyped): untyped =
  ## Compile-time gate registration with full safety verification.
  ##
  ## Verifies:
  ##   1. AST node whitelist (verifyGateRunner)
  ##   2. Pragma whitelist (inside verifyGateRunner)
  ##   3. No ref object parameters (assertGateSignature)
  ##   4. gcsafe + raises annotations (assertGateSignature)
  ##
  ## Registers:
  ##   - Gate proc in inprocess_dispatch registry
  ##
  ## Usage:
  ##   proc runMyGate*(ctx: InProcessGateContext): GateResult {.gcsafe, raises: [].} =
  ##     ...
  ##   registerGate("my-gate-id", runMyGate)

  # Step 1: AST whitelist + pragma whitelist verification
  discard verifyGateRunner(runner)

  # Step 2: Extract proc name for registration
  let procName = if runner.kind == nnkProcDef: runner[0] else: runner

  # Step 3: Generate registration code
  result = quote do:
    # Compile-time signature verification
    assertGateSignature(`procName`)
    # Runtime registration in in-process dispatch registry
    registerInProcessGate(`gateId`, `procName`)

{.pop.}

