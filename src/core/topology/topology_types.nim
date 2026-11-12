import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import std/[sets, options, strutils, tables]
import core/sorter/sorter_core
import core/topology/plan
export sorter_core, plan, options

type
  TopologyBoundaryKind* = enum
    topologyBoundaryNone,
    topologyBoundaryInterface,
    topologyBoundaryTrivialDiscard

  ResolutionKind* = enum
    rrUnique       ## 정확히 한 후보로 결정됨
    rrAmbiguous    ## 같은 module::name에 여러 definition (func/template 등) 존재 — 임의 선택 금지
    rrUnresolved   ## 후보 없음

  ResolutionResult* = object
    kind*: ResolutionKind
    resolvedIdx*: int       ## rrUnique일 때 유효
    candidates*: seq[int]   ## rrAmbiguous일 때 후보 목록 (디버깅/진단용)

  TopologySymbol* = object
    modulePath*: string
    functionName*: string
    nodeType*: string
    nodeId*: SorterNodeId
    declarationLine*: int
    bodyStartLine*: int
    bodyEndLine*: int
    exported*: bool
    boundaryKind*: TopologyBoundaryKind
    rawCallTargets*: seq[string]
    branchCount*: int
    nestingDepth*: int
    lineSpan*: int
    hasAxiomImpl*: bool  ## AST-based {.} pragma detection
    definitionFingerprint*: string  ## definition discriminator (additive, does not alter SorterNodeId)

  TopologyNodeMetric* = object
    nodeId*: SorterNodeId
    interfaceDistance*: int
    dependencyCount*: int
    dependentCount*: int
    transitiveDependentCount*: int
    couplingScore*: int
    centralityScore*: int
    complexityScore*: int
    topologyScore*: int
    branchCount*: int
    nestingDepth*: int
    lineSpan*: int
    logicalDepth*: int
    semanticWeight*: float

  TopologyUnresolvedEdge* = object
    ## An edge that could not be resolved to a unique dependency node.
    ## Retained in the graph artifact so that downstream stages (S1)
    ## can force FALLBACK_REQUIRED when such edges are reachable from a change.
    fromNodeId*: SorterNodeId
    targetName*: string
    modulePath*: string
    resolutionKind*: ResolutionKind

  TopologyAnalysis* = object
    state*: SorterState
    symbols*: seq[TopologySymbol]
    metrics*: seq[TopologyNodeMetric]
    verificationQueue*: seq[SorterNodeId]
    structuralBottlenecks*: seq[SorterNodeId]
    repairPriorityDependencies*: seq[SorterNodeId]
    symbolFirstPass*: bool
    ## W3-C: O(1) index tables built during topology construction.
    metricIndex*: Table[string, int]
    symbolIndex*: Table[string, int]
    ## Unresolved / ambiguous call-target edges retained from topology construction.
    ## These edges are NOT added to node.dependencyIds (they have no resolved target),
    ## but they are preserved in the artifact so that a change flowing through an
    ## unknown edge is not silently missed.
    unresolvedEdges*: seq[TopologyUnresolvedEdge]

type
  TopologyScopeKind* = enum
    topologyScopeIndent,
    topologyScopeBrace

  DeclParseResult* = object
    found*: bool
    functionName*: string
    exported*: bool
    indent*: int
    bodyFragment*: string
    signatureText*: string  ## declaration text before body (= delimiter), used for definitionFingerprint
    scopeKind*: TopologyScopeKind
    initialBraceDepth*: int
    braceSeen*: bool
    nodeType*: string

  TopologyTraversalContext* = object
    visited*: HashSet[int]
    inFlight*: HashSet[int]

# ── Execution Plan Types (I/O-free intent representation) ──────────────────

type
  TopologyOperationKind* = enum
    tokMoveFile
    tokWriteFile
    tokExec
    tokCreateDir
    tokStageFile
    tokRecordManifest
    tokUpdateLock

  TopologyOperation* = object
    ## Business intent only: what to do to the filesystem.
    case kind*: TopologyOperationKind
    of tokMoveFile:
      srcPath*, dstPath*: string
    of tokWriteFile:
      writePath*, content*: string
    of tokExec:
      command*: seq[string]
    of tokCreateDir:
      dirPath*: string
    of tokStageFile:
      stageSrc*: string
    of tokRecordManifest:
      manifestPlan*: Plan
    of tokUpdateLock:
      lockPath*: string
      lockMoves*: seq[MoveOp]

  TopologyExecutionPolicy* = object
    ## Environment controls, separate from business operations.
    dryRun*: bool
    force*: bool
    requireCleanGit*: bool
    requireApproval*: bool
    allowRollback*: bool
    autoApprove*: bool

  TopologyExecutionPlan* = object
    policy*: TopologyExecutionPolicy
    operations*: seq[TopologyOperation]

  TopologyExecutionResultKind* = enum
    terkSuccess
    terkDryRun
    terkCancelled
    terkValidationFailed
    terkRollbackFailed

  TopologyExecutionResult* = object
    kind*: TopologyExecutionResultKind
    executed*: seq[TopologyOperation]
    error*: Option[string]

# ── Pure path helpers (no std/os) ──────────────────────────────────────────

func topologyExtractFilename*(path: string): string {.raises: [].} =
  let lastSlash = path.rfind('/')
  if lastSlash >= 0:
    result = path.substr(lastSlash + 1)
  else:
    result = path

func topologyParentDir*(path: string): string {.raises: [].} =
  let lastSlash = path.rfind('/')
  if lastSlash >= 0:
    result = path.substr(0, lastSlash - 1)
  else:
    result = ""

{.pop.}
