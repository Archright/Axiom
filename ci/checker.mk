# ci/checker.mk — gateway/부트스트랩 실행 코드 (Tier C closure 멤버)
#
# runner-pool-acceptance.yml가 H에서 실행하는 make 타깃의 단일 정의점.
# Makefile은 `include ci/checker.mk`로 로컬 호출을 유지하고, 이 파일은
# `make -f ci/checker.mk <target>` 단독 실행이 가능하도록 자기 완결이다
# (모든 변수 ?=/:= 자체 정의, SHELL 명시).
#
# 레시피는 Makefile에서 이동한 것(변경 금지 원칙 대상)으로,
# recipe_hash 입력(config.nims·config/effects.nims·src/gate/config.nims)과
# setup-axiom-toolchain trustSurface는 무변경이다.

SHELL := /bin/bash

NIM ?= nim
NIMBLE_PKGS := $(HOME)/.nimble/pkgs2
CHECKSUMS_PATH := $(wildcard $(NIMBLE_PKGS)/checksums-*)
FUSION_PATH := $(wildcard $(NIMBLE_PKGS)/fusion-*)
# Resolve the toolchain ROOT (must contain compiler/*.nim for kernel builds
# importing compiler/[ast, idents]).
NIM_TOOLCHAIN_ROOT := $(if $(wildcard $(HOME)/.choosenim/toolchains/nim-2.2.10/compiler/ast.nim),$(HOME)/.choosenim/toolchains/nim-2.2.10,$(patsubst %/bin/nim,%,$(shell which nim 2>/dev/null || echo $(HOME)/.choosenim/toolchains/nim-2.2.10/bin/nim)))
NIM_TOOL_FLAGS := --hints:off --skipParentCfg --skipProjCfg --path:$(NIM_TOOLCHAIN_ROOT) --path:. --path:src --path:tools --path:$(CHECKSUMS_PATH) --path:$(FUSION_PATH)

# ci-compile per-product nimcache (DEBT#481 isolation, see ci-compile).
# Stays INSIDE build/nimcache/ so the ci-bootstrap-artifacts B-cache payload
# (runner-pool-acceptance ci-bootstrap upload) keeps covering these objects —
# it is safe there because every ci-compile product sets
# AXIOM_HERMETIC_BUILDING=1, which skips config.nims' hermeticPreBuild entirely
# (that block is the only thing that rmDir's build/nimcache).
CI_COMPILE_NIMCACHE ?= build/nimcache/ci-compile

# CI 환경 (runner-pool-acceptance가 설정; 미설정 = 로컬 전량)
AXIOM_CI ?=

.PHONY: test-gateway test-gateway-shard-audit test-gateway-identity-gate \
	test-gateway-policy-gate test-gateway-fast test-gateway-all \
	test-gateway-coverage ci-compile ci-bootstrap-cheap ci-bootstrap setup-hooks \
	gateway-binaries gateway-binaries-consume gateway-hook-binary \
	gateway-hook-binary-consume gateway-provision gateway-hook-provision \
	ci-compile-products ci-compile-install-ax-cas \
	ci-compile-gate-hook ci-compile-precompile-gates ci-compile-ax \
	ci-skip-products ci-skip-install-ax-cas ci-skip-gate-hook \
	ci-skip-precompile-gates ci-skip-ax

SHARD_COUNT ?= 1
SHARD_INDEX ?= 0

# Landing-required gateway test policy (plan Phase 2 / E4, R13c — Phase 3
# re-tiering) — committed contract. RequiredPolicy = $(LANDING_POLICY) — the
# ONLY origin of the landing lane; never derived from `ls`. The policy check is
# UNCONDITIONAL (fires in ALL and EMPTY modes alike; the coverage-plane EMPTY
# shortcut below does not bypass it).
LANDING_POLICY ?= config/policy/landing_required_gateway_tests.json
GATEWAY_JUNIT_DIR ?= build/gateway-junit-dir

# Coverage plane (plan Phase 3) — tests moved OUT of the landing lane live in
# tests/gateway_coverage/ and run via the local-only `make test-gateway-coverage`
# target. Their junit is never consumed by CI gates.
GATEWAY_COVERAGE_DIR ?= tests/gateway_coverage

# ── Landing-lane binary products (B1: one minting authority per arch) ─────────
# The 9 products the landing lane consumes (test-gateway + test-gateway-shard-audit)
# and the 1 product the cheap bootstrap tail consumes (bin/setup-hooks).
# Previously each of the 8 gateway-shard legs recompiled all of them (80 duplicate
# compiles per PR). The minting producer is the arch-matched producer job
# (runner-pool-acceptance candidate-build-arm — arm); consumers declare
# AXIOM_GATEWAY_BINARIES=consume and ASSERT presence instead of recompiling.
# Arch boundary is load-bearing: x64 ci-bootstrap products cannot execute on arm,
# so the two producers stay separate (never collapsed into one global producer).
# The commands below are the historical per-shard commands verbatim — same source,
# same flags, same order — so the R1-fast lane invariant ("same compile commands,
# same flags, same runner") is preserved by construction, not by convention.
GATEWAY_LANDLANE_PRODUCTS := bin/run_gate bin/nimtry build/git_wrapper \
	build/command_policy_gate bin/hotspot_coverage_gate bin/conflict_marker_gate \
	bin/golden_master_gate bin/all_gateway_runner bin/impact_closure_selector
GATEWAY_HOOK_PRODUCTS := bin/setup-hooks

# Provisioning mode — ONE declared switch with exactly two meanings:
#   mint    (default) this job is a producer: compile every product.
#   consume           the producer's artifact is the authority: compile 0 and
#                     assert every product present + executable (fail-closed).
# There is no third meaning and no silent-skip path: under 'consume' a missing
# product is a hard FAIL, because missing evidence is not a valid empty set
# (docs/spec/merge_admission_controller.md §2 "missing ≠ valid empty").
AXIOM_GATEWAY_BINARIES ?= mint
# The switch selects WHICH provisioning target the dispatcher depends on — a
# make-native dispatcher target, NOT a `NAME := target` variable referenced as
# `consumer: $(NAME)`. The execution-closure deriver
# (tools/ci/derive_checker_closure.nim — parseMakefile → walkMakeTarget) matches
# prerequisites LITERALLY (`if p in w.targets`), so a `$(VAR)` prerequisite is
# invisible to it: the consume-mode assertion the switch selected never reached
# the derived closure. That is an under-approximation (execution the closure
# could not see), and a make-native target is visible without relaxing the
# deriver. Same make semantics — exactly one of the two targets is ever run.
ifeq ($(AXIOM_GATEWAY_BINARIES),mint)
gateway-provision: gateway-binaries
gateway-hook-provision: gateway-hook-binary
else ifeq ($(AXIOM_GATEWAY_BINARIES),consume)
gateway-provision: gateway-binaries-consume
gateway-hook-provision: gateway-hook-binary-consume
else
$(error AXIOM_GATEWAY_BINARIES must be 'mint' or 'consume' (got '$(AXIOM_GATEWAY_BINARIES)'))
endif

# Shared assertion body — $(1) = provisioning label, $(2) = product list.
# Recursive variable, NOT `define` (same reason as GATEWAY_RECORDED_EMPTY_SCOPE
# below): parseMakefile registers only `NAME = value` variables whose name
# matches [A-Za-z0-9_]+, so a `define` body and this dashed name were both
# invisible to the deriver and `$(call …)` never expanded — the consume
# assertion's shell would be unattributable execution. The body stays inline
# shell (fully walked, not an opaque script member) and the reported count is
# computed by the shell from the same list it iterates, so `$(words …)` — a make
# function the deriver's shell model cannot evaluate — is no longer needed as a
# second source of truth for the same number.
GATEWAY_CONSUME_ASSERT = \
	for b in $(2); do \
	  n=$$((n+1)); \
	  if [ ! -s "$$b" ] || [ ! -x "$$b" ]; then \
	    echo "[AXIOM GATE] FAIL — $(1): landing-lane product absent or not executable: $$b"; \
	    echo "               AXIOM_GATEWAY_BINARIES=consume asserts the minting producer's"; \
	    echo "               artifact; absence is not a pass (compile=0 means download, not skip)."; \
	    exit 1; \
	  fi; \
	done; \
	echo "[AXIOM GATE] consume OK — $$n product(s) present and executable (compile=0)"

gateway-binaries: bin/impact_closure_selector ## Mint the 9 landing-lane products (producer only — arch-matched minting authority)
	@echo "[AXIOM GATE] Building gateway execution binaries (landing lane)..."
	nim c --hints:off -d:release -o:bin/run_gate src/cli/run_gate.nim
	nim c --hints:off -d:release -o:bin/nimtry src/gate/nimtry.nim
	nim c --hints:off -d:release -o:build/git_wrapper src/gate/utils/git_wrapper.nim
	nim c --hints:off -d:release -o:build/command_policy_gate src/gate/utils/command_policy_gate.nim
	nim c --hints:off -d:release -o:bin/hotspot_coverage_gate src/gate/runners/hotspot_coverage_gate.nim
	nim c --hints:off -d:release -o:bin/conflict_marker_gate src/gate/runners/conflict_marker_gate.nim
	nim c --hints:off -d:release -o:bin/golden_master_gate src/gate/runners/golden_master_gate.nim
	nim c --hints:off -d:release -o:bin/all_gateway_runner tests/gateway/all_gateway_runner.nim

gateway-binaries-consume: ## Assert the 9 landing-lane products came from the minting producer (no recompile)
	$(call GATEWAY_CONSUME_ASSERT,landing-lane,$(GATEWAY_LANDLANE_PRODUCTS))

# bin/setup-hooks is consumed by ci-bootstrap-cheap (the cheap bootstrap tail),
# which runs on BOTH producers: the x64 ci-bootstrap job and every arm
# gateway-shard leg. It is therefore provisioned separately from the 9 landing
# -lane products — minting the whole lane here would add 9 compiles to the x64
# bootstrap job that never consumes them.
gateway-hook-binary: bin/setup-hooks ## Mint bin/setup-hooks (producer only)

gateway-hook-binary-consume: ## Assert bin/setup-hooks came from the minting producer (no recompile)
	$(call GATEWAY_CONSUME_ASSERT,cheap-bootstrap-tail,$(GATEWAY_HOOK_PRODUCTS))

# Selector decision record (B4) — the ONLY recorded fact that may admit an empty
# landing-lane scope. Produced by the select job (runner-pool-acceptance
# "Upload decision record": decision.json + decision-report.json +
# oracle-evidence.json) and consumed here by both landing-lane gates.
# Absent record = no derivation = FAIL (never an implicit pass).
GATEWAY_DECISION_DIR ?= build/gateway-decision-dir

# Recorded empty-scope derivation (B4) — the ONE condition under which an empty
# landing-lane scope is admissible. Terminal admission invariant
# (docs/spec/verification_dag_contract.md §6): ExpectedNodes == AccountedNodes,
# and missing evidence classifies as NotExecuted = admission FAIL. Absent
# evidence is never a valid empty set (docs/spec/merge_admission_controller.md §2,
# "missing ≠ valid empty"). So the two sites that used to disagree converge on
# ONE rule:
#   selected set = ∅ DERIVED BY THE SELECTOR from verified independent-oracle
#     evidence (mode=none ∧ gatewayTestScope=EMPTY ∧ derivedEmpty=true) — an
#     explicit, recorded fact → recorded N/A, admissible
#     (ADR-0025 Amendment C §C.1.3 — "영향-공집합 후보는 floor 면제").
#   zero shards ACTUALLY RAN without that record → FAIL. Infrastructure not
#     executing is NotExecuted, not an empty set.
# Authority boundary (§2.6): derivationDigest verification belongs to the
# selector (loadOracleEvidence — invalid evidence forces exit 2 → full
# fallback, so an unverifiable derivation can never reach gatewayTestScope=EMPTY).
# This is a CONSUMER: it asserts the record is present, self-consistent and
# bound to the run's decisionHash. It never re-derives the verdict.
# Emits an auditable N/A record artifact ($(GATEWAY_DECISION_DIR)/gateway-na-record.xml)
# so the N/A is visible, never an absence (§0.9 silent skip 금지).
# Usage: $(call GATEWAY_RECORDED_EMPTY_SCOPE,<gate-label>)
# Recursive variable, NOT `define`: the execution-closure deriver
# (tools/ci/derive_checker_closure.nim — parseMakefile) only resolves `$(call …)`
# against `NAME = value` variables whose name matches [A-Za-z0-9_]+; a `define`
# body and a dashed name are both invisible to it, so the recipe text would be
# unattributable execution and the closure would fail closed. The body therefore
# stays inline shell (fully walked, not an opaque script member) and every
# failure is an explicit `|| { …; exit 1; }` — no helper function, no
# `command -v` (the deriver's shell model has no command-word position for a
# `command -v` argument list). Same semantics, statically attributable form.
GATEWAY_RECORDED_EMPTY_SCOPE = \
	dd="$(GATEWAY_DECISION_DIR)"; \
	test -s "$$dd/decision.json" || { echo "[$(1)] FAIL — no recorded selector decision ($$dd/decision.json): zero shards ran and nothing derived the empty selection — absent evidence is not a valid empty set (NotExecuted = admission FAIL)"; exit 1; }; \
	test -s "$$dd/oracle-evidence.json" || { echo "[$(1)] FAIL — no recorded oracle evidence ($$dd/oracle-evidence.json): the empty-scope exemption requires verified independent-oracle evidence (derivedEmpty=true)"; exit 1; }; \
	jq -n true >/dev/null 2>&1 || { echo "[$(1)] FAIL — jq unavailable — the recorded derivation cannot be verified (fail-closed)"; exit 1; }; \
	jq -e '.mode == "none"' "$$dd/decision.json" >/dev/null || { echo "[$(1)] FAIL — decision.json mode is not 'none'"; exit 1; }; \
	jq -e '.gatewayTestScope == "EMPTY"' "$$dd/decision.json" >/dev/null || { echo "[$(1)] FAIL — decision.json gatewayTestScope is not 'EMPTY'"; exit 1; }; \
	jq -e '.derivedEmpty == true' "$$dd/decision.json" >/dev/null || { echo "[$(1)] FAIL — decision.json does not carry derivedEmpty=true"; exit 1; }; \
	jq -e '.shards == []' "$$dd/decision.json" >/dev/null || { echo "[$(1)] FAIL — decision.json declares a non-empty shard set"; exit 1; }; \
	jq -e '.oracleEvidence.oracleId == "axiom/oracle-evidence/v1" and .oracleEvidence.derivedEmpty == true and (.oracleEvidence.derivationDigest | test("^[0-9a-f]{64}$$"))' "$$dd/decision.json" >/dev/null || { echo "[$(1)] FAIL — decision.json oracleEvidence binding missing or malformed"; exit 1; }; \
	jq -e '.schema == "axiom/oracle-evidence/v1" and .derivedEmpty == true' "$$dd/oracle-evidence.json" >/dev/null || { echo "[$(1)] FAIL — oracle-evidence.json schema/derivedEmpty mismatch"; exit 1; }; \
	if [ -n "$$EXPECTED_GATEWAY_DECISION_HASH" ]; then \
	  dhash=$$(sha256sum "$$dd/decision.json" | cut -d' ' -f1); \
	  test "$$dhash" = "$$EXPECTED_GATEWAY_DECISION_HASH" || { echo "[$(1)] FAIL — decision.json sha256 ($$dhash) != this run's decisionHash ($$EXPECTED_GATEWAY_DECISION_HASH) — the record is not this run's decision"; exit 1; }; \
	fi; \
	mkdir -p "$$dd"; \
	printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
	  '<testsuites name="gateway-empty-scope-na" tests="1" failures="0" errors="0" skipped="1">' \
	  '  <testsuite name="landing-lane-empty-scope" tests="1" skipped="1">' \
	  '    <testcase classname="notApplicable" name="landing-required-set-empty-scope">' \
	  '      <skipped message="selector-derived empty selection (mode=none, gatewayTestScope=EMPTY, oracle evidence derivedEmpty=true) — landing-required set accounted as RECORDED N/A, not executed"/>' \
	  '    </testcase>' \
	  '  </testsuite>' \
	  '</testsuites>' > "$$dd/gateway-na-record.xml"; \
	echo "[$(1)] RECORDED N/A — empty landing-lane scope derived by the selector (mode=none, shards=[], oracle evidence derivedEmpty=true); landing-required set accounted as N/A, ExpectedNodes == AccountedNodes"; \
	echo "[$(1)] auditable record → $$dd/gateway-na-record.xml (decision.json sha256=$$(sha256sum "$$dd/decision.json" | cut -d' ' -f1))"

# Policy-file parse used by every landing-lane consumer (file list derivation,
# test-gateway preflight, shard audit). Fail-closed: missing/unreadable policy,
# missing/empty tests[], empty testPath, or unresolvable testPath → exit 1 and
# NO output, so every consumer that derives from it fails loudly. Implemented
# as a path command (bin/impact_closure_selector --policy-files) for
# test-gateway/test-gateway-shard-audit — the closure deriver resolves the
# binary via the file-target product rule below. The gate targets
# (test-gateway-identity-gate/test-gateway-policy-gate) run in CI workspaces
# WITHOUT a Nim toolchain, so they parse the policy inline (shell grep/cut/awk)
# with the same fail-closed semantics.

# Landing-lane test list — the COMMITTED POLICY SET derived from
# $(LANDING_POLICY) (SSOT). `ls` 파생 금지 (plan E4/R13c).
# test-gateway/test-gateway-shard-audit derive it from the selector binary
# INSIDE the recipe shell:
#   files=$$(bin/impact_closure_selector --policy-files "$(LANDING_POLICY)")
# The gate targets (no Nim toolchain in that CI job) parse the same JSON
# inline with the equivalent fail-closed shell extraction.
# (no make-level $(shell python...) — statically derivable, deterministic).

# Gateway shard selection — single source of the CI shard split (landing lane).
# Deterministic positional (NR) modulo assignment over the lexically sorted
# POLICY list (computed in-recipe from the --policy-files output, sorted again
# for byte-identical parity with the legacy pipeline) — in CI the executed set
# == RequiredPolicy by construction (Phase 3; plan E4 `ls`-파생 집합 0곳).
# SHARD_COUNT=1 (default) selects ALL policy tests. Shared by test-gateway
# (execution) and test-gateway-shard-audit (partition identity) so the split
# cannot diverge.

# Policy selector binary — file-target product rule: lets the closure deriver
# resolve bin/impact_closure_selector as a generated product (source → binary)
# and gives make a rebuild dependency. It is a prerequisite of gateway-binaries
# (the minting producer), so fresh checkouts build it before any consumer runs.
bin/impact_closure_selector: tools/ci/impact_closure_selector.nim
	$(NIM) c $(NIM_TOOL_FLAGS) -o:$@ $<

test-gateway: gateway-provision ## landing lane — committed policy set (LG-001..014, §0.7 비즈니스 BDD)
	@bin/impact_closure_selector --policy-files "$(LANDING_POLICY)" >/dev/null || { echo "[AXIOM GATE] FAIL — landing policy unreadable/invalid: $(LANDING_POLICY)"; exit 1; }
	@echo "[AXIOM GATE] Running Gateway Business Test Suite (landing policy set)..."
	@files=$$(bin/impact_closure_selector --policy-files "$(LANDING_POLICY)"); \
	sel=$$(printf '%s\n' "$$files" | sed '/^$$/d' | sort | awk -v s=$(SHARD_INDEX) -v n=$(SHARD_COUNT) 'NR % n == s'); \
	test -n "$$sel" || { echo "[AXIOM GATE] FAIL — empty shard selection (SHARD_INDEX=$(SHARD_INDEX), SHARD_COUNT=$(SHARD_COUNT)): an empty selection would widen to the whole landing lane — refusing (fail-closed)"; exit 1; }; \
	AXIOM_JOBS=$(if $(filter $(AXIOM_CI),1),2,$(shell nproc)) ./bin/all_gateway_runner --skip-known-failing=config/known_failing_gateway.txt --probe-known-failing --junit-output=build/gateway-junit.xml $$sel


# Machine-checked partition identity for the CI shard split (landing lane):
#   union(shards) == landing policy set, and pairwise intersections == ∅.
# sum==total && duplicates==0 is the exact partition predicate (any file twice
# forces duplicates>0; any omission forces sum<total). Fail-closed.
# NOTE: this static audit alone is INSUFFICIENT — it verifies the partition
# formula but not that the runner actually executed those files. See
# test-gateway-identity-gate for the post-execution gate that closes this gap.
test-gateway-shard-audit: gateway-provision
	@files=$$(bin/impact_closure_selector --policy-files "$(LANDING_POLICY)") || { echo "[shard-audit] FAIL — landing policy unreadable/invalid or empty: $(LANDING_POLICY)"; exit 1; }; \
	total=$$(printf '%s\n' "$$files" | sed '/^$$/d' | wc -l); \
	test "$$total" -gt 0 || { echo "[shard-audit] FAIL — landing policy unreadable/invalid or empty: $(LANDING_POLICY)"; exit 1; }; \
	union=$$(mktemp); \
	sum=0; \
	$(foreach i,$(shell seq 0 $$(($(SHARD_COUNT)-1))),sel=$$(printf '%s\n' "$$files" | sed '/^$$/d' | sort | awk -v s=$(i) -v n=$(SHARD_COUNT) 'NR % n == s'); cnt=$$(printf '%s\n' "$$sel" | sed '/^$$/d' | wc -l); sum=$$((sum+cnt)); printf '%s\n' $$sel >> $$union;) \
	dups=$$(sed '/^$$/d' $$union | sort | uniq -d | wc -l); \
	echo "[shard-audit] policy_total=$$total shards_sum=$$sum duplicate_files=$$dups"; \
	test "$$sum" -eq "$$total" && test "$$dups" -eq 0 || { echo "[shard-audit] FAIL — partition identity violated (landing policy set)"; rm -f $$union; exit 1; }; \
	echo "[shard-audit] OK — union == landing policy set ($$total tests), pairwise disjoint ($(SHARD_COUNT) shards)"; \
	rm -f $$union

# Post-execution identity-set gate: verifies that the JUnit output from
# all shard runs covers the LANDING POLICY SET (union == policy set,
# plan Phase 3 re-tiering — the 86/`ls` universe is historical) with no
# duplicates across shards (pairwise disjoint). This closes the gap where a
# static partition audit can pass while the actual execution produces a
# different result (see DEBT#418).
# Usage: make test-gateway-identity-gate SHARD_COUNT=8 [EXPECTED_GATEWAY_TESTS=ALL|EMPTY]
# A3 (2026-09-23) generalization — Phase 3 re-tiered:
#   EXPECTED_GATEWAY_TESTS unset (or 'ALL') → union == landing policy set check
#   (14 items; used by mode=full / tag / select-failure → full fallback paths).
#   The policy file (config/policy/landing_required_gateway_tests.json) is
#   authoritative — the env token only selects expected-mode semantics, it does
#   not define the set.
#   EXPECTED_GATEWAY_TESTS='EMPTY' → the selector derived an EMPTY scope
#   (mode=none: no work unit selected AND verified independent-oracle evidence
#   derivedEmpty=true). An empty scope is admissible ONLY when that derivation is
#   RECORDED and bound to this run's decisionHash (ci-select-decision artifact →
#   $(GATEWAY_DECISION_DIR)); the gate emits an auditable N/A record artifact
#   from it. Zero shards that ran WITHOUT that record is FAIL — infrastructure
#   not executing is NotExecuted, not a valid empty set (DEBT#470; ADR-0025
#   Amendment C §C.1.3). `if: always()` still holds the lane open — but an
#   empty scope now has to say WHY, on the record. Any other value →
#   fail-closed (unknown scope token).
#   mode=selected: W8 is unit-granular → scope is the full policy set → 'ALL'.
# Expects junit artifacts downloaded to $(GATEWAY_JUNIT_DIR) — declared once at
# ci/checker.mk:49 as `GATEWAY_JUNIT_DIR ?= build/gateway-junit-dir`. That path
# is the variable's DEFAULT value, not a fixed location: the recipe reads the
# variable, so `make ... GATEWAY_JUNIT_DIR=<path>` relocates the globbed source
# junit tree. Layout inside that directory: one subdirectory per shard, each
# containing gateway-junit.xml.
# Phase 2 (plan E4/R13c): 이 타깃은 마지막에 test-gateway-policy-gate를
# 무조건 체이닝한다 — 착지 집합(RequiredPolicy)은 coverage 평면의 EMPTY/ALL
# 단축과 무관하게 항상 검증된다. EMPTY 모드에서 정책 항목이 실행되지 않았다면
# policy-gate는 SELECTOR가 기록한 파생(기록 부재 시 FAIL — 위 EMPTY 규칙 참조)
# 이 있을 때만 이를 N/A로 계정처리하고, 없으면 FAIL한다 (착지 집합은 무조건
# 실행되거나, 근거가 기록된 N/A로 계정되어야 한다 — 워크플로 측 실행 보장은 별도
# 보고 항목).
# NOTE: 이 타깃과 test-gateway-policy-gate는 Nim 툴체인이 없는 CI 워크스페이스
# (gateway-identity-gate job)에서 실행된다 — guard-build는 Error 127을 낸다.
# 두 타깃은 반드시 pure shell(bash)로 유지하고 bin/impact_closure_selector를
# 사용하지 않는다. 정책 리스트는 $(LANDING_POLICY)에서 grep/cut으로 파싱하며,
# 추출 0건·testPath 미존재·포맷 불일치 → exit 1 (fail-closed).
# testPath 실존 검증은 `find -L -maxdepth 0 -type f`(≡ [ -f ]) + comm -23으로
# 일괄 수행한다 (deriver grammar는 레시피의 while/case/mapfile/<<</continue를 거부).
test-gateway-identity-gate:
	@set -euo pipefail; \
	policy_file="$(LANDING_POLICY)"; \
	test -f "$$policy_file" || { echo "[identity-gate] FAIL — landing policy unreadable/invalid or empty: $$policy_file" >&2; exit 1; }; \
	files=$$(grep -o '"testPath": *"[^"]*"' "$$policy_file" | cut -d'"' -f4 | sort) || { echo "[identity-gate] FAIL — landing policy unreadable/invalid or empty: $$policy_file" >&2; exit 1; }; \
	total=$$(printf '%s\n' "$$files" | sed '/^$$/d' | wc -l); \
	test "$$total" -gt 0 || { echo "[identity-gate] FAIL — landing policy unreadable/invalid or empty: $$policy_file" >&2; exit 1; }; \
	bad_paths=$$(comm -23 <(printf '%s\n' "$$files" | sed '/^$$/d' | sort) <(printf '%s\n' "$$files" | sed '/^$$/d' | tr '\n' '\0' | xargs -r -0 -I{} find -L {} -maxdepth 0 -type f 2>/dev/null | sort)); \
	if [ -n "$$bad_paths" ]; then \
	  printf '%s\n' "$$bad_paths" | sed 's/^/[identity-gate] FAIL — landing policy testPath does not resolve: /'; \
	  exit 1; \
	fi; \
	expected="$${EXPECTED_GATEWAY_TESTS:-ALL}"; \
	junit_dir="$$(mktemp -d)"; \
	trap 'rm -rf "$$junit_dir"' EXIT; \
	for f in "$(GATEWAY_JUNIT_DIR)"/gateway-junit-shard-*/gateway-junit.xml; do \
	  if [ -f "$$f" ]; then \
	    grep -ho 'classname="run" name="[^"]*"' "$$f" 2>/dev/null | sed 's/classname="run" name="//;s/"$$//' >> "$$junit_dir/all_names.txt" || true; \
	  fi; \
	done; \
	all_names=$$(sort "$$junit_dir/all_names.txt" 2>/dev/null || true); \
	unique_names=$$(printf '%s\n' "$$all_names" | sed '/^$$/d' | sort -u); \
	entry_count=$$(printf '%s\n' "$$all_names" | sed '/^$$/d' | wc -l); \
	unique_count=$$(printf '%s\n' "$$unique_names" | sed '/^$$/d' | wc -l); \
	dups=$$(printf '%s\n' "$$all_names" | sed '/^$$/d' | sort | uniq -d | wc -l); \
	missing=$$(comm -23 <(printf '%s\n' "$$files" | sed '/^$$/d' | sed 's|.*/||;s|\.nim$$||' | sort) <(printf '%s\n' "$$unique_names" | sed '/^$$/d' | sort) | wc -l); \
	echo "[identity-gate] expected=$$expected entries=$$entry_count unique=$$unique_count duplicates=$$dups missing_from_executed=$$missing policy_total=$$total"; \
	if [ "$$expected" = "EMPTY" ]; then \
	  test "$$entry_count" -eq 0 || { echo "[identity-gate] FAIL — EMPTY scope: $$entry_count junit entries (expected 0)"; exit 1; }; \
	  $(call GATEWAY_RECORDED_EMPTY_SCOPE,identity-gate) ; \
	  echo "[identity-gate] OK — empty scope is selector-derived and RECORDED (not an implicit pass)"; \
	elif [ "$$expected" = "ALL" ]; then \
	  test "$$entry_count" -eq "$$total" && test "$$dups" -eq 0 && test "$$missing" -eq 0 || { echo "[identity-gate] FAIL — identity set violated (landing policy set)"; exit 1; }; \
	  echo "[identity-gate] OK — executed set == landing policy set ($$total/$$total), pairwise disjoint"; \
	else \
	  echo "[identity-gate] FAIL — unknown EXPECTED_GATEWAY_TESTS: $$expected"; exit 1; \
	fi; \
	rm -rf "$$junit_dir"; \
	$(MAKE) -f ci/checker.mk test-gateway-policy-gate

# Landing-required set membership gate (plan Phase 2 산출물 3 / E4, R13c) —
# unconditional post-execution contract, fires in ALL and EMPTY modes alike.
# RequiredPolicy = $(LANDING_POLICY) (SSOT — `ls` 파생 금지).
#   ∀ r ∈ RequiredPolicy:
#       r resolves successfully (testPath 트리 존재)
#     ∧ r ∈ Executed (junit run-suite에 basename 존재)
#     ∧ r 무실패 (해당 junit testcase에 <failure> 없음)
#     ∧ no duplicate policy identity (policyId·testPath 각각 유일)
# mustRef 참조체크: INV-1..INV-13 (certification_continuity_contract.md §5) /
# R1..R8 (config/readiness_policy.json) 실존 id만 허용. mustRef="UNRESOLVED"는
# Phase-3 semantic proof 대기 후보로 별도 취급 — justification이 정확히
# "candidate pending Phase-3 semantic proof"일 때만 허용 (이후 단계 게이트가
# 편입/기각 확정). 정책원본 테스트 삭제 시뮬레이션 = resolution FAIL (E4).
# Junit 없음(junit_files=0) = 전 항목 not-executed → FAIL — 착지 집합은
# 스코프 선택기와 무관하게 실행되어야 한다. 유일한 예외: EMPTY 스코프에서
# selector가 기록한 파생(decision.json mode=none ∧ gatewayTestScope=EMPTY ∧
# oracle evidence derivedEmpty=true, 이 run의 decisionHash에 결속)이 있으면
# 각 항목을 RECORDED N/A로 계정처리한다 (ExpectedNodes == AccountedNodes —
# B4 규칙, ADR-0025 Amendment C §C.1.3). 기록 부재/불일치 = FAIL.
# Usage: make test-gateway-policy-gate [LANDING_POLICY=...] [GATEWAY_JUNIT_DIR=...]
# Implemented as a pure-shell recipe (bash, no Nim) — exact behavioral port of
# the former inline python (later bin/impact_closure_selector --policy-gate).
# The gateway-identity-gate CI job has no Nim toolchain (guard-build → Error
# 127), so this target must stay statically derivable shell; policy entries are
# parsed per-object with awk over the machine-generated JSON (indent=2).
# Per-entry validation (incomplete/mustRef/UNRESOLVED-justification/testPath/
# junit membership) is ONE inline awk over the derived records — the closure
# deriver grammar rejects recipe-level while/case/<<</continue/mapfile, so the
# entry iteration lives inside awk; testPath existence is precomputed into
# tmpdir/badpaths.txt via `find -L -maxdepth 0 -type f` (≡ [ -f ]) + comm -23.
test-gateway-policy-gate:
	@set -euo pipefail; \
	policy_file="$(LANDING_POLICY)"; \
	junit_dir="$(GATEWAY_JUNIT_DIR)"; \
	na_mode=0; \
	if [ "$${EXPECTED_GATEWAY_TESTS:-ALL}" = "EMPTY" ]; then \
	  $(call GATEWAY_RECORDED_EMPTY_SCOPE,policy-gate) ; \
	  na_mode=1; \
	fi; \
	test -f "$$policy_file" || { echo "[policy-gate] FAIL - landing policy unreadable: $$policy_file" >&2; exit 1; }; \
	grep -q '^[[:space:]]*"tests"[[:space:]]*:[[:space:]]*\[' "$$policy_file" || { echo "[policy-gate] FAIL — tests[] missing or not a list"; exit 1; }; \
	entry_opens=$$(grep -c '^    {' "$$policy_file" || true); \
	test "$$entry_opens" -gt 0 || { echo "[policy-gate] FAIL — tests[] empty (landing-required set cannot be empty)"; exit 1; }; \
	tmpdir="$$(mktemp -d)"; \
	trap 'rm -rf "$$tmpdir"' EXIT; \
	: > "$$tmpdir/executed.raw"; : > "$$tmpdir/failed.raw"; \
	junit_cnt=$$(find "$$junit_dir" -type f -name 'gateway-junit.xml' 2>/dev/null | wc -l | tr -d ' ' || true); \
	find "$$junit_dir" -type f -name 'gateway-junit.xml' 2>/dev/null -exec grep -ho 'classname="run" name="[^"]*"' {} \; | sed 's/classname="run" name="//;s/"$$//' | sed '/^$$/d' >> "$$tmpdir/executed.raw" || true; \
	find "$$junit_dir" -type f -name 'gateway-junit.xml' 2>/dev/null -exec awk '/<testcase / { in_tc = 1; tc = $$0 } in_tc && (/<\/testcase>/ || /\/>/) { if (tc ~ /<failure/) { if (match(tc, /classname="run"[[:space:]]+name="[^"]*"/)) { n = substr(tc, RSTART, RLENGTH); sub(/^classname="run"[[:space:]]+name="/, "", n); sub(/"$$/, "", n); print n } } in_tc = 0; next } in_tc { tc = tc "\n" $$0 }' {} \; >> "$$tmpdir/failed.raw" || true; \
	sort -u -o "$$tmpdir/executed.raw" "$$tmpdir/executed.raw"; \
	sort -u -o "$$tmpdir/failed.raw" "$$tmpdir/failed.raw"; \
	executed_cnt=$$(wc -l < "$$tmpdir/executed.raw" | tr -d ' '); \
	failed_cnt=$$(wc -l < "$$tmpdir/failed.raw" | tr -d ' '); \
	echo "[policy-gate] junit_files=$$junit_cnt executed(run)=$$executed_cnt failed=$$failed_cnt"; \
	records=$$(awk '/^    [{]/ { in_entry = 1; pid = ""; must = ""; tp = ""; just = ""; next } in_entry && /"policyId"[[:space:]]*:[[:space:]]*"/ { v = $$0; sub(/^[[:space:]]*"policyId"[[:space:]]*:[[:space:]]*"/, "", v); sub(/"[[:space:]]*,?[[:space:]]*$$/, "", v); pid = v; next } in_entry && /"mustRef"[[:space:]]*:[[:space:]]*"/ { v = $$0; sub(/^[[:space:]]*"mustRef"[[:space:]]*:[[:space:]]*"/, "", v); sub(/"[[:space:]]*,?[[:space:]]*$$/, "", v); must = v; next } in_entry && /"testPath"[[:space:]]*:[[:space:]]*"/ { v = $$0; sub(/^[[:space:]]*"testPath"[[:space:]]*:[[:space:]]*"/, "", v); sub(/"[[:space:]]*,?[[:space:]]*$$/, "", v); tp = v; next } in_entry && /"justification"[[:space:]]*:[[:space:]]*"/ { v = $$0; sub(/^[[:space:]]*"justification"[[:space:]]*:[[:space:]]*"/, "", v); sub(/"[[:space:]]*,?[[:space:]]*$$/, "", v); just = v; next } in_entry && /^    [}][[:space:]]*,?[[:space:]]*$$/ { print pid "\t" must "\t" tp "\t" just; in_entry = 0; next }' "$$policy_file") || true; \
	n_records=$$(printf '%s\n' "$$records" | sed '/^$$/d' | wc -l); \
	test "$$n_records" -eq "$$entry_opens" || { echo "[policy-gate] FAIL — malformed test entry (not an object)"; exit 1; }; \
	dup_ids=$$(printf '%s\n' "$$records" | cut -f1 | sort | uniq -d || true); \
	dup_paths=$$(printf '%s\n' "$$records" | cut -f3 | sort | uniq -d || true); \
	dups=$$({ printf '%s\n' $${dup_ids:+$$dup_ids}; printf '%s\n' $${dup_paths:+$$dup_paths}; } | awk 'NF' | paste -sd, - | sed 's/,/, /g'); \
	if [ -n "$$dups" ]; then \
	  echo "[policy-gate] FAIL — duplicate policy identity: $$dups"; \
	fi; \
	comm -23 <(printf '%s\n' "$$records" | cut -f3 | sed '/^$$/d' | sort) <(printf '%s\n' "$$records" | cut -f3 | sed '/^$$/d' | tr '\n' '\0' | xargs -r -0 -I{} find -L {} -maxdepth 0 -type f 2>/dev/null | sort) > "$$tmpdir/badpaths.txt"; \
	printf '%s\n' "$$records" | awk -v execf="$$tmpdir/executed.raw" -v failf="$$tmpdir/failed.raw" -v badf="$$tmpdir/badpaths.txt" -v probsf="$$tmpdir/probs.txt" -v na="$$na_mode" 'BEGIN { for (; (getline l < execf) > 0;) executed[l] = 1; close(execf); for (; (getline l < failf) > 0;) failed[l] = 1; close(failf); for (; (getline l < badf) > 0;) bad[l] = 1; close(badf) } { split($$0, f, "\t"); pid = f[1]; must = f[2]; tp = f[3]; just = f[4]; probs = ""; if (pid == "" || must == "" || tp == "" || just == "") probs = probs sprintf("%s\t%s\n", pid, "incomplete entry (policyId/mustRef/testPath/justification required)"); if (must !~ /^(UNRESOLVED|INV-(1|2|3|4|5|6|7|8|9|10|11|12|13)|R[1-8])$$/) probs = probs sprintf("%s\t%s\n", pid, "mustRef not in INV-1..13 / R1..R8: " must); if (must == "UNRESOLVED" && just != "candidate pending Phase-3 semantic proof") probs = probs sprintf("%s\t%s\n", pid, "UNRESOLVED must carry the exact Phase-3-pending justification"); jname = ""; if (tp == "" || (tp in bad)) probs = probs sprintf("%s\t%s\n", pid, "testPath does not resolve: " tp); else { jname = tp; sub(/^.*\//, "", jname); sub(/\.[^.]*$$/, "", jname); if (na == "1") naacct[pid] = jname; else if (!(jname in executed)) probs = probs sprintf("%s\t%s\n", pid, "not executed (junit run-suite missing): " jname); else if (jname in failed) probs = probs sprintf("%s\t%s\n", pid, "executed but failing: " jname) } pidr[NR] = pid; if (probs == "" && na == "1") okline[NR] = sprintf("[policy-gate] %s %s mustRef=%s — N/A (recorded empty scope: selector-derived mode=none, oracle evidence derivedEmpty=true)", pid, jname, must); else if (probs == "") okline[NR] = sprintf("[policy-gate] %s %s mustRef=%s — OK", pid, jname, must); else { probpid[pid] = 1; allprobs = allprobs probs } } END { for (i = 1; i <= NR; i++) if (okline[i] != "" && !(pidr[i] in probpid)) print okline[i]; n = split(allprobs, pl, "\n"); for (i = 1; i <= n; i++) if (pl[i] != "") { p = pl[i]; q = pl[i]; sub(/\t.*$$/, "", p); sub(/^[^\t]*\t/, "", q); print "[policy-gate] FAIL — " p ": " q } printf "%s", allprobs > probsf; close(probsf) }'; \
	if [ -n "$$dups" ] || [ -s "$$tmpdir/probs.txt" ]; then \
	  echo "[policy-gate] FAIL — landing-required set violated (fail-closed)"; exit 1; \
	fi; \
	if [ "$$na_mode" = "1" ]; then \
	  echo "[policy-gate] OK — every landing-required item resolved and ACCOUNTED as recorded N/A under the selector-derived empty scope ($$n_records items, ExpectedNodes == AccountedNodes)"; \
	else \
	  echo "[policy-gate] OK — every landing-required test resolved and executed without failure ($$n_records items)"; \
	fi

# AXIOM_HERMETIC_BUILDING marks the hermetic build sandbox (see
# src/gate/config.nims): its role is reduced to preventing re-entry
# inside the build process only (no longer a runtime gating mechanism).
# On a fresh checkout bin/ax does not exist yet, so the
# guarded-domain integrity check must not fire while bootstrap itself
# is producing the artifact. Without this, ci-bootstrap depends on stale
# workspace state (nondeterministic clean-CI pass).
#
# Parallel safety (DEBT#481 shape, applied here in its simpler form):
#   1. ISOLATION FIRST — each product gets its own nimcache. The 4 sources are
#      mutually non-importing (gate_hook/precompile_gates/main/install_ax_cas
#      share no module), so no product can observe another's objects.
#   2. THEN fan out. install_ax_cas (the smallest product) stays SERIAL and runs
#      first: on a fresh checkout config.nims materializes
#      src/generated/build_env.nim (vendors.nims seeds it, the seed guard
#      injects the live BuildSourceHash) — a single file every `nim c` writes.
#      Running one product first closes that shared-write window by
#      construction; the canonical-bootstrap contract in
#      .github/actions/setup-axiom-toolchain/action.yml requires the same
#      ordering ("build_env.nim must exist before nimble compiles anything").
# The fan out is make-native (one target per product), not a shell subshell
# swarm: make itself is the fail-closed join (a failed product aborts the build,
# so no per-product status file can go missing — the shell form needed one and
# still had to prove absence was an error), and each compile recipe stays a
# bare `nim c …` line that the execution-closure deriver can attribute to its
# source. A `( … ) &` background subshell with per-job log redirection is
# statically unattributable and was rejected by the closure oracle
# (`PATH 미지 실행 이름: '('` + a lost `bin/ax → src/cli/main.nim` product map).
# `make ci-compile -j4` fans out (CI runs it that way); plain `make ci-compile`
# is the same order, serial. ci-bootstrap forwards the same -j4 to this fan-out
# (job1 build-base-artifacts reaches this path via `make ci-bootstrap`,
# admission-check.yml — previously serial there, the only CI entry point that
# missed the fan-out). ci-bootstrap-cheap stays serial: its steps are strictly
# sequential (install_ax_cas -> setup-hooks -> scope hash -> baseline check).
# ── S5 build-skip switch (data/ci_pareto/selection_table.json S5 — J3 공급 재사용) ──
# B-캐시 HIT 레인에서 `make ci-compile`의 4종 재컴파일(웜 레인 86–102s 실측)을
# 생략한다. 계약 (J3: 스킵은 검증된 공급 재사용일 뿐 — 판정은 항상 재계산):
#   1. 호출자(runner-pool-acceptance ci-bootstrap)가 B-verify(4종 SourceCoherence
#      probe, #577 — keygen b-identity의 trusted tree에 대한 재실행)를 통과시켰을
#      때만 AXIOM_S5_BUILD_SKIP=1을 넘긴다. 미설정(로컬·미검증 레인) = 종전
#      컴파일 그대로.
#   2. 이 스위치는 ASSERTION이다 — bypass가 아니다. skip 타깃은 생략된 각
#      바이너리의 SourceCoherence(내장 BuildSourceHash vs live src/ 재계산,
#      런타임 SSOT src/infrastructure/provenance_probe.nim)를 호출자 워크스페이스에서
#      재단언하며, 하나라도 실패하면 빌드를 중단한다 (fail-closed). 검증 없이
#      플래그를 설정한 호출자는 조용히 건너뛰는 게 아니라 크게 실패한다 — 결핍은
#      유효한 빈 집합이 아니다 (docs/spec/merge_admission_controller.md §2).
#   3. make는 조건 분기 중 하나만 읽고, 정적 closure deriver(parseMakefile)는
#      마지막 분기(컴파일)를 등록한다 — gateway-provision mint/consume 스위치와
#      동일한 make-native dispatcher 패턴 (이 파일 상단 주석 참조). 파생 closure는
#      항상 fail-closed 쪽(실제 컴파일)을 본다.
ifeq ($(AXIOM_S5_BUILD_SKIP),1)
ci-compile: ci-skip-install-ax-cas ci-skip-products ## S5 — B-verified supply reuse (skip re-asserts provenance, fail-closed)
else
ci-compile: ci-compile-install-ax-cas ci-compile-products ## Compile the 4 bootstrap tools (install_ax_cas serial, gate_hook/precompile_gates/ax in parallel — `make ci-compile -j4`)
endif

# install_ax_cas is a prerequisite of ci-compile-products as well, so make
# finishes it before any of the parallel group starts — the ordering the
# build_env.nim contract needs, enforced by the dependency graph.
ci-compile-products: ci-compile-install-ax-cas ci-compile-gate-hook ci-compile-precompile-gates ci-compile-ax

# ci-compile-hermetic-measure — the full hermetic pre-build pass, serially
# BEFORE the guarded compiles: it measures VerifierBuildId (64-hex) into
# src/generated/build_env.nim. AXIOM_HERMETIC_BUILDING=1 compiles skip
# hermeticPreBuild (config.nims), so without this step a cold CI build embeds
# the .default seed "unmeasured" — the state envelope's execution identity
# then never establishes (revalidateRestoredStateIdentity, defect 5) and the
# release binary fails the §1b campaign engineBuild guard. config.nims cannot
# run the tool itself (NimScript exec of compiled binaries is unreliable), so
# the measurement is wired here where make sees the exit code — fail-closed,
# unlike the seed-guard fallback. Referenced by all four compile targets so
# make (which dedups prerequisites) runs it exactly once before any fan-out.
# NOTE: keep comments OUT of recipe lines — derive_checker_closure parses every
# recipe line as a command token stream (walkMakeTarget → analyzeCommandTokens).
ci-compile-hermetic-measure:
	AXIOM_HERMETIC_BUILDING=1 $(NIM) c --hints:off -o:bin/hermetic_build tools/hermetic_build.nim
	bin/hermetic_build
	grep -qE 'VerifierBuildId\* = "[0-9a-f]{64}"' src/generated/build_env.nim || { echo "FAIL: VerifierBuildId not measured (64-hex) after hermetic_build"; exit 1; }

# S5 enforcement — 생략된 각 바이너리는 존재·실행 가능·provenance 일치를 재단언한다.
# probe 실패 = make 즉시 중단 (재컴파일 폴백은 호출자 eligibility 게이트의 소관이며,
# make 레벨 위반은 호출자 계약 버그다 — 조용한 스킵 금지).
ci-skip-products: ci-skip-install-ax-cas ci-skip-gate-hook ci-skip-precompile-gates ci-skip-ax

ci-skip-install-ax-cas:
	@echo "[S5] supply reuse — bin/install_ax_cas recompile skipped (B-verified payload; judgment recomputed)"
	bin/install_ax_cas --check-provenance

ci-skip-gate-hook:
	@echo "[S5] supply reuse — bin/gate_hook recompile skipped (B-verified payload; judgment recomputed)"
	bin/gate_hook --check-provenance

ci-skip-precompile-gates:
	@echo "[S5] supply reuse — bin/precompile_gates recompile skipped (B-verified payload; judgment recomputed)"
	bin/precompile_gates --check-provenance

ci-skip-ax:
	@echo "[S5] supply reuse — bin/ax recompile skipped (B-verified payload; judgment recomputed)"
	bin/ax --check-provenance

ci-compile-install-ax-cas: ci-compile-hermetic-measure
	AXIOM_HERMETIC_BUILDING=1 $(NIM) c --hints:off -o:bin/install_ax_cas src/cli/install_ax_cas.nim

ci-compile-gate-hook: ci-compile-hermetic-measure
	AXIOM_HERMETIC_BUILDING=1 $(NIM) c --hints:off --nimcache:$(CI_COMPILE_NIMCACHE)/gate_hook -o:bin/gate_hook src/gate/runners/gate_hook.nim

# precompile_gates: -d:release -d:axiomNoLto — the tool's hot path is 9.2MB .nim
# closure hashing (computeTransitiveSourceHash × 54 gates): debug builds spend
# ~192s/run there, release ~3.4s (~56×; measured 2026-11-09, warm-lane runs on
# 16-core x64, Nim 2.2.10/gcc 13.3.0). LTO adds no runtime gain for it
# (tool-side 3.3s w/ LTO vs 3.4s w/o) while costing link time + RSS on the
# runner — so the tool opts out with the existing axiomNoLto define
# (config.nims release block). Gate CAS keys are unaffected: computeCasKey
# inputs (gate source closure + computeBuildEnvHash: config.nims/axiom.nimble/
# toolchain) do not include this tool's build mode. B-fingerprint/manifest
# record the digest at build time (binding-only verify, flag-agnostic).
# NOTE: keep comments OUT of recipe lines — derive_checker_closure parses every
# recipe line as a command token stream (walkMakeTarget → analyzeCommandTokens).
ci-compile-precompile-gates: ci-compile-hermetic-measure
	AXIOM_HERMETIC_BUILDING=1 $(NIM) c -d:release -d:axiomNoLto --hints:off --nimcache:$(CI_COMPILE_NIMCACHE)/precompile_gates -o:bin/precompile_gates src/cli/precompile_gates.nim

ci-compile-ax: ci-compile-hermetic-measure
	AXIOM_HERMETIC_BUILDING=1 $(NIM) c -d:release --hints:off --nimcache:$(CI_COMPILE_NIMCACHE)/ax -o:bin/ax src/cli/main.nim

ci-bootstrap-cheap: ## Post-compile low-cost steps (install CAS, hooks, scope hash, baseline) — per-executor cheap tail of ci-bootstrap
	./bin/install_ax_cas
	$(MAKE) -f ci/checker.mk setup-hooks
	bin/ax scope hash
	bin/ax baseline check

ci-bootstrap: ## Build tools -> init hooks -> baseline (prerequisites for all steps)
	$(MAKE) -f ci/checker.mk ci-compile -j4
	$(MAKE) -f ci/checker.mk ci-bootstrap-cheap

# R1-fast (Slice 3a-L B): feedback-latency lane — the highest-signal gateway
# correctness test (run_gate_feature_test) as the FIRST verification surface of
# verify-integration-r1, so the same failure CI previously surfaced only after
# ~43m (39m preamble + 15m43s full gateway compile queue) is detected in
# minutes. T= selects the single test (same positional-filter mechanism the
# runner already supports). This target is a strict SUBSET of the landing lane:
# its three compiles are the first/second/eighth lines of gateway-binaries
# verbatim — same compile commands, same flags, same runner — plus the same
# --skip-known-failing policy; only the test list is filtered. R1-fast PASS
# implies nothing about R1-full; R1-full always runs afterwards in the same job.
T ?= tests/gateway/run_gate_feature_test.nim
test-gateway-fast: ## R1-fast — 단일 gateway correctness test (기본 run_gate_feature_test) / usage: make test-gateway-fast [T=tests/gateway/<test>.nim]
	@echo "[AXIOM GATE] R1-fast: building gateway fast-lane binaries..."
	@nim c --hints:off -d:release -o:bin/run_gate src/cli/run_gate.nim
	@nim c --hints:off -d:release -o:bin/nimtry src/gate/nimtry.nim
	@nim c --hints:off -d:release -o:bin/all_gateway_runner tests/gateway/all_gateway_runner.nim
	@echo "[AXIOM GATE] R1-fast: running $(T)..."
	@AXIOM_JOBS=$(if $(filter $(AXIOM_CI),1),2,$(shell nproc)) ./bin/all_gateway_runner --skip-known-failing=config/known_failing_gateway.txt --probe-known-failing --junit-output=build/gateway-junit.xml "$(T)"

test-gateway-all: ## 모든 gateway 테스트 실행 (landing policy + coverage — 86개, known-failing 포함, 디버그용)
	@echo "[AXIOM GATE] Running ALL Gateway Tests (landing policy + coverage, known-failing 포함)..."
	@nim c --hints:off -d:release -o:bin/all_gateway_runner tests/gateway/all_gateway_runner.nim
	@AXIOM_JOBS=$(if $(filter $(AXIOM_CI),1),2,$(shell nproc)) ./bin/all_gateway_runner --root=tests/gateway --root=$(GATEWAY_COVERAGE_DIR) --junit-output=build/gateway-junit.xml

# Non-landing coverage plane (plan Phase 3 / E8): the tests moved out of the
# landing lane run here, LOCAL-only — their junit (build/gateway-junit-coverage.xml)
# is never consumed by CI gates. Same runner/flags/prebuilt binaries as
# test-gateway (identical compile+run semantics), only the root and junit
# output differ.
test-gateway-coverage: ## coverage plane — tests/gateway_coverage/*_feature_test.nim (로컬, CI 미소비)
	@echo "[AXIOM GATE] Building gateway execution binaries..."
	@nim c --hints:off -d:release -o:bin/run_gate src/cli/run_gate.nim
	@nim c --hints:off -d:release -o:bin/nimtry src/gate/nimtry.nim
	@nim c --hints:off -d:release -o:build/git_wrapper src/gate/utils/git_wrapper.nim
	@nim c --hints:off -d:release -o:build/command_policy_gate src/gate/utils/command_policy_gate.nim
	@nim c --hints:off -d:release -o:bin/hotspot_coverage_gate src/gate/runners/hotspot_coverage_gate.nim
	@nim c --hints:off -d:release -o:bin/conflict_marker_gate src/gate/runners/conflict_marker_gate.nim
	@nim c --hints:off -d:release -o:bin/golden_master_gate src/gate/runners/golden_master_gate.nim
	@echo "[AXIOM GATE] Running Gateway Coverage Suite (tests/$(GATEWAY_COVERAGE_DIR) — non-landing plane)..."
	@nim c --hints:off -d:release -o:bin/all_gateway_runner tests/gateway/all_gateway_runner.nim
	@AXIOM_JOBS=$(if $(filter $(AXIOM_CI),1),2,$(shell nproc)) ./bin/all_gateway_runner --root=$(GATEWAY_COVERAGE_DIR) --skip-known-failing=config/known_failing_gateway.txt --probe-known-failing --junit-output=build/gateway-junit-coverage.xml $(shell ls $(GATEWAY_COVERAGE_DIR)/*_feature_test.nim)

bin/setup-hooks: tools/setup_hooks.nim
	$(NIM) c $(NIM_TOOL_FLAGS) -o:$@ $<

setup-hooks: gateway-hook-provision ## Configure git to use version-controlled hooks from .githooks/
	./bin/setup-hooks