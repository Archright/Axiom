## Refactor Task Types — SSOT for sieve-triggered refactoring task lifecycle.
## Defines the work-unit and result types used by the Sieve Refactoring Trigger.

import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import core/types/hubs/sorter_node_id        # SorterNodeId
import core/types/hubs/refactoring_hub       # RefactoringTemplate
import core/types/obligation_evidence        # ObligationEvidence

type
  RefactorStrategy* = enum
    stratStructuralAST       ## b > u: deterministic static transform (no LLM)
    stratInvariantInference  ## u >= b: AI-based invariant injection (Phase 2)

  SieveRuleKind* = enum
    srkTopology
    srkAstAnalysis
    srkUnsatCore
    srkIoBoundary

  RefactorTask* = object
    nodeId*: SorterNodeId
    modulePath*: string
    functionName*: string
    sourceCode*: string
    currentEntropy*: float
    strategy*: RefactorStrategy
    dominantRule*: SieveRuleKind
    ruleWarnings*: seq[string]
    templates*: seq[RefactoringTemplate]
    attempt*: int
    maxAttempts*: int
    belief*: float
    uncertainty*: float

  RefactorStatus* = enum
    rsVerified    ## 수학적 증명 성공 (Z3 통과)
    rsSkipped     ## Soft Guide 컷 (패턴 미스치 등)
    rsEscalated   ## Hard Gate 실패 (파서 오류, Z3 타임아웃 등)

  SkippedReason* = enum
    srPatternMismatch    ## 패턴 가드 soft miss
    srNoTransformApplied ## 변형 로직이 변경 없음
    srIoDetected         ## I/O 경계 노드 (Phase 2)

  EscalationReason* = enum
    erGuardHardReject    ## 패턴 가드 hard reject (파서 실패)
    erZ3Rejected         ## Z3 등가성 검증 실패
    erZ3Timeout          ## Z3 타임아웃
    erEnginePanic        ## 엔진 내부 예외 및 버그 추적용
    erInvariantPhase2    ## Phase 2 placeholder

  RefactorResult* = object
    evidence*: ObligationEvidence
    case status*: RefactorStatus
    of rsVerified:
      refactoredSource*: string
    of rsSkipped:
      skipReason*: SkippedReason
      softMisses*: seq[string]
    of rsEscalated:
      escalateReason*: EscalationReason
      contextLog*: string

{.pop.}
