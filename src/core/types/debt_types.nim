## Debt Type Definitions — structured debt/quirk classification.
##
## Provides DebtKind enum and parseDebtKind() for type-safe debt
## category extraction from {.axiomDebt.} pragmas.
## Also provides BudgetCategory enum for budget metric categorization.

import std/[strutils, options, typetraits]
import checksums/sha2

type
  DebtKind* = enum
    dkArchitecture = "architecture"
    dkSafety       = "safety"
    dkPerformance  = "performance"
    dkQuirk        = "quirk"
    dkLegacy       = "legacy"

  BudgetCategory* = enum
    ## Budget metric categories from data/debt_budgets.json.
    bcImportLint      ## import_lint_violations — tools/ importing src/core/ or src/gate/
    bcLayerViolation  ## layer_violations — src/core/ importing gate/ directly
    bcEffectViolation ## effect_violations — procs lacking {.raises: [].}
    bcNimtryViolation ## nimtry_violations — soc-domain-imports violations
    bcDebtRegistryOpen ## debt_registry_open — open entries count
    bcDebtRegistryClosed ## debt_registry_closed — closed entries count

func parseDebtKind*(s: string): Option[DebtKind] {.raises: [].} =
  ## Parse a string into DebtKind at runtime.
  ## Returns none if the string is not a valid DebtKind value.
  ##
  ## Example:
  ##   parseDebtKind("quirk")       → some(dkQuirk)
  ##   parseDebtKind("architecture") → some(dkArchitecture)
  ##   parseDebtKind("invalid")      → none(DebtKind)
  let normalized = s.strip().toLowerAscii()
  case normalized
  of "architecture": some(dkArchitecture)
  of "safety":       some(dkSafety)
  of "performance":  some(dkPerformance)
  of "quirk":        some(dkQuirk)
  of "legacy":       some(dkLegacy)
  else:              none(DebtKind)

func debtKindToStr*(kind: DebtKind): string {.raises: [].} =
  ## Convert DebtKind to its string representation.
  ## Inverse of parseDebtKind().
  result = $kind  # Nim auto-uses the string value ("architecture", "quirk", etc.)

func parseBudgetCategory*(s: string): Option[BudgetCategory] {.raises: [].} =
  ## Parse a string into BudgetCategory at runtime.
  ## Returns none if the string is not a valid BudgetCategory value.
  ##
  ## Example:
  ##   parseBudgetCategory("importLint")     → some(bcImportLint)
  ##   parseBudgetCategory("effectViolation") → some(bcEffectViolation)
  ##   parseBudgetCategory("invalid")        → none(BudgetCategory)
  let normalized = s.strip().toLowerAscii()
  case normalized
  of "importlint":      some(bcImportLint)
  of "layerviolation":  some(bcLayerViolation)
  of "effectviolation": some(bcEffectViolation)
  of "nimtryviolation": some(bcNimtryViolation)
  of "debtregistryopen": some(bcDebtRegistryOpen)
  of "debtregistryclosed": some(bcDebtRegistryClosed)
  else:                 none(BudgetCategory)

func budgetCategoryToStr*(cat: BudgetCategory): string {.raises: [].} =
  ## Convert BudgetCategory to its string representation.
  ## Inverse of parseBudgetCategory().
  result = $cat  # Nim auto-uses the enum name ("bcImportLint" → "bcImportLint")

type
  DebtClass* = enum
    dcOpenDebt     ## Entry is open with verifiable evidence on disk
    dcUnverified   ## Entry is open but no verifiable evidence on disk
    dcStale        ## Entry references no existing files and status is closed/accepted
    dcResolved     ## Entry is closed with a resolution
    dcQuirk        ## Category contains "quirk"
    dcBudgetDrift  ## Budget metric where current exceeds baseline

func debtClassToStr*(dc: DebtClass): string {.raises: [].} =
  ## Convert DebtClass to its canonical string label.
  case dc
  of dcOpenDebt:   "OPEN_DEBT"
  of dcUnverified: "UNVERIFIED"
  of dcStale:      "STALE"
  of dcResolved:   "RESOLVED"
  of dcQuirk:      "QUIRK"
  of dcBudgetDrift: "BUDGET_DRIFT"

