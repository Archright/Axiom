# Phase 7: CI Migration-Aware Baseline Classifier

**Status**: Design
**Date**: 2026-08-14
**Applies to**: Axiom integrity engine — Phase 7 CI baseline migration classifier
**Extends**: `docs/design/phase5_claimstore_index.md` (Phase 5 ClaimStore), `docs/design/phase3_evidence_claiming.md` (claim model)

---

## 0. Source Grounding

| Source | Key type / function | Used in |
|--------|---------------------|---------|
| `src/cli/shared/baseline_snapshot_core.nim:346` | `baselineCheckOutcome*` — numeric-only (VKD/dual count) comparison | Current CI baseline gate |
| `src/cli/shared/baseline_snapshot_core.nim:50` | `BaselineSnapshot*` — vkdFixed4, coverageRatio, tierDistribution | Current snapshot type |
| `src/cli/shared/baseline_snapshot_core.nim:308` | `BaselineCheckOutcome*` — code + changeKind (IMPROVEMENT/REGRESSION/RECLASSIFICATION/MAINTAINED) | Current outcome type |
| `src/gate/manifest.d/stale-cert-gate.json` | stages: `["ci"]`, entry: `tools/stale_cert_gate` | CI gate wiring (manifest.d) |
| `src/gate/manifest.d/coverage-ratchet-gate.json` | stages: `["pre-push","ci"]`, entry: `src/gate/runners/coverage_ratchet_gate` | CI gate wiring (manifest.d) |
| `.github/workflows/ci.yml` | `make ci-gates` → `bin/gate_hook ci` (ARCHITECT-IMMUTABLE) | CI pipeline |
| `src/gate/runners/gate_hook.nim:394-401` | `if stage == "ci"` → CAS pre-flight → `orch.runCi()` | Gate hook CI path |
| `src/gate/gate_contract.nim:40-43` | `gsPreCommit`, `gsPrePush`, `gsCI` stage enum | Gate stage wiring |

---

## 1. Current State

### 1.1 `baselineCheckOutcome` — Numeric-Only Detector

`baselineCheckOutcome` (`baseline_snapshot_core.nim:346`) compares two scalar values:

1. `vkdFixed4` (string-parsed float) — the VKD headline metric
2. `dualVerifiedCount` (int) — genuinely dual-verified certificate count

It produces a `BaselineCheckOutcome` (`baseline_snapshot_core.nim:308`) with `changeKind` ∈ {"IMPROVEMENT","REGRESSION","RECLASSIFICATION","MAINTAINED"}. The decision logic at lines 383–403 is a **single-axis threshold comparison**: if VKD drops, it checks whether the dual-verified count also dropped to distinguish regression from reclassification.

### 1.2 The `BaselineSnapshot` Type

`BaselineSnapshot` (`baseline_snapshot_core.nim:50`) carries numeric metrics only: `vkdFixed4`, `timestamp`, `totalFunctions`, `verifiedFunctions`, `vkdScore`, `coverageRatio`, `rigorScore`, `tierDistribution`, `certificatesByTier`, `soundnessMode`, `topSourceModules`, `kernelTotal`, `kernelExemptTotal`, `vksTotal`. It has **no content-addressable identity** over the claim set, no per-axis diff capability, and no migration/regression distinction based on semantic changes. The `BaselineCheckOutcome.changeKind` field is a string enum that conflates metric comparison with semantic classification.

### 1.3 The vkdFixed4 Lesson

The vkdFixed4 metric can change for two fundamentally different reasons:

- **Genuine regression**: a verified function lost its proof (VKD drops, dual count drops).
- **Semantic reclassification**: a function migrated from Z3-only to dual-verified (VKD drops because the denominator changed, but dual count preserved or grew). This is **migration**, not regression — yet the current code classifies it as RECLASSIFICATION only when dual count is preserved, and as ACTUAL_REGRESSION when dual count drops. The metric-semantics gap is not captured.

### 1.4 CI Gating Path

The CI baseline gate is wired mechanically through `manifest.d`:

```
.github/workflows/ci.yml:164  →  make ci-gates  →  bin/gate_hook ci
  └─ gate_hook.nim:394-401    →  allGates() filtered by gsCI stage
       └─ manifest.d/*.json    →  stale-cert-gate, coverage-ratchet-gate, ...
```

