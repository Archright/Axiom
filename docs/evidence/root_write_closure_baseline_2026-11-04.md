# Root Write Closure — P0 Baseline 관측 편입본 (VS-1 PR-1)

> **편입**: 본 문서는 VS-1 Root Write Closure PR-1(branch `workstream/root-write-closure`)의
> 증거로, 저장소 밖 관측 원본 `<user-home>/.cache/axiom/rwc/baseline_2026-11-04.md`를
> 내용 무손 편입한 것이다(아래 본문 = 관측 원본 verbatim; 스크래치 원본은
> `<user-home>/.cache/axiom/rwc/scratch/`에 보존).
>
> **관측 조건**: 2026-11-04 13:09–13:14 KST · 대상 저장소
> `.5`(branch `main`, 관측 시작 시점 clean) ·
> **관측 시점 HEAD**: `76efe1fcccc9e0dd0fc60e3c6e310dad4b63d7fe`
> ("Merge pull request #1257 from Archright/work/decision-binding-escalation-survey-2026-11-04") ·
> 추적 파일 수정 0건 · 저장소 내 신규 파일 0건(validator 산출은 전부 gitignored 빌드 경로).

---

# Root Write Closure — P0 Baseline 관측 기록 (2026-11-04)

- **관측일시**: 2026-11-04 13:09–13:14 KST
- **대상 저장소**: `.5` (branch `main`, 관측 시작 시점 clean)
- **HEAD**: `76efe1fcccc9e0dd0fc60e3c6e310dad4b63d7fe` — 2026-11-04 02:23:15 +0000, "Merge pull request #1257 from Archright/work/decision-binding-escalation-survey-2026-11-04"
- **기록 위치**: 저장소 밖 `<user-home>/.cache/axiom/rwc/baseline_2026-11-04.md` — 추적 파일 수정 0건, 저장소 내 신규 파일 0건 (validator 산출은 전부 gitignored 빌드 경로)
- **스크래치 원본 보존**: `<user-home>/.cache/axiom/rwc/scratch/` (무시됨 전체 목록 19,496줄 등 명령 출력 원본)

## 실행 명령 목록

1. `git ls-files | awk -F/ '{print $1}' | sort | uniq -c | sort -rn`
2. `git ls-files --others --exclude-standard | head -50` + 개수
3. `git ls-files --others --ignored --exclude-standard | awk -F/ '{print $1}' | sort | uniq -c | sort -rn | head -20` + 총개수
4. `find . -mindepth 1 -maxdepth 1 -printf '%y %f\n' | sort`
5. `git fetch origin main` → `git rev-parse HEAD` → `git merge-base HEAD origin/main`
6. `make validate-root-layout`
7. `git status --porcelain` (make 실행 전/후)
8. `find bin -maxdepth 1 -type f -printf '%f\n' | grep -E '_[0-9A-Fa-f]{8,}$' | wc -l` + `find bin -maxdepth 1 -type f | wc -l` (make 전/후 2회)

---

## 1. 인벤토리 (make 실행 전 시점)

### 1.1 Tracked 파일 top-level 요약

명령: `git ls-files | awk -F/ '{print $1}' | sort | uniq -c | sort -rn` — 출력 44줄 전체:

```
   2177 tests
   1446 src
   1061 experiments
    988 docs
    562 data
    332 tools
     55 config
     31 .github
     28 proofs
     24 vendor
     12 _lto_evidence
      2 .githooks
      1 topology_policy.json
      1 topology.lock
      1 topology.json
      1 promotion_intent.json
      1 nimble.lock
      1 lfs_exceptions.json
      1 lean-toolchain
      1 lakefile.toml
      1 lake-manifest.json
      1 flake.nix
      1 config.nims
      1 ci
      1 bin
      1 axiom.toml
      1 axiom.nimble
      1 axiom.lock
      1 README.md
      1 Makefile
      1 LICENSE
      1 Dockerfile.build
      1 AGENTS.md
      1 .opencode
      1 .gitignore
      1 .gitattributes
      1 .envrc.example
      1 .envrc
      1 .env.example
      1 .editorconfig
      1 .dockerignore
      1 .cursorrules
      1 .config
      1 .axiom_root
```

### 1.2 미추적·비무시 (untracked, non-ignored)

명령: `git ls-files --others --exclude-standard | head -50` + 개수

출력: **(빈 — 출력 0줄, 0바이트)**
개수: **0**

### 1.3 무시됨 (ignored)

명령: `git ls-files --others --ignored --exclude-standard | awk -F/ '{print $1}' | sort | uniq -c | sort -rn | head -20` + 총개수

출력 (head -20 — 실제 top-level 종류는 12개):

```
  16274 build
   1319 .nimcache
    997 .axiom
    352 bin
    260 data
    164 tmp
     62 tests
     50 proofs
     14 logs
      2 src
      1 config
      1 .cache
```

총개수: **19,496** — 전체 목록(19,496줄)은 `scratch/inventory3_ignored_all.txt`에 원본 보존

### 1.4 실제 루트 파일시스템

명령: `find . -mindepth 1 -maxdepth 1 -printf '%y %f\n' | sort` — 52 엔트리 전체 (디렉터리 24 · 파일 28):

