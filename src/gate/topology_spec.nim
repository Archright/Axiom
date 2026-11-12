import gate/framework/topology_types
import std/tables

## Orphan Gate Authority Closure (2026-10-08) — stages declaration honesty.
## The ci.yml retirement (fa069d610, 2026-09-16) removed the last production
## `bin/gate_hook ci` caller (former chain: ci.yml verify-integration-r1 →
## `make ci-gates` → `AXIOM_CI=1 bin/gate_hook ci`), so `ci` stage claims
## became unverifiable false protection claims. Live verdict authority is the
## four .githooks direct calls only (anti-theater, layer-enforcement, nim-check,
## stale-cert); every other gate is declared `manual` = standalone direct-run
## contract, not stage-dispatched. Enforcement: manifest-consistency-gate
## Check 10 (declaration↔call-site consistency) — a gate may re-declare
## `ci` only after a production gate_hook invocation lane exists again.

const TopologySpec* = [
  initTopologyEntry(
    id = "anti-theater-gate",
    name = "Anti-Theater Gate",
    layer = lkFunctional,
    entry = "src/gate/runners/anti_theater_gate",
    stages = @[skPreCommit],
    filesPattern = "*.nim|Makefile|*.mk|.circleci",
    passFilenames = false,
    weight = wkLight,
    category = ckRule,
    severity = svError
  ),
  initTopologyEntry(
    id = "evidence-truth-boundary-gate",
    name = "Evidence Truth Boundary Gate",
    layer = lkFunctional,
    entry = "src/gate/runners/evidence_truth_boundary_gate",
    stages = @[skManual],
    filesPattern = "*.nim",
    passFilenames = false,
    weight = wkLight,
    category = ckRule,
    severity = svError
  ),
  initTopologyEntry(
    id = "decision-binding-gate",
    name = "Decision Binding Gate",
    layer = lkFunctional,
    entry = "src/gate/runners/decision_binding_gate",
    stages = @[skManual],
    filesPattern = "*.nim",
    passFilenames = false,
    weight = wkLight,
    category = ckRule,
    severity = svError
  ),
  initTopologyEntry(
    id = "asset-hygiene-gate",
    name = "Axiom asset hygiene gate",
    layer = lkFunctional,
    entry = "src/gate/runners/asset_hygiene_gate",
    stages = @[skManual],
    filesPattern = ".gitattributes|docs/|src/|data/asset_hygiene_baseline.json",
    passFilenames = false,
    weight = wkMedium,
    category = ckRule,
    severity = svError,
    executionMode = emInterpreted
  ),
  initTopologyEntry(
    id = "binary-artifact-gate",
    name = "Axiom binary artifact gate",
    layer = lkFunctional,
    entry = "src/gate/runners/binary_artifact_gate.nim",
    stages = @[skManual],
    passFilenames = true,
    weight = wkMedium,
    category = ckRule,
    severity = svError
  ),
  initTopologyEntry(
    id = "binary-freshness-gate",
    name = "Axiom binary freshness gate",
    layer = lkFunctional,
    entry = "src/gate/runners/binary_freshness_gate",
    stages = @[skManual],
    filesPattern = "src/|axiom.nimble|config.nims",
    passFilenames = false,
    weight = wkMedium,
    category = ckRule,
    argsTemplate = @["$repoRoot"],
    after = @["cli-build"],
    tier = 1,
    severity = svError,
    executionMode = emInterpreted
  ),

  initTopologyEntry(
    id = "cli-build",
    name = "Axiom CLI build gate",
    layer = lkFunctional,
    entry = "src/gate/runners/cli_build",
    stages = @[skManual],
    filesPattern = "src/|src/semantic_proofs|tests|lakefile|lean-toolchain|axiom.nimble|config.nims|AGENTS.md",
    passFilenames = false,
    weight = wkHeavy,
    category = ckRule,
    tier = 1,
    severity = svError,
    executionMode = emInterpreted
  ),
  initTopologyEntry(
    id = "conflict-marker-gate",
    name = "Axiom conflict marker gate",
    layer = lkFunctional,
    entry = "src/gate/runners/conflict_marker_gate",
    stages = @[skManual],
    filesPattern = "src/",
    passFilenames = true,
    weight = wkMedium,
    category = ckRule,
    argsTemplate = @["$repoRoot", "$mode", "$maxJobs"],
    severity = svError
  ),
  initTopologyEntry(
    id = "core-invariant-gate",
    name = "Axiom core invariant gate",
    layer = lkFunctional,
    entry = "src/gate/runners/core_invariant_gate.nim",
    stages = @[skManual],
    filesPattern = "src/core/[^/]+\\.nim$",
    passFilenames = true,
    weight = wkLight,
    category = ckTheorem,
    severity = svError
  ),
  initTopologyEntry(
    id = "coverage-ratchet-gate",
    name = "Axiom coverage ratchet gate",
    layer = lkFunctional,
    entry = "src/gate/runners/coverage_ratchet_gate",
    stages = @[skManual],
    filesPattern = "src/",
    passFilenames = false,
    weight = wkMedium,
    category = ckRule,
    severity = svError,
    executionMode = emInterpreted
  ),
  initTopologyEntry(
    id = "debt-integrity-gate",
    name = "Axiom debt integrity gate",
    layer = lkFunctional,
    entry = "src/gate/runners/debt_integrity_gate",
    stages = @[skManual],
    filesPattern = "src/",
    passFilenames = true,
    weight = wkMedium,
    category = ckRule,
    argsTemplate = @["$repoRoot", "$mode", "$maxJobs"],
    severity = svError
  ),
  initTopologyEntry(
    id = "delegation-enforcer",
    name = "Axiom delegation enforcer",
    layer = lkFunctional,
    entry = "src/gate/runners/delegation_enforcer.nim",
    stages = @[skManual],
    passFilenames = false,
    weight = wkMedium,
    category = ckPolicy,
    severity = svError
  ),
  initTopologyEntry(
    id = "discarded-write-audit-gate",
    name = "Discarded write audit gate",
    layer = lkFunctional,
    entry = "src/gate/runners/discarded_write_audit_gate",
    stages = @[skManual],
    filesPattern = "src/",
    passFilenames = false,
    weight = wkMedium,
    category = ckRule,
    severity = svError,
    executionMode = emInterpreted
  ),
  initTopologyEntry(
    id = "doc-completeness-gate",
    name = "Axiom documentation completeness gate",
    layer = lkFunctional,
    entry = "src/gate/runners/doc_completeness_gate.nim",
    stages = @[skManual],
    filesPattern = "src/|docs/|AGENTS.md",
    passFilenames = false,
    weight = wkLight,
    category = ckRule,
    severity = svError
  ),
  initTopologyEntry(
    id = "documentation-first-gate",
    name = "Axiom documentation first gate",
    layer = lkFunctional,
    entry = "src/gate/runners/documentation_first_gate",
    stages = @[skManual],
    filesPattern = "src/|docs/|AGENTS.md",
    passFilenames = true,
    weight = wkLight,
    category = ckPolicy,
    severity = svError
  ),
  initTopologyEntry(
    id = "effect-inference-gate",
    name = "Axiom effect inference gate",
    layer = lkFunctional,
    entry = "src/gate/runners/effect_inference_gate",
    stages = @[skManual],
    filesPattern = "src/core/",
    passFilenames = true,
    weight = wkMedium,
    category = ckRule,
    argsTemplate = @["$repoRoot", "$mode", "$maxJobs"],
    severity = svWarn
  ),
  initTopologyEntry(
    id = "env-gate",
    name = "Environment Variable Gate",
    layer = lkFunctional,
    entry = "src/gate/runners/env_runner",
    stages = @[skManual],
    filesPattern = "*.nim|Makefile|*.mk|.circleci|*.env",
    passFilenames = false,
    weight = wkLight,
    category = ckValidation,
    severity = svError
  ),
  initTopologyEntry(
    id = "external-cli-smoke",
    name = "Axiom external CLI smoke gate",
    layer = lkFunctional,
    entry = "src/gate/runners/external_cli_smoke.nim",
    stages = @[skManual],
    filesPattern = "src/|src/semantic_proofs|lakefile|lean-toolchain|axiom.nimble|config.nims",
    passFilenames = false,
    weight = wkMedium,
    category = ckRule,
    after = @["cli-build"],
    severity = svError
  ),
  initTopologyEntry(
    id = "gate-self-check",
    name = "Axiom gate self check",
    layer = lkMeta,
    entry = "bin/gate_self_check",
    stages = @[skManual],
    passFilenames = false,
    weight = wkMedium,
    category = ckRule,
    severity = svError,
    alwaysRun = true
  ),
  initTopologyEntry(
    id = "gateway-test",
    name = "Axiom gateway test gate",
    layer = lkFunctional,
    entry = "src/gate/runners/gateway_test_gate.nim",
    stages = @[skManual],
    filesPattern = "src/|tests/|axiom.nimble|config.nims",
    passFilenames = false,
    weight = wkHeavy,
    category = ckRule,
    argsTemplate = @["$repoRoot", "$mode", "$maxJobs"],
    depsDirs = @["tests/gateway/", "bin/gateway_test_gate"],
    after = @["nim-check"],
    severity = svError
  ),
  initTopologyEntry(
    id = "golden-master-gate",
    name = "Golden master snapshot gate",
    layer = lkFunctional,
    entry = "src/gate/runners/golden_master_gate",
    stages = @[skManual],
    filesPattern = "src/",
    passFilenames = false,
    weight = wkMedium,
    category = ckRule,
    severity = svError
  ),
  initTopologyEntry(
    id = "hermetic-test-gate",
    name = "Axiom hermetic test gate",
    layer = lkFunctional,
    entry = "src/gate/runners/hermetic_test_gate",
    stages = @[skManual],
    filesPattern = "tests/|data/hermetic_test_baseline.json",
    passFilenames = false,
    weight = wkMedium,
    category = ckRule,
    severity = svError,
    executionMode = emInterpreted
  ),
  initTopologyEntry(
    id = "hotspot-gate",
    name = "Axiom hotspot gate",
    layer = lkFunctional,
    entry = "src/gate/runners/hotspot_gate",
    stages = @[skManual],
    filesPattern = "src/",
    passFilenames = true,
    weight = wkMedium,
    category = ckRule,
    argsTemplate = @["$repoRoot", "$mode", "$maxJobs", "data/code_health_baseline.json"],
    tier = 1,
    severity = svError,
    executionMode = emInterpreted
  ),
  # NOTE: hotspot-coverage-gate (src/gate/runners/hotspot_coverage_gate.nim) is
  # a distinct live gate from hotspot-gate (src/gate/runners/hotspot_gate.nim).
  # The former enforces test coverage on high-churn modules; the latter runs the
  # code-health churn analysis. Functionally related but separate binaries — both
  # are SSOT-registered independently.
  initTopologyEntry(
    id = "hotspot-coverage-gate",
    name = "Axiom hotspot coverage gate",
    layer = lkFunctional,
    entry = "src/gate/runners/hotspot_coverage_gate",
    stages = @[skManual],
    filesPattern = "src/",
    passFilenames = true,
    weight = wkMedium,
    category = ckRule,
    argsTemplate = @["$repoRoot", "$mode", "$maxJobs"],
    severity = svError
  ),
  initTopologyEntry(
    id = "immunity-gate",
    name = "Axiom unified immunity gate",
    layer = lkMeta,
    entry = "src/gate/runners/immunity_gate",
    stages = @[skManual],
    filesPattern = "src/core/|data/immunity_baseline.json|logs/break_glass/",
    passFilenames = false,
    weight = wkHeavy,
    category = ckPolicy,
    severity = svError,
    executionMode = emInterpreted
  ),
  initTopologyEntry(
    id = "import-encapsulation-gate",
    name = "Axiom import encapsulation gate",
    layer = lkFunctional,
    entry = "src/gate/runners/import_encapsulation_gate",
    stages = @[skManual],
    filesPattern = "src/",
    passFilenames = true,
    weight = wkMedium,
    category = ckPolicy,
    argsTemplate = @["$repoRoot", "$mode", "$maxJobs"],
    severity = svError,
    executionMode = emInterpreted
  ),
  initTopologyEntry(
    id = "integrity-test",
    name = "Axiom integrity check gate",
    layer = lkFunctional,
    entry = "src/gate/runners/integrity_test",
    stages = @[skManual],
    filesPattern = "src/|tests/|axiom.nimble|config.nims",
    passFilenames = false,
    weight = wkHeavy,
    category = ckTheorem,
    after = @["cli-build"],
    tier = 1,
    severity = svError,
    executionMode = emInterpreted
  ),
  initTopologyEntry(
    id = "integrity-workflow",
    name = "Axiom integrity workflow gate",
    layer = lkFunctional,
    entry = "src/gate/runners/integrity_workflow",
    stages = @[skManual],
    passFilenames = false,
    weight = wkMedium,
    category = ckTheorem,
    severity = svError
  ),
  initTopologyEntry(
    id = "intent-gate",
    name = "Axiom intent gate",
    layer = lkFunctional,
    entry = "src/gate/runners/intent_gate.nim",
    stages = @[skManual],
    passFilenames = false,
    weight = wkLight,
    category = ckPolicy,
    severity = svError
  ),
  initTopologyEntry(
    id = "language-ban-gate",
    name = "Axiom language ban gate",
    layer = lkFunctional,
    entry = "src/gate/runners/language_ban_gate.nim",
    stages = @[skManual],
    passFilenames = true,
    weight = wkMedium,
    category = ckPolicy,
    severity = svError
  ),
  initTopologyEntry(
    id = "layer-enforcement-gate",
    name = "Layer Enforcement Gate",
    layer = lkFunctional,
    entry = "src/gate/runners/layer_enforcement_gate",
    # Orphan Gate Authority Closure (2026-10-08): the gate is invoked directly
    # at BOTH hooks — .githooks/pre-commit Part 3 (line 99) and .githooks/
    # pre-push Part 3 (line 38) — so the under-declared pre-push stage is now
    # stated instead of silently omitted.
    stages = @[skPreCommit, skPrePush],
    filesPattern = "*.nim",
    passFilenames = false,
    weight = wkMedium,
    category = ckRule,
    severity = svError
  ),
  initTopologyEntry(
    id = "lean-z3-consensus-gate",
    name = "Lean-Z3 consensus gate (dual-kernel proof verification)",
    layer = lkFunctional,
    entry = "src/gate/runners/lean_z3_consensus_gate",
    stages = @[skManual],
    filesPattern = "proofs/",
    passFilenames = false,
    weight = wkMedium,
    category = ckTheorem,
    tier = 1,
    severity = svError,
    executionMode = emInterpreted
  ),
  initTopologyEntry(
    id = "manifest-consistency-gate",
    name = "Axiom manifest consistency gate",
    layer = lkFunctional,
    entry = "src/gate/runners/manifest_consistency_gate",
    stages = @[skManual],
    filesPattern = "src/gate/manifest.d/|src/gate/gate_manifest.schema.json|src/gate/runners/",
    passFilenames = false,
    weight = wkMedium,
    category = ckPolicy,
    severity = svError,
    executionMode = emInterpreted
  ),
  initTopologyEntry(
    id = "mcp-tool-usage-gate",
    name = "Axiom MCP tool usage gate",
    layer = lkFunctional,
    entry = "src/gate/runners/mcp_tool_usage_gate",
    stages = @[skManual],
    filesPattern = "src/|docs/|AGENTS.md",
    passFilenames = true,
    weight = wkLight,
    category = ckRule,
    severity = svError
  ),
  initTopologyEntry(
    id = "monotonic-whitelist-gate",
    name = "Axiom monotonic whitelist gate",
    layer = lkFunctional,
    entry = "src/gate/runners/monotonic_whitelist_gate",
    stages = @[skManual],
    filesPattern = "src/gate/architecture_policy.lock",
    passFilenames = false,
    weight = wkMedium,
    category = ckPolicy,
    tier = 1,
    severity = svError,
    executionMode = emInterpreted
  ),
  initTopologyEntry(
    id = "nim-check",
    name = "Axiom nim check gate",
    layer = lkFunctional,
    entry = "src/gate/runners/nim_check_gate.nim",
    # Orphan Gate Authority Closure (2026-10-08): the only live dispatch is the
    # direct .githooks/pre-commit Part 1 invocation (line 74); the ci-stage
    # declaration died with the ci.yml retirement (fa069d610) that removed the
    # last `bin/gate_hook ci` production caller.
    stages = @[skPreCommit],
    filesPattern = ".nim|axiom.nimble|config.nims",
    passFilenames = true,
    weight = wkHeavy,
    category = ckRule,
    argsTemplate = @["$repoRoot", "$mode", "$maxJobs"],
    depsDirs = @["bin/nim_check_gate"],
    severity = svError
  ),
  initTopologyEntry(
    id = "policy-validator",
    name = "Axiom policy validator",
    layer = lkFunctional,
    entry = "src/gate/runners/policy_validator.nim",
    stages = @[skManual],
    filesPattern = "src/|architecture_policy.lock",
    passFilenames = false,
    weight = wkLight,
    category = ckPolicy,
    tier = 1,
    severity = svError
  ),
  initTopologyEntry(
    id = "procedure-gate",
    name = "Axiom procedure gate",
    layer = lkFunctional,
    entry = "src/gate/runners/procedure_gate",
    stages = @[skManual],
    filesPattern = "src/|src/semantic_proofs|tests/|lakefile|lean-toolchain|axiom.nimble|config.nims",
    passFilenames = false,
    weight = wkLight,
    category = ckPolicy,
    severity = svWarn,
    executionMode = emInterpreted
  ),
  initTopologyEntry(
    id = "proof-universe-lock-gate",
    name = "Axiom proof universe lock gate",
    layer = lkFunctional,
    entry = "src/gate/runners/proof_universe_lock_gate",
    stages = @[skManual],
    passFilenames = false,
    weight = wkMedium,
    category = ckTheorem,
    after = @["nim-check"],
    severity = svError,
    executionMode = emInterpreted
  ),
  initTopologyEntry(
    id = "quality-gate-runner",
    name = "Axiom quality gate runner",
    layer = lkFunctional,
    entry = "src/gate/runners/quality_gate_runner",
    stages = @[skManual],
    filesPattern = "src/",
    passFilenames = true,
    weight = wkMedium,
    category = ckRule,
    severity = svError,
    executionMode = emInterpreted
  ),
  initTopologyEntry(
    id = "readiness-start-gate",
    name = "Axiom readiness start gate (productization E2E + readiness evaluator)",
    layer = lkFunctional,
    entry = "src/gate/runners/readiness_start_gate",
    stages = @[skManual],
    filesPattern = "tests/gateway/|tools/readiness_evaluator.nim|src/core/utils/decision_algebra.nim|config/readiness_policy.json|data/readiness/|src/gate/runners/readiness_start_gate.nim",
    passFilenames = false,
    weight = wkHeavy,
    category = ckValidation,
    severity = svError,
    alwaysRun = true
  ),
  initTopologyEntry(
    id = "release-version-gate",
    name = "Release Version Gate",
    layer = lkFunctional,
    entry = "src/gate/runners/release_version_gate",
    stages = @[skManual],
    passFilenames = false,
    weight = wkMedium,
    category = ckPolicy,
    severity = svError,
    alwaysRun = true,
    tier = 1,
    argsTemplate = @["$repoRoot"],
    executionMode = emInterpreted
  ),
  initTopologyEntry(
    id = "reliability-gate",
    name = "Reliability gate",
    layer = lkFunctional,
    entry = "src/gate/runners/reliability_gate",
    stages = @[skManual],
    filesPattern = "src/",
    passFilenames = false,
    weight = wkMedium,
    category = ckRule,
    severity = svError,
    executionMode = emInterpreted
  ),
  initTopologyEntry(
    id = "sorry-audit-gate",
    name = "Axiom sorry audit gate",
    layer = lkFunctional,
    entry = "src/gate/runners/sorry_audit_gate",
    stages = @[skManual],
    filesPattern = "proofs/.*\\.lean$",
    passFilenames = true,
    weight = wkMedium,
    category = ckTheorem,
    # DEBT#493: sorry_audit_gate reads its repoRoot from paramStr(1); without a
    # template the delivered file tokens landed on argv[1] and were consumed as
    # the scan root. The runner ignores trailing tokens by design.
    argsTemplate = @["$repoRoot"],
    tier = 1,
    severity = svError
  ),
  initTopologyEntry(
    id = "spec-binding-gate",
    name = "Axiom spec binding gate",
    layer = lkFunctional,
    entry = "src/gate/runners/spec_binding_gate.nim",
    stages = @[skManual],
    filesPattern = "src/cli/|tests/features/",
    passFilenames = false,
    weight = wkLight,
    category = ckPolicy,
    severity = svError
  ),
  initTopologyEntry(
    id = "spec-presence-gate",
    name = "Axiom spec presence gate",
    layer = lkFunctional,
    entry = "src/gate/runners/spec_presence_gate.nim",
    stages = @[skManual],
    filesPattern = "src/**",
    passFilenames = false,
    weight = wkLight,
    category = ckPolicy,
    severity = svError
  ),
  initTopologyEntry(
    id = "stale-cert-gate",
    name = "Stale certificate pre-commit gate",
    layer = lkFunctional,
    entry = "tools/stale_cert_gate",
    # Orphan Gate Authority Closure (2026-10-08): live dispatch is the direct
    # .githooks/pre-commit Part 4 invocation (line 112); the ci-stage claim was
    # orphaned by the ci.yml retirement (fa069d610).
    stages = @[skPreCommit],
    filesPattern = "src/verification/certificates/|src/",
    passFilenames = false,
    weight = wkLight,
    category = ckRule,
    severity = svError
  ),
  initTopologyEntry(
    id = "baseline-migration-gate",
    name = "Baseline transition gate (migration-aware classifier)",
    layer = lkFunctional,
    entry = "src/gate/runners/baseline_migration_gate",
    stages = @[skManual],
    filesPattern = "data/|src/",
    passFilenames = false,
    weight = wkLight,
    category = ckRule,
    severity = svError
  ),
  initTopologyEntry(
    id = "static-analyzer",
    name = "Consolidated static analyzer (Track B)",
    layer = lkFunctional,
    entry = "tools/static_analyzer",
    stages = @[skManual],
    filesPattern = "src/",
    passFilenames = false,
    weight = wkMedium,
    category = ckPolicy,
    severity = svError
  ),
  initTopologyEntry(
    id = "tcb-coverage-gate",
    name = "Axiom TCB coverage gate",
    layer = lkFunctional,
    entry = "tools/ci/tcb_coverage_gate",
    stages = @[skManual],
    filesPattern = "src/core/trusted/",
    passFilenames = false,
    weight = wkMedium,
    category = ckTheorem,
    argsTemplate = @["$repoRoot"],
    severity = svWarn
  ),
  initTopologyEntry(
    id = "test-coverage-gate",
    name = "Axiom test coverage gate",
    layer = lkFunctional,
    entry = "src/gate/runners/test_coverage_gate.nim",
    stages = @[skManual],
    filesPattern = "src/**",
    passFilenames = false,
    weight = wkLight,
    category = ckRule,
    severity = svError
  ),
  initTopologyEntry(
    id = "unstaged-guard",
    name = "Axiom unstaged guard",
    layer = lkMeta,
    entry = "src/gate/runners/unstaged_guard",
    stages = @[skManual],
    passFilenames = false,
    weight = wkLight,
    category = ckRule,
    severity = svError
  ),
  initTopologyEntry(
    id = "verification-auditor",
    name = "Axiom verification auditor gate",
    layer = lkFunctional,
    entry = "src/gate/runners/verification_auditor_gate.nim",
    stages = @[skManual],
    filesPattern = "src/",
    passFilenames = false,
    weight = wkMedium,
    category = ckTheorem,
    argsTemplate = @["$repoRoot", "$mode", "$maxJobs"],
    after = @["nim-check"],
    severity = svError,
    alwaysRun = true
  ),
  initTopologyEntry(
    id = "trust-commit-scope",
    name = "Trust Commit direct-write scope gate",
    layer = lkFunctional,
    entry = "src/gate/runners/trust_commit_scope_gate",
    stages = @[skManual],
    passFilenames = false,
    weight = wkLight,
    category = ckRule,
    severity = svError
  )
]

## GateEnablement is the single home for every gate-enablement decision.
## Listing an id is the act of disabling it; every other topology id is
## implicitly enabled, so the table records deviations rather than restating
## the topology. `config/gates.json` is a pure projection of TopologySpec and
## this table, generated by tools/sync_topology.nim — it must not be hand-edited.
const GateEnablement* = {
  # static-analyzer (DEBT#426): exits 1 on any finding with no threshold,
  # baseline or whitelist policy, so enabling it blocks every CI run until
  # the analyzer policy decision lands.
  "static-analyzer": false,
  "golden-master-gate": false,
  "unstaged-guard": false,
}.toTable
