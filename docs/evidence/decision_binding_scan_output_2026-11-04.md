# Decision Binding 스캔 출력 산출물 — 2026-11-04

> **본 문서의 지위**: `docs/evidence/decision_binding_escalation_survey_2026-11-04.md`(본 조사 본문)의
> 기계 산출물 첨부다. 내용은 조사 실행 시의 원문 그대로(verbatim)다 — 요약·편집 없음.
> 실행 환경: throwaway worktree `/tmp/dbwarn_wt` = canonical main `2f9c21693b401fb040991561b820718b9be0046d`
> (클린 트리, src/·config 무수정). 출력 내 절대경로 `/tmp/dbwarn_wt/...`는 해당 worktree 루트를 가리킨다.
> 본문 문서의 §2(조사 방법)에 실행 명령 원문이 있다.

## A. `bin/decision_binding_checker --escalation-threshold 30` (관측 워닝의 재현, exit 0)

- 1~2행: waiver 로드(259건)와 위반 파일 수. `Found 50 violation(s)`의 단위는 **파일**이다 (본문 §3).
- 3행 이하 `  ` 들여쓰기 213행 = 위반 **함수** 목록(파일:라인 포함).
- 마지막 행: 관측된 워닝과 동일한 형식의 WARN(본문 §1).

```
[decision-binding] Loaded 259 active waiver(s) from decision_binding.waiver.json
[decision-binding] Found 50 violation(s)
  parsePropositionsSchema (/tmp/dbwarn_wt/src/cli/proposition_intake.nim:252) returns Result/Option without axiomDecision
  loadEvidenceRecordForRegister (/tmp/dbwarn_wt/src/cli/cert_cli.nim:627) returns Result/Option without axiomDecision
  persistRegisteredSubject (/tmp/dbwarn_wt/src/cli/cert_cli.nim:675) returns Result/Option without axiomDecision
  ledgerHasSubjectCert (/tmp/dbwarn_wt/src/cli/cert_cli.nim:820) returns Result/Option without axiomDecision
  ledgerRecordConsistentWith (/tmp/dbwarn_wt/src/cli/cert_cli.nim:1220) returns Result/Option without axiomDecision
  validateCoutOverlayNode (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:1234) returns Result/Option without axiomDecision
  validateCoutOverlayNode (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:1259) returns Result/Option without axiomDecision
  validateTomlD2AgentOverlayNode (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:1538) returns Result/Option without axiomDecision
  validateTomlD2AgentOverlayNode (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:1558) returns Result/Option without axiomDecision
  validateSidecarOverlayNode (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:2472) returns Result/Option without axiomDecision
  loadNimSidecarOverlayDomain (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:2479) returns Result/Option without axiomDecision
  validateSidecarOverlayNode (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:2494) returns Result/Option without axiomDecision
  capabilityAdapterFor (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:4481) returns Result/Option without axiomDecision
  parseTrustSurfaceJson (/tmp/dbwarn_wt/src/cli/merge_cli.nim:754) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  rotationAllowlistOk (/tmp/dbwarn_wt/src/cli/merge_cli.nim:803) returns Result/Option without axiomDecision
  trustSurfaceOutcome (/tmp/dbwarn_wt/src/cli/merge_cli.nim:1200) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  MergeAdmissible (/tmp/dbwarn_wt/src/cli/merge_cli.nim:1233) multiple returns without axiomDecision
  checkedStr (/tmp/dbwarn_wt/src/cli/merge_cli.nim:1562) multiple returns without axiomDecision
  parseLayerPairRegistry (/tmp/dbwarn_wt/src/cli/merge_cli.nim:1760) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  loadTrustSurface (/tmp/dbwarn_wt/src/cli/merge_cli.nim:1860) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  collectCertificateContinuityFacts (/tmp/dbwarn_wt/src/cli/merge_cli.nim:1963) returns Result/Option without axiomDecision
  parseMergeSuccess (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2189) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  requestGitHubPut (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2205) returns Result/Option without axiomDecision
  performMerge (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2238) returns Result/Option without axiomDecision
  observePullState (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2282) returns Result/Option without axiomDecision
  resolveMergeShapeApi (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2351) returns Result/Option without axiomDecision
  resolveMergeShapeLocal (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2382) returns Result/Option without axiomDecision
  loadLedgerCertFor (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2420) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  scanLedgerContinuityCertNode (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2568) returns Result/Option without axiomDecision
  collectCertificateContinuityFacts (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2632) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  parseActiveKernelSymbols (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2680) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  vaultManifestIndex (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2705) returns Result/Option without axiomDecision
  safeSpecRelPath (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:318) multiple returns without axiomDecision
  parseFindingEvidence (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:397) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  selectDisplayBlock (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:439) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  selectReportableUnits (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:453) returns Result/Option without axiomDecision
  evalLinearRhs (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:531) returns Result/Option without axiomDecision
  evalClauseValue (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:555) returns Result/Option without axiomDecision
  classifyGhOutcome (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:784) multiple returns without axiomDecision
  parseIssueView (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:878) returns Result/Option without axiomDecision
  parseIssueRefList (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:893) returns Result/Option without axiomDecision
  decodeGhContentsJson (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:907) returns Result/Option without axiomDecision
  receiptFromJson (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:1144) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  parseUpstreamFlags (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:1281) returns Result/Option without axiomDecision
  loadSpecOverlay (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:1387) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  loadReceipt (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:1403) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  saveReceiptAtomic (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:1418) returns Result/Option without axiomDecision
  verifyCertBinding (/tmp/dbwarn_wt/src/cli/landing_cli.nim:106) multiple returns without axiomDecision
  fetchPrHead (/tmp/dbwarn_wt/src/cli/landing_cli.nim:150) returns Result/Option without axiomDecision
  compareStatus (/tmp/dbwarn_wt/src/cli/landing_cli.nim:167) returns Result/Option without axiomDecision
  validateSubjectPinObject (/tmp/dbwarn_wt/src/cli/external_subject_registry.nim:227) returns Result/Option without axiomDecision
  validateOwnershipObject (/tmp/dbwarn_wt/src/cli/external_subject_registry.nim:254) returns Result/Option without axiomDecision
  fromJsonResult (/tmp/dbwarn_wt/src/core/types/request_result.nim:119) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  changeDescriptorFromJson (/tmp/dbwarn_wt/src/core/types/candidate_identity.nim:204) returns Result/Option without axiomDecision
  candidateStateIdentityFromJson (/tmp/dbwarn_wt/src/core/types/candidate_identity.nim:211) returns Result/Option without axiomDecision
  candidateProvenanceFromJson (/tmp/dbwarn_wt/src/core/types/candidate_identity.nim:218) returns Result/Option without axiomDecision
  verificationContextIdentityFromJson (/tmp/dbwarn_wt/src/core/types/candidate_identity.nim:233) returns Result/Option without axiomDecision
  candidateEvidenceDigestFromJson (/tmp/dbwarn_wt/src/core/types/candidate_identity.nim:242) returns Result/Option without axiomDecision
  materializedCandidateFromJson (/tmp/dbwarn_wt/src/core/types/candidate_identity.nim:251) returns Result/Option without axiomDecision
  materializationRecordFromJson (/tmp/dbwarn_wt/src/core/types/candidate_identity.nim:263) returns Result/Option without axiomDecision
  fromJson (/tmp/dbwarn_wt/src/core/types/execution_plan.nim:66) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  fromJson (/tmp/dbwarn_wt/src/core/types/request_id.nim:32) returns Result/Option without axiomDecision
  countCallDepth (/tmp/dbwarn_wt/src/core/diagnostics/pattern_guard.nim:247) multiple returns without axiomDecision
  commonAncestorDir (/tmp/dbwarn_wt/src/core/gate/trust_commit_scope_scan.nim:268) multiple returns without axiomDecision
  parseDerivedSet (/tmp/dbwarn_wt/src/core/policy/rotation_closure_facts.nim:86) returns Result/Option without axiomDecision
  pinClosureLineSet (/tmp/dbwarn_wt/src/core/policy/rotation_closure_facts.nim:102) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  verifyRatchetDowngradeSignature (/tmp/dbwarn_wt/src/core/trusted/ratchet_authority.nim:57) multiple returns without axiomDecision
  validateClaimOwnership (/tmp/dbwarn_wt/src/core/trusted/bug_attribution_grounds.nim:116) returns Result/Option without axiomDecision
  validateGroundsFile (/tmp/dbwarn_wt/src/core/trusted/bug_attribution_grounds.nim:378) returns Result/Option without axiomDecision
  containsU64Lit (/tmp/dbwarn_wt/src/core/trusted/private/ir_to_smt_chunk2.nim:36) multiple returns without axiomDecision
  explicitSpecFromOverlay (/tmp/dbwarn_wt/src/core/trusted/specification_artifact.nim:68) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  measuredBinaryDigest (/tmp/dbwarn_wt/src/verification/obligation/measured_digests.nim:56) multiple returns without axiomDecision
  containsIdentToken (/tmp/dbwarn_wt/src/verification/obligation/canonical_verification.nim:388) multiple returns without axiomDecision
  measureSubjectGitRef (/tmp/dbwarn_wt/src/verification/obligation/canonical_verification.nim:869) multiple returns without axiomDecision
  measureCompositeCarrierTypename (/tmp/dbwarn_wt/src/verification/obligation/canonical_verification.nim:1190) multiple returns without axiomDecision
  rejectionToken (/tmp/dbwarn_wt/src/verification/obligation/candidate_eligibility.nim:97) returns Result/Option without axiomDecision
  canonicalizeEnvValue (/tmp/dbwarn_wt/src/verification/obligation/identity.nim:53) multiple returns without axiomDecision
  rustTemplateSkeleton (/tmp/dbwarn_wt/src/verification/rust_obligation_render.nim:111) multiple returns without axiomDecision
  rustExtractorIdentityDigest (/tmp/dbwarn_wt/src/verification/rust_obligation_render.nim:674) multiple returns without axiomDecision
  loadCASEntryByKey (/tmp/dbwarn_wt/src/verification/canonical_cache.nim:149) returns Result/Option without axiomDecision
  parseJudgmentSubject (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:358) returns Result/Option without axiomDecision
  collectChainedDigest (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:531) returns Result/Option without axiomDecision
  deriveSubjectTreeClosure (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:563) returns Result/Option without axiomDecision
  collectTestSourceClosure (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:583) returns Result/Option without axiomDecision
  collectGoldenFixturesDigest (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:599) returns Result/Option without axiomDecision
  subjectSourceClosure (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:661) returns Result/Option without axiomDecision
  subjectFixturesDigest (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:675) returns Result/Option without axiomDecision
  collectRecipeDigest (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:689) returns Result/Option without axiomDecision
  compilerPinsDigest (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:695) returns Result/Option without axiomDecision
  collectToolchainBundleDigest (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:707) returns Result/Option without axiomDecision
  collectJudgmentClosure (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:806) returns Result/Option without axiomDecision
  validateS1aJudgmentPayloadNode (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:944) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  validateProofIntegrityPayloadNode (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1065) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  validateD2GoldenPayloadNode (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1122) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  validateD2PersistPayloadNode (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1185) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  validateJudgmentPayloadNode (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1235) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  writeJudgmentEvidenceFile (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1279) returns Result/Option without axiomDecision
  parseJudgmentEvidenceFile (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1305) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  writeSubjectEvidenceFile (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1411) returns Result/Option without axiomDecision
  writeProofIntegrityJudgmentEvidenceFile (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1431) returns Result/Option without axiomDecision
  buildJudgmentRecord (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1723) returns Result/Option without axiomDecision
  validateJudgmentWitnessNode (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1779) multiple returns without axiomDecision
  judgmentRootRecordMarkerShape (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1813) multiple returns without axiomDecision
  writeJudgmentDecisionFile (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1859) returns Result/Option without axiomDecision
  verifyJudgmentReuse (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1909) multiple returns without axiomDecision
  runJudgmentAttestBranchForSubject (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1954) returns Result/Option without axiomDecision
  runJudgmentAttestBranch (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:2117) returns Result/Option without axiomDecision
  parseExecutionVerdict (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:2184) returns Result/Option without axiomDecision
  validateJudgmentExecutionRecord (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:2244) multiple returns without axiomDecision
  appendExecutionRecord (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:2327) returns Result/Option without axiomDecision
  validateExtractionJobRecord (/tmp/dbwarn_wt/src/verification/extraction_provenance.nim:164) multiple returns without axiomDecision
  jobRecordFromJson (/tmp/dbwarn_wt/src/verification/extraction_provenance.nim:224) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  extractionJobRecordFromPayload (/tmp/dbwarn_wt/src/verification/extraction_provenance.nim:262) returns Result/Option without axiomDecision
  extractionJobKey (/tmp/dbwarn_wt/src/verification/extraction_provenance.nim:316) returns Result/Option without axiomDecision
  fileSha256Hex (/tmp/dbwarn_wt/src/verification/extraction_provenance.nim:330) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  llbcFileDigest (/tmp/dbwarn_wt/src/verification/extraction_provenance.nim:344) returns Result/Option without axiomDecision
  ledgerCertId (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:77) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  shaFromObject (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:96) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  shaFromNode (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:105) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  ledgerScanIndexFromTree (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:114) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  listEntriesFromTree (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:152) returns Result/Option without axiomDecision
  decodeBlobContent (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:164) returns Result/Option without axiomDecision
  blobEntrySha (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:190) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  fetchTipTree (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:217) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  listLedgerCertIds (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:260) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  listRefEntryNames (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:279) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  openLedgerScanIndex (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:316) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  downloadLedgerCertificateAtBlob (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:370) returns Result/Option without axiomDecision
  downloadLedgerCertificate (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:381) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  validateEvidenceRecord (/tmp/dbwarn_wt/src/verification/evidence_ledger.nim:167) multiple returns without axiomDecision
  evidenceRecordFromJson (/tmp/dbwarn_wt/src/verification/evidence_ledger.nim:200) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  evidenceKeysFromNames (/tmp/dbwarn_wt/src/verification/evidence_ledger.nim:243) returns Result/Option without axiomDecision
  blobShaForKey (/tmp/dbwarn_wt/src/verification/evidence_ledger.nim:258) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  decodeEvidenceBlob (/tmp/dbwarn_wt/src/verification/evidence_ledger.nim:281) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  parseEvidenceRecord (/tmp/dbwarn_wt/src/verification/evidence_ledger.nim:294) returns Result/Option without axiomDecision
  isOid40 (/tmp/dbwarn_wt/src/verification/admission_artifact.nim:87) multiple returns without axiomDecision
  mintAdmissionPayload (/tmp/dbwarn_wt/src/verification/admission_artifact.nim:96) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  decodeExecutionIdentityClaims (/tmp/dbwarn_wt/src/verification/admission_artifact.nim:140) returns Result/Option without axiomDecision
  admissionPayloadDigest (/tmp/dbwarn_wt/src/verification/admission_artifact.nim:202) returns Result/Option without axiomDecision
  artifactPayloadFromEnvelope (/tmp/dbwarn_wt/src/verification/admission_artifact.nim:216) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  validateAttestationInputs (/tmp/dbwarn_wt/src/verification/attestation_orchestrator.nim:266) multiple returns without axiomDecision
  inputsFromJson (/tmp/dbwarn_wt/src/verification/attestation_orchestrator.nim:299) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  parseAttestationEvidenceText (/tmp/dbwarn_wt/src/verification/attestation_orchestrator.nim:350) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  reuseIrHashFromPayload (/tmp/dbwarn_wt/src/verification/attestation_orchestrator.nim:562) returns Result/Option without axiomDecision
  isEarlyReturnIfWire (/tmp/dbwarn_wt/src/verification/ast_wire.nim:173) multiple returns without axiomDecision
  provenanceValidationError (/tmp/dbwarn_wt/src/verification/attestation_witness.nim:177) multiple returns without axiomDecision
  semanticValidationError (/tmp/dbwarn_wt/src/verification/attestation_witness.nim:197) multiple returns without axiomDecision
  parseWitnessBundleText (/tmp/dbwarn_wt/src/verification/attestation_witness.nim:428) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  signWitness (/tmp/dbwarn_wt/src/verification/attestation_witness.nim:490) returns Result/Option without axiomDecision
  computeTestClosureDigest (/tmp/dbwarn_wt/src/verification/verification_query_engine.nim:98) returns Result/Option without axiomDecision
  computeBaselineDigest (/tmp/dbwarn_wt/src/verification/verification_query_engine.nim:129) returns Result/Option without axiomDecision
  computeLockDigest (/tmp/dbwarn_wt/src/verification/verification_query_engine.nim:139) returns Result/Option without axiomDecision
  computePolicyDigest (/tmp/dbwarn_wt/src/verification/verification_query_engine.nim:149) returns Result/Option without axiomDecision
  dependencyDomain (/tmp/dbwarn_wt/src/verification/producer_identity.nim:73) multiple returns without axiomDecision
  verifyContinuity (/tmp/dbwarn_wt/src/verification/continuity_check.nim:76) multiple returns without axiomDecision
  verifyContinuityCertDetailed (/tmp/dbwarn_wt/src/verification/continuity_check.nim:132) multiple returns without axiomDecision
  irBytesEqual (/tmp/dbwarn_wt/src/verification/extraction_agreement.nim:81) multiple returns without axiomDecision
  normalizeLeanForDifferential (/tmp/dbwarn_wt/src/verification/renderer_differential.nim:278) multiple returns without axiomDecision
  parseSubjectText (/tmp/dbwarn_wt/src/verification/subject_store.nim:43) returns Result/Option without axiomDecision
  saveSubject (/tmp/dbwarn_wt/src/verification/subject_store.nim:54) returns Result/Option without axiomDecision
  loadSubject (/tmp/dbwarn_wt/src/verification/subject_store.nim:74) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  listSubjects (/tmp/dbwarn_wt/src/verification/subject_store.nim:87) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  findSubjectsByHeadSha (/tmp/dbwarn_wt/src/verification/subject_store.nim:106) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  isFullCertClaim (/tmp/dbwarn_wt/src/verification/cert_reconcile.nim:865) multiple returns without axiomDecision
  parseNimblePkgDirName (/tmp/dbwarn_wt/src/verification/counterexample_replay.nim:246) returns Result/Option without axiomDecision
  versionRank (/tmp/dbwarn_wt/src/verification/counterexample_replay.nim:264) returns Result/Option without axiomDecision
  newestPkgDir (/tmp/dbwarn_wt/src/verification/counterexample_replay.nim:309) returns Result/Option without axiomDecision
  evalConcreteBinOp (/tmp/dbwarn_wt/src/verification/counterexample_replay.nim:336) returns Result/Option without axiomDecision
  evalConcreteUnaryOp (/tmp/dbwarn_wt/src/verification/counterexample_replay.nim:390) returns Result/Option without axiomDecision
  evaluatePostconditions (/tmp/dbwarn_wt/src/verification/counterexample_replay.nim:475) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  parseConcreteLiteral (/tmp/dbwarn_wt/src/verification/counterexample_replay.nim:488) returns Result/Option without axiomDecision
  decideReplayVerdict (/tmp/dbwarn_wt/src/verification/counterexample_replay.nim:523) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  ceReplayModulePath (/tmp/dbwarn_wt/src/verification/counterexample_replay.nim:778) multiple returns without axiomDecision
  subjectTreeNeedsDepRoots (/tmp/dbwarn_wt/src/verification/counterexample_replay.nim:913) multiple returns without axiomDecision
  isCertifiedNoEffectPath (/tmp/dbwarn_wt/src/verification/semantic_set_derivation.nim:238) multiple returns without axiomDecision
  parseLsTreeZ (/tmp/dbwarn_wt/src/verification/semantic_set_derivation.nim:384) returns Result/Option without axiomDecision
  isHexLen (/tmp/dbwarn_wt/src/verification/semantic_set_derivation.nim:465) multiple returns without axiomDecision
  runGitOrErr (/tmp/dbwarn_wt/src/verification/semantic_set_derivation.nim:473) returns Result/Option without axiomDecision
  probeTreeResolvable (/tmp/dbwarn_wt/src/verification/semantic_set_derivation.nim:510) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  listTreeUniverse (/tmp/dbwarn_wt/src/verification/semantic_set_derivation.nim:524) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  verifyPartition (/tmp/dbwarn_wt/src/verification/semantic_set_derivation.nim:546) returns Result/Option without axiomDecision
  probeCharonVersion (/tmp/dbwarn_wt/src/verification/charon_runner.nim:186) multiple returns without axiomDecision
  runPinnedCharonCargo (/tmp/dbwarn_wt/src/verification/charon_runner.nim:215) multiple returns without axiomDecision
  lowerPostconditionModel (/tmp/dbwarn_wt/src/verification/batch_uap/ir_pipeline_runner.nim:443) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  isHexOfLen (/tmp/dbwarn_wt/src/verification/verification_subject.nim:76) multiple returns without axiomDecision
  isValidIso8601Zulu (/tmp/dbwarn_wt/src/verification/verification_subject.nim:84) multiple returns without axiomDecision
  subjectFromJson (/tmp/dbwarn_wt/src/verification/verification_subject.nim:202) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  isAxiomAllowed (/tmp/dbwarn_wt/src/verification/kernel_reexecution.nim:61) multiple returns without axiomDecision
  evaluateObservedAxioms (/tmp/dbwarn_wt/src/verification/kernel_reexecution.nim:138) multiple returns without axiomDecision
  z3ResultVerdict (/tmp/dbwarn_wt/src/verification/kernel_reexecution.nim:169) multiple returns without axiomDecision
  loadCertJsonForReexecution (/tmp/dbwarn_wt/src/verification/kernel_reexecution.nim:203) returns Result/Option without axiomDecision
  reexecuteLean (/tmp/dbwarn_wt/src/verification/kernel_reexecution.nim:259) multiple returns without axiomDecision
  reexecuteZ3 (/tmp/dbwarn_wt/src/verification/kernel_reexecution.nim:316) multiple returns without axiomDecision
  subjectCertJournalBind (/tmp/dbwarn_wt/src/verification/subject_continuity_writer.nim:226) returns Result/Option without axiomDecision
  subjectCertSignAndWrite (/tmp/dbwarn_wt/src/verification/subject_continuity_writer.nim:234) returns Result/Option without axiomDecision
  readBlobs (/tmp/dbwarn_wt/src/verification/tested_tree_closure.nim:295) returns Result/Option without axiomDecision
  readBlob (/tmp/dbwarn_wt/src/verification/tested_tree_closure.nim:357) returns Result/Option without axiomDecision
  lockEntryName (/tmp/dbwarn_wt/src/verification/tested_tree_closure.nim:394) multiple returns without axiomDecision
  validateVerifierIdentityInputs (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:267) multiple returns without axiomDecision
  validateEvidenceKeyInputs (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:328) multiple returns without axiomDecision
  collectChainedFileDigest (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:365) returns Result/Option without axiomDecision
  collectZ3Pin (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:389) returns Result/Option without axiomDecision
  collectLeanPin (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:404) returns Result/Option without axiomDecision
  collectRecipeDigest (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:421) returns Result/Option without axiomDecision
  collectZ3ChecksumPolicyDigest (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:428) returns Result/Option without axiomDecision
  collectEvidenceDraftDigest (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:434) returns Result/Option without axiomDecision
  collectScopeDigest (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:441) returns Result/Option without axiomDecision
  collectPolicyDigest (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:448) returns Result/Option without axiomDecision
  collectArtifactDigests (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:457) returns Result/Option without axiomDecision
  collectVerifierIdentityInputs (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:473) returns Result/Option without axiomDecision
  markStrictGeneration (/tmp/dbwarn_wt/src/infrastructure/evidence_artifact_io.nim:264) multiple returns without axiomDecision
  saveCompletenessBinding (/tmp/dbwarn_wt/src/infrastructure/evidence_artifact_io.nim:392) multiple returns without axiomDecision
  executePlan (/tmp/dbwarn_wt/src/engine/plan_executor.nim:64) returns Result/Option without axiomDecision
[decision-binding] WARN: 50 function(s) missing {.axiomDecision.} pragma — escalation threshold 30 days not yet reached
```

