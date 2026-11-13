# Axiom-core Local CI Pipeline
# GitHub Actions 대신 로컬에서 프로젝트 무결성을 보호하는 Self-Defending Code 파이프라인.
# 사용법: make local-ci

SHELL := /bin/bash
NIM ?= nim

# Gateway/부트스트랩 실행 코드는 ci/checker.mk (Tier C closure 멤버)가 단일
# 정의점이다 — runner-pool-acceptance.yml이 H에서 실행하는 make 타깃과 동일
# 정의를 로컬도 사용한다 (self-contained: make -f ci/checker.mk <target>).
include ci/checker.mk
NIMBLE := $(HOME)/.nimble/bin/nimble

NIMBLE_PKGS := $(HOME)/.nimble/pkgs2
CHECKSUMS_PATH := $(wildcard $(NIMBLE_PKGS)/checksums-*)
FUSION_PATH := $(wildcard $(NIMBLE_PKGS)/fusion-*)
# Resolve the toolchain ROOT (must contain compiler/*.nim for kernel builds
# importing compiler/[ast, idents]). `which nim` can point at the choosenim
# shim in ~/.nimble/bin whose parent has no compiler/ — observed on the CX23
# ephemeral runner — so prefer the canonical choosenim toolchain when present.
NIM_TOOLCHAIN_ROOT := $(if $(wildcard $(HOME)/.choosenim/toolchains/nim-2.2.10/compiler/ast.nim),$(HOME)/.choosenim/toolchains/nim-2.2.10,$(patsubst %/bin/nim,%,$(shell which nim 2>/dev/null || echo $(HOME)/.choosenim/toolchains/nim-2.2.10/bin/nim)))
NIM_TOOL_FLAGS := --hints:off --skipParentCfg --skipProjCfg --nimcache:build/nimcache/tools --path:$(NIM_TOOLCHAIN_ROOT) --path:. --path:src --path:tools --path:$(CHECKSUMS_PATH) --path:$(FUSION_PATH)

# CI 환경 변수 자동 감지 ($$CI 이스케이프)
IS_CI := $(shell if [ "$$CI" = "true" ]; then echo "true"; else echo "false"; fi)

# ── Φ2: Theater/vacuity/doc-sync check targets wired into verify-all ──────────
# check-mutation was removed: it required tests/mutation/lean/ fixtures that do
# not exist (broken, orphaned target). Superseded by check-mutation-harness
# (wraps tools/mutation_harness.sh, injects fake theater + expects scanner
# failure). Note: the old comment misattributed this to DEBT#404, which actually
# tracks the static_gate_scanner.nim <50-line TCB claim — unrelated, already
# closed as FIXED; the dead gate had no real registry entry.
CHECK_THEATER_TARGETS := check-nim-theater check-lean-vacuity check-vacuity-simple doc-path-validator
# ── Gate taxonomy (verification contract, not runtime) ─────────────────────
# F = fast local sanity   S = structural/invariant   R = full/release
GATES_FAST    := check-determinism env-check check-imports check-debt check-nim-theater \
                 check-proof-unit-consistency check-proof-unit-reconcile check-epoch-transaction \
                 validate-root-layout
GATES_STATIC  := check-arch check-mcp doc-path-validator check-decision-binding \
                 check-topology-drift check-decision-graph-drift \
                 check-manifest-consistency check-cert-manifest-drift \
                 check-cert-integrity check-cert-integrity-fast check-scope-consistency \
                 check-merge-admission-cert-mirror \
                 check-layer-enforcement check-layer-negative
GATES_FULL    := check-lean-vacuity check-vacuity-simple
# ── Pre-push static admissibility subset (단일 정의점) ─────────────────────
# push 대상 OID snapshot에서 실행되는 정적 게이트. push-admissibility: 레시피가
# 이 변수를 실행 소비(단, thin target은 prebuilt symlink를 직접 사용)하므로,
# 변수 갱신 시 레시피 실행 순서와 check-push-admissibility-integrity를 함께 맞춘다.
# check-repository-surface는 push-context 전용 게이트(origin/main merge-base 필요,
# d6520d04c 2026-09-21 도입)라 GATES_FAST/STATIC/FULL 유니버스 밖에 있으며
# integrity check가 명시적으로 수용한다.
# check-git-access (2026-09-24, L3 depth-1)도 push-context 전용 — CI 실행 클로저
# (run 블록 + 해석 가능 스크립트)의 history/parent git 접근 grep 스캔. ~수십 ms.
# check-monitor-purity (2026-10-05)도 push-context 전용 — PR-landing 관측 표면
# (merge_admission_observation.md + merge_ruleset_drift_monitor.nim +
# ci-watch/SKILL.md)의 GitHub mutation 동사 grep 스캔. Tier 0 강화일 뿐 보안
# 경계가 아니다(호출 토큰의 실제 권한까지는 강제 불가 — GitHub가 request
# method를 감사하지 않음). ~수십 ms.
# Measured 2026-08-29 (snapshot/warm, dev host): 총 ~22-27s (debt 지배적 21-26s).
PUSH_ADMISSIBILITY_GATES := check-debt check-nim-theater doc-path-validator check-determinism check-proof-unit-consistency check-proof-unit-reconcile check-repository-surface check-git-access check-monitor-purity check-workflow-shell-syntax check-epoch-transaction check-merge-admission-cert-mirror check-layer-enforcement check-layer-negative validate-root-layout
# ── Test suite (별도 축 — gate taxonomy와 미혼합) ─────────────────────────────────
TESTS_FAST_UNIT := tests/unit/axiom_ir_test.nim tests/unit/ir_to_lean_test.nim \
                  tests/unit/test_debt_events.nim tests/unit/test_debt_pipeline.nim \
                  tests/unit/test_debt_projection.nim tests/unit/smt_sort_test.nim \
                  tests/unit/contract_synthesis_test.nim \
                  tests/unit/safe_parsers_test.nim \
                  tests/unit/ast_to_ir_test.nim tests/unit/feature_manifest_determinism_test.nim \
                  tests/test_ir_generator.nim tests/test_ast_hash_whitespace.nim \
                  tests/test_axiom_ir.nim tests/test_best_effort_pragma.nim \
                  tests/test_gate_macro.nim tests/test_profiler.nim tests/test_state_ledger.nim \
                  tests/unit/test_debt_budget_sync.nim \
                  tests/unit/test_debt_projection_determinism.nim \
                  tests/unit/test_theater_allowlist_structure.nim \
                  tests/unit/test_lane_module_resolution.nim \
                  tests/unit/test_hollow_cas_closure.nim \
                  tests/unit/test_assurance_tier_node_report.nim \
                  tests/unit/test_vkd_determinism.nim \
                  tests/unit/test_certificate_trust_closure.nim \
                  tests/unit/wf_runners_exit_code_test.nim \
                  tests/unit/resolve_node_outcome_test.nim \
                  tests/unit/evidence_propagation_test.nim \
                  tests/unit/candidate_eligibility_test.nim \
                  tests/unit/execution_identity_propagation_test.nim \
                  tests/unit/bundle_digest_test.nim \
                  tests/unit/promotion_semantics_test.nim \
                  tests/unit/certificate_eligibility_test.nim \
                  tests/unit/proof_state_machine_test.nim \
                  tests/verification/test_g6_prove_runtime_vault.nim \
                  tests/verification/test_g6_verify_journal_not_reference.nim \
                  tests/verification/test_g6_runtime_reference_divergence.nim \
                  tests/unit/test_counterexample_replay.nim \
                  tests/unit/test_bug_verdict_projection.nim \
                  tests/unit/test_canonical_projection_paths.nim \
                  tests/unit/test_scope_lock_rust.nim \
                  tests/unit/test_rust_replay_adapter.nim \
                  tests/unit/test_llbc_to_canonical.nim \
                  tests/unit/test_binop_unsigned.nim \
                  tests/unit/test_language_ban_gate.nim \
                  tests/unit/test_release_version_gate.nim \
                  tests/unit/test_rust_guard_attempt.nim


.PHONY: test perf-check bench-cost-probe verify-all meta-gate registry-check env-check doc-path-validator check-determinism check-mutation-harness check-decision-binding check-topology-drift check-decision-graph-drift check-git-purity check-manifest-consistency check-scope-consistency check-proof-unit-consistency check-proof-unit-reconcile check-epoch-transaction check-merge-admission-cert-mirror sloc-verify check-quality-gate local-verify-static local-verify-static-full check-toolchain-pin check-build-state-coherence check-binary-liveness local-verify-contract-exact check-mcp check-cert-integrity check-cert-integrity-fast check-readiness-start check-workflow-shell-syntax promote-assets promote-assets-apply test-fast test-fast-one perf-baseline clean-cache clean-test-cache clean-release-cache build verify-contract verify-contract-unit verify-contract-release-e2e ci-compile ci-bootstrap-cheap test-gateway-identity-gate gate-binaries validate-root-layout

# ── Φ1: Build Metadata Prerequisite ──────────────────────────────────────────
# build_metadata.json must exist before config.nims can staticRead it.
# Generated by tools/build_metadata_generator.nim (standalone, no project config).
METADATA := src/generated/build_metadata.json

$(METADATA): tools/build_metadata_generator.nim config.nims axiom.nimble
	@echo "=== [Φ1] Generating build metadata ==="
	@mkdir -p src/generated
	$(NIM) c $(NIM_TOOL_FLAGS) -o:bin/build_metadata_generator tools/build_metadata_generator.nim
	bin/build_metadata_generator
	@echo "✅ build_metadata.json generated"

help: ## 도움말 표시
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

env-check: ## CI 환경 변수 검증 (pre-flight)
	@echo "=== [Φ0] Environment Variable Check ==="
	@$(NIM) c --hints:off -r src/gate/runners/env_runner.nim
	@echo "✅ Environment variables OK"
	@echo ""

local-ci: env-check check-imports check-mcp check-arch check-debt build test test-vc-pipeline ## 전체 로컬 CI 파이프라인 실행
	@echo ""
	@echo "✅ local-ci PASSED — all checks green"

verify-all: env-check ## AGENTS.md 메타 스펙 동기화 검증
	@echo "=== [Φ2] Running theater/vacuity/doc-sync checks ==="
	@for t in $(CHECK_THEATER_TARGETS); do $(MAKE) $$t || exit 1; done
	$(MAKE) check-arch || exit 1
	$(NIM) check --hints:off tools/meta_spec_gate.nim
	$(NIM) c --hints:off -r tools/meta_spec_gate.nim

.PHONY: registry-check
registry-check:
	$(MAKE) -C tools debt_cli check

check-imports: bin/check_imports_ast ## Import boundary scan (AST-based, parseStmt + nnkImportStmt)
	@echo "=== Import boundary scan ==="
	@bin/check_imports_ast

