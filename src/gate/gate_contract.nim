import core/trusted/layer_declaration
import std/algorithm
axiomLayer "gate"
{.push raises: [CatchableError].}

# ═══════════════════════════════════════════════════════════════
# GATE CONTRACT v1.2 — READ-ONLY API BOUNDARY
# ═══════════════════════════════════════════════════════════════
# Changelog:
#   v1.1: Added skipCiRequested field to GateResult (Plan v13-Absolute, [Arch-Review-Verified])
#   v1.2: Added gracePeriodUntil field to GateConfig (Grace Period mechanism)
#   v1.3: Added alwaysRun field to GateConfig (Deterministic scope routing, [Arch-Review-Verified])
# 이 파일은 main↔core 브랜치 간 공유 계약입니다.
# 수정 규칙:
#   1. 필드 추가: 반드시 minor version bump (v1.0 → v1.1)
#   2. 필드 삭제/이름 변경: 반드시 major version bump (v1.x → v2.0)
#   3. 자동 리팩토링 도구의 대상이 아닙니다
#   4. 이 파일의 수정은 human architect 승인이 필요합니다
#   5. 커밋 메시지에 [Arch-Review-Verified] 키워드 필수
# ═══════════════════════════════════════════════════════════════

from core/types/gate_types import FailureCategory, FailCacheTtlSec, cacheTtl,
  GateHermeticity, ghHermetic, ghTransient
import core/results
import std/tables
import std/times
import gate/framework/topology_types
import gate/topology_spec
import core/gate/static_project_matrix
export FailureCategory, FailCacheTtlSec, cacheTtl, GateHermeticity

const AxiomTotalGates* = TopologySpec.len
  ## Live gate count derived from SSOT TopologySpec (== 57).
static:
  assert AxiomTotalGates <= static_project_matrix.AxiomLedgerCap,
    "SSOT mismatch: live gate count exceeds ledger capacity"

type
  GateStage* = enum
    gsPreCommit
    gsPrePush
    gsManual
    gsCI            ## CI-only stage (not in local hooks)
    gsAnyCi         ## CI-only virtual stage: matches any CI gate (pre-commit|pre-push|CI)

  GateLayer* = enum
    glMeta         ## L1: infrastructure verification (no process spawning)
    glFunctional   ## L2: code/logic verification (may spawn processes)

  GateWeight* = enum
    gwLight = 1    ## Fast static analysis / metadata gates (<100 MB, <1s)
    gwMedium = 2   ## Moderate compilation / single-process verification
    gwHeavy = 4    ## Full test suite / multi-process compilation / Lean+Z3

  GateRunMode* = enum
    grmIncremental  ## Fast-Feedback: staged changed files only (pre-commit)
    grmExhaustive   ## Deep-Validation: full src/ + tests/gateway/ (pre-push, CI)

  GateSeverity* = enum
    gsWarn    ## Warning-only: stderr 출력, exit code 0 허용 (observability phase)
    gsError   ## Error: exit code 1, CI 차단 (enforcement phase)

  GateResult* = object
    ok*: bool
    name*: string
    stdout*: string
    stderr*: string
    duration*: Duration
    failureCategory*: FailureCategory  ## ok=false일 때만 유효
    failureReason*: string             ## ok=false일 때만 유효
    skipCiRequested*: bool             ## CI=0 cutover 이후 설정자 없음(관성 유지). 스레드 안전 — 각 가드가 자기 결과에만 기록

  GateErrorCode* = enum
    gecTimeout         ## Gate exceeded time budget
    gecCompileFail     ## Gate binary compilation failed
    gecAssertionFail   ## Compile-time assertion violation
    gecIoError         ## File system I/O failure
    gecVfsKeyNotFound  ## VFS lookup miss (requested path not in VFS)
    gecSubprocessFail  ## External process returned non-zero
    gecUnknown         ## Unclassified error

  GateError* = object
    code*: GateErrorCode
    message*: string
    gateId*: string

  GateOutcome* = Result[GateResult, GateError]

  # ── Context-Aware Dependency Types ──
  # Typed declarations for external state that gates may depend on.
  # Eliminates magic strings; enables compile-time exhaustive checking via `case`.

  DependencyKind* = enum
    dkGitConfig,    ## git config --local --get <key>
    dkEnvVar        ## env var access

  EnvDependency* = object
    kind*: DependencyKind
    key*: string

  EnvContextSnapshot* = object
    values*: Table[string, string]   ## key → value (deterministic snapshot)

  EnvError* = object
    msg*: string
    dep*: EnvDependency

  InputSliceKind* = enum
    skFilesPattern    ## Existing filesPattern-based matching
    skSubtreeHash     ## Merkle subtree hash of specific directories
    skDataFileHash    ## SHA-256 of specific data files
    skAlways          ## Always run (no caching)

  GateConfig* = object
    id*: string
    name*: string
    layer*: GateLayer      ## Architecture layer — enforces boundary rules
    entry*: string
    executionMode*: string  ## aot or interpreted execution policy
    stages*: set[GateStage]
    filesPattern*: string
    scope*: seq[string]
    passFilenames*: bool
    priority*: int
    envVars*: seq[(string, string)]
    weight*: GateWeight    ## Concurrency cost — global token scheduler budget unit
    depsDirs*: seq[string]  ## Dependency paths for Merkle fallback when entry=""
    argsTemplate*: seq[string]  ## CLI argument template (e.g. @["$repoRoot", "$mode", "$maxJobs"])
    after*: seq[string]          ## DAG dependency: gate IDs that must complete before this gate
    tier*: int                   ## Execution tier: 1=fast-path (light), 2=deep-path (heavy/compilation)
    envDependencies*: seq[EnvDependency]  ## External state dependencies for context-aware cache keys
    severity*: GateSeverity              ## Failure severity: gsError (blocking) or gsWarn (warning-only)
    gracePeriodUntil*: string            ## ISO 8601 date: gsError treated as gsWarn until this date
    hermeticity*: GateHermeticity       ## Cache policy: ghHermetic or ghTransient
    # ── Phase 1-C: Fine-Grained Input Slicing ──
    # Enables per-gate cache key isolation instead of global compositeLockHash.
    # Orchestrator reconstructs InputSlice from these fields (see gate/slice_hash.nim).
    inputSliceKind*: InputSliceKind    ## Compile-time enum: skFilesPattern | skSubtreeHash | skDataFileHash | skAlways
    inputSlicePaths*: seq[string]      ## File/directory paths for slice hash computation
    inputSliceExclude*: seq[string]    ## Exclude patterns for slice hash computation
    # ── Phase H: DAG Artifact Subscriptions ──
    produces*: seq[string]             ## Artifact paths this gate produces (optional)
    subscribes*: seq[string]           ## Artifact paths this gate subscribes to (optional)
    alwaysRun*: bool              ## Deterministic scope routing: run even when change-set is empty (opt-in)

  GateRunner* = object
    maxJobs*: int
    failFast*: bool
    repoRoot*: string

  PushRef* = object
    localRef*: string     # e.g. "refs/heads/core"
    localSha*: string     # 40-char full hash
    remoteRef*: string    # e.g. "refs/heads/core"
    remoteSha*: string    # 40-char full hash