## B. `bin/decision_binding_checker --escalation-threshold 57` (FAIL 분기 노출, exit 1)

- 만료 2026-12-31인 waiver 259건 전부가 "EXPIRING SOON"으로 출력되며 잔여 일수 **56일**(2026-11-04 10:39 KST 기준)이 기계 계산되어 찍힌다.
- 최종 행이 FAIL(exit 1) — 임계값 미만 진입 시의 에스컬레이션 분기 원문이다. 본문 §5의 FAIL 진입일(2026-12-01) 산출 근거.

```
[decision-binding] Loaded 259 active waiver(s) from decision_binding.waiver.json
[decision-binding] Found 50 violation(s)
  parsePropositionsSchema (/tmp/dbwarn_wt/src/cli/proposition_intake.nim:252) returns Result/Option without axiomDecision
  loadEvidenceRecordForRegister (/tmp/dbwarn_wt/src/cli/cert_cli.nim:627) returns Result/Option without axiomDecision
  persistRegisteredSubject (/tmp/dbwarn_wt/src/cli/cert_cli.nim:675) returns Result/Option without axiomDecision
  ledgerHasSubjectCert (/tmp/dbwarn_wt/src/cli/cert_cli.nim:820) returns Result/Option without axiomDecision
  ledgerRecordConsistentWith (/tmp/dbwarn_wt/src/cli/cert_cli.nim:1220) returns Result/Option without axiomDecision
  validateCoutOverlayNode (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:1234) returns Result/Option without axiomDecision
  validateCoutOverlayNode (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:1259) returns Result/Option without axiomDecision
  validateTomlD2AgentOverlayNode (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:1538) returns Result/Option without axiomDecision
  validateTomlD2AgentOverlayNode (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:1558) returns Result/Option without axiomDecision
  validateSidecarOverlayNode (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:2472) returns Result/Option without axiomDecision
  loadNimSidecarOverlayDomain (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:2479) returns Result/Option without axiomDecision
  validateSidecarOverlayNode (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:2494) returns Result/Option without axiomDecision
  capabilityAdapterFor (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:4481) returns Result/Option without axiomDecision
  parseTrustSurfaceJson (/tmp/dbwarn_wt/src/cli/merge_cli.nim:754) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  rotationAllowlistOk (/tmp/dbwarn_wt/src/cli/merge_cli.nim:803) returns Result/Option without axiomDecision
  trustSurfaceOutcome (/tmp/dbwarn_wt/src/cli/merge_cli.nim:1200) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  MergeAdmissible (/tmp/dbwarn_wt/src/cli/merge_cli.nim:1233) multiple returns without axiomDecision
  checkedStr (/tmp/dbwarn_wt/src/cli/merge_cli.nim:1562) multiple returns without axiomDecision
  parseLayerPairRegistry (/tmp/dbwarn_wt/src/cli/merge_cli.nim:1760) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  loadTrustSurface (/tmp/dbwarn_wt/src/cli/merge_cli.nim:1860) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  collectCertificateContinuityFacts (/tmp/dbwarn_wt/src/cli/merge_cli.nim:1963) returns Result/Option without axiomDecision
  parseMergeSuccess (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2189) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  requestGitHubPut (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2205) returns Result/Option without axiomDecision
  performMerge (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2238) returns Result/Option without axiomDecision
  observePullState (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2282) returns Result/Option without axiomDecision
  resolveMergeShapeApi (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2351) returns Result/Option without axiomDecision
  resolveMergeShapeLocal (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2382) returns Result/Option without axiomDecision
  loadLedgerCertFor (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2420) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  scanLedgerContinuityCertNode (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2568) returns Result/Option without axiomDecision
  collectCertificateContinuityFacts (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2632) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  parseActiveKernelSymbols (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2680) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  vaultManifestIndex (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2705) returns Result/Option without axiomDecision
  safeSpecRelPath (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:318) multiple returns without axiomDecision
  parseFindingEvidence (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:397) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  selectDisplayBlock (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:439) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  selectReportableUnits (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:453) returns Result/Option without axiomDecision
  evalLinearRhs (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:531) returns Result/Option without axiomDecision
  evalClauseValue (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:555) returns Result/Option without axiomDecision
  classifyGhOutcome (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:784) multiple returns without axiomDecision
  parseIssueView (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:878) returns Result/Option without axiomDecision
  parseIssueRefList (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:893) returns Result/Option without axiomDecision
  decodeGhContentsJson (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:907) returns Result/Option without axiomDecision
  receiptFromJson (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:1144) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  parseUpstreamFlags (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:1281) returns Result/Option without axiomDecision
  loadSpecOverlay (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:1387) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  loadReceipt (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:1403) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  saveReceiptAtomic (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:1418) returns Result/Option without axiomDecision
  verifyCertBinding (/tmp/dbwarn_wt/src/cli/landing_cli.nim:106) multiple returns without axiomDecision
  fetchPrHead (/tmp/dbwarn_wt/src/cli/landing_cli.nim:150) returns Result/Option without axiomDecision
  compareStatus (/tmp/dbwarn_wt/src/cli/landing_cli.nim:167) returns Result/Option without axiomDecision
  validateSubjectPinObject (/tmp/dbwarn_wt/src/cli/external_subject_registry.nim:227) returns Result/Option without axiomDecision
  validateOwnershipObject (/tmp/dbwarn_wt/src/cli/external_subject_registry.nim:254) returns Result/Option without axiomDecision
  fromJsonResult (/tmp/dbwarn_wt/src/core/types/request_result.nim:119) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  changeDescriptorFromJson (/tmp/dbwarn_wt/src/core/types/candidate_identity.nim:204) returns Result/Option without axiomDecision
  candidateStateIdentityFromJson (/tmp/dbwarn_wt/src/core/types/candidate_identity.nim:211) returns Result/Option without axiomDecision
  candidateProvenanceFromJson (/tmp/dbwarn_wt/src/core/types/candidate_identity.nim:218) returns Result/Option without axiomDecision
  verificationContextIdentityFromJson (/tmp/dbwarn_wt/src/core/types/candidate_identity.nim:233) returns Result/Option without axiomDecision
  candidateEvidenceDigestFromJson (/tmp/dbwarn_wt/src/core/types/candidate_identity.nim:242) returns Result/Option without axiomDecision
  materializedCandidateFromJson (/tmp/dbwarn_wt/src/core/types/candidate_identity.nim:251) returns Result/Option without axiomDecision
  materializationRecordFromJson (/tmp/dbwarn_wt/src/core/types/candidate_identity.nim:263) returns Result/Option without axiomDecision
  fromJson (/tmp/dbwarn_wt/src/core/types/execution_plan.nim:66) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  fromJson (/tmp/dbwarn_wt/src/core/types/request_id.nim:32) returns Result/Option without axiomDecision
  countCallDepth (/tmp/dbwarn_wt/src/core/diagnostics/pattern_guard.nim:247) multiple returns without axiomDecision
  commonAncestorDir (/tmp/dbwarn_wt/src/core/gate/trust_commit_scope_scan.nim:268) multiple returns without axiomDecision
  parseDerivedSet (/tmp/dbwarn_wt/src/core/policy/rotation_closure_facts.nim:86) returns Result/Option without axiomDecision
  pinClosureLineSet (/tmp/dbwarn_wt/src/core/policy/rotation_closure_facts.nim:102) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  verifyRatchetDowngradeSignature (/tmp/dbwarn_wt/src/core/trusted/ratchet_authority.nim:57) multiple returns without axiomDecision
  validateClaimOwnership (/tmp/dbwarn_wt/src/core/trusted/bug_attribution_grounds.nim:116) returns Result/Option without axiomDecision
  validateGroundsFile (/tmp/dbwarn_wt/src/core/trusted/bug_attribution_grounds.nim:378) returns Result/Option without axiomDecision
  containsU64Lit (/tmp/dbwarn_wt/src/core/trusted/private/ir_to_smt_chunk2.nim:36) multiple returns without axiomDecision
  explicitSpecFromOverlay (/tmp/dbwarn_wt/src/core/trusted/specification_artifact.nim:68) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  measuredBinaryDigest (/tmp/dbwarn_wt/src/verification/obligation/measured_digests.nim:56) multiple returns without axiomDecision
  containsIdentToken (/tmp/dbwarn_wt/src/verification/obligation/canonical_verification.nim:388) multiple returns without axiomDecision
  measureSubjectGitRef (/tmp/dbwarn_wt/src/verification/obligation/canonical_verification.nim:869) multiple returns without axiomDecision
  measureCompositeCarrierTypename (/tmp/dbwarn_wt/src/verification/obligation/canonical_verification.nim:1190) multiple returns without axiomDecision
  rejectionToken (/tmp/dbwarn_wt/src/verification/obligation/candidate_eligibility.nim:97) returns Result/Option without axiomDecision
  canonicalizeEnvValue (/tmp/dbwarn_wt/src/verification/obligation/identity.nim:53) multiple returns without axiomDecision
  rustTemplateSkeleton (/tmp/dbwarn_wt/src/verification/rust_obligation_render.nim:111) multiple returns without axiomDecision
  rustExtractorIdentityDigest (/tmp/dbwarn_wt/src/verification/rust_obligation_render.nim:674) multiple returns without axiomDecision
  loadCASEntryByKey (/tmp/dbwarn_wt/src/verification/canonical_cache.nim:149) returns Result/Option without axiomDecision
  parseJudgmentSubject (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:358) returns Result/Option without axiomDecision
  collectChainedDigest (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:531) returns Result/Option without axiomDecision
  deriveSubjectTreeClosure (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:563) returns Result/Option without axiomDecision
  collectTestSourceClosure (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:583) returns Result/Option without axiomDecision
  collectGoldenFixturesDigest (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:599) returns Result/Option without axiomDecision
  subjectSourceClosure (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:661) returns Result/Option without axiomDecision
  subjectFixturesDigest (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:675) returns Result/Option without axiomDecision
  collectRecipeDigest (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:689) returns Result/Option without axiomDecision
  compilerPinsDigest (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:695) returns Result/Option without axiomDecision
  collectToolchainBundleDigest (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:707) returns Result/Option without axiomDecision
  collectJudgmentClosure (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:806) returns Result/Option without axiomDecision
  validateS1aJudgmentPayloadNode (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:944) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  validateProofIntegrityPayloadNode (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1065) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  validateD2GoldenPayloadNode (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1122) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  validateD2PersistPayloadNode (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1185) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  validateJudgmentPayloadNode (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1235) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  writeJudgmentEvidenceFile (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1279) returns Result/Option without axiomDecision
  parseJudgmentEvidenceFile (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1305) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  writeSubjectEvidenceFile (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1411) returns Result/Option without axiomDecision
  writeProofIntegrityJudgmentEvidenceFile (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1431) returns Result/Option without axiomDecision
  buildJudgmentRecord (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1723) returns Result/Option without axiomDecision
  validateJudgmentWitnessNode (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1779) multiple returns without axiomDecision
  judgmentRootRecordMarkerShape (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1813) multiple returns without axiomDecision
  writeJudgmentDecisionFile (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1859) returns Result/Option without axiomDecision
  verifyJudgmentReuse (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1909) multiple returns without axiomDecision
  runJudgmentAttestBranchForSubject (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1954) returns Result/Option without axiomDecision
  runJudgmentAttestBranch (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:2117) returns Result/Option without axiomDecision
  parseExecutionVerdict (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:2184) returns Result/Option without axiomDecision
  validateJudgmentExecutionRecord (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:2244) multiple returns without axiomDecision
  appendExecutionRecord (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:2327) returns Result/Option without axiomDecision
  validateExtractionJobRecord (/tmp/dbwarn_wt/src/verification/extraction_provenance.nim:164) multiple returns without axiomDecision
  jobRecordFromJson (/tmp/dbwarn_wt/src/verification/extraction_provenance.nim:224) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  extractionJobRecordFromPayload (/tmp/dbwarn_wt/src/verification/extraction_provenance.nim:262) returns Result/Option without axiomDecision
  extractionJobKey (/tmp/dbwarn_wt/src/verification/extraction_provenance.nim:316) returns Result/Option without axiomDecision
  fileSha256Hex (/tmp/dbwarn_wt/src/verification/extraction_provenance.nim:330) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  llbcFileDigest (/tmp/dbwarn_wt/src/verification/extraction_provenance.nim:344) returns Result/Option without axiomDecision
  ledgerCertId (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:77) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  shaFromObject (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:96) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  shaFromNode (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:105) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  ledgerScanIndexFromTree (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:114) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  listEntriesFromTree (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:152) returns Result/Option without axiomDecision
  decodeBlobContent (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:164) returns Result/Option without axiomDecision
  blobEntrySha (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:190) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  fetchTipTree (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:217) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  listLedgerCertIds (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:260) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  listRefEntryNames (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:279) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  openLedgerScanIndex (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:316) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  downloadLedgerCertificateAtBlob (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:370) returns Result/Option without axiomDecision
  downloadLedgerCertificate (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:381) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  validateEvidenceRecord (/tmp/dbwarn_wt/src/verification/evidence_ledger.nim:167) multiple returns without axiomDecision
  evidenceRecordFromJson (/tmp/dbwarn_wt/src/verification/evidence_ledger.nim:200) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  evidenceKeysFromNames (/tmp/dbwarn_wt/src/verification/evidence_ledger.nim:243) returns Result/Option without axiomDecision
  blobShaForKey (/tmp/dbwarn_wt/src/verification/evidence_ledger.nim:258) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  decodeEvidenceBlob (/tmp/dbwarn_wt/src/verification/evidence_ledger.nim:281) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  parseEvidenceRecord (/tmp/dbwarn_wt/src/verification/evidence_ledger.nim:294) returns Result/Option without axiomDecision
  isOid40 (/tmp/dbwarn_wt/src/verification/admission_artifact.nim:87) multiple returns without axiomDecision
  mintAdmissionPayload (/tmp/dbwarn_wt/src/verification/admission_artifact.nim:96) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  decodeExecutionIdentityClaims (/tmp/dbwarn_wt/src/verification/admission_artifact.nim:140) returns Result/Option without axiomDecision
  admissionPayloadDigest (/tmp/dbwarn_wt/src/verification/admission_artifact.nim:202) returns Result/Option without axiomDecision
  artifactPayloadFromEnvelope (/tmp/dbwarn_wt/src/verification/admission_artifact.nim:216) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  validateAttestationInputs (/tmp/dbwarn_wt/src/verification/attestation_orchestrator.nim:266) multiple returns without axiomDecision
  inputsFromJson (/tmp/dbwarn_wt/src/verification/attestation_orchestrator.nim:299) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  parseAttestationEvidenceText (/tmp/dbwarn_wt/src/verification/attestation_orchestrator.nim:350) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  reuseIrHashFromPayload (/tmp/dbwarn_wt/src/verification/attestation_orchestrator.nim:562) returns Result/Option without axiomDecision
  isEarlyReturnIfWire (/tmp/dbwarn_wt/src/verification/ast_wire.nim:173) multiple returns without axiomDecision
  provenanceValidationError (/tmp/dbwarn_wt/src/verification/attestation_witness.nim:177) multiple returns without axiomDecision
  semanticValidationError (/tmp/dbwarn_wt/src/verification/attestation_witness.nim:197) multiple returns without axiomDecision
  parseWitnessBundleText (/tmp/dbwarn_wt/src/verification/attestation_witness.nim:428) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  signWitness (/tmp/dbwarn_wt/src/verification/attestation_witness.nim:490) returns Result/Option without axiomDecision
  computeTestClosureDigest (/tmp/dbwarn_wt/src/verification/verification_query_engine.nim:98) returns Result/Option without axiomDecision
  computeBaselineDigest (/tmp/dbwarn_wt/src/verification/verification_query_engine.nim:129) returns Result/Option without axiomDecision
  computeLockDigest (/tmp/dbwarn_wt/src/verification/verification_query_engine.nim:139) returns Result/Option without axiomDecision
  computePolicyDigest (/tmp/dbwarn_wt/src/verification/verification_query_engine.nim:149) returns Result/Option without axiomDecision
  dependencyDomain (/tmp/dbwarn_wt/src/verification/producer_identity.nim:73) multiple returns without axiomDecision
  verifyContinuity (/tmp/dbwarn_wt/src/verification/continuity_check.nim:76) multiple returns without axiomDecision
  verifyContinuityCertDetailed (/tmp/dbwarn_wt/src/verification/continuity_check.nim:132) multiple returns without axiomDecision
  irBytesEqual (/tmp/dbwarn_wt/src/verification/extraction_agreement.nim:81) multiple returns without axiomDecision
  normalizeLeanForDifferential (/tmp/dbwarn_wt/src/verification/renderer_differential.nim:278) multiple returns without axiomDecision
  parseSubjectText (/tmp/dbwarn_wt/src/verification/subject_store.nim:43) returns Result/Option without axiomDecision
  saveSubject (/tmp/dbwarn_wt/src/verification/subject_store.nim:54) returns Result/Option without axiomDecision
  loadSubject (/tmp/dbwarn_wt/src/verification/subject_store.nim:74) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  listSubjects (/tmp/dbwarn_wt/src/verification/subject_store.nim:87) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  findSubjectsByHeadSha (/tmp/dbwarn_wt/src/verification/subject_store.nim:106) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  isFullCertClaim (/tmp/dbwarn_wt/src/verification/cert_reconcile.nim:865) multiple returns without axiomDecision
  parseNimblePkgDirName (/tmp/dbwarn_wt/src/verification/counterexample_replay.nim:246) returns Result/Option without axiomDecision
  versionRank (/tmp/dbwarn_wt/src/verification/counterexample_replay.nim:264) returns Result/Option without axiomDecision
  newestPkgDir (/tmp/dbwarn_wt/src/verification/counterexample_replay.nim:309) returns Result/Option without axiomDecision
  evalConcreteBinOp (/tmp/dbwarn_wt/src/verification/counterexample_replay.nim:336) returns Result/Option without axiomDecision
  evalConcreteUnaryOp (/tmp/dbwarn_wt/src/verification/counterexample_replay.nim:390) returns Result/Option without axiomDecision
  evaluatePostconditions (/tmp/dbwarn_wt/src/verification/counterexample_replay.nim:475) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  parseConcreteLiteral (/tmp/dbwarn_wt/src/verification/counterexample_replay.nim:488) returns Result/Option without axiomDecision
  decideReplayVerdict (/tmp/dbwarn_wt/src/verification/counterexample_replay.nim:523) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  ceReplayModulePath (/tmp/dbwarn_wt/src/verification/counterexample_replay.nim:778) multiple returns without axiomDecision
  subjectTreeNeedsDepRoots (/tmp/dbwarn_wt/src/verification/counterexample_replay.nim:913) multiple returns without axiomDecision
  isCertifiedNoEffectPath (/tmp/dbwarn_wt/src/verification/semantic_set_derivation.nim:238) multiple returns without axiomDecision
  parseLsTreeZ (/tmp/dbwarn_wt/src/verification/semantic_set_derivation.nim:384) returns Result/Option without axiomDecision
  isHexLen (/tmp/dbwarn_wt/src/verification/semantic_set_derivation.nim:465) multiple returns without axiomDecision
  runGitOrErr (/tmp/dbwarn_wt/src/verification/semantic_set_derivation.nim:473) returns Result/Option without axiomDecision
  probeTreeResolvable (/tmp/dbwarn_wt/src/verification/semantic_set_derivation.nim:510) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  listTreeUniverse (/tmp/dbwarn_wt/src/verification/semantic_set_derivation.nim:524) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  verifyPartition (/tmp/dbwarn_wt/src/verification/semantic_set_derivation.nim:546) returns Result/Option without axiomDecision
  probeCharonVersion (/tmp/dbwarn_wt/src/verification/charon_runner.nim:186) multiple returns without axiomDecision
  runPinnedCharonCargo (/tmp/dbwarn_wt/src/verification/charon_runner.nim:215) multiple returns without axiomDecision
  lowerPostconditionModel (/tmp/dbwarn_wt/src/verification/batch_uap/ir_pipeline_runner.nim:443) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  isHexOfLen (/tmp/dbwarn_wt/src/verification/verification_subject.nim:76) multiple returns without axiomDecision
  isValidIso8601Zulu (/tmp/dbwarn_wt/src/verification/verification_subject.nim:84) multiple returns without axiomDecision
  subjectFromJson (/tmp/dbwarn_wt/src/verification/verification_subject.nim:202) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  isAxiomAllowed (/tmp/dbwarn_wt/src/verification/kernel_reexecution.nim:61) multiple returns without axiomDecision
  evaluateObservedAxioms (/tmp/dbwarn_wt/src/verification/kernel_reexecution.nim:138) multiple returns without axiomDecision
  z3ResultVerdict (/tmp/dbwarn_wt/src/verification/kernel_reexecution.nim:169) multiple returns without axiomDecision
  loadCertJsonForReexecution (/tmp/dbwarn_wt/src/verification/kernel_reexecution.nim:203) returns Result/Option without axiomDecision
  reexecuteLean (/tmp/dbwarn_wt/src/verification/kernel_reexecution.nim:259) multiple returns without axiomDecision
  reexecuteZ3 (/tmp/dbwarn_wt/src/verification/kernel_reexecution.nim:316) multiple returns without axiomDecision
  subjectCertJournalBind (/tmp/dbwarn_wt/src/verification/subject_continuity_writer.nim:226) returns Result/Option without axiomDecision
  subjectCertSignAndWrite (/tmp/dbwarn_wt/src/verification/subject_continuity_writer.nim:234) returns Result/Option without axiomDecision
  readBlobs (/tmp/dbwarn_wt/src/verification/tested_tree_closure.nim:295) returns Result/Option without axiomDecision
  readBlob (/tmp/dbwarn_wt/src/verification/tested_tree_closure.nim:357) returns Result/Option without axiomDecision
  lockEntryName (/tmp/dbwarn_wt/src/verification/tested_tree_closure.nim:394) multiple returns without axiomDecision
  validateVerifierIdentityInputs (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:267) multiple returns without axiomDecision
  validateEvidenceKeyInputs (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:328) multiple returns without axiomDecision
  collectChainedFileDigest (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:365) returns Result/Option without axiomDecision
  collectZ3Pin (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:389) returns Result/Option without axiomDecision
  collectLeanPin (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:404) returns Result/Option without axiomDecision
  collectRecipeDigest (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:421) returns Result/Option without axiomDecision
  collectZ3ChecksumPolicyDigest (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:428) returns Result/Option without axiomDecision
  collectEvidenceDraftDigest (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:434) returns Result/Option without axiomDecision
  collectScopeDigest (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:441) returns Result/Option without axiomDecision
  collectPolicyDigest (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:448) returns Result/Option without axiomDecision
  collectArtifactDigests (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:457) returns Result/Option without axiomDecision
  collectVerifierIdentityInputs (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:473) returns Result/Option without axiomDecision
  markStrictGeneration (/tmp/dbwarn_wt/src/infrastructure/evidence_artifact_io.nim:264) multiple returns without axiomDecision
  saveCompletenessBinding (/tmp/dbwarn_wt/src/infrastructure/evidence_artifact_io.nim:392) multiple returns without axiomDecision
  executePlan (/tmp/dbwarn_wt/src/engine/plan_executor.nim:64) returns Result/Option without axiomDecision
[decision-binding] WAIVER EXPIRING SOON: src/core/trusted/architecture_invariants.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/static_gate_scanner.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/runners/debt_scan_gate.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/solver/z3_pool.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/vault/vault_factory.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/io/io_utils.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/encoding/smt_to_lean/private/parser.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/schema/task_schema.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/interfaces/git_operations.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/manifest_parser.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/types/results.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/gateway/gateway_json.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/session/session_parser_validators.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/proof/proof_universe_lock.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/json/json_utils.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/json/json_scan_parse.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/solver/wp_simplifier.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/proof_state_projection.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/ast_extractor.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/sieve/sieve_rules.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/personas/legislator.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/engine/dag_executor.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/verifier/legislator.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/cli/action_output_cli.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/cli/action_plan_cli.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/cli/cli_io_input.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/cli/cli_surface_generated.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/cli/debug_mode.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/cli/gate_ring_buffer.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/cli/payload_bridge.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/cli/precompile_gates.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/cli/report_cli.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/cli/run_gate.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/cli/selection_state.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/cli/subagent_orchestrator.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/cli/wf_render.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/cli/wf_runners.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/cli/wf_state_parsing.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/cli/wf_state_vacuity.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/api/axiom_api_helpers.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/api/axiom_api_session_helpers.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/api/axiom_api_session_ops.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/api/axiom_api_session_proof.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/api/axiom_api_verify.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/audit/burn_down_queue.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/audit/sad_gate.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/bmc/bmc_engine.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/boundary/abstract_spec_lowering.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/boundary/axiom_registry_loader.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/boundary/boundary_extractor_part1_part1.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/boundary/gateway/gateway_generator.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/boundary/private/semantic_hint_factory.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/cache/proof_cache.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/cache/ttl_cache.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/contract/contract_ast_extractor.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/contract/contract_param_util.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/contract/contract_smtlib2.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/contracts/universal_pipeline_contract.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/contracts/z3_extraction.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/diagnostics/diagnostics_engine_helpers.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/diagnostics/diagnostics_engine_main.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/encoding/smt_to_lean/private/arithmetic_expr.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/encoding/smt_to_lean_codegen.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/encoding/smt_to_lean_translate.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/encoding/smtlib2_sanitizer.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/encoding/smtlib2_util.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/gate/artifact_manifest.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/gate/atomic_deploy.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/gate/cache_manifest.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/gate/file_hash_cache.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/gate/gate_cas.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/gate/gate_memo.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/gate/gate_vfs.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/gate/merkle_vfs.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/gate/overlay_mount.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/gate/resource_limits.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/gate/transitive_hash.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/gateway/gateway_helpers.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/gateway/gateway_main.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/gateway/gateway_types.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/integrity/refinement_types.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/interfaces/io_executor.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/ir/ir_generator.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/ir/ir_to_lean.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/json/json_safe.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/json/json_scan_skip.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/judge/lean_replay.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/judge/smart_search.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/judge/the_judge_eval.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/judge/the_judge_query_part2.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/logic/pipeline_fingerprint_engine.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/logic/pipeline_trace_artifacts.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/logic/refinement_controller.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/logic/refinement_invariant.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/macros/enforce_linear.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/observer/scanner.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/orchestrator/cfg_builder.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/orchestrator/orchestrator_topology_worker.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/orchestrator/orchestrator_vault.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/parsers/collect.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/parsers/expression_parser.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/parsers/lean.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/parsers/nav.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/parsers/safe_parsers.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/parsers/tree_sitter/cache.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/parsers/tree_sitter_extractor.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/parsers/tree_sitter_parse.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/parsers/tree_sitter_parser.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/proof/axiom_lemmas.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/proof/function_source_extractor.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/proof/proof_budget.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/release/version_derive.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/schema/cst_schema.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/session/session_parser.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/solver/smt2_lexer.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/sorter/sorter_core_index_table.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/spec/spec_generator_main.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/symbol_graph/global_symbol_graph_builder_part1.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/symbol_graph/global_symbol_graph_builder_part2.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/symbolic/symbolic_types_exec.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/symbolic/symbolic_types_parse.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/sync/sync_utils_process.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/text/text_utils.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/topology/declaration.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/topology/lock.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/topology/merkle_cache.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/topology/policy.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/topology/suggest.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/topology/symbol_interning.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/topology/topology_engine.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/translator/ast_to_lean_bridge.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/translator/nim_ast_to_json_nodes.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/translator/universal_mapper_part1.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/trusted/ast_to_ir.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/trusted/axiom_boot_compiler.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/trusted/axiom_ir.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/trusted/axiom_pragmas_lite.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/trusted/axiom_pragmas_macros.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/trusted/axiom_pragmas_procs.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/trusted/effect_inference_engine.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/trusted/io_boundary.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/trusted/ir_to_lean.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/trusted/layer_enforcement.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/trusted/provenance_guard.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/trusted/smt_sort.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/trusted/stdlib_shield.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/trusted/theorem_writer.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/type_system/liquid_inference.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/types/asi_types.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/types/certificate_types.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/types/debt_types.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/types/domain_utils.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/types/function_verification_summary.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/types/quarantine.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/types/symbolic_types_expr.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/types/type_mapping.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/types/vkd_types.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/utils/text_utils.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/vault/vault_manager_spec.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/vault/vault_manager_storage.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/verified_axioms/verified_axioms_catalog_part1.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/core/verified_axioms/verified_axioms_core.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/engine/atomic_ops.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/engine/task_dag.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/action_cache.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/architecture_ast_facts.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/attestation.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/cache/soundness_cache_types.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/daemon/gate_daemon_client.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/gate_cache.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/gate_dag.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/gate_rules_module_classifier.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/gate_utils.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/gateway.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/in_process_gates.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/logic_binding_gate.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/manifest_provider.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/nimtry/nimtry_cli.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/nimtry/solid_queries_dip_ocp.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/orchestrator/hook/analyzer.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/orchestrator/hook/context.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/orchestrator/hook/executor.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/orchestrator/hook/memo.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/orchestrator_hook.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/pipeline.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/pipeline_orchestrator.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/predicates/types.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/runners/asset_hygiene_gate.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/runners/axiom_codemod.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/runners/binary_freshness_gate.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/runners/ci_pipeline_health_gate.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/runners/ci_skip_detector_gate.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/runners/core_invariant_gate.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/runners/decision_binding_gate.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/runners/documentation_first_gate.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/runners/import_encapsulation_gate.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/runners/import_normalizer.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/runners/lean_z3_consensus_gate.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/runners/manifest_consistency_gate.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/runners/private/documentation_first_gate_procs_part1.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/runners/release_version_gate.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/runners/semantic_boundary_guard.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/runners/unified_gate_runner.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/types.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/utils/git_wrapper.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/utils/inprocess_dispatch.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/utils/plumbing.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/gate/utils/shell_ast_analyzer.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/infrastructure/cas_index.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/infrastructure/gate_signing/proof_verifier.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/infrastructure/gate_signing/smtlib2_parser.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/infrastructure/gate_signing/z3_proof_to_lean.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/infrastructure/vfs_intern.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/personas/detective.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/personas/judge_automation.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/personas/llm_response_guard.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/ui/ax_tui_reporter_part1.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/abstract_provider.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/analyzer/analyzer_shared_cert.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/analyzer/stage_01_ast_extract.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/ax_classify.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/ax_implication.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/ax_tautology.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/batch_uap/loop_driver.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/batch_uap/private/request_builder.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/certificate_hydration.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/certificate_manager.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/contract_source_extractor.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/ecosystem_linkage.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/fingerprint_engine.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/integrity_guard.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/integrity_ledger.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/lean_lsp_protocol.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/lean_repl_bridge.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/leanstral_prompt.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/leanstral_repl.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/llm_backend.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/loop_invariant_synthesis.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/orchestrator/healing_orchestrator.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/orchestrator/private/healing_orchestrator_part1.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/pipeline_core_types.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/pipeline_lean_spec_inference_part1.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/pipeline_lean_spec_inference_part2.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/pipeline_negative_scan_part2.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/pipeline_transition.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/proof_linkage.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/proof_state_builder.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/report_engine.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/router.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/semantics/translator.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/solver/fixedpoint_engine.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/solver/proof_cache.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/solver/provers.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/solver/triviality_filter.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/spacer_chc_router.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/state_manager.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/static_rules.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/symbolic_test_synth.nim (2026-12-31, 56 days remaining)
[decision-binding] WAIVER EXPIRING SOON: src/verification/tactic_backtrack.nim (2026-12-31, 56 days remaining)
[decision-binding] FAIL: 50 function(s) missing {.axiomDecision.} pragma — waiver(s) expiring within 57 days
```