The `stale-cert-gate` and `coverage-ratchet-gate` are registered in `manifest.d` with `"stages": ["ci"]` and are invoked by `gate_hook ci` via the manifest-driven stage filter. No baseline-specific gate exists today — baseline checking is triggered via `--rebaseline` flag or the `baseline_cli.nim` path, not as a CI-stage gate in manifest.d.

### 1.5 What Is Missing

The current design has no content-addressable baseline identity, no per-axis diff capability, and no migration/regression distinction based on semantic changes. The `BaselineCheckOutcome.changeKind` field conflates metric comparison with semantic classification.

---

## 2. Proposal

### 2.1 Core Design: Detector + Classifier Separation

The baseline hash is a **DETECTOR**; a separate **TRANSITION CLASSIFIER** decides IMPROVEMENT/REGRESSION/RECLASSIFICATION/MIGRATION from per-axis diffs — NOT from a raw metric drop.

```
Baseline = H(ClaimPolicyVersion, ClaimSet)          # detector (content hash)
TransitionClassifier(diff) → {IMPROVEMENT, REGRESSION, RECLASSIFICATION, MIGRATION}
```

**Key principle**: a raw VKD/coverage metric drop is never sufficient to declare regression. The classifier must inspect the per-axis diff to determine whether the drop is caused by a semantic migration (e.g., reclassification of certGreen → certZ3Verified) or a genuine proof loss.

### 2.2 Per-Axis Diff Dimensions

The classifier operates on a diff of per-axis attributes:

| Axis | Source | Diff Signal |
|------|--------|-------------|
| `sourceHash` | `BaselineSnapshot.topSourceModules` + `certificatesByTier` content hash | New/removed/changed source modules |
| `specId` | Claim `specId` (H(canonicalSpecIR, origin, ruleVersion)) | Spec change → possible reclassification |
| `semanticProfileId` | Claim `semanticProfileId` | Semantic contract change → migration |
| `encoding` | Certificate encoding version / tier | Tier migration (Z3-only → dual-verified) |
| `evidence` | `EvidenceBundle` content hash | Evidence change → reclassification or regression |
| `policy` | `ClaimPolicyVersion` | Policy version change → migration |

### 2.3 TransitionClassifier Algorithm

The classifier is a two-phase function:

**Phase 1 — Axis Diff Extraction**: `extractPerAxisDiffs(ClaimDiff) → AxisDiffs` walks the ClaimDiff and produces a set of axis-level change flags. Each axis is independently classified as `UNCHANGED`, `MODIFIED`, or `ADDED/REMOVED`.

**Phase 2 — Classification Decision**: `classifyAxisDiffs(AxisDiffs, VKD metrics) → TransitionClass` applies the decision table (§2.4) using axis-level flags as primary inputs and VKD/dual-count metrics as fallback signals.

```nim
TransitionClassifier(claimDiff: ClaimDiff; vkdMetrics: VkdMetrics): TransitionClass =
  let axisDiffs = extractPerAxisDiffs(claimDiff)
  if axisDiffs.hasAnyMigrationSignal:
    return MIGRATION
  if axisDiffs.hasAnyReclassificationSignal:
    return RECLASSIFICATION
  if axisDiffs.hasRegressionSignal:
    return REGRESSION
  # Fallback: metric-only comparison (pre-ClaimStore or no claim diff available)
  if vkdMetrics.vkdDropped and vkdMetrics.dualCountDropped:
    return REGRESSION
  if vkdMetrics.vkdDropped and vkdMetrics.dualCountPreserved:
    return RECLASSIFICATION
  if vkdMetrics.vkdIncreased:
    return IMPROVEMENT
  return MAINTAINED
```

### 2.4 Classification Decision Table

| Source diff | Spec diff | SemanticProfile diff | Evidence diff | Policy diff | Classification |
|-------------|-----------|---------------------|---------------|-------------|----------------|
| — | — | — | — | — | IMPROVEMENT (new proofs added) |
| — | — | — | — | — | REGRESSION (proofs lost) |
| — | — | ✓ | — | — | RECLASSIFICATION (semantic contract changed) |
| ✓ | — | — | — | — | RECLASSIFICATION (source refactored, proof preserved) |
| — | ✓ | — | — | — | RECLASSIFICATION (spec changed, proof preserved) |
| — | — | — | ✓ | — | RECLASSIFICATION (evidence updated) |
| — | — | — | — | ✓ | MIGRATION (policy migration) |
| ✓ | ✓ | ✓ | ✓ | ✓ | MIGRATION (full migration) |
| VKD↓ + dualCount↓ | — | — | — | — | REGRESSION (genuine proof loss) |
| VKD↓ + dualCount≥ | — | — | — | — | RECLASSIFICATION (P0-style reclassification) |