# ---------------------------------------------------------------------------
# Evidence-First 재아키텍처 — 공용 타입 계약 (Phase 0/0b/3/6 기반)
#
# 다른 모듈(debt_observation, debt_identity, debt_classifier, debt_claim,
# debt_budget, debt_provenance, debt_correlation, debt_cli)이 이 파일의 타입을
# 공통 계약으로 import한다. 고정 스키마이므로 임의 확장 전에 여기에서 결정한다.
# ---------------------------------------------------------------------------

type
  ObservationKind* = enum
    okSourceMarker      ## explicit source marker (DEBT#/QUIRK(/TODO/...)
    okAstPattern        ## AST-surface semantic pattern
    okCfgPattern        ## CFG/control-flow pattern
    okGateDeclaration   ## declared gate in topology
    okGateExecution     ## observed gate execution
    okCertificate       ## certificate artifact event
    okProofArtifact     ## proof/proof-artifact event
    okPromotion         ## artifact promotion event
    okMetric            ## budget/metric observation
    okMetricEvaluation  ## metric evaluation with observed value, direction, status
    okDocumentClaim     ## claim from docs/spec
    okExternalClaim     ## claim from external/official source (Context7, etc.)

  # Observation subject identity basis (canonical, snapshot-independent).
  # snapshotId 는 identity 가 아니라 Observation 필드로만 보관된다 (피드백 #2).
  DebtObservation* = object
    observationId*: string    ## content-address: H(canonicalObservation)
    kind*: ObservationKind
    subject*: string          ## canonical subject: normalized path (no line)
    semanticIdentity*: string ## symbol/type + AST canonicalSyntaxHash
    # snapshotId 는 identity 가 아니라 관측 컨텍스트
    snapshotId*: string       ## repository snapshot (별도 보관, identity 미포함)
    source*: string
    payload*: string
    observedAt*: string       ## ISO-8601
    toolchainContext*: string
    # Phase 1 metric evaluation extensions (kind==okMetricEvaluation only)
    observedValue*: int64     ## integer metric value at observation time
    direction*: string        ## IMPROVEMENT | REGRESSION | MAINTAINED
    status*: string           ## PASS | DRIFT | INFO

  # candidateId: rule-independent, snapshot-independent (피2).
  # candidateId = H(canonicalSubject ∥ semanticIdentity)
  ClassificationRecord* = object
    candidateId*: string
    classifierVersion*: string
    ruleSetHash*: string
    taxonomyVersion*: string
    result*: DebtClass
    evidenceIds*: seq[string]

  # ClassificationEvent: 이벤트 소싱, append-only. 최신 committed event가 current view (피5, I19).
  # identity 원칙: auditSequence 는 audit-LOCAL total order 이다. 전역 순서는
  # AuditCommit.commitSequence 가 담당 (global event sequence 만들지 않음, v3#3/v4#1).
  ClassificationEvent* = object
    eventId*: string
    candidateId*: string
    auditRunId*: string          ## owning audit run (metadata)
    auditSequence*: uint64       ## audit-local sequence 0,1,2,... (전역 아님)
    decisionId*: string          ## id of persisted immutable PolicyDecision (sha256 ref)
    classifierVersion*: string
    ruleSetHash*: string
    taxonomyVersion*: string
    result*: DebtClass
    evidenceIds*: seq[string]
    parentEventId*: string    ## 이전 event (같은 candidate lineage)
    recordedAt*: string
    repositorySnapshot*: string

  # Claim specialization — 모든 도메인이 같은 파이프라인 (피7)
  ClaimKind* = enum
    ckDebtClaim
    ckQuirkClaim
    ckDriftClaim
    ckIntegrityClaim

  QuirkOwnership* = enum
    qoUpstreamConfirmed   ## view: UPSTREAM_CONFIRMED
    qoProjectLocal        ## view: PROJECT_LOCAL
    qoUnverifiedHistorical ## view: UNVERIFIED_HISTORICAL

  Claim* = ref object
    claimId*: string
    kind*: ClaimKind
    candidateId*: string
    text*: string
    evidenceIds*: seq[string]

  QuirkClaim* = object
    claim*: Claim
    ownership*: QuirkOwnership
    confidence*: float      ## reproduction confidence 0..1
    reproduction*: string
    toolchainVersion*: string
    upstreamRefs*: seq[string]  ## official docs / issue refs
    localTestRefs*: seq[string]

  DriftKind* = enum
    driftMatch            ## MATCH
    driftMeasurement      ## MEASUREMENT_DRIFT
    driftBaseline         ## BASELINE_DRIFT
    driftDefinition       ## DEFINITION_DRIFT
    driftIntentional      ## INTENTIONAL_REGRESSION
    driftStaleBudget      ## STALE_BUDGET
    driftUnverified       ## UNVERIFIED

  MetricObservation* = object
    metricId*: string
    value*: float
    definitionHash*: string
    measurementMethodHash*: string
    scope*: string
    baselineRef*: float
    repoSnapshot*: string
    toolchainContext*: string

  Debt* = object
    candidateId*: string
    kind*: ClaimKind
    actionable*: bool
    currentlyTrue*: bool
    evidenceSufficient*: bool
    intentionallyAccepted*: bool
    classification*: ClassificationRecord

  # Provenance DAG (Phase 2)
  ProvenanceNodeKind* = enum
    pnkRepositorySnapshot
    pnkObservation
    pnkPattern
    pnkClaim
    pnkClassification
    pnkDebt
    pnkArtifact

  ProvenanceEdgeKind* = enum
    peDerivedFrom
    peObservedIn
    peExecutedAs
    peProves
    pePromotedBy
    peClassifiedBy
    peSupersedes
    peRenamedFrom
    peSplitFrom
    peMergedInto
    peResolves
    peRegresses

  ProvenanceNode* = object
    nodeId*: string
    kind*: ProvenanceNodeKind
    payloadRef*: string

  ProvenanceEdge* = object
    edgeKind*: ProvenanceEdgeKind
    fromNode*: string
    toNode*: string

  ProvenanceGraph* = object
    nodes*: seq[ProvenanceNode]
    edges*: seq[ProvenanceEdge]