## C. `bin/hermetic_build --check-decision-bindings --escalation-threshold 30` (게이트 스캐너, exit 0)

- `make check-decision-binding`(Makefile:273-276)이 실행하는 두 번째 스캐너의 전체 출력. `Found 66 violation(s)` = **파일** 66, 함수 329.
- dbc(A)와의 차이 16파일은 중첩·비프리뷰 함수까지 스캔하는 구현 차이 때문이다 (본문 §8).

```
[hermetic] build_env.nim generated (content changed)
[decision-binding] Starting decision binding check...
[decision-binding] Found 66 violation(s)
  parsePropositionsSchema (/tmp/dbwarn_wt/src/cli/proposition_intake.nim:252) returns Result/Option without axiomDecision
  loadEvidenceRecordForRegister (/tmp/dbwarn_wt/src/cli/cert_cli.nim:627) returns Result/Option without axiomDecision
  persistRegisteredSubject (/tmp/dbwarn_wt/src/cli/cert_cli.nim:675) returns Result/Option without axiomDecision
  loadAttestInputs (/tmp/dbwarn_wt/src/cli/cert_cli.nim:767) returns Result/Option without axiomDecision
  ledgerHasSubjectCert (/tmp/dbwarn_wt/src/cli/cert_cli.nim:820) returns Result/Option without axiomDecision
  ledgerRecordConsistentWith (/tmp/dbwarn_wt/src/cli/cert_cli.nim:1220) returns Result/Option without axiomDecision
  parseRoundtripClause (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:903) returns Result/Option without axiomDecision
  parseUpperDomainClause (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:927) returns Result/Option without axiomDecision
  parseLowerDomainClause (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:941) returns Result/Option without axiomDecision
  parseRemLowerClause (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:1058) returns Result/Option without axiomDecision
  parseRemRangeClause (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:1071) returns Result/Option without axiomDecision
  parseRemGeZeroClause (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:1087) returns Result/Option without axiomDecision
  parseCoutClaimClause (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:1211) returns Result/Option without axiomDecision
  validateCoutOverlayNode (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:1234) returns Result/Option without axiomDecision
  validateCoutOverlayNode (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:1259) returns Result/Option without axiomDecision
  parseD2ExclusionClause (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:1400) returns Result/Option without axiomDecision
  parseD2AtomClause (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:1413) returns Result/Option without axiomDecision
  parseD2ForbidOperandCounts (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:1433) returns Result/Option without axiomDecision
  parseD2GateClause (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:1478) returns Result/Option without axiomDecision
  validateTomlD2AgentOverlayNode (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:1538) returns Result/Option without axiomDecision
  validateTomlD2AgentOverlayNode (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:1558) returns Result/Option without axiomDecision
  parseBvArithBody (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:1820) returns Result/Option without axiomDecision
  parseBvNamedDefClause (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:1847) returns Result/Option without axiomDecision
  validateBvSubjectPin (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:1899) returns Result/Option without axiomDecision
  validateBvOwnership (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:1928) returns Result/Option without axiomDecision
  validateBvCarriers (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:1950) returns Result/Option without axiomDecision
  definitionOf (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:2083) returns Result/Option without axiomDecision
  validateSidecarAdoption (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:2423) returns Result/Option without axiomDecision
  validateSidecarOverlayNode (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:2472) returns Result/Option without axiomDecision
  loadNimSidecarOverlayDomain (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:2479) returns Result/Option without axiomDecision
  validateSidecarOverlayNode (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:2494) returns Result/Option without axiomDecision
  referencedParam (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:3375) returns Result/Option without axiomDecision
  referencedParam (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:3597) returns Result/Option without axiomDecision
  referencedParam (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:3769) returns Result/Option without axiomDecision
  referencedParam (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:4001) returns Result/Option without axiomDecision
  bvAdapterValidate (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:4281) returns Result/Option without axiomDecision
  d2AdapterValidate (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:4315) returns Result/Option without axiomDecision
  sidecarAdapterValidate (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:4349) returns Result/Option without axiomDecision
  coutAdapterValidate (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:4391) returns Result/Option without axiomDecision
  capabilityAdapterFor (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:4481) returns Result/Option without axiomDecision
  registryPayloadFor (/tmp/dbwarn_wt/src/cli/axiom_engine.nim:5033) returns Result/Option without axiomDecision
  loadScopeLock (/tmp/dbwarn_wt/src/cli/rust_lane_cli.nim:292) returns Result/Option without axiomDecision
  parseMintArgs (/tmp/dbwarn_wt/src/cli/admission_cli.nim:74) returns Result/Option without axiomDecision
  parseAppendArgs (/tmp/dbwarn_wt/src/cli/admission_cli.nim:184) returns Result/Option without axiomDecision
  parseShowArgs (/tmp/dbwarn_wt/src/cli/admission_cli.nim:273) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  parseTrustSurfaceJson (/tmp/dbwarn_wt/src/cli/merge_cli.nim:754) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  rotationAllowlistOk (/tmp/dbwarn_wt/src/cli/merge_cli.nim:803) returns Result/Option without axiomDecision
  trustSurfaceOutcome (/tmp/dbwarn_wt/src/cli/merge_cli.nim:1200) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  MergeAdmissible (/tmp/dbwarn_wt/src/cli/merge_cli.nim:1233) multiple returns without axiomDecision
  checkedStr (/tmp/dbwarn_wt/src/cli/merge_cli.nim:1562) multiple returns without axiomDecision
  parseLayerPairRegistry (/tmp/dbwarn_wt/src/cli/merge_cli.nim:1760) returns Result/Option without axiomDecision
  loadDerivedLineSet (/tmp/dbwarn_wt/src/cli/merge_cli.nim:1849) returns Result/Option without axiomDecision
  loadTrustSurface (/tmp/dbwarn_wt/src/cli/merge_cli.nim:1860) returns Result/Option without axiomDecision
  loadPinBClosure (/tmp/dbwarn_wt/src/cli/merge_cli.nim:1884) returns Result/Option without axiomDecision
  collectCertificateContinuityFacts (/tmp/dbwarn_wt/src/cli/merge_cli.nim:1963) returns Result/Option without axiomDecision
  certificateFactFromPath (/tmp/dbwarn_wt/src/cli/merge_cli.nim:1966) returns Result/Option without axiomDecision
  parseMergeSuccess (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2189) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  requestGitHubPut (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2205) returns Result/Option without axiomDecision
  performMerge (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2238) returns Result/Option without axiomDecision
  observePullState (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2282) returns Result/Option without axiomDecision
  resolveMergeShapeApi (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2351) returns Result/Option without axiomDecision
  resolveMergeShapeLocal (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2382) returns Result/Option without axiomDecision
  loadLedgerCertFor (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2420) returns Result/Option without axiomDecision
  certificateFactFromNode (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2471) returns Result/Option without axiomDecision
  verifiedCertificateArtifact (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2495) returns Result/Option without axiomDecision
  certificateFactFromPath (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2524) returns Result/Option without axiomDecision
  scanLedgerContinuityCertNode (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2568) returns Result/Option without axiomDecision
  collectCertificateContinuityFacts (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2632) returns Result/Option without axiomDecision
  parseActiveKernelSymbols (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2680) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  vaultManifestIndex (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2705) returns Result/Option without axiomDecision
  vaultPolicyEpochCurrentDigests (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2731) returns Result/Option without axiomDecision
  vaultFileBytes (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2743) returns Result/Option without axiomDecision
  vaultFileJson (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2751) returns Result/Option without axiomDecision
  vaultTreeSha256 (/tmp/dbwarn_wt/src/cli/merge_cli.nim:2762) returns Result/Option without axiomDecision
  safeSpecRelPath (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:318) multiple returns without axiomDecision
  parseFindingEvidence (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:397) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  selectDisplayBlock (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:439) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  selectReportableUnits (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:453) returns Result/Option without axiomDecision
  evalLinearRhs (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:531) returns Result/Option without axiomDecision
  evalClauseValue (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:555) returns Result/Option without axiomDecision
  classifyGhOutcome (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:784) multiple returns without axiomDecision
  parseIssueView (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:878) returns Result/Option without axiomDecision
  parseIssueRefList (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:893) returns Result/Option without axiomDecision
  decodeGhContentsJson (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:907) returns Result/Option without axiomDecision
  receiptFromJson (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:1144) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  parseUpstreamFlags (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:1281) returns Result/Option without axiomDecision
  loadSpecOverlay (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:1387) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  loadReceipt (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:1403) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  saveReceiptAtomic (/tmp/dbwarn_wt/src/cli/upstream_report_cli.nim:1418) returns Result/Option without axiomDecision
  isOid40 (/tmp/dbwarn_wt/src/cli/landing_cli.nim:85) multiple returns without axiomDecision
  verifyCertBinding (/tmp/dbwarn_wt/src/cli/landing_cli.nim:106) multiple returns without axiomDecision
  fetchPrHead (/tmp/dbwarn_wt/src/cli/landing_cli.nim:150) returns Result/Option without axiomDecision
  compareStatus (/tmp/dbwarn_wt/src/cli/landing_cli.nim:167) returns Result/Option without axiomDecision
  parseAppendArgs (/tmp/dbwarn_wt/src/cli/evidence_cli.nim:53) returns Result/Option without axiomDecision
  parseLookupArgs (/tmp/dbwarn_wt/src/cli/evidence_cli.nim:138) returns Result/Option without axiomDecision
  validateSubjectPinObject (/tmp/dbwarn_wt/src/cli/external_subject_registry.nim:227) returns Result/Option without axiomDecision
  validateOwnershipObject (/tmp/dbwarn_wt/src/cli/external_subject_registry.nim:254) returns Result/Option without axiomDecision
  parseCapabilityTag (/tmp/dbwarn_wt/src/cli/external_subject_registry.nim:355) returns Result/Option without axiomDecision
  parsePresenceTag (/tmp/dbwarn_wt/src/cli/external_subject_registry.nim:367) returns Result/Option without axiomDecision
  parseObservationTag (/tmp/dbwarn_wt/src/cli/external_subject_registry.nim:373) returns Result/Option without axiomDecision
  compatLaneEnvelopeProjection (/tmp/dbwarn_wt/src/cli/external_subject_registry.nim:485) returns Result/Option without axiomDecision
  envelopeEntryForNode (/tmp/dbwarn_wt/src/cli/external_subject_registry.nim:531) returns Result/Option without axiomDecision
  pointsToStableEntry (/tmp/dbwarn_wt/src/cli/install_ax_cas.nim:38) multiple returns without axiomDecision
  fromJsonResult (/tmp/dbwarn_wt/src/core/types/request_result.nim:119) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  changeDescriptorFromJson (/tmp/dbwarn_wt/src/core/types/candidate_identity.nim:204) returns Result/Option without axiomDecision
  candidateStateIdentityFromJson (/tmp/dbwarn_wt/src/core/types/candidate_identity.nim:211) returns Result/Option without axiomDecision
  candidateProvenanceFromJson (/tmp/dbwarn_wt/src/core/types/candidate_identity.nim:218) returns Result/Option without axiomDecision
  verificationContextIdentityFromJson (/tmp/dbwarn_wt/src/core/types/candidate_identity.nim:233) returns Result/Option without axiomDecision
  candidateEvidenceDigestFromJson (/tmp/dbwarn_wt/src/core/types/candidate_identity.nim:242) returns Result/Option without axiomDecision
  materializedCandidateFromJson (/tmp/dbwarn_wt/src/core/types/candidate_identity.nim:251) returns Result/Option without axiomDecision
  materializationRecordFromJson (/tmp/dbwarn_wt/src/core/types/candidate_identity.nim:263) returns Result/Option without axiomDecision
  fromJson (/tmp/dbwarn_wt/src/core/types/execution_plan.nim:66) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  fromJson (/tmp/dbwarn_wt/src/core/types/request_id.nim:32) returns Result/Option without axiomDecision
  countCallDepth (/tmp/dbwarn_wt/src/core/diagnostics/pattern_guard.nim:247) multiple returns without axiomDecision
  normalizeMaxWorkers (/tmp/dbwarn_wt/src/core/orchestrator/orchestrator_api.nim:40) multiple returns without axiomDecision
  commonAncestorDir (/tmp/dbwarn_wt/src/core/gate/trust_commit_scope_scan.nim:268) multiple returns without axiomDecision
  parseDerivedSet (/tmp/dbwarn_wt/src/core/policy/rotation_closure_facts.nim:86) returns Result/Option without axiomDecision
  pinClosureLineSet (/tmp/dbwarn_wt/src/core/policy/rotation_closure_facts.nim:102) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  verifyRatchetDowngradeSignature (/tmp/dbwarn_wt/src/core/trusted/ratchet_authority.nim:57) multiple returns without axiomDecision
  isLowerHex (/tmp/dbwarn_wt/src/core/trusted/bug_attribution_grounds.nim:59) multiple returns without axiomDecision
  isStringArray (/tmp/dbwarn_wt/src/core/trusted/bug_attribution_grounds.nim:70) multiple returns without axiomDecision
  requireObject (/tmp/dbwarn_wt/src/core/trusted/bug_attribution_grounds.nim:91) returns Result/Option without axiomDecision
  validateReproduction (/tmp/dbwarn_wt/src/core/trusted/bug_attribution_grounds.nim:97) returns Result/Option without axiomDecision
  validateClaimOwnership (/tmp/dbwarn_wt/src/core/trusted/bug_attribution_grounds.nim:116) returns Result/Option without axiomDecision
  validateGroundsEnvelope (/tmp/dbwarn_wt/src/core/trusted/bug_attribution_grounds.nim:184) returns Result/Option without axiomDecision
  validateGroundsConfirmation (/tmp/dbwarn_wt/src/core/trusted/bug_attribution_grounds.nim:267) returns Result/Option without axiomDecision
  validateGroundsCategories (/tmp/dbwarn_wt/src/core/trusted/bug_attribution_grounds.nim:289) returns Result/Option without axiomDecision
  validateGroundsDigest (/tmp/dbwarn_wt/src/core/trusted/bug_attribution_grounds.nim:368) returns Result/Option without axiomDecision
  validateGroundsFile (/tmp/dbwarn_wt/src/core/trusted/bug_attribution_grounds.nim:378) returns Result/Option without axiomDecision
  containsU64Lit (/tmp/dbwarn_wt/src/core/trusted/private/ir_to_smt_chunk2.nim:36) multiple returns without axiomDecision
  explicitSpecFromOverlay (/tmp/dbwarn_wt/src/core/trusted/specification_artifact.nim:68) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  indexGuard (/tmp/dbwarn_wt/src/core/trusted/contract_synthesis.nim:47) multiple returns without axiomDecision
  isSha256Hex (/tmp/dbwarn_wt/src/core/utils/skreport_comparison.nim:169) multiple returns without axiomDecision
  isSha256Hex (/tmp/dbwarn_wt/src/verification/obligation/obligation_types.nim:444) multiple returns without axiomDecision
  isGitRef (/tmp/dbwarn_wt/src/verification/obligation/obligation_types.nim:452) multiple returns without axiomDecision
  leafStr (/tmp/dbwarn_wt/src/verification/obligation/post_satisfaction.nim:64) returns Result/Option without axiomDecision
  atomSubject (/tmp/dbwarn_wt/src/verification/obligation/post_satisfaction.nim:88) returns Result/Option without axiomDecision
  guardAtomOf (/tmp/dbwarn_wt/src/verification/obligation/post_satisfaction.nim:105) returns Result/Option without axiomDecision
  negateGuardAtom (/tmp/dbwarn_wt/src/verification/obligation/post_satisfaction.nim:144) returns Result/Option without axiomDecision
  normalizeGuard (/tmp/dbwarn_wt/src/verification/obligation/post_satisfaction.nim:161) returns Result/Option without axiomDecision
  clauseFromExpr (/tmp/dbwarn_wt/src/verification/obligation/post_satisfaction.nim:192) returns Result/Option without axiomDecision
  collectClauses (/tmp/dbwarn_wt/src/verification/obligation/post_satisfaction.nim:248) returns Result/Option without axiomDecision
  bodyAsIfElse (/tmp/dbwarn_wt/src/verification/obligation/post_satisfaction.nim:283) returns Result/Option without axiomDecision
  measuredBinaryDigest (/tmp/dbwarn_wt/src/verification/obligation/measured_digests.nim:56) multiple returns without axiomDecision
  lower (/tmp/dbwarn_wt/src/verification/obligation/canonical_verification.nim:301) multiple returns without axiomDecision
  containsIdentToken (/tmp/dbwarn_wt/src/verification/obligation/canonical_verification.nim:388) multiple returns without axiomDecision
  runKernelCheck (/tmp/dbwarn_wt/src/verification/obligation/canonical_verification.nim:721) returns Result/Option without axiomDecision
  measureSubjectGitRef (/tmp/dbwarn_wt/src/verification/obligation/canonical_verification.nim:869) multiple returns without axiomDecision
  measureCompositeCarrierTypename (/tmp/dbwarn_wt/src/verification/obligation/canonical_verification.nim:1190) multiple returns without axiomDecision
  rejectionToken (/tmp/dbwarn_wt/src/verification/obligation/candidate_eligibility.nim:97) returns Result/Option without axiomDecision
  divisorOperandOf (/tmp/dbwarn_wt/src/verification/obligation/candidate_eligibility.nim:261) multiple returns without axiomDecision
  divisorTautologyOf (/tmp/dbwarn_wt/src/verification/obligation/candidate_eligibility.nim:278) multiple returns without axiomDecision
  rejectionTokenOrNull (/tmp/dbwarn_wt/src/verification/obligation/candidate_eligibility.nim:583) returns Result/Option without axiomDecision
  canonicalizeEnvValue (/tmp/dbwarn_wt/src/verification/obligation/identity.nim:53) multiple returns without axiomDecision
  rustTemplateSkeleton (/tmp/dbwarn_wt/src/verification/rust_obligation_render.nim:111) multiple returns without axiomDecision
  widthBound (/tmp/dbwarn_wt/src/verification/rust_obligation_render.nim:203) returns Result/Option without axiomDecision
  rustExtractorIdentityDigest (/tmp/dbwarn_wt/src/verification/rust_obligation_render.nim:674) multiple returns without axiomDecision
  loadCASEntryByKey (/tmp/dbwarn_wt/src/verification/canonical_cache.nim:149) returns Result/Option without axiomDecision
  decodeTypePayload (/tmp/dbwarn_wt/src/verification/llbc_to_canonical.nim:332) multiple returns without axiomDecision
  parseUintText (/tmp/dbwarn_wt/src/verification/llbc_to_canonical.nim:401) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  requireSignatureShape (/tmp/dbwarn_wt/src/verification/llbc_to_canonical.nim:788) multiple returns without axiomDecision
  decodeAssert (/tmp/dbwarn_wt/src/verification/llbc_to_canonical.nim:932) multiple returns without axiomDecision
  parseJudgmentSubject (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:358) returns Result/Option without axiomDecision
  fileDigestHexOrErr (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:516) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  collectChainedDigest (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:531) returns Result/Option without axiomDecision
  deriveSubjectTreeClosure (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:563) returns Result/Option without axiomDecision
  collectTestSourceClosure (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:583) returns Result/Option without axiomDecision
  collectGoldenFixturesDigest (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:599) returns Result/Option without axiomDecision
  subjectSourceClosure (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:661) returns Result/Option without axiomDecision
  subjectFixturesDigest (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:675) returns Result/Option without axiomDecision
  collectRecipeDigest (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:689) returns Result/Option without axiomDecision
  compilerPinsDigest (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:695) returns Result/Option without axiomDecision
  collectToolchainBundleDigest (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:707) returns Result/Option without axiomDecision
  collectJudgmentClosure (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:806) returns Result/Option without axiomDecision
  exactFieldSet (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:922) multiple returns without axiomDecision
  validateS1aJudgmentPayloadNode (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:944) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  validateProofIntegrityPayloadNode (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1065) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  validateD2GoldenPayloadNode (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1122) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  validateD2PersistPayloadNode (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1185) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  validateJudgmentPayloadNode (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1235) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  writeJudgmentEvidenceFile (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1279) returns Result/Option without axiomDecision
  parseJudgmentEvidenceFile (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1305) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  writeSubjectEvidenceFile (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1411) returns Result/Option without axiomDecision
  writeProofIntegrityJudgmentEvidenceFile (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1431) returns Result/Option without axiomDecision
  buildJudgmentRecord (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1723) returns Result/Option without axiomDecision
  validateJudgmentWitnessNode (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1779) multiple returns without axiomDecision
  judgmentRootRecordMarkerShape (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1813) multiple returns without axiomDecision
  writeJudgmentDecisionFile (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1859) returns Result/Option without axiomDecision
  verifyJudgmentReuse (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1909) multiple returns without axiomDecision
  runJudgmentAttestBranchForSubject (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:1954) returns Result/Option without axiomDecision
  runJudgmentAttestBranch (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:2117) returns Result/Option without axiomDecision
  parseExecutionVerdict (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:2184) returns Result/Option without axiomDecision
  validateJudgmentExecutionRecord (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:2244) multiple returns without axiomDecision
  appendExecutionRecord (/tmp/dbwarn_wt/src/verification/judgment_cas.nim:2327) returns Result/Option without axiomDecision
  rustGuardWidthBound (/tmp/dbwarn_wt/src/verification/rust_extraction_agreement.nim:277) returns Result/Option without axiomDecision
  fingerprintFromNode (/tmp/dbwarn_wt/src/verification/extraction_provenance.nim:121) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  validateExtractionContract (/tmp/dbwarn_wt/src/verification/extraction_provenance.nim:150) multiple returns without axiomDecision
  validateExtractionJobRecord (/tmp/dbwarn_wt/src/verification/extraction_provenance.nim:164) multiple returns without axiomDecision
  jobRecordFromJson (/tmp/dbwarn_wt/src/verification/extraction_provenance.nim:224) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  extractionJobRecordFromPayload (/tmp/dbwarn_wt/src/verification/extraction_provenance.nim:262) returns Result/Option without axiomDecision
  extractionJobKey (/tmp/dbwarn_wt/src/verification/extraction_provenance.nim:316) returns Result/Option without axiomDecision
  fileSha256Hex (/tmp/dbwarn_wt/src/verification/extraction_provenance.nim:330) returns Result/Option without axiomDecision
  llbcFileDigest (/tmp/dbwarn_wt/src/verification/extraction_provenance.nim:344) returns Result/Option without axiomDecision
  ledgerCertId (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:77) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  shaFromObject (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:96) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  shaFromNode (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:105) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  ledgerScanIndexFromTree (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:114) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  listEntriesFromTree (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:152) returns Result/Option without axiomDecision
  decodeBlobContent (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:164) returns Result/Option without axiomDecision
  blobEntrySha (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:190) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  fetchTipTree (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:217) returns Result/Option without axiomDecision
  listLedgerCertIds (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:260) returns Result/Option without axiomDecision
  listRefEntryNames (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:279) returns Result/Option without axiomDecision
  openLedgerScanIndex (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:316) returns Result/Option without axiomDecision
  fetchLedgerCertBlob (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:339) returns Result/Option without axiomDecision
  downloadLedgerCertificateAtBlob (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:370) returns Result/Option without axiomDecision
  downloadLedgerCertificate (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:381) returns Result/Option without axiomDecision
  ledgerHasCertAtTip (/tmp/dbwarn_wt/src/verification/ledger_side_ref.nim:493) returns Result/Option without axiomDecision
  stripInjectedCommentBlock (/tmp/dbwarn_wt/src/verification/cert_writer.nim:65) multiple returns without axiomDecision
  validateVerifierArtifactDigests (/tmp/dbwarn_wt/src/verification/evidence_ledger.nim:121) multiple returns without axiomDecision
  validateEvidenceRecord (/tmp/dbwarn_wt/src/verification/evidence_ledger.nim:167) multiple returns without axiomDecision
  evidenceRecordFromJson (/tmp/dbwarn_wt/src/verification/evidence_ledger.nim:200) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  evidenceKeysFromNames (/tmp/dbwarn_wt/src/verification/evidence_ledger.nim:243) returns Result/Option without axiomDecision
  blobShaForKey (/tmp/dbwarn_wt/src/verification/evidence_ledger.nim:258) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  decodeEvidenceBlob (/tmp/dbwarn_wt/src/verification/evidence_ledger.nim:281) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  parseEvidenceRecord (/tmp/dbwarn_wt/src/verification/evidence_ledger.nim:294) returns Result/Option without axiomDecision
  isOid40 (/tmp/dbwarn_wt/src/verification/admission_artifact.nim:87) multiple returns without axiomDecision
  mintAdmissionPayload (/tmp/dbwarn_wt/src/verification/admission_artifact.nim:96) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  decodeExecutionIdentityClaims (/tmp/dbwarn_wt/src/verification/admission_artifact.nim:140) returns Result/Option without axiomDecision
  admissionPayloadDigest (/tmp/dbwarn_wt/src/verification/admission_artifact.nim:202) returns Result/Option without axiomDecision
  artifactPayloadFromEnvelope (/tmp/dbwarn_wt/src/verification/admission_artifact.nim:216) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  isCanonicalVerifierBuildId (/tmp/dbwarn_wt/src/verification/attestation_orchestrator.nim:144) multiple returns without axiomDecision
  validateAttestationInputs (/tmp/dbwarn_wt/src/verification/attestation_orchestrator.nim:266) multiple returns without axiomDecision
  inputsFromJson (/tmp/dbwarn_wt/src/verification/attestation_orchestrator.nim:299) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  parseAttestationEvidenceText (/tmp/dbwarn_wt/src/verification/attestation_orchestrator.nim:350) returns Result/Option without axiomDecision
  reloadStoredSubject (/tmp/dbwarn_wt/src/verification/attestation_orchestrator.nim:391) returns Result/Option without axiomDecision
  reuseIrHashFromPayload (/tmp/dbwarn_wt/src/verification/attestation_orchestrator.nim:562) returns Result/Option without axiomDecision
  isEarlyReturnIfWire (/tmp/dbwarn_wt/src/verification/ast_wire.nim:173) multiple returns without axiomDecision
  serializeFuncDefWire (/tmp/dbwarn_wt/src/verification/ast_wire.nim:430) multiple returns without axiomDecision
  provenanceValidationError (/tmp/dbwarn_wt/src/verification/attestation_witness.nim:177) multiple returns without axiomDecision
  semanticValidationError (/tmp/dbwarn_wt/src/verification/attestation_witness.nim:197) multiple returns without axiomDecision
  witnessJsonObject (/tmp/dbwarn_wt/src/verification/attestation_witness.nim:295) returns Result/Option without axiomDecision
  witnessJsonString (/tmp/dbwarn_wt/src/verification/attestation_witness.nim:302) returns Result/Option without axiomDecision
  decodeWitnessSemantic (/tmp/dbwarn_wt/src/verification/attestation_witness.nim:308) returns Result/Option without axiomDecision
  parseWitnessBundleText (/tmp/dbwarn_wt/src/verification/attestation_witness.nim:428) returns Result/Option without axiomDecision
  signWitness (/tmp/dbwarn_wt/src/verification/attestation_witness.nim:490) returns Result/Option without axiomDecision
  computeTestClosureDigest (/tmp/dbwarn_wt/src/verification/verification_query_engine.nim:98) returns Result/Option without axiomDecision
  computeBaselineDigest (/tmp/dbwarn_wt/src/verification/verification_query_engine.nim:129) returns Result/Option without axiomDecision
  computeLockDigest (/tmp/dbwarn_wt/src/verification/verification_query_engine.nim:139) returns Result/Option without axiomDecision
  computePolicyDigest (/tmp/dbwarn_wt/src/verification/verification_query_engine.nim:149) returns Result/Option without axiomDecision
  dependencyDomain (/tmp/dbwarn_wt/src/verification/producer_identity.nim:73) multiple returns without axiomDecision
  isOid40 (/tmp/dbwarn_wt/src/verification/continuity_check.nim:55) multiple returns without axiomDecision
  verifyContinuity (/tmp/dbwarn_wt/src/verification/continuity_check.nim:76) multiple returns without axiomDecision
  irBytesEqual (/tmp/dbwarn_wt/src/verification/extraction_agreement.nim:81) multiple returns without axiomDecision
  startsAt (/tmp/dbwarn_wt/src/verification/renderer_differential.nim:98) multiple returns without axiomDecision
  normalizeLeanForDifferential (/tmp/dbwarn_wt/src/verification/renderer_differential.nim:278) multiple returns without axiomDecision
  parseSubjectText (/tmp/dbwarn_wt/src/verification/subject_store.nim:43) returns Result/Option without axiomDecision
  saveSubject (/tmp/dbwarn_wt/src/verification/subject_store.nim:54) returns Result/Option without axiomDecision
  loadSubject (/tmp/dbwarn_wt/src/verification/subject_store.nim:74) returns Result/Option without axiomDecision
  listSubjects (/tmp/dbwarn_wt/src/verification/subject_store.nim:87) returns Result/Option without axiomDecision
  findSubjectsByHeadSha (/tmp/dbwarn_wt/src/verification/subject_store.nim:106) returns Result/Option without axiomDecision
  atomicReplaceFile (/tmp/dbwarn_wt/src/verification/cert_reconcile.nim:331) returns Result/Option without axiomDecision
  atomicReplaceFile (/tmp/dbwarn_wt/src/verification/cert_reconcile.nim:343) returns Result/Option without axiomDecision
  isFullCertClaim (/tmp/dbwarn_wt/src/verification/cert_reconcile.nim:865) multiple returns without axiomDecision
  isQuarantined (/tmp/dbwarn_wt/src/verification/cert_reconcile.nim:1168) multiple returns without axiomDecision
  parseNimblePkgDirName (/tmp/dbwarn_wt/src/verification/counterexample_replay.nim:246) returns Result/Option without axiomDecision
  versionRank (/tmp/dbwarn_wt/src/verification/counterexample_replay.nim:264) returns Result/Option without axiomDecision
  newestPkgDir (/tmp/dbwarn_wt/src/verification/counterexample_replay.nim:309) returns Result/Option without axiomDecision
  evalConcreteBinOp (/tmp/dbwarn_wt/src/verification/counterexample_replay.nim:336) returns Result/Option without axiomDecision
  evalConcreteUnaryOp (/tmp/dbwarn_wt/src/verification/counterexample_replay.nim:390) returns Result/Option without axiomDecision
  evaluatePostconditions (/tmp/dbwarn_wt/src/verification/counterexample_replay.nim:475) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  parseConcreteLiteral (/tmp/dbwarn_wt/src/verification/counterexample_replay.nim:488) returns Result/Option without axiomDecision
  decideReplayVerdict (/tmp/dbwarn_wt/src/verification/counterexample_replay.nim:523) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  extractObservedResult (/tmp/dbwarn_wt/src/verification/counterexample_replay.nim:538) returns Result/Option without axiomDecision
  ceReplayModulePath (/tmp/dbwarn_wt/src/verification/counterexample_replay.nim:778) multiple returns without axiomDecision
  subjectTreeNeedsDepRoots (/tmp/dbwarn_wt/src/verification/counterexample_replay.nim:913) multiple returns without axiomDecision
  bindSubjectIntegrity (/tmp/dbwarn_wt/src/verification/counterexample_replay.nim:1050) multiple returns without axiomDecision
  d2AgentReplayPostcondition (/tmp/dbwarn_wt/src/verification/counterexample_replay.nim:1392) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  isCertifiedNoEffectPath (/tmp/dbwarn_wt/src/verification/semantic_set_derivation.nim:238) multiple returns without axiomDecision
  parseLsTreeZ (/tmp/dbwarn_wt/src/verification/semantic_set_derivation.nim:384) returns Result/Option without axiomDecision
  isHexLen (/tmp/dbwarn_wt/src/verification/semantic_set_derivation.nim:465) multiple returns without axiomDecision
  runGitOrErr (/tmp/dbwarn_wt/src/verification/semantic_set_derivation.nim:473) returns Result/Option without axiomDecision
  probeTreeResolvable (/tmp/dbwarn_wt/src/verification/semantic_set_derivation.nim:510) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  listTreeUniverse (/tmp/dbwarn_wt/src/verification/semantic_set_derivation.nim:524) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  verifyPartition (/tmp/dbwarn_wt/src/verification/semantic_set_derivation.nim:546) returns Result/Option without axiomDecision
  isSemverDigits (/tmp/dbwarn_wt/src/verification/charon_runner.nim:93) multiple returns without axiomDecision
  probeCharonVersion (/tmp/dbwarn_wt/src/verification/charon_runner.nim:186) multiple returns without axiomDecision
  runPinnedCharonCargo (/tmp/dbwarn_wt/src/verification/charon_runner.nim:215) multiple returns without axiomDecision
  lowerPostconditionModel (/tmp/dbwarn_wt/src/verification/batch_uap/ir_pipeline_runner.nim:443) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  isHexOfLen (/tmp/dbwarn_wt/src/verification/verification_subject.nim:76) multiple returns without axiomDecision
  isValidIso8601Zulu (/tmp/dbwarn_wt/src/verification/verification_subject.nim:84) multiple returns without axiomDecision
  subjectFromJson (/tmp/dbwarn_wt/src/verification/verification_subject.nim:202) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  isAxiomAllowed (/tmp/dbwarn_wt/src/verification/kernel_reexecution.nim:61) multiple returns without axiomDecision
  evaluateObservedAxioms (/tmp/dbwarn_wt/src/verification/kernel_reexecution.nim:138) multiple returns without axiomDecision
  z3ResultVerdict (/tmp/dbwarn_wt/src/verification/kernel_reexecution.nim:169) multiple returns without axiomDecision
  loadCertJsonForReexecution (/tmp/dbwarn_wt/src/verification/kernel_reexecution.nim:203) returns Result/Option without axiomDecision
  reexecuteLean (/tmp/dbwarn_wt/src/verification/kernel_reexecution.nim:259) multiple returns without axiomDecision
  reexecuteZ3 (/tmp/dbwarn_wt/src/verification/kernel_reexecution.nim:316) multiple returns without axiomDecision
  resolveLeanChecker (/tmp/dbwarn_wt/src/verification/kernel_reexecution.nim:369) multiple returns without axiomDecision
  subjectCertJournalBind (/tmp/dbwarn_wt/src/verification/subject_continuity_writer.nim:226) returns Result/Option without axiomDecision
  subjectCertSignAndWrite (/tmp/dbwarn_wt/src/verification/subject_continuity_writer.nim:234) returns Result/Option without axiomDecision
  readBlobs (/tmp/dbwarn_wt/src/verification/tested_tree_closure.nim:295) returns Result/Option without axiomDecision
  readBlob (/tmp/dbwarn_wt/src/verification/tested_tree_closure.nim:357) returns Result/Option without axiomDecision
  lockEntryName (/tmp/dbwarn_wt/src/verification/tested_tree_closure.nim:394) multiple returns without axiomDecision
  extractObservedResult (/tmp/dbwarn_wt/src/verification/rust_replay_adapter.nim:314) returns Result/Option without axiomDecision
  rustSubjectModulePath (/tmp/dbwarn_wt/src/verification/rust_replay_adapter.nim:696) multiple returns without axiomDecision
  bindRustSubjectIntegrity (/tmp/dbwarn_wt/src/verification/rust_replay_adapter.nim:722) multiple returns without axiomDecision
  validateVerifierIdentityInputs (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:267) multiple returns without axiomDecision
  validateEvidenceKeyInputs (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:328) multiple returns without axiomDecision
  fileDigestHex (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:350) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  collectChainedFileDigest (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:365) returns Result/Option without axiomDecision
  collectZ3Pin (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:389) returns Result/Option without axiomDecision
  collectLeanPin (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:404) returns Result/Option without axiomDecision
  collectRecipeDigest (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:421) returns Result/Option without axiomDecision
  collectZ3ChecksumPolicyDigest (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:428) returns Result/Option without axiomDecision
  collectEvidenceDraftDigest (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:434) returns Result/Option without axiomDecision
  collectScopeDigest (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:441) returns Result/Option without axiomDecision
  collectPolicyDigest (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:448) returns Result/Option without axiomDecision
  collectArtifactDigests (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:457) returns Result/Option without axiomDecision
  collectVerifierIdentityInputs (/tmp/dbwarn_wt/src/verification/evidence_cas.nim:473) returns Result/Option without axiomDecision
  markStrictGeneration (/tmp/dbwarn_wt/src/infrastructure/evidence_artifact_io.nim:264) multiple returns without axiomDecision
  isCanonicalSha256Hex (/tmp/dbwarn_wt/src/infrastructure/evidence_artifact_io.nim:305) multiple returns without axiomDecision
  parseCompletenessPayloadStrict (/tmp/dbwarn_wt/src/infrastructure/evidence_artifact_io.nim:313) returns Result/Option without axiomDecision
  parseCompletenessBindingJson (/tmp/dbwarn_wt/src/infrastructure/evidence_artifact_io.nim:351) returns Result/Option without axiomDecision
  saveCompletenessBinding (/tmp/dbwarn_wt/src/infrastructure/evidence_artifact_io.nim:392) multiple returns without axiomDecision
  isConsumptionParent (/tmp/dbwarn_wt/src/gate/runners/evidence_truth_boundary_gate.nim:358) multiple returns without axiomDecision
  jtiSeen (/tmp/dbwarn_wt/src/gate/runners/coverage_ratchet_gate.nim:231) multiple returns without axiomDecision
  runMetricsMaterializer (/tmp/dbwarn_wt/src/gate/runners/readiness_start_gate.nim:230) multiple returns without axiomDecision
  executePlan (/tmp/dbwarn_wt/src/engine/plan_executor.nim:64) returns Result/Option without axiomDecision
[decision-binding] WARN: 66 function(s) missing {.axiomDecision.} pragma — escalation threshold 30 days not yet reached
```
