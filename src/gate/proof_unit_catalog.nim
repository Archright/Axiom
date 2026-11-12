## proof_unit_catalog.nim — W-unit axis: single editing authority
##
## The W1–W11 CI work-unit catalog (id, name, input path patterns, duration,
## tier membership, full-certification requirement, sub-stage ids) is defined
## HERE and only here. Consumers MUST source W-axis facts from this module —
## no hardcoded re-declaration elsewhere:
##   - tools/ci/impact_closure_selector.nim (makeWorkUnits builds from this)
##   - tests/unit/test_run_identity.nim (manifest integrity)
##   - tests/features/selector_soundness_oracle.nim (ValidWorkUnits)
##   - docs/spec/incremental_ci_tiers_scheduling.md §3 + docs/adr/0019 §2
##     (reference only — no value duplication)
##
## Authority boundaries (separate axes, intentionally NOT duplicated here):
##   - File→gate axis (gate SSOT):    src/gate/topology_spec.nim (ADR-0004)
##   - Gateway partition axis:        Makefile gateway_shard_files
##   - Soundness mutation oracle:     data/selector_soundness/mutation_catalog.json
##     (independent oracle — deliberately NOT derived from this catalog, §0.9)
##   - Scheduling policy Tier(C):     incremental_ci_tiers_scheduling.md §5 (A1)
##   - Semantic rule algorithm (BFS/depends_on): impact_closure_selector.nim §7
##
## Data provenance (cutover 2026-09-23):
##   - pathPatterns/duration: values previously hardcoded in
##     tools/ci/impact_closure_selector.nim §2 (makeWorkUnits), themselves
##     sourced from ci_observed_dag_p1_2026-08-28.md / migration-doc / gh-run.
##   - tier membership: incremental_ci_tiers_scheduling.md §3 (2026-08-28):
##     L0 = {W3, W4/G7, W10, W11}, L1 = {W1, W2, W4, W5, W6, W7, W8},
##     L2 = full pipeline (W9 is L2-only). W4/G7 denotes the G7 sub-stage of
##     W4 (see subunits).
##   - requiredForFullCertification: data/ci_required_work_units.json (deleted
##     2026-09-23; its sole consumer converted to this module).
##   - no-effect constants: repo-level certified non-affecting declarations
##     previously in impact_closure_selector.nim §8a (docs/ blanket removed 2026-09-23).

import std/math

{.push raises: [].}

type
  ProofTier* = enum
    ptL0 = "L0", ptL1 = "L1", ptL2 = "L2"

  ProofUnit* = object
    id*: string                 # "W1" .. "W11"
    name*: string               # e.g. "verify-static"
    pathPatterns*: seq[string]  # input-closure glob patterns (selector §7 direct matching)
    durationMin*: float         # measured minutes; NaN for unknown (W9 — legacy "UNKNOWN" expression)
    tier*: ProofTier            # L0/L1/L2 membership (tier spec §3)
    requiredForFullCertification*: bool  # full-certification (L2) membership
    subunits*: seq[string]      # sub-stage ids (W4 → G1/G2/G6/G7; G7 is an L0 sub-stage per tier spec)

const
  ProofUnitCatalog* = [
    ProofUnit(id: "W1", name: "verify-static",
      pathPatterns: @["*.nim", "src/", "AGENTS.md",
                      "config/gates.manifest.toml", "src/gate/manifest.d/",
                      "src/generated/", "proofs/", "data/asset_hygiene_baseline.json",
                      "Makefile", ".circleci/"],
      durationMin: 16.0, tier: ptL1, requiredForFullCertification: true, subunits: @[]),
    ProofUnit(id: "W2", name: "ci-bootstrap",
      pathPatterns: @["src/cli/", "src/core/", "axiom.nimble", "config.nims",
                      "lakefile", "lean-toolchain"],
      durationMin: 5.33, tier: ptL1, requiredForFullCertification: true, subunits: @[]),
    ProofUnit(id: "W3", name: "verify-contract-release-e2e-full",
      pathPatterns: @["bin/ax"],
      durationMin: 0.13, tier: ptL0, requiredForFullCertification: true, subunits: @[]),
    ProofUnit(id: "W4", name: "verify-contract",
      pathPatterns: @["src/", "tests/unit/", "tests/gateway/", "tests/verification/",
                      "tests/negative/", "tools/invariant_mutation_harness.sh",
                      "tools/readiness_evaluator.nim", "config/readiness_policy.json",
                      "bin/ax"],
      durationMin: 16.83, tier: ptL1, requiredForFullCertification: true,
      subunits: @["G1", "G2", "G6", "G7"]),
    ProofUnit(id: "W5", name: "ci-unit-tests",
      pathPatterns: @["src/"],
      durationMin: 12.30, tier: ptL1, requiredForFullCertification: true, subunits: @[]),
    ProofUnit(id: "W6", name: "verify-all",
      pathPatterns: @["src/", "proofs/", "tools/meta_spec_gate.nim",
                      "tools/ci/check_nim_theater.nim", "tools/ci/check_lean_vacuity.nim",
                      "tools/ci/doc_path_validator.nim", "tests/architecture_constraints.nim"],
      durationMin: 4.25, tier: ptL1, requiredForFullCertification: true, subunits: @[]),
    ProofUnit(id: "W7", name: "ci-gates",
      pathPatterns: @["config/gates.manifest.toml", "src/gate/manifest.d/",
                      "src/gate/runners/", "src/", "tests/gateway/",
                      "config/readiness_policy.json"],
      durationMin: 3.15, tier: ptL1, requiredForFullCertification: true, subunits: @[]),
    ProofUnit(id: "W8", name: "test-gateway",
      pathPatterns: @["tests/gateway/", "src/cli/run_gate.nim", "src/gate/utils/"],
      durationMin: 11.88, tier: ptL1, requiredForFullCertification: true, subunits: @[]),
    ProofUnit(id: "W9", name: "ci-lake-build",
      pathPatterns: @["proofs/", "lakefile.lean"],
      durationMin: NaN, tier: ptL2, requiredForFullCertification: true, subunits: @[]),
    ProofUnit(id: "W10", name: "verify-coverage-guard",
      pathPatterns: @["tools/coverage_guard.nim", "tools/measure_coverage.nim",
                      "build/branch_coverage.json", "data/.coverage_baseline_main.json"],
      durationMin: 2.05, tier: ptL0, requiredForFullCertification: true, subunits: @[]),
    ProofUnit(id: "W11", name: "generate-docs",
      pathPatterns: @["src/engine.nim", "src/engine/", "src/core/", "src/generated/"],
      durationMin: 1.80, tier: ptL0, requiredForFullCertification: true, subunits: @[])
  ]

# ═══════════════════════════════════════════════════════════════════════════
# Repo-level certified no-effect declarations (moved from
# impact_closure_selector.nim §8a, 2026-09-23).
#
# NOTE: the former blanket "docs/" prefix is REMOVED. docs/ paths with known
# impact carry explicit edges instead (docs/spec/** → W4/W7 via selector Step 7;
# docs/DEBT_REGISTRY.md → W1; docs/agents/** → build input or gate-scan input →
# conservative UNCERTAIN). The docs/agents build-input claim covers EXACTLY the
# 3 embedded files — AGENTS.md, docs/agents/architecture.md,
# docs/agents/rules_workflow.md (tools/generate_embedded_docs.nim:13-17); the
# remaining docs/agents files are normative docs on the gate-scan axis
# (proof_unit_consistency_gate (g) roots docs/agents|docs/spec|config/policy),
# so their impact is non-zero on that axis too — "0 아님" (정정 2026-09-30,
# plan Phase 2d; classification unchanged). Other docs paths remain
# non-affecting via the ".md" extension below — existing behavior preserved.
# ═══════════════════════════════════════════════════════════════════════════

const
  CertifiedNoEffectPrefixes* = @[
    ".github/",         # workflow metadata (ci.yml removed at CI=0 cutover)
    ".githooks/", ".opencode/", ".axiom/", ".config/", ".cursorrules"
  ]
  CertifiedNoEffectExtensions* = @[
    ".md", ".png", ".svg", ".jpg", ".jpeg", ".gif", ".ico", ".webp",
    ".lock", ".nix", ".dockerignore", ".gitignore", ".gitattributes",
    ".envrc", ".editorconfig", ".git"
  ]
  CertifiedNoEffectRootNames* = @["license", "copying", "readme"]

{.pop.}