```
d .axiom
d .cache
d .config
d .git
d .githooks
d .github
d .nimcache
d .opencode
d .worktrees
d _lto_evidence
d bin
d build
d ci
d config
d data
d docs
d experiments
d logs
d proofs
d src
d tests
d tmp
d tools
d vendor
f .axiom_root
f .cursorrules
f .dockerignore
f .editorconfig
f .env.example
f .envrc
f .envrc.example
f .gitattributes
f .gitignore
f AGENTS.md
f Dockerfile.build
f LICENSE
f Makefile
f README.md
f axiom.lock
f axiom.nimble
f axiom.toml
f config.nims
f flake.nix
f lake-manifest.json
f lakefile.toml
f lean-toolchain
f lfs_exceptions.json
f nimble.lock
f promotion_intent.json
f topology.json
f topology.lock
f topology_policy.json
```

---

## 2. Validator 원본 출력 — `make validate-root-layout`

- 실행: 2026-11-04 13:11 KST (pre-make 마커 13:10:43 직후)
- 소요: real 16.7s / user 17.5s / sys 1.4s
- make exit code: **2** — `make: *** [Makefile:401: validate-root-layout] 오류 1`
- 아래는 stdout+stderr 통합 원본 **253줄 전체** (Nim 컴파일 단계 훅 출력 — integrity · hermetic · sync_topology · decision-binding — 포함):