func observationIdentity*(subject: string; semanticIdentity: string): string
    {.raises: [].} =
  ## Raw concatenation forming the input to candidateId hash.
  ## (Hashing itself is provided by sha2 in the identity module.)
  subject & "\x1e" & semanticIdentity

func quirkOwnershipToStr*(q: QuirkOwnership): string {.raises: [].} =
  case q
  of qoUpstreamConfirmed:   "UPSTREAM_CONFIRMED"
  of qoProjectLocal:        "PROJECT_LOCAL"
  of qoUnverifiedHistorical: "UNVERIFIED_HISTORICAL"

# ---------------------------------------------------------------------------
# Phase 0 — Typed Identity Namespace (I11: raw string → typed identity only
# via a validated constructor; no free-form casting).
#
# Three-level identity separation (禁止 #2: one hash must not mean both
# content, execution, and lineage). Distinct string types prevent collapse:
#   ContentDigest — "what this artifact is" (content identity)
#   ExecutionId   — "which execution produced it" (content-addressed execution)
#   LineageId     — "which logical verification operation" (lineage)
#   PromotionId   — a single promotion event (execution identity of promotion)
#   AuditInputId  — content-addressed, immutable audit input snapshot
#   AuditRunId    — a specific audit invocation (input id + ordinal + nonce)
#   EventId       — append-only classification/observation event identity
#   CandidateId   — rule-independent, snapshot-independent fingerprint/lineage
# ---------------------------------------------------------------------------

