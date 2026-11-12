import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## gate_types.nim — SSOT for architecture gate and certificate directive types.
## Extracted from domain_types.nim (Phase B-4).

import core/types/certificate_types

type
  ArchitectureGateSeverity* = enum
    agWarning
    agBlocking

  ArchitectureViolation* = object
    checkName*: string
    ruleId*: string
    severity*: ArchitectureGateSeverity
    message*: string
    affectedFunctions*: seq[string]

  ArchitecturePrinciplesGate* = object
    warnings*: int
    blockingFailures*: int
    totalPenalty*: float
    violations*: seq[ArchitectureViolation]

  AuditTrailViolation* = object
    functionName*: string
    ruleId*: string
    severity*: ArchitectureGateSeverity
    message*: string

  AuditTrailGate* = object
    violations*: seq[AuditTrailViolation]
    blockingFailures*: int

  GlobalInfluenceViolation* = object
    functionName*: string
    ruleId*: string
    severity*: ArchitectureGateSeverity
    message*: string
    influencer*: string
    affectedNodes*: seq[string]
    reason*: string

  GlobalInfluenceGate* = object
    violations*: seq[GlobalInfluenceViolation]
    blockingFailures*: int

  TypeIntegrityViolation* = object
    functionName*: string
    ruleId*: string
    severity*: ArchitectureGateSeverity
    message*: string
    affectedNodes*: seq[string]

  TypeIntegrityGate* = object
    violations*: seq[TypeIntegrityViolation]
    blockingFailures*: int

  SymbolicInvariantViolation* = object
    functionName*: string
    ruleId*: string
    severity*: ArchitectureGateSeverity
    message*: string
    affectedNodes*: seq[string]

  SymbolicInvariantGate* = object
    violations*: seq[SymbolicInvariantViolation]
    blockingFailures*: int

  SemanticIntegrityViolation* = object
    functionName*: string
    ruleId*: string
    severity*: ArchitectureGateSeverity
    message*: string
    affectedNodes*: seq[string]
    nimInvariant*: string
    leanProposition*: string

  SemanticIntegrityGate* = object
    violations*: seq[SemanticIntegrityViolation]
    blockingFailures*: int
    validatedCount*: int
    semanticHallucinations*: int

  # Gate Layer Purity: Data-Centric Contracts (Phase 2)
  # Gate procs MUST NOT mutate FunctionCertificate directly.
  # They produce read-only GateDirectiveBundle[T] containing:
  #   1. gateResult: the analysis result object (*Gate)
  #   2. directives: seq[CertificateDirective] describing mutations to apply
  # Actual mutation is performed by certificate_applier.nim (Infra layer).
  # See: AGENTS.md §0.3 First-Principles, docs/history/phase2-gate-purity.md

  CertificateDirectiveKind* = enum
    cdkSetStatus       ## Change certificate status + reason
    cdkSetLinkage      ## Change linkageVerified field
    cdkSetField        ## Extension point for future field mutations

  CertificateDirective* = object
    functionName*: string               ## Target function's qualifiedName
    kind*: CertificateDirectiveKind
    status*: CertificateStatus          ## For cdkSetStatus
    reason*: string                     ## For cdkSetStatus
    linkageVerified*: bool              ## For cdkSetLinkage
    fieldName*: string                  ## For cdkSetField (extension)
    fieldValue*: string                 ## For cdkSetField (extension)

  GateDirectiveBundle*[T] = object
    gateResult*: T                      ## The analysis result (*Gate)
    directives*: seq[CertificateDirective]

  # ── Gate Failure Category (shared between core/ and gate/ layers) ──
  # SSOT: failure classification for type-safe cache policy.
  # gate/gate_types.nim re-exports this; core/gate/gate_memo.nim imports directly.
  FailureCategory* = enum
    fcPermanent   ## 영구 실패: 설정 누락, 권한 부족 — 캐시 안 함 (TTL=0)
    fcTransient   ## 일시적 실패: uncommitted changes, 네트워크 — 캐시 가능 (TTL=300)
    fcValidation  ## 검증 실패: 코드 로직 위반 — CAS 영구 캐시 (TTL=0, content-addressed invalidation)
    fcUnknown     ## 알 수 없는 상태: 분류 불가능 — theater detection, 안전 측 실패 (TTL=0)

  # ── Gate Hermeticity (cache policy determinism) ──
  # SSOT: classifies whether a gate's result depends only on declared inputs
  # (hermetic) or on external mutable state (transient).
  # Hermetic gates cache both PASS and FAIL (deterministic given inputs).
  # Transient gates never cache FAIL (external state may change between runs).
  GateHermeticity* = enum
    ghHermetic   ## 결과가 선언된 입력 + 파일 변경에만 의존 — PASS/FAIL 모두 CAS 캐싱
    ghTransient  ## 외부 상태 의존 (네트워크, git config, CLI) — FAIL 캐싱 금지

const FailCacheTtlSec* = 300  ## Cache TTL for transient failures (seconds)

func cacheTtl*(cat: FailureCategory): int =
  ## Cache TTL by failure category.
  ## Used in gate_contract.nim for failure category caching.
  case cat
  of fcPermanent: 0
  of fcTransient: FailCacheTtlSec
  of fcValidation: 0
  of fcUnknown: 0

{.pop.}