# ---------------------------------------------------------------------------
# Gate Definition Conversion (from TopologySpec to GateConfig)
# ---------------------------------------------------------------------------

func convertStageKind(kitchen: StageKind): GateStage {.raises: [].} =
  case kitchen
  of skPreCommit: gsPreCommit
  of skPrePush: gsPrePush
  of skManual: gsManual
  of skCI: gsCI

func convertLayerKind(lk: LayerKind): GateLayer {.raises: [].} =
  case lk
  of lkMeta: glMeta
  of lkFunctional: glFunctional

func convertWeightKind(wk: WeightKind): GateWeight {.raises: [].} =
  case wk
  of wkLight: gwLight
  of wkMedium: gwMedium
  of wkHeavy: gwHeavy

func convertSeverityKind(sv: SeverityKind): GateSeverity {.raises: [].} =
  case sv
  of svWarn: gsWarn
  of svError: gsError

func convertHermeticityKind(hk: HermeticityKind): GateHermeticity {.raises: [].} =
  case hk
  of hkHermetic: ghHermetic
  of hkTransient: ghTransient

func convertExecutionModeKind(em: ExecutionModeKind): string {.raises: [].} =
  case em
  of emAOT: "aot"
  of emInterpreted: "interpreted"

func allGates*(): seq[GateConfig] {.raises: [CatchableError].} =
  ## Convert TopologySpec entries to GateConfig objects.
  ## This is the SSOT-to-runtime adapter used by the execution layer.
  result = @[]
  for entry in TopologySpec:
    var stageSet: set[GateStage]
    for s in entry.stages:
      stageSet.incl(convertStageKind(s))
    let gc = GateConfig(
      id: entry.id,
      name: entry.name,
      layer: convertLayerKind(entry.layer),
      entry: entry.entry,
      executionMode: convertExecutionModeKind(entry.executionMode),
      stages: stageSet,
      filesPattern: entry.filesPattern,
      scope: @[],
      passFilenames: entry.passFilenames,
      priority: entry.priority,
      envVars: @[],
      weight: convertWeightKind(entry.weight),
      depsDirs: entry.depsDirs,
      argsTemplate: entry.argsTemplate,
      after: entry.after,
      tier: entry.tier,
      envDependencies: @[],
      severity: convertSeverityKind(entry.severity),
      gracePeriodUntil: "",
      hermeticity: convertHermeticityKind(entry.hermeticity),
      inputSliceKind: skFilesPattern,
      inputSlicePaths: @[],
      inputSliceExclude: @[],
      produces: @[],
      subscribes: @[],
      alwaysRun: entry.alwaysRun
    )
    result.add(gc)
  result.sort(proc(a, b: GateConfig): int = system.cmp(a.id, b.id))

{.pop.}