func sha256Ref*(prefix, payload: string): string {.raises: [].} =
  ## ``"sha256:" & hex(secureHash(payload))`` — canonical content digest.
  "sha256:" & $Sha_256.secureHash(prefix & payload)

func isValidSha256Ref*(s: string): bool {.raises: [].} =
  ## True iff ``s`` is exactly ``sha256:`` followed by 64 lowercase hex chars.
  ## This is the canonical form for all content-addressed identities.
  if s.len != 71 or not s.startsWith("sha256:"):
    return false
  for c in s[7 .. ^1]:
    if c notin {'0'..'9', 'a'..'f'}:
      return false
  true

type
  ContentDigest* = distinct string
  ExecutionId*   = distinct string
  LineageId*     = distinct string
  PromotionId*   = distinct string
  AuditInputId*  = distinct string
  AuditRunId*    = distinct string
  EventId*       = distinct string
  CandidateId*   = distinct string

# A generic content digest over a phantom subject tag. ``Digest[ProofArtifact]``
# and ``Digest[Certificate]`` are distinct types even though the payload string
# is shared — the Rust ``PhantomData`` analogue for Axiom artifacts.
type
  Digest*[T] = distinct string

func raw*(x: ContentDigest): string {.raises: [].} = string(x)
func raw*(x: ExecutionId): string   {.raises: [].} = string(x)
func raw*(x: LineageId): string     {.raises: [].} = string(x)
func raw*(x: PromotionId): string   {.raises: [].} = string(x)
func raw*(x: AuditInputId): string  {.raises: [].} = string(x)
func raw*(x: AuditRunId): string    {.raises: [].} = string(x)
func raw*(x: EventId): string       {.raises: [].} = string(x)
func raw*(x: CandidateId): string   {.raises: [].} = string(x)
func raw*[T](x: Digest[T]): string  {.raises: [].} = string(x)

func `$`*(x: ContentDigest): string {.raises: [].} = string(x)
func `$`*(x: ExecutionId): string   {.raises: [].} = string(x)
func `$`*(x: LineageId): string     {.raises: [].} = string(x)
func `$`*(x: PromotionId): string   {.raises: [].} = string(x)
func `$`*(x: AuditInputId): string  {.raises: [].} = string(x)
func `$`*(x: AuditRunId): string    {.raises: [].} = string(x)
func `$`*(x: EventId): string       {.raises: [].} = string(x)
func `$`*(x: CandidateId): string   {.raises: [].} = string(x)
func `$`*[T](x: Digest[T]): string  {.raises: [].} = string(x)

# Distinct-string value semantics for all typed identities. `==`/`!=` compare
# the underlying raw form so tests and provenance lookups can compare safely.
func `==`*(a, b: ContentDigest): bool {.raises: [].} = string(a) == string(b)
func `==`*(a, b: ExecutionId): bool   {.raises: [].} = string(a) == string(b)
func `==`*(a, b: LineageId): bool     {.raises: [].} = string(a) == string(b)
func `==`*(a, b: PromotionId): bool   {.raises: [].} = string(a) == string(b)
func `==`*(a, b: AuditInputId): bool  {.raises: [].} = string(a) == string(b)
func `==`*(a, b: AuditRunId): bool    {.raises: [].} = string(a) == string(b)
func `==`*(a, b: EventId): bool       {.raises: [].} = string(a) == string(b)
func `==`*(a, b: CandidateId): bool   {.raises: [].} = string(a) == string(b)
func `==`*[T](a, b: Digest[T]): bool  {.raises: [].} = string(a) == string(b)

func `!=`*(a, b: ContentDigest): bool {.raises: [].} = not (a == b)
func `!=`*(a, b: ExecutionId): bool   {.raises: [].} = not (a == b)
func `!=`*(a, b: LineageId): bool     {.raises: [].} = not (a == b)
func `!=`*(a, b: PromotionId): bool   {.raises: [].} = not (a == b)
func `!=`*(a, b: AuditInputId): bool  {.raises: [].} = not (a == b)
func `!=`*(a, b: AuditRunId): bool    {.raises: [].} = not (a == b)
func `!=`*(a, b: EventId): bool       {.raises: [].} = not (a == b)
func `!=`*(a, b: CandidateId): bool   {.raises: [].} = not (a == b)
func `!=`*[T](a, b: Digest[T]): bool  {.raises: [].} = not (a == b)

# Validated constructors (I11) — invalid shapes are rejected at the boundary.
func parseContentDigest*(s: string): Option[ContentDigest] {.raises: [].} =
  if isValidSha256Ref(s): some(ContentDigest(s)) else: none(ContentDigest)

func parseEventId*(s: string): Option[EventId] {.raises: [].} =
  if isValidSha256Ref(s): some(EventId(s)) else: none(EventId)

func parseCandidateId*(s: string): Option[CandidateId] {.raises: [].} =
  if isValidSha256Ref(s): some(CandidateId(s)) else: none(CandidateId)

func parseAuditInputId*(s: string): Option[AuditInputId] {.raises: [].} =
  if isValidSha256Ref(s): some(AuditInputId(s)) else: none(AuditInputId)

func newExecutionId*(parentExecution, toolchain, config, inputArtifacts, params: string): ExecutionId {.raises: [].} =
  ## Content-addressed execution identity: changing any execution parameter
  ## (e.g. Z3 timeout 5s vs 30s) yields a different ExecutionId, while the same
  ## logical verification lineage may still share a LineageId (replayability).
  ExecutionId(sha256Ref("exec:",
    parentExecution & "\x1e" & toolchain & "\x1e" & config & "\x1e" &
      inputArtifacts & "\x1e" & params))

func newLineageId*(logicalSubject: string): LineageId {.raises: [].} =
  LineageId(sha256Ref("lineage:", logicalSubject))

func newAuditRunId*(inputId: AuditInputId; executionAttemptOrdinal: int; nonce: string): AuditRunId {.raises: [].} =
  ## AuditRunId identifies the *execution*, not the outcome: it is derived from
  ## the content-addressed input + a deterministic attempt ordinal + nonce.
  ## startedAt / wall-clock metadata are excluded so the same input yields an
  ## auditable, replayable run identity (I10).
  AuditRunId(sha256Ref("run:", raw(inputId) & "\x1e" & $executionAttemptOrdinal & "\x1e" & nonce))

# ---------------------------------------------------------------------------
# Phase 2/5 — Integrity policy model. A Pattern is NOT a Debt; it is promoted
# through an explicit policy evaluation only:
#   pattern → policy → (violation ∧ evidence) → PRODUCT_INTEGRITY_DEBT
# Detection and judgment are strictly separated (禁止 #1).
# ---------------------------------------------------------------------------

type
  ObservedIntegrityPattern* = enum
    oipBypass
    oipSkip
    oipExemption
    oipFallback
    oipNonCanonical
    oipManualOverride
    oipUncertifiedPath

  IntegrityPolicyVerdict* = enum
    ipvAcceptable    ## accepted under context (e.g. declared fail-open with docs + log)
    ipvWarning       ## observable, low severity
    ipvViolation     ## product-integrity debt candidate
    ipvUnverified    ## not enough evidence to judge

  IntegrityPolicyEvaluation* = object
    decisionId*: string
    policyDigest*: string
    candidateId*: string
    pattern*: ObservedIntegrityPattern
    verdict*: IntegrityPolicyVerdict
    evidenceIds*: seq[string]
    rationale*: string

  # Policy decision — immutable, content-addressed evaluation artifact. Derived
  # from evidence (never authoritative on its own); referenced by
  # ClassificationEvent.decisionId. decisionId excludes execution/runtime
  # metadata so identical evidence+policy yields a reusable artifact (v4-10).
  PolicyDecision* = object
    decisionId*: ContentDigest     # H(canonical({candidateId|evidenceRoot|policyDigest|verdict|rationale}))
    candidateId*: string
    evidenceRoot*: ContentDigest
    policyDigest*: ContentDigest
    verdict*: IntegrityPolicyVerdict
    rationale*: string

  # Three-level identity on a proof/provenance artifact (禁止 #3):
  #   artifactId      = content identity   (what the proof says)
  #   executionId     = execution identity (which run produced it)
  #   verificationId  = lineage identity   (which logical verification it serves)
  ProofArtifactIdentity* = object
    artifactId*: ContentDigest
    executionId*: ExecutionId
    verificationId*: LineageId

# ---------------------------------------------------------------------------
# v3/v4 — PolicyArtifact / AuditRunStatus / AuditCommit / Rule identity.
# AuditCommit is the SINGLE commitment authority; AuditRun.status is only
# materialized metadata and never independently determines canonical state (I16).
# ---------------------------------------------------------------------------

  PolicyArtifact* = object
    policyId*: ContentDigest       # policyArtifactDigest(canonical all fields) — body-only 가 아님 (v3#5)
    body*: string
    classifierVersion*: string
    taxonomyVersion*: string
    normalizationVersion*: string

  AuditRunStatus* = enum
    arPrepared    ## staged, not yet committed
    arCommitted   ## valid AuditCommit exists (authority); status is metadata
    arFailed      ## audit aborted — its events must NOT be visible in projection (I15)

  AuditCommit* = object
    ## v8 — Canonical Commit Manifest (marker 아님): execution closure를 canonical
    ## history에 편입시키는 유일한 승격 증거. closure = "무엇이 실행/영속되었는가"이지
    ## materialized interpretation이 아니다 (universeDigest/projectionVersion은
    ## ProjectionRequest 쪽 소관 — v8 피드백 5·6). resultRoot는 decisionDigest와
    ## 중복되어 제거.
    commitId*: ContentDigest       # H(canonical(AuditCommit excluding commitId))
    commitSequence*: uint64        # GLOBAL cross-audit history order (v4#1); ordinal position (single-writer)
    auditRunId*: AuditRunId
    firstSequence*: uint64         # first audit-local event seq covered by this commit
    lastSequence*: uint64          # last audit-local event seq covered by this commit
    eventCount*: uint64
    eventRoot*: ContentDigest      # H(canonical(committed event set)) — content-address 증명 (D2)
    decisionDigest*: ContentDigest # evaluator(PolicyDecision[]) output의 canonical root — 실행 결과 단일 해시
    provenanceRoot*: ContentDigest
    parentCommitId*: ContentDigest
    recordedAt*: string            # execution metadata — I18 시간→커밋 resolve용; canonical closure 계산에서 제외

  # v8 — ProjectionRequest: interpretation은 commit 소유가 아니라 request 소유.
  # same commit + projectionVersion v1 → universeDigest A, v2 → universeDigest B.
  ProjectionRequest* = object
    commitId*: ContentDigest
    projectionVersion*: string

  # v8 — ReadHealth: 단순 skip 금지. 반드시 4분류 (canonical reader는 중간 손상 즉
  # integrityFailure, EOF 불완전 frame만 recoverableTail).
  ReadHealth* = enum
    rhClean            ## 유효한 레코드만 존재
    rhRecoverableTail  ## EOF의 불완전 frame만 있음 — 유효 prefix 승격, tail 폐기
    rhMalformedRecord  ## 문법 오류 record 발견 — forensic reader용 기록(telemetry)
    rhIntegrityFailure ## 유효 prefix 이후 중간 손상/체크섬 불일치 — fail-close

  JournalSkip* = object
    lineNo*: int
    reason*: string
    kind*: ReadHealth

  JournalReadReport*[T] = object
    valid*: seq[T]
    skipped*: seq[JournalSkip]
    health*: ReadHealth

# ---------------------------------------------------------------------------
# Phase 7 — Audit input manifest (explicit, not a vague evidenceSnapshot). I9:
#   AuditInputId = H(canonical(AuditInputManifest)); every root it references
#   is immutable. AuditInputId differs from AuditRunId (I10).
# ---------------------------------------------------------------------------

type
  AuditInputManifest* = object
    repositorySnapshot*: string
    evidenceRoot*: ContentDigest
    provenanceRoot*: ContentDigest
    artifactRoot*: ContentDigest
    executionRoot*: ContentDigest
    ruleSetHash*: string             # legacy compatibility — canonical rule id 는 policyDigest
    policyDigest*: ContentDigest     # canonical rule identity (v3#5 unified)
    toolchainContext*: string

  AuditRun* = object
    auditInputId*: AuditInputId
    auditRunId*: AuditRunId
    policyDigest*: ContentDigest
    evidenceRoot*: ContentDigest
    eventRoot*: ContentDigest
    resultRoot*: ContentDigest
    status*: AuditRunStatus        ## materialized metadata (authority = AuditCommit)
    recordedAt*: string            ## metadata — never part of the run id

func canonicalizeManifest*(m: AuditInputManifest): string {.raises: [].} =
  m.repositorySnapshot & "\x1e" &
    raw(m.evidenceRoot) & "\x1e" &
    raw(m.provenanceRoot) & "\x1e" &
    raw(m.artifactRoot) & "\x1e" &
    raw(m.executionRoot) & "\x1e" &
    m.ruleSetHash & "\x1e" &
    raw(m.policyDigest) & "\x1e" &
    m.toolchainContext

func manifestInputId*(m: AuditInputManifest): AuditInputId {.raises: [].} =
  AuditInputId(sha256Ref("AuditInput:", canonicalizeManifest(m)))

# ---------------------------------------------------------------------------
# Phase 3 — EvidenceCollector interface. Static, runtime and external evidence
# all feed through one interface so Layer-3 runtime/proof correlation is a
# normal evidence source, not a special case (⑦).
# ---------------------------------------------------------------------------

type
  EvidenceCollectorKind* = enum
    eckStatic
    eckRuntime
    eckExternal

  EvidenceCollector* = object
    kind*: EvidenceCollectorKind
    detectorId*: string
    detectorVersion*: string
    ruleSetHash*: string

  PatternObservation* = object
    id*: string
    kind*: ObservationKind     # okAstPattern / okCfgPattern / okSourceMarker ...
    pattern*: ObservedIntegrityPattern
    subject*: string           # canonical path (no line)
    semanticIdentity*: string
    payload*: string
    source*: string            # collector id + rule id
    evidenceIds*: seq[string]

# ---------------------------------------------------------------------------
# v4 — UniverseProjection / CandidateProjection — canonical materialized view.
# projection provenance 는 single inputDigest 가 아니라 orderedCommitRoot
# (committed audit-history prefix) 로 바인딩한다. universeDigest =
# H(projectionVersion ∥ cutoff ∥ orderedCommitRoot ∥ policyContextDigest ∥
#   sorted CandidateProjection[]) (v4-8/12).
# ---------------------------------------------------------------------------

type
  CandidateProjection* = object
    candidateId*: string
    classification*: DebtClass
    category*: string
    severity*: string
    active*: bool
    firstSeen*: string         ## ISO-8601 of first committed event (candidate lineage)
    lastSeen*: string          ## ISO-8601 of latest committed event
    lineageId*: string
    decisionId*: string        ## candidate-level policy provenance (→ PolicyDecision.policyDigest)

  UniverseProjection* = object
    projectionVersion*: string
    cutoff*: string            ## cutoff commitId (or "HEAD"/current)
    orderedCommitRoot*: string ## H(canonical ordered [{seq,commitId}...]) provenance
    policyContextDigest*: string  ## H(sorted-unique policyDigests of active candidates) (v3#6)
    inputRoot*: string
    candidates*: seq[CandidateProjection]
    universeDigest*: string    ## canonical projection digest

# ---------------------------------------------------------------------------
# v4 — digest helpers & invariant contracts.
# ---------------------------------------------------------------------------

func integrityPolicyVerdictToStr*(v: IntegrityPolicyVerdict): string {.raises: [].} =
  case v
  of ipvAcceptable: "ACCEPT"
  of ipvWarning:    "WARN"
  of ipvViolation:  "VIOLATION"
  of ipvUnverified: "UNVERIFIED"

func policyArtifactDigest*(body, classifierVersion, taxonomyVersion, normalizationVersion: string): ContentDigest {.raises: [].} =
  ## policyDigest = H(canonical(PolicyArtifact)) — body 뿐 아니라 모든
  ## semantic 메타를 봉합(gam classifierVersion 버전 변경도 digest 변화). (v3#5)
  ContentDigest(sha256Ref("PolicyArtifact:",
    body & "\x1e" & classifierVersion & "\x1e" &
      taxonomyVersion & "\x1e" & normalizationVersion))

func policyDecisionDigest*(candidateId, evidenceRoot, policyDigest: string;
                           verdict: IntegrityPolicyVerdict; rationale: string): ContentDigest {.raises: [].} =
  ## decisionId = H(canonical(PolicyDecision-relevant-fields)). execution/runtime
  ## metadata(decisionId/recordedAt/auditRunId/auditSequence) 제외 → 동일
  ## evidence+policy 는 재사용 가능한 artifact. (v4-10)
  ContentDigest(sha256Ref("PolicyDecision:",
    candidateId & "\x1e" & evidenceRoot & "\x1e" & policyDigest & "\x1e" &
      integrityPolicyVerdictToStr(verdict) & "\x1e" & rationale))

const
  I12ProjectionDeterminism* =
    "same committed ClassificationEvent prefix + same ProjectionVersion -> same UniverseProjection"
  I13ExactEvaluationDeterminism* =
    "same AuditInputManifest + same PolicyArtifact + same evaluatorVersion -> same resultDigest"
  I14HistoricalReconstruction* =
    "delete all materialized views + retain immutable facts/events -> reconstruct -> digest-identical projection"
  I15CommittedVisibility* =
    "uncommitted ClassificationEvent (no valid AuditCommit) -> never visible in canonical current universe"
  I16CommitAuthority* =
    "only a valid AuditCommit (eventRef==expected, committed stream) can produce canonical projection; AuditRun.status is metadata only"
  I17CommitClosure* =
    "a committed AuditRun has an immutable ClassificationEvent set; appending any later event to that run is invalid"
  I18TimeProjectionClosure* =
    "projectUpToTime(t) = projectUpToCommit(latestValidCommitAtOrBefore(t))"
  I19ProjectionStateRule* =
    "current classification(candidate) = latest valid committed ClassificationEvent under order (commitRun,didSeq,eventId); RESOLVED kept as active=false history, never deleted"
  I20ReplayTargetIdentity* =
    "exact replay -> AuditRunId; re-evaluate -> AuditInputId; reconstruct -> CommitId|time; explain -> CandidateId"

  # v8 — 최종 4대 불변식 (피드백 §11 확정 원문). canonical log/history 설계의 계약.
  InvCanonicality* =
    "Canonical history is the maximal valid committed prefix of the audit log"
  InvCommitValidity* =
    "A commit is valid iff its transaction is complete, its closure validates, and its parent/sequence relation matches the preceding canonical commit"
  InvRecovery* =
    "Only an incomplete frame at physical EOF is recoverable; any corruption after a valid committed prefix is fail-closed"
  InvProjectionPure* =
    "Projection is a pure deterministic function of committed canonical events and an explicit projection version"

  # v8 — 결정성 4종 (피드백 7: D4 명칭 = Canonical History Determinism).
  D1ExecutionDeterminism* =
    "same AuditInputManifest + same PolicyArtifact + same evaluatorVersion -> same PolicyDecision set"
  D2EventDeterminism* =
    "same decision set -> same canonical ClassificationEvent set -> same eventRoot"
  D3ProjectionDeterminism* =
    "same committed history + same ProjectionRequest.projectionVersion -> same universeDigest"
  D4CanonicalHistoryDeterminism* =
    "same logical history -> same canonical commit chain (digest/sequence/parent)"
