## slice_catalog.nim — CI-quantization S-axis: single editing authority
##
## The SL-01..SL-17 CI slice catalog (id, name, engine mapping, verification
## steps, produces, required policies, input producers, promotion state) is
## defined HERE and only here. Consumers MUST source S-axis facts from this
## module — no hardcoded re-declaration elsewhere:
##   - tools/ci/epoch_transaction_gate.nim (imports SliceCatalog + the epoch
##     4-way binding target declarations below)
##   - config/policy/epoch_manifest.json is the EPOCH STATE record (which
##     slices are implemented in the current epoch) — it must equal this
##     catalog's implemented projection, enforced by the epoch gate.
##
## Epoch promotion transaction — 4-way atomic binding (approved plan S0):
##   epoch promotion transaction =
##       SliceCatalog (SSOT, this file)         src/gate/slice_catalog.nim
##     + Epoch Manifest                         config/policy/epoch_manifest.json
##     + SliceEngine mapping (callee 3종)       .github/workflows/{admission-check,
##                                              certificate-mint,
##                                              runner-pool-acceptance}.yml
##     + productionExecutionPin                 config/trusted_writer_set.json
##                                              (trustedAdmissionWorkflowSha —
##                                              repo-observable pin record;
##                                              org-ruleset pin itself is
##                                              outside the repo)
##   ← all four MUST be updated in the same commit (minimum: same PR); any
##     one updated alone = fail-closed (EPOCH_TRANSACTION_INCOMPLETE /
##     EPOCH_TRANSACTION_INCONSISTENT — see the gate tool).
##
## Slice definition rules (approved plan, verbatim semantics):
##   - SL-0713 = a SINGLE entry (SL-07 exactly-once + SL-13 [B2] are
##     inseparable: one-way B2→D6 ordering dependency + single certificate
##     ledger). Do NOT split.
##   - SL-05 and SL-14 are SEPARATE individual entries (merging requires
##     atomicity evidence — none exists yet; default = separate).
##   - SL-06 = required-policy SET slice (LG-001..014 are NOT individual
##     slices — only the set is).
##   - SL-08 = B/H binding (build_sha == B + per-file sha256).
##
## Per-slice fields left "미확정" (undetermined) are NOT invented here —
## they are filled by the slice's own promotion (승격) PR with evidence.
## Data provenance: every verification step cites the EXECUTED file:line
## (measured 2026-09-28 at commit d40eab21f; refreshed for origin/main
## 1441ff76f in the integration-review PR — SL-01/02/03/05/08/09/10/14).
## Engine job patterns name the workflow jobs that house each slice's steps.

import std/math

{.push raises: [].}

type
  SliceStep* = object
    stepNamePattern*: string  # substring matched against `- name:` lines of engine files
    evidence*: string         # measured file:line of the engine step

  EpochSlice* = object
    id*: string                      # "SL-01" .. "SL-17" (SL-0713 merged — see rules)
    name*: string                    # slice semantics (evidence-derived; "미확정" when not)
    engineFiles*: seq[string]        # callee workflow basenames where this slice fires
    verificationSteps*: seq[SliceStep]  # firing step evidence in the engine
    produces*: seq[string]           # artifacts/records this slice produces
    requiresPolicies*: seq[string]   # config/policy/* consumed by this slice
    inputProducers*: seq[string]     # upstream engine steps/jobs feeding this slice
    executorJobs*: seq[string]       # engine job patterns (검증자 job)
    implemented*: bool               # promotion state (epoch manifest equality SSOT)
    note*: string                    # binding rules / 미확정 markers / plan references