```
nim c --hints:off -o:bin/validate_root_manifest tools/ci/validate_root_manifest.nim
[integrity] merkle concat: sha256sum:sha256sum:sha256sum:sha256sum:
[integrity] expected: 62f0c2f4f71ca83ab8e3688f4bde2b0edea9c9ff1f241b9b78979d6c61f1507b
[integrity] actual:   62f0c2f4f71ca83ab8e3688f4bde2b0edea9c9ff1f241b9b78979d6c61f1507b
[Axiom] Checking feature_manifest.json freshness (content-hash)...
feature_manifest.json ensured fresh
[sync_certs] Manifest fresh (5 entries)
[hermetic] Environment unchanged (HIT)
[hermetic] build_env.nim restored from cache body
[hermetic] Syncing topology...
[sync_topology] Root: .5
[sync_topology] Syncing manifest.d/*.json...
  Manifests: 0 written, 54 unchanged
[sync_topology] Syncing _index.json...
  Index: unchanged
[sync_topology] Syncing manifest_registry.nim...
  Registry: unchanged
[sync_topology] Syncing gate_registry.nim...
  Gate registry: unchanged
[sync_topology] Syncing helper_registry.nim...
  Helper registry: unchanged
[sync_topology] Syncing gates.manifest.toml...
  Manifest TOML: unchanged
[sync_topology] Syncing config/gates.json...
  Gate config: unchanged
[sync_topology] Done.
[hermetic] Checking decision bindings (audit)...
[decision-binding] Loaded 259 active waiver(s) from decision_binding.waiver.json
[decision-binding] Found 50 violation(s)
  parsePropositionsSchema (.5/src/cli/proposition_intake.nim:252) returns Result/Option without axiomDecision
  loadEvidenceRecordForRegister (.5/src/cli/cert_cli.nim:627) returns Result/Option without axiomDecision
  persistRegisteredSubject (.5/src/cli/cert_cli.nim:675) returns Result/Option without axiomDecision
  ledgerHasSubjectCert (.5/src/cli/cert_cli.nim:820) returns Result/Option without axiomDecision
  ledgerRecordConsistentWith (.5/src/cli/cert_cli.nim:1220) returns Result/Option without axiomDecision
  validateCoutOverlayNode (.5/src/cli/axiom_engine.nim:1234) returns Result/Option without axiomDecision
  validateCoutOverlayNode (.5/src/cli/axiom_engine.nim:1259) returns Result/Option without axiomDecision
  validateTomlD2AgentOverlayNode (.5/src/cli/axiom_engine.nim:1538) returns Result/Option without axiomDecision
  validateTomlD2AgentOverlayNode (.5/src/cli/axiom_engine.nim:1558) returns Result/Option without axiomDecision
  validateSidecarOverlayNode (.5/src/cli/axiom_engine.nim:2472) returns Result/Option without axiomDecision
  loadNimSidecarOverlayDomain (.5/src/cli/axiom_engine.nim:2479) returns Result/Option without axiomDecision
  validateSidecarOverlayNode (.5/src/cli/axiom_engine.nim:2494) returns Result/Option without axiomDecision
  capabilityAdapterFor (.5/src/cli/axiom_engine.nim:4481) returns Result/Option without axiomDecision
  parseTrustSurfaceJson (.5/src/cli/merge_cli.nim:754) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  rotationAllowlistOk (.5/src/cli/merge_cli.nim:803) returns Result/Option without axiomDecision
  trustSurfaceOutcome (.5/src/cli/merge_cli.nim:1200) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  MergeAdmissible (.5/src/cli/merge_cli.nim:1233) multiple returns without axiomDecision
  checkedStr (.5/src/cli/merge_cli.nim:1562) multiple returns without axiomDecision
  parseLayerPairRegistry (.5/src/cli/merge_cli.nim:1760) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  loadTrustSurface (.5/src/cli/merge_cli.nim:1860) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  collectCertificateContinuityFacts (.5/src/cli/merge_cli.nim:1963) returns Result/Option without axiomDecision
  parseMergeSuccess (.5/src/cli/merge_cli.nim:2189) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  requestGitHubPut (.5/src/cli/merge_cli.nim:2205) returns Result/Option without axiomDecision
  performMerge (.5/src/cli/merge_cli.nim:2238) returns Result/Option without axiomDecision
  observePullState (.5/src/cli/merge_cli.nim:2282) returns Result/Option without axiomDecision
  resolveMergeShapeApi (.5/src/cli/merge_cli.nim:2351) returns Result/Option without axiomDecision
  resolveMergeShapeLocal (.5/src/cli/merge_cli.nim:2382) returns Result/Option without axiomDecision
  loadLedgerCertFor (.5/src/cli/merge_cli.nim:2420) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  scanLedgerContinuityCertNode (.5/src/cli/merge_cli.nim:2568) returns Result/Option without axiomDecision
  collectCertificateContinuityFacts (.5/src/cli/merge_cli.nim:2632) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  parseActiveKernelSymbols (.5/src/cli/merge_cli.nim:2680) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  vaultManifestIndex (.5/src/cli/merge_cli.nim:2705) returns Result/Option without axiomDecision
  safeSpecRelPath (.5/src/cli/upstream_report_cli.nim:318) multiple returns without axiomDecision
  parseFindingEvidence (.5/src/cli/upstream_report_cli.nim:397) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  selectDisplayBlock (.5/src/cli/upstream_report_cli.nim:439) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  selectReportableUnits (.5/src/cli/upstream_report_cli.nim:453) returns Result/Option without axiomDecision
  evalLinearRhs (.5/src/cli/upstream_report_cli.nim:531) returns Result/Option without axiomDecision
  evalClauseValue (.5/src/cli/upstream_report_cli.nim:555) returns Result/Option without axiomDecision
  classifyGhOutcome (.5/src/cli/upstream_report_cli.nim:784) multiple returns without axiomDecision
  parseIssueView (.5/src/cli/upstream_report_cli.nim:878) returns Result/Option without axiomDecision
  parseIssueRefList (.5/src/cli/upstream_report_cli.nim:893) returns Result/Option without axiomDecision
  decodeGhContentsJson (.5/src/cli/upstream_report_cli.nim:907) returns Result/Option without axiomDecision
  receiptFromJson (.5/src/cli/upstream_report_cli.nim:1144) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  parseUpstreamFlags (.5/src/cli/upstream_report_cli.nim:1281) returns Result/Option without axiomDecision
  loadSpecOverlay (.5/src/cli/upstream_report_cli.nim:1387) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  loadReceipt (.5/src/cli/upstream_report_cli.nim:1403) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  saveReceiptAtomic (.5/src/cli/upstream_report_cli.nim:1418) returns Result/Option without axiomDecision
  verifyCertBinding (.5/src/cli/landing_cli.nim:106) multiple returns without axiomDecision
  fetchPrHead (.5/src/cli/landing_cli.nim:150) returns Result/Option without axiomDecision
  compareStatus (.5/src/cli/landing_cli.nim:167) returns Result/Option without axiomDecision
  validateSubjectPinObject (.5/src/cli/external_subject_registry.nim:227) returns Result/Option without axiomDecision
  validateOwnershipObject (.5/src/cli/external_subject_registry.nim:254) returns Result/Option without axiomDecision
  fromJsonResult (.5/src/core/types/request_result.nim:119) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  changeDescriptorFromJson (.5/src/core/types/candidate_identity.nim:204) returns Result/Option without axiomDecision
  candidateStateIdentityFromJson (.5/src/core/types/candidate_identity.nim:211) returns Result/Option without axiomDecision
  candidateProvenanceFromJson (.5/src/core/types/candidate_identity.nim:218) returns Result/Option without axiomDecision
  verificationContextIdentityFromJson (.5/src/core/types/candidate_identity.nim:233) returns Result/Option without axiomDecision
  candidateEvidenceDigestFromJson (.5/src/core/types/candidate_identity.nim:242) returns Result/Option without axiomDecision
  materializedCandidateFromJson (.5/src/core/types/candidate_identity.nim:251) returns Result/Option without axiomDecision
  materializationRecordFromJson (.5/src/core/types/candidate_identity.nim:263) returns Result/Option without axiomDecision
  fromJson (.5/src/core/types/execution_plan.nim:66) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  fromJson (.5/src/core/types/request_id.nim:32) returns Result/Option without axiomDecision
  countCallDepth (.5/src/core/diagnostics/pattern_guard.nim:247) multiple returns without axiomDecision
  commonAncestorDir (.5/src/core/gate/trust_commit_scope_scan.nim:268) multiple returns without axiomDecision
  parseDerivedSet (.5/src/core/policy/rotation_closure_facts.nim:86) returns Result/Option without axiomDecision
  pinClosureLineSet (.5/src/core/policy/rotation_closure_facts.nim:102) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  verifyRatchetDowngradeSignature (.5/src/core/trusted/ratchet_authority.nim:57) multiple returns without axiomDecision
  validateClaimOwnership (.5/src/core/trusted/bug_attribution_grounds.nim:116) returns Result/Option without axiomDecision
  validateGroundsFile (.5/src/core/trusted/bug_attribution_grounds.nim:378) returns Result/Option without axiomDecision
  containsU64Lit (.5/src/core/trusted/private/ir_to_smt_chunk2.nim:36) multiple returns without axiomDecision
  explicitSpecFromOverlay (.5/src/core/trusted/specification_artifact.nim:68) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  measuredBinaryDigest (.5/src/verification/obligation/measured_digests.nim:56) multiple returns without axiomDecision
  containsIdentToken (.5/src/verification/obligation/canonical_verification.nim:388) multiple returns without axiomDecision
  measureSubjectGitRef (.5/src/verification/obligation/canonical_verification.nim:869) multiple returns without axiomDecision
  measureCompositeCarrierTypename (.5/src/verification/obligation/canonical_verification.nim:1190) multiple returns without axiomDecision
  rejectionToken (.5/src/verification/obligation/candidate_eligibility.nim:97) returns Result/Option without axiomDecision
  canonicalizeEnvValue (.5/src/verification/obligation/identity.nim:53) multiple returns without axiomDecision
  rustTemplateSkeleton (.5/src/verification/rust_obligation_render.nim:111) multiple returns without axiomDecision
  rustExtractorIdentityDigest (.5/src/verification/rust_obligation_render.nim:674) multiple returns without axiomDecision
  loadCASEntryByKey (.5/src/verification/canonical_cache.nim:149) returns Result/Option without axiomDecision
  parseJudgmentSubject (.5/src/verification/judgment_cas.nim:358) returns Result/Option without axiomDecision
  collectChainedDigest (.5/src/verification/judgment_cas.nim:531) returns Result/Option without axiomDecision
  deriveSubjectTreeClosure (.5/src/verification/judgment_cas.nim:563) returns Result/Option without axiomDecision
  collectTestSourceClosure (.5/src/verification/judgment_cas.nim:583) returns Result/Option without axiomDecision
  collectGoldenFixturesDigest (.5/src/verification/judgment_cas.nim:599) returns Result/Option without axiomDecision
  subjectSourceClosure (.5/src/verification/judgment_cas.nim:661) returns Result/Option without axiomDecision
  subjectFixturesDigest (.5/src/verification/judgment_cas.nim:675) returns Result/Option without axiomDecision
  collectRecipeDigest (.5/src/verification/judgment_cas.nim:689) returns Result/Option without axiomDecision
  compilerPinsDigest (.5/src/verification/judgment_cas.nim:695) returns Result/Option without axiomDecision
  collectToolchainBundleDigest (.5/src/verification/judgment_cas.nim:707) returns Result/Option without axiomDecision
  collectJudgmentClosure (.5/src/verification/judgment_cas.nim:806) returns Result/Option without axiomDecision
  validateS1aJudgmentPayloadNode (.5/src/verification/judgment_cas.nim:944) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  validateProofIntegrityPayloadNode (.5/src/verification/judgment_cas.nim:1065) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  validateD2GoldenPayloadNode (.5/src/verification/judgment_cas.nim:1122) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  validateD2PersistPayloadNode (.5/src/verification/judgment_cas.nim:1185) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  validateJudgmentPayloadNode (.5/src/verification/judgment_cas.nim:1235) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  writeJudgmentEvidenceFile (.5/src/verification/judgment_cas.nim:1279) returns Result/Option without axiomDecision
  parseJudgmentEvidenceFile (.5/src/verification/judgment_cas.nim:1305) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  writeSubjectEvidenceFile (.5/src/verification/judgment_cas.nim:1411) returns Result/Option without axiomDecision
  writeProofIntegrityJudgmentEvidenceFile (.5/src/verification/judgment_cas.nim:1431) returns Result/Option without axiomDecision
  buildJudgmentRecord (.5/src/verification/judgment_cas.nim:1723) returns Result/Option without axiomDecision
  validateJudgmentWitnessNode (.5/src/verification/judgment_cas.nim:1779) multiple returns without axiomDecision
  judgmentRootRecordMarkerShape (.5/src/verification/judgment_cas.nim:1813) multiple returns without axiomDecision
  writeJudgmentDecisionFile (.5/src/verification/judgment_cas.nim:1859) returns Result/Option without axiomDecision
  verifyJudgmentReuse (.5/src/verification/judgment_cas.nim:1909) multiple returns without axiomDecision
  runJudgmentAttestBranchForSubject (.5/src/verification/judgment_cas.nim:1954) returns Result/Option without axiomDecision
  runJudgmentAttestBranch (.5/src/verification/judgment_cas.nim:2117) returns Result/Option without axiomDecision
  parseExecutionVerdict (.5/src/verification/judgment_cas.nim:2184) returns Result/Option without axiomDecision
  validateJudgmentExecutionRecord (.5/src/verification/judgment_cas.nim:2244) multiple returns without axiomDecision
  appendExecutionRecord (.5/src/verification/judgment_cas.nim:2327) returns Result/Option without axiomDecision
  validateExtractionJobRecord (.5/src/verification/extraction_provenance.nim:164) multiple returns without axiomDecision
  jobRecordFromJson (.5/src/verification/extraction_provenance.nim:224) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  extractionJobRecordFromPayload (.5/src/verification/extraction_provenance.nim:262) returns Result/Option without axiomDecision
  extractionJobKey (.5/src/verification/extraction_provenance.nim:316) returns Result/Option without axiomDecision
  fileSha256Hex (.5/src/verification/extraction_provenance.nim:330) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  llbcFileDigest (.5/src/verification/extraction_provenance.nim:344) returns Result/Option without axiomDecision
  ledgerCertId (.5/src/verification/ledger_side_ref.nim:77) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  shaFromObject (.5/src/verification/ledger_side_ref.nim:96) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  shaFromNode (.5/src/verification/ledger_side_ref.nim:105) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  ledgerScanIndexFromTree (.5/src/verification/ledger_side_ref.nim:114) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  listEntriesFromTree (.5/src/verification/ledger_side_ref.nim:152) returns Result/Option without axiomDecision
  decodeBlobContent (.5/src/verification/ledger_side_ref.nim:164) returns Result/Option without axiomDecision
  blobEntrySha (.5/src/verification/ledger_side_ref.nim:190) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  fetchTipTree (.5/src/verification/ledger_side_ref.nim:217) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  listLedgerCertIds (.5/src/verification/ledger_side_ref.nim:260) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  listRefEntryNames (.5/src/verification/ledger_side_ref.nim:279) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  openLedgerScanIndex (.5/src/verification/ledger_side_ref.nim:316) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  downloadLedgerCertificateAtBlob (.5/src/verification/ledger_side_ref.nim:370) returns Result/Option without axiomDecision
  downloadLedgerCertificate (.5/src/verification/ledger_side_ref.nim:381) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  validateEvidenceRecord (.5/src/verification/evidence_ledger.nim:167) multiple returns without axiomDecision
  evidenceRecordFromJson (.5/src/verification/evidence_ledger.nim:200) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  evidenceKeysFromNames (.5/src/verification/evidence_ledger.nim:243) returns Result/Option without axiomDecision
  blobShaForKey (.5/src/verification/evidence_ledger.nim:258) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  decodeEvidenceBlob (.5/src/verification/evidence_ledger.nim:281) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  parseEvidenceRecord (.5/src/verification/evidence_ledger.nim:294) returns Result/Option without axiomDecision
  isOid40 (.5/src/verification/admission_artifact.nim:87) multiple returns without axiomDecision
  mintAdmissionPayload (.5/src/verification/admission_artifact.nim:96) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  decodeExecutionIdentityClaims (.5/src/verification/admission_artifact.nim:140) returns Result/Option without axiomDecision
  admissionPayloadDigest (.5/src/verification/admission_artifact.nim:202) returns Result/Option without axiomDecision
  artifactPayloadFromEnvelope (.5/src/verification/admission_artifact.nim:216) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  validateAttestationInputs (.5/src/verification/attestation_orchestrator.nim:266) multiple returns without axiomDecision
  inputsFromJson (.5/src/verification/attestation_orchestrator.nim:299) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  parseAttestationEvidenceText (.5/src/verification/attestation_orchestrator.nim:350) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  reuseIrHashFromPayload (.5/src/verification/attestation_orchestrator.nim:562) returns Result/Option without axiomDecision
  isEarlyReturnIfWire (.5/src/verification/ast_wire.nim:173) multiple returns without axiomDecision
  provenanceValidationError (.5/src/verification/attestation_witness.nim:177) multiple returns without axiomDecision
  semanticValidationError (.5/src/verification/attestation_witness.nim:197) multiple returns without axiomDecision
  parseWitnessBundleText (.5/src/verification/attestation_witness.nim:428) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  signWitness (.5/src/verification/attestation_witness.nim:490) returns Result/Option without axiomDecision
  computeTestClosureDigest (.5/src/verification/verification_query_engine.nim:98) returns Result/Option without axiomDecision
  computeBaselineDigest (.5/src/verification/verification_query_engine.nim:129) returns Result/Option without axiomDecision
  computeLockDigest (.5/src/verification/verification_query_engine.nim:139) returns Result/Option without axiomDecision
  computePolicyDigest (.5/src/verification/verification_query_engine.nim:149) returns Result/Option without axiomDecision
  dependencyDomain (.5/src/verification/producer_identity.nim:73) multiple returns without axiomDecision
  verifyContinuity (.5/src/verification/continuity_check.nim:76) multiple returns without axiomDecision
  verifyContinuityCertDetailed (.5/src/verification/continuity_check.nim:132) multiple returns without axiomDecision
  irBytesEqual (.5/src/verification/extraction_agreement.nim:81) multiple returns without axiomDecision
  normalizeLeanForDifferential (.5/src/verification/renderer_differential.nim:278) multiple returns without axiomDecision
  parseSubjectText (.5/src/verification/subject_store.nim:43) returns Result/Option without axiomDecision
  saveSubject (.5/src/verification/subject_store.nim:54) returns Result/Option without axiomDecision
  loadSubject (.5/src/verification/subject_store.nim:74) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  listSubjects (.5/src/verification/subject_store.nim:87) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  findSubjectsByHeadSha (.5/src/verification/subject_store.nim:106) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  isFullCertClaim (.5/src/verification/cert_reconcile.nim:865) multiple returns without axiomDecision
  parseNimblePkgDirName (.5/src/verification/counterexample_replay.nim:246) returns Result/Option without axiomDecision
  versionRank (.5/src/verification/counterexample_replay.nim:264) returns Result/Option without axiomDecision
  newestPkgDir (.5/src/verification/counterexample_replay.nim:309) returns Result/Option without axiomDecision
  evalConcreteBinOp (.5/src/verification/counterexample_replay.nim:336) returns Result/Option without axiomDecision
  evalConcreteUnaryOp (.5/src/verification/counterexample_replay.nim:390) returns Result/Option without axiomDecision
  evaluatePostconditions (.5/src/verification/counterexample_replay.nim:475) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  parseConcreteLiteral (.5/src/verification/counterexample_replay.nim:488) returns Result/Option without axiomDecision
  decideReplayVerdict (.5/src/verification/counterexample_replay.nim:523) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  ceReplayModulePath (.5/src/verification/counterexample_replay.nim:778) multiple returns without axiomDecision
  subjectTreeNeedsDepRoots (.5/src/verification/counterexample_replay.nim:913) multiple returns without axiomDecision
  isCertifiedNoEffectPath (.5/src/verification/semantic_set_derivation.nim:238) multiple returns without axiomDecision
  parseLsTreeZ (.5/src/verification/semantic_set_derivation.nim:384) returns Result/Option without axiomDecision
  isHexLen (.5/src/verification/semantic_set_derivation.nim:465) multiple returns without axiomDecision
  runGitOrErr (.5/src/verification/semantic_set_derivation.nim:473) returns Result/Option without axiomDecision
  probeTreeResolvable (.5/src/verification/semantic_set_derivation.nim:510) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  listTreeUniverse (.5/src/verification/semantic_set_derivation.nim:524) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  verifyPartition (.5/src/verification/semantic_set_derivation.nim:546) returns Result/Option without axiomDecision
  probeCharonVersion (.5/src/verification/charon_runner.nim:186) multiple returns without axiomDecision
  runPinnedCharonCargo (.5/src/verification/charon_runner.nim:215) multiple returns without axiomDecision
  lowerPostconditionModel (.5/src/verification/batch_uap/ir_pipeline_runner.nim:443) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  isHexOfLen (.5/src/verification/verification_subject.nim:76) multiple returns without axiomDecision
  isValidIso8601Zulu (.5/src/verification/verification_subject.nim:84) multiple returns without axiomDecision
  subjectFromJson (.5/src/verification/verification_subject.nim:202) returns Result/Option without axiomDecision; multiple returns without axiomDecision
  isAxiomAllowed (.5/src/verification/kernel_reexecution.nim:61) multiple returns without axiomDecision
  evaluateObservedAxioms (.5/src/verification/kernel_reexecution.nim:138) multiple returns without axiomDecision
  z3ResultVerdict (.5/src/verification/kernel_reexecution.nim:169) multiple returns without axiomDecision
  loadCertJsonForReexecution (.5/src/verification/kernel_reexecution.nim:203) returns Result/Option without axiomDecision
  reexecuteLean (.5/src/verification/kernel_reexecution.nim:259) multiple returns without axiomDecision
  reexecuteZ3 (.5/src/verification/kernel_reexecution.nim:316) multiple returns without axiomDecision
  subjectCertJournalBind (.5/src/verification/subject_continuity_writer.nim:226) returns Result/Option without axiomDecision
  subjectCertSignAndWrite (.5/src/verification/subject_continuity_writer.nim:234) returns Result/Option without axiomDecision
  readBlobs (.5/src/verification/tested_tree_closure.nim:295) returns Result/Option without axiomDecision
  readBlob (.5/src/verification/tested_tree_closure.nim:357) returns Result/Option without axiomDecision
  lockEntryName (.5/src/verification/tested_tree_closure.nim:394) multiple returns without axiomDecision
  validateVerifierIdentityInputs (.5/src/verification/evidence_cas.nim:267) multiple returns without axiomDecision
  validateEvidenceKeyInputs (.5/src/verification/evidence_cas.nim:328) multiple returns without axiomDecision
  collectChainedFileDigest (.5/src/verification/evidence_cas.nim:365) returns Result/Option without axiomDecision
  collectZ3Pin (.5/src/verification/evidence_cas.nim:389) returns Result/Option without axiomDecision
  collectLeanPin (.5/src/verification/evidence_cas.nim:404) returns Result/Option without axiomDecision
  collectRecipeDigest (.5/src/verification/evidence_cas.nim:421) returns Result/Option without axiomDecision
  collectZ3ChecksumPolicyDigest (.5/src/verification/evidence_cas.nim:428) returns Result/Option without axiomDecision
  collectEvidenceDraftDigest (.5/src/verification/evidence_cas.nim:434) returns Result/Option without axiomDecision
  collectScopeDigest (.5/src/verification/evidence_cas.nim:441) returns Result/Option without axiomDecision
  collectPolicyDigest (.5/src/verification/evidence_cas.nim:448) returns Result/Option without axiomDecision
  collectArtifactDigests (.5/src/verification/evidence_cas.nim:457) returns Result/Option without axiomDecision
  collectVerifierIdentityInputs (.5/src/verification/evidence_cas.nim:473) returns Result/Option without axiomDecision
  markStrictGeneration (.5/src/infrastructure/evidence_artifact_io.nim:264) multiple returns without axiomDecision
  saveCompletenessBinding (.5/src/infrastructure/evidence_artifact_io.nim:392) multiple returns without axiomDecision
  executePlan (.5/src/engine/plan_executor.nim:64) returns Result/Option without axiomDecision
[decision-binding] WARN: 50 function(s) missing {.axiomDecision.} pragma — escalation threshold 30 days not yet reached
bin/validate_root_manifest
FAIL: tmp forbidden
FAIL: .worktrees unknown
FAIL: .nimcache forbidden
FAIL: ci unknown
FAIL: experiments unknown
FAIL: _lto_evidence unknown
FAIL: bin/axiom.nim forbidden (source extension in bin/)
SUMMARY: 7 violation(s) found
make: *** [Makefile:401: validate-root-layout] 오류 1
```

### FAIL 목록 요약 (7건 — 원본에서 발췌)

```
FAIL: tmp forbidden
FAIL: .worktrees unknown
FAIL: .nimcache forbidden
FAIL: ci unknown
FAIL: experiments unknown
FAIL: _lto_evidence unknown
FAIL: bin/axiom.nim forbidden (source extension in bin/)
SUMMARY: 7 violation(s) found
```

---

## 3. Git 상태

### 3.1 `git fetch origin main` (읽기 전용, make 실행 전 — 원본 출력, exit 0)

```
github.com:Archright/Axiom URL에서
 * branch                main       -> FETCH_HEAD
   76efe1fcc..356dbb6b9  main       -> origin/main
```

### 3.2 SHA

- `git rev-parse HEAD`: `76efe1fcccc9e0dd0fc60e3c6e310dad4b63d7fe`
- `git rev-parse origin/main` (fetch 후): `356dbb6b935f02623d7c97a33f5c812912082e8c`
- `git merge-base HEAD origin/main`: `76efe1fcccc9e0dd0fc60e3c6e310dad4b63d7fe`
- 해석: merge-base == HEAD → 로컬 `main`은 `origin/main`의 조상 (behind — fast-forward 가능). fetch가 `origin/main`을 `76efe1fcc..356dbb6b9`로 전진시켰음.

### 3.3 `git status --porcelain` 전/후

- make 실행 전: **0줄 (clean)**
- make 실행 후: **0줄**
- 전후 diff: **없음**
- 해석: validator 산출물은 모두 gitignored 경로(`bin/`, `build/`, `.axiom/`)에 생성됨 → **git이 보는 untracked(비무시) 신규 파일 0개, 추적 파일 수정 0건**.

---

## 4. 카운트

### 4.1 해시 접미 파일 카운트 (make 전/후)

명령: `find bin -maxdepth 1 -type f -printf '%f\n' | grep -E '_[0-9A-Fa-f]{8,}$' | wc -l` + `find bin -maxdepth 1 -type f | wc -l`

make 전:

```
total=353
hash_suffixed=236
total_recursive=353
```

make 후:

```
total=354
hash_suffixed=236
total_recursive=354
```

- 해시 접미 파일: **전 236 → 후 236 (불변)**
- bin 전체 파일 (maxdepth 1): **전 353 → 후 354 (+1)**
- 신규 `bin/validate_root_manifest`는 해시 접미 규칙(`_` + hex 8자 이상 접미)에 해당하지 않음 → `-o:` 고정 출력명이며 해시 카운트 불변.
- 정합 검증: bin/ 353 = 무시 352(§1.3) + 추적 1(`bin/axiom.nim`) + 미추적·비무시 0.

### 4.2 bin 파일 목록 전후 diff (`diff pre_bin_files.txt post_bin_files.txt`)

```
344a345
> validate_root_manifest
```

### 4.3 make 실행으로 생성·수정된 파일 (pre-make 마커 기준, `.git` 제외)

- mtime이 마커(2026-11-04 13:10:43) 이후인 파일 **73개**, 그중 inode birth time이 마커 이후 = **생성 39개**, 기존 inode가 mtime만 갱신 = **수정만 34개** (birth time 미지원 0개).
- 전부 gitignored 경로. git untracked(비무시) 신규 파일 0개.

생성 (39개):

```
./.axiom/cache/hermetic_env_hash.txt
./.axiom/cache/nimcache_leases/860409
./bin/feature_manifest_generator
./bin/validate_root_manifest
./build/nimcache/debug/@mvalidate_root_manifest.nim.c
./build/nimcache/debug/@mvalidate_root_manifest.nim.c.o
./build/nimcache/debug/@palgorithm.nim.c.o
./build/nimcache/debug/@pchecksums@sprivate@ssha_utils.nim.c.o
./build/nimcache/debug/@pchecksums@ssha2.nim.c.o
./build/nimcache/debug/@pcore@strusted@saxiom_pragmas.nim.c.o
./build/nimcache/debug/@phashes.nim.c.o
./build/nimcache/debug/@pjson.nim.c.o
./build/nimcache/debug/@pmath.nim.c.o
./build/nimcache/debug/@pos.nim.c.o
./build/nimcache/debug/@posproc.nim.c.o
./build/nimcache/debug/@pparsejson.nim.c.o
./build/nimcache/debug/@ppathnorm.nim.c.o
./build/nimcache/debug/@pposix.nim.c.o
./build/nimcache/debug/@pstd@sassertions.nim.c.o
./build/nimcache/debug/@pstd@scmdline.nim.c.o
./build/nimcache/debug/@pstd@senvvars.nim.c.o
./build/nimcache/debug/@pstd@soserrors.nim.c.o
./build/nimcache/debug/@pstd@sprivate@sdigitsutils.nim.c.o
./build/nimcache/debug/@pstd@sprivate@soscommon.nim.c.o
./build/nimcache/debug/@pstd@sprivate@sosdirs.nim.c.o
./build/nimcache/debug/@pstd@sprivate@sospaths2.nim.c.o
./build/nimcache/debug/@pstd@sstaticos.nim.c.o
./build/nimcache/debug/@pstd@ssyncio.nim.c.o
./build/nimcache/debug/@pstd@stypedthreads.nim.c.o
./build/nimcache/debug/@pstreams.nim.c.o
./build/nimcache/debug/@pstrtabs.nim.c.o
./build/nimcache/debug/@pstrutils.nim.c.o
./build/nimcache/debug/@psystem.nim.c.o
./build/nimcache/debug/@psystem@sdollars.nim.c.o
./build/nimcache/debug/@psystem@sexceptions.nim.c.o
./build/nimcache/debug/@ptables.nim.c.o
./build/nimcache/debug/@ptimes.nim.c.o
./build/nimcache/debug/@punicode.nim.c.o
./build/nimcache/debug/validate_root_manifest.json
```

수정만 (34개):

```
./build/nimcache/debug/@palgorithm.nim.c
./build/nimcache/debug/@pchecksums@sprivate@ssha_utils.nim.c
./build/nimcache/debug/@pchecksums@ssha2.nim.c
./build/nimcache/debug/@pcore@strusted@saxiom_pragmas.nim.c
./build/nimcache/debug/@phashes.nim.c
./build/nimcache/debug/@pjson.nim.c
./build/nimcache/debug/@pmath.nim.c
./build/nimcache/debug/@pos.nim.c
./build/nimcache/debug/@posproc.nim.c
./build/nimcache/debug/@pparsejson.nim.c
./build/nimcache/debug/@ppathnorm.nim.c
./build/nimcache/debug/@pposix.nim.c
./build/nimcache/debug/@pstd@sassertions.nim.c
./build/nimcache/debug/@pstd@scmdline.nim.c
./build/nimcache/debug/@pstd@senvvars.nim.c
./build/nimcache/debug/@pstd@soserrors.nim.c
./build/nimcache/debug/@pstd@sprivate@sdigitsutils.nim.c
./build/nimcache/debug/@pstd@sprivate@soscommon.nim.c
./build/nimcache/debug/@pstd@sprivate@sosdirs.nim.c
./build/nimcache/debug/@pstd@sprivate@sospaths2.nim.c
./build/nimcache/debug/@pstd@sstaticos.nim.c
./build/nimcache/debug/@pstd@ssyncio.nim.c
./build/nimcache/debug/@pstd@stypedthreads.nim.c
./build/nimcache/debug/@pstreams.nim.c
./build/nimcache/debug/@pstrtabs.nim.c
./build/nimcache/debug/@pstrutils.nim.c
./build/nimcache/debug/@psystem.nim.c
./build/nimcache/debug/@psystem@sdollars.nim.c
./build/nimcache/debug/@psystem@sexceptions.nim.c
./build/nimcache/debug/@ptables.nim.c
./build/nimcache/debug/@ptimes.nim.c
./build/nimcache/debug/@punicode.nim.c
./build/nimcache/debug/feature_manifest_generator.json
./src/generated/build_env.nim
```

비고:
- `bin/feature_manifest_generator` — 파일명은 make 전부터 존재(전후 목록 동일)하나 inode가 make 중 재생성(재빌드; 컴파일 훅의 feature_manifest fresh 검사 단계).
- `src/generated/build_env.nim` — **추적 파일**이나 porcelain 변화 없음 = 내용 동일 복원("[hermetic] build_env.nim restored from cache body"). 추적 파일 내용 수정 0건.
- `bin/validate_root_manifest` — 본 슬라이스 validator 산출물 (신규, make 전 미존재 확인).

---

## 5. 종합

P0 baseline 관측 시점(2026-11-04, HEAD `76efe1fccc`)에서 `make validate-root-layout`은 **exit 2 · FAIL 7건** — `tmp` forbidden, `.worktrees`/`ci`/`experiments`/`_lto_evidence` unknown, `.nimcache` forbidden, `bin/axiom.nim` forbidden. Filesystem Contract V1 미충족 상태가 baseline이다. 해시 접미 파일 236개(전/후 불변), bin 총 파일 353→354. validator 실행은 git 상태를 오염시키지 않는다 (추적·비무시 파일 0건 변화, 산출 전부 무시 경로). 병렬 관찰: 컴파일 훅의 decision-binding 감사가 함수 50건 `axiomDecision` 프래그마 미부착 WARN(escalation 임계 30일 미도달)을 baseline으로 함께 기록했다.