**The VKD/dual-count comparison is a fallback signal, not the primary classifier.** When per-axis diffs indicate migration (spec/semanticProfile/policy change), the classification is MIGRATION regardless of whether VKD dropped. This is the vkdFixed4 lesson: a metric-semantics change must be classified as migration, not regression.

### 2.5 Per-Metric Coexistence (Do NOT Build One Universal Engine)

The VKD gate and coverage gate are **separate per-metric coexistence works**:

- **VKD gate** (`baseline_snapshot_core.nim:346`): uses `BaselineSnapshot` + `baselineCheckOutcome` for VKD/dual-count comparison. The TransitionClassifier augments this with per-axis diff analysis.
- **Coverage gate** (`coverage-ratchet-gate.json`): uses `coverage_ratchet_gate` with its own baseline (`data/reliability_score.json`). The classifier does NOT unify these two gates into one engine.

Each metric gate retains its own baseline hash and comparison logic. The TransitionClassifier is a **separate layer** that can be invoked by either gate when a baseline diff is detected. The classifier is metric-agnostic — it consumes axis diffs and produces a classification, which the gate then maps to its own exit-code contract.

### 2.6 How a Claim-Set Diff Feeds the Classifier

**Note**: `ClaimSet` does not yet exist — it is part of Phase-5 ClaimStore (`docs/design/phase5_claimstore_index.md`). The classifier is designed to consume a ClaimSet diff when ClaimStore is available.

```
ClaimStore (Phase 5)
  └─ ClaimSet = { claimId → VerifiedClaim }
       └─ diff(ClaimSet_old, ClaimSet_new) → ClaimDiff
            ├─ addedClaims:    seq[VerifiedClaim]
            ├─ removedClaims:  seq[VerifiedClaim]
            ├─ changedClaims:  seq[(VerifiedClaim, VerifiedClaim)]  # before/after
            └─ unchangedClaims: seq[VerifiedClaim]

TransitionClassifier(ClaimDiff) → TransitionClass
  ├─ extractPerAxisDiffs(ClaimDiff) → AxisDiffs
  ├─ classifyAxisDiffs(AxisDiffs) → TransitionClass
  └─ applyFallbackMetricCheck(AxisDiffs, VKD metrics) → TransitionClass
```

When ClaimStore is not yet available (pre-Phase 5), the classifier falls back to the existing numeric-only `baselineCheckOutcome` logic. The classifier is **forward-compatible**: it consumes ClaimSet diffs when available and degrades gracefully to metric-only comparison otherwise.

### 2.7 CI Integration Path

The classifier integrates into CI via the existing manifest.d wiring:

1. A new gate entry in `src/gate/manifest.d/` (e.g., `baseline-classifier-gate.json`) with `"stages": ["ci"]` and `"execution_mode": "interpreted"`.
2. The gate runner invokes `TransitionClassifier` on the current `BaselineSnapshot` vs. the stored baseline.
3. The gate returns exit code 0 for IMPROVEMENT/RECLASSIFICATION/MIGRATION, exit code 1 for REGRESSION.
4. The `gate_hook ci` path (`gate_hook.nim:394-401`) picks it up automatically via the manifest stage filter — no CI workflow changes needed (`.github/workflows/ci.yml` is ARCHITECT-IMMUTABLE).

---

## 3. Design Constraints

1. **No source modification**: This document is a design artifact only.
2. **Per-metric coexistence**: VKD gate and coverage gate remain separate; no universal engine.
3. **Detector ≠ Classifier**: The baseline hash (`H(ClaimPolicyVersion, ClaimSet)`) detects change; the classifier interprets it.
4. **Migration over regression**: When per-axis diffs indicate semantic migration, classification is MIGRATION regardless of metric direction.
5. **Fallback to metric-only**: Before ClaimStore is available, the classifier degrades to the existing `baselineCheckOutcome` logic.
6. **Manifest-driven CI wiring**: Gates are registered in `manifest.d` and picked up by `gate_hook ci` — no CI workflow edits.