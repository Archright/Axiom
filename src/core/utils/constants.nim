import core/trusted/layer_declaration
axiomLayer "domain"
import generated/build_env
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

# SSOT for all cross-cutting constants.
# Timeout values, resource limits, and schema keys live here.

const
  # ── Timeouts (milliseconds) ─────────────────────────────────────────────
  defaultAxiomProofTimeoutMs* = 30_000
  proofAttemptHardTimeoutMs* = 120_000
  leanstralTimeoutMs* = 30_000  ## Wave D: increased from 15s for large functions

  ## ACI (Axiom Complexity Index) thresholds for adaptive timeout.
  aciSimpleMax* = 9     ## ACI <= 9: simple, 10s timeout
  aciMediumMax* = 29    ## ACI 10-29: medium, 30s timeout
  aciComplexMax* = 69   ## ACI 30-69: complex, 60s timeout
                        ## ACI >= 70: critical, 120s timeout or pipeline block
  aciCriticalThreshold* = 70  ## Functions with ACI >= this are blocked from pipeline

  ## SOLID coupling threshold for SRP violation detection.
  srpCouplingThreshold* = 8  ## >8 unique external symbols → bcHighCoupling
  leanFieldParseWindow* = 96  ## max chars to scan when parsing Lean property field names (the_judge_lean.nim)
  minDynamicTimeoutMs* = 5_000
  maxDynamicTimeoutMs* = 120_000
  resourceSemaphoreTimeoutMs* = 30_000
  orchestrationWallClockTimeoutMs* = 600_000
  parallelDepthWallClockTimeoutMs* = 300_000
  processKillGracePeriodMs* = 2_000

  ## ── Fuel budget (deterministic, CPU-independent resource limiter) ─────
  DefaultOrchestratorFuel* = 1000  ## Deterministic fuel budget for orchestrator
  FuelPerDepthLevel* = 50          ## Fuel consumed per depth level processed

  ## Default solver command for Z3 FFI / subprocess fallback ────────────
  DefaultSolverCommand* = "z3"

  ## Z3 deterministic resource limit (DEBT-NEW-003) ──────────────────────
  ## rlimit = timeoutMs * multiplier. Prevents non-deterministic timeout
  ## behavior under varying CPU load. Tunable — start with 1000 and adjust
  ## based on observed query complexity distribution.
  z3RlimitMultiplier* = 1000

  ## Network / inspector ─────────────────────────────────────────────────
  ## Default localhost port for the trace inspector HTTP server.
  traceInspectorPort* = 12345

  ## Engine version hash for auto-invalidation of stale quarantine records.
  ## Resolved at compile time from generated/build_env.
  AxiomEngineVersionHash* = "v0.5.0-dev-" & BuildEnvGitHash[0..6]

  ## Schema keys (AxiomSession v1 & proof artifacts) ─────────────────────
  ## All JSON keys used in AxiomSession, ProofArtifact, and ASI report documents.
  schemaVersionKey* = "schemaVersion"
  sessionIdKey* = "sessionId"
  messagesKey* = "messages"
  axiomSessionV1* = "axiom.session.v1"
  ## v1 report document schema identity (productization_contract.md §7 — Phase 5
  ## freeze). Consumers MUST check this before parsing the report document;
  ## a mismatched value means the state was produced by an incompatible build.
  axiomReportSchemaVersion* = "axiom.report.v1"
  ## Cross-path skReport reproduction comparison (productization_contract.md §6c)
  ## — the versioned comparison record and its declared per-side identity bundle.
  axiomSkReportComparisonSchemaVersion* = "axiom.skreport-comparison.v2"
  axiomSkReportIdentitySchemaVersion* = "axiom.skreport-identity.v2"
  ## §6c v2 rejection skeleton marker: the lane hashes the rejection reason
  ## with the recorded offending path replaced by THIS constant, and the
  ## §6c comparison recomputes the same substitution — the only mechanical
  ## promotion path for a reason difference (single definition).
  axiomSkReportSkeletonMarker* = "<offending-path>"
  ## §6c v2 certified rejection leaf position: the ONLY reason leaf whose
  ## differing pair the promotion rule may bind (contract §6c rule 3 — "그 잎
  ## 쌍이 양측 targets[0].reason이고"). The lane records this exact path in
  ## binding.rejection.reasonLeaf and the comparison refuses any promotion
  ## whose differing pair does not sit at this position on BOTH sides with
  ## both records agreeing (audit F3 — position incoherence fails closed).
  axiomSkReportRejectionReasonLeaf* = "targets[0].reason"
  statusKey* = "status"
  labelKey* = "label"
  nodeIdKey* = "nodeId"
  modulePathKey* = "modulePath"
  functionNameKey* = "functionName"
  targetKey* = "target"
  sourceRootKey* = "sourceRoot"
  timestampKey* = "timestamp"
  reasonKey* = "reason"
  totalNodesKey* = "totalNodes"
  totalSourceFunctionsKey* = "totalSourceFunctions"
  attemptedNodesKey* = "attemptedNodes"
  verifiedKey* = "verified"
  counterExamplesKey* = "counterExamples"
  vacuousContradictionsKey* = "vacuousContradictions"
  timedOutKey* = "timedOut"
  unattemptedKey* = "unattempted"
  totalWallTimeMsKey* = "totalWallTimeMs"
  cpuEfficiencyKey* = "cpuEfficiency"
  cacheHitCountKey* = "cacheHitCount"
  reproofRequiredKey* = "reproofRequired"
  dependencyDepthKey* = "dependencyDepth"
  impactIndexKey* = "impactIndex"
  premiseCountKey* = "premiseCount"
  shortcutStateKey* = "shortcutState"
  vkdFixed4Key* = "vkdFixed4"
  asiWeightedFixed4Key* = "asiWeightedFixed4"
  asiScanFixed4Key* = "asiScanFixed4"
  verificationVerdictKey* = "verificationVerdict"
  fingerprintsKey* = "fingerprints"
  evolutionReasoningKey* = "evolutionReasoning"
  traceReportKey* = "traceReport"
  pocSnippetKey* = "pocSnippet"
  translationKey* = "translation"
  inferredSpecKey* = "inferredSpec"
  proofReplayKey* = "proofReplay"
  operationalSemanticsKey* = "operationalSemantics"
  refinementKey* = "refinement"
  terminationKey* = "termination"
  initialScanKey* = "initialScan"
  finalScanKey* = "finalScan"
  healingRoundsKey* = "healingRounds"
  evolutionKey* = "evolution"
  certifiedAtKey* = "certifiedAt"
  tacticsKey* = "tactics"
  theoremKey* = "theorem"
  theoremNameKey* = "theoremName"
  currentFingerprintKey* = "currentFingerprint"
  trustedKey* = "trusted"
  retryCountKey* = "retryCount"
  entriesKey* = "entries"
  remediationHintKey* = "remediationHint"
  strategyKey* = "strategy"
  bottleneckLogKey* = "bottleneckLog"
  causesKey* = "causes"
  evidenceLogJsonKey* = "evidenceLogJson"

  ## File system paths — SSOT for project-wide directory paths.
  ## NOTE: logs/* paths are intentionally excluded here per Architecture Gate
  ## (use logs/audit/stream.jsonl or content-addressed naming). Modules that
  ## need logs/ paths define them locally via their impure module exemption.
  ## The canonical runtime vault is .axiom/vault (ephemeral, gitignored).
  ## Stable certs (src/verification/certificates) are git-ignored dev artifacts.
  CanonicalVaultDir* = ".axiom/vault"
  defaultCertDir* = ".axiom/vault"
    ## Canonical runtime vault (.axiom/vault).

  perfectAsi* = "1.0000"
    ## ASI threshold for a perfect integrity score (4 decimal places).

  fingerprintMismatchStaleReason* = "fingerprint mismatch — auto-detected stale"
    ## SSOT reason key for auto-detected stale fingerprint mismatches.

  ## Engine topology salt — version-locked cache invalidation ─────────────
  PipelineVersionTag* = "v3"
    ## Bumped on any pipeline architecture change that invalidates cached results.
  AntiVacuityGateRevision* = 2
    ## Revision counter for the anti-vacuity gate; bump when gate logic changes.

func computeEngineTopologySalt*(z3Version, leanVersion, gitHash: string): string {.noSideEffect.} =
  ## Platform-independent cache salt: no $hash(), explicit string concatenation only.
  PipelineVersionTag & "|" & $AntiVacuityGateRevision & "|" &
    z3Version & "|" & leanVersion & "|" & gitHash

{.pop.}

{.pop.}