# Same --depfile gap as DEBT_AUDIT_SRCS below: the stub-only dep let a stale
# bin/nimtry (pre root-write-closure cache path) silently re-create .nimcache/
# at the repo root. Implementation files must force a rebuild.
bin/nimtry: src/gate/nimtry.nim $(wildcard src/gate/nimtry/*.nim)
	$(NIM) c $(NIM_TOOL_FLAGS) -o:$@ $<

bin/purity_check: tools/local_purity_check.nim
	$(NIM) c --hints:off -o:$@ $<

# Mirrors the engine's audit_engine_inputs.manifest input set; Nim lacks --depfile
# (verified), so transitive imports outside src/core/debt are an accepted untracked gap.
DEBT_AUDIT_SRCS := tools/debt_engine.nim $(wildcard src/core/debt/*.nim)

bin/debt_engine: $(DEBT_AUDIT_SRCS)
	$(NIM) c $(NIM_TOOL_FLAGS) -o:$@ $<

bin/check_imports_ast: tools/check_imports_ast.nim
	$(NIM) c $(NIM_TOOL_FLAGS) -o:$@ $<

bin/check_debt_sync: tools/check_debt_sync.nim
	$(NIM) c $(NIM_TOOL_FLAGS) -o:$@ $<

# -d:release is mandatory: in dev builds the reduction ratchet downgrades a
# violation to WARN (debt_integrity_gate.nim:301-303), which would let a
# baseline regression pass as green — exactly the theater this gate exists
# to forbid. CI runs the binary unconditionally after this target.
bin/debt_integrity_gate: src/gate/runners/debt_integrity_gate.nim \
                         src/core/debt/debt_integrity.nim \
                         src/gate/lib/debt_scanner.nim
	$(NIM) c $(NIM_TOOL_FLAGS) -d:release -o:$@ $<

bin/layer_enforcement_gate: src/gate/runners/layer_enforcement_gate.nim \
                            src/core/trusted/layer_rules.nim \
                            src/core/trusted/layer_enforcement.nim \
                            src/core/trusted/layer_declaration.nim
	$(NIM) c $(NIM_TOOL_FLAGS) -o:$@ $<

check-layer-enforcement: bin/layer_enforcement_gate ## Layer import boundary — closed universe, fail-closed (DEBT#287)
	@AXIOM_ROOT="$(CURDIR)" bin/layer_enforcement_gate --strict

# DEBT#287 liveness harness: the gate must FAIL closed on both negative
# fixtures (unknown layer + forbidden import). A PASS here is fail-open
# regression — the gate enforcing nothing while reporting green.
check-layer-negative: bin/layer_enforcement_gate ## DEBT#287 negative fixtures must deterministically FAIL (anti-theater liveness)
	@out=$$(AXIOM_ROOT="$(CURDIR)/tests/negative/layer_gate/unknown_layer" bin/layer_enforcement_gate --strict 2>&1); rc=$$?; \
	if [ $$rc -eq 0 ]; then \
	  echo "[check-layer-negative] FAIL: unknown_layer fixture PASSED (fail-open!)"; echo "$$out"; exit 1; \
	fi; \
	echo "$$out" | grep -q "unclassified layer (fail-closed, DEBT#287): no inferLayer rule matches this path (unregistered prefix 'src/mystery/')" || { \
	  echo "[check-layer-negative] FAIL: unknown_layer failed without the unknown-layer verdict"; echo "$$out"; exit 1; }; \
	echo "[check-layer-negative] unknown_layer: deterministic FAIL (rc=$$rc)"; \
	out=$$(AXIOM_ROOT="$(CURDIR)/tests/negative/layer_gate/forbidden_import" bin/layer_enforcement_gate --strict 2>&1); rc=$$?; \
	if [ $$rc -eq 0 ]; then \
	  echo "[check-layer-negative] FAIL: forbidden_import fixture PASSED (fail-open!)"; echo "$$out"; exit 1; \
	fi; \
	echo "$$out" | grep -q "imports 'mcp/tools' (mcp from domain) — denied by rule src/core/ (forbidden prefix 'mcp/')" || { \
	  echo "[check-layer-negative] FAIL: forbidden_import failed without the forbidden-import verdict"; echo "$$out"; exit 1; }; \
	echo "[check-layer-negative] forbidden_import: deterministic FAIL (rc=$$rc)"; \
	out=$$(AXIOM_ROOT="$(CURDIR)/tests/negative/layer_gate/forbidden_verification" bin/layer_enforcement_gate --strict 2>&1); rc=$$?; \
	if [ $$rc -eq 0 ]; then echo "[check-layer-negative] FAIL: forbidden_verification PASSED (fail-open!)"; echo "$$out"; exit 1; fi; \
	echo "$$out" | grep -q "imports 'verification/admissibility' (infrastructure from domain) — denied by rule src/core/ (forbidden prefix 'verification/')" || { \
	  echo "[check-layer-negative] FAIL: forbidden_verification failed without the exact verdict"; echo "$$out"; exit 1; }; \
	echo "[check-layer-negative] forbidden_verification: deterministic FAIL (rc=$$rc)"; \
	out=$$(AXIOM_ROOT="$(CURDIR)/tests/negative/layer_gate/forbidden_ui" bin/layer_enforcement_gate --strict 2>&1); rc=$$?; \
	if [ $$rc -eq 0 ]; then echo "[check-layer-negative] FAIL: forbidden_ui PASSED (fail-open!)"; echo "$$out"; exit 1; fi; \
	echo "$$out" | grep -q "imports 'ui/notion_semantic_mapper' (presentation from domain) — denied by rule src/core/ (forbidden prefix 'ui/')" || { \
	  echo "[check-layer-negative] FAIL: forbidden_ui failed without the exact verdict"; echo "$$out"; exit 1; }; \
	echo "[check-layer-negative] forbidden_ui: deterministic FAIL (rc=$$rc)"; \
	out=$$(AXIOM_ROOT="$(CURDIR)/tests/negative/layer_gate/allowed_import" bin/layer_enforcement_gate --strict 2>&1); rc=$$?; \
	if [ $$rc -ne 0 ]; then echo "[check-layer-negative] FAIL: allowed_import blocked (over-blocking)"; echo "$$out"; exit 1; fi; \
	echo "[check-layer-negative] allowed_import: PASS (rc=$$rc) — legal core/ dependency not over-blocked"; \
	out=$$(AXIOM_ROOT="$(CURDIR)/tests/negative/layer_gate/approved_pair" bin/layer_enforcement_gate --strict 2>&1); rc=$$?; \
	if [ $$rc -ne 0 ]; then echo "[check-layer-negative] FAIL: approved_pair blocked (approved (file,target) pair must be honored)"; echo "$$out"; exit 1; fi; \
	echo "[check-layer-negative] approved_pair: PASS (rc=$$rc) — approved (file, target) pair honored"; \
	out=$$(AXIOM_ROOT="$(CURDIR)/tests/negative/layer_gate/approved_pair_new_target" bin/layer_enforcement_gate --strict 2>&1); rc=$$?; \
	if [ $$rc -eq 0 ]; then echo "[check-layer-negative] FAIL: approved_pair_new_target PASSED (per-FILE whitelist regression — DEBT#495)"; echo "$$out"; exit 1; fi; \
	echo "$$out" | grep -q "imports 'verification/admissibility' (infrastructure from domain) — denied by rule src/core/ (forbidden prefix 'verification/')" || { \
	  echo "[check-layer-negative] FAIL: approved_pair_new_target failed without the exact verdict"; echo "$$out"; exit 1; }; \
	echo "[check-layer-negative] approved_pair_new_target: deterministic FAIL (rc=$$rc) — a whitelisted file CANNOT add a new forbidden target"

check-arch: bin/nimtry ## 아키텍처 위반 검사 (nimtry v2 fingerprint gate — exit-code gated)
	@echo "=== [2/4] Architecture Violation Check ==="
	@if [ -f bin/nimtry ]; then \
		OUT=$$(bin/nimtry src/ 2>&1); \
		RC=$$?; \
		if [ "$$RC" -ne 0 ]; then \
			echo "❌ Architecture check FAILED (nimtry exit $$RC):"; \
			echo "$$OUT" | awk 'NF' || true; \
			exit 1; \
		fi; \
		echo "✅ No architecture violations"; \
	else \
		echo "❌ bin/nimtry not found — architecture check REQUIRED"; \
		exit 1; \
	fi
	@echo ""

check-mcp: ## MCP module compile check
	$(NIM) check --hints:off src/mcp/tools.nim

check-debt: bin/debt_engine ## Debt synchronization validator
	@echo "=== Debt synchronization validator ==="
	@bin/debt_engine --validate

audit-dir-doc: bin/debt_engine ## Directory/documentation debt audit (deterministic)
	@bin/debt_engine --audit-dir-doc

# ── Verify-static parity gates ────────────────────────────────────────────────
# Shared 3-pin core of the two toolchain gates — single definition point.
# check-determinism consumes it for verify-static parity; check-toolchain-pin
# consumes it as the documented read-only substitute for CI's destructive
# reset (docs/spec/verify_static_exact_contract.md — behavior-preserving).
define TOOLCHAIN_PIN_CORE
@nim --version | grep 2.2.10
@z3 --version | grep 4.13.3
@lean --version | grep 4.33.0
endef

check-determinism: ## Toolchain pin verification (nim/z3/lean/git greps; NEVER reset/clean)
	@echo "=== [check-determinism] toolchain pin verification ==="
	@$(TOOLCHAIN_PIN_CORE)
	# git floor mirrors assertGitCapability in merge_materializer.nim (runtime authority)
	@git --version | grep -E 'git version 2\.(4[0-9]|[5-9][0-9])\.'
	@echo "Toolchain pins OK"

# static_gate_scanner.nim requires every file in config/gates.manifest.toml to
# exist at compile time (error() at static_gate_scanner.nim:91-93). The manifest
# lists gate-self-check -> bin/gate_self_check (config/gates.manifest.toml:105-106),
# which is gitignored and absent in a fresh tree; if missing the scanner fails for
# the wrong (vacuous) reason. Single-gate AOT compile, matching the repo gate-build
# convention (Makefile:358-359). The harness also fail-closes on this independently.
bin/gate_self_check: src/gate/runners/gate_self_check.nim
	$(NIM) c $(NIM_TOOL_FLAGS) -o:$@ $<

check-mutation-harness: bin/gate_self_check ## Mutation harness (wraps tools/mutation_harness.sh)
	@echo "=== [check-mutation-harness] mutation harness ==="
	@./tools/mutation_harness.sh

check-decision-binding: ## Decision binding audit (hermetic_build --check-decision-bindings)
	@echo "=== [check-decision-binding] decision binding audit ==="
	@nim c --hints:off -o:bin/hermetic_build tools/hermetic_build.nim
	@bin/hermetic_build --check-decision-bindings --escalation-threshold 30

check-topology-drift: ## Topology drift guard (regenerates + git diff --exit-code)
	@echo "=== [check-topology-drift] topology drift guard ==="
	@nim c --hints:off -o:bin/sync_topology tools/sync_topology.nim
	@bin/sync_topology
	@if git diff --exit-code -- src/gate/manifest.d/*.json src/generated/manifest_registry.nim src/generated/gate_registry.nim src/generated/helper_registry.nim config/gates.manifest.toml; then \
		echo "OK -- all generated files in sync"; \
	else \
		echo "ERROR: generated files drifted from topology_spec.nim SSOT"; \
		exit 1; \
	fi

check-decision-graph-drift: ## Decision graph drift guard (sync_decisions)
	@echo "=== [check-decision-graph-drift] decision graph drift guard ==="
	@nim c --hints:off -o:bin/sync_decisions tools/sync_decisions.nim
	@bin/sync_decisions --ci-drift-check

check-cert-manifest-drift: ## Certificate manifest drift guard (sync_certs)
	@echo "=== [check-cert-manifest-drift] certificate manifest drift guard ==="
	@nim c --hints:off -o:bin/sync_certs tools/sync_certs.nim
	@bin/sync_certs --ci-drift-check

check-cert-integrity: ## Certificate integrity gate (full mode — all certs vs manifest)
	@echo "=== [check-cert-integrity] certificate integrity gate (full) ==="
	@nim c --hints:off -o:bin/cert_integrity_gate tools/cert_integrity_gate.nim
	@bin/cert_integrity_gate --mode full

check-cert-integrity-fast: ## Certificate integrity gate (fast mode — changed certs only)
	@echo "=== [check-cert-integrity-fast] certificate integrity gate (fast) ==="
	@nim c --hints:off -o:bin/cert_integrity_gate tools/cert_integrity_gate.nim
	@bin/cert_integrity_gate --mode fast

promote-assets: bin/promote_assets ## Asset promotion (staging → validated → atomic canonical)
	@echo "=== [promote-assets] AssetPromotionBoundary (Intent Delta inspection) ==="
	@bin/promote_assets --intent promotion_intent.json

promote-assets-apply: bin/promote_assets ## Asset promotion, apply to canonical
	@echo "=== [promote-assets-apply] AssetPromotionBoundary (apply) ==="
	@bin/promote_assets --intent promotion_intent.json --apply

bin/promote_assets: tools/promote_assets.nim src/shared_types/io_bridge.nim
	@nim c --hints:off -o:bin/promote_assets tools/promote_assets.nim

check-git-purity: ## Git tree purity (read-only; blanket 0-diff — build_env.nim untracked+gitignored)
	@echo "=== [check-git-purity] git tree purity (read-only) ==="
	@if git status --porcelain | grep -q .; then \
		echo "FAIL -- working tree is dirty:"; \
		git status --porcelain; \
		exit 1; \
	else \
		echo "OK -- tree clean"; \
	fi

check-manifest-consistency: ## Manifest consistency gate (SSOT-driven, Check 6)
	$(NIM) c $(NIM_TOOL_FLAGS) -o:bin/manifest_consistency_gate src/gate/runners/manifest_consistency_gate.nim
	bin/manifest_consistency_gate

check-scope-consistency: ## Scope consistency gate (deriveKernelScope == lock, fail-closed)
	@# Preflight: rebuild bin/ax if source tree hash is stale (no runtime self-rebuild).
	@bin/hermetic_build --check-source-hash >/dev/null 2>&1 || $(NIM) c --hints:off --warnings:off -o:bin/ax src/cli/main.nim
	bin/ax scope

bin/proof_unit_consistency_gate: tools/ci/proof_unit_consistency_gate.nim src/gate/proof_unit_catalog.nim
	$(NIM) c $(NIM_TOOL_FLAGS) -o:$@ $<

check-proof-unit-consistency: bin/proof_unit_consistency_gate ## A0′ consistency gate (W-axis single-authority drift guard; fail-closed)
	@echo "=== [check-proof-unit-consistency] A0′ consistency gate ==="
	@bin/proof_unit_consistency_gate
	@echo "✅ A0′ consistency gate PASS — catalog/selector/oracle/docs/manifest aligned"

bin/proof_reconcile_gate: tools/ci/proof_reconcile_gate.nim src/gate/proof_unit_catalog.nim
	$(NIM) c $(NIM_TOOL_FLAGS) -o:$@ $<

check-proof-unit-reconcile: bin/proof_reconcile_gate ## A3 reconcile gate static self-check (catalog↔A3 projection invariant; fail-closed)
	@echo "=== [check-proof-unit-reconcile] A3 projection invariant (static) ==="
	@bin/proof_reconcile_gate
	@echo "✅ A3 reconcile gate static PASS — W2↔ci-bootstrap / W8↔gateway-shard projection aligned"

bin/epoch_transaction_gate: tools/ci/epoch_transaction_gate.nim src/gate/slice_catalog.nim
	$(NIM) c $(NIM_TOOL_FLAGS) -o:$@ $<

bin/merge_admission_cert_mirror_gate: tools/ci/merge_admission_cert_mirror_gate.nim
	$(NIM) c $(NIM_TOOL_FLAGS) -o:$@ $<

check-merge-admission-cert-mirror: bin/merge_admission_cert_mirror_gate ## certRequired + vaultCertRequired mirror consistency gate (policy SSOT ↔ merge_cli.nim compile-time constants; fail-closed)
	@echo "=== [check-merge-admission-cert-mirror] certRequired/vaultCertRequired policy↔predicate mirrors ==="
	@bin/merge_admission_cert_mirror_gate
	@echo "✅ certRequired/vaultCertRequired mirror gate PASS — config/policy/merge_admission.json and src/cli/merge_cli.nim agree"

check-epoch-transaction: bin/epoch_transaction_gate ## Epoch 4-way binding gate (S0-c: SliceCatalog+EpochManifest+Engine+Pin; fail-closed)
	@echo "=== [check-epoch-transaction] epoch promotion transaction 4-way binding ==="
	@if [ -f config/policy/epoch_manifest.json ]; then \
		mb=$$(git merge-base origin/main HEAD 2>/dev/null); \
		if [ -n "$$mb" ]; then \
			bin/epoch_transaction_gate --diff "$$mb" HEAD; \
		else \
			echo "[check-epoch-transaction] origin/main merge-base unavailable — static self-check only"; \
			bin/epoch_transaction_gate; \
		fi \
	else \
		echo "[check-epoch-transaction] SKIP (loud): config/policy/epoch_manifest.json absent from this OID — pre-introduction snapshot; the 4-way binding invariant applies from its introducing commit onward"; \
	fi
	@echo "✅ epoch transaction gate PASS — catalog/manifest/engine/pin aligned (4-way)"

bin/core_purity_gate: tools/ci/core_purity_gate.nim data/core_purity_baseline.json
	$(NIM) c $(NIM_TOOL_FLAGS) -o:$@ $<

check-core-purity: bin/core_purity_gate ## Core purity ratchet (src/core side effects + effect-system escapes; baseline-anchored, fail-closed)
	@echo "=== [check-core-purity] core purity ratchet ==="
	@bin/core_purity_gate --check
	@echo "✅ core purity gate PASS — no new unapproved side effect in src/core"

check-quality-gate: ## Quality gate (SSOT-driven, staged-file AST scan)
	$(NIM) c $(NIM_TOOL_FLAGS) -o:bin/quality_gate_runner src/gate/runners/quality_gate_runner.nim
	@CHANGED="$$(git diff HEAD --name-only --diff-filter=ACMR -- '*.nim' | tr '\n' ',' | sed 's/,$$//')"; \
	if [ -n "$$CHANGED" ]; then \
		echo "[quality-gate] checking changed files: $$CHANGED"; \
		bin/quality_gate_runner --files "$$CHANGED"; \
	else \
		echo "[quality-gate] SKIP -- no changed Nim files (incremental gate, no-op)"; \
	fi

validate-root-layout: ## Filesystem Contract V2 root manifest validation + test battery (docs/spec/filesystem_contract.md)
	$(NIM) c --hints:off -o:bin/validate_root_manifest tools/ci/validate_root_manifest.nim
	bin/validate_root_manifest
	$(NIM) c --hints:off -o:build/validate_root_manifest_test tools/tests/validate_root_manifest_test.nim
	AXIOM_PROJECT_ROOT=$(CURDIR) build/validate_root_manifest_test
	@echo "✅ validate-root-layout PASS — filesystem contract honored (validator + tests)"

# Aggregate verify-static parity targets (CI-identical ORDER; purity MUST be last)
sloc-verify: ## SLOC governance verify (Ratified Manifest ⊆ policy; sibling gate, not called by test/local-verify-static)
	$(NIM) c --hints:off -o:bin/sloc_verify tools/sloc_verify.nim
	bin/sloc_verify
	@echo "✅ sloc-verify PASS — governance contract honored"

local-verify-static: $(GATES_FAST) $(GATES_STATIC) ## 16 non-intrusive verify-static gates (in-place safe)
	@echo "✅ local-verify-static PASSED — 16 gates green"

local-verify-static-full: $(GATES_FAST) $(GATES_STATIC) $(GATES_FULL) check-mutation-harness check-git-purity ## All 18 verify-static gates (worktree-only: mutation + purity)
	@echo "✅ local-verify-static-full PASSED — 18 gates green"

# ── P3: Runtime preflight contracts ──────────────────────────────────
# Two independent substrate contracts; must NOT be merged into one target.

# Contract A: build state coherence — bin/ax is NOT executed.
# Compares the embedded BuildSourceHash in src/generated/build_env.nim
# against a live recomputation of the src/ tree hash.
# Mismatch → fail-closed exit 1 signals BLOCKED_BY_BUILD_STATE_COHERENCE.
# 판정은 PASS/FAIL; exit 1이면 타깃 실패.
check-build-state-coherence: ## Runtime preflight A: build state coherence (bin/ax 미실행)
	@bin/hermetic_build --check-source-hash

# Contract B: binary liveness — contract A must pass first.
# Verifies that bin/ax is executable and terminates within 120s.
# 계약은 '필수 command가 종료한다'이며 timeout 수치는 검사 수단.
# BLOCKED_BY_BINARY_LIVENESS failureReason 문자열 + exit 1로 표현.
check-binary-liveness: ## Runtime preflight B: binary liveness (계약 A 통과 후에만 유효)
	@test -x bin/ax || { echo "BLOCKED_BY_BINARY_LIVENESS: bin/ax not executable"; exit 1; }
	@timeout 120 bin/ax --version >/dev/null; rc=$$?; \
	if [ "$$rc" -eq 124 ]; then echo "BLOCKED_BY_BINARY_LIVENESS: bin/ax --version did not terminate within 120s"; exit 1; \
	elif [ "$$rc" -ne 0 ]; then echo "BLOCKED_BY_BINARY_LIVENESS: bin/ax --version exit=$$rc"; exit 1; \
	else echo "binary liveness OK"; fi

# ── P4: LocalExact for verify-contract ──────────────────────────────
# CI-identical local gate: reproduces verify-contract with the same
# substrate preflight and toolchain verification as the CI pipeline.
local-verify-contract-exact: ## LocalExact for verify-contract (CI-identical local gate)
	$(MAKE) check-build-state-coherence
	$(MAKE) check-binary-liveness
	$(MAKE) check-toolchain-pin
	$(MAKE) verify-contract

# Non-destructive toolchain pin verification — substitutes for CI's destructive
# `git clean -ffdx` determinism guard (ci.yml line 70) with a read-only grep approach.
# FAILS if any tool version mismatches the pinned version, without touching the worktree.
check-toolchain-pin:
	@echo "=== [check-toolchain-pin] toolchain version verification ==="
	@$(TOOLCHAIN_PIN_CORE)
	@echo "Toolchain pins OK"

# ── Phase 1: push-admissibility thin target + integrity ───────────────────
# Thin target executed in snapshot CWD (make -C <snapshot> push-admissibility).
# Uses prebuilt symlinks directly — no per-gate recompilation (Phase 0 measurement basis).
# PUSH_ADMISSIBILITY_GATES is the single definition point; thin target and integrity check consume it.
#
# check-debt skip predicate (sound input-set scoping): the debt engine's
# verdict-relevant input set is exactly (a) every `file` in
# data/architecture_debt.json (content re-hashed), (b) every `files[]` path of
# open/deferred debt_registry.json entries (W7 live-file EXISTENCE check;
# `:NN` line annotations stripped, dir-prefixed inputs match by prefix), and
# (c) the fixed sync/projection/policy files enumerated below. Part D budget
# metrics are advisory (DRIFT never affects the exit code), so their scan
# inputs are excluded. Skip ONLY when the branch diff (merge-base..HEAD) is
# disjoint from that set; ANY error (git, JSON, python) exits 1 = run the
# gate — fail-safe direction is always to do the work. check-debt itself and
# its GATES_FAST/local-ci uses remain UNCONDITIONAL.
# [skip] effect_violations 해소: pre-push 스냅샷은 현재 Makefile을 복사해 실행하므로
# (.githooks/pre-push "Ensure snapshot has the current Makefile"), 이 선행조건이
# 스냅샷 CWD의 bin/에 평가자를 스테이징한다 — 훅의 symlink 목록은 FROZEN이므로
# 스냅샷 폐쇄는 여기서 닫힌다. check-debt → bin/debt_engine --validate Part D가 사용.
# bin/nimtry도 동일 폐쇄: debt_engine nimtry_violations 평가자가 bin/nimtry src/를
# 실행하며, 스냅샷 bin/에 없으면 evaluator error → fail-closed Validation FAILED.
push-admissibility: bin/effect_contract_projection bin/nimtry ## pre-push push-target OID static admissibility (snapshot CWD)
	@echo "=== push-admissibility: snapshot OID gates ==="
	@if printf '%s\n' \
	  'import json, subprocess, sys' \
	  'def die(msg):' \
	  '    print("[check-debt] predicate error: " + msg + " - running full validation (fail-safe)")' \
	  '    sys.exit(1)' \
	  'try:' \
	  '    mb = subprocess.run(["git", "merge-base", "origin/main", "HEAD"], capture_output=True, text=True)' \
	  '    if mb.returncode != 0: die("git merge-base failed")' \
	  '    diff = subprocess.run(["git", "-c", "core.quotePath=false", "diff", "--name-only", "-z", mb.stdout.strip(), "HEAD"], capture_output=True, text=True)' \
	  '    if diff.returncode != 0: die("git diff failed")' \
	  '    ch = set(p for p in diff.stdout.split("\0") if p)' \
	  '    inputs = set()' \
	  '    for e in json.load(open("data/architecture_debt.json")).get("entries", []):' \
	  '        if e.get("file"): inputs.add(e["file"])' \
	  '    for e in json.load(open("data/debt_registry.json")).get("entries", []):' \
	  '        if (e.get("status") or "").lower() not in ("open", "deferred"): continue' \
	  '        for f in e.get("files", []):' \
	  '            b = f.rsplit(":", 1)[0] if (f.count(":") and f.rsplit(":", 1)[1].isdigit()) else f' \
	  '            if b: inputs.add(b)' \
	  '    inputs.update(["data/debt_registry.json", "data/architecture_debt.json", "data/debt_ledger.json", "data/debt_budgets.json", "data/debt_schema.json", "docs/DEBT_REGISTRY.md", "src/generated/debt_constants.nim", "config/policy/policy_dispositions.json", "config/policy/policy_revisions.json"])' \
	  '    inter = sorted(ch.intersection(inputs))' \
	  '    dirhit = sorted(c for c in ch if any(p.endswith("/") and c.startswith(p) for p in inputs))' \
	  '    if not inter and not dirhit:' \
	  '        print("[check-debt] SKIP (loud): branch diff disjoint from debt input set (" + str(len(ch)) + " changed paths, 0 debt inputs) — full validation remains unconditional in GATES_FAST/local-ci")' \
	  '        sys.exit(0)' \
	  '    hits = (inter + [c for c in dirhit if c not in inter])[:3]' \
	  '    print("[check-debt] RUN: branch diff intersects debt input set (" + str(len(ch)) + " changed paths, " + str(len(hits)) + " hit(s): " + ", ".join(hits) + ") — full validation proceeds")' \
	  '    sys.exit(1)' \
	  'except SystemExit:' \
	  '    raise' \
	  'except Exception as exc:' \
	  '    die("exception: " + repr(exc))' \
	  | python3 -; then :; \
	else \
		bin/debt_engine --validate; \
	fi
	@bin/check_nim_theater --allowlist tools/ci/nim_theater_allowlist.json src/ tests/ tools/
	@bin/doc_path_validator
	@bin/proof_unit_consistency_gate
	@bin/proof_reconcile_gate
	@if [ -f config/policy/epoch_manifest.json ]; then \
		bin/epoch_transaction_gate --diff "$$(git merge-base origin/main HEAD)" HEAD; \
	else \
		echo "[check-epoch-transaction] SKIP (loud): epoch manifest absent from this OID — pre-introduction snapshot; the 4-way binding invariant applies from its introducing commit onward"; \
	fi
	@$(MAKE) --no-print-directory check-determinism
	@$(MAKE) --no-print-directory check-repository-surface
	@$(MAKE) --no-print-directory check-git-access
	@$(MAKE) --no-print-directory check-monitor-purity
	@$(MAKE) --no-print-directory check-workflow-shell-syntax
	@$(MAKE) --no-print-directory check-layer-enforcement
	@$(MAKE) --no-print-directory check-layer-negative
	@$(MAKE) --no-print-directory validate-root-layout
	@echo "PASS: $(PUSH_ADMISSIBILITY_GATES) green (snapshot)"

# ── Repository Surface ratchet (advisory adjudication layer) ──────────────
# merge authority는 GitHub다(CODEOWNERS + ruleset required check + merge queue) —
# 이 타깃은 merge 권한을 부여·거부하지 않으며 FAIL이어도 merge를 막지 않는다. 판정은
# merge-base(origin/main, HEAD)의 정책 × 브랜치 diff로 계산하는 조언적 surface 보고
# (base-policy binding)다; snapshot worktree(공유 refs)에서도 동일하게 동작한다.
# base에 정책이 없으면(계약 이전 main에서 떨어진 브랜치) FAIL — ax git sync로 계약
# 이후 main에 재단골 후 push. 미분류 경로는 PRODUCT(defaultClass, v51 · 전 op PASS),
# FROZEN은 열거된 경계에서 ADD/MODIFY/DELETE = FAIL.
check-repository-surface: bin/surface_guard ## Advisory surface report: base policy × branch diff
	@mkdir -p .axiom; \
	mb=$$(git merge-base origin/main HEAD); \
	git show "$$mb:config/repository_surface.json" > .axiom/surface_base_policy.json \
	  || { echo "[surface-gate FAIL] base $$mb 에 정책이 없다 — ax git sync 후 push"; exit 1; }; \
	git diff --name-status "$$mb" HEAD > .axiom/surface_changes.name-status; \
	bin/surface_guard --policy .axiom/surface_base_policy.json --diff .axiom/surface_changes.name-status

bin/surface_guard: tools/surface_guard.nim
	nim c --hints:off -d:release -o:$@ $<

# ── Depth-1 Git invariant (L3 depth-1): clause-1 push gate ─────────────────
# CI 검증 경로(depth-1 checkout: admission-check.yml + certificate-mint.yml)
# 에서 history/parent 객체 접근(grep-class 패턴: HEAD~, ^N, rev-list,
# merge-base, git log, git describe, @{, ...)을 차단한다. 전체 실행 클로저
# 인벤토리를 출력하며(감사 증거 겸용) breakers 발견 시 exit 1 (fail-closed).
# CHEAP: grep-class 스캔, 수십 ms — push-admissibility thin target에 배선.
check-git-access: ## depth-1 git invariant: CI history/parent access scan (grep-class)
	@if [ -f tools/ci/git_access_scan.sh ]; then \
	  bash tools/ci/git_access_scan.sh; \
	else \
	  echo "[check-git-access] SKIP (loud): tools/ci/git_access_scan.sh absent from this OID — pre-L3-d1 snapshot; the clause-1 invariant applies from its introducing commit onward"; \
	fi

# ── PR-landing monitor purity (Tier 0 reinforcement) ────────────────────────
# PR-landing 관측 표면(docs/agents/merge_admission_observation.md +
# tools/merge_ruleset_drift_monitor.nim + .opencode/skills/ci-watch/SKILL.md)에
# GitHub mutation 동사(gh pr merge, -X POST/PUT/PATCH/DELETE,
# enqueue/merge/ruleset/branch-protection mutation 이름)가 없음을 grep 스캔으로
# 강제한다. 런타임 감지는 불가능(GitHub는 request method를 감사하지 않음)하므로
# check-git-access와 동일하게 정적 강제다. monitor의 행위는 관측(GET/GraphQL
# query)뿐 — merge/ruleset authority는 GitHub다. Tier 0 강화: 관측 표면에
# mutation 레시피가 존재하지 않음을 보장할 뿐, 호출 토큰의 실제 권한까지
# 강제하지 않는다(보안 경계 아님). CHEAP: grep-class 스캔, 수십 ms —
# push-admissibility thin target에 배선 (tools/ci/monitor_purity_scan.sh).
check-monitor-purity: ## PR-landing monitor purity: 관측 표면 mutation 동사 scan (grep-class)
	@if [ -f tools/ci/monitor_purity_scan.sh ]; then \
	  bash tools/ci/monitor_purity_scan.sh; \
	else \
	  echo "[check-monitor-purity] SKIP (loud): tools/ci/monitor_purity_scan.sh absent from this OID — pre-introduction snapshot; the monitor-purity invariant applies from its introducing commit onward"; \
	fi

# ── Workflow run-block shell syntax + parse-poison (yml run: scalars) ─────
# 모든 .github/workflows/*.yml의 모든 `run:` 블록을 python3 yaml.safe_load로
# 전수 추출하여 bash -n 문법 검사. fail-closed: 단일 블록 오류(예: missing fi
# → EOF)에도 exit 1 — certificate-mint.yml step (2a) fi EOF 사고 (gate run
# 36250541060) + cmp 파일명 결함 클래스가 생산을 두 번 깨뜨린 것을 영구 차단.
# + 파스 독 룰(2026-10-14): 표현식 토큰 보유 run 스칼라 길이 > 21,000 → FAIL
# (계획 단계 HTTP 422 'Exceeded max expression length 21000' — 0-job·체크런
# 미생산 독; docs/spec/gh_run_observation_quirks.md Q4).
# zero-dep (python3+yaml, bash — 신규 외부 바이너리 없음; actionlint/shellcheck
# 는 prebuilt 바이너리 다운로드라 채택 거부, 도구 헤더에 근거). CHEAP: 수백 ms
# — push-admissibility thin target에 배선 (tools/ci/validate_workflow_shell.sh).
# 룰 셀프테스트: make test-workflow-poison-lint.
check-workflow-shell-syntax: ## workflow run: 블록 전수 bash -n 문법 게이트 (fail-closed)
	@if [ -f tools/ci/validate_workflow_shell.sh ]; then \
	  bash tools/ci/validate_workflow_shell.sh; \
	else \
	  echo "[check-workflow-shell-syntax] SKIP (loud): tools/ci/validate_workflow_shell.sh absent from this OID — pre-introduction snapshot; the run-block syntax invariant applies from its introducing commit onward"; \
	fi

check-push-admissibility-integrity: ## subset ⊆ GATES_FAST∪GATES_STATIC∪GATES_FULL + check-repository-surface/check-git-access/check-monitor-purity/check-workflow-shell-syntax (push-only)
	@ok=1; for g in $(PUSH_ADMISSIBILITY_GATES); do \
	  case " $(GATES_FAST) $(GATES_STATIC) $(GATES_FULL) check-repository-surface check-git-access check-monitor-purity check-workflow-shell-syntax " in *" $$g "*) ;; *) \
	    echo "ERROR: $$g 이(가) 게이트 유니버스(GATES_FAST/STATIC/FULL 또는 push-only surface/git-access/monitor-purity/workflow-shell-syntax)에 없습니다"; ok=0;; esac; \
	done; [ $$ok -eq 1 ] && echo "✅ push-admissibility subset is within the known gate universe (+ push-only surface/git-access/monitor-purity/workflow-shell-syntax)" || exit 1

# ── Productization Contract Preservation (verify-contract canonical gate) ─────
# Phase 0.5 (plan SSOT): make verify-contract = 유일한 canonical local entrypoint
# for Productization Contract Preservation (GO 6조건 회귀 방어).
# ENFORCED = G1 ∧ G2 ∧ G4 ∧ G6 ∧ G7 (G3 = Engineering Guard, G5 = 테스트 배선 미완료 — DEBT#432, 미포함).
# CI는 개별 테스트를 나열하지 않고 run: make verify-contract 단일 호출점을 사용.
#
# D1: verify-contract runs 4 subtargets in PARALLEL via &+wait (not runPool —
# see rationale below).  verify-contract-serial preserves the serial baseline
# for D3 cross-check.
#
# Orchestration choice: tools/process_pool.nim runPool is structurally built
# for "compile N homogeneous modules in parallel" — it takes a single
# buildCmd: proc(module: string): seq[string] and applies it uniformly to a
# seq[string] of modules, appending per-module --nimcache.  It cannot host
# 4 heterogeneous recipes (G1's worktree harness, G4's negative-compile
# shell logic, G7's multi-step e2e, G2's internal loop).  Therefore the
# plan's sanctioned fallback is used: the &+wait pattern proven at
# Makefile:589-606 (test-fast), adapted with per-subtarget exit-code capture
# via status files for fail-closed verdict reporting.
# runPool(90-94행)은 단일 buildCmd proc을 동질 module 배열에 적용하는 구조라 G1(worktree mutation harness)/G4(negative-compile) 같은 이질 recipe를 수용할 수 없어 &+wait를 채택.
# ── verify-contract shared artifact prebuild (DEBT#457) ────────────
# Build once → Freeze → Fan-out: the config/integrity.nims hooks compile
# bin/sync_certs + bin/feature_manifest_generator on EVERY nim c. Parallel
# subtargets relinking them concurrently collide on the shared output path
# (ETXTBSY / Permission denied — nim relinks on every `nim c`, there is no
# binary freshness skip). This prerequisite materializes them exactly once,
# serially, BEFORE fan-out; under AXIOM_VERIFY_CONTRACT_FANOUT=1 the hooks
# then execute the frozen binaries read-only (fail-closed when missing).
# Side effect: the first serial compile also warms hermeticPreBuild artifacts
# (bin/hermetic_build etc.), closing the fresh-checkout parallel build hole.
verify-contract-artifacts: ## serial prebuild of shared contract artifacts (DEBT#457) + release bin/ax seed (DEBT#481)
	$(NIM) c -r --hints:off -d:AXIOM_GATE_BOND=1 -d:skipImportLint --skipUserCfg --out:bin/feature_manifest_generator tools/feature_manifest_generator.nim ensure
	$(NIM) c -r --hints:off -d:AXIOM_GATE_BOND=1 -d:skipImportLint --skipUserCfg --out:bin/sync_certs tools/sync_certs.nim --ensure
	# DEBT#481 residual closure: fan-out 중 bin/ax 작성자를 0으로 만든다. tests/config.nims는
	# 컴파일 시점에 bin/ax 존재를 quit(1) 가드하므로 g2/g6g4는 이 직렬 시드에 의존하고,
	# g7-consume은 시드 직후라 재링크하지 않는다(아래 consume의 freshness skip 참조).
	# g1은 격리 worktree 안에서 빌드하므로 무관하다.
	@if [ -L bin/ax ]; then echo "artifacts: bin/ax is the bootstrap CAS stable entry — seed skipped (A-1)"; else $(NIM) c -d:release --hints:off --nimcache:$(VC_NIMCACHE_g7) -o:bin/ax src/cli/main.nim; fi

# verify-contract fan-out (PRUNE #1 — shared canonical proof artifact): in CI,
# verify-integration runs verify-contract-release-e2e-full (producer, which
# persists logs/verify_contract_e2e_report.json; logs/ax_proof_state.json is
# written by the prove itself) immediately before this target, so g7 consumes
# that canonical result instead of re-running the identical prove — the
# --target normalizeMaxWorkers prove now executes ONCE per CI run. Fail-closed:
# verify-contract-release-e2e-consume falls back to the non-full e2e prove path
# when either artifact is missing (local standalone runs). Duplication record +
# artifact contract: docs/spec/execution_accounting_contract.md §16.
# verify-contract g7 split switch (Slice 3-AF-2): CONTRACT_SKIP_G7=1 drops the
# g7 fan-out line (below) and the g7 entry in the status-verification loop,
# leaving the artifact-free subtargets g2/g1/g6g4 — the parallel
# verify-contract surface. g7-consume STAYS in the serial path (the producer
# workspace): consumption rights require the producer's canonical proof
# artifacts (logs/verify_contract_e2e_report.json + logs/ax_proof_state.json,
# written by the immediately-preceding e2e-full step in the SAME run); in a
# run without them it would silently degrade to the fallback prove path —
# re-running the identical --target normalizeMaxWorkers prove a second time
# (Slice 3-AF-2; artifact contract: docs/spec/execution_accounting_contract.md
# §16). Default 0: unset/0 keeps the historical fan-out byte-for-byte; the
# wait + status-verification + fail-closed (missing .status = FAIL) structure
# is identical in both branches (make-level ifeq, NOT recipe-level — a
# conditional inside the \ -joined fan-out chain is swallowed into the shell
# script, tested 2026-09-17).
CONTRACT_SKIP_G7 ?= 0
# Contract fan-out membership — ONE list drives both the backgrounding and the
# status-verification loop. This block used to be an if/else whose two branches
# duplicated the entire fan-out body; the copies had already drifted (DEBT#481
# pinned the second one), so there was no single definition point to reason about.
ifeq ($(CONTRACT_SKIP_G7),1)
CONTRACT_FANOUT_TARGETS := g2 g1 g6g4
else
CONTRACT_FANOUT_TARGETS := g2 g1 g6g4 g7
endif

# verify-contract fan-out nimcache isolation (DEBT#481).
# MUST NOT live under build/nimcache/: config.nims hermeticPreBuild (config.nims
# "Clearing build/nimcache for deterministic clean builds") rmDir's that WHOLE
# tree on an envHash MISS, so a per-subtarget subtree *inside* it is only
# partitioning, not isolation — one subtarget still deletes another's objects
# mid-compile. Observed on merged main 8d3c9795: gcc "can't create
# .../@pverification@...nim.c.o", ld "cannot find .../@pcore@...nim.c.o", and at
# run time "cannot open: .../build/nimcache/verify-contract-release-e2e/ax.json
# [IOError]". Outside the tree, no subtarget can delete another's objects.
# (ci/checker.mk ci-compile keeps its per-product nimcache INSIDE build/nimcache
# because every ci-compile product sets AXIOM_HERMETIC_BUILDING=1, which skips
# hermeticPreBuild entirely — different hazard, different mitigation.)
VERIFY_CONTRACT_NIMCACHE_ROOT ?= build/nimcache-verify-contract
VC_NIMCACHE_g2 := $(VERIFY_CONTRACT_NIMCACHE_ROOT)/g2-verify-contract-unit
VC_NIMCACHE_g6g4 := $(VERIFY_CONTRACT_NIMCACHE_ROOT)/g6g4-verify-scenario-oracles
VC_NIMCACHE_g7 := $(VERIFY_CONTRACT_NIMCACHE_ROOT)/g7-verify-contract-release-e2e

# $(call contract_fanout,<log-tag>,<sub-make-target>,<env-prefix>)
# One backgrounded sub-make per member, writing its own log + exit-status file.
# The body deliberately does NOT end with a line-continuation backslash: a
# trailing '\' on the last body line makes make fold the following 'endef' into
# the body ("missing 'endef'"). Call sites supply the continuation.
# $(3) carries AXIOM_VERIFY_CONTRACT_FANOUT=1 for every member except g1: that
# marker freezes the shared contract artifacts (config/integrity.nims
# manifestBootstrap / certManifestBootstrap) so parallel subtargets consume
# bin/feature_manifest_generator + bin/sync_certs read-only instead of relinking
# them concurrently (DEBT#457). g1 runs the mutation harness in an isolated
# worktree and was never part of that freeze.
define contract_fanout
	( echo $$$$ > .verify-contract-logs/$(1).pid; $(3)$(MAKE) $(2) > .verify-contract-logs/$(1).log 2>&1; echo $$? > .verify-contract-logs/$(1).status ) &
endef

verify-contract: verify-contract-artifacts ## Productization Contract Preservation — 유일한 canonical local entrypoint (PARALLEL, g7-consume excluded when CONTRACT_SKIP_G7=1)
	@echo "=== [verify-contract] Productization Contract Preservation (GO 계약 회귀 방어) — PARALLEL ==="
	@rm -rf .verify-contract-logs
	@mkdir -p .verify-contract-logs
	$(call contract_fanout,g2,verify-contract-unit,AXIOM_VERIFY_CONTRACT_FANOUT=1 ) \
	$(call contract_fanout,g1,verify-invariant-mutation,) \
	$(call contract_fanout,g6g4,verify-scenario-oracles,AXIOM_VERIFY_CONTRACT_FANOUT=1 ) \
	$(if $(filter 0,$(CONTRACT_SKIP_G7)),$(call contract_fanout,g7,verify-contract-release-e2e-consume,AXIOM_VERIFY_CONTRACT_FANOUT=1 )) \
	wait; \
	FAIL=0; \
	for target in $(CONTRACT_FANOUT_TARGETS); do \
	  if [ ! -f .verify-contract-logs/$$target.status ]; then \
	    echo "[FAIL] $$target (status file missing — evidence lost)"; FAIL=$$((FAIL+1)); \
	  else \
	    status=$$(cat .verify-contract-logs/$$target.status); \
	    if [ "$$status" -ne 0 ]; then \
	      echo "[FAIL] $$target (exit code: $$status)"; cat .verify-contract-logs/$$target.log; FAIL=$$((FAIL+1)); \
	    else \
	      echo "[PASS] $$target"; \
	    fi; \
	  fi; \
	done; \
	rm -rf .verify-contract-logs; \
	if [ "$$FAIL" -gt 0 ]; then echo "❌ verify-contract: $$FAIL subtarget(s) failed"; exit 1; fi; \
	echo "✅ verify-contract PASSED — Productization Contract Preservation ENFORCED (parallel)"

verify-contract-serial: ## Productization Contract Preservation — serial baseline (for D3 cross-check)
	@echo "=== [verify-contract-serial] Productization Contract Preservation — SERIAL baseline ==="
	@$(MAKE) verify-contract-unit         || exit 1  # G2: canonical count/outcome 단일 authority chain
	@$(MAKE) verify-invariant-mutation    || exit 1  # G1: invariant mutation harness (M1·M2·M3 die)
	@$(MAKE) verify-scenario-oracles      || exit 1  # G6·G4: runtime/reference DATA-FLOW + fail-closed
	@$(MAKE) verify-contract-release-e2e  || exit 1  # G7: release bin/ax E2E (same executable)
	@echo "✅ verify-contract-serial PASSED — Productization Contract Preservation ENFORCED"

# G2 — GO-critical contract invariant unit tests (단일 authority 체인 봉인:
# resolveNodeOutcome → canonical outcome → canonicalVerifiedCount → prove/report/status/self-healing).
# certLeanVerified/certGreen/certVerifiedAxiom 은 독립 count authority 가 아님 (§계획).
CONTRACT_UNIT_TESTS := tests/unit/resolve_node_outcome_test.nim \
                       tests/unit/evidence_propagation_test.nim \
                       tests/unit/candidate_eligibility_test.nim \
                       tests/unit/execution_identity_propagation_test.nim \
                       tests/unit/bundle_digest_test.nim \
                       tests/unit/promotion_semantics_test.nim \
                       tests/unit/certificate_eligibility_test.nim \
                       tests/unit/proof_state_machine_test.nim \
                       tests/unit/test_doc_reference_contract_core.nim \
                       tests/unit/test_make_probe_integration.nim

verify-contract-unit: ## G2 — GO-critical contract invariant unit tests (단일 canonical count authority)
	@echo "=== [verify-contract-unit] GO-critical contract invariants ==="
	@for t in $(CONTRACT_UNIT_TESTS); do \
		echo "  -- $$t"; \
		$(NIM) c -r --hints:off --nimcache:$(VC_NIMCACHE_g2) "$$t" || exit 1; \
	done
	@echo "✅ verify-contract-unit PASSED"

# G1 — invariant mutation harness 를 isolated worktree 에서 실행.
# invariant_mutation_harness.sh 는 tracked source 를 sed 로 변형 후 git checkout 복원하므로
# 반드시 원본 working tree 가 아닌 격리 worktree 에서 실행해야 한다 (계획 §isolated worktree).
# tools/local_purity_check.nim 의 --exec-cmd 모드가 바로 그 격리 바깥 worktree 에서
# 임의 shell command 를 실행한다.
verify-invariant-mutation: bin/purity_check ## G1 — invariant mutation harness (M1·M2·M3 die, isolated worktree)
	@echo "=== [verify-invariant-mutation] invariant mutation harness (isolated worktree) ==="
	@bin/purity_check --warm-nimcache --exec-cmd 'bash tools/invariant_mutation_harness.sh'
	@echo "✅ verify-invariant-mutation PASSED — M1·M2·M3 died"

# G6·G4 — scenario 5/6 oracle + negative compile-reject(fail-closed) DATA-FLOW 검증.
verify-scenario-oracles: ## G6·G4 — runtime/reference boundary DATA-FLOW + fail-closed oracles
	@echo "=== [verify-scenario-oracles] GAP-B scenario 5/6 oracles + G4 fail-closed ==="
	@echo "  -- tests/gateway/state_manager_self_healing_test.nim (scenario 5 projection count)"
	@$(NIM) c -r --hints:off --nimcache:$(VC_NIMCACHE_g6g4) tests/gateway/state_manager_self_healing_test.nim || exit 1
	@echo "  -- tests/unit/test_evidence_truth_boundary.nim (scenario 6 oracle)"
	@$(NIM) c -r --hints:off --nimcache:$(VC_NIMCACHE_g6g4) tests/unit/test_evidence_truth_boundary.nim || exit 1
	@echo "  -- tests/verification/test_g6_* (runtime=VERIFIED / reference=FAILED DATA-FLOW)"
	@for t in tests/verification/test_g6_prove_runtime_vault.nim \
	          tests/verification/test_g6_verify_journal_not_reference.nim \
	          tests/verification/test_g6_runtime_reference_divergence.nim; do \
		echo "     -- $$t"; \
		$(NIM) c -r --hints:off --nimcache:$(VC_NIMCACHE_g6g4) "$$t" || exit 1; \
	done
	@echo "  -- tests/negative/forge_receipt_external.nim — compile must FAIL (fail-closed, G4)"
	@if $(NIM) c --hints:off --nimcache:$(VC_NIMCACHE_g6g4) tests/negative/forge_receipt_external.nim >/dev/null 2>&1; then \
		echo "❌ forge_receipt_external.nim compiled successfully — expected REJECT (fail-open!)"; \
		exit 1; \
	else \
		echo "  ✅ forge_receipt_external.nim correctly REJECTED at compile (fail-closed)"; \
	fi
	@echo "✅ verify-scenario-oracles PASSED"

# G7 — release product E2E: 동일 release bin/ax 로 prove→persist→verify/report/status.
# release bin/ax 는 필요시 빌드한 후 이진 identity 를 고정한다.
# Preflight: always rebuild release bin/ax from current source (no runtime self-rebuild;
# ensures E2E tests the current build, not a stale artifact).
verify-contract-release-e2e: ## G7 — release bin/ax product E2E (same executable)
	@echo "=== [verify-contract-release-e2e] G7 release product E2E ==="
	$(NIM) c -d:release --hints:off --nimcache:$(VC_NIMCACHE_g7) -o:bin/ax src/cli/main.nim || exit 1
	@echo "  -- executable identity:"; sha256sum bin/ax
	@echo "  -- ax scope hash"; bin/ax scope hash || exit 1
	@echo "  -- ax prove (fresh proof state; report/status depend on this generated state)"; bin/ax prove --target normalizeMaxWorkers || exit 1
	@echo "  -- ax report --json (canonical projection)"; bin/ax report --json || exit 1
	@echo "  -- ax status --json (product state)"; bin/ax status --json || exit 1
	@echo "✅ verify-contract-release-e2e PASSED"

# G7-consume — shared canonical proof artifact consumer (PRUNE #1).
# verify-integration runs verify-contract-release-e2e-full (the producer) BEFORE
# this fan-out in the same CI job; g7 therefore consumes the producer's canonical
# report/state instead of re-proving: the --target normalizeMaxWorkers prove now
# runs ONCE per CI run (previously e2e-full and the g7 non-full e2e each ran the
# identical prove — input-identical only while the target cert stays non-
# promotable; consuming the artifact removes that conditionality entirely).
#   Artifacts: logs/verify_contract_e2e_report.json (report persisted by the
#   producer) + logs/ax_proof_state.json (persisted canonical state, written by
#   the prove itself via persistAxProofState). logs/ is gitignored — artifacts
#   are per-run ephemeral, same-run by construction within one CI job.
#   Fail-closed guard: BOTH must exist. If either is missing, fall back to the
#   non-full e2e prove path (below) — local standalone `make verify-contract`
#   keeps working without a prior producer run.
#   Consumer assertions on the saved artifact mirror the producer's jq checks:
#   (a) schemaVersion=="axiom.report.v1", (b) exactly-1 row for the requested
#   --target node (the --target contract invariant "exactly the selected target
#   node(s)", kept tied to the contract), (c) 6-key report<->state equality.
#   Report-exit consistency is NOT re-checked here: the saved report artifact
#   carries no prove exit code — the producer already asserted it at capture.
#   A-1 (runtime-aware audit 2026-09-08): the unconditional rebuild below
#   existed for G7's same-executable guarantee + (pre-PRUNE) re-prove; PRUNE #1
#   already moved proof consumption to the shared canonical artifact, and a
#   CAS-symlinked bin/ax stable entry IS the same executable e2e-full proved
#   with — the guarantee is preserved by testing that artifact. The rebuild is
#   therefore conditional: skipped when bin/ax is the CAS stable entry
#   (symlink); run only when bin/ax is missing or a plain file (local standalone
#   `make verify-contract`).
verify-contract-release-e2e-consume: ## G7 — release product E2E consuming the shared canonical proof artifact (PRUNE #1)
	@echo "=== [verify-contract-release-e2e-consume] G7 release product E2E (shared canonical proof artifact) ==="
	@if [ -L bin/ax ]; then echo "g7: bin/ax is the bootstrap CAS stable entry — rebuild skipped (A-1)"; \
	elif [ -n "$$(find src config -name '*.nim' -newer bin/ax -print -quit)" ]; then echo "g7: bin/ax stale — rebuild (standalone path)"; $(NIM) c -d:release --hints:off --nimcache:$(VC_NIMCACHE_g7) -o:bin/ax src/cli/main.nim || exit 1; \
	else echo "g7: bin/ax fresh (serial seed by verify-contract-artifacts, DEBT#481) — rebuild skipped, fan-out 중 공유 산출물 기록자 0"; fi
	@echo "  -- executable identity:"; sha256sum bin/ax
	@echo "  -- ax scope hash"; bin/ax scope hash || exit 1
	@set -eu; \
	NODE="src/core/orchestrator/orchestrator_api.nim::normalizeMaxWorkers"; \
	STATE=logs/ax_proof_state.json; \
	ARTIFACT=logs/verify_contract_e2e_report.json; \
	if [ -f "$$STATE" ] && [ -f "$$ARTIFACT" ]; then \
	  echo "  -- [consume] canonical proof artifact present ($$ARTIFACT + $$STATE) — consuming saved prove result, prove NOT re-run"; \
	  REPORT="$$(cat "$$ARTIFACT")"; \
	  printf '%s' "$$REPORT" | jq -e '.schemaVersion=="axiom.report.v1"' >/dev/null || \
	    { echo "FAIL: report schema"; exit 1; }; \
	  N="$$(printf '%s' "$$REPORT" | jq -c --arg id "$$NODE" '[.nodeReports[] | select(.nodeId==$$id)]')"; \
	  [ "$$(printf '%s' "$$N" | jq 'length')" = "1" ] || \
	    { echo "FAIL: target node not exactly 1: $$NODE"; exit 1; }; \
	  printf '%s' "$$REPORT" | jq -e --argjson st "$$(cat "$$STATE")" \
	    '.summary.verified==$$st.summary.verified and .summary.symbolCount==$$st.summary.symbolCount and .summary.verifiedRatio==$$st.summary.verifiedRatio and .summary.verificationSuccessRate==$$st.summary.verificationSuccessRate and .summary.totalSourceFunctions==$$st.summary.totalSourceFunctions and .summary.failedCount==$$st.summary.failedCount' \
	    >/dev/null || { echo "FAIL: report/state inconsistency"; exit 1; }; \
	  echo "  -- [consume] assertions PASSED (report schema, exactly-1 --target node, 6-key report/state equality)"; \
	else \
	  echo "  -- [fallback] canonical proof artifact missing ($$ARTIFACT or $$STATE) — falling back to full prove path"; \
	  echo "  -- ax prove (fresh proof state; report/status depend on this generated state)"; bin/ax prove --target normalizeMaxWorkers || exit 1; \
	  echo "  -- ax report --json (canonical projection)"; bin/ax report --json || exit 1; \
	fi; \
	echo "  -- ax status --json (product state)"; bin/ax status --json || exit 1
	@echo "✅ verify-contract-release-e2e-consume PASSED"

# G7-full — CI release E2E. Canonical product-outcome assertion.
# 정확한 정의: "certificate storage-layout independent + canonical persisted-state projection consistency".
#  - certificate(data/trusted/certificates 등) 저장구조에는 비의존한다(스캔/열거 없음).
#  - 반면 로그/데이터의 canonical persisted state logs/ax_proof_state.json 투영 일관성은 **의존**하고 검증한다.
# 리포트 stdout은 exit code와 독립적으로 취득하고, 제품의 report verdict
# (runOutcome.verdict/gateVerdict + summary)를 재구성이 아니라 "일관성 검증"으로 소비한다.
# verified==0은 G7 FAIL이다 — 아무것도 확립하지 못한 run은 성공이 아니다.
# (제품 exit code 자체의 fail-open 수정은 pinned-file rotation follow-up이다;
#  이 target은 verdict를 직접 assert해 CI에서 fail-closed로 동작한다.)
# status·tier는 보고된 값 그대로 소비만 — 둘 사이 관계(status→tier/tier→status)를 CI가 새로 해석하지 않음(금지).
verify-contract-release-e2e-full: ## G7-full — CI release E2E (canonical product-outcome assertion, §계획 v7)
	@set -eu; \
	NODE="src/core/orchestrator/orchestrator_api.nim::normalizeMaxWorkers"; \
	bin/ax --check-provenance || exit 1; \
	HASH_A="$$(sha256sum bin/ax | cut -d' ' -f1)"; \
	bin/ax --version >/dev/null; \
	AXIOM_CI=1 bin/ax prove --target normalizeMaxWorkers; \
	set +e; REPORT="$$(bin/ax report --json)"; REPORT_EXIT=$$?; set -e; \
	[ -n "$$REPORT" ] || { echo "FAIL: report stdout empty"; exit 1; }; \
	mkdir -p logs; printf '%s' "$$REPORT" > logs/verify_contract_e2e_report.json; \
	printf '%s\n' "$$REPORT_EXIT" > logs/verify_contract_e2e_report_exit.txt; \
	printf '%s' "$$REPORT" | jq -e '.schemaVersion=="axiom.report.v1"' >/dev/null || \
	  { echo "FAIL: report schema"; exit 1; }; \
	N="$$(printf '%s' "$$REPORT" | jq -c --arg id "$$NODE" '[.nodeReports[] | select(.nodeId==$$id)]')"; \
	[ "$$(printf '%s' "$$N" | jq 'length')" = "1" ] || \
	  { echo "FAIL: target node not exactly 1: $$NODE"; exit 1; }; \
	TIER="$$(printf '%s' "$$N" | jq -r '.[0].assuranceTier')"; \
	STATUS="$$(printf '%s' "$$N" | jq -r '.[0].status')"; \
	V=$$(printf '%s' "$$REPORT" | jq -r '.summary.verified'); \
	F=$$(printf '%s' "$$REPORT" | jq -r '.summary.failedCount'); \
	TO=$$(printf '%s' "$$REPORT" | jq -r '.summary.timeoutCount // 0'); \
	VERDICT="$$(printf '%s' "$$REPORT" | jq -r '.runOutcome.verdict // "MISSING"')"; \
	GATE="$$(printf '%s' "$$REPORT" | jq -r '.runOutcome.gateVerdict // "MISSING"')"; \
	EXPECTED_EXIT=0; { [ "$$VERDICT" = "PASS" ] && [ "$$GATE" = "PASS" ] && [ "$$F" -eq 0 ] && [ "$$TO" -eq 0 ] && [ "$$V" -gt 0 ]; } || EXPECTED_EXIT=1; \
	[ "$$REPORT_EXIT" -eq "$$EXPECTED_EXIT" ] || \
	  { echo "FAIL: report exit $$REPORT_EXIT inconsistent with verdict (verdict=$$VERDICT gate=$$GATE v=$$V f=$$F to=$$TO, expect $$EXPECTED_EXIT)"; exit 1; }; \
	STATE=logs/ax_proof_state.json; [ -f "$$STATE" ] || { echo "FAIL: no state SSOT"; exit 1; }; \
	MODULE="src/core/orchestrator/orchestrator_api.nim"; FN="normalizeMaxWorkers"; \
	VAULT=data/trusted/certificates; \
	IRS="$$(jq -r --arg m "$$MODULE" --arg f "$$FN" \
	    '[.entries[]|select(.modulePath==$$m and .functionName==$$f)|.irHash]|join(" ")' \
	    "$$VAULT/manifest.json")"; \
	CERT=""; for h in $$IRS; do \
	  bin/ax cert verify "$$VAULT/$$h.json" >/dev/null 2>&1 && CERT="$$VAULT/$$h.json"; \
	done; \
	[ -n "$$CERT" ] || { echo "FAIL: no current certificate for $$MODULE::$$FN"; exit 1; }; \
	KERNEL_OUT="$$(bin/ax cert verify --kernel "$$CERT" 2>&1)" || \
	  { echo "FAIL: cert verify --kernel rejected $$CERT"; echo "$$KERNEL_OUT"; exit 1; }; \
	echo "$$KERNEL_OUT"; \
	printf '%s\n' "$$KERNEL_OUT" > logs/verify_contract_e2e_kernel.out; \
	jq -e --slurpfile c "$$CERT" \
	  '.executionIdentity.executionBundleFingerprint==$$c[0].executionBundleFingerprint' \
	  "$$STATE" >/dev/null || { echo "FAIL: run/cert identity mismatch"; exit 1; }; \
	jq -e --arg n "$$NODE" \
	  '[.runAccounting.units[]|select(.unitId==$$n and .verificationOutcome=="SATISFIED" and .satisfactionSource=="FRESH")]|length==1' \
	  "$$STATE" >/dev/null || { echo "FAIL: target unit not FRESH-SATISFIED"; exit 1; }; \
	printf '%s\n' "$$CERT" > logs/verify_contract_e2e_cert_path.txt; \
	printf '%s' "$$REPORT" | jq -e --argjson st "$$(cat "$$STATE")" \
	  '.summary.verified==$$st.summary.verified and .summary.symbolCount==$$st.summary.symbolCount and .summary.verifiedRatio==$$st.summary.verifiedRatio and .summary.verificationSuccessRate==$$st.summary.verificationSuccessRate and .summary.totalSourceFunctions==$$st.summary.totalSourceFunctions and .summary.failedCount==$$st.summary.failedCount' \
	  >/dev/null || { echo "FAIL: report/state inconsistency"; exit 1; }; \
	HASH_B="$$(sha256sum bin/ax | cut -d' ' -f1)"; \
	[ "$$HASH_A" = "$$HASH_B" ] || { echo "FAIL: release binary changed during E2E"; exit 1; }; \
	echo "INFO: G7 pass (tier=$$TIER status=$$STATUS cert=$$CERT)"
	@echo "✅ verify-contract-release-e2e-full PASSED"

bin/readiness_start_gate: src/gate/runners/readiness_start_gate.nim
	AXIOM_CI=1 AXIOM_CI_PRESERVE_CACHE=1 $(NIM) c --hints:off -d:release -o:$@ $<

check-readiness-start: bin/readiness_start_gate ## productization START gate: E2E vertical slice + readiness evaluator
	AXIOM_CI=1 AXIOM_CI_PRESERVE_CACHE=1 ./bin/readiness_start_gate

build: $(METADATA) ## 전체 CLI 빌드 (nim check)
	@echo "=== [3/4] Full Build ==="
	$(NIM) c --hints:off -d:allowMissingZ3 -o:bin/ax src/cli/main.nim
	@echo "✅ Build successful"
	@echo ""

GATE_RUNNERS := bin/validate-runners

bin/validate-runners: src/gate/runners/validate_runners.nim
	$(NIM) c --hints:off -o:$@ $<

gate-runners: $(GATE_RUNNERS) ## Gate runner binaries 빌드
	@echo "✅ Gate runners built"

# ── gate-binaries — AGENTS.md §2.7 문서 명령 실현 ────────────────────────────
# pre-push liveness pair 6종의 단일 출처는 .githooks/pre-push의 pair 목록
# (line 72)이다. pre-push는 src -nt bin → FAIL (mtime precondition)로
# 판정하므로, make 의존성 시맨틱(prereq가 bin보다 최신이면 재빌드)과 1:1로
# 정합한다 — 이 타깃이 성공하면 push-admissibility의 liveness precondition이
# 결정적으로 통과한다.
GATE_LIVENESS_BINS := bin/debt_engine bin/check_nim_theater bin/doc_path_validator \
                      bin/proof_unit_consistency_gate bin/proof_reconcile_gate bin/epoch_transaction_gate

# bin/layer_enforcement_gate — pre-push Part 3는 부재/스테일(src -nt bin) 시 재빌드한다.
# make 의존성 시맨틱(prereq가 bin보다 최신이면 재빌드)으로 동일 갱신을 보장해야
# gate-binaries가 진짜 폐쇄가 된다.
# bin/effect_contract_projection — push-admissibility check-debt → bin/debt_engine
# --validate Part D가 이 바이너리를 subprocess로 평가한다(evalEffectViolations).
bin/effect_contract_projection: src/verification/projections/effect_contract_projection.nim
	$(NIM) c $(NIM_TOOL_FLAGS) -o:$@ $<

gate-binaries: $(GATE_LIVENESS_BINS) gate-runners bin/layer_enforcement_gate bin/effect_contract_projection ## worktree 전환 후 gate 바이너리 갱신 (pre-push liveness 6종 + gate-runners + layer gate + effect evaluator)
	@echo "✅ gate-binaries: pre-push liveness 6종 + gate runners + layer_enforcement_gate + effect_contract_projection up to date"

test:
	@echo "[AXIOM GATE] Running E2E Verification Suite..."
	@nim c -r tests/test_contract_pipeline.nim
	@$(MAKE) perf-check

# data/benchmarks/perf_latest.json is an untracked execution artifact
# (gitignored): stage 1 regenerates it in place on every run, so repeated
# gate runs leave `git status` clean. Only the baselines are versioned —
# perf-baseline below stays the explicit-only writer of perf_baseline.json.
perf-check:
	@nim c -r tools/perf_measure.nim latest
	@nim c -r tools/perf_checker.nim --baseline:data/benchmarks/perf_baseline.json --latest:data/benchmarks/perf_latest.json --max-regression:5.0

# perf-baseline은 EXPLICIT-ONLY다: 그 어떤 타깃도 이 타깃에 의존해서는 안 된다.
# tools/perf_measure.nim baseline (min-of-5)으로 data/benchmarks/perf_baseline.json을
# 재생성한다. 자동 복구 경로(CI 레인, make test, self-heal)로 연결되는 것은 금지다 —
# 자동 갱신되는 baseline은 실제 회귀를 조용히 세탁한다(§0.9 theater).
# baseline은 인간의 명시적 판단으로만 움직인다.
perf-baseline:
	@nim c -r tools/perf_measure.nim baseline

bench-cost-probe:
	@nim c -r --hints:off tools/benchmark_cost_probe.nim

# ── L1 Developer Fast Verify (DX: persistent cache, no release/LTO) ───────────
# P1 DX profile — "내가 방금 수정한 것이 깨졌는가?"
#   * 캡슐화: AXIOM_CI_PRESERVE_CACHE=1 (hermetic rmDir 회피 + .git/index MISS 제거)
#   * no nimble build/install, no release, no LTO
#   * 모든 cheap deterministic unit tests (병렬) + fast static gates
#   * 자동 affected-test selection은 금지(불확정); test-fast <explicit> 으로만 수동 선택
#   * L2 전체(Lean vacuity/decision-graph/cert-integrity 등 무거운 gate)는
#     local-verify-static-full 로 분리 — test-fast는 L1 속도에 집중
# INVARIANT: same source + same environment → same verdict (결정론성 유지).
test-fast: ## L1: 빠른 증분 developer verify (캐시 보존, no LTO, 병렬 유닛, fast gates)
	@echo "=== [L1] test-fast: incremental developer verification (no release/LTO) ==="
	@$(MAKE) $(GATES_FAST) || exit 1
	@export AXIOM_CI_PRESERVE_CACHE=1; \
	rm -rf /tmp/opencode/ax-unittest-cache && mkdir -p /tmp/opencode/ax-unittest-cache; \
	i=0; \
	for t in $(TESTS_FAST_UNIT); do \
	  i=$$((i+1)); \
	  ( AXIOM_CI_PRESERVE_CACHE=1 AXIOM_HERMETIC_BUILDING=1 $(NIM) c -r --hints:off --nimcache:/tmp/opencode/ax-unittest-cache/$$i -o:/tmp/opencode/ax-ut$$i "$$t" \
	      > /tmp/opencode/ax-ut$$i.log 2>&1 ) & \
	done; \
	wait; \
	FAIL=0; \
	N=$$(echo "$(TESTS_FAST_UNIT)" | wc -w); \
	for i in $$(seq 1 $$N); do \
	  if [ -s /tmp/opencode/ax-ut$$i.log ]; then \
	    if grep -qE "Error:|Check failed|\[FAILED\]|Traceback" /tmp/opencode/ax-ut$$i.log; then echo "[FAIL] unit $$i"; cat /tmp/opencode/ax-ut$$i.log | tail -8; FAIL=$$((FAIL+1)); fi; \
	  fi; \
	done; \
	if [ "$$FAIL" -gt 0 ]; then echo "❌ test-fast: $$FAIL unit test(s) failed"; exit 1; fi; \
	echo "✅ test-fast PASSED — $$i cheap deterministic unit tests green (incremental, no LTO)"

# ── 명시적 단일 테스트 타겟 (자동 affected-test selection 대신 수동 선택) ──────
test-fast-one: ## test-fast <FILE|TARGET> — 단일 대상만 증분 검증 /usage: make test-fast-one T=testFilePath/name
	@if [ -z "$(T)" ]; then echo "usage: make test-fast-one T=tests/unit/axiom_ir_test.nim"; exit 1; fi
	@export AXIOM_CI_PRESERVE_CACHE=1; \
	AXIOM_CI_PRESERVE_CACHE=1 $(NIM) c -r --hints:off --nimcache:build/nimcache/test -o:/tmp/opencode/ax-one "$(T)"

test-all: ## 전체 테스트: 단위 + gateway 순차 실행
	@$(MAKE) test-unit
	@$(MAKE) test-gateway

clean: ## 빌드 산출물 삭제 (로컬 전용, CI에서는 사용 금지)
	rm -rf .nimcache/ build/
	cd bin/ && for f in *; do case "$$f" in generate-pbt-tests|nimtry|sync-branch) ;; *) rm -f "$$f";; esac; done
	rm -rf .axiom/staging/*
	rm -rf tools/logs/*
	find tests/gateway/ -maxdepth 1 -type f -executable -delete 2>/dev/null || true  # axiom:best-effort(cleanup — no stale binaries)
	@echo "✅ Clean complete (local only — CI uses CircleCI cache)"

# ── Explicit Cache Lifecycle (P4: cache deletion ≠ build behavior) ─────────────
# 빌드는 항상 캐시를 재사용하고, 삭제만 명시적으로 수행한다.
clean-cache: ## 모든 로컬 reusable cache 명시 제거 (hermetic + compiler + dep caches)
	rm -rf .axiom/cache/ build/nimcache/ $(VERIFY_CONTRACT_NIMCACHE_ROOT) .nimcache/ .cache/
	@echo "✅ All local caches cleared (hermetic .axiom/cache, build/nimcache, $(VERIFY_CONTRACT_NIMCACHE_ROOT), .nimcache, .cache)"

# verify-contract fan-out nimcache(VERIFY_CONTRACT_NIMCACHE_ROOT)는 build/nimcache/
# 밖의 독립 루트(DEBT#481)이므로 컴파일러 프로필로 분할되지 않는다 — 그 서브디렉터리
# 이름은 프로필이 아니라 fan-out 멤버(g2/g6g4/g7)를 가리킨다. 여기서 멤버→프로필 대응을
# 새로 주장하지 않고 루트 단위로 통째 제거한다(재생성 가능한 캐시). 멤버 이름을 하드코딩하면
# 새 멤버 추가 시 clean 공백이 그대로 재발하므로 파생된 루트 변수만 참조한다.
clean-test-cache: ## test/debug nimcache 만 제거 (debug/test profile)
	rm -rf build/nimcache/test build/nimcache/debug $(VERIFY_CONTRACT_NIMCACHE_ROOT)
	@echo "✅ test/debug nimcache cleared"

clean-release-cache: ## release/danger nimcache 만 제거 (release/LTO profile)
	rm -rf build/nimcache/release $(VERIFY_CONTRACT_NIMCACHE_ROOT)
	@echo "✅ release nimcache cleared"

test-unit:
	@nim c -r tests/test_proof_injector.nim
	@nim c -r tests/test_ir_generator.nim
	@nim c -r tests/test_ast_hash_whitespace.nim
	@nim c -r tests/test_axiom_ir.nim
	@nim c -r tests/test_best_effort_pragma.nim
	@nim c -r tests/test_gate_macro.nim
	@nim c -r tests/test_profiler.nim
	@nim c -r tests/test_state_ledger.nim
	@nim c -r tests/unit/feature_manifest_determinism_test.nim
	@nim c -r tests/ci/test_derive_checker_closure.nim
	@nim c -r tests/ci/test_reanchor_pin.nim
	@nim c -r tests/ci/test_verify_b_artifact.nim
	@nim c -r tests/ci/test_b_cache_anchor.nim
	@nim c -r tests/ci/test_admission_check_stages.nim
	@nim c -r tests/ci/test_admission_venue_split.nim
	@nim c -r tests/ci/test_s5_build_skip.nim
	@nim c -r tests/ci/test_sl02_consumer_binding.nim
	@nim c -r tests/ci/test_landing_observe_acceptance.nim
	@nim c -r tests/ci/test_l3_guard_fail_closed.nim
	@nim c -r tests/cli/test_merge_cli.nim
	@nim c -r tests/cli/test_report_cli.nim
	@nim c -r tests/unit/test_judgment_set_derivation.nim

# ── oracle-evidence mode=none floor 회귀 픽스처 (Phase 2d, 계획 CE #13) ────
# 셀렉터 --oracle-evidence 계약(0이 정당한/정당하지 않은 경우) + 게이트
# 재검증 + evidence 실패 모드. 기존 타깃에는 편입하지 않는다 (추가 전용).
test-oracle-evidence:
	@nim c -r tests/ci/test_oracle_evidence_regression.nim

# ── Workflow parse-poison lint self-test (tools/ci/test_workflow_poison_lint.sh) ──
# validate_workflow_shell.sh 파스 독 룰(토큰 보유 run 스칼라 > 21,000자 → FAIL,
# docs/spec/gh_run_observation_quirks.md Q4)의 셀프테스트: 커밋된 5-피처 설계
# 판정 행렬(21,001 FAIL / 21,000 PASS / 20,999 PASS / 30,004 토큰무 PASS /
# 25,954 FAIL-회귀) + 원본 워크플로 false-positive sweep. fail-closed, zero-dep.
test-workflow-poison-lint: ## workflow parse-poison 룰 셀프테스트 (fixture 판정 행렬 + false-positive sweep, fail-closed)
	@if [ -f tools/ci/test_workflow_poison_lint.sh ]; then \
	  bash tools/ci/test_workflow_poison_lint.sh; \
	else \
	  echo "[test-workflow-poison-lint] SKIP (loud): tools/ci/test_workflow_poison_lint.sh absent from this OID — pre-introduction snapshot; the fixture contract applies from its introducing commit onward"; \
	fi

.PHONY: test-workflow-poison-lint

# ── Workflow lane-stderr guard self-test (tools/ci/test_workflow_lane_guard.sh) ──
# validate_workflow_shell.sh 레인-stderr 방출 룰(레인 패턴 보유 워크플로는 전사
# 공개(라이브 tee 또는 cat 재출력) + `if: always()` 레인 로그 업로드 마커 필수 —
# 미충족 → FAIL; prereg 2026-10-14 §8 개정 2026-10-15)의 셀프테스트: 커밋된
# 2-피처 판정 행렬(무방출 FAIL / 방출 PASS) + 실제 역사 blob 정합성 검사
# (리버트 4레인 blob 2c94c9914 FAIL / 레시피 2555ab966 PASS — git 객체 미해결 시
# fail-closed) + 원본 워크플로 false-positive sweep. fail-closed, zero-dep.
test-workflow-lane-guard: ## workflow lane-stderr 가드 셀프테스트 (fixture 행렬 + 역사 blob 정합성 + sweep, fail-closed)
	@if [ -f tools/ci/test_workflow_lane_guard.sh ]; then \
	  bash tools/ci/test_workflow_lane_guard.sh; \
	else \
	  echo "[test-workflow-lane-guard] SKIP (loud): tools/ci/test_workflow_lane_guard.sh absent from this OID — pre-introduction snapshot; the fixture contract applies from its introducing commit onward"; \
	fi

.PHONY: test-workflow-lane-guard

# ── Workflow jq data-contract self-test (tools/ci/test_workflow_jq_contracts.sh) ──
# 라이브 워크플로 YAML에서 jq 프로그램 텍스트를 추출(python3+PyYAML 앵커 단일-
# 매치, 0/다수 매치 → exit 2 fail-closed)하여 실측 캡처 fixture(2026-11-01
# gh api GET 응답 verbatim — tests/fixtures/workflow_jq_contracts/, 출처는
# capture_manifest.json)에 실행하고 기대 출력과 정확 일치를 단언한다.
# 고정 계약: Q16(ghec-canary jobs-API labels는 문자열 배열 — `[.labels[]? |
# (.name? // .)]` 평탄화 + index 게이트, docs/spec/ci_provider_failover_quirks.md
# Q16)·Q17(router ACC_NON_SKIP 배열 — `.[] |` 분배 관측 행 출력, 동문서 Q17).
# `bash -n` 셸 게이트가 전혀 검증하지 못한 클래스(jq가 소비하는 데이터 구조)의
# 회귀 — 2026-11-01 GHEC 복귀 incident(PR #1160/#1163)에서 발화. 네트워크 호출
# 없음(커밋된 정적 fixture). 음성 통제: 수리 전 프로그램이 fixture에서 jq
# exit 5임을 재검증 — fixture가 mock으로 오염되거나 수리가 되돌려지면 FAIL.
# fail-closed, zero-dep(jq/python3/PyYAML/bash — validate_workflow_shell.sh와
# 동일 의존 집합).
test-workflow-jq-contracts: ## workflow jq 데이터 계약 셀프테스트 (라이브 YAML 추출 × 실측 fixture, Q16/Q17 회귀 고정, fail-closed)
	@if [ -f tools/ci/test_workflow_jq_contracts.sh ]; then \
	  bash tools/ci/test_workflow_jq_contracts.sh; \
	else \
	  echo "[test-workflow-jq-contracts] SKIP (loud): tools/ci/test_workflow_jq_contracts.sh absent from this OID — pre-introduction snapshot; the jq data-contract applies from its introducing commit onward"; \
	fi

.PHONY: test-workflow-jq-contracts

test-vc-pipeline:
	@nim c -d:axiomProfile -r tests/test_vc_complete.nim

check-vacuity:
	@echo "[GATE] Running Vacuity Check on test fixtures..."
	@nim c -r tools/ci/check_vacuity.nim --path:tests/fixtures/

test-prelude: ## prelude.lean integration tests (NimInt mapping, Int.natCast_nonneg)
	@echo "=== [prelude] Prelude Integration Tests ==="
	$(NIM) c $(NIM_TOOL_FLAGS) -o:bin/test_prelude tests/integration/test_prelude.nim
	bin/test_prelude
	@echo "✅ Prelude integration tests passed"
	@echo ""

audit: ## 4-dimension quality audit + nimtry + stub check (로컬 실행)
	$(NIM) c -r src/gate/runners/quality_gate_runner.nim
	$(NIM) c -r src/gate/runners/debt_scan_gate.nim
	$(NIM) c -r src/core/audit/governance_engine.nim
	$(NIM) c --mm:orc -r tools/ci/verify_stubs.nim
	@if [ -f bin/nimtry ]; then bin/nimtry src/; else echo "❌ bin/nimtry not found — architecture check REQUIRED"; exit 1; fi

seed: ## PBT asset enrichment (로컬 실행)
	$(NIM) c -r tools/seed_registry.nim --layer=2+

nightly: audit seed ## Nightly 전체 실행 (로컬 — SSOT nightly_runner.nim)
	$(NIM) c --hints:off -r tools/nightly_runner.nim

hotspot-report: ## Generate burn-down priority report
	$(NIM) c -r tools/ci/hotspot_report.nim --since=30 --top=20 --format=markdown > docs/reports/hotspot_burn_down.md
	@echo "✅ Report generated: docs/reports/hotspot_burn_down.md"

hotspot-check: ## Verify changed files don't worsen top hotspots (gate-hook integrated)
	$(NIM) c --hints:off -r src/gate/runners/hotspot_enforcement_gate.nim

bin/hotspot_enforcement_gate: src/gate/runners/hotspot_enforcement_gate.nim ## Build hotspot enforcement gate binary
	$(NIM) c --hints:off -o:$@ $<

strict-build: ## Strict build with axiomStrict invariants enforced
	nim c --hints:off -d:axiomStrict -d:release -o:bin/ax src/cli/main.nim
	@echo "✅ Strict build successful"

check-architecture: ## Architecture constraint test with approved violation support
	@echo "=== Architecture Constraints (CI Test) ==="
	$(NIM) c -r tests/architecture_constraints.nim
	@echo ""

test-legacy: ## 레거시 스텁 테스트 실행 (수동, 컴파일 검증만)
	@COUNT=$$(ls tests/legacy/*.nim 2>/dev/null | wc -l); \
	if [ "$$COUNT" -eq 0 ]; then \
		echo "✅ No legacy stubs remaining (cleaned)"; \
		exit 0; \
	fi; \
	echo "⚠️  Running legacy stubs ($$COUNT files, compilation-only)"; \
	FAIL=0; \
	for f in tests/legacy/*.nim; do \
		nim c --hints:off "$$f" || FAIL=$$((FAIL+1)); \
	done; \
	if [ $$FAIL -gt 0 ]; then \
		echo "❌ $$FAIL/$$COUNT legacy stubs failed to compile"; \
		exit 1; \
	fi; \
	echo "✅ Legacy stubs compile ($$COUNT files)"

immutable-build: ## The Immutable Builder — transactional auto-healing build
	@echo "=== The Immutable Builder: Transactional Build ==="
	$(NIM) c -d:release -o:bin/build tools/build.nim
	bin/build
	@echo ""

immutable-dry: ## The Immutable Builder — dry run (show plan, no changes)
	@echo "=== The Immutable Builder: Dry Run ==="
	$(NIM) c -o:bin/build tools/build.nim
	bin/build --dryRun
	@echo ""

immutable-verify: ## The Immutable Builder — idempotency verification (2-pass)
	@echo "=== The Immutable Builder: Idempotency Verification ==="
	$(NIM) c -d:release -o:bin/build tools/build.nim
	bin/build --verify --jsonLog
	@echo ""

generate-features: ## BDD feature files from {.genFeature.} type annotations
	nim c --hints:off -o:bin/feature_writer tools/feature_writer.nim
	bin/feature_writer

pre-commit: ## [Axiom v5.1] Compile-time overhead zero — all tools pre-built, assets fixed
	@echo "==> 1/5: Hermetic static analysis toolchain pre-build (release optimized)"
	@$(NIM) c -d:release $(NIM_TOOL_FLAGS) -o:bin/hermetic_build tools/hermetic_build.nim
	@$(NIM) c -d:release $(NIM_TOOL_FLAGS) -o:bin/check_imports_ast tools/check_imports_ast.nim
	@$(NIM) c -d:release $(NIM_TOOL_FLAGS) -o:bin/debt_engine tools/debt_engine.nim
	@$(NIM) c -d:release $(NIM_TOOL_FLAGS) -o:bin/feature_manifest_generator tools/feature_manifest_generator.nim
	@echo "==> 2/5: Generate manifest and BDD assets from fixed binaries"
	@./bin/feature_manifest_generator
	@echo "==> 3/5: Static consistency verification"
	@./bin/check_imports_ast
	@echo "==> 4/5: Debt synchronization verification"
	@./bin/debt_engine --validate
	@echo "==> 5/5: Git staging of generated data assets"
	@git add tests/features/*.feature data/architecture_debt.json data/feature_manifest.json
	@echo "✅ [Axiom v5.1] Pre-commit integrity fixed. Safe to git commit."

# ── Φ2: Fail-Closed Paradigm Shift CI Scanners ──────────────────────────────────────────
.PHONY: check-nim-theater check-lean-vacuity check-vacuity check-vacuity-simple check-perf doc-path-validator

check-nim-theater: bin/check_nim_theater ## Static theater pattern scan (Nim code)
	@echo "=== [Φ2a] Nim Theater Pattern Scan ==="
	@bin/check_nim_theater --allowlist tools/ci/nim_theater_allowlist.json src/ tests/ tools/
	@echo "✅ Nim theater check passed"

bin/check_nim_theater: tools/ci/check_nim_theater.nim
	$(NIM) c $(NIM_TOOL_FLAGS) -o:$@ $<

check-lean-vacuity: bin/check_lean_vacuity ## Lean proof totalness scan
	@echo "=== [Φ2b] Lean Vacuity & Axiom Check ==="
	@bin/check_lean_vacuity --allowlist tools/ci/lean_vacuity_allowlist.json proofs/ src/verification/ tests/fixtures/
	@echo "✅ Lean vacuity check passed"

bin/check_lean_vacuity: tools/ci/check_lean_vacuity.nim
	$(NIM) c $(NIM_TOOL_FLAGS) -o:$@ $<

check-vacuity-simple: ## Lean 4 vacuity scanner via `lake env lean --run` (canonical toolchain, per-file isolation, lake-built oleans)
	@echo "=== [Φ2b''] Lean Vacuity Scan (lake env lean --run, per-file isolated) ==="
	@export LEAN_PATH="$$PWD/proofs/.lake/build/lib/lean:$${LEAN_PATH:-}"; \
	(cd proofs && lake build) || { echo "FATAL: 'lake build' failed — vacuity scan requires built oleans"; exit 1; }; \
	FILES_FIXTURES=$$(find tests/fixtures/ -name '*.lean' -not -name 'positive_spec.lean' -not -name 'test_custom_reverse_sorry.lean' 2>/dev/null); \
	FILES_GATE=""; \
	if ls proofs/.lake/build/lib/lean/GateInvariants/*.olean >/dev/null 2>&1; then \
		FILES_GATE="proofs/GateInvariants.lean $$(find proofs/GateInvariants/ -name '*.lean' 2>/dev/null)"; \
	else \
		echo "WARNING: GateInvariants oleans missing — skipping GateInvariants proofs"; \
	fi; \
	FILES_IR=""; \
	if [ -f proofs/.lake/build/lib/lean/IR/TranslatorEquivalence.olean ]; then \
		FILES_IR="proofs/IR.lean $$(find proofs/IR/ -name '*.lean' 2>/dev/null)"; \
	else \
		echo "WARNING: IR proof lib not fully built — skipping import-dependent IR proofs (IR.lean, IR/MetaCheckIR, IR/ShmFFI, IR/LeanWorker, IR/TranslatorEquivalence)"; \
		FILES_IR="proofs/IR/AxiomIRExpr.lean proofs/IR/ForkFFI.lean"; \
	fi; \
	FILES="$$FILES_GATE $$FILES_IR $$FILES_FIXTURES"; \
	if [ -z "$${FILES// /}" ]; then \
		echo "No .lean files to check"; \
	else \
		for f in $$FILES; do \
			echo "Checking $$f..."; \
			(cd proofs && lake env lean --run check_vacuity.lean "../$$f") || exit 1; \
		done; \
	fi
	@echo "✅ Vacuity check passed"

bin/doc_path_validator: tools/ci/doc_path_validator.nim
	$(NIM) c $(NIM_TOOL_FLAGS) -o:$@ $<

doc-path-validator: ## Validate documentation file path references (fail-closed; DEBT#403 FIXED)
	@echo "=== [Φ2d] Doc Path Validator ==="
	@$(NIM) c $(NIM_TOOL_FLAGS) -o:bin/doc_path_validator tools/ci/doc_path_validator.nim
	bin/doc_path_validator

check-perf:
	@$(NIM) c -r -o:bin/check_perf tools/ci/check_perf.nim