const
  SliceCatalog* = [
    # ── admission-check.yml callee chain (GATE A: B-pinned check producer) ──
    EpochSlice(id: "SL-01", name: "admission identity",
      engineFiles: @["admission-check.yml"],
      verificationSteps: @[
        SliceStep(stepNamePattern: "Re-derive admission identity",
                  evidence: ".github/workflows/admission-check.yml:449-500")],
      produces: @["B/H/HEAD_TREE_OID/MERGE_TREE_OID (run env facts)",
                  "mergeTreeDigest (identity chain anchor, ADR-0025 §11)"],
      requiresPolicies: @[],
      inputProducers: @["PR API pulls/{N} (trusted identity source)",
                        "_candidate checkout of H (data-only path)"],
      executorJobs: @["admission-check"],
      implemented: true,
      note: "B/H re-derivation + tree OIDs; base.ref == main fail-closed. Epoch N+2 승격 slice로 IMPLEMENTED 전환 (2026-09-28, epoch_transaction_gate layer-1 closure G1 — 카탈로그+매니페스트 원자 페어). Engine mapping 기존 실측 (엔진 파일 무변경): admission-check.yml:205 scope_sl01 derive + :455-456 '[check] Re-derive admission identity' scope 게이트."),
    EpochSlice(id: "SL-02", name: "derived-closure load (rotation closure sets)",
      engineFiles: @["admission-check.yml"],
      verificationSteps: @[
        SliceStep(stepNamePattern: "Load derived-closure sets",
                  evidence: ".github/workflows/admission-check.yml:1539"),
        SliceStep(stepNamePattern: "Admission predicate evaluation",
                  evidence: ".github/workflows/admission-check.yml:1613 (SL-02 consumer verification legs: all-or-none 4-file + L1 identity + L2 digest/membership inside the predicate step)")],
      produces: @["(consumes + verifies) derived-closure artifact sets (derived-H.txt, derived-B.txt, pin-H.json, identity.json — producer output, all-or-none)"],
      requiresPolicies: @[],
      inputProducers: @["org gate closure job (same-run derived-closure artifact, all-or-none)",
                        "in-place fallback derivation (event-frozen H/B, artifact absent — same ADR C2 authority)"],
      executorJobs: @["admission-check"],
      implemented: true,
      note: "feat/sl02-consumer-binding 승격 (ADR-0033): 소비자 계약 확장 — all-or-none 4파일(identity.json 신설) + L1 식별자 결속(candidateHeadSha/baseSha 이벤트 대조·40-hex·pinHeadBlobSha blob@H 대조·runAttempt — run-level err fail-closed) + L2 집합 완전성(B-고정 deriver --ref H/B 재실행 digest 등식 — proof_reconcile_gate oracle-digest 패턴의 verdict 연결 + git ls-tree(H) 멤버별 blob 대조). 과잉 멤버는 digest 등식만 탐지(구조 검사는 존재 라인 한정 — 계약 명시). in-place 폴백의 H 유도를 git rev-parse HEAD(==B, false NORMAL)에서 주체 head(SL02_PR_HEAD, merge_group은 event G의 parent2 — #667 회전 정합 병합)로 정정 + pin-H를 git show H:TWS(B 핀이 아닌 H 핀)로 + H 객체 bounded fetch(identity-step 선례). 부정 T1–T6 실측: tests/ci/test_sl02_consumer_binding.nim + tests/cli/test_merge_cli.nim 회귀."),
    EpochSlice(id: "SL-03", name: "evidence validity (D9 staging + subject + witness)",
      engineFiles: @["admission-check.yml"],
      verificationSteps: @[
        SliceStep(stepNamePattern: "Stage D9 evidence",
                  evidence: ".github/workflows/admission-check.yml:512-577"),
        SliceStep(stepNamePattern: "Register subject",
                  evidence: ".github/workflows/admission-check.yml:585-619"),
        SliceStep(stepNamePattern: "Attest witness-only",
                  evidence: ".github/workflows/admission-check.yml:627-650")],
      produces: @["data/trusted/evidence/draft-assembled.json (axiom.attestation.evidence.v1)",
                  "subjectId (64-hex) + data/trusted/evidence/<subjectId>.json (final record)",
                  "witness.json + witness.sha256"],
      requiresPolicies: @[],
      inputProducers: @["data/certification/evidence-draft.json (B-pinned draft)",
                        "_candidate tree funcSource byte-match (@H)",
                        "B-built bin/ax + ircheck (SL-08 artifact)"],
      executorJobs: @["admission-check"],
      implemented: true,
      note: "D9 staging (inline port of tools/ci/assemble_d9_evidence.sh, deleted CI=0 cutover) + subject-register + witness-only; B-built ax re-derives subjectId; no GITHUB_TOKEN (no network). Epoch N+3 승격 slice로 IMPLEMENTED 전환 (2026-09-28, epoch_transaction_gate layer-1 closure G1 — 카탈로그+매니페스트 원자 페어). Engine mapping 기존 실측 (엔진 파일 무변경): admission-check.yml:518-519 scope_sl03 단독 + :591-592/:633-634 sl08∧sl03."),
    EpochSlice(id: "SL-04", name: "certificate validity (mint [X] checks — P1/P2/P4)",
      engineFiles: @["certificate-mint.yml"],
      verificationSteps: @[
        SliceStep(stepNamePattern: "(P1) [X]1 artifact identity",
                  evidence: ".github/workflows/certificate-mint.yml:793"),
        SliceStep(stepNamePattern: "(P2) [X]2 file digest",
                  evidence: ".github/workflows/certificate-mint.yml:834"),
        SliceStep(stepNamePattern: "(P4) [X]3 field binding",
                  evidence: ".github/workflows/certificate-mint.yml:886")],
      produces: @["certificate.json validity verdict (artifact identity + file digest + field binding == 재유도값)"],
      requiresPolicies: @[],
      inputProducers: @["subject-certificate-<run_attempt> artifact (prepare, SL-12)",
                        "admission-check-<PR> witness artifact (SL-03)"],
      executorJobs: @["certificate-mint (publish stage)"],
      implemented: true,
      note: "SL-04 = certificate VALIDITY (mint 소속 [X] 체인) — witness-only는 SL-03 (매핑 정정). SL-0713은 D6 발행 의례 + [B2], 별도 엔트리. admission-check.yml에는 sl04 scope 플래그 없음 (mint 소속 — callee 범위 밖). Epoch N+5 승격 slice로 IMPLEMENTED 전환 (2026-09-29, epoch_transaction_gate layer-1 closure G1+G2b — 카탈로그+매니페스트 원자 페어 + 비핀 엔진 변경 승격 동반). Engine mapping 신설 실측: certificate-mint.yml publish에 '[slice-engine] Load epoch manifest implementedSlices (contents API @B — scope authority)' 신설 — scope_sl04 게이트로 (P1) [X]1 artifact identity(:793) · (P2) [X]2 file digest(:834) · (P4) [X]3 field binding(:886) 발화 제한; (P0)/(P5)/(P6)/(P7)은 scope_sl0713 게이트로 NO-FIRE (SL-0713 미정착 — D6/[B2]는 별도 승격 slice 대기). 카탈로그 증거 라인은 N+4 slice-engine 삽입(+54) 드리프트를 현행 라인으로 정정. C5/C1 계약 개정 동반: prepare 자체빌드(계약 예외 C1) 제거 → admission lane build-base-artifacts(B-결속 바이트, build_sha==B + per-file sha256) 소비 — publish [X]1~5 결속 검증 경로 불변 (소비 source만 변경; ADR-0026 C1 개정문 2026-09-29)."),
    EpochSlice(id: "SL-05", name: "admission predicate evaluation",
      engineFiles: @["admission-check.yml"],
      verificationSteps: @[
        SliceStep(stepNamePattern: "Admission predicate evaluation",
                  evidence: ".github/workflows/admission-check.yml:855-943")],
      produces: @["admission-verdict.log",
                  ".axiom/gate_history.jsonl (canonical merge-admission journal)"],
      requiresPolicies: @["config/policy/merge_admission.json (consumed via ax merge --dry-run)"],
      inputProducers: @["witness (SL-03)",
                        "derived-closure sets (SL-02 load, org gate, pre-gate optional, all-or-none)"],
      executorJobs: @["admission-check"],
      implemented: true,
      note: "MergeAdmissible verdict IS the required check conclusion — `ax merge N --dry-run` exits 0 on GO, non-zero on NOT-ADMIT/run-level failure, and the step's exit projects onto the check. Fires on BOTH pull_request and merge_group (merge_group re-anchored by run head parent2 → PR resolution via the GitHub API; head_ref string parsing forbidden — ADR-0027 P1). Predicate inputs: admission facts snapshot + base freshness (V.baseSha == AXIOM_MAIN_SHA; BASE_UNRECORDED/STALE_BASE deny). Axiom decides, GitHub enforces at merge time (strict / queue invalidation — ADR-0027 P3/R2). SL-14 is a SEPARATE slice."),
    EpochSlice(id: "SL-06", name: "required policy set (LG-001..014)",
      engineFiles: @["admission-check.yml"],
      verificationSteps: @[],
      produces: @[],  # 미확정 — policy set consumption outcome
      requiresPolicies: @["config/policy/landing_required_gateway_tests.json (LG-001..014 — the SET is one slice; ids are NOT individual slices)"],
      inputProducers: @[],  # 미확정
      executorJobs: @["admission-check"],
      implemented: false,
      note: "Evidence: docs/adr/0025-gateway-landing-authority.md:269. Policy set consumed via evaluation gates — no dedicated engine step yet (미확정)."),
    # ── certificate-mint.yml chain (D6 exactly-once publish authority) ──
    EpochSlice(id: "SL-0713", name: "certificate continuity publish (D6 exactly-once + [B2])",
      engineFiles: @["certificate-mint.yml"],
      verificationSteps: @[
        SliceStep(stepNamePattern: "(P0) Publish activation guard",
                  evidence: ".github/workflows/certificate-mint.yml:1014"),
        SliceStep(stepNamePattern: "(P5) [B2] (b) canonical tree identity",
                  evidence: ".github/workflows/certificate-mint.yml:1284"),
        SliceStep(stepNamePattern: "(P6) [B2] (c) gateway lane conclusion",
                  evidence: ".github/workflows/certificate-mint.yml:1337"),
        SliceStep(stepNamePattern: "(P7) D6 + FF-CAS 3분기 reconciliation",
                  evidence: ".github/workflows/certificate-mint.yml:1387")],
      produces: @["certificate.json (published, signed)",
                  "axiom/certificates side-ref ledger append (FF-CAS, exactly-once)"],
      requiresPolicies: @[],
      inputProducers: @["subject-certificate-<run_attempt> artifact (prepare, SL-12)",
                        "tested-tree-digest artifact (gateway lane, SL-10)",
                        "admission-check-<PR> artifact (SL-03 witness)"],
      executorJobs: @["certificate-mint (publish stage)"],
      implemented: true,
      note: "SL-07 + SL-13 merged as ONE entry (exactly-once + [B2] inseparable: one-way B2→D6 ordering + single certificate ledger). SINGLE ledger를 깨는 분리 시도 = fail. Epoch N+7 승격 slice로 IMPLEMENTED 전환 (2026-10-01, epoch_transaction_gate layer-1 closure G1 — 카탈로그+매니페스트 원자 페어; certificate-mint.yml 무변경 → G2b 비발동, productionExecutionPin 무변경). 귀속 재정정: (P1)/(P2)/(P4)는 SL-04 소속 (scope_sl04 게이트 — 실측 :1079/:1122/:1181) → 본 엔트리에서 중복 제거. 엔진 게이트 실측: scope_sl0713 4곳 — (P0) :1014 · (P5) :1284 · (P6) :1337 · (P7) :1387 (N+6 이후 C5/C1 개정 보완·merge_group 바인딩·toolchain scope 후속 커밋 드리프트를 현행 라인으로 정정). (P7) = ax cert ledger-append: D6 멱등(재실행 0) + FF-CAS 3분기 reconciliation + exactly-once(first=1/rerun=0) — refs/heads/axiom/certificates side-ref append-only. 선행 확정: ADR-0025 Amendment C §C.5 (mode=none/derivedEmpty candidate [B2](c) 재조정 메모) + docs/evidence/sl0713_promotion_binding_2026-10-01.md (D6/[B2] 준비성 판정 + 영구 append 폭발반경 결정 바인딩) 동봉."),
    EpochSlice(id: "SL-12", name: "certificate mint prepare (B-built sign ceremony)",
      engineFiles: @["certificate-mint.yml"],
      verificationSteps: @[
        SliceStep(stepNamePattern: "(4) Verify + normalize witness",
                  evidence: ".github/workflows/certificate-mint.yml:591"),
        SliceStep(stepNamePattern: "(5) Cert artifact digest + manifest + upload",
                  evidence: ".github/workflows/certificate-mint.yml:639")],
      produces: @["certificate.json + cert-manifest.txt + B-built bin/ax (subject-certificate-<run_attempt> artifact)"],
      requiresPolicies: @["config/trusted_writer_set.json (TrustedWriterSet@B, step 2a)"],
      inputProducers: @["admission-check-<PR> artifact (witness, run-scoped)",
                        "PR API B/H (pre-landing mint — no M)"],
      executorJobs: @["certificate-mint (prepare stage)"],
      implemented: true,
      note: "Authority 정규성 [B1]: the SINGLE build site = admission lane build-base-artifacts (B-built only; C5/C1 계약 개정 2026-09-29 — prepare 자체빌드 소비 전환, 이하 SL-04 note). Epoch N+4 승격 slice로 IMPLEMENTED 전환 (2026-09-29, epoch_transaction_gate layer-1 closure G1+G2b — 카탈로그+매니페스트 원자 페어 + 비핀 엔진 변경은 승격 동반 요구, 게이트 G2a/G2b split PR #326 기반). Engine mapping G-신설 실측: certificate-mint.yml prepare에 '[slice-engine] Load epoch manifest implementedSlices (B tree — scope authority)' 신설 — scope_sl12 게이트로 (4) Verify + normalize witness(:591) · (5) Cert artifact digest + manifest + upload(:639) · (5b) Upload subject-certificate artifact (trusted-name) 동일 게이트 ((5b)는 if-no-files-found: error — (5) 미발화 시 함께 꺼야 NO-FIRE 의미 보존). TWS/pin 값 무변경 (admission blob 불변 — G2b 경로)."),
    EpochSlice(id: "SL-08", name: "B/H binding (build_sha == B + per-file sha256)",
      engineFiles: @["admission-check.yml", "certificate-mint.yml", "runner-pool-acceptance.yml"],
      verificationSteps: @[
        SliceStep(stepNamePattern: "Verify artifact manifest",
                  evidence: ".github/workflows/admission-check.yml:409-433"),
        SliceStep(stepNamePattern: "(P2) [X]2 file digest",
                  evidence: ".github/workflows/certificate-mint.yml:780-799 (cert_sha256 + build_sha == B)"),
        SliceStep(stepNamePattern: "Verify candidate consumption",
                  evidence: ".github/workflows/runner-pool-acceptance.yml:550 (gateway-shard manifest digest binding)")],
      produces: @["manifest.txt (build_sha + per-file sha256 bindings)"],
      requiresPolicies: @[],
      inputProducers: @["build-base-artifacts (B-built bin/ax + ircheck + manifest)"],
      executorJobs: @["build-base-artifacts", "admission-check", "certificate-mint (publish)", "gateway-shard"],
      implemented: true,
      note: "첫 active epoch N+1의 승격 slice로 IMPLEMENTED 전환 (2026-09-28, epoch_transaction_gate layer-1 closure G1 — 카탈로그+매니페스트 원자 페어). Engine mapping 확정(3엔진 실측): admission-check ':415 [check] Verify artifact manifest' + certificate-mint ':780 (P2) [X]2 file digest' + runner-pool-acceptance ':550 Verify candidate consumption'. Canonical verifier = tools/ci/verify_b_artifact.sh (tracked, testable implementation of the '[check] Verify artifact manifest' predicate); inline step은 동일 계약 구현."),
    # ── runner-pool-acceptance.yml lane (gateway 8-way + A3) ──
    EpochSlice(id: "SL-09", name: "gateway shard partition (8-way K=8)",
      engineFiles: @["runner-pool-acceptance.yml"],
      verificationSteps: @[
        SliceStep(stepNamePattern: "Run gateway shard",
                  evidence: ".github/workflows/runner-pool-acceptance.yml:571 (gateway-shard job)"),
        SliceStep(stepNamePattern: "Verify identity set",
                  evidence: ".github/workflows/runner-pool-acceptance.yml:655 (gateway-identity-gate job)"),
        SliceStep(stepNamePattern: "Run reconcile gate",
                  evidence: ".github/workflows/runner-pool-acceptance.yml:712 (proof-reconcile job)")],
      produces: @["executed-shard-<n>.json (axiom/ci-executed/v1)",
                  "gateway-junit-shard-<n> (build/gateway-junit.xml)",
                  "identity-set verdict (union == landing policy set + pairwise disjoint — junit 소비 판정, EXPECTED_GATEWAY_TESTS ALL|EMPTY)"],
      requiresPolicies: @[],
      inputProducers: @["candidate-arm64 artifact (candidate-build-arm — compile=0)", 
                        "decision record (select — SL-10)"],
      executorJobs: @["gateway-shard (matrix shard 0..7)", "gateway-identity-gate", "proof-reconcile"],
      implemented: false,
      note: "K=8 fixed partition (ADR-0023 A1.8 — POLICY 다이얼 금지); A3 executed records bind to decisionHash. epoch N+6 (SL-10 승격 PR) 귀속 재정정: 'Verify identity set'(:655) + 'Run reconcile gate'(:712)는 SL-09 산출(junit/executed — gateway-junit-shard-*/executed-shard-*)을 소비하는 사후 검증 — SL-09 귀속 (실측: gateway-identity-gate needs [gateway-shard], proof-reconcile needs [gateway-shard]; SL-10 = select 단독 자기완결). 승격 PR에서 이 재정정과 함께 scope_sl09 게이트 신설 예정 (SL-09 implemented 전환 시)."),
    EpochSlice(id: "SL-10", name: "gateway decision identity (A3 decision envelope)",
      engineFiles: @["runner-pool-acceptance.yml"],
      verificationSteps: @[
        SliceStep(stepNamePattern: "Run selector",
                  evidence: ".github/workflows/runner-pool-acceptance.yml:212 (select job steps)")],
      produces: @["decision.json + decisionHash (axiom/ci-select-decision/v1)",
                  "tested-tree-digest artifact (landing candidate tree)"],
      requiresPolicies: @[],
      inputProducers: @[],  # 자기완결 — 타 job 산출물 소비 0 (checkout + 이벤트 컨텍스트만; B/H는 PR/push 이벤트 필드)
      executorJobs: @["select"],
      implemented: true,
      note: "epoch N+6 승격 (첫 runner-pool 게이트 증분). 귀속 재정정: select만 SL-10 — 실측 근거 runner-pool-acceptance.yml DAG: select job은 다른 job 산출물 0 소비 (decision/blob base/head = checkout+이벤트), 하류(ci-bootstrap/candidate-build-arm/gateway-shard/identity-gate/proof-reconcile)가 select 산출을 소비하는 단방향. 'Verify identity set'(:655)/'Run reconcile gate'(:712)는 SL-09 산출(junit/executed) 소비 → SL-09 재정정. proof_reconcile_gate (tools/ci) = A3 executor (decision ↔ executed exact-set) — SL-09 귀속. identity-set verdict (구 'union == 86')는 SL-09 produces로 이동 — 실제 판정 = union == landing policy set (config/policy/landing_required_gateway_tests.json, Phase-3 re-tiering)."),
    # ── verdict observation surface (separate from SL-05 — no atomicity evidence) ──
    EpochSlice(id: "SL-14", name: "verdict observation surface (records upload + landing trigger)",
      engineFiles: @["admission-check.yml"],
      verificationSteps: @[],
      produces: @["admission-check-<PR> artifact (witness + verdict log + gate history)",
                  "landing-trigger Check Run (external_id = admission-check-<PR>, Landing App trigger evidence)",
                  "(provisioning) Upload admission records — `if: always()` step, non-verification",
                  "(provisioning) Post landing-trigger Check Run — `if: always()` step, non-verification"],
      requiresPolicies: @[],
      inputProducers: @["admission-verdict.log + witness (SL-05/SL-03)"],
      executorJobs: @["admission-check"],
      implemented: false,
      note: "SL-05/SL-14 분리 기본값 (묶기 위한 원자성 증거 없음 — 계획 규칙). Upload/Check-Run 스텝은 provisioning/observation (if: always()) — 검증 스텝이 아니므로 verificationSteps에서 제외 (I-3: always() 스텝은 slice 검증으로 등재 금지)."),
    # ── planned slices without measured engine mapping (registered ahead) ──
    EpochSlice(id: "SL-11", name: "미확정 (plan-defined; engine mapping pending promotion)",
      engineFiles: @[],
      verificationSteps: @[],
      produces: @[],
      requiresPolicies: @[],
      inputProducers: @[],
      executorJobs: @[],
      implemented: false,
      note: "SL-11 속성 미확정 — 승격 PR에서 실측 증거와 함께 확정 (지어내지 않음)."),
    EpochSlice(id: "SL-15", name: "admission evidence identity reuse (Evidence CAS HIT/MISS)",
      engineFiles: @["admission-check.yml", "certificate-mint.yml"],
      verificationSteps: @[
        SliceStep(stepNamePattern: "[check] Attest witness-only (B-built ax kernel, H-derived data)",
                  evidence: ".github/workflows/admission-check.yml:917-993 (SL-15 CAS env arming + evidence-record fail-closed assert; the attest chain stages a-f themselves are SL-03's verification)"),
        SliceStep(stepNamePattern: "(P7b) [SL-15] evidence record → evidence CAS ledger append (exactly-once)",
                  evidence: ".github/workflows/certificate-mint.yml:1518-1605 (exactly-one + expired=false artifact lookups; evidenceKey/sha256(payload)/bundle-wire==witness semantic.evidenceDigest binding; idempotent ledger append)")],
      produces: @["evidence-record-<candidate head>-<run_attempt> artifact",
                  "refs/heads/axiom/evidence-cas record (durable evidence side-ref)"],
      requiresPolicies: @[],
      inputProducers: @["witness (SL-03)", "admission B-built ax (SL-08)"],
      executorJobs: @["admission-check", "certificate-mint (publish stage)"],
      implemented: true,
      note: "feat/admission-identity-reuse 승격: attestation_orchestrator의 planEvidenceCas/attestWitnessChainCas (HIT = §15.3 sanctioned skip of stages b+c after full re-verification; MISS = fresh production + record emission)를 admission-check attest와 certificate-mint publish가 소비. Key-soundness: EvidenceKey는 검증기 artifact digest를 정체성에서 배제한다 — tools/hermetic_build.nim이 BuildEnvGitHash/BuildDate를 바이너리에 각인하므로 같은 트리 재빌드도 바이트가 달라져 해싱하면 매 CI run마다 false MISS가 된다; artifact digest는 record-level integrity metadata로만 저장된다 (evidence_cas.nim 문서 참조)."),
    EpochSlice(id: "SL-16", name: "미확정 (plan-defined; engine mapping pending promotion)",
      engineFiles: @[],
      verificationSteps: @[],
      produces: @[],
      requiresPolicies: @[],
      inputProducers: @[],
      executorJobs: @[],
      implemented: false,
      note: "SL-16 속성 미확정 — 승격 PR에서 실측 증거와 함께 확정 (지어내지 않음)."),
    EpochSlice(id: "SL-17", name: "미확정 (plan-defined; engine mapping pending promotion)",
      engineFiles: @[],
      verificationSteps: @[],
      produces: @[],
      requiresPolicies: @[],
      inputProducers: @[],
      executorJobs: @[],
      implemented: false,
      note: "SL-17 속성 미확정 — 승격 PR에서 실측 증거와 함께 확정 (지어내지 않음)."),
    EpochSlice(id: "SL-18", name: "test-judgment CAS (s1a judgment reuse — §15.3-class REUSED basis)",
      engineFiles: @["admission-check.yml", "certificate-mint.yml"],
      verificationSteps: @[
        SliceStep(stepNamePattern: "[check] Judgment CAS plan (s1a judgment reuse, SL-15 scope)",
                  evidence: ".github/workflows/admission-check.yml:735-767 (read-only ledger consult through the B-built ax; REUSED decision file → the GO-critical loop's sanctioned skip; EXECUTED → the evidence file is required at the armed attest)"),
        SliceStep(stepNamePattern: "(P7c) [SL-15] judgment record → judgment CAS ledger append (exactly-once)",
                  evidence: ".github/workflows/certificate-mint.yml:1695-1781 (exactly-one + expired=false artifact lookups; record identity + §5-(d) witness byte binding; idempotent ledger append with MINT_JUDGAPPEND_COUNT)")],
      produces: @["judgment-record-<candidate head>-<run_attempt> artifact",
                  "judgment record on refs/heads/axiom/evidence-cas (durable judgment side-ref)"],
      requiresPolicies: @[],
      inputProducers: @["s1a golden test judgment flush (GO-critical loop)",
                        "witness .semantic.judgment binding (SL-03 attest)",
                        "admission B-built ax (SL-08)"],
      executorJobs: @["admission-check", "certificate-mint (publish stage)"],
      implemented: true,
      note: "feat/judgment-cas-s1a 승격: verification/judgment_cas.nim의 9성분 클로저 identity (계약 docs/spec/test_judgment_cas_contract.md §4) + §5 5조건 재검증 + fail-closed EXECUTED 회귀 (§6)를 admission-check plan 스텝과 certificate-mint P7c exactly-once append가 소비. scope는 SL-15 (s1a 골든 블록) 게이트를 재사용 — SL-18은 test-judgment 재사용 기제 자체 (판정의 재분류, fresh-execution 증거 아님 — 계약 §2). 비핀 엔진(certificate-mint.yml) 변경은 본 슬라이스 승격으로 청구 (G2b path 1); 핀 엔진(admission-check.yml)은 TWS 레코드 + manifest pin과 동일 트랜잭션 (G2a — ba827508f3ff7df4048703c54665532fa02e7394)."),
    EpochSlice(id: "SL-19", name: "third-party action generation cutover (node24 pin rotation)",
      engineFiles: @["admission-check.yml", "certificate-mint.yml", "runner-pool-acceptance.yml"],
      verificationSteps: @[
        SliceStep(stepNamePattern: "[build] Checkout B only (base.sha",
                  evidence: ".github/workflows/admission-check.yml:251 (build-base-artifacts — the step whose uses: carries the rotated checkout pin)"),
        SliceStep(stepNamePattern: "Checkout B only (trusted config/tree",
                  evidence: ".github/workflows/certificate-mint.yml:1288 (publish — rotated checkout pin carrier)"),
        SliceStep(stepNamePattern: "Upload tested-tree-digest",
                  evidence: ".github/workflows/runner-pool-acceptance.yml:347 (select — rotated upload-artifact pin carrier)")],
      produces: @["node24-generation action pin surface (checkout v7.0.1 @3d3c42e5 · upload-artifact v7.0.2 @cf430e03 · download-artifact v8.0.2 @9000827c · cache save/restore v6.1.0 @55cc8345 — 40-hex SHA + version 주석)"],
      requiresPolicies: @[],
      inputProducers: @["actions/* latest release tag → tag-object dereference (커밋 SHA 실측 — 2026-11-02 회전 시점 측정)"],
      executorJobs: @["build-base-artifacts", "certificate-mint (publish)", "select"],
      implemented: true,
      note: "AGENTS.md §2.5 일관된 세대 전환 (coherent generation — CI Epoch Cutover protocol): 외부 액션 핀을 node20 세대(checkout v4.4.0 · upload/download-artifact v4 · cache v4)에서 node24 세대로 회전. 실측 인벤토리(2026-11-02, `rg -n 'uses:' .github/` 전수): checkout ×39 (@11d5960a v4.4.0 ×37 + @11bd7190 v4.2.2 observation.yml 이형 핀 ×2 → v7.0.1 @3d3c42e5 통일), upload-artifact ×29 (v4 @ea165f8d → v7.0.2 @cf430e03), download-artifact ×24 (v4 @d3f86a10 → v8.0.2 @9000827c), cache save/restore ×7 (v4 @0057852b → v6.1.0 @55cc8345 — save 3 + restore 4); node24 기핀 create-github-app-token @64ab729a ×6 · dependabot/fetch-metadata ×1 무접촉. 보류 ×6 — gateway-jobs-measure.yml (checkout ×2·upload ×1·cache save ×1) · hardware-falsification-smoke.yml (checkout ×2)는 base 정책 v91에서 CONTROLLED 등록 소실(v12 보유 — FROZEN `.github/**` glob 흡수, v52 결정 #18의 6경로 재등록 미포함)으로 SURFACE_FORBIDDEN → 재등록 정책 PR(Owner 권한 — 2단계 정책 PR 선례) 후속 회전 대기 (본 PR은 게이트 green 유지 위해 해당 5핀 구 세대 보존). 4-way binding: admission-check.yml blob f0bb8fb5 = TWS trustedAdmissionWorkflowSha = manifest productionExecutionPin 동일 diff (G2a) + 본 엔트리 G1 (engineFiles 3종으로 certificate-mint/runner-pool 회전을 본 승격이 청구 — G2b). 파라미터 호환 실측: artifact-ids:·archive:·digest-mismatch: 사용 0건 — download v5 path fix(by-ID 전용)·upload v7 direct upload(opt-in)·v8 digest 기본값이 소비 표면에 접촉 없음; checkout allow-unsafe-pr-checkout 가드는 v4.4.0부터 활성 — v7 회전은 동작 중립 (fork-PR checkout 의존 0건 실측). download v8 digest-mismatch 기본 error(구 warn): continue-on-error 소프트 다운로드 5곳(ci-cache-publisher nimcache 캐리어·lane fold ×3, runner-pool derived-closure soft ×1, closure-watcher drift findings ×1)은 스텝 실패가 continue-on-error로 흡수되고 하류가 존재 판정(in-place 폴백·본문 결손 명기) → J3 fail-open 유지 (조정 불필요); 경판정 다운로드는 fail-closed 계약(lane judgment fail-closed on landing · SL-02 all-or-none digest 등식)과 정합.")
  ]

# ═══════════════════════════════════════════════════════════════════════════
# Epoch 4-way binding targets — declared HERE (single editing authority).
# The org-ruleset productionExecutionPin itself lives outside the repo; its
# repo-observable record is config/trusted_writer_set.json field
# trustedAdmissionWorkflowSha (content-addressed git blob sha of
# admission-check.yml, ADR-0022 §5 — updated atomically with the workflow).
# ═══════════════════════════════════════════════════════════════════════════

const
  EpochSliceCatalogPath* = "src/gate/slice_catalog.nim"
  EpochManifestPath* = "config/policy/epoch_manifest.json"
  EngineMappingDir* = ".github/workflows"
  EngineMappingFiles* = [
    "admission-check.yml",
    "certificate-mint.yml",
    "runner-pool-acceptance.yml"
  ]
  ProductionPinRecordPath* = "config/trusted_writer_set.json"
  ProductionPinRecordField* = "trustedAdmissionWorkflowSha"

{.pop.}