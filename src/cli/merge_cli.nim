import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}

## Merge Admission Controller — `ax merge <PR-number>`.
##
## Decides deterministically whether a PR head is admissible to merge.
## Axiom is the single admission predicate producer; GitHub (ruleset +
## required status check) is the sole merge ENFORCEMENT authority. There is
## no in-CLI ruleset adjudication lane.
## Architecture (docs/spec/merge_admission_controller.md):
##
##   collectAdmissionFacts(H)  →  AdmissionFacts(H)  →  MergeAdmissible(V, mainSha)
##   (I/O: each logical fact   (immutable snapshot;   (pure predicate; consumes the
##    source fetched once)      Option — None = deny)   snapshot once, never re-fetches)
##
## Admission invariants:
## * **Snapshot identity**: every PR-derived fact is bound to the PR head SHA H
##   observed at collection start; the predicate consumes the snapshot once.
## * **missing ≠ valid empty**: facts absent from the record (Option[AdmissionFacts]
##   = None, or an empty required-validations set) deny — never read as "clean".
## * **Platform check evidence (GitHub delegation, P12)**: required-check
##   presence/passing conclusions, workflow identity binding and verdict-job
##   evidence are GitHub's authority at merge time (ruleset required status
##   checks `admission-check`; merge-queue re-evaluation — ADR-0027 P5) —
##   this predicate never re-derives them. The legacy required-validations double
##   binding (Pass 0–2.6), the v1.8.0 required-workflow verdict pass, the A2
##   ruleset pre-flight and the M12 stale re-check were removed as
##   duplicate re-implementations of those platform guarantees.
## * **Base freshness (single freshness predicate)**: the candidate's verified
##   base `V.baseSha` MUST equal the declared main tip `mainSha` — unrecorded
##   (BASE_UNRECORDED) and mismatched (STALE_BASE) both deny. This binding is
##   PROVENANCE only, not a freshness decision — freshness enforcement on the
##   landing path is merge-queue invalidation ALONE (ADR-0027 P5, strict
##   retired 2026-10-05; Axiom is admission authority only). `V.baseSha` is
##   the EVENT-FROZEN anchor
##   (AXIOM_MAIN_SHA), not the live PR API `base.sha`: the queue advances the
##   base while the PR snapshot lags behind it, so a live anchor made every
##   landing PR invalidate every other open PR (STALE_BASE false deny).
## * **Rotation/closure adjudication (Phase 4, ADR-0025 §7/§13 + Amendment F
##   2026-10-12)**: when the org gate supplies derived closure line-files
##   (AXIOM_DERIVED_H_PATH / AXIOM_DERIVED_B_PATH / AXIOM_DERIVED_M_PATH —
##   deriver format; M = the candidate tree merge-tree(B, H) whose equality
##   with the tested landing candidate the gate verified) + the H-side pin
##   (AXIOM_PIN_H_PATH), the SUBJECT CLASS is the PR's own candidate delta:
##   closureChange = (derived(M) != derived(B)) → ROTATION, else NORMAL.
##   Base drift (set(H) vs set(B) differences the PR never made) does not
##   enter the classification. A rotation subject still admits only when every
##   condition holds (① changed ⊆ pin@B keys ∪ docs/adr/** ∪ pin file ∪ A2
##   companions, ② subject Δ=0, ③ old anchor == derived(B) or genesis 1회,
##   ④ new anchor == derived(H), ⑤ approval delegated to GitHub CODEOWNERS);
##   any failure = NOT-ADMIT (ROT_* codes). ③ is evaluated on EVERY path
##   (classification-independent fact) and denies here (ROT_OLD_PIN); ④ is
##   evaluated on every path and denies ONLY at Pass 2.75. Env absent
##   (UNSPECIFIED) → verdict fail-closes (ROT_UNSPECIFIED — the committed
##   verdict-stage contract). Run-level input failures — not verdicts — exit
##   non-zero. Pure core: adjudicateRotation (tested).
## * **Vault-certificate pass (Pass 2.96b, proof-required admission contract
##   docs/spec/proof_required_admission_contract.md)**: the sibling of Pass
##   2.96 — when vaultCertRequired, every in-scope kernel symbol carrying a
##   vault manifest entry demands an EXISTING vault cert with content
##   irHash == manifest identity, and the policy-epoch equalities
##   (sha256(policy)@B == local, sha256(scope)@B == local) hold exactly.
##   Reason vocabulary = journal strings NO_CERT/SUBJECT_MISMATCH/
##   POLICY_MISMATCH/SCOPE_MISMATCH (no new enum/gate/authority). Order:
##   2.96 → 2.96b → 2.97.
## * **Trust surface**: a PR whose changed files (or rename sources) touch the
##   admission trust surface requires manual merge (auto-merge denied). The
##   surface is evaluated at runtime from the policy SSOT
##   (config/policy/merge_admission.json) read from the workspace cwd — the B
##   checkout in the verdict job, so a PR editing the policy cannot
##   re-classify itself — unioned with the compiled protection-retention
##   tombstones (loadTrustSurface).
## * **RL-14.4 layer admissibility (M-41, S5)**: a changed/added `src/core/**`
##   file that introduces a forbidden-layer import (verification/ cli/ mcp/
##   ui/ gate/) NOT covered by an approved (source, target) pair denies
##   (LAYER_FORBIDDEN_IMPORT / LAYER_IMPORT_UNPARSED; collection failure =
##   UNKNOWN = LAYER_ADMISSIBILITY_UNKNOWN — fail-closed). Judging reuses the
##   trusted SSOT (layer_rules normalization contract + isAllowedImport) with
##   the workspace architecture_policy.lock pair registry injected at the I/O
##   boundary — GitHub enforces because the admission-check conclusion IS the
##   dry-run exit.
## * **Stale evaluation**: the verdict applies to H only; if the PR head moved
##   by evaluation end, the evaluation is stale and denies.
## * **Base freshness**: `--match-head-commit` is an atomic guard for HEAD;
##   base freshness is asserted by this predicate against the current main tip
##   it was handed (`mainSha`) — a pre-merge observation, not an atomic
##   compare-and-swap; landing-path enforcement is the merge queue's own
##   invalidation (ADR-0027 P5).

import std/[os, osproc, json, strutils, httpclient, times, options, sets, algorithm]
import core/axiom_pragmas
import core/crypto/hash_kernel
import core/results
import core/parsers/safe_parsers
import core/policy/change_graph_facts
import core/policy/rotation_closure_facts
## Hub re-export (the core/results.nim idiom): the rotation parsing
## primitives and RotationPinBPath/RotationPinKey moved to the shared leaf
## module, and merge_cli stays the consumer-facing surface for them.
export rotation_closure_facts
import infrastructure/certificate_attestation
import infrastructure/logging_facade
import core/interfaces/git_operations
import verification/certificate_verifier
import verification/kernel_reexecution
import verification/ledger_side_ref
import verification/subject_store
import verification/verification_subject
import verification/extraction_agreement
import verification/continuity_check
import core/trusted/layer_rules
import core/trusted/layer_enforcement
# ---------------------------------------------------------------------------
# Required validation — policy SSOT mirror (config/policy/merge_admission.json
# v1.19.0, ADR-0035 + ADR-0036 + hybrid authority rotation): the required
# check contexts are the live five ('admission-check', 'bsec-integrity',
# 'debt-registry-gate', 'generation-acceptance', 'axiom-operational-slice' —
# the resolved "main" ruleset's required_status_checks, all integration_id
# 15368 = the GitHub Actions app — the app-level producer control).
# Check-evidence evaluation is GitHub's ruleset authority at merge time (P12
# delegation) — these constants are retained as the canonical identity
# declaration, NOT as a merge-time re-verification. proof_unit_
# consistency_gate (f.3) still asserts the required-workflow-ids block is
# non-empty (source-level standing invariant). The ruleset itself is
# identified by NAME resolution ("main") since the hybrid authority
# rotation — the numeric ruleset id 20303214 belonged to the OLD repository
# (preserved as <legacy-repo>) and 404s under the recreated one
# (observed: 26702792, 2026-11-07).
# ---------------------------------------------------------------------------
const
  RequiredChecks*: seq[string] = @[
    "admission-check",
    "bsec-integrity",
    "debt-registry-gate",
    "generation-acceptance",
    "axiom-operational-slice",
    "publication-integrity",
  ]
  ## Repo-native producer identities — the Axiom-side identity mirror of the
  ## platform's app-level control (integration_id 15368). NOT a merge-time
  ## re-verification: the predicate deliberately does not collect check-runs
  ## nor re-verify producer identity (ADR-0025 Amendment B / P12; ADR-0035 §1).
  ## admission-check's CONTEXT producer is the ORG-INJECTED workflow
  ## Archright/.github admission-gate-v2.yml (repository_id 1182157951,
  ## sha-pinned by org ruleset 25218071) — it is not expressible as a repo
  ## workflow and is recorded in the policy SSOT's
  ## requiredWorkflowDetection.
  ## HYBRID AUTHORITY ROTATION (policy v1.19.0, 2026-11-07): the binding
  ## identity is the workflow PATH — a repository-scoped numeric workflow id
  ## is reassigned whenever the repository is recreated (clean-origin
  ## migration measured 2026-11-07: all four pre-migration ids 404 under
  ## repos/Archright/Axiom and resolve only under the preserved archive),
  ## so the ids survive in the policy SSOT as workflowIdObservation
  ## {value, observedAt} records (bsec-integrity 409432614,
  ## debt-registry-gate 409432630, generation-acceptance 409432642,
  ## axiom-operational-slice 409432611 — observed 2026-11-07T05:23:47Z).
  ## This block keeps its historical name RequiredWorkflowIds because
  ## proof_unit_consistency_gate (f.3) pins that identifier as the standing
  ## non-emptiness invariant; the drift monitor compares it with the policy's
  ## (job -> workflowPath) bindings — the two sides must be updated in the
  ## SAME commit (one-sided update turns the drift monitor leg 1 RED).
  RequiredWorkflowIds*: seq[tuple[jobName: string, workflowPath: string]] = @[
    ("bsec-integrity", ".github/workflows/bsec-integrity.yml"),
    ("debt-registry-gate", ".github/workflows/debt-registry-gate.yml"),
    ("generation-acceptance", ".github/workflows/generation-acceptance.yml"),
    ("axiom-operational-slice", ".github/workflows/axiom-operational-slice.yml"),
    # v1.20.0 (2026-11-09): publication-integrity — the single publication
    # readiness verdict (5 dimension sub-jobs aggregated). workflowIdObservation
    # is a post-push readback record in the policy SSOT; the PATH is the
    # primary binding (hybrid authority rotation, v1.19.0).
    ("publication-integrity", ".github/workflows/publication-integrity.yml"),
  ]
  DefaultRepo*: string = "Archright/Axiom"
  ## Certified-admission policy key (certification-continuity Phase 5, INV-1):
  ## true = this admission DEMANDS a subject-continuity ledger certificate.
  ## Mirrors config/policy/merge_admission.json ("certRequired") — update
  ## together. Missing ≠ valid empty (spec §2).
  CertRequired*: bool = true
  ## Proof-required admission policy key (docs/spec/
  ## proof_required_admission_contract.md §2.1): true = this admission DEMANDS
  ## valid vault certificates for in-scope kernel symbols that carry a vault
  ## manifest entry (Pass 2.96b — the sibling of Pass 2.96, not an extension
  ## of it). Mirrors config/policy/merge_admission.json ("vaultCertRequired")
  ## — update together (the mirror gate enforces the pair).
  VaultCertRequired*: bool = true
  ## Rotation/closure adjudication (ADR-0025 §7/§13, plan Phase 4) — env-gated
  ## inputs. The org gate supplies the deriver's closure line-files plus the
  ## H-side pin; env absent = qualification UNSPECIFIED → the verdict
  ## fail-closes (ROT_UNSPECIFIED). Mirrors the gate's derived-sets contract —
  ## config/policy/merge_admission.json has no field for this (B-built code
  ## only, no new authority).
  EnvDerivedHPath*: string = "AXIOM_DERIVED_H_PATH"
  EnvDerivedBPath*: string = "AXIOM_DERIVED_B_PATH"
  ## Candidate-delta classification input (ADR-0025 Amendment F, 2026-10-12):
  ## the DERIVED closure line-set OF the candidate tree M — the gate supplies
  ## it only after machine-verifying M == tree(the tested landing candidate).
  EnvDerivedMPath*: string = "AXIOM_DERIVED_M_PATH"
  EnvPinHPath*: string = "AXIOM_PIN_H_PATH"
  ## RotationPinBPath / RotationPinKey live in the shared rotation-facts leaf
  ## module (core/policy/rotation_closure_facts) — ONE compiled implementation
  ## with the rotation preflight checker.
  RotationAdrGlob*: string = "docs/adr/**"
  ## ADR-0025 Amendment A2 (2026-09-27, merge 88be7a442): 회전 allowlist 최소
  ## 정합 집합. Current §13 list(아래 rotationAllowlistOk)는 회전 PR이 반드시
  ## 동반하는 파일들을 원리적으로 배제한다 — tws↔admission-check.yml ATOMICITY
  ## 페어(landing-integrity), check-debt의 architecture_debt rawContentHash
  ## 재생성, 회전 테스트 동반 — active 게이트 아래 회전 PR 착지 불가(PR #295
  ## STOP-BLOCKED 실측). A2는 아래 6개 경로를 회전 동반 변경 허용 집합으로
  ## 확정한다. NON-member production src/ 변경은 여전히 allowlist 밖 (A2 (i)).
  ## A2 확장 (plan Phase 2, trust-layer-isolation): the RequiredPolicy SSOT
  ## config/policy/landing_required_gateway_tests.json (mustRef/testPath
  ## entries) is a rotation companion — a rotation PR creating or updating it
  ## must not deadlock the rotation allowlist (same fix class as A2).
  ## A2 확장 (2026-10-10, same fix class — rotation-PR deadlock 실측 PR #699):
  ## config/policy/epoch_manifest.json is the THIRD leg of the pin atomicity
  ## triple. The epoch gate (tools/ci/epoch_transaction_gate.nim) fail-closes
  ## on `productionExecutionPin != trustedAdmissionWorkflowSha`, so every
  ## legitimate admission-workflow pin rotation MUST touch it in the same
  ## commit alongside trusted_writer_set.json and admission-check.yml. It was
  ## the one mandatory rotation companion missing from this set, which made
  ## queue-path rotation impossible (ROT_ALLOWLIST on exactly this path,
  ## merge_group verdict 2026-10-10 — the other two paths were already
  ## allowlisted). Adding it completes A2's stated purpose ("회전 PR이 반드시
  ## 동반하는 파일들을 원리적으로 배제한다 ... 착지 불가") rather than widening
  ## trust: the file is a pin twin, not production source. NON-member
  ## production src/ remains outside (A2 (i)).
  ## A2 확장 (2026-10-12, same fix class — ROT_ALLOWLIST 실측 merge_group
  ## verdict on PR #780): the candidate-delta rotation (ADR-0025 Amendment F)
  ## accompanies exactly these nine non-member files — the rotation tests
  ## (tests/ci/test_sl02_consumer_binding.nim 5-file contract, tests/ci/
  ## test_derive_checker_closure.nim --tree leg), the reproducibility
  ## contracts and their evidence (docs/spec/certification_continuity_
  ## contract.md §11 git pin, docs/spec/github_delegation_residuals.md
  ## parameter roles, docs/evidence/s1-stale-base-repro-2026-10-12.md), the
  ## depth-1 gate's clause-3 contract (tools/ci/git_access_scan.sh), the
  ## ALLGREEN policy expectation (tools/merge_ruleset_drift_monitor.nim +
  ## tests/unit/test_merge_ruleset_drift_monitor.nim), and the budget ledger
  ## reconciliation (data/debt_ledger.json). Each is either a test/contract
  ## of the rotation machinery or the ledger data the rotation's own gates
  ## read — the same "mandatory companion" class as A2/2026-10-10, not
  ## production source. NON-member production src/ remains outside (A2 (i)).
  ## data/quality_gate_baseline.json (2026-10-14): the Static-First ratchet
  ## baseline the quality-gate checker reads; a substantive PR that honestly
  ## improves member files and re-freezes its scoped groups (runner's
  ## --files --update-baseline path) rotates the closure AND accompanies its
  ## own baseline — the same mandatory-companion class as nimtry_baseline
  ## (nimtry_evaporate §3.0-9 precedent, U01 measured basis).
  ## INV-9 claim-integrity artifacts (2026-10-14): the forbidden-claim
  ## sentence scanner set (library + CI runner + allowlist data + tests,
  ## ADR-0030 U2) is NOT product source — no ax prove surface; the scanner
  ## consumes certificate-adjacent artifacts only. Its first landing is
  ## atomically bound to the layer_rules crossing pair that admits the
  ## runner's import, i.e. to a closure rotation — the same
  ## rotation-machinery contract/test companion class as test_merge_cli /
  ## derive_checker_closure tests, not the A2 (i) excluded production-src
  ## class.
  ## A5 (2026-10-14, rust lane landing — PR #827): 검증 대상 범위 확장(rust certified subset) 동반 회전 경로. 열거형만 — glob 없음(ADR-0025 A4 규율 준수).
  ## A2 확장 (2026-10-17, same fix class — ROT_NEW_PIN + ROT_ALLOWLIST 실측
  ## merge_group verdict on PR #895, MG run 38997388474): MG 착지 판정 증거
  ## 게이트 착지(Nim 계층 48a33ede4 + admission-check.yml 신세대 blob
  ## 1c9848a7)의 candidate delta는 클로저 멤버 2개(src/verification/
  ## judgment_cas.nim, src/cli/cert_cli.nim)를 변경하므로 ROTATION으로
  ## 분류되며, 그 동반 4경로가 이 열거형 밖이라 ① 어노테이션(allowlistOk
  ## false)이 관측됐다. 회전 기계의 테스트/계약/증거 동반 클래스로 수록한다 —
  ## A2 2026-10-12·A4(PR #826)·INV-9(3c9cffd0d)와 동일 fix class:
  ## tests/unit/test_judgment_cas.nim(회전 멤버의 단위 계약 — test_merge_cli·
  ## test_derive_checker_closure 동일 클래스),
  ## docs/evidence/mg_evidence_gate_prereg_2026-10-17.md(본 회전의 사전등록 —
  ## rotation_allowlist_a5_prereg 동일 클래스),
  ## docs/evidence/ci_epoch_record_mg_evidence_gate_2026-10-17.md(§2.5 세대
  ## 기록 — s1-stale-base-repro 동일 클래스). 열거형만 — glob 없음(A4 규율).
  ## 비멤버 production src/는 계속 밖(A2 (i)). data/benchmarks/perf_latest.json은
  ## 버전 관리 밖의 실행 아티팩트(gitignored — perf-artifact policy)라 멤버가 아니다.
  RotationAllowlistExtra*: seq[string] = @[
    ".github/workflows/admission-check.yml",
    ".github/workflows/certificate-mint.yml",
    "data/architecture_debt.json",
    "data/debt_ledger.json",
    "data/nimtry_baseline.json",
    "data/quality_gate_baseline.json",
    "docs/evidence/s1-stale-base-repro-2026-10-12.md",
    "docs/spec/certification_continuity_contract.md",
    "docs/spec/github_delegation_residuals.md",
    "tests/cli/test_merge_cli.nim",
    "tests/ci/test_derive_checker_closure.nim",
    "tests/ci/test_sl02_consumer_binding.nim",
    "tests/unit/test_merge_ruleset_drift_monitor.nim",
    "tests/verification/test_attestation.nim",
    "tools/ci/git_access_scan.sh",
    "tools/merge_ruleset_drift_monitor.nim",
    "config/policy/landing_required_gateway_tests.json",
    "config/policy/epoch_manifest.json",
    "src/verification/forbidden_claim_scan.nim",
    "tools/ci/check_inv9_forbidden_claims.nim",
    "tools/ci/inv9_forbidden_claim_allowlist.json",
    "tests/verification/test_forbidden_claim_scan.nim",
    "data/verification_scope.lock",
    "docs/evidence/rotation_allowlist_a5_prereg_2026-10-14.md",
    "docs/spec/rust_certified_subset.md",
    "docs/spec/rust_toolchain_quirks.md",
    "src/cli/rust_lane_cli.nim",
    "src/verification/charon_runner.nim",
    "tests/fixtures/rust/axiom_rust_probe/Cargo.lock",
    "tests/fixtures/rust/axiom_rust_probe/Cargo.toml",
    "tests/fixtures/rust/axiom_rust_probe/README.md",
    "tests/fixtures/rust/axiom_rust_probe/axiom.specs.json",
    "tests/fixtures/rust/axiom_rust_probe/axiom_rust_probe.llbc",
    "tests/fixtures/rust/axiom_rust_probe/src/lib.rs",
    "tests/gateway/rust_lane_cli_acceptance_test.nim",
    "tests/gateway/rust_subject_provenance_issuance_test.nim",
    "tests/gateway/rust_subject_three_cases_test.nim",
    "tests/unit/test_charon_runner.nim",
    "docs/evidence/ci_epoch_record_mg_evidence_gate_2026-10-17.md",
    "docs/evidence/mg_evidence_gate_prereg_2026-10-17.md",
    "tests/unit/test_judgment_cas.nim",
    "tests/unit/test_judgment_set_derivation.nim",
    "docs/evidence/ci_epoch_record_mg_reuse_eligibility_2026-10-18.md",
    "docs/evidence/rotation_allowlist_guard_obligation_prereg_2026-10-18.md",
    ".gitignore",
    "Makefile",
    "tests/fixtures/rust/axiom_guard_probe/Cargo.lock",
    "tests/fixtures/rust/axiom_guard_probe/Cargo.toml",
    "tests/fixtures/rust/axiom_guard_probe/README.md",
    "tests/fixtures/rust/axiom_guard_probe/axiom_guard_probe.llbc",
    "tests/fixtures/rust/axiom_guard_probe/src/lib.rs",
    "tests/unit/test_rust_guard_attempt.nim",
    "tests/unit/test_theater_allowlist_structure.nim",
    "tests/unit/test_rust_replay_adapter.nim",
    "docs/evidence/rotation_allowlist_guard_confirmation_prereg_2026-10-19.md",
    "docs/spec/replay_evidence_policy.md",
    "docs/evidence/rotation_allowlist_replay_evidence_prereg_2026-10-19.md",
    "docs/agents/report-guardrails.md",
    "tests/unit/test_vkd_ssot_invariant.nim",
    "docs/evidence/rotation_allowlist_post_vkd_prereg_2026-10-19.md",
    "src/core/policy/rotation_closure_facts.nim",
    "tools/ci/rotation_pin_anchor_check.nim",
    "tests/ci/test_rotation_pin_anchor_check.nim",
    "docs/evidence/rotation_preflight_prereg_2026-10-20.md",
    "docs/evidence/rotation_allowlist_vs1_preflight_prereg_2026-10-20.md",
    "src/verification/tested_tree_closure.nim",
    "docs/spec/test_judgment_cas_contract.md",
    # ADR-0035 회전 동반 (2026-10-21, required-check SSOT 정합): 이 회전은
    # 클로저 멤버(src/cli/merge_cli.nim — 본 파일)의 내용을 바꾸므로
    # candidate-delta 분류가 ROTATION이다. 동반 4경로는 모두 "회전 기계의
    # 계약/증거/정책 동반 클래스" — production src/가 아니며 A2 (i)의
    # NON-member production src/ 금지 클래스가 아니다:
    # config/policy/merge_admission.json(정책 SSOT — 판정 참조용 기록의
    #   정규 원본; v1.15.0에서 requiredValidations 정합),
    # docs/adr/0035-admission-ssot.md(근거 문서 — SSOT 분담 기록),
    # .github/workflows/admission-ssot-drift.yml(상시 드리프트 감지 —
    #   required check가 아님; 사후 관측),
    # docs/evidence/org-self-venue-expected-failure-2026-10-21.md(P1 기록 —
    #   비권위적 실패의 수용 근거).
    # 핀 파일(config/trusted_writer_set.json)은 RotationPinBPath로 이미 허용.
    # 열거형만 — glob 없음(A4 규율); 비멤버 production src/는 계속 밖(A2 (i)).
    "config/policy/merge_admission.json",
    "docs/adr/0035-admission-ssot.md",
    ".github/workflows/admission-ssot-drift.yml",
    "docs/evidence/org-self-venue-expected-failure-2026-10-21.md",
    # ADR-0036 회전 동반 (2026-10-22, GPA v1): 이 회전도 클로저 멤버
    # (src/cli/merge_cli.nim — 본 파일)의 내용을 바꾸므로 candidate-delta
    # 분류가 ROTATION이다. 동반 2경로는 "회전 기계의 계약/정책 동반 클래스" —
    # production src/가 아니며 A2 (i)의 NON-member production src/ 금지
    # 클래스가 아니다:
    # .github/workflows/generation-acceptance.yml(신규 승격 acceptance 게이트 —
    #   Driver/Candidate 분리, L1~L4 판정; required check로 승격되는 산출물
    #   그 자체이므로 정책 SSOT v1.16.0의 trustSurface에도 등재됨),
    # tools/promotion/validate_manifest.sh(승격 manifest의 관계 검증 도구 —
    #   필드 존재가 아니라 run↔SHA↔readback↔merge 연결을 검사).
    # 근거 문서(docs/adr/0036-generation-promotion-acceptance.md)는
    # RotationAdrGlob(docs/adr/**)로 이미 허용된다.
    # 핀 파일(config/trusted_writer_set.json)은 RotationPinBPath로 이미 허용.
    # 열거형만 — glob 없음(A4 규율); 비멤버 production src/는 계속 밖(A2 (i)).
    ".github/workflows/generation-acceptance.yml",
    "tools/promotion/validate_manifest.sh",
    # ADR-0037 회전 동반 (2026-10-22, operational-slice required check SSOT
    # 정합): 이 회전도 클로저 멤버(src/cli/merge_cli.nim — 본 파일)의 내용을
    # 바꾸므로 candidate-delta 분류가 ROTATION이다. 동반 경로는 "회전 기계의
    # 계약/증거/정책 동반 클래스" — production src/가 아니며 A2 (i)의 NON-member
    # production src/ 금지 클래스가 아니다:
    # config/policy/merge_admission.json — 정책 SSOT(requiredValidations +
    #   trustSurface 동반 갱신; 이미 허용됨 — 여기 재열거는 근거 기록),
    # data/promotions/axiom-operational-slice-activation/manifest.json —
    #   operator ruleset PUT의 승격 manifest(관계 검증 도구
    #   tools/promotion/validate_manifest.sh의 검증 대상).
    # .github/workflows/axiom-operational-slice.yml 자체는 본 회전의 delta에
    # 없다(PR #1040에서 이미 착지) — 본 회전은 그것을 required로 등록하는
    # 정책/거울 회전이다. ADR 문서는 RotationAdrGlob(docs/adr/**)으로 허용.
    # 핀 파일(config/trusted_writer_set.json)은 RotationPinBPath로 이미 허용.
    # 열거형만 — glob 없음(A4 규율); 비멤버 production src/는 계속 밖(A2 (i)).
    "data/promotions/axiom-operational-slice-activation/manifest.json"]
  ## VS-1 회전핀 프리플라이트 (2026-10-20): H2(④) 판정을 리프 모듈
  ## core/policy/rotation_closure_facts로 추출해 착지 predicate와 PR-head
  ## 오라클(tools/ci/rotation_pin_anchor_check.nim)이 **하나의 컴파일 구현**을
  ## 공유한다. 신규 클로저 멤버 1경로 + 비멤버 오라클/테스트/사전등록 4경로.
  ## 사전등록: docs/evidence/rotation_allowlist_vs1_preflight_prereg_2026-10-20.md
  ## (게이트 계약: docs/evidence/rotation_preflight_prereg_2026-10-20.md).
  ## 열거형만 — glob 없음(A4 규율).
  ## v5 회전 (2026-10-21 — judgment 증거 정체성 세대 컷): 클로저 멤버
  ## src/verification/judgment_cas.nim(①③ M-tree 유도) + 신규 클로저 멤버
  ## src/verification/tested_tree_closure.nim(①③ 도출 권위)의 ④ 재앵커 +
  ## 동반 2경로(계약 문서 docs/spec/test_judgment_cas_contract.md — v1.0.5
  ## 개정, workflow .github/workflows/admission-check.yml은 이미 열거됨 —
  ## A2 triple 포함). 열거형만 — glob 없음(A4 규율); 비멤버 production src/는
  ## 계속 밖(A2 (i)).
  ## post-vkd 회전 (2026-10-19 세 번째 — #936/#950 시대 일관성 스윕): 클로저
  ## 멤버 src/cli/shared/proof_hydration.nim(dead tryWriteBackL1Cache 삭제·주석
  ## 정정) ④ 재앵커 + 동반 2경로(가드레일 문서 정정·동면 ssot 테스트 주석) +
  ## 본 회전 사전등록. 사전등록:
  ## docs/evidence/rotation_allowlist_post_vkd_prereg_2026-10-19.md.
  ## 열거형만 — glob 없음(A4 규율); 비멤버 production src/는 계속 밖(A2 (i)).
  ## replay-evidence 회전 (2026-10-19 두 번째, A/B/C 보강: 귀속·BuildInvocation·
  ## G2 문구): 클로저 멤버 rust_rust_pipeline.nim(귀속 제약 쿼리·구체 검사)·
  ## rust_replay_adapter.nim(BuildInvocation·기록 검사)·rust_lane_cli.nim(로그)의
  ## ④ 재앵커 + 동반 2경로(신규 등급 계약 문서·본 회전 사전등록). 사전등록:
  ## docs/evidence/rotation_allowlist_replay_evidence_prereg_2026-10-19.md.
  ## 열거형만 — glob 없음(A4 규율); 비멤버 production src/는 계속 밖(A2 (i)).
  ## guard-confirmation 회전 (2026-10-19 — A-슬라이스: overflow 확인의 계약
  ## 정합 투영, Option A 유지): 클로저 멤버 src/cli/axiom_engine.nim(§10
  ## projectAbs 절대화)·src/cli/rust_lane_cli.nim·src/verification/
  ## rust_rust_pipeline.nim(확인 투영)·rust_replay_adapter.nim(프로파일/panic)의
  ## ④ 재앵커 + 동반 2경로(테스트 단위 계약 test_rust_replay_adapter —
  ## test_judgment_cas 동일 클래스, 본 회전 사전등록). 사전등록:
  ## docs/evidence/rotation_allowlist_guard_confirmation_prereg_2026-10-19.md.
  ## 열거형만 — glob 없음(A4 규율); 비멤버 production src/는 계속 밖(A2 (i)).
  ## guard-obligation 회전 (2026-10-18, PR #919 — ROT_NEW_PIN + allowlist
  ## 실측 해소, 62dbeab8b PR #895 동일 fix class): 클로저 멤버
  ## src/verification/rust_extraction_agreement.nim·rust_obligation_render.nim
  ## ·rust_rust_pipeline.nim + src/cli/rust_lane_cli.nim(④ 핀 재앵커 —
  ## pin@B 키 커버)의 동반 9경로. 사전등록:
  ## docs/evidence/rotation_allowlist_guard_obligation_prereg_2026-10-18.md.
  ## 열거형만 — glob 없음(A4 규율); 비멤버 production src/는 계속 밖(A2 (i)).
  ## (main 병합 2026-10-18: #920 mg-reuse-eligibility 동반 2경로 보존.)
  ## PR-files listing completeness: the API caps at 3000 files; reaching the
  ## cap means completeness cannot be proven → fail-closed.
  PrFilesCap*: int = 3000
  ## Trust surface — policy SSOT single-source (B-anchored). The runtime
  ## authority for trust-surface classification is the `trustSurface` array
  ## of config/policy/merge_admission.json, loaded at evaluation time by
  ## loadTrustSurface from the workspace cwd — the SAME CWD-relative
  ## resolution as RotationPinBPath (pin@B). The MG verdict job executes in
  ## the B checkout ("Checkout executor tree = B"), so the evaluated policy
  ## is always B's file: a PR editing the policy cannot re-classify itself
  ## (self-exemption is structurally impossible). Motivation: the compiled
  ## literal this replaces had drifted from the policy — the v1.9.0/v1.12.0
  ## entries (config/trusted_writer_set.json, admission-check.yml,
  ## certificate-mint.yml, bsec-integrity.yml,
  ## experiments/act2-wp-toml-b1-input-integrity/bsec/replay.sh) were absent
  ## at runtime, causing the 2026-10-14 06:47 arbitrary-deny incident (MG
  ## run 38524327637). A second compiled copy of the live surface would
  ## re-create that drift, so there is none; the per-entry rationale (CI=0
  ## surviving workflows, Landing App binding, rust-subject TCB register) is
  ## documented in the policy SSOT's description field — this file no longer
  ## duplicates it. Note: this file (src/cli/merge_cli.nim) is itself on the
  ## surface — its own landing is the exit-0 manual lane.
  TrustSurfacePolicyPath*: string = "config/policy/merge_admission.json"
  ## Protection-retention tombstones — the ONLY compiled trust-surface data.
  ## Deleted paths retained so a PR resurrecting or renaming one of these
  ## historical paths still denies auto-merge; the policy SSOT lists only the
  ## surviving surface, so the tombstones cannot live there and are unioned
  ## into every loaded surface by loadTrustSurface. Deleted by the CI=0
  ## cutover and its predecessors: auto_merge.yml / readiness_start.yml /
  ## verify-candidate.yml (fa069d610, 2026-09-16) and ci.yml (4619699c3,
  ## 2026-09-18), plus canonical-bootstrap/** (removed with the action it
  ## wrapped).
  ## tests/cli/* pin rename-source hits on these paths — do not remove them
  ## without updating the tests.
  TrustSurfaceTombstones*: seq[string] = @[
    ".github/workflows/auto_merge.yml",
    ".github/workflows/ci.yml",
    ".github/workflows/readiness_start.yml",
    ".github/workflows/verify-candidate.yml",
    ".github/actions/canonical-bootstrap/**",
  ]

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  ## Outcome of a merge-admission evaluation.
  MergeAdmissionResult* = enum
    mergeGo                ## All required validations pass; base fresh; admissible.
    mergeRebaseRequired    ## Tested base SHA differs from current main SHA.
    mergeChecksIncomplete  ## A required validation is missing/not-passing/ambiguous.
    mergeAborted           ## Snapshot/trust-surface/staleness failure (fail-closed).

  ## Per-check status captured from GitHub check-runs API.
  CheckStatus* = object
    name*: string
    conclusion*: string

  ## One required validation resolved against a specific workflow run attempt.
  ValidationAttempt* = object
    jobName*: string
    workflowId*: int
    runId*: int
    attempt*: int
    conclusion*: string

  ## Rotation/closure adjudication outcome (ADR-0025 §7/§13, plan Phase 4):
  ## the SUBJECT CLASS of the closure adjudication computed at the I/O
  ## boundary from the gate-supplied derived closure line-files — the class is
  ## not the admission judgment (see adjudicateRotation docstring).
  RotationQualification* = enum
    rqUnspecified  ## closure inputs env absent — verdict fail-closes (ROT_UNSPECIFIED)
    rqNormal       ## closure 3-way equality holds — ordinary subject class
    rqRotation     ## closure mismatch — ROTATION subject class (④ verified by Pass 2.75)
    rqNone         ## NOT-ADMIT — a ladder condition (① or ③) failed (ROT_*)

  ## Auditable per-condition flags of the ROTATION adjudication (Amendment F
  ## fixed ladder: inputs/identity → ③ old anchor → ④ new anchor → delta
  ## classification → ① allowlist; a flag is truthful iff its ladder position
  ## was reached — unreachable ones keep the default false).
  RotationCheck* = object
    closureChange*: bool         ## candidate-delta classification (Amendment F): derived(M) != derived(B) —
                                 ## M = the gate-verified candidate tree merge-tree(B, H) (NOT set(H)/set(B) drift)
    changed*: seq[string]        ## PR changed paths (A/M/D/R, incl. rename sources)
    allowlistOk*: bool           ## ① every changed path ∈ pin@B keys ∪ docs/adr/** ∪ pin file
                                 ##   (rotation-subject condition — vacuous-true under NORMAL, A2 ii)
    subjectDeltaZero*: bool      ## ② no changed path outside the allowlist (≡ ① — audit twin)
    genesis*: bool               ## pin@B has NO trustedCheckerTreeClosure key (ADR §7 1회)
    oldAnchorOk*: bool           ## ③ genesis exception OR line-set(pin@B) == set(B) —
                                 ##   classification-independent fact on EVERY path; the single
                                 ##   deny point is right here (ROT_OLD_PIN)
    newAnchorOk*: bool           ## ④ line-set(pin@H) == set(H) (atomic rotation) — every path;
                                 ##   the single ④ policy deny site is Pass 2.75 (H2)
    delegatedToPlatform*: bool   ## ⑤ CODEOWNER approval = GitHub (NOT re-checked here)

  ## Snapshot fact: the pure adjudication result bound at the I/O boundary.
  RotationAdjudication* = object
    qualification*: RotationQualification
    check*: RotationCheck
    reasonCode*: string          ## "" = no condition violated. ROT_ALLOWLIST/ROT_OLD_PIN = a
                                 ##   ladder deny (rqNone). ROT_NEW_PIN/ROT_GENESIS_INVALID may
                                 ##   also ANNOTATE a non-deny fact (rqNormal/rqRotation) when ④
                                 ##   failed — the deny then comes from Pass 2.75 (H2) verbatim.
    reason*: string

  ## Trust-surface violation: a PR changed file (or rename source) matching
  ## the protected patterns.
  TrustSurfaceHit* = object
    path*: string          ## the matched file path
    renamedFrom*: string   ## non-empty when a rename source matched

  ## RL-14.4 (M-41, S5) verdict for ONE import target of a changed src/core
  ## file — same vocabulary as the runtime layer gate's verdicts so admission
  ## and the gate are falsifiable against each other.
  LayerImportVerdict* = enum
    livRejected   ## parsed import denied — no approved (source, target) pair covers it
    livUnparsed   ## target resolves to no canonical path — normalization rule 10, fail-closed

  ## RL-14.4 (M-41, S5) collection status of the layer-admissibility fact.
  LayerAdmissibilityStatus* = enum
    lasPass      ## no unapproved forbidden-layer import introduced
    lasFail      ## >= 1 violation (REJECTED or UNPARSED) — deny
    lasUnknown   ## lock/content collection failure — deny fail-closed (never silent-pass)

  ## One M-41 violation citation — (file, line, target) is the unambiguous
  ## diagnosis evidence the reviewer demanded: a block must name its own
  ## cause, never be mistakable for another check's failure.
  LayerAdmissibilityViolation* = object
    file*: string              ## repo-relative source path (src/core/…)
    line*: int                 ## 1-based import-statement line
    target*: string            ## raw import token as written
    verdict*: LayerImportVerdict
    normalizedTarget*: string  ## canonical target ("" for UNPARSED)

  ## RL-14.4 (M-41, S5) admission-time layer fact — collected at the I/O
  ## boundary (head snapshot + workspace pair registry) and consumed by
  ## Pass 2.92. Judging itself is the trusted SSOT (isAllowedImport) fed the
  ## injected pairs — this snapshot carries only evidence.
  LayerAdmissibilityFacts* = object
    status*: LayerAdmissibilityStatus
    scannedFiles*: int         ## changed src/core/** .nim files judged at head
    approvedPairCount*: int    ## active pair exceptions injected into the judge
    violations*: seq[LayerAdmissibilityViolation]
    note*: string              ## UNKNOWN detail ("" on PASS/FAIL)

  ## CertificateContinuityFacts (certification-continuity Phase 5, contract
  ## §5 INV-1): one certified subject's certificate record, bound at the I/O
  ## boundary. The cert-side fields (subjectId … signatureOk) come from the
  ## side-ref ledger certificate binding block + its Ed25519 attestation;
  ## the observed fields (actualCandidateCommit / currentPolicyDigest /
  ## currentScopeDigest) come from the evaluation environment. The pure
  ## predicate enforces EXACT equality between the certified and the observed
  ## values — OID/digest binding only, no tree re-derivation (INV-3).
  CertificateContinuityFacts* = object
    subjectId*: string            ## cert.subjectId (64 hex)
    baseSha*: string              ## cert.baseSha — certified construction base (40 hex)
    headSha*: string              ## cert.headSha — certified PR head (40 hex)
    headTreeDigest*: string       ## cert.headTreeDigest (64 hex)
    policyDigest*: string         ## cert.policyDigest (64 hex)
    scopeDigest*: string          ## cert.scopeDigest (64 hex)
    evidenceDigest*: string       ## cert.evidenceDigest (64 hex)
    signatureOk*: bool            ## Ed25519 attestation verified at the boundary
    currentPolicyDigest*: string  ## sha256(config/policy/merge_admission.json bytes) NOW
    currentScopeDigest*: string   ## sha256(data/verification_scope.lock bytes) NOW

  ## VaultCertTarget (proof-required admission contract §1/§3): one in-scope
  ## kernel symbol's vault-certificate binding, collected at the I/O boundary.
  ## The identity requirement is the vault manifest's irHash — the cert
  ## convention (cert_integrity_gate) is filename == content irHash.
  VaultCertTarget* = object
    modulePath*: string       ## the changed kernel module path (scope lock)
    functionName*: string     ## the active kernel symbol's name (scope lock)
    irHash*: string           ## manifest irHash — the required vault cert identity
    certPresent*: bool        ## the vault cert file exists in the admitted tree (H)
    irHashMatch*: bool        ## cert content irHash == manifest irHash (else SUBJECT_MISMATCH)

  ## VaultCertContinuityFacts — the Pass 2.96b snapshot fact (contract §4.3),
  ## bound at the I/O boundary. The vault cert carries NO policy/scope digests
  ## (schema difference from the subject-continuity cert, contract §2.2), so
  ## the certificate-side epoch is the committed state at the event-frozen
  ## base B (immutable tree objects) and the current side is the
  ## certificateFactFromNode projection duplicated (sha256 of the LOCAL files
  ## NOW). The pure predicate enforces EXACT equality only (INV-3: no tree
  ## re-derivation).
  VaultCertContinuityFacts* = object
    targets*: seq[VaultCertTarget]    ## in-scope symbols WITH a manifest entry (sorted)
    policyEpochDigest*: string        ## sha256(config/policy/merge_admission.json @ B tree)
    scopeEpochDigest*: string         ## sha256(data/verification_scope.lock @ B tree)
    currentPolicyDigest*: string      ## sha256(config/policy/merge_admission.json) NOW
    currentScopeDigest*: string       ## sha256(data/verification_scope.lock) NOW

  ## AdmissionFacts(H) — the immutable snapshot consumed once by the pure
  ## predicate. Every PR-derived field is bound to the head SHA `headSha`
  ## observed at collection start.
  AdmissionFacts* = object
    headSha*: string
    baseSha*: string                    ## canonical: the PR record's base.sha
    validations*: seq[ValidationAttempt] ## latest-attempt evidence per required validation
    prFileCount*: int                   ## total PR changed files collected (completeness)
    listingComplete*: bool              ## false → trust-surface check cannot be proven
    trustSurfaceHits*: seq[TrustSurfaceHit]
    changeGraph*: ChangeGraphStatus
    mergeableState*: string             ## supporting fact (never the core truth)
    certificate*: Option[CertificateContinuityFacts] = none(CertificateContinuityFacts)
      ## Phase 5: some = a subject-continuity certificate for this PR/subject
      ## was found in the side-ref ledger and bound at the I/O boundary → the
      ## certificate-continuity pass (Pass 2.96) runs.
    certRequired*: bool = false
      ## Phase 5: true = this certified admission DEMANDED a certificate and
      ## none was found → NO_CERT (missing ≠ valid empty). Legacy
      ## (uncertified) evaluations keep this false and skip the pass.
    rotation*: Option[RotationAdjudication] = none(RotationAdjudication)
      ## Phase 4 (ADR-0025 §7/§13): some = the gate supplied closure inputs
      ## (derived H/B line-files + H-side pin) and the adjudication ran —
      ## Pass 2.97 denies rqNone (ROT_* codes). None = inputs absent
      ## (UNSPECIFIED — the SL-02 pre-gate state) → Pass 2.97 denies
      ## ROT_UNSPECIFIED: the committed verdict-stage contract
      ## (admission-check.yml :1446/:1541) fail-closes on UNSPECIFIED.
    vaultCert*: Option[VaultCertContinuityFacts] = none(VaultCertContinuityFacts)
      ## Pass 2.96b (proof-required admission contract §4.3): some = the vault
      ## target set was collected and bound → the pass runs. None = no
      ## collection targets (no in-scope kernel symbol carries a vault
      ## manifest entry) → the pass is SKIPPED — a recorded skip, marked in
      ## the dry-run JSON (buildDryRunJson), never a silent one.
    vaultCertRequired*: bool = false
      ## Pass 2.96b: true = this admission demands vault certificates for
      ## its in-scope manifest targets (the I/O boundary fills the
      ## VaultCertRequired const). The requirement is what denies: a
      ## demanded-but-absent fact stays a recorded skip, and the per-target
      ## absence (certPresent=false) is the NO_CERT state.
    layerAdmissibility*: Option[LayerAdmissibilityFacts] = none(LayerAdmissibilityFacts)
      ## RL-14.4 (M-41, S5): some = the layer fact was collected at the I/O
      ## boundary and Pass 2.92 judges it — lasFail and lasUnknown deny.
      ## None = a legacy record predating M-41 (Pass skipped); the single
      ## production collection path ALWAYS binds the fact and binds
      ## lasUnknown — never None — on a collection failure.

  ## VerificationRecord — legacy CI-evidence record + the admission snapshot.
  ## `admission` is Option: None means the extended facts were never collected,
  ## which MUST deny (missing ≠ valid empty).
  VerificationRecord* = object
    headSha*: string
    baseSha*: string
    requiredChecks*: seq[CheckStatus]
    admission*: Option[AdmissionFacts]
    ## Candidate binding (ADR-0020 Phase 5, spec v9 §2b): present only when the
    ## record describes a speculative candidate subject (not a plain PR head).
    ## Populated at the I/O boundary; the pure predicate consumes the snapshot.
    candidate*: Option[CandidateBinding]

  ## CandidateBinding — identity + run↔identity binding verification results
  ## for a speculative candidate subject (ADR-0020 §2b/D6). `bindingVerified`
  ## is computed at the I/O boundary (run identity binding plus
  ## dispatch-inputs contrast); the pure predicate consumes the result and
  ## denies when false — an unbound candidate never admits (missing ≠ valid
  ## empty), reasonCode BINDING_MISMATCH.
  CandidateBinding* = object
    candidateTreeDigest*: string
    queueEpoch*: uint32
    position*: int
    predecessor*: string
    predecessorStatus*: string
    bindingVerified*: bool
    bindingReadPath*: string

  ## MergeAdmissionOutcome — the result paired with a human-readable reason
  ## and a machine-readable reason code (audit).
  MergeAdmissionOutcome* = object
    result*: MergeAdmissionResult
    reason*: string
    reasonCode*: string

  ## Outcome of a single GitHub merge request (PUT /pulls/{n}/merge) — the
  ## merge commit OID (L) plus the response evidence. Only success produces L.
  MergeOutcome* = object
    mergeSha*: string   ## L — server-created merge commit OID
    merged*: bool       ## response `merged` field
    ghMessage*: string  ## response `message` field

  ## Evidence of a failed merge request — the actuator's classification input.
  MergeFailure* = object
    httpStatus*: int    ## HTTP status (0 = transport-level error)
    ghMessage*: string  ## GitHub `message` (or transport error text)
    rateLimitRemaining*: string  ## x-ratelimit-remaining ("" = absent)
    rateLimitReset*: string      ## x-ratelimit-reset ("" = absent)
    retryAfter*: string          ## retry-after ("" = absent)

  ## Classified merge denial — reason vocabulary reuses the existing
  ## mergeAborted verdict; the machine codes are journal strings (no new
  ## enum values).
  MergeDenial* = object
    reason*: string
    reasonCode*: string
    currentHead*: string  ## PR head observed by the classification GET

# ---------------------------------------------------------------------------
# Pure helpers — glob matching (mirrors src/core/policy/architecture_policy_part2.nim)
# ---------------------------------------------------------------------------

func pathMatchesGlob*(path: string; pattern: string): bool {.raises: [].} =
  let p = path.replace("\\", "/")
  let pat = pattern.replace("\\", "/")
  if pat.endsWith("/**"):
    let prefix = pat[0 .. ^4]
    return p == prefix or p.startsWith(prefix & "/")
  if pat.contains('*'):
    let star = pat.find('*')
    let prefix = pat[0 ..< star]
    let suffix = pat[star + 1 .. ^1]
    return p.startsWith(prefix) and p.endsWith(suffix)
  p == pat or p.startsWith(pat & "/")

func trustSurfaceMatch*(filename: string; renamedFrom: string;
                        surface: seq[string]): Option[TrustSurfaceHit] {.raises: [].} =
  ## Check both the current path and (for renames) the previous path against
  ## the trust surface. A hit on either is a violation. `surface` is the
  ## EFFECTIVE surface the caller supplies — loadTrustSurface's policy-SSOT
  ## load (B-workspace anchored) — never a compiled copy of the live paths.
  for pat in surface:
    if pathMatchesGlob(filename, pat):
      return some(TrustSurfaceHit(path: filename, renamedFrom: ""))
  if renamedFrom.len > 0:
    for pat in surface:
      if pathMatchesGlob(renamedFrom, pat):
        return some(TrustSurfaceHit(path: filename, renamedFrom: renamedFrom))
  none(TrustSurfaceHit)

func parseTrustSurfaceJson*(node: JsonNode): Result[seq[string], string] {.raises: [].} =
  ## Pure core of the trust-surface load: extract the `trustSurface` array
  ## from a parsed config/policy/merge_admission.json. Fail-closed —
  ## non-object root, missing/non-array trustSurface, non-string or empty
  ## patterns, and an EMPTY array are all errors: an empty surface would
  ## silently de-protect everything, so protection must never read as
  ## vacuously clean.
  if node.isNil or node.kind != JObject:
    return err("policy root is not a JSON object")
  let ts = node.getOrDefault("trustSurface")
  if ts.isNil or ts.kind != JArray:
    return err("policy has no trustSurface array")
  var entries: seq[string] = @[]
  for e in ts.items:
    if e.kind != JString:
      return err("trustSurface contains a non-string entry")
    if e.getStr().len == 0:
      return err("trustSurface contains an empty pattern")
    entries.add(e.getStr())
  if entries.len == 0:
    return err("trustSurface array is empty (protection must never silently be empty)")
  ok(entries)

# ---------------------------------------------------------------------------
# Rotation/closure adjudication (ADR-0025 §7/§13 + Amendment F) — pure core
# ---------------------------------------------------------------------------
# Env-gated Pass: when the org gate supplies the deriver's closure line-files
# (AXIOM_DERIVED_H_PATH / AXIOM_DERIVED_B_PATH / AXIOM_DERIVED_M_PATH —
# `<mode> <type> <sha>\t<path>` linetext, byte-sorted; the M file is the
# derived closure OF the candidate tree merge-tree(B, H), supplied only after
# the gate machine-verified its equality with the tested landing candidate)
# plus the H-side pin (AXIOM_PIN_H_PATH), the SUBJECT CLASS is the PR's own
# candidate delta: closureChange = (derived(M) != derived(B)) → ROTATION, else
# NORMAL — base drift never classifies (Amendment F). A rotation subject
# admits only when ALL conditions hold (① allowlist ⊆ pin@B keys ∪ docs/adr/**
# ∪ pin file ∪ A2 companions, ② subject Δ=0 — same predicate, audit twin —
# ③ old anchor == derived(B) or genesis exception (ADR §7 1회; classification-
# independent fact, denied here), ④ new anchor == derived(H) (denied only at
# Pass 2.75), ⑤ approval delegated to GitHub CODEOWNERS). Any failure =
# NOT-ADMIT (ROT_*). When the env is absent the verdict fail-closes
# (rqUnspecified → ROT_UNSPECIFIED — admission-check .yml :1446/:1541). The
# pure parsing primitives (stripJsoncComments / parseDerivedSet /
# pinClosureLineSet / closurePathFromLine) and the ④ judgment
# (newAnchorVerdict) live in the shared leaf module
# core/policy/rotation_closure_facts — ONE compiled implementation consumed
# here and by the rotation preflight checker (tools/ci/
# rotation_pin_anchor_check.nim); only the allowlist (①) machinery and the
# adjudication ladder remain below.

func rotationAllowlistOk*(path: string; pinB: Option[HashSet[string]]): bool {.raises: [].} =
  ## Allowlist membership (ADR-0025 §13 3분류 / Amendment A2 2026-09-27): a
  ## changed path is allowed iff it is a closure member path (pin@B keys), or
  ## under docs/adr/**, or the pin file itself, or one of the A2 rotation-
  ## companion paths (RotationAllowlistExtra — trust workflow pair, rotation
  ## data, rotation tests). Genesis (pin@B key absent) leaves the non-closure
  ## tails unchanged. NON-member production src/ still fails (A2 (i) — 회전
  ## 으로 승인 불가).
  if pinB.isSome:
    for line in pinB.get:
      if closurePathFromLine(line) == path:
        return true
  for extra in RotationAllowlistExtra:
    if extra == path:
      return true
  path == RotationPinBPath or pathMatchesGlob(path, RotationAdrGlob)

func annotateNewAnchor(r: var RotationAdjudication;
                       derivedH: HashSet[string];
                       pinH, pinB: Option[HashSet[string]]) {.raises: [].} =
  ## ④ (pin anchor) FACT annotation only — evaluated on EVERY path (NORMAL
  ## included) and NEVER denies. The single ④ policy deny site is Pass 2.75 (H2)
  ## in MergeAdmissible; this records WHY ④ failed. The judgment itself is the
  ## shared newAnchorVerdict (core/policy/rotation_closure_facts) — the same
  ## compiled implementation the rotation preflight checker consumes. Failure
  ## precedence into the annotation is applied by the caller (③ old anchor
  ## overwrites it first — Amendment F ladder step 2 before step 3; the ①
  ## allowlist is step 5, BELOW ④, so it never overwrites), so the recorded
  ## reason is always the ladder-selected one.
  let v = newAnchorVerdict(derivedH, pinH, pinB)
  r.check.newAnchorOk = v.ok
  if v.ok:
    return
  r.reasonCode = v.code
  r.reason = v.reason

func adjudicateRotation*(derivedH, derivedB, derivedM: HashSet[string];
                         pinB: Option[HashSet[string]];
                         pinH: Option[HashSet[string]];
                         changed: seq[string]): RotationAdjudication {.raises: [].} =
  ## Pure rotation/closure adjudication (ADR-0025 §7/§13 + Amendment F,
  ## 2026-10-12): the SUBJECT CLASS is the PR's OWN candidate delta —
  ##   closureChange = (derived(M) != derived(B))
  ## with M = the candidate tree (git merge-tree --write-tree B H) whose
  ## equality with the tested landing candidate the GATE machine-verified
  ## BEFORE supplying these inputs (CANDIDATE_TREE_MISMATCH-class gate — the
  ## classification input is unqualified without it). Base drift (differences
  ## between set(H) and set(B) the PR never made) does NOT enter the
  ## classification — the stale-base misclassification (S1,
  ## docs/evidence/s1-stale-base-repro-2026-10-12.md) is the defect this
  ## replaces. The class is NOT an admission judgment; the judgment lives only
  ## in the verdict (MergeAdmissible + dryRunExit). A non-empty reasonCode is a
  ## FACT annotation (why ④ failed) and may accompany rqNormal/rqRotation; it
  ## is not a deny by itself.
  ## Fixed failure ladder (Amendment F — evaluated top-down):
  ##   1. inputs/identity — env absent → UNSPECIFIED (collector ok(none)); a
  ##      missing/malformed derived line-file or an unverified candidate-tree
  ##      equality is a run-level fail-closed at the collector/gate, never a
  ##      clean verdict.
  ##   2. ③ old anchor (genesis exception OR line-set(pin@B) == set(B)) —
  ##      classification-independent FACT on EVERY path; the SINGLE deny point
  ##      here (rqNone + ROT_OLD_PIN). Its reason overwrites the ④ annotation.
  ##   3. ④ new anchor (line-set(pin@H) == set(H)) — FACT on every path, NEVER
  ##      denies here; the single ④ policy deny site is Pass 2.75 (H2) in
  ##      MergeAdmissible, consuming the annotation verbatim.
  ##   4. delta classification — rqRotation iff closureChange else rqNormal.
  ##   5. ① allowlist (A2) — rotation-subject condition, evaluated ONLY on the
  ##      ROTATION path (vacuous-true under NORMAL, A2 ii); fails → rqNone +
  ##      ROT_ALLOWLIST, and never overwrites the ④ annotation (step 3 is
  ##      above step 5).
  ## H1 requires H2 in the same generation — without Pass 2.75 a ④-fail would
  ## return its class and admit.
  result.check.delegatedToPlatform = true
  result.check.changed = changed
  result.check.genesis = pinB.isNone
  # ③④ — classification-independent facts, computed on EVERY path (ladder
  # steps 2-3 precede the classification at step 4).
  result.check.oldAnchorOk = result.check.genesis or (pinB.isSome and pinB.get == derivedB)
  annotateNewAnchor(result, derivedH, pinH, pinB)
  if not result.check.oldAnchorOk:
    result.qualification = rqNone
    result.reasonCode = "ROT_OLD_PIN"
    result.reason = "rotation old anchor invalid: pin@B trustedCheckerTreeClosure present " &
      "but line-set(pin@B) != set(derived B) (fail-closed)"
    return
  # ④ Delta classification (Amendment F §1): the PR's own candidate delta.
  result.check.closureChange = (derivedM != derivedB)
  if not result.check.closureChange:
    result.qualification = rqNormal
    # ①② are rotation-subject conditions — vacuous-true under NORMAL (A2 ii).
    result.check.allowlistOk = true
    result.check.subjectDeltaZero = true
    return
  # Closure changed by the candidate delta → ROTATION subject class. ① still
  # denies here (ladder step 5; it never overwrites the ④ annotation — the
  # recorded reason stays the ladder-selected one). ④ never denies here —
  # Pass 2.75 owns it.
  result.qualification = rqRotation
  var allowlistOk = true
  for p in changed:
    if not rotationAllowlistOk(p, pinB):
      allowlistOk = false
      break
  result.check.allowlistOk = allowlistOk
  # ② subject Δ = 0 is EQUIVALENT to ① (one predicate) — reported as an
  # audit twin, never a separate adjudication.
  result.check.subjectDeltaZero = allowlistOk
  if not allowlistOk:
    result.qualification = rqNone
    if result.reasonCode.len == 0:
      # The message derives from the SAME constants the predicate consumes —
      # the previous hand-maintained copy drifted (named only A2's original
      # four classes while RotationAllowlistExtra grew to eight: PRs
      # #306/#702 added the landing-required-gateway-tests and epoch-manifest
      # pin twins), so blocked PRs were told an allowlist that did not match
      # the enforced one. join/& are non-raising; the judgment above is
      # byte-identical.
      result.reasonCode = "ROT_ALLOWLIST"
      result.reason = "closure changed by the candidate delta requires ROTATION but changed path(s) fall outside the " &
        "allowlist (closure pin@B keys ∪ " & RotationAdrGlob & " ∪ " & RotationPinBPath &
        " ∪ A2 companions: " & join(RotationAllowlistExtra, " · ") &
        " — ADR-0025 A2) — subject Δ != 0 (fail-closed)"
    return

func qualificationName*(q: RotationQualification): string {.raises: [].} =
  case q
  of rqUnspecified: "UNSPECIFIED"
  of rqNormal: "NORMAL"
  of rqRotation: "ROTATION"
  of rqNone: "NONE"

# Judged-source fingerprint — evidence scope is deliberately narrow: it proves
# (i) the deterministic fingerprint of the SOURCE containing the judgment code
# and (ii) code↔binary binding. The run↔verdict binding belongs to the job-log
# envelope; "engine identity" is NOT claimed. hash_kernel.sha256Hex is the
# single hashing authority (NIST: SHA-1 is unsuitable for collision-resistant
# new trust evidence). Bytes are compile-time-pinned (staticRead) so the
# fingerprint is a pure function of the judged source; runtime hashing of those
# bytes is deterministic (the same input always hashes identically).
const MergeCliSourceBytes* = staticRead(currentSourcePath())

func judgeSourceFingerprint*(): string {.raises: [].} =
  ## SHA-256 of the judged source bytes (see the evidence-scope note above).
  result = sha256Hex(MergeCliSourceBytes)

# ---------------------------------------------------------------------------
# RL-14.4 layer admissibility (M-41, S5) — pure core
# ---------------------------------------------------------------------------
# A changed/added src/core/** file that introduces a forbidden-layer import
# (verification/ cli/ mcp/ ui/ gate/) NOT covered by an approved
# (source, target) pair denies the merge. The RULE is not re-coded here: the
# normalization contract (expandImportTargets / normalizeImportPath /
# resolveImportTarget — layer_rules.nim) and the judge (isAllowedImport —
# layer_enforcement.nim) are the trusted SSOT; the approved-pair registry is
# injected as isAllowedImport's parameter exactly like the runtime gate does
# (decision docs/history/debt/rl14-4-crossing-decision-2026-10-11.md §4 —
# Domain never reads src/gate/**, the consumer injects the lock data).
# "NEW" is the registry itself: the 23 approved pairs ARE the baseline of the
# staged enforcement (soc_queries.nim filters by the same pairs), so an
# unapproved forbidden import in a CHANGED core file is by construction a new
# crossing (DEBT#495 per-pair scope — an already-paired file gaining another
# forbidden import still violates).

const
  ## The RL-14.4 five forbidden import-target prefixes for src/core/ sources
  ## (docs/agents/core_rules.md "SoC Red Lines" RL-14.4). LayerRules[0] adds
  ## engine//frontend/ as extra SoC table rows — outside M-41 scope, judged by
  ## the gates that own that table. Policy SSOT mirror, like RequiredChecks.
  Rl144ForbiddenPrefixes*: seq[string] = @["verification/", "cli/", "mcp/", "ui/", "gate/"]
  ## Exception registry (decision §3.1) — read from the WORKSPACE (base-state)
  ## lock, never from the PR head, so a PR can never approve its own crossing.
  ## Paths mirror the runtime gate's constants (layer_enforcement_gate.nim).
  LayerPolicyLockPath*: string = "src/gate/architecture_policy.lock"
  LayerPairRegistryKey*: string = "core_to_verification_pairs"

func isCoreSourcePath*(path: string): bool {.raises: [].} =
  ## A PR changed path that lands a Nim module in the Domain layer (RL-14.4's
  ## subject side; trusted/ INCLUDED — the pair registry explicitly grants
  ## core/trusted crossings, so they are judged, not skipped).
  path.startsWith("src/core/") and path.endsWith(".nim")

func layerStatusName*(s: LayerAdmissibilityStatus): string {.raises: [].} =
  case s
  of lasPass: "PASS"
  of lasFail: "FAIL"
  of lasUnknown: "UNKNOWN"

func layerVerdictName*(v: LayerImportVerdict): string {.raises: [].} =
  case v
  of livRejected: "REJECTED"
  of livUnparsed: "UNPARSED"

func unknownLayerFacts*(note: string; scanned: int): LayerAdmissibilityFacts {.raises: [].} =
  ## The fail-closed collection-failure shape — the predicate maps this to
  ## LAYER_ADMISSIBILITY_UNKNOWN (deny), never to a silent pass (AGENTS §4:
  ## 검증 불가 = fail closed).
  LayerAdmissibilityFacts(status: lasUnknown, scannedFiles: scanned,
    approvedPairCount: 0, violations: @[], note: note)

func unclosedBrackets(s: string): int {.raises: [].} =
  ## Bracket balance of one statement — mirrors the runtime gate's helper so
  ## multi-line `import a/[b, c]` statements join EXACTLY as
  ## layer_enforcement_gate.scanFile joins them (admission must judge the
  ## same statement boundaries the gate judges).
  result = 0
  for ch in s:
    if ch == '[':
      inc result
    elif ch == ']' and result > 0:
      dec result

func splitImportList(importPart: string): seq[string] {.raises: [].} =
  ## Comma-split at bracket depth 0 — mirrors the runtime gate's helper so
  ## `std/[a, b]` stays ONE token for the SSOT expandImportTargets (rule 6).
  result = @[]
  var current = ""
  var depth = 0
  for ch in importPart:
    if ch == '[':
      inc depth
    elif ch == ']' and depth > 0:
      dec depth
    if ch == ',' and depth == 0:
      result.add(current.strip())
      current = ""
    else:
      current.add(ch)
  result.add(current.strip())

func extractImportTargets*(content: string): seq[tuple[line: int, target: string]] {.raises: [].} =
  ## Line-scan of one file's content for import targets — a faithful mirror of
  ## layer_enforcement_gate.scanFile's statement walk (the live RL-14.4
  ## enforcement layer): `import …` statements with bracket-continuation
  ## joining, and `from X import …` heads (imported symbols are not targets).
  ## Comment lines never match (they do not start with the statement keyword
  ## after strip), so admission and the gate see identical statement sets on
  ## identical content. Empty trailing tokens are kept — the SSOT resolution
  ## maps them to UNPARSED (rule 10), exactly like the gate's judgeTarget.
  result = @[]
  let lines = content.splitLines()
  var idx = 0
  while idx < lines.len:
    let lineNum = idx + 1
    let stripped = lines[idx].strip()
    inc idx
    var targets: seq[string] = @[]
    if stripped.startsWith("import "):
      var stmt = stripped
      while unclosedBrackets(stmt) > 0 and idx < lines.len:
        stmt.add(" ")
        stmt.add(lines[idx].strip())
        inc idx
      let importPart = stmt[7..^1].strip()
      for tok in splitImportList(importPart):
        targets.add(tok.strip())
    elif stripped.startsWith("from "):
      let parts = stripped.split(" import ")
      if parts.len >= 1:
        let head = parts[0]
        targets.add(if head.len >= 5: head[5..^1].strip() else: "")
    for t in targets:
      result.add((lineNum, t))

func judgeCoreFileImports*(srcFile, content: string;
                           approved: seq[(string, string)]): seq[LayerAdmissibilityViolation] {.raises: [].} =
  ## M-41 judging for ONE changed src/core file's head content — pure. Per
  ## import target, mirroring the runtime gate's judgeTarget precedence:
  ##   target without "/"         → out of layer-path scope (rule 7)
  ##   resolveImportTarget = @[]  → UNPARSED (rule 10 fail-closed)
  ##   forbidden-five prefix AND
  ##   not isAllowedImport(pairs) → REJECTED (the M-41 violation proper)
  ## Each canonical target is judged SEPARATELY through the SSOT judge, so a
  ## bracket import flags exactly its offending member at per-pair scope.
  for (lineNum, raw) in extractImportTargets(content):
    if not raw.contains("/"):
      continue
    let resolved = resolveImportTarget(srcFile, raw)
    if resolved.len == 0:
      result.add(LayerAdmissibilityViolation(
        file: srcFile, line: lineNum, target: raw,
        verdict: livUnparsed, normalizedTarget: ""))
      continue
    for canonical in resolved:
      var forbidden = false
      for prefix in Rl144ForbiddenPrefixes:
        if canonical.startsWith(prefix):
          forbidden = true
          break
      if not forbidden:
        continue
      if isAllowedImport(srcFile, canonical, approved):
        continue
      result.add(LayerAdmissibilityViolation(
        file: srcFile, line: lineNum, target: raw,
        verdict: livRejected, normalizedTarget: canonical))

func layerAdmissibilityVerdict*(coreContents: seq[tuple[path, content: string]];
                                approved: seq[(string, string)]): LayerAdmissibilityFacts {.raises: [].} =
  ## Pure fold — the M-41 verdict over the collected (path, content) snapshot.
  ## PASS iff NO changed src/core file introduces an unapproved forbidden-layer
  ## import or an unparseable one; FAIL carries EVERY violation so the
  ## diagnosis names each (file, line, target) cause.
  result.status = lasPass
  result.scannedFiles = coreContents.len
  result.approvedPairCount = approved.len
  for (p, c) in coreContents:
    result.violations.add(judgeCoreFileImports(p, c, approved))
  if result.violations.len > 0:
    result.status = lasFail

func firstLayerViolation*(L: LayerAdmissibilityFacts): LayerAdmissibilityViolation {.raises: [].} =
  ## The citation for a FAIL verdict — a REJECTED (unapproved forbidden-layer)
  ## violation takes precedence over an UNPARSED one so the reasonCode names
  ## the layer crossing itself when both are present.
  result = L.violations[0]
  for v in L.violations:
    if v.verdict == livRejected:
      return v

func buildDryRunJson*(prNumber: int; headSha, baseSha: string;
                      outcome: MergeAdmissionOutcome;
                      rotation: Option[RotationAdjudication];
                      layer = none(LayerAdmissibilityFacts);
                      preflight = false;
                      vaultCertRequired = false;
                      vaultCertTargets = -1): JsonNode {.raises: [].} =
  ## Assemble the `--json` dry-run verdict object (one machine line on stdout;
  ## the future gate's verdict job parses `qualification` from it). When the
  ## closure inputs were absent the adjudication did not run → qualification
  ## UNSPECIFIED, rotationCheck null, and the verdict itself is the
  ## ROT_UNSPECIFIED fail-closed deny. `preflight=true`
  ## marks the ADR-0032 PR-preflight evaluation (`ax merge --preflight`): the
  ## machine line then carries `"preflight": true` — that verdict is a
  ## non-canonical preflight signal, NEVER a landing-eligibility judgment
  ## (the canonical verdict is the merge_group verdict, ADR-0032 (a),(f)).
  ## `layer` carries the M-41 fact: the `layerAdmissibility` key makes a
  ## layer-caused block machine-readable (status + every (file, line, target)
  ## violation), not just an exit code; null = legacy record predating M-41.
  var check: JsonNode = newJNull()
  var note = ""
  if rotation.isSome:
    let c = rotation.get.check
    check = %*{
      "closureChange": c.closureChange,
      "changed": c.changed,
      "allowlistOk": c.allowlistOk,
      "subjectDeltaZero": c.subjectDeltaZero,
      "genesis": c.genesis,
      "oldAnchorOk": c.oldAnchorOk,
      "newAnchorOk": c.newAnchorOk,
      "delegatedToPlatform": c.delegatedToPlatform
    }
  else:
    note = "closure inputs absent (" & EnvDerivedHPath & "/" & EnvDerivedBPath &
      "/" & EnvDerivedMPath & "/" & EnvPinHPath & ") — qualification UNSPECIFIED (verdict fail-closes)"
  var layerJson: JsonNode = newJNull()
  if layer.isSome:
    let L = layer.get
    var vj = newJArray()
    for v in L.violations:
      vj.add(%*{
        "file": v.file,
        "line": v.line,
        "target": v.target,
        "verdict": layerVerdictName(v.verdict),
        "normalizedTarget": v.normalizedTarget
      })
    layerJson = %*{
      "status": layerStatusName(L.status),
      "scannedFiles": L.scannedFiles,
      "approvedPairCount": L.approvedPairCount,
      "note": L.note,
      "violations": vj
    }
  result = %*{
    "prNumber": prNumber,
    "headSha": headSha,
    "baseSha": baseSha,
    "verdict": {
      "result": $outcome.result,
      "reasonCode": outcome.reasonCode,
      "reason": outcome.reason
    },
    "qualification": if rotation.isSome: qualificationName(rotation.get.qualification) else: "UNSPECIFIED",
    "rotationCheck": check,
    "rotationNote": note,
    "vaultCert": {
      "required": vaultCertRequired,
      "targets": if vaultCertTargets < 0: newJNull() else: %vaultCertTargets
    },
    "judge": {
      "source": judgeSourceFingerprint()
    },
    "preflight": preflight,
    "layerAdmissibility": layerJson
  }

func trustSurfaceOutcome*(F: AdmissionFacts): Option[MergeAdmissionOutcome] {.raises: [].} =
  ## Pass 2.7/2.8 — PR-files listing completeness + trust surface — the
  ## single source of truth for the codes.
  if not F.listingComplete:
    return some(MergeAdmissionOutcome(
      result: mergeAborted,
      reason: "PR files listing incomplete (pagination did not terminate cleanly or " &
        $F.prFileCount & " files reached the " & $PrFilesCap & "-file cap) — trust surface cannot be proven",
      reasonCode: "TRUST_SURFACE_INCOMPLETE"))
  if F.trustSurfaceHits.len > 0:
    # Upper fail-closed boundary (4-class contract): the manual-merge route is
    # "human ceremony + machine pin-anchor check". Without rotation inputs the
    # machine check cannot run — that state must not land (fail-closed), or the
    # "all landings verify pin@H == derived(H)" invariant would have an
    # unverifiable landing path. ROT_UNSPECIFIED is the upper-boundary code;
    # the policy deny for ④ itself is Pass 2.75 (H2).
    if F.rotation.isNone:
      return some(MergeAdmissionOutcome(
        result: mergeAborted,
        reason: "trust-surface file modified but rotation/closure inputs were not supplied — " &
          "the manual-merge path requires the machine pin-anchor check (fail-closed, upper boundary)",
        reasonCode: "ROT_UNSPECIFIED"))
    let first = F.trustSurfaceHits[0]
    let detail = if first.renamedFrom.len > 0:
                   first.renamedFrom & " renamed to " & first.path
                 else:
                   first.path
    return some(MergeAdmissionOutcome(
      result: mergeAborted,
      reason: "trust-surface file modified (" & detail & ") — manual merge required",
      reasonCode: "TRUST_SURFACE_MODIFIED"))
  none(MergeAdmissionOutcome)

func MergeAdmissible*(V: VerificationRecord; mainSha: string): MergeAdmissionOutcome {.raises: [].} =
  # Pass −1 — admission facts must be PRESENT. None = never collected = deny.
  if V.admission.isNone:
    return MergeAdmissionOutcome(
      result: mergeAborted,
      reason: "admission facts not collected — missing facts never admit (fail-closed)",
      reasonCode: "FACTS_MISSING")

  let F = V.admission.get

  # Pass 0 — base freshness (the SINGLE freshness predicate): the candidate's
  # verified base MUST equal the declared main tip. This pass is a PROVENANCE
  # identity on every CI path, not a freshness decision — landing-path
  # freshness enforcement is the merge queue's invalidation semantics ALONE
  # (ADR-0027 P5, 2026-10-05: strict retired from the freshness role,
  # superseding the P3-era "Axiom decides, GitHub enforces" split). An
  # unrecorded base is a missing fact, never a clean one: the
  # I/O boundary has no fallback to invent it (missing ≠ valid empty), so the
  # predicate denies (BASE_UNRECORDED) rather than admitting on absent facts.
  #
  # The anchor on both sides is the EVENT-FROZEN base (V.baseSha and mainSha
  # are the same declared value on every CI path), so this pass is an IDENTITY
  # there: on merge_group the deny that used to fire was a false deny produced
  # by comparing the queue's frozen base against the lagging live PR API, and
  # the queue's own base invalidation is the freshness authority for that path.
  # The deny is NOT removed, only un-spoofed: it still fires for a declared
  # main that differs from the recorded anchor (re-verification after the base
  # moved) and for any caller that reaches the predicate without an anchor —
  # BASE_UNRECORDED is unreachable from runMergeCli/runMergeActuatorCli (both
  # reject an unset AXIOM_MAIN_SHA before collecting), and is kept fail-closed
  # for every other caller.
  if V.baseSha.len == 0:
    return MergeAdmissionOutcome(
      result: mergeAborted,
      reason: "candidate base not recorded — freshness cannot be evaluated against main " &
        $mainSha & " (fail-closed)",
      reasonCode: "BASE_UNRECORDED")
  if V.baseSha != mainSha:
    let verifiedBase = V.baseSha[0 ..< min(V.baseSha.len, 12)]
    let currentMain = mainSha[0 ..< min(mainSha.len, 12)]
    return MergeAdmissionOutcome(
      result: mergeAborted,
      reason: "candidate verified against base " & verifiedBase &
        ", but current main is " & currentMain &
        " — freshness binding requires the current tip",
      reasonCode: "STALE_BASE")

  # Platform check evidence (P12): required checks / verdict runs
  # are GitHub's merge-time authority (ruleset `admission-check`; landing
  # freshness enforcement = merge-queue invalidation alone, ADR-0027 P5) —
  # no local re-derivation pass runs here.

  # Pass 2.75 — pin anchor (④): the SINGLE POLICY DENY SITE for pin@H != derived(H)
  # (line-set mismatch or the key absent as a tree fact). Runs BEFORE the
  # trust-surface routing so the manual-merge route is "human ceremony + machine
  # check" (4-class contract: policy deny @H2 outranks the exit-0 route —
  # proof_required_admission_contract.md §3 amended accordingly). The reason is
  # consumed VERBATIM from the fact annotation (ladder-selected: ①→③→④);
  # when the rotation fact is absent the upper fail-closed boundary owns the
  # state (trustSurfaceOutcome's hit×none flip / Pass 2.97 ROT_UNSPECIFIED) —
  # this pass never invents a code for inputs it cannot see.
  if F.rotation.isSome and not F.rotation.get.check.newAnchorOk:
    return MergeAdmissionOutcome(
      result: mergeAborted,
      reason: F.rotation.get.reason,
      reasonCode: F.rotation.get.reasonCode)

  # Pass 2.7/2.8 — PR-files listing completeness + trust surface.
  let surfaceOutcome = trustSurfaceOutcome(F)
  if surfaceOutcome.isSome:
    return surfaceOutcome.get

  # Pass 2.9 — change graph: the PR's manifest DAG must be valid.
  if not F.changeGraph.valid:
    let first = if F.changeGraph.violations.len > 0: F.changeGraph.violations[0].message else: "invalid"
    return MergeAdmissionOutcome(
      result: mergeAborted,
      reason: "change graph invalid: " & first,
      reasonCode: "GRAPH_INVALID")

  # Pass 2.92 — RL-14.4 layer admissibility (M-41 staged enforcement, S5).
  # The fact was collected at the I/O boundary (head content snapshot of the
  # changed src/core/** files + the WORKSPACE pair registry injected into the
  # trusted judge) and is only consumed here — pure, one pass, no re-fetch.
  # A FAIL denies with the M-41-specific code and cites the offending
  # (file, line, target) so the block is never mistakable for another check's
  # failure; UNKNOWN (lock unreadable, content unobtainable) denies
  # fail-closed; None (a legacy record predating M-41) skips — the single
  # production collection path always binds the fact and binds UNKNOWN, never
  # None, on collection failure.
  if F.layerAdmissibility.isSome:
    let L = F.layerAdmissibility.get
    if L.status == lasUnknown:
      return MergeAdmissionOutcome(
        result: mergeAborted,
        reason: "RL-14.4 (M-41) layer admissibility UNKNOWN: " & L.note &
          " — the PR introduces no provably-approved forbidden-layer import set (fail-closed)",
        reasonCode: "LAYER_ADMISSIBILITY_UNKNOWN")
    if L.status == lasFail:
      if L.violations.len == 0:
        return MergeAdmissionOutcome(
          result: mergeAborted,
          reason: "RL-14.4 (M-41) layer admissibility FAIL with no cited violation — inconsistent fact (fail-closed)",
          reasonCode: "LAYER_ADMISSIBILITY_UNKNOWN")
      let cited = firstLayerViolation(L)
      case cited.verdict
      of livRejected:
        return MergeAdmissionOutcome(
          result: mergeAborted,
          reason: "RL-14.4 (M-41) layer violation: " & cited.file & ":" & $cited.line &
            " imports '" & cited.target & "' -> '" & cited.normalizedTarget &
            "' — forbidden layer from domain, no approved (source, target) pair covers it" &
            " — merge blocked (" & $L.violations.len & " violation(s); full list in layerAdmissibility.violations)",
          reasonCode: "LAYER_FORBIDDEN_IMPORT")
      of livUnparsed:
        return MergeAdmissionOutcome(
          result: mergeAborted,
          reason: "RL-14.4 (M-41) unparseable import: " & cited.file & ":" & $cited.line &
            " '" & cited.target & "' resolves to no canonical target (normalization contract rule 10)" &
            " — merge blocked, fail-closed (" & $L.violations.len &
            " violation(s); full list in layerAdmissibility.violations)",
          reasonCode: "LAYER_IMPORT_UNPARSED")

  # Pass 2.95 — candidate binding (ADR-0020 §2b): when the subject is a
  # speculative candidate, the run↔identity binding must have been verified at
  # the I/O boundary; an unbound candidate never admits (missing ≠ valid empty).
  if V.candidate.isSome:
    let C = V.candidate.get
    if not C.bindingVerified:
      let treeHint = if C.candidateTreeDigest.len >= 8:
        C.candidateTreeDigest[0 .. 7]
      else:
        C.candidateTreeDigest
      return MergeAdmissionOutcome(
        result: mergeAborted,
        reason: "candidate " & treeHint & " run↔identity binding not verified — fail-closed",
        reasonCode: "BINDING_MISMATCH")

  # Pass 2.96 — certificate continuity (certification-continuity Phase 5,
  # contract §5 INV-1): when a subject-continuity certificate is bound to this
  # admission, the certified subject MUST equal the actual merge candidate
  # (exact baseSha AND headSha equality — the actuator resolves the same
  # certificate by the (baseSha, headSha) PAIR in loadLedgerCertFor, so a
  # head-only match admitted a certificate the actuator could never load) and
  # its digest set MUST equal the CURRENT policy/scope state. Every check is
  # exact equality on the snapshot facts — the predicate never re-derives trees
  # (INV-3).
  # missing ≠ valid empty: a demanded-but-absent certificate denies NO_CERT.
  if F.certificate.isSome or F.certRequired:
    if F.certificate.isNone:
      return MergeAdmissionOutcome(
        result: mergeAborted,
        reason: "no subject-continuity certificate for this PR/subject — certified admission requires one (re-attest)",
        reasonCode: "NO_CERT")
    let C = F.certificate.get
    if not C.signatureOk:
      return MergeAdmissionOutcome(
        result: mergeAborted,
        reason: "certificate " & C.subjectId[0 ..< min(C.subjectId.len, 12)] &
          " attestation signature invalid (fail-closed)",
        reasonCode: "CERT_INVALID")
    if C.headSha != V.headSha:
      return MergeAdmissionOutcome(
        result: mergeAborted,
        reason: "certified headSha " & C.headSha[0 ..< min(C.headSha.len, 12)] &
          " != actual PR head " & V.headSha[0 ..< min(V.headSha.len, 12)] &
          " — certified subject != PR head (INV-1); head changed — re-attest",
        reasonCode: "SUBJECT_MISMATCH")
    if C.baseSha != V.baseSha:
      return MergeAdmissionOutcome(
        result: mergeAborted,
        reason: "certified baseSha " & C.baseSha[0 ..< min(C.baseSha.len, 12)] &
          " != admission base " & V.baseSha[0 ..< min(V.baseSha.len, 12)] &
          " — certified subject != admitted base (INV-1); the actuator resolves the " &
          "certificate by the (baseSha, headSha) pair, so this cert would never load — re-attest",
        reasonCode: "SUBJECT_MISMATCH")
    if C.policyDigest != C.currentPolicyDigest:
      return MergeAdmissionOutcome(
        result: mergeAborted,
        reason: "certificate policyDigest " & C.policyDigest[0 ..< min(C.policyDigest.len, 12)] &
          " != current sha256(merge_admission.json) " & C.currentPolicyDigest[0 ..< min(C.currentPolicyDigest.len, 12)] &
          " — re-attest under the current policy",
        reasonCode: "POLICY_MISMATCH")
    if C.scopeDigest != C.currentScopeDigest:
      return MergeAdmissionOutcome(
        result: mergeAborted,
        reason: "certificate scopeDigest " & C.scopeDigest[0 ..< min(C.scopeDigest.len, 12)] &
          " != current sha256(verification_scope.lock) " & C.currentScopeDigest[0 ..< min(C.currentScopeDigest.len, 12)] &
          " — re-attest under the current verification scope",
        reasonCode: "SCOPE_MISMATCH")

  # Pass 2.96b — vault certificate continuity (proof-required admission
  # contract docs/spec/proof_required_admission_contract.md §2–§4): the
  # SIBLING of Pass 2.96 (rotation-Pass 2.97 precedent — numbered sibling
  # insertion, never a rewrite of the 2.96 equality ladder). When the
  # admission demands vault certificates (vaultCertRequired) and the
  # collector bound a target set, every in-scope manifest target must carry
  # an EXISTING vault certificate whose content irHash equals the manifest
  # identity, and the policy-epoch equalities must hold exactly. Reason
  # vocabulary is the journal strings NO_CERT / SUBJECT_MISMATCH /
  # POLICY_MISMATCH / SCOPE_MISMATCH — the same strings as Pass 2.96 mean
  # the same thing; which pass fired is identified by the reason preamble.
  # fact = none (no targets) is a recorded SKIP (contract §4.3), not a
  # silent one — the dry-run JSON marks it. Precedence is the pass order:
  # trust surface (2.7/2.8) and TRUST_SURFACE_INCOMPLETE fire before this
  # pass, so the TRUST_SURFACE_MODIFIED manual-merge path (dryRunExit 0)
  # outranks the vault demand (contract §3 HARD).
  if F.vaultCertRequired and F.vaultCert.isSome:
    let VC = F.vaultCert.get
    for t in VC.targets:
      if not t.certPresent:
        return MergeAdmissionOutcome(
          result: mergeAborted,
          reason: "Pass 2.96b: no vault certificate for in-scope kernel symbol " &
            t.modulePath & "::" & t.functionName &
            " (manifest irHash " & t.irHash[0 ..< min(t.irHash.len, 12)] &
          " — proof-required admission requires one (re-attest)",
          reasonCode: "NO_CERT")
      if not t.irHashMatch:
        return MergeAdmissionOutcome(
          result: mergeAborted,
          reason: "Pass 2.96b: vault certificate identity mismatch for " &
            t.modulePath & "::" & t.functionName &
            " — content irHash != manifest irHash " & t.irHash[0 ..< min(t.irHash.len, 12)] &
            " (filename == content irHash is the cert_integrity_gate convention)",
          reasonCode: "SUBJECT_MISMATCH")
    if VC.policyEpochDigest != VC.currentPolicyDigest:
      return MergeAdmissionOutcome(
        result: mergeAborted,
        reason: "Pass 2.96b: policy epoch mismatch — vault target set bound under " &
          "sha256(merge_admission.json)@B " & VC.policyEpochDigest[0 ..< min(VC.policyEpochDigest.len, 12)] &
          " != current " & VC.currentPolicyDigest[0 ..< min(VC.currentPolicyDigest.len, 12)] &
          " — the evaluation environment's policy != B (re-attest)",
        reasonCode: "POLICY_MISMATCH")
    if VC.scopeEpochDigest != VC.currentScopeDigest:
      return MergeAdmissionOutcome(
        result: mergeAborted,
        reason: "Pass 2.96b: scope epoch mismatch — vault target set bound under " &
          "sha256(verification_scope.lock)@B " & VC.scopeEpochDigest[0 ..< min(VC.scopeEpochDigest.len, 12)] &
          " != current " & VC.currentScopeDigest[0 ..< min(VC.currentScopeDigest.len, 12)] &
          " — the evaluation environment's scope != B (re-attest)",
        reasonCode: "SCOPE_MISMATCH")

  # Pass 2.97 — rotation/closure adjudication (ADR-0025 §7/§13, plan Phase 4):
  # when the gate supplied the closure inputs, a closure mismatch
  # (set(H) != set(B) != set(pin@B)) authorizes ROTATION only when every
  # condition holds; any failure = NOT-ADMIT with the explicit ROT_* code
  # (same denial style as the passes above).
  # UNSPECIFIED fail-closed (the committed verdict-stage contract,
  # admission-check.yml :1446/:1541 — DEBT#501 closed FIXED): inputs absent
  # (rotation = none — the SL-02 pre-gate state, where scope_sl02 is never
  # true and the derived-closure artifact is never fetched) means the closure
  # adjudication did not run, and informational absence never reads as clean
  # (missing ≠ valid empty) → NOT-ADMIT ROT_UNSPECIFIED. UNSPECIFIED !=
  # NORMAL/ROTATION is exactly the contract: a post-gate transient download
  # loss fails closed here rather than admitting unevaluated. The pure
  # adjudication itself is computed at the I/O boundary (file/env reads there,
  # never in the predicate).
  if F.rotation.isNone:
    return MergeAdmissionOutcome(
      result: mergeAborted,
      reason: "rotation qualification UNSPECIFIED — closure inputs absent (derived-closure " &
        "artifact not supplied), the closure adjudication did not run — " &
        "informational absence never reads as clean (missing ≠ valid empty, fail-closed)",
      reasonCode: "ROT_UNSPECIFIED")
  if F.rotation.get.qualification == rqNone:
    let rot = F.rotation.get
    return MergeAdmissionOutcome(
      result: mergeAborted,
      reason: rot.reason,
      reasonCode: rot.reasonCode)

  # Final GO — all product passes cleared, base freshness included (Pass 0).
  # The base binding is provenance identity; landing-path freshness
  # enforcement is the merge queue's invalidation alone (ADR-0027 P5).
  let boundMain = mainSha[0 ..< min(mainSha.len, 12)]
  MergeAdmissionOutcome(
    result: mergeGo,
    reason: "admission passes cleared (base provenance bound to main " & boundMain &
      "; landing freshness enforced by merge-queue invalidation — ADR-0027 P5)",
    reasonCode: "GO")

func effectiveCertRequired*(preflight: bool): bool {.raises: [].} =
  ## Venue-split certificate requirement (ADR-0032 (c)): the canonical
  ## admission ALWAYS demands a subject-continuity certificate (`CertRequired`
  ## — the fail-closed default, unchanged). The PR preflight venue evaluates
  ## the remaining passes without it — reachable ONLY through the explicit
  ## `ax merge --preflight` opt-in, and its result is a preflight signal,
  ## never a landing-eligibility judgment (the canonical verdict is the
  ## merge_group verdict, ADR-0032 (a),(f)).
  CertRequired and not preflight

func dryRunExit*(o: MergeAdmissionOutcome): int {.raises: [].} =
  ## The admission verdict projected onto a process exit code — the single
  ## source of truth for the dry-run exit contract shared by runMergeCli and
  ## runMergeActuatorCli. The CI required check's conclusion IS this exit
  ## (Axiom decides, GitHub enforces); run-level input failures exit non-zero
  ## at their own boundary and never reach here.
  ##
  ## Exit semantics are bound to the admission policy (config/policy/
  ## merge_admission.json trustSurface contract), not to a blanket rule:
  ##   mergeGo                  → 0
  ##   TRUST_SURFACE_MODIFIED   → 0 — the policy routes trust-surface changes
  ##     to the architect manual-merge path ("manual merge required"); a red
  ##     required check would seal the path the contract itself opens
  ##     (CODEOWNERS review + TWS pin ceremony are the enforcement there).
  ##     The marker stays loud in the verdict log and the --json record so the
  ##     manual path is never silent.
  ##   every other NOT-ADMIT    → 1 — fail-closed binding (STALE_BASE,
  ##     GRAPH_INVALID, BINDING_MISMATCH, NO_CERT, ROT_*, TRUST_SURFACE_INCOMPLETE …).
  if o.result == mergeGo:
    0
  elif o.reasonCode == "TRUST_SURFACE_MODIFIED":
    0
  else:
    1

# ---------------------------------------------------------------------------
# I/O helpers — GitHub REST API (stdlib httpclient)
# ---------------------------------------------------------------------------

proc loadJson*(text: string): JsonNode {.raises: [CatchableError].} =
  if text.len == 0:
    return %*{}
  try:
    parseJson(text)
  except CatchableError:
    %*{}

proc checkedStr*(node: JsonNode; path: varargs[string]): string {.raises: [CatchableError].} =
  if node.isNil:
    return ""
  var n = node
  for key in path:
    try:
      if n.kind == JObject and n.hasKey(key):
        n = n[key]
      else:
        return ""
    except CatchableError:
      return ""
  if not n.isNil and n.kind == JString:
    n.getStr()
  else:
    ""

proc checkedInt*(node: JsonNode; path: varargs[string]): int {.raises: [CatchableError].} =
  var n = node
  for key in path:
    try:
      if n.kind == JObject and n.hasKey(key):
        n = n[key]
      else:
        return 0
    except CatchableError:
      return 0
  if n.kind == JInt:
    int(n.getInt())
  else:
    0

proc ghGet*(url: string; token: string): JsonNode {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## GET /{url} returning parsed JSON (2xx only). Non-2xx or transport
  ## failure raises with the HTTP status code embedded — fail-closed, never
  ## swallowed. The status in the error message is the actionable denial
  ## evidence for the actuator's merge-failure classification.
  var client = newHttpClient()
  defer: client.close()
  client.headers = newHttpHeaders([
    ("Authorization", "Bearer " & token),
    ("Accept", "application/vnd.github.v3+json")])
  var body = ""
  let requestT0 = epochTime()
  try:
    let resp = client.request(url, HttpGet)
    logInfo("merge_cli", "phase=gh-request url=" & url &
      " elapsed_ms=" & $int((epochTime() - requestT0) * 1000.0) & " status=" & $resp.code)
    let status = resp.code
    if status.int div 100 != 2:
      let msg = checkedStr(loadJson(resp.body), "message")
      raise newException(CatchableError,
        "GitHub API HTTP " & $status.int & " for " & url &
        (if msg.len > 0: ": " & msg else: ""))
    body = resp.body
  except HttpRequestError as e:
    logInfo("merge_cli", "phase=gh-request url=" & url &
      " elapsed_ms=" & $int((epochTime() - requestT0) * 1000.0) & " outcome=transport-error")
    raise newException(CatchableError, "GitHub API " & $e.msg & " for " & url)
  loadJson(body)

# ---------------------------------------------------------------------------
# GitHub API calls — each logical fact source fetched ONCE per snapshot
# ---------------------------------------------------------------------------

proc getPrFiles*(prNumber: int; token: string; repo: string = DefaultRepo): tuple[files: seq[tuple[filename, previous: string]], complete: bool] {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Full-paginate GET /pulls/{N}/files. `complete=false` when pagination did
  ## not terminate cleanly or the 3000-file cap was reached (listing cannot
  ## be proven complete → fail-closed upstream).
  var
    page = 1
    files: seq[tuple[filename, previous: string]] = @[]
    terminatedCleanly = false
  while true:
    let j = ghGet("https://api.github.com/repos/" & repo & "/pulls/" & $prNumber &
      "/files?per_page=100&page=" & $page, token)
    if j.kind != JArray:
      # Non-array response mid-pagination = incomplete listing.
      return (files, false)
    let elems = j.getElems()
    if elems.len == 0:
      # Empty page = confirmed end of listing (only reached when the previous
      # page was exactly per_page-sized).
      terminatedCleanly = true
      break
    for f in elems:
      files.add((checkedStr(f, "filename"), checkedStr(f, "previous_filename")))
    if elems.len < 100:
      # Partial page = natural end of listing.
      terminatedCleanly = true
      break
    inc page
  # Completeness = clean termination AND below the 3000-file cap (at the cap
  # the API silently omits files, so completeness is unprovable).
  let complete = terminatedCleanly and files.len < PrFilesCap
  (files, complete)

func decodeBase64*(s: string): string {.raises: [].} =
  ## Minimal base64 decoder (stdlib-free, allocation-safe).
  const tbl = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  proc val(c: char): int {.raises: [].} =
    let i = tbl.find(c)
    if i >= 0: i else: 0
  var acc = 0
  var bits = 0
  for c in s:
    if c == '=':
      break
    acc = (acc shl 6) or val(c)
    bits += 6
    if bits >= 8:
      bits -= 8
      result.add(char((acc shr bits) and 0xFF))

proc getChangeGraphFacts*(headSha: string; token: string; repo: string = DefaultRepo): ChangeGraphStatus {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## ChangeGraphFacts(H): fetch config/changes/*.toml at ref=H (immutable
  ## snapshot; flat-only contract — subdirectories are fixtures) and evaluate.
  let j = ghGet("https://api.github.com/repos/" & repo & "/contents/config/changes?ref=" & headSha, token)
  if j.kind != JArray:
    return ChangeGraphStatus(valid: false, violations: @[ChangeGraphViolation(
      kind: cgvEmptyGraph,
      message: "config/changes listing unavailable at ref=" & headSha)])
  var nodes: seq[ChangeManifestNode] = @[]
  for entry in j.getElems():
    if checkedStr(entry, "type") == "file" and checkedStr(entry, "name").endsWith(".toml"):
      let dl = ghGet(checkedStr(entry, "url").split("?")[0] & "?ref=" & headSha, token)
      let contentB64 = checkedStr(dl, "content")
      if contentB64.len > 0:
        # GitHub contents API returns base64 content (possibly with newlines).
        let content = decodeBase64(contentB64.replace("\n", ""))
        nodes = nodes & parseChangeManifestContent(content)
  evaluateChangeGraph(nodes)

# ---------------------------------------------------------------------------
# RL-14.4 layer admissibility (M-41, S5) — collection (I/O boundary)
# ---------------------------------------------------------------------------

proc fetchFileAtRef*(path: string; refSha: string; token: string;
                     repo: string = DefaultRepo): Result[string, int]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## GET /contents/{path}?ref={refSha} → decoded file text — the head-side
  ## snapshot reader for the M-41 fact (same base64 contents contract as
  ## getChangeGraphFacts). ok(content); err(httpStatus) where 404 = the path
  ## does not exist at the ref (a file REMOVED by the PR — introduces no
  ## import), 0 = transport failure, -1 = non-base64/empty body. Everything
  ## except ok/404 is a collection failure the caller must fail-closed on.
  var client = newHttpClient()
  defer: client.close()
  client.headers = newHttpHeaders([
    ("Authorization", "Bearer " & token),
    ("Accept", "application/vnd.github.v3+json")])
  var status = 0
  var body = ""
  try:
    let resp = client.request(
      "https://api.github.com/repos/" & repo & "/contents/" & path & "?ref=" & refSha, HttpGet)
    status = resp.code.int
    if status div 100 != 2:
      return err(status)
    body = resp.body
  except CatchableError:
    return err(status)
  let j = loadJson(body)
  if checkedStr(j, "encoding") != "base64":
    return err(-1)
  let contentB64 = checkedStr(j, "content")
  if contentB64.len == 0:
    return err(-1)
  ok(decodeBase64(contentB64.replace("\n", "")))

func extractQuotedEntries(value: string): seq[string] {.raises: [].} =
  ## Double-quoted elements of a single-line "[...]" array value — mirrors the
  ## runtime gate's extractQuotedEntries so admission reads the registry
  ## entries byte-identically to layer_enforcement_gate.parsePairRegistry.
  result = @[]
  let v = value.strip()
  if not (v.startsWith("[") and v.endsWith("]")):
    return
  var current = ""
  var inString = false
  for i in 1 ..< v.len - 1:
    let ch = v[i]
    if inString:
      if ch == '"':
        result.add(current)
        current = ""
        inString = false
      else:
        current.add(ch)
    elif ch == '"':
      inString = true

func isDateFormExpiry(expires: string): bool {.raises: [].} =
  ## "yyyy-MM-dd" shape — mirrors the gate's expiry classification: only
  ## date-form expiries lapse; release-form expiries (e.g. "v0.5.0") are
  ## release-gated and kept (decision §3.2).
  expires.len == 10 and expires.count('-') == 2

proc parseLayerPairRegistry*(lockPath: string): Result[seq[(string, string)], string]
    {.raises: [CatchableError, OSError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read the approved (source, target) pair registry from the WORKSPACE
  ## policy lock — the base-state authority, so a PR can never approve its own
  ## crossing. Mirrors layer_enforcement_gate.parsePairRegistry semantics:
  ## entry format "source.nim|target|reason|expires"; ONLY (source, target) is
  ## injected (the judging function's parameter contract, DEBT#495); a
  ## date-form expiry in the past is dropped (an expired exception reverts to
  ## a violation — fail closed); an unparseable expiry grants nothing; a
  ## malformed entry grants nothing (logged). err = the lock itself cannot be
  ## read or the registry key is absent — the caller maps err to UNKNOWN
  ## (deny), never to "no exceptions" silently.
  if not fileExists(lockPath):
    return err("policy lock not found: " & lockPath)
  var content = ""
  try:
    content = readFile(lockPath)
  except CatchableError as e:
    return err("policy lock unreadable (" & lockPath & "): " & e.msg)
  var found = false
  var pairs: seq[(string, string)] = @[]
  for line in content.splitLines():
    let stripped = line.strip()
    if stripped.len == 0 or stripped.startsWith("#"):
      continue
    if not (stripped.startsWith(LayerPairRegistryKey) and stripped.contains('=')):
      continue
    found = true
    let eqIdx = stripped.find('=')
    for entry in extractQuotedEntries(stripped[(eqIdx + 1)..^1]):
      let fields = entry.split('|')
      if fields.len != 4:
        logError("merge_cli", "[m41] malformed pair entry (expected source|target|reason|expires): " &
          entry & " — grants nothing")
        continue
      let expires = fields[3].strip()
      if isDateFormExpiry(expires):
        var expired = false
        try:
          expired = parse(expires, "yyyy-MM-dd") < now()
        except CatchableError:
          expired = true  # unparseable expiry grants nothing (fail closed)
        if expired:
          logInfo("merge_cli", "[m41] expired pair exception dropped: " & fields[0].strip() &
            " -> " & fields[1].strip() & " (expires " & expires & ")")
          continue
      pairs.add((fields[0].strip(), fields[1].strip()))
    break
  if not found:
    return err("pair registry '" & LayerPairRegistryKey & "' not found in " & lockPath)
  ok(pairs)

proc collectLayerAdmissibility*(files: seq[tuple[filename, previous: string]];
                                headSha: string; token: string;
                                repo: string = DefaultRepo): LayerAdmissibilityFacts
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The I/O half of the M-41 fact — fetch only, the verdict is the PURE
  ## layerAdmissibilityVerdict. Changed/added src/core/** .nim files are
  ## snapshotted at the PR head (fetchFileAtRef; a 404 = removed at H — a
  ## removed file introduces no import) and the workspace pair registry is
  ## injected into the trusted judge. Every collection failure (lock
  ## unreadable / registry key absent / content unobtainable) binds UNKNOWN —
  ## Pass 2.92 denies fail-closed; this proc never silently passes.
  var coreTotal = 0
  for (fn, prev) in files:
    if isCoreSourcePath(fn):
      inc coreTotal
  let lockRes = parseLayerPairRegistry(LayerPolicyLockPath)
  if lockRes.isErr:
    return unknownLayerFacts(lockRes.error &
      " — approved (source, target) pairs cannot be established", coreTotal)
  var coreContents: seq[tuple[path, content: string]] = @[]
  for (fn, prev) in files:
    if not isCoreSourcePath(fn):
      continue
    let fetchRes = fetchFileAtRef(fn, headSha, token, repo)
    if fetchRes.isErr:
      if fetchRes.error == 404:
        continue
      return unknownLayerFacts("src/core file content unobtainable at head " &
        headSha[0 ..< min(headSha.len, 12)] & ": " & fn &
        " (status " & $fetchRes.error & ")", coreTotal)
    coreContents.add((fn, fetchRes.get))
  layerAdmissibilityVerdict(coreContents, lockRes.get)

# ---------------------------------------------------------------------------
# collectAdmissionFacts — the single I/O boundary of one admission evaluation
# ---------------------------------------------------------------------------

proc loadDerivedLineSet(label, path: string): Result[HashSet[string], string]
    {.raises: [CatchableError, OSError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Derived line-file → line-set at the I/O boundary, fail-closed on
  ## missing/malformed input (never an empty set in place of a failure).
  if not fileExists(path):
    return err(label & " file missing: " & path & " (fail-closed)")
  let res = parseDerivedSet(readFile(path))
  if res.isErr:
    return err(label & " (" & path & "): " & res.error & " (fail-closed)")
  ok(res.get)

proc loadTrustSurface*(policyPath: string = TrustSurfacePolicyPath): Result[seq[string], string]
    {.raises: [CatchableError, OSError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Effective trust surface = policy SSOT `trustSurface` ∪
  ## TrustSurfaceTombstones (protection-retention). The policy file is read
  ## from the workspace cwd — the same CWD-relative resolution as
  ## loadPinBClosure's pin@B, i.e. the B checkout in the MG verdict job — so
  ## the evaluation is anchored to B and a PR editing the policy cannot
  ## re-classify itself. Fail-closed: missing file, parse failure, or an
  ## invalid trustSurface array are err — never an empty set in place of a
  ## failure (loadPinBClosure error semantics).
  if not fileExists(policyPath):
    return err("trust surface policy missing: " & policyPath &
      " not found in workspace cwd (fail-closed)")
  try:
    let parseRes = parseTrustSurfaceJson(
      parseJson(stripJsoncComments(readFile(policyPath))))
    if parseRes.isErr:
      return err("trust surface policy invalid (" & policyPath & "): " &
        parseRes.error & " (fail-closed)")
    ok(parseRes.get & TrustSurfaceTombstones)
  except CatchableError as e:
    return err("trust surface policy parse failure (" & policyPath & "): " &
      e.msg & " (fail-closed)")

proc loadPinBClosure(): Result[Option[HashSet[string]], string]
    {.raises: [CatchableError, OSError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## pin@B — the B checkout's trusted_writer_set.json (workspace cwd).
  if not fileExists(RotationPinBPath):
    return err("pin@B missing: " & RotationPinBPath & " not found in workspace cwd (fail-closed)")
  try:
    let pinBRes = pinClosureLineSet(parseJson(stripJsoncComments(readFile(RotationPinBPath))))
    if pinBRes.isErr:
      return err("pin@B invalid (" & RotationPinBPath & "): " & pinBRes.error & " (fail-closed)")
    ok(pinBRes.get)
  except CatchableError as e:
    return err("pin@B parse failure (" & RotationPinBPath & "): " & e.msg & " (fail-closed)")

proc collectRotationInputs*(derivedHPath, derivedBPath, derivedMPath, pinHPath: string;
                            changed: seq[string];
                            listingComplete: bool): Result[Option[RotationAdjudication], string]
    {.raises: [CatchableError, OSError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Rotation/closure adjudication inputs (ADR-0025 §7/§13 + Amendment F):
  ## env-supplied derived closure line-files + pin files are read HERE (the
  ## I/O boundary) and folded into the pure adjudication. ok(none) = NO
  ## closure env supplied → qualification UNSPECIFIED — the VERDICT, not the
  ## collector, fail-closes on it (Pass 2.97 ROT_UNSPECIFIED, admission-check
  ## .yml :1446/:1541).
  ## Run-level errors (distinct from verdicts — caller exits non-zero):
  ##   * partial supply (one derived path set, or pin@H alone) — a
  ##     misconfigured gate must not silently downgrade to UNSPECIFIED;
  ##   * derived line-file unreadable/malformed (H, B, or the candidate-delta
  ##     M leg — Amendment F's third derivation, the closure OF the
  ##     gate-verified candidate tree);
  ##   * pin@B (workspace cwd = B checkout) missing/unparsable/malformed —
  ##     the old-anchor fact ③ requires pin@B;
  ##   * PR files listing incomplete — the allowlist cannot be proven.
  ## Verdict-level failures (ROT_NEW_PIN / ROT_GENESIS_INVALID): pin@H
  ## missing/unreadable/unparsable → pinH = none — only the ④ fact needs it.
  ## The candidate-tree EQUALITY fact (M == the tested landing candidate) is
  ## established upstream by the gate (CANDIDATE_TREE_MISMATCH-class gate) —
  ## this collector consumes the verified derived(M) file, it cannot re-derive
  ## a tree.
  if derivedHPath.len == 0 and derivedBPath.len == 0 and derivedMPath.len == 0 and
     pinHPath.len == 0:
    return ok(none(RotationAdjudication))
  if derivedHPath.len == 0 or derivedBPath.len == 0 or derivedMPath.len == 0:
    return err("closure inputs partially supplied (derivedH='" & derivedHPath &
      "', derivedB='" & derivedBPath & "', derivedM='" & derivedMPath &
      "') — gate must supply all three derived line-files (fail-closed)")
  let hRes = loadDerivedLineSet(EnvDerivedHPath, derivedHPath)
  if hRes.isErr:
    return err(hRes.error)
  let bRes = loadDerivedLineSet(EnvDerivedBPath, derivedBPath)
  if bRes.isErr:
    return err(bRes.error)
  let mRes = loadDerivedLineSet(EnvDerivedMPath, derivedMPath)
  if mRes.isErr:
    return err(mRes.error)
  let pinBRes = loadPinBClosure()
  if pinBRes.isErr:
    return err(pinBRes.error)
  # pin@H — the H candidate root's copy of trusted_writer_set.json (the NEW
  # anchor). Missing/unreadable → none → condition ④ fails (verdict-level).
  var pinH: Option[HashSet[string]] = none(HashSet[string])
  if pinHPath.len > 0:
    if fileExists(pinHPath):
      try:
        let pinHRes = pinClosureLineSet(parseJson(stripJsoncComments(readFile(pinHPath))))
        if pinHRes.isErr:
          logWarn("merge_cli", "pin@H uninterpretable (" & pinHPath & "): " & pinHRes.error &
            " — rotation new-anchor condition will fail (fail-closed)")
        else:
          pinH = pinHRes.get
      except CatchableError as e:
        logWarn("merge_cli", "pin@H unreadable (" & pinHPath & "): " & e.msg &
          " — rotation new-anchor condition will fail (fail-closed)")
    else:
      logWarn("merge_cli", EnvPinHPath & " file missing: " & pinHPath &
        " — rotation new-anchor condition will fail (fail-closed)")
  if not listingComplete:
    return err("PR files listing incomplete — rotation allowlist cannot be proven (fail-closed)")
  ok(some(adjudicateRotation(hRes.get, bRes.get, mRes.get, pinBRes.get, pinH, changed)))

proc collectCertificateContinuityFacts*(headSha: string; token: string; repo: string = DefaultRepo): Result[Option[CertificateContinuityFacts], string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}

proc certificateFactFromPath(certPath, headSha: string): Result[CertificateContinuityFacts, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}

proc collectVaultCertFacts*(baseSha, headSha: string; changedFiles: seq[string];
                            token: string; repo: string = DefaultRepo): Result[Option[VaultCertContinuityFacts], string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}

proc collectAdmissionFacts*(prNumber: int; token: string; eventBaseSha: string; repo: string = DefaultRepo; certPath: string = ""; preflight = false): tuple[record: VerificationRecord, prJson: JsonNode] {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Collect ALL admission facts for a PR into one immutable snapshot bound
  ## to the head SHA observed first. Each logical fact source is fetched
  ## exactly once (pagination is an implementation detail of the snapshot).
  ##
  ## `preflight` is the ADR-0032 PR-preflight venue switch (explicit
  ## `--preflight` opt-in only — never the canonical path): the certificate
  ## demand becomes `effectiveCertRequired(preflight)` so the preflight
  ## signal can evaluate without a subject-continuity certificate. The
  ## canonical evaluation keeps `certRequired = CertRequired = true`
  ## (fail-closed default, NO_CERT on absence).
  ##
  ## `certPath` is the attestation tier's artifact handoff (ADR-0022 §4, the
  ## `--cert` flag): when a certificate artifact pre-binds against THIS head
  ## (the exact boundary verification of `certificateFactFromPath`), it
  ## provably replaces the ledger-scan fact — `bindCertificateSource` binds
  ## the identical fact over it — so the full-ledger scan is skipped as dead
  ## computation. Any pre-bind failure falls back to the scan; the denial
  ## then stays fail-closed at `bindCertificateSource`.
  ##
  ## `eventBaseSha` is the EVENT-FROZEN base anchor — `AXIOM_MAIN_SHA`
  ## (`github.event.pull_request.base.sha || github.event.merge_group.base_sha`),
  ## the very base the run's evidence was produced against — and it is the ONLY
  ## base this snapshot records. The LIVE `pulls/N` `base.sha` is deliberately
  ## NOT read: the merge queue advances the base while the PR API snapshot lags,
  ## so a live anchor made every landing PR invalidate every other open PR with
  ## a STALE_BASE false deny (measured 2026-10-04: ~247 min of wasted CI). The
  ## caller rejects an empty anchor before calling, which is why
  ## BASE_UNRECORDED is unreachable from the CLI paths (the fail-closed branch
  ## stays for any caller that has no anchor). The same anchor is the ledger
  ## certificate's construction base, so the actuator's (base, head) lookup key
  ## stays aligned with the freshness anchor (Pass 2.96 enforces the pairing).
  # Phase attribution — wall-clock into stderr logs ONLY; never enters the
  # dry-run JSON line, the journal, or any certificate payload.
  let tPr0 = epochTime()
  let prJson = ghGet("https://api.github.com/repos/" & repo & "/pulls/" & $prNumber, token)
  logInfo("merge_cli", "phase=fact-pr elapsed_ms=" & $int((epochTime() - tPr0) * 1000.0))
  let headSha = checkedStr(prJson, "head", "sha")
  let mergeableState = checkedStr(prJson, "mergeable_state")

  result.record.headSha = headSha
  result.record.baseSha = eventBaseSha

  # Check-evidence/rule-set collection removed (P12 GitHub delegation):
  # required-check runs, ruleset detection and the required-workflow verdict
  # facts were duplicates of the platform's merge-time authority.

  # (5) PR files — full pagination; completeness + rename-aware matching.
  let tFiles0 = epochTime()
  let (files, complete) = getPrFiles(prNumber, token, repo)
  logInfo("merge_cli", "phase=fact-pr-files elapsed_ms=" & $int((epochTime() - tFiles0) * 1000.0) &
    " files=" & $files.len & " complete=" & $complete)
  # Trust surface — evaluated from the policy SSOT in the workspace cwd (the
  # B checkout: a PR editing the policy cannot re-classify itself), unioned
  # with the compiled protection-retention tombstones. A load failure is a
  # run-level failure (fail-closed raise), not a verdict.
  let surfaceRes = loadTrustSurface()
  if surfaceRes.isErr:
    raise newException(CatchableError,
      "trust surface evaluation failed (run-level, fail-closed): " & surfaceRes.error)
  var hits: seq[TrustSurfaceHit] = @[]
  for (fn, prev) in files:
    let hit = trustSurfaceMatch(fn, prev, surfaceRes.get)
    if hit.isSome:
      hits.add(hit.get)

  # (5b) Rotation/closure adjudication (ADR-0025 §7/§13 + Amendment F) —
  # env-gated: the org gate supplies derived closure line-files (H / B / the
  # candidate-delta M leg) + the H-side pin via env. Env absent → ok(none) →
  # qualification UNSPECIFIED → the VERDICT fail-closes (Pass 2.97
  # ROT_UNSPECIFIED). Run-level input failures (partial supply, unreadable
  # derived file, pin@B parse failure, incomplete listing) RAISE —
  # fail-closed, distinct from verdicts.
  # changed = all PR paths — status A/M/D/R all count; rename sources too.
  var changedFiles: seq[string] = @[]
  for (fn, prev) in files:
    changedFiles.add(fn)
    if prev.len > 0 and prev notin changedFiles:
      changedFiles.add(prev)
  changedFiles.sort()

  # (5c) Vault-certificate facts (Pass 2.96b — proof-required admission
  # contract §1–§4): the (modulePath, functionName) → vault cert lookup
  # collector (new I/O primitive ①) + the policy-epoch equality inputs
  # (primitive ②). Absence of an in-scope manifest target is ok(none) —
  # the recorded skip the VERDICT marks; run-level read failures raise
  # (fail-closed), never read as absence.
  let tVault0 = epochTime()
  let vaultRes = collectVaultCertFacts(eventBaseSha, headSha, changedFiles, token, repo)
  logInfo("merge_cli", "phase=fact-vaultcert elapsed_ms=" & $int((epochTime() - tVault0) * 1000.0))
  if vaultRes.isErr:
    raise newException(CatchableError, vaultRes.error)
  var vaultFact: Option[VaultCertContinuityFacts] = none(VaultCertContinuityFacts)
  if vaultRes.get.isSome:
    vaultFact = some(vaultRes.get.get)

  let tRot0 = epochTime()
  let rotationRes = collectRotationInputs(
    getEnv(EnvDerivedHPath), getEnv(EnvDerivedBPath), getEnv(EnvDerivedMPath),
    getEnv(EnvPinHPath), changedFiles, complete)
  logInfo("merge_cli", "phase=fact-rotation elapsed_ms=" & $int((epochTime() - tRot0) * 1000.0))
  if rotationRes.isErr:
    raise newException(CatchableError,
      "rotation/closure adjudication failed (run-level, fail-closed): " & rotationRes.error)
  var rotationFact: Option[RotationAdjudication] = none(RotationAdjudication)
  if rotationRes.get.isSome:
    rotationFact = some(rotationRes.get.get)

  # (5c) RL-14.4 layer admissibility (M-41, S5) — the changed src/core/**
  # files are snapshotted at head and judged against the WORKSPACE (base)
  # pair registry. Collection failures bind UNKNOWN (deny) — they never
  # raise, because the layer verdict is verdict evidence, not a run-level
  # input failure; Pass 2.92 consumes the fact.
  let layerFact = collectLayerAdmissibility(files, headSha, token, repo)

  # (6) ChangeGraphFacts(H) — ref-pinned snapshot.
  let tGraph0 = epochTime()
  let graph = getChangeGraphFacts(headSha, token, repo)
  logInfo("merge_cli", "phase=fact-changegraph elapsed_ms=" & $int((epochTime() - tGraph0) * 1000.0))

  # (7) Certificate-continuity facts — bound at the I/O boundary (Phase 5,
  # INV-1). Missing is a fact; the predicate decides NO_CERT from certRequired.
  # Artifact handoff (--cert): a pre-bind that verifies against THIS head
  # yields exactly the fact bindCertificateSource binds afterwards (identical
  # boundary verification — certificateFactFromPath), so the full-ledger scan
  # would be dead computation and is skipped. A pre-bind failure (invalid
  # artifact, head drift, unreadable file) falls back to the scan and the
  # bindCertificateSource denial stays fail-closed.
  let tCert0 = epochTime()
  var certFact: Option[CertificateContinuityFacts] = none(CertificateContinuityFacts)
  var artifactFactBound = false
  if certPath.len > 0:
    let artPre = certificateFactFromPath(certPath, headSha)
    if artPre.isOk:
      certFact = some(artPre.get)
      artifactFactBound = true
      logInfo("merge_cli", "phase=fact-certledger skipped (artifact --cert fact replaces ledger scan)")
  if not artifactFactBound:
    let certFactsRes = collectCertificateContinuityFacts(headSha, token, repo)
    logInfo("merge_cli", "phase=fact-certledger elapsed_ms=" & $int((epochTime() - tCert0) * 1000.0))
    if certFactsRes.isErr:
      raise newException(CatchableError, certFactsRes.error)
    certFact = certFactsRes.get

  result.record.admission = some(AdmissionFacts(
    headSha: headSha,
    baseSha: eventBaseSha,
    prFileCount: files.len,
    listingComplete: complete,
    trustSurfaceHits: hits,
    changeGraph: graph,
    mergeableState: mergeableState,
    certificate: certFact,
    certRequired: effectiveCertRequired(preflight),
    rotation: rotationFact,
    vaultCert: vaultFact,
    vaultCertRequired: VaultCertRequired,
    layerAdmissibility: some(layerFact)))
  result.prJson = prJson

# ---------------------------------------------------------------------------
# Evidence logging — .axiom/gate_history.jsonl
# ---------------------------------------------------------------------------

proc getTimestamp*(): string {.raises: [OSError].} =
  format(now().utc, "yyyy-MM-dd'T'HH:mm:ss'Z'")

proc appendGateHistory*(entry: string) {.raises: [CatchableError, OSError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let path = ".axiom/gate_history.jsonl"
  var dir = parentDir(path)
  if not dirExists(dir):
    createDir(dir)
  var f = open(path, fmAppend)
  defer: f.close()
  f.write(entry & "\n")

proc logMergePublish*(prNumber: int; cert: JsonNode; baseSha, headSha, mergeSha, verdict: string)
    {.raises: [CatchableError, OSError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Append a merge-publish evidence record to .axiom/gate_history.jsonl —
  ## used for the merge-shape/continuity deny paths (Pass 7/8 fail-closed)
  ## and the final CC_PASSED record. Verdict vocabulary reuses
  ## continuityVerdictCode (CC_PASSED / CC_MISMATCH / CC_NO_CERT / CC_ERROR);
  ## merge-failure denials are journaled via logMergeAdmission instead.
  let entry = %*{
    "stage": "merge-publish",
    "timestamp": getTimestamp(),
    "prNumber": prNumber,
    "certId": cert{"subjectId"}.getStr(""),
    "baseSha": baseSha,
    "headSha": headSha,
    "mergeCommitSha": mergeSha,
    "verdict": verdict
  }
  appendGateHistory($entry)

proc logMergeAdmission*(headSha: string; testedBaseSha: string; mainSha: string;
                        decision: MergeAdmissionResult; reason: string; reasonCode: string; prNumber: int) {.raises: [CatchableError, OSError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Append a merge-admission evidence record to .axiom/gate_history.jsonl.
  let ts = getTimestamp()
  let entry = %*{
    "stage": "merge-admission",
    "timestamp": ts,
    "prNumber": prNumber,
    "headSha": headSha,
    "testedBaseSha": testedBaseSha,
    "mainSha": mainSha,
    "decision": $decision,
    "reasonCode": reasonCode,
    "reason": reason
  }
  appendGateHistory($entry & "\n")

# ---------------------------------------------------------------------------
# Merge execution — GitHub REST API server-side merge (merge method)
# ---------------------------------------------------------------------------

proc parseMergeSuccess*(node: JsonNode): Option[MergeOutcome] {.raises: [CatchableError].} =
  ## Extract the merge-commit OID L from a 2xx PUT /pulls/{n}/merge body.
  ## A 2xx whose body omits `sha` (or has an empty one) is unresolvable → None
  ## (fail-closed: L is the continuity fact source).
  if node.isNil or node.kind != JObject:
    return none(MergeOutcome)
  let sha = checkedStr(node, "sha")
  if sha.len == 0:
    return none(MergeOutcome)
  let mergedNode = node.getOrDefault("merged")
  let merged = if mergedNode.kind == JBool: mergedNode.getBool else: false
  some(MergeOutcome(
    mergeSha: sha,
    merged: merged,
    ghMessage: checkedStr(node, "message")))

proc requestGitHubPut*(url: string; body: string; token: string): Result[JsonNode, MergeFailure]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Single-shot PUT — NO retry loop. 2xx → ok(parsed body); any other status
  ## → err(MergeFailure) with the status + GitHub message + rate-limit headers
  ## (observational only — the actuator still never retries).
  var client = newHttpClient()
  defer: client.close()
  client.headers = newHttpHeaders([
    ("Authorization", "Bearer " & token),
    ("Accept", "application/vnd.github.v3+json"),
    ("Content-Type", "application/json")])
  try:
    let resp = client.request(url, HttpPut, body = body)
    if resp.code.int div 100 == 2:
      if resp.body.len == 0:
        return err(MergeFailure(httpStatus: resp.code.int,
          ghMessage: "empty 2xx merge response body (fail-closed)"))
      try:
        ok(parseJson(resp.body))
      except CatchableError as e:
        err(MergeFailure(httpStatus: resp.code.int,
          ghMessage: "merge response parse error: " & e.msg))
    else:
      let msgNode = loadJson(resp.body)
      err(MergeFailure(
        httpStatus: resp.code.int,
        ghMessage: checkedStr(msgNode, "message"),
        rateLimitRemaining: resp.headers.getOrDefault("x-ratelimit-remaining"),
        rateLimitReset: resp.headers.getOrDefault("x-ratelimit-reset"),
        retryAfter: resp.headers.getOrDefault("retry-after")))
  except HttpRequestError as e:
    err(MergeFailure(httpStatus: 0, ghMessage: $e.msg))

proc performMerge*(prNumber: int; headSha: string; token: string; repo: string = DefaultRepo): Result[MergeOutcome, MergeFailure]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The SINGLE actuation of a landing (ADR-0025 §1 M-B + Amendment A,
  ## plan rev.7 Phase 0): REST PUT /repos/{owner}/{repo}/pulls/{number}/merge
  ## with merge_method=merge and sha=headSha. `sha` is a HEAD PIN ONLY — the
  ## merge API has NO base compare-and-swap; base binding is enforced by the
  ## non-bypass actuator identity (A1: landing actuator identity ∉ effective
  ## bypass actors) + the ruleset strict evaluation at merge time (A2/E3).
  ## A3 (baseSha == current main tip) is a PRE-FLIGHT observation, NOT an
  ## atomic freshness guarantee. There is no local merge-tree construction,
  ## no ref mutation, no self-CAS — self-owned merge authority = 0 (E1).
  ## Single-shot — the CALLER classifies failures via one GET; there is never
  ## a merge-time retry.
  let url = "https://api.github.com/repos/" & repo & "/pulls/" & $prNumber & "/merge"
  var reqBody = %*{
    "merge_method": "merge",
    "sha": headSha
  }
  let resp = requestGitHubPut(url, $reqBody, token)
  if resp.isErr:
    return err(resp.error)
  let parsed = parseMergeSuccess(resp.get)
  if parsed.isNone:
    return err(MergeFailure(httpStatus: 200, ghMessage: "merge body missing sha (fail-closed)"))
  ok(parsed.get)

# ---------------------------------------------------------------------------
# Auto-merge arm command spec — `gh pr merge <N> --auto` (construction only)
# ---------------------------------------------------------------------------

func buildGhArmCommand*(prNumber: int; headSha: string): string {.raises: [].} =
  ## The ARM actuation command — `gh pr merge <N> --auto --match-head-commit
  ## <headSha>`. NO --merge/--squash/--rebase flag: the merge METHOD
  ## authority is the ruleset queue's merge_method, not the CLI (a missing
  ## strategy flag in non-interactive mode also FAILS if the queue vanished —
  ## fail-closed bonus). Execution is the operator's gh invocation: Axiom
  ## does not arm (the in-CLI arm-auto executor was removed with the
  ## arm-auto lane, 2026-10-03 decision-authority unification).
  "gh pr merge " & $prNumber & " --auto --match-head-commit " & headSha

# ---------------------------------------------------------------------------
# Merge failure classification — ONE observation GET, no merge-time retry
# ---------------------------------------------------------------------------

proc observePullState*(prNumber: int; token: string; repo: string = DefaultRepo): Result[JsonNode, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Single GET /repos/{repo}/pulls/{n} AFTER a failed merge request — the
  ## only classification evidence (head staleness / mergeable_state / GH
  ## message). Exactly one observation, never a retry loop.
  let url = "https://api.github.com/repos/" & repo & "/pulls/" & $prNumber
  let j = ghGet(url, token)
  if not j.isNil and j.kind == JObject:
    ok(j)
  else:
    err("observability GET " & url & " returned non-object (fail-closed)")

proc classifyMergeFailure*(failure: MergeFailure; expectedHead: string; prState: JsonNode): MergeDenial {.raises: [CatchableError].} =
  ## Classify a failed PUT /pulls/{n}/merge into the shared mergeAborted
  ## vocabulary with a precise machine reasonCode. Retry is NEVER produced
  ## here — every branch is final (fail-closed). `prState` is the observation
  ## GET response ("" / non-object → unresolvable, fail-closed).
  let ghMsg = failure.ghMessage
  let status = failure.httpStatus
  if prState.isNil or prState.kind != JObject:
    return MergeDenial(reason: "merge request failed (HTTP " & $status & "): " & ghMsg &
      " — observation GET non-object, classification unresolvable (fail-closed)",
      reasonCode: "MERGE_UNKNOWN")
  let currentHead = checkedStr(prState, "head", "sha")
  let mergeableState = checkedStr(prState, "mergeable_state")
  # Stale head — head moved away from the admitted H. New head requires
  # re-certification, which happens naturally via a newer workflow run.
  if currentHead.len > 0 and currentHead != expectedHead:
    return MergeDenial(
      reason: "merge failed (HTTP " & $status & "): " & ghMsg &
        " — PR head now " & currentHead & " != admitted head " & expectedHead &
        " (stale head — re-certification required, retry prohibited)",
      reasonCode: "STALE_HEAD",
      currentHead: currentHead)
  # 405/409 with head intact — the admission-time mergeability was ALREADY
  # non-null and the merge was refused anyway → hard deny.
  if status == 405 or status == 409:
    return MergeDenial(
      reason: "merge denied (HTTP " & $status & "): " & ghMsg &
        " — head unchanged but merge refused (mergeability=" & mergeableState & ")",
      reasonCode: "MERGE_DENIED",
      currentHead: currentHead)
  # 422 — API-level refusal. Deny.
  if status == 422:
    return MergeDenial(
      reason: "merge denied (HTTP 422): " & ghMsg &
        " — head unchanged, API refused (mergeability=" & mergeableState & ")",
      reasonCode: "MERGE_DENIED",
      currentHead: currentHead)
  # 403/429 — rate limiting; headers are observational evidence only, never a
  # retry trigger.
  if status == 403 or status == 429:
    return MergeDenial(
      reason: "merge denied (HTTP " & $status & "): " & ghMsg &
        " — rate limit (x-ratelimit-remaining=" & failure.rateLimitRemaining &
        ", x-ratelimit-reset=" & failure.rateLimitReset &
        ", retry-after=" & failure.retryAfter & ")",
      reasonCode: "RATE_LIMITED",
      currentHead: currentHead)
  MergeDenial(
    reason: "merge request failed (HTTP " & $status & "): " & ghMsg &
      " — head unchanged, unclassifiable status (fail-closed)",
    reasonCode: "MERGE_UNKNOWN",
    currentHead: currentHead)

# ---------------------------------------------------------------------------
# Post-merge shape observation — merge commit L, its parents, parent2 tree
# ---------------------------------------------------------------------------

proc resolveMergeShapeApi*(mergeSha: string; token: string; repo: string = DefaultRepo): Result[MainShape, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Resolve (L, parent1=base, parent2=head, parent2^{tree}) via the GitHub
  ## API alone — the CI-safe primary path (runner checks out main without a
  ## fetch, so no local MERGE_HEAD exists after a server-side merge).
  ## Fail-closed on any mismatch or unresolvable L.
  let commitUrl = "https://api.github.com/repos/" & repo & "/commits/" & mergeSha
  let commit = ghGet(commitUrl, token)
  if commit.isNil or commit.kind != JObject:
    return err("resolveMergeShapeApi: commit response for L " & mergeSha & " not an object (fail-closed)")
  let parentsArr = commit.getOrDefault("parents")
  if parentsArr.kind != JArray or parentsArr.len != 2:
    return err("resolveMergeShapeApi: L " & mergeSha & " is not a 2-parent merge commit (parents=" &
      $parentsArr.len & ") (fail-closed)")
  let parent1 = if parentsArr.len > 0: checkedStr(parentsArr[0], "sha") else: ""
  let parent2 = if parentsArr.len > 1: checkedStr(parentsArr[1], "sha") else: ""
  if parent1.len == 0 or parent2.len == 0:
    return err("resolveMergeShapeApi: L " & mergeSha & " parents unresolvable (fail-closed)")
  # headTreeOid = tree OID of the head-parent commit (parent2).
  let parent2Url = "https://api.github.com/repos/" & repo & "/commits/" & parent2
  let parent2Commit = ghGet(parent2Url, token)
  # REST /commits/{sha} nests the tree at commit.tree.sha — top-level .tree
  # is absent (live probe during Owner #11 landing: top-level null), so the
  # pre-fix path always failed fail-closed with "tree OID for parent2
  # unresolvable" AFTER a successful CAS landing (Pass 7, exit 1).
  let parent2Tree = checkedStr(parent2Commit, "commit", "tree", "sha")
  if parent2Tree.len == 0:
    return err("resolveMergeShapeApi: tree OID for parent2 " & parent2 & " unresolvable (fail-closed)")
  ok(MainShape(mainSha: mergeSha, parent1: parent1, parent2: parent2,
    headTreeOid: parent2Tree))

proc resolveMergeShapeLocal*(mergeSha: string): Result[MainShape, string] {.raises: [CatchableError, OSError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## LOCAL-MODE fallback ONLY — resolve the merge-commit shape via local git
  ## (MERGE_HEAD / ^1 / ^2 / ^{tree}). Used when the API transport is
  ## unavailable in local tests — never the primary path in CI. Fail-closed.
  let gitExe = findRealGit()
  let (p1Out, p1Code) = runGitEx(gitExe, "rev-parse " & mergeSha & "^1")
  let (p2Out, p2Code) = runGitEx(gitExe, "rev-parse " & mergeSha & "^2")
  if p1Code != 0 or p2Code != 0:
    return err("resolveMergeShapeLocal: cannot resolve parents of " & mergeSha & " (fail-closed)")
  let parent1 = p1Out.strip()
  let parent2 = p2Out.strip()
  let (treeOut, treeCode) = runGitEx(gitExe, "rev-parse " & parent2 & "^{tree}")
  if treeCode != 0:
    return err("resolveMergeShapeLocal: cannot resolve tree of parent2 " & parent2 & " (fail-closed)")
  ok(MainShape(mainSha: mergeSha, parent1: parent1, parent2: parent2,
    headTreeOid: treeOut.strip()))

# ---------------------------------------------------------------------------
# Load ledger cert for a (baseSha, headSha) pair — uses existing ledger machinery
# ---------------------------------------------------------------------------

func selectNewestCreatedAtCert*(newest: JsonNode; newestCreatedAt: string;
                                candidate: JsonNode; candidateCreatedAt: string): tuple[cert: JsonNode, createdAt: string] {.raises: [].} =
  ## Canonicality comparison between two ledger certificates of the SAME
  ## subject: the cert with the LATER createdAt wins. Two certs on the same
  ## subject are an INV-13 violation (a preserved historical duplicate); the
  ## newest mint is the canonical authority (INV-13 retroactive
  ## canonicalization). When exactly one of the two carries a createdAt, the
  ## timestamped cert wins (a missing mint time cannot preempt a known one).
  ## Tie or both-empty keeps the current winner for determinism.
  if newestCreatedAt.len == 0 and candidateCreatedAt.len > 0:
    result = (cert: candidate, createdAt: candidateCreatedAt)
  elif newestCreatedAt.len > 0 and candidateCreatedAt.len > 0 and
       candidateCreatedAt > newestCreatedAt:
    result = (cert: candidate, createdAt: candidateCreatedAt)
  else:
    result = (cert: newest, createdAt: newestCreatedAt)

proc loadLedgerCertFor*(baseSha, headSha: string; token: string; repo: string = DefaultRepo): Result[JsonNode, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Load the canonical subject-continuity certificate from the side-ref
  ## ledger whose baseSha and headSha match the given pair. When multiple
  ## ledger certs match the same subject (INV-13 violation — historical
  ## duplicates are preserved), the cert with the LATEST createdAt is adopted
  ## as canonical (INV-13 retroactive canonicalization). Uses the same 3+N
  ## scan the admission scan uses (openLedgerScanIndex index + one blob
  ## request per listed certificate).
  ## Returns the raw certificate JSON node, or an error.
  if token.len == 0:
    return err("loadLedgerCertFor: GITHUB_TOKEN not set (fail-closed)")
  let transport = liveLedgerTransport(token)
  # Open ONE scan index (tip + commit + recursive tree) and fetch each listed
  # certificate by its pinned blob sha — a single blob request per cert
  # (3+N); the append-only FF ledger never rewrites a listed entry, so the
  # pinned map is exact. Find the one matching (baseSha, headSha).
  let scanRes = openLedgerScanIndex(transport, repo)
  if scanRes.isErr:
    return err("loadLedgerCertFor: " & scanRes.error)
  var matchedCert: JsonNode
  var matchedCreatedAt = ""
  for entry in scanRes.get.entries:
    let download = downloadLedgerCertificateAtBlob(transport, repo, entry.certId, entry.blobSha)
    if download.isErr:
      continue
    let node = download.get
    if node.getOrDefault("kind").getStr("") != "subject-continuity":
      continue
    let bs = node{"baseSha"}.getStr("")
    let hs = node{"headSha"}.getStr("")
    if bs != baseSha or hs != headSha:
      continue
    if not verifyCertificateAttestation(node).isOk:
      return err("loadLedgerCertFor: certificate attestation signature invalid (fail-closed)")
    let createdAt = node{"createdAt"}.getStr("")
    if matchedCert.isNil:
      matchedCert = node
      matchedCreatedAt = createdAt
      continue
    let chosen = selectNewestCreatedAtCert(matchedCert, matchedCreatedAt, node, createdAt)
    if chosen.cert != matchedCert:
      logWarn("merge_cli", "loadLedgerCertFor: INV-13 violation — multiple ledger certs for subject (base " &
        baseSha & " head " & headSha & "); adopting canonical cert with latest createdAt " & chosen.createdAt &
        " (rejected: " & matchedCreatedAt & ")")
      matchedCert = chosen.cert
      matchedCreatedAt = chosen.createdAt
  if matchedCert.isNil:
    return err("loadLedgerCertFor: no matching certificate on ledger for baseSha " & baseSha & " headSha " & headSha)
  ok(matchedCert)

proc certificateFactFromNode(node: JsonNode): Result[CertificateContinuityFacts, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Build the certificate-continuity snapshot fact from a certificate JSON
  ## node whose Ed25519 attestation the CALLER already verified. The observed
  ## environment digests (sha256 of the CURRENT policy/scope state) are
  ## computed here — the pure predicate (Pass 2.96) enforces EXACT equality
  ## between the certified and the observed values (INV-3: OID/digest binding
  ## only, no tree re-derivation).
  let policyNow = fileSha256Hex("config/policy/merge_admission.json")
  let scopeNow = fileSha256Hex("data/verification_scope.lock")
  if policyNow.len == 0 or scopeNow.len == 0:
    return err("certificateFactFromNode: environment digest computation failed (fail-closed)")
  ok(CertificateContinuityFacts(
    subjectId: node{"subjectId"}.getStr(""),
    baseSha: node{"baseSha"}.getStr(""),
    headSha: node{"headSha"}.getStr(""),
    headTreeDigest: node{"headTreeDigest"}.getStr(""),
    policyDigest: node{"policyDigest"}.getStr(""),
    scopeDigest: node{"scopeDigest"}.getStr(""),
    evidenceDigest: node{"evidenceDigest"}.getStr(""),
    signatureOk: true,
    currentPolicyDigest: policyNow,
    currentScopeDigest: scopeNow))

proc verifiedCertificateArtifact(certPath, headSha: string): Result[JsonNode, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Parse and fail-closed-verify the ATTESTATION TIER's artifact certificate:
  ## subject-continuity kind, headSha binding to the evaluated head, Ed25519
  ## attestation. This is the exact verification chain of
  ## certificateFactFromPath (the artifact is an alternate transport of the
  ## same signed object the ledger publishes — ADR-0022 §4), exposed so a
  ## caller may consume the verified NODE (e.g. the actuator's post-merge
  ## continuity verdict) without re-scanning the ledger.
  if certPath.len == 0:
    return err("certificateFactFromPath: empty certificate artifact path (fail-closed)")
  if not fileExists(certPath):
    return err("certificateFactFromPath: certificate artifact not found: " & certPath & " (fail-closed)")
  var node: JsonNode
  try:
    node = parseJson(readFile(certPath))
  except CatchableError as e:
    return err("certificateFactFromPath: certificate artifact unreadable: " & e.msg)
  if node.getOrDefault("kind").getStr("") != "subject-continuity":
    return err("certificateFactFromPath: not a subject-continuity certificate (fail-closed)")
  let certHead = node{"headSha"}.getStr("")
  if certHead != headSha:
    return err("certificateFactFromPath: certificate headSha " & certHead &
      " != evaluated PR head " & headSha & " (fail-closed)")
  let att = verifyCertificateAttestation(node)
  if att.isErr:
    return err("certificateFactFromPath: certificate attestation signature invalid (fail-closed)")
  ok(node)

proc certificateFactFromPath(certPath, headSha: string): Result[CertificateContinuityFacts, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Build the certificate-continuity fact from the ATTESTATION TIER's
  ## artifact handoff — a local subject-continuity certificate file minted by
  ## the trusted attest tier and transported via the GitHub Actions artifact
  ## substrate (ADR-0022 §4: attest = mint/PREPARE authority with contents:
  ## read; the admission actuator = the single publication authority).
  ## Verification is IDENTICAL to the ledger path — verifyCertificateAttestation
  ## + headSha binding — the artifact is an alternate transport of the same
  ## signed object, not a weaker authority. Fail-closed on every mismatch.
  let nodeRes = verifiedCertificateArtifact(certPath, headSha)
  if nodeRes.isErr:
    return err(nodeRes.error)
  certificateFactFromNode(nodeRes.get)

proc bindCertificateSource(record: var VerificationRecord; certPath: string; prNumber: int): bool
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Bind the certificate SOURCE of one admission evaluation (fail-closed on
  ## every mismatch). With the attestation tier's artifact handoff (--cert),
  ## the artifact-sourced fact replaces the ledger-scan fact — identical
  ## boundary verification, alternate transport (ADR-0022 §4: publication is
  ## the admission actuator's post-verdict commit, so the verdict consumes the
  ## PRE-publication certificate). Without --cert the ledger scan stands
  ## (bootstrap/recovery path — D9 operator publication). Returns false on a
  ## missing head SHA or any artifact error — the caller denies.
  let headSha = record.headSha
  if headSha.len == 0:
    logInfo("merge_cli", "could not resolve head SHA for PR " & $prNumber)
    return false
  if certPath.len == 0:
    return true
  let artRes = certificateFactFromPath(certPath, headSha)
  if artRes.isErr:
    logInfo("merge_cli", artRes.error)
    return false
  if record.admission.isSome:
    var af = record.admission.get
    af.certificate = some(artRes.get)
    record.admission = some(af)
    true
  else:
    logInfo("merge_cli", "admission facts missing while binding artifact certificate (fail-closed)")
    false

proc scanLedgerContinuityCertNode*(transport: LedgerTransport; headSha: string; repo: string = DefaultRepo): Result[Option[JsonNode], string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Full-ledger scan core (transport-injectable for fixture tests): open ONE
  ## scan index (tip + commit + recursive tree = 3 requests) and fetch each
  ## listed certificate by its pinned blob sha (ONE request per cert — 3+N
  ## total; the ledger's append-only FF tip never rewrites a listed entry, so
  ## the pinned map is exact). Match = subject-continuity cert whose headSha
  ## == headSha; INV-13 duplicates adopt the LATEST createdAt (warn). A
  ## download failure skips that cert (historical continue semantics —
  ## absence stays a fact for the predicate); a present-but-tampered MATCHING
  ## cert is an immediate failure (fail-closed). Errors carry no prefix —
  ## the live wrapper adds the collectCertificateContinuityFacts identity.
  let scanT0 = epochTime()
  let scanRes = openLedgerScanIndex(transport, repo)
  if scanRes.isErr:
    return err(scanRes.error)
  let scanCerts = scanRes.get.entries.len
  logInfo("merge_cli", "phase=cert-ledger-scan certs=" & $scanCerts)
  var matchedCert: JsonNode
  var matchedCreatedAt = ""
  # Per-iteration attribution: each iteration's wall clock is logged when the
  # NEXT one starts (stderr only) — covers every continue/return path in the
  # body below without touching its control flow. Time values stay out of
  # all attested artifacts.
  var prevCertId = ""
  var prevIterT0 = epochTime()
  for entry in scanRes.get.entries:
    if prevCertId.len > 0:
      logInfo("merge_cli", "phase=cert-scan-iter certId=" & prevCertId &
        " elapsed_ms=" & $int((epochTime() - prevIterT0) * 1000.0))
    prevCertId = entry.certId
    prevIterT0 = epochTime()
    let download = downloadLedgerCertificateAtBlob(transport, repo, entry.certId, entry.blobSha)
    if download.isErr:
      continue
    let node = download.get
    if node.getOrDefault("kind").getStr("") != "subject-continuity":
      continue
    if node{"headSha"}.getStr("") != headSha:
      continue
    let att = verifyCertificateAttestation(node)
    if att.isErr:
      return err("certificate attestation signature invalid (fail-closed)")
    let createdAt = node{"createdAt"}.getStr("")
    if matchedCert.isNil:
      matchedCert = node
      matchedCreatedAt = createdAt
      continue
    let chosen = selectNewestCreatedAtCert(matchedCert, matchedCreatedAt, node, createdAt)
    if chosen.cert != matchedCert:
      logWarn("merge_cli", "collectCertificateContinuityFacts: INV-13 violation — multiple ledger certs for head " &
        headSha & "; adopting canonical cert with latest createdAt " & chosen.createdAt &
        " (rejected: " & matchedCreatedAt & ")")
      matchedCert = chosen.cert
      matchedCreatedAt = chosen.createdAt
  if prevCertId.len > 0:
    logInfo("merge_cli", "phase=cert-scan-iter certId=" & prevCertId &
      " elapsed_ms=" & $int((epochTime() - prevIterT0) * 1000.0))
  logInfo("merge_cli", "phase=cert-ledger-scan certs=" & $scanCerts &
    " elapsed_ms=" & $int((epochTime() - scanT0) * 1000.0))
  if matchedCert.isNil:
    return ok(none(JsonNode))
  ok(some(matchedCert))

proc collectCertificateContinuityFacts*(headSha: string; token: string; repo: string = DefaultRepo): Result[Option[CertificateContinuityFacts], string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Collect the certificate-continuity facts for head H at the I/O boundary:
  ## the canonical subject-continuity ledger certificate whose headSha == H,
  ## decoded into the snapshot fact type. When multiple ledger certs match
  ## head H (INV-13 violation — historical duplicates are preserved), the
  ## cert with the LATEST createdAt is adopted as canonical (INV-13
  ## retroactive canonicalization). Absence of a matching cert is a
  ## FACT (ok(none)) — the pure predicate decides NO_CERT from certRequired.
  ## A present-but-tampered cert is an immediate failure (fail-closed).
  if token.len == 0:
    return err("collectCertificateContinuityFacts: GITHUB_TOKEN not set (fail-closed)")
  let transport = liveLedgerTransport(token)
  let nodeRes = scanLedgerContinuityCertNode(transport, headSha, repo)
  if nodeRes.isErr:
    return err("collectCertificateContinuityFacts: " & nodeRes.error)
  if nodeRes.get.isNone:
    return ok(none(CertificateContinuityFacts))
  let factRes = certificateFactFromNode(nodeRes.get.get)
  if factRes.isErr:
    return err("collectCertificateContinuityFacts: " & factRes.error)
  ok(some(factRes.get))

# ---------------------------------------------------------------------------
# Vault-certificate facts (Pass 2.96b) — proof-required admission contract
# ---------------------------------------------------------------------------
# New I/O primitives (contract §2.1 implementation binding, items ②–③):
#   ① (modulePath, functionName) → vault cert lookup collector
#   ② policy-epoch equality — the certificateFactFromNode projection
#     (sha256 of the LOCAL policy/scope files NOW) duplicated into the vault
#     fact; the certificate side is the committed state at the event-frozen
#     base B (immutable tree objects), because vault certs carry no digests.
# Target set (contract §1): changed PR paths ∩ active kernel symbols
# (data/verification_scope.lock kernel_symbols − kernel_exempt_symbols,
# read from the admitted tree H) ∩ vault manifest entries (manifest @H).
# The manifest and cert files are read at H — the ADMITTED tree defines its
# own proof assets: a tree that removes a manifest entry (decertification
# alongside the source change) is silent, while a tree that keeps an entry
# must keep its certificate (missing → NO_CERT, corrupt → SUBJECT_MISMATCH).

type
  ## Vault contents fetcher — the collector's only source of remote tree
  ## bytes. `some` = the file body at (refSha, path); `none` = the file does
  ## not exist at that ref (a FACT, not an error); `err` = any other failure
  ## (run-level, fail-closed — never read as absence).
  VaultCertFetch* = proc(refSha: string; path: string): Result[Option[JsonNode], string]
    {.raises: [CatchableError, OSError, Exception].}

func parseActiveKernelSymbols*(scopeNode: JsonNode): Result[HashSet[string], string] {.raises: [].} =
  ## data/verification_scope.lock (schema_version 3) → the ACTIVE kernel
  ## symbol set: kernel_symbols − kernel_exempt_symbols, entries in the
  ## lock's "modulePath::functionName" form. The lock is the ONLY scope
  ## authority (contract §1); a missing list or a malformed entry fails
  ## closed.
  if scopeNode.isNil or scopeNode.kind != JObject:
    return err("verification_scope.lock is not a JSON object (fail-closed)")
  var active = initHashSet[string]()
  let kernel = scopeNode.getOrDefault("kernel_symbols")
  if kernel.isNil or kernel.kind != JArray:
    return err("verification_scope.lock has no 'kernel_symbols' array (fail-closed)")
  for entry in kernel.getElems():
    if entry.kind != JString or entry.getStr.len == 0:
      return err("verification_scope.lock 'kernel_symbols' entry malformed (fail-closed)")
    active.incl(entry.getStr())
  let exempt = scopeNode.getOrDefault("kernel_exempt_symbols")
  if exempt.isNil or exempt.kind != JArray:
    return err("verification_scope.lock has no 'kernel_exempt_symbols' array (fail-closed)")
  for entry in exempt.getElems():
    if entry.kind != JString or entry.getStr.len == 0:
      return err("verification_scope.lock 'kernel_exempt_symbols' entry malformed (fail-closed)")
    active.excl(entry.getStr())
  ok(active)

func vaultManifestIndex*(manifestNode: JsonNode): Result[
    seq[tuple[modulePath, functionName, irHash: string]], string] {.raises: [].} =
  ## vault manifest.json entries → the (modulePath, functionName) → irHash
  ## index in deterministic order (byte-sorted by modulePath, functionName).
  if manifestNode.isNil or manifestNode.kind != JObject:
    return err("vault manifest.json is not a JSON object (fail-closed)")
  let entries = manifestNode.getOrDefault("entries")
  if entries.isNil or entries.kind != JArray:
    return err("vault manifest.json has no 'entries' array (fail-closed)")
  var idx: seq[tuple[modulePath, functionName, irHash: string]] = @[]
  for e in entries.getElems():
    if e.kind != JObject:
      return err("vault manifest.json entry is not an object (fail-closed)")
    let mp = e.getOrDefault("modulePath")
    let fn = e.getOrDefault("functionName")
    let ir = e.getOrDefault("irHash")
    if mp.isNil or mp.kind != JString or mp.getStr.len == 0 or
       fn.isNil or fn.kind != JString or fn.getStr.len == 0 or
       ir.isNil or ir.kind != JString or ir.getStr.len == 0:
      return err("vault manifest.json entry missing modulePath/functionName/irHash (fail-closed)")
    idx.add((modulePath: mp.getStr, functionName: fn.getStr, irHash: ir.getStr))
  idx.sort(proc(a, b: tuple[modulePath, functionName, irHash: string]): int {.raises: [].} =
    let c = cmp(a.modulePath, b.modulePath)
    if c != 0: c else: cmp(a.functionName, b.functionName))
  ok(idx)

proc vaultPolicyEpochCurrentDigests(): Result[tuple[currentPolicy, currentScope: string], string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## NEW I/O primitive ② (contract §2.2): the certificateFactFromNode
  ## projection duplicated — sha256 of the LOCAL policy/scope files NOW, the
  ## current side of the Pass 2.96b epoch equality. Empty digest (unreadable
  ## file) = fail-closed, same semantics as certificateFactFromNode.
  let policyNow = fileSha256Hex("config/policy/merge_admission.json")
  let scopeNow = fileSha256Hex("data/verification_scope.lock")
  if policyNow.len == 0 or scopeNow.len == 0:
    return err("vaultPolicyEpochCurrentDigests: environment digest computation failed (fail-closed)")
  ok((currentPolicy: policyNow, currentScope: scopeNow))

func vaultFileBytes(node: JsonNode): Result[string, string] {.raises: [].} =
  ## GitHub contents API envelope → the decoded file bytes. A missing or
  ## non-base64 body is a contract violation — fail-closed.
  let contentB64 = node.getOrDefault("content")
  if contentB64.isNil or contentB64.kind != JString:
    return err("vault tree fetch: response has no base64 content (fail-closed)")
  ok(decodeBase64(contentB64.getStr.replace("\n", "")))

proc vaultFileJson(node: JsonNode): Result[JsonNode, string] {.raises: [].} =
  ## GitHub contents API envelope → the parsed file JSON (fail-closed on an
  ## unparsable body).
  let bytesRes = vaultFileBytes(node)
  if bytesRes.isErr:
    return err(bytesRes.error)
  try:
    ok(parseJson(bytesRes.get))
  except CatchableError as e:
    err("vault tree fetch: file body unparsable: " & e.msg & " (fail-closed)")

func vaultTreeSha256(node: JsonNode): Result[string, string] {.raises: [].} =
  ## GitHub contents API response → sha256 of the decoded file bytes (the
  ## tree-object digest side of the epoch equality). A non-base64 body is a
  ## contract violation — fail-closed.
  let bytesRes = vaultFileBytes(node)
  if bytesRes.isErr:
    return err(bytesRes.error)
  ok(sha256Hex(bytesRes.get))

proc collectVaultCertFactsCore*(baseSha, headSha: string; changedFiles: seq[string];
                                fetch: VaultCertFetch): Result[Option[VaultCertContinuityFacts], string]
    {.raises: [CatchableError, OSError, Exception].} =
  ## NEW I/O primitive ① — the (modulePath, functionName) → vault cert lookup
  ## collector core (transport-injectable for fixture tests; the live wrapper
  ## binds the GitHub contents API). Reads:
  ##   * data/verification_scope.lock @H — the active kernel symbol set
  ##   * src/verification/certificates/manifest.json @H — the target index
  ##   * src/verification/certificates/<irHash>.json @H — per-target cert
  ##     existence + content irHash identity (failure-fact: NO_CERT /
  ##     SUBJECT_MISMATCH inputs)
  ##   * config/policy/merge_admission.json + data/verification_scope.lock
  ##     @B — the certificate-side epoch digests (immutable tree objects)
  ##   * the LOCAL policy/scope files — the current-side digests (primitive ②)
  ## ok(none) = no in-scope manifest target → Pass 2.96b recorded skip.
  ## Every other unreadable input is a run-level error (fail-closed).
  if changedFiles.len == 0:
    return ok(none(VaultCertContinuityFacts))
  let scopeRes = fetch(headSha, "data/verification_scope.lock")
  if scopeRes.isErr:
    return err("vault collector: scope lock read failed (fail-closed): " & scopeRes.error)
  if scopeRes.get.isNone:
    return err("vault collector: data/verification_scope.lock absent at " & headSha & " (fail-closed)")
  let scopeJson = vaultFileJson(scopeRes.get.get)
  if scopeJson.isErr:
    return err("vault collector: " & scopeJson.error)
  let activeRes = parseActiveKernelSymbols(scopeJson.get)
  if activeRes.isErr:
    return err("vault collector: " & activeRes.error)
  let manifestRes = fetch(headSha, "src/verification/certificates/manifest.json")
  if manifestRes.isErr:
    return err("vault collector: manifest read failed (fail-closed): " & manifestRes.error)
  if manifestRes.get.isNone:
    return err("vault collector: src/verification/certificates/manifest.json absent at " & headSha & " (fail-closed)")
  let manifestJson = vaultFileJson(manifestRes.get.get)
  if manifestJson.isErr:
    return err("vault collector: " & manifestJson.error)
  let manifestIdx = vaultManifestIndex(manifestJson.get)
  if manifestIdx.isErr:
    return err("vault collector: " & manifestIdx.error)
  var targets: seq[VaultCertTarget] = @[]
  for entry in manifestIdx.get:
    let symbol = entry.modulePath & "::" & entry.functionName
    if symbol notin activeRes.get:
      continue
    if entry.modulePath notin changedFiles:
      continue
    targets.add(VaultCertTarget(
      modulePath: entry.modulePath, functionName: entry.functionName,
      irHash: entry.irHash, certPresent: false, irHashMatch: false))
  if targets.len == 0:
    return ok(none(VaultCertContinuityFacts))
  # Certificate-side epoch: the committed state at the event-frozen base B.
  let policyBRes = fetch(baseSha, "config/policy/merge_admission.json")
  if policyBRes.isErr:
    return err("vault collector: policy@B read failed (fail-closed): " & policyBRes.error)
  if policyBRes.get.isNone:
    return err("vault collector: config/policy/merge_admission.json absent at " & baseSha & " (fail-closed)")
  let policyB = vaultTreeSha256(policyBRes.get.get)
  if policyB.isErr:
    return err("vault collector: " & policyB.error)
  let scopeBRes = fetch(baseSha, "data/verification_scope.lock")
  if scopeBRes.isErr:
    return err("vault collector: scope lock@B read failed (fail-closed): " & scopeBRes.error)
  if scopeBRes.get.isNone:
    return err("vault collector: data/verification_scope.lock absent at " & baseSha & " (fail-closed)")
  let scopeB = vaultTreeSha256(scopeBRes.get.get)
  if scopeB.isErr:
    return err("vault collector: " & scopeB.error)
  # Per-target vault cert (admitted tree H): existence + content identity.
  for i in 0 ..< targets.len:
    let certPath = "src/verification/certificates/" & targets[i].irHash & ".json"
    let certRes = fetch(headSha, certPath)
    if certRes.isErr:
      return err("vault collector: vault cert read failed (fail-closed): " & certRes.error)
    if certRes.get.isNone:
      continue
    let certJson = vaultFileJson(certRes.get.get)
    if certJson.isErr:
      return err("vault collector: " & certJson.error)
    targets[i].certPresent = true
    let ir = certJson.get.getOrDefault("irHash")
    targets[i].irHashMatch = (not ir.isNil) and ir.kind == JString and
      ir.getStr == targets[i].irHash
  # Current-side epoch digests — the duplicated projection (primitive ②).
  let currentRes = vaultPolicyEpochCurrentDigests()
  if currentRes.isErr:
    return err("vault collector: " & currentRes.error)
  ok(some(VaultCertContinuityFacts(
    targets: targets,
    policyEpochDigest: policyB.get,
    scopeEpochDigest: scopeB.get,
    currentPolicyDigest: currentRes.get.currentPolicy,
    currentScopeDigest: currentRes.get.currentScope)))

proc collectVaultCertFacts*(baseSha, headSha: string; changedFiles: seq[string];
                            token: string; repo: string = DefaultRepo): Result[Option[VaultCertContinuityFacts], string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Live wrapper: bind the GitHub contents API as the vault fetch transport.
  ## 404 = `none` (a fact — the cert is absent at that ref); any other
  ## failure = `err` (run-level, fail-closed).
  if token.len == 0:
    return err("collectVaultCertFacts: GITHUB_TOKEN not set (fail-closed)")
  let fetch: VaultCertFetch = proc(refSha: string; path: string): Result[Option[JsonNode], string]
      {.raises: [CatchableError, OSError, Exception].} =
    let url = "https://api.github.com/repos/" & repo & "/contents/" & path & "?ref=" & refSha
    try:
      ok(some(ghGet(url, token)))
    except CatchableError as e:
      if e.msg.contains("HTTP 404"):
        ok(none(JsonNode))
      else:
        err($e.msg)
  collectVaultCertFactsCore(baseSha, headSha, changedFiles, fetch)

# ---------------------------------------------------------------------------
# I/O boundary — runMergeCli
# ---------------------------------------------------------------------------

## `runMergeCli` is the I/O boundary for `ax merge`.  It reads GITHUB_TOKEN
## from the process environment, injects the EVENT-FROZEN base anchor from
## AXIOM_MAIN_SHA (REQUIRED — fail-closed when unset), collects the
## AdmissionFacts snapshot bound to that anchor, evaluates the pure predicate,
## logs evidence, and optionally executes the server-side merge (pinned to the
## evaluated head SHA) when --apply is given.
proc runMergeCli*(args: seq[string]; dryRun: bool; certPath = ""; jsonOut = false; preflight = false): int {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  # Phase attribution — wall-clock totals emitted to stderr logs ONLY; never
  # enters the --json stdout line, the journal, or any certificate payload.
  let attributionT0 = epochTime()
  let token = getEnv("GITHUB_TOKEN")
  if token.len == 0:
    logInfo("merge_cli", "GITHUB_TOKEN not set — cannot query GitHub API")
    return 1

  # Parse PR number positional arg.
  var prNumber = 0
  for a in args:
    if a.len > 0 and a.allCharsInSet({'0'..'9'}):
      let parsed = safeParseInt(a)
      if parsed.isOk():
        prNumber = parsed.get()
      break
  if prNumber == 0:
    logInfo("merge_cli", "usage: ax merge <PR-number> [--dry-run | --apply]")
    return 1

  # mainSha: REQUIRED explicit input, read BEFORE collection because it is the
  # event-frozen base anchor the snapshot is bound to (and the value Pass 0
  # compares against). No fallback — an unset value denies (the old
  # testedBaseSha fallback made base freshness vacuously true).
  let mainSha = getEnv("AXIOM_MAIN_SHA")
  if mainSha.len == 0:
    logInfo("merge_cli", "AXIOM_MAIN_SHA not set — refusing to evaluate without explicit main SHA (fail-closed)")
    return 1

  # One evaluation = one snapshot: collect ALL facts bound to head H once,
  # against the event-frozen base B = mainSha. The --cert artifact handoff
  # replaces the ledger scan when it pre-binds (ADR-0022 §4 — identical
  # verification, alternate transport).
  let tCollect0 = epochTime()
  var (record, _) = collectAdmissionFacts(prNumber, token, mainSha, certPath = certPath, preflight = preflight)
  let attributionCollectMs = int((epochTime() - tCollect0) * 1000.0)
  logInfo("merge_cli", "phase=collect-facts elapsed_ms=" & $attributionCollectMs)
  let headSha = record.headSha
  # Certificate source binding: artifact handoff (--cert) or ledger scan,
  # fail-closed on a missing head SHA or artifact error.
  let tBind0 = epochTime()
  if not bindCertificateSource(record, certPath, prNumber):
    logInfo("merge_cli", "attribution: collect_ms=" & $attributionCollectMs &
      " bind_ms=" & $int((epochTime() - tBind0) * 1000.0) &
      " total_ms=" & $int((epochTime() - attributionT0) * 1000.0))
    return 1
  let attributionBindMs = int((epochTime() - tBind0) * 1000.0)
  logInfo("merge_cli", "phase=bind-cert elapsed_ms=" & $attributionBindMs)
  # The tested base IS the anchor — never a re-read of the live PR API, which
  # lags the queue and is what produced the STALE_BASE false denies. It also
  # keys the ledger certificate lookup, so journal, dry-run JSON and the
  # (base, head) actuator lookup all read one value.
  let testedBaseSha = record.baseSha

  # Head pinning: the merge PUT pins sha=H (head-moved → 405 from GitHub);
  # no local re-query re-derivation (M12 stale re-check removed — platform
  # guarantee).

  let tPredicate0 = epochTime()
  let outcome = MergeAdmissible(record, mainSha)
  let attributionPredicateMs = int((epochTime() - tPredicate0) * 1000.0)
  logInfo("merge_cli", "phase=predicate elapsed_ms=" & $attributionPredicateMs)
  logMergeAdmission(headSha, testedBaseSha, mainSha, outcome.result, outcome.reason, outcome.reasonCode, prNumber)
  # ADR-0032 (c),(f) — the preflight venue's verdict is a NON-CANONICAL
  # signal: certRequired was suppressed by the explicit --preflight opt-in
  # and the landing-eligibility judgment is exclusively the merge_group
  # verdict. Stated on every preflight evaluation, before any projection.
  if preflight:
    logInfo("merge_cli", "[preflight] venue=pull_request — certRequired suppressed by explicit --preflight opt-in; this verdict is NOT a landing-eligibility judgment (canonical verdict = merge_group, ADR-0032 (a),(f))")

  # --json machine line (stdout — one JSON object): the future gate's verdict
  # job parses `qualification` (NORMAL/ROTATION/NONE/UNSPECIFIED) from it.
  # Dry-run exit contract (dryRunExit — single source): exit 0 = admission GO,
  # or TRUST_SURFACE_MODIFIED (the policy routes trust-surface changes to the
  # architect manual-merge path — the check must not seal it); exit 1 = every
  # other NOT-ADMIT reasonCode or a run-level failure (e.g. rotation run-level
  # input errors raised above). The CI required check's conclusion IS this
  # exit — Axiom decides, GitHub enforces (a failing check blocks the merge).
  if jsonOut:
    var rotFact: Option[RotationAdjudication] = none(RotationAdjudication)
    var vaultRequired = false
    var vaultTargets = -1
    var layerFact: Option[LayerAdmissibilityFacts] = none(LayerAdmissibilityFacts)
    if record.admission.isSome:
      let af = record.admission.get
      rotFact = af.rotation
      vaultRequired = af.vaultCertRequired
      if af.vaultCert.isSome:
        vaultTargets = af.vaultCert.get.targets.len
      layerFact = af.layerAdmissibility
    stdout.writeLine($buildDryRunJson(prNumber, headSha, testedBaseSha, outcome,
      rotFact, layerFact, preflight = preflight,
      vaultCertRequired = vaultRequired, vaultCertTargets = vaultTargets))

  if dryRun:
    logInfo("merge_cli", "[dry-run] " & $outcome.result & " (" & outcome.reasonCode & "): " & outcome.reason)
    logInfo("merge_cli", "attribution: collect_ms=" & $attributionCollectMs &
      " bind_ms=" & $attributionBindMs & " predicate_ms=" & $attributionPredicateMs &
      " total_ms=" & $int((epochTime() - attributionT0) * 1000.0))
    return dryRunExit(outcome)

  if outcome.result != mergeGo:
    logInfo("merge_cli", "merge blocked (" & outcome.reasonCode & "): " & outcome.reason)
    logInfo("merge_cli", "attribution: collect_ms=" & $attributionCollectMs &
      " bind_ms=" & $attributionBindMs & " predicate_ms=" & $attributionPredicateMs &
      " total_ms=" & $int((epochTime() - attributionT0) * 1000.0))
    return 1

  # GitHub delegation (P12): required-check binding + strict freshness are
  # the platform ruleset's own configuration, enforced at merge evaluation —
  # no A2 ruleset re-derivation here.

  # The single actuation — native merge PUT (performMerge: merge_method=merge,
  # sha=headSha — head pin only; no ref mutation, no local merge-tree
  # construction, no self-CAS).
  let mergeRes = performMerge(prNumber, headSha, token)
  if mergeRes.isOk:
    logInfo("merge_cli", "merge of PR " & $prNumber & " initiated (merge, head pinned to " & headSha[0 ..< 9] & ")")
    return 0
  logInfo("merge_cli", "merge of PR " & $prNumber & " failed (HTTP " & $mergeRes.error.httpStatus &
    "): " & mergeRes.error.ghMessage)
  return 1

# ---------------------------------------------------------------------------
# Actuator — `ax merge` with full Model B sequence (certification-continuity Phase 5+)
# ---------------------------------------------------------------------------

## `runMergeActuatorCli` executes the full Model B actuator sequence:
## admission → load ledger cert → base/head freshness → policy/scope digest
## → A2 ruleset pre-flight → SINGLE native-merge PUT (performMerge,
## merge_method=merge, sha=headSha — head pin only) → verify merge-commit
## shape (Pass 7) → continuity verdict (Pass 8) → journal.
## Exit 0 ONLY when the full sequence passes (continuity ccPassed).
## Every failure is fail-visible with a precise reason code. The actuator
## performs NO ref mutation and no local merge-tree construction — GitHub
## native MERGE is the sole main mutation authority (ADR-0025 §1 M-B +
## Amendment A): self-owned merge authority = 0 (E1).

type MergeActuatorOutcome* = enum
  maAdmitted            ## admission passed, merge executed, continuity PASS
  maAdmitFailed         ## admission denied (reason in reason field)
  maNoCert              ## no ledger certificate for (baseSha, headSha)
  maCertInvalid         ## certificate signature or schema invalid
  maStaleBase           ## origin/main != cert.baseSha
  maStaleHead           ## PR head != cert.headSha
  maPolicyMismatch      ## current policy digest != cert.policyDigest
  maScopeMismatch       ## current scope digest != cert.scopeDigest
  maMergeFailed         ## native merge PUT failed — classification + journal record
  maContinuityMismatch  ## merge commit parents or continuity verdict failed
  maJournalError        ## journal write failed

proc runMergeActuatorCli*(args: seq[string]; dryRun: bool;
                          certPath = ""): int {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let token = getEnv("GITHUB_TOKEN")
  if token.len == 0:
    logInfo("merge_cli", "GITHUB_TOKEN not set — cannot query GitHub API")
    return 1

  # Parse PR number positional arg.
  var prNumber = 0
  for a in args:
    if a.len > 0 and a.allCharsInSet({'0'..'9'}):
      let parsed = safeParseInt(a)
      if parsed.isOk():
        prNumber = parsed.get()
      break
  if prNumber == 0:
    logInfo("merge_cli", "usage: ax merge <PR-number> [--dry-run | --apply]")
    return 1

  # mainSha: REQUIRED explicit input, read BEFORE collection because it is the
  # event-frozen base anchor the snapshot is bound to.
  let mainSha = getEnv("AXIOM_MAIN_SHA")
  if mainSha.len == 0:
    logInfo("merge_cli", "AXIOM_MAIN_SHA not set — refusing to evaluate without explicit main SHA (fail-closed)")
    return 1

  # One evaluation = one snapshot, against the event-frozen base B = mainSha.
  # The --cert artifact handoff replaces the ledger scan when it pre-binds
  # (ADR-0022 §4 — identical verification, alternate transport).
  var (record, _) = collectAdmissionFacts(prNumber, token, mainSha, certPath = certPath)
  let headSha = record.headSha
  # Certificate source binding: artifact handoff (--cert) or ledger scan,
  # fail-closed on a missing head SHA or artifact error.
  if not bindCertificateSource(record, certPath, prNumber):
    return 1
  # The tested base IS the anchor — one value feeds Pass 0, the journal, the
  # dry-run JSON, the (base, head) ledger lookup below and the post-merge
  # continuity check, so they can never disagree about which base was tested.
  let testedBaseSha = record.baseSha

  # Head pinning: the merge PUT pins sha=H (platform guarantee; M12 stale
  # re-check removed).

  # Pass 1 — admission. The snapshot binds the certificate-continuity facts
  # (Pass 2.96 inside the pure predicate — INV-1 consumption) and base
  # freshness (final pass). The former imperative Passes 2-5 are absorbed.
  let admitOutcome = MergeAdmissible(record, mainSha)
  logMergeAdmission(headSha, testedBaseSha, mainSha, admitOutcome.result, admitOutcome.reason, admitOutcome.reasonCode, prNumber)
  if admitOutcome.result != mergeGo:
    logInfo("merge_cli", "merge blocked (" & admitOutcome.reasonCode & "): " & admitOutcome.reason)
    return 1

  # Continuity object: the raw ledger cert node for the post-merge continuity
  # verdict (verifyContinuity consumes the cert JSON). The admission snapshot
  # already proved presence + signature + digest equality (Pass 2.96); this
  # load is observation-only, so a load failure surfaces at Pass 8 as CC_ERROR
  # (fail-closed after merge — the pre-merge gate has already denied in the
  # snapshot). With the --cert artifact handoff the SAME verified signed
  # object is consumed directly (verifiedCertificateArtifact — the exact
  # fail-closed chain bindCertificateSource approved) and the full-ledger
  # re-scan is skipped; a re-read failure falls back to the ledger load.
  var certNode: JsonNode
  if certPath.len > 0:
    let artNode = verifiedCertificateArtifact(certPath, headSha)
    if artNode.isOk:
      certNode = artNode.get
  if certNode.isNil:
    let certNodeRes = loadLedgerCertFor(testedBaseSha, headSha, token)
    certNode = if certNodeRes.isOk: certNodeRes.get else: %*{"kind": "subject-continuity", "baseSha": testedBaseSha, "headSha": headSha}
  let cert = certNode

  # Actuation (ADR-0025 Amendment A / plan Phase 0) — admission + certificate
  # passes have all cleared; the actuator performs the SINGLE native-merge PUT
  # (performMerge: merge_method=merge, sha=headSha — head pin only). No ref
  # mutation, no local merge-tree construction, no self-CAS: GitHub native
  # MERGE is the sole main mutation authority (self-owned merge authority =
  # 0, E1). Base binding = A1 actuator identity ∉ effective bypass actors +
  # ruleset strict enforcement at merge evaluation (A2/E3); A3 (baseSha ==
  # main tip) is the freshness assertion inside the predicate (Pass 0) and is
  # what the dry-run exit reports — same rule as runMergeCli.
  if dryRun:
    logInfo("merge_cli", "[dry-run] " & $admitOutcome.result & " (" & admitOutcome.reasonCode & "): would perform native merge (PUT /pulls/" & $prNumber & "/merge, sha=headSha) for PR " & $prNumber)
    return dryRunExit(admitOutcome)
  # GitHub delegation (P12): required-check binding + strict freshness are
  # the platform ruleset's configuration — no A2 re-derivation before PUT.
  let mergeRes = performMerge(prNumber, headSha, token)
  if mergeRes.isErr:
    let prStateObs = observePullState(prNumber, token)
    let denial = classifyMergeFailure(mergeRes.error, headSha,
      if prStateObs.isOk: prStateObs.get else: nil)
    logMergeAdmission(headSha, testedBaseSha, mainSha, mergeAborted, denial.reason,
      denial.reasonCode, prNumber)
    logInfo("merge_cli", "merge of PR " & $prNumber & " failed: " & denial.reason)
    return 1
  stdout.writeLine("MERGE_OK " & $ %*{"mergeSha": mergeRes.get.mergeSha})
  let mergeHeadSha = mergeRes.get.mergeSha

  # Pass 7 — observe the merge-commit shape from the server (L, parents,
  # parent2 tree) via the GitHub API — the primary path. The local git path
  # is a fallback ONLY for local/tests (AXIOM_MERGE_LOCAL_GIT_OBSERVATION=1);
  # in CI the runner checks out main without a fetch, so no MERGE_HEAD exists
  # after a server-side merge. Fail-closed on any mismatch or unresolvable L.
  let localShapeOnly = getEnv("AXIOM_MERGE_LOCAL_GIT_OBSERVATION").len > 0
  var shape: MainShape
  if localShapeOnly:
    let shapeRes = resolveMergeShapeLocal(mergeHeadSha)
    if shapeRes.isErr:
      logInfo("merge_cli", shapeRes.error & " — continuity check skipped")
      logMergePublish(prNumber, cert, testedBaseSha, headSha, mergeHeadSha, "CC_ERROR")
      return 1
    shape = shapeRes.get
  else:
    let shapeRes = resolveMergeShapeApi(mergeHeadSha, token)
    if shapeRes.isErr:
      logInfo("merge_cli", shapeRes.error & " — continuity check skipped")
      logMergePublish(prNumber, cert, testedBaseSha, headSha, mergeHeadSha, "CC_ERROR")
      return 1
    shape = shapeRes.get

  # Pass 8 — the Model B continuity predicate, evaluated EXACTLY once over the
  # observed Main shape and the already-loaded cert: merge-commit shape,
  # parent1 == cert.baseSha, parent2 == cert.headSha, sha256(parent2 tree) ==
  # cert.headTreeDigest. The per-check diagnostics below mirror the previous
  # manual parent/tree passes but NEVER feed the verdict (fail-closed).
  let observed = shape
  let continuityVerdict = verifyContinuity(observed, cert)
  if continuityVerdict != ccPassed:
    if observed.parent1 != testedBaseSha or observed.parent2 != headSha:
      logInfo("merge_cli", "continuity mismatch: merge parents (" & observed.parent1 & ", " &
        observed.parent2 & ") != (baseSha " & testedBaseSha & ", headSha " & headSha & ")")
    elif cert{"headTreeDigest"}.getStr("").len > 0 and
         sha256Hex(observed.headTreeOid) != cert{"headTreeDigest"}.getStr(""):
      logInfo("merge_cli", "headTreeDigest mismatch: " & sha256Hex(observed.headTreeOid) &
        " != " & cert{"headTreeDigest"}.getStr(""))
    else:
      logInfo("merge_cli", "continuity verdict: " & $continuityVerdict)
    logMergePublish(prNumber, cert, testedBaseSha, headSha, mergeHeadSha,
      continuityVerdictCode(continuityVerdict))
    return 1

  # Pass 10 — journal the merge result.
  try:
    let entry = %*{
      "stage": "merge-publish",
      "timestamp": getTimestamp(),
      "prNumber": prNumber,
      "certId": cert{"subjectId"}.getStr(""),
      "baseSha": testedBaseSha,
      "headSha": headSha,
      "mergeCommitSha": mergeHeadSha,
      "verdict": "CC_PASSED"
    }
    appendGateHistory($entry)
  except CatchableError:
    logInfo("merge_cli", "journal write failed (merge-publish)")
    return 1

  # Continuity invocation completes; the merge result is fully journaled.
  logInfo("merge_cli", "merge of PR " & $prNumber & " completed — continuity PASS (merge " & mergeHeadSha[0 ..< 9] & ")")
  return 0

# ---------------------------------------------------------------------------
# Dispatch entry — mergeCli
# ---------------------------------------------------------------------------
## `mergeCli` parses --dry-run / --apply / --json flags and dispatches
## to runMergeCli or runMergeActuatorCli. The Model B actuator is the
## primary path when --apply is given; the legacy runMergeCli stays
## available for dry-run admission-only evaluation.
proc mergeCli*(args: seq[string]): int {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var dryRun = false
  var applyFlag = false
  var certPath = ""
  var jsonFlag = false
  var preflightFlag = false
  var positional: seq[string] = @[]
  var i = 0
  while i < args.len:
    case args[i]
    of "--dry-run":
      dryRun = true; inc i
    of "--apply":
      applyFlag = true; inc i
    of "--json":
      jsonFlag = true; inc i
    of "--preflight":
      preflightFlag = true; inc i
    of "--cert":
      if i + 1 >= args.len:
        logInfo("merge_cli", "--cert requires a value (certificate artifact path)")
        return 1
      certPath = args[i + 1]; inc i; inc i
    else:
      positional.add(args[i]); inc i

  # ADR-0032 (c): preflight is a verdict-shape signal, never an actuation —
  # the landing/apply path ALWAYS demands the canonical certificate posture,
  # so the combination is rejected outright (fail-closed, not a silent
  # precedence).
  if preflightFlag and applyFlag:
    logInfo("merge_cli", "--preflight cannot be combined with --apply — preflight performs no merge actuation (ADR-0032 (c); the canonical actuator always demands a subject-continuity certificate)")
    return 1

  # Safe default: no --apply means dry-run (admission decision + evidence only).
  # A real server-side merge happens ONLY with an explicit --apply.
  if applyFlag and positional.len > 0 and positional[0].allCharsInSet({'0'..'9'}):
    return runMergeActuatorCli(positional, dryRun = dryRun, certPath = certPath)
  runMergeCli(positional, dryRun = not applyFlag, certPath = certPath, jsonOut = jsonFlag, preflight = preflightFlag)

when isMainModule:
  let args = commandLineParams()
  quit(mergeCli(args))
{.pop.}
## MUST-T2 acceptance fixture (2026-09-30): this touch makes the PR trust-surface — arm must refuse, manual merge only.
