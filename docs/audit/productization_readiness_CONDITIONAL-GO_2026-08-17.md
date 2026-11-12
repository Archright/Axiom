# Axiom v1 Productization Readiness Audit — CONDITIONAL GO

- **Date**: 2026-08-17T05:30:00Z
- **Baseline commit**: `6206884461987d4e0114b8e5a49fd8cda9fedaee` (treeDigest `sha256:c9d7e4d1…`), evidence freeze `61765c622`, R1 atom fix `90e5e3ea1`
- **Decision artifact**: `data/readiness/decision.GO.2026-08-17.json` (verdict `CONDITIONAL GO`, conditions `["R7=FAIL"]`)
- **Evaluator**: `tools/readiness_evaluator.nim` (pure decision function; `bin/readiness_evaluator`, deterministic build 2026-08-17)
- **Policy**: `config/readiness_policy.json` (axiom-readiness-v1)
- **Supersedes**: `docs/audit/productization_readiness_2026-08-17.md` (NO-GO interim, same-date earlier snapshot) — kept for history, this document is the authoritative decision for the current baseline.

## Verdict table

| Invariant | State | Criticality |
|-----------|-------|-------------|
| R1 Product Contract | PASS | critical |
| R2 Result Semantics | PASS | critical |
| R3 Verification Determinism | PASS | critical |
| R4 Artifact/Provenance Integrity | PASS | critical |
| R5 CLI Contract Stability | PASS | critical |
| R6 Failure Semantics | PASS | critical |
| R7 Scope/Coverage Honesty | **FAIL** (measured 0.0 < 0.5; snapshot run 4/23 = 0.1739 < 0.5) — 제품 scope disclosure: 낮은 coverage는 제품 부정이 아니라 "이번 실행에서 해당 assurance에 도달한 symbol 수"의 공개 문제. overclaim 아님 (claim ⊆ emitter 유지) | non-critical |
| R8 Reproducible Operability | PASS (documented developer-source execution path on snapshot basis; **fresh-clone install reproducibility remains UNVERIFIED**) | critical |

## What was verified (evidence, not claims)

1. **P1 Tier semantics — R2 PASS**: `tests/unit/test_assurance_tier_node_report.nim` 12/12 pass; `assuranceTier`/`tierResolution` projected losslessly into `ax report --json`; z3-only → `z3-verified`, dual → `dual-verified` (distinguishable).
2. **P2 Certificate trust closure — R4 PASS**: `tests/unit/test_certificate_trust_closure.nim` 4/4 pass; `verifyCertificateClosure` (deep verify → identityDigest recompute → trust journal binding → replay input match → `H(certProjection)==H(journalClaimProjection)`); `ax cert verify` rewired; tampered cert → FAIL; journal missing → JOURNAL_REQUIRED (exit 2).
3. **P5 CLI contract — R1/R5 PASS**: `tests/unit/wf_runners_exit_code_test.nim` 9/9 pass; `axProofShortcutExitCode` (verified=0 ∧ failed/timeout>0 → 1); `schemaVersion: axiom.report.v1` injected and foreign values rejected; exit-code family per command differ from success (0 vs 1/139); stdout/stderr split verified.
4. **P1 cache fail-closed — R6/R8 PASS**: corrupt `topology_merkle.json` → exit 0, SIGSEGV-free, cache rebuilt, same `proof_universe commit fec26838…`; cache is optimization, not truth.
5. **P6 Golden Product Run (snapshot A, same binary):**
   - `ax prove --limit 1` ×2 (cold cache): exit 0/0, telemetry-excluded projection **identical** `d0153741a6ff…` (raw diff = 4 timing lines only)
   - `ax report --json` ×2: exit 1/1 (verified=0 → contract verification-failure, not crash), projection identical `a41b3ea6e8a7…`, schemaVersion present
   - VKD: single canonical projection `getCanonicalVkdMetrics`; snapshot VKD = 4/23 ≈ 0.1739 (+4 certGreen-admitted) vs main-repo state 0/23 — value depends on state file prefetch by design; threshold 0.5 unmet
6. **R7 scope honesty**: README claims reduced to supported kernel scope; `verifiedEmitterScope ⊆ claimedScope` → no overclaim promotion; R7 FAIL is pure low-coverage, non-critical.

## Conditions attached to GO

1. **R7 coverage threshold** (`vkdMinThreshold: 0.5`) — current measured VKD 0.0–0.1739 far below; first pilot must not advertise coverage numbers. Condition: either raise coverage via admitted-certGreen expansion or explicitly document v1 as bounded-coverage preview with VKD reported live.
2. **AGENTS.md §0.11 stale VKD number (5/23 ≈ 21.7%)** — superseded by measured 0.0/0.174; **RESOLVED 2026-08-17 (rev.3.1 승인)**: AGENTS.md §-1 불변 파일에서 값 라인을 제거하고 canonical projection 원칙 문구로 교체 (`git diff AGENTS.md` = 값 삭제 + 원칙 블록만). VKD 판정 수치는 `metrics.vkd` (SSOT)만 사용한다.
3. **Negative-fixture harness** — `--target` outside the compile-time axiomRegistry silently falls back to full frontier (exit 0, no false-success); need explicit invalid-input (exit 3) before v1 GA.
4. **Golden-run harness location** — goldens currently artifact-in-/tmp; a tracked `tests/golden/readiness/` harness with 2× repeat + projection-hash assertion belongs to the minimum gate (committed harness deferred to first follow-up).

## Non-blocking debt (post-v1 workstreams)

- Reproducible cross-build byte determinism (snapshot A/B binaries differ)
- Full-frontier wall-time/сgroup budget measurement for long runs
- `src/generated/build_env.nim` regeneration: keep as tracked file with idempotent write (content-dependent, deterministic)
- Full `tests/golden/readiness/` fixture expansion (positive ×2, negative ×2 persisted)
- Debt registry triage: file-level blankets without product impact remain internal maintainability

## Evidence files

`data/readiness/evidence/R1..R8.json` — schemaVersion 1, collection 2026-08-17T05:00Z, freshUntil 2026-09-16T05:00Z; repoIdentity head/treeDigest frozen to evaluation baseline; evaluator validation: 8 valid, 0 invalid (rerun passes).

## Repro command

```bash
export PATH="$HOME/.choosenim/toolchains/nim-2.2.10/bin:$HOME/.nimble/bin:$PATH"
nim c -o:bin/readiness_evaluator tools/readiness_evaluator.nim
bin/readiness_evaluator --policy config/readiness_policy.json --evidence-dir data/readiness/evidence \
  --repo-head 6206884461987d4e0114b8e5a49fd8cda9fedaee --tree-digest sha256:c9d7e4d191273630159488972e85f035eb9ff9915667552c7eeee14e67a6b02b \
  --working-tree-clean true --toolchain-nim 2.2.10 --toolchain-z3 4.13.3 --toolchain-lean 4.29.0 \
  --eval-time 2026-08-17T05:30:00Z --out data/readiness/decision.GO.2026-08-17.json
```

(Use the exact repo-head of the baseline commit `620688446…`; `git rev-parse HEAD` at evaluation time.)