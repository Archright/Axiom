# Environment Inputs Specification

**Status**: NORMATIVE  
**Created**: 2026-08-18  
**Version**: v1  
**Related**: AGENTS.md §0.6b, `src/core/trusted/env_types.nim`, `docs/spec/hermetic_gate_framework.md`, `docs/spec/repository_state_model.md`

---

## Principle

> Declared inputs are normative; undeclared inputs are not permitted to affect canonical execution semantics. No unaudited ambient input may influence a gate verdict on any path — verdicts are shaped only by declared, audited surfaces (manifest-declared gate contracts and explicit CLI flags). DEBT#478 closure (2026-10-07): `AXIOM_GATE_SEVERITY`, `AXIOM_REBASELINE` and `AXIOM_UPDATE_BASELINE` were removed from the DECLARED registry and from `EnvVar`; rebaselining survives exclusively as the sanctioned `--rebaseline` CLI flag threaded explicitly to gate argv.

All environment variables consumed by Axiom fall into exactly one of three categories. Variables not listed in DECLARED or IMPLICITLY_ALLOWED are FORBIDDEN_TO_AFFECT_SEMANTICS.

---

## §1. Classification Structure

| Category | Scope | Effect on Canonical Execution |
|----------|-------|-------------------------------|
| DECLARED | Explicitly enumerated below | Defined behavior; values influence semantics per documented contract |
| IMPLICITLY_ALLOWED | Standard POSIX/system variables | Non-semantic usage only (paths, locale); values do NOT alter verification logic |
| FORBIDDEN_TO_AFFECT_SEMANTICS | All other environment variables | MUST NOT influence canonical execution; if consumed, must be read-only passthrough or ignored |

**Rule**: Any environment variable not appearing in DECLARED or IMPLICITLY_ALLOWED sections is implicitly FORBIDDEN_TO_AFFECT_SEMANTICS. Adding a new variable to DECLARED requires updating `src/core/trusted/env_types.nim` (EnvVar enum) before use.

---

## §2. DECLARED Environment Variables

Variables in this section are registered in `EnvVar` enum (`src/core/trusted/env_types.nim`). Consumption MUST go through `getAxiomEnv()` or `getAxiomEnvOr()` — direct `getEnv()` calls are prohibited except in trusted boundary modules.

### §2.1 Gate System

| Variable | Enum Registration | Primary Consumer(s) | Category |
|----------|-------------------|---------------------|----------|
| `AXIOM_ENV` | `evAxiomEnv` | `src/core/gate/env_gate.nim:29` | Runtime |
| `AXIOM_LOG_LEVEL` | `evAxiomLogLevel` | (logging infrastructure) | Runtime |
| `AXIOM_DEV_MODE` | `evDevMode` | (development controls) | Runtime |
| `AXIOM_GATE_BOND` | `evGateBond` | `config.nims:363`, `src/core/trusted/env_types.nim:24` | Build/Gate |
| `AXIOM_GATE_SOCKET` | `evGateSocket` | (gate IPC) | Runtime |
| `AXIOM_GATE_GPG_KEY_ID` | `evGateGpgKeyId` | (signature verification) | Gate |
| `AXIOM_GATE_TIMEOUT` | `evGateTimeout` | (gate timeout control) | Gate |
| `AXIOM_BYPASS_SIGNATURE` | `evBypassSignature` | (emergency bypass) | Gate |
| `AXIOM_BYPASS_PUBKEY` | `evBypassPubkey` | (bypass key) | Gate |
| `AXIOM_BYPASS_REASON` | `evBypassReason` | (bypass justification) | Gate |
| `AXIOM_RECURSION_GUARD` | `evRecursionGuard` | (recursion prevention) | Runtime |
| `AXIOM_SHADOW_GATE` | `evShadowGate` | (shadow gate mode) | Gate |
| `AXIOM_SHADOW_PROMOTION` | `evShadowPromotion` | (shadow promotion) | Gate |
| `AXIOM_SINGLE_GATE_ID` | `evSingleGateId` | (single gate execution) | Gate |
| `AXIOM_GATE_CONTEXT_ID` | `evGateContextId` | (gate context) | Gate |
| `AXIOM_CAS_HASH_MODE` | `evCasHashMode` | (CAS hash mode) | Gate |
| `AXIOM_SCOPE_ROUTING` | `evScopeRouting` | (scope routing) | Gate |
| `AXIOM_EMERGENCY_NO_VERIFY` | `evEmergencyNoVerify` | `src/core/trusted/bypass_verify.nim:29` | Gate |

### §2.2 Build & Toolchain

| Variable | Enum Registration | Primary Consumer(s) | Category |
|----------|-------------------|---------------------|----------|
| `AXIOM_JOBS` | `evJobs` | (job count) | Build |
| `AXIOM_BUILD_JOBS` | `evBuildJobs` | (build job count) | Build |
| `AXIOM_COMPILE_CORES` | `evCompileCores` | (compile parallelism) | Build |
| `AXIOM_FORCE_MAX_JOBS` | `evForceMaxJobs` | (force max jobs) | Build |
| `AXIOM_NIM_PARALLEL_BUILD` | `evNimParallelBuild` | (Nim parallel build) | Build |
| `AXIOM_TIMEOUT_SLA` | `evTimeoutSla` | (timeout SLA) | Build |
| `AXIOM_HERMETIC_BUILDING` | `evHermeticBuilding` | `tools/hermetic_build.nim:11`, `src/gate/runners/nim_check_runner.nim:211`, `config.nims:363` | Build |
| `AXIOM_STATE_LEDGER_PATH` | `evStateLedgerPath` | `src/core/gate/env_gate.nim:45` | Runtime |
| `AXIOM_STATE_PATH` | `evStatePath` | (state path) | Runtime |
| `AXIOM_INPROCESS_DISPATCH` | `evInProcessDispatch` | (in-process dispatch) | Runtime |
| `AXIOM_LOW_OVERHEAD` | `evLowOverhead` | (low overhead mode) | Runtime |
| `AXIOM_SKIP_HEAVY_TESTS` | `evSkipHeavyTests` | `tools/ci/smoke_test.nim:163` | Test |
| `AXIOM_CONTINUE_ON_ERROR` | `evContinueOnError` | (continue on error) | Runtime |

### §2.3 Memory & Resource Limits

| Variable | Enum Registration | Primary Consumer(s) | Category |
|----------|-------------------|---------------------|----------|
| `AXIOM_MEM_HEADROOM` | `evMemHeadroom` | (memory headroom) | Runtime |
| `AXIOM_MEM_PER_JOB` | `evMemPerJob` | (memory per job) | Runtime |
| `AXIOM_CGROUP_MEMORY_MAX` | `evCgroupMemoryMax` | (cgroup memory limit) | Runtime |
| `AXIOM_CGROUP_MEMORY_HIGH` | `evCgroupMemoryHigh` | (cgroup memory high) | Runtime |
| `AXIOM_CGROUP_CPU_MAX` | `evCgroupCpuMax` | (cgroup CPU limit) | Runtime |

### §2.4 Lean / Verification

| Variable | Enum Registration | Primary Consumer(s) | Category |
|----------|-------------------|---------------------|----------|
| `AXIOM_LEAN_CMD` | `evLeanCmd` | (Lean command path) | Runtime |
| `AXIOM_PROOF_CACHE_PATH` | `evProofCachePath` | (proof cache location) | Runtime |
| `AXIOM_PROVE_VAULT_DIR` | `evProveVaultDir` | (prove vault directory) | Runtime |
| `AXIOM_PROVE_WORKERS` | `evProveWorkers` | `src/verification/batch_uap/loop_driver.nim:605` | Runtime |
| `AXIOM_PROVE_BINARY` | `evProveBinary` | (prove binary path) | Runtime |
| `AXIOM_SMT_TIMEOUT` | `evSmtTimeout` | `src/verification/solver/z3_pool.nim:599` | Runtime |
| `AXIOM_FREEZE_GRAPH_CACHE` | `evFreezeGraphCache` | `src/verification/analyzer/stage_01_ast_extract.nim:84` | Runtime |

### §2.5 LLM Integration

| Variable | Enum Registration | Primary Consumer(s) | Category |
|----------|-------------------|---------------------|----------|
| `AXIOM_LLM_API_URL` | `evLlmApiUrl` | `src/personas/legislator.nim:342`, `src/core/verifier/legislator.nim:190`, `src/core/gate/env_gate.nim:34` | Runtime |
| `AXIOM_LLM_API_KEY` | `evLlmApiKey` | `src/personas/legislator.nim:343`, `src/core/verifier/legislator.nim:190`, `src/core/gate/env_gate.nim:34` | Runtime |
| `AXIOM_LLM_MODEL` | `evLlmModel` | `src/personas/legislator.nim:248`, `src/core/verifier/legislator.nim:86` | Runtime |

### §2.6 Debt / Coverage

| Variable | Enum Registration | Primary Consumer(s) | Category |
|----------|-------------------|---------------------|----------|
| `AXIOM_CRITICAL_DEBT_THRESHOLD` | `evCriticalDebtThreshold` | `tools/debt_ct_validator.nim:484` | Gate |
| `AXIOM_RATCHET_DOWNGRADE` | `evRatchetDowngrade` | (ratchet downgrade — **request only**: signals intent, grants no authority; downgrade executes solely on an Ed25519 signature verifying against the pinned key per [coverage_ratchet_protocol.md](coverage_ratchet_protocol.md) §Admin Signature) | Gate |
| `AXIOM_RATCHET_REASON` | `evRatchetReason` | (ratchet reason — request justification carried into the audit record; never a substitute for the signed approval, [coverage_ratchet_protocol.md](coverage_ratchet_protocol.md)) | Gate |
| `AXIOM_RATCHET_APPROVAL` | `evRatchetApproval` | (pinned-key Ed25519 approval JSON — signature + jti + expires_at; the sole downgrade authority, consumed at `src/gate/runners/coverage_ratchet_gate.nim`, key contract in `core/trusted/ratchet_authority.nim`, [coverage_ratchet_protocol.md](coverage_ratchet_protocol.md) §Admin Signature) | Gate |
| `AXIOM_COMMIT_TYPE` | `evCommitType` | (commit type classification) | Gate |
| `AXIOM_CHECK` | `evCheck` | `src/gate/compile_time_checks.nim:335` | Gate |

### §2.7 Database

| Variable | Enum Registration | Primary Consumer(s) | Category |
|----------|-------------------|---------------------|----------|
| `AXIOM_DB_BACKEND` | `evDbBackend` | (database backend selection) | Runtime |
| `AXIOM_DB_PATH` | `evDbPath` | (database path) | Runtime |

### §2.8 Logging & Audit

| Variable | Enum Registration | Primary Consumer(s) | Category |
|----------|-------------------|---------------------|----------|
| `AXIOM_LOG_DIR` | `evLogDir` | (log directory) | Runtime |
| `AXIOM_VAULT_DIR` | `evVaultDir` | (vault directory) | Runtime |

### §2.9 CI / Source Control

| Variable | Enum Registration | Primary Consumer(s) | Category |
|----------|-------------------|---------------------|----------|
| `AXIOM_CI_BASE_REF` | `evCiBaseRef` | (CI base ref) | CI |
| `AXIOM_CI` | `evCi` | (CI mode flag) | CI |
| `AXIOM_CHANGED_FILES` | `evChangedFiles` | (changed files list) | CI |
| `AXIOM_STAGED_FILES` | `evStagedFiles` | (staged files list) | CI |
| `AXIOM_PUSH_COMMITS` | `evPushCommits` | (push commits flag) | CI |
| `AXIOM_REQUIRE_PERFECT_ASI` | `evRequirePerfectAsi` | (ASI perfection requirement) | Gate |

### §2.10 Testing / PBT

| Variable | Enum Registration | Primary Consumer(s) | Category |
|----------|-------------------|---------------------|----------|
| `AXIOM_PBT_SEED` | `evPbtSeed` | (property-based test seed) | Test |

### §2.11 Root / Path

| Variable | Enum Registration | Primary Consumer(s) | Category |
|----------|-------------------|---------------------|----------|
| `AXIOM_REPO_ROOT` | `evAxiomRepoRoot` | (repository root override) | Runtime |
| `AXIOM_ROOT` | `evRoot` | `src/cli/precompile_gates.nim:31`, `tools/ci/validate_axiom_root.nim:57` | Runtime |
| `AXIOM_LEGACY_PYTHON_PATH` | `evLegacyPythonPath` | (legacy Python path) | Runtime |

### §2.12 CI Platform Events

| Variable | Enum Registration | Primary Consumer(s) | Category |
|----------|-------------------|---------------------|----------|
| `AXIOM_CI_EVIDENCE_MAX_AGE_HOURS` | `evCiEvidenceMaxAgeHours` | (evidence age limit) | CI |
| `CIRCLECI_EVENT` | `evCircleciEvent` | (CircleCI event type) | CI |
| `CIRCLE_SCHEDULE` | `evCircleSchedule` | (CircleCI schedule) | CI |
| `GITHUB_EVENT_NAME` | `evGithubEventName` | (GitHub event name) | CI |
| `GITHUB_SCHEDULE` | `evGithubSchedule` | (GitHub schedule) | CI |

### §2.13 External Tools

| Variable | Enum Registration | Primary Consumer(s) | Category |
|----------|-------------------|---------------------|----------|
| `COMPUTERNAME` | `evComputerName` | (Windows hostname) | Environment |
| `SOURCE_DATE_EPOCH` | `evSourceDateEpoch` | (reproducible build timestamp) | Build |
| `SOURCE_DATE_ROOT` | `evSourceDateRoot` | (reproducible build root) | Build |
| `GIT_INDEX_FILE` | `evGitIndexFile` | (Git index override) | Environment |
| `GIT_DIR` | `evGitDir` | (Git directory override) | Environment |
| `NIM_CACHE_DIR` | `evNimCacheDir` | `tools/full_transform.nim:351` | Build |
| `GHCR_TOKEN` | `evGhcrToken` | `tools/ci/ci_engine.nim:180` | CI |
| `MISTRAL_API_KEY` | `evMistralApiKey` | `tools/ci/ci_engine.nim:186` | CI |
| `AXIOM_Z3_PATH` | `evZ3Path` | `tools/z3_precache.nim:27` | Runtime |
| `AXIOM_Z3_LIB` | `evZ3Lib` | (Z3 library path) | Runtime |
| `AXIOM_NIM_PARSER` | `evAxiomNimParser` | (Nim tree-sitter parser path) | Runtime |
| `AXIOM_LEAN_PARSER` | `evAxiomLeanParser` | (Lean tree-sitter parser path) | Runtime |
| `AXIOM_TS_NIM_PARSER` | `evAxiomTsNimParser` | (TypeScript-Nim parser path) | Runtime |
| `AXIOM_TS_LEAN_PARSER` | `evAxiomTsLeanParser` | (TypeScript-Lean parser path) | Runtime |

### §2.14 Standard Environment (Registered)

| Variable | Enum Registration | Primary Consumer(s) | Category |
|----------|-------------------|---------------------|----------|
| `HOME` | `evHome` | `tools/ingest_audit_debt.nim:230`, `tools/ci/ci_engine.nim:196` | Environment |
| `USER` | `evUser` | `tools/ci/ci_engine.nim:410` | Environment |
| `PATH` | `evPath` | `tools/hermetic_build.nim:386,467` | Environment |
| `TMPDIR` | `evTmpDir` | `tools/full_transform.nim:352` | Environment |
| `LANG` | `evLang` | (locale) | Environment |
| `LC_ALL` | `evLcAll` | (locale) | Environment |

### §2.15 Additional Declared (Direct getEnv, Not in Enum)

These variables are consumed via direct `getEnv()` calls but are established project conventions. They SHOULD be added to the `EnvVar` enum in future refactoring.

| Variable | Primary Consumer(s) | Category | Notes |
|----------|---------------------|----------|-------|
| `NIM_EXE` | `src/gate/gateway.nim:165,247,260` | Build | Nim executable path; default `"nim"` |
| `AXIOM_GATE_FOR_COMMIT` | `src/gate/gateway.nim:597` | Gate | Commit-mode gate execution |
| `AXIOM_GATE_L2` | `tools/ci/pre_commit_gate.nim:28` | Gate | L2 gate trigger |
| `AXIOM_PRECOMPILE_WORKERS` | `src/cli/precompile_gates.nim:230` | Build | Precompile worker count |
| `AXIOM_VFS_ROOT_HASH` | `src/gate/orchestrator/hook/executor.nim:642` | Gate | VFS root hash |
| `AXIOM_PUSH_REFS` | `src/gate/runners/release_version_gate.nim:31` | Gate | Push refs for release |
| `AXIOM_Z3_INCREMENTAL` | `src/verification/solver/z3_pool.nim:338,670,681` | Runtime | Incremental Z3 mode |
| `AXIOM_SKIP_SOLVER_CHECK` | `src/verification/batch_uap/loop_driver.nim:456` | Test | Skip solver availability check |
| `AXIOM_FAST_BUILD` | `config.nims:484,499`, `tools/hermetic_build.nim:1338,1368,1390,1402` | Build | Fast build shortcut |
| `AXIOM_GIT_HASH` | `tools/build_metadata_generator.nim:54,952`, `tools/hermetic_build.nim:1261` | Build | Git hash for builds |
| `AXIOM_DECISION_BINDING_AUDIT` | `tools/hermetic_build.nim:2022` | Gate | Decision binding audit mode |
| `AXIOM_ALLOW_LEGACY_TEMP` | `tools/ci/ratchet_check.nim:56` | Gate | Allow legacy temp files |
| `AXIOM_PROJECT_ROOT` | `tools/tests/validate_root_manifest_test.nim:11`, `tools/tests/validate_axiom_root_test.nim:11` | Test | Test project root override |
| `AxiomParsingImports` | `src/gate/compile_time_checks.nim:64` | Gate | Parsing import filter |
| `AXIOM_DEFAULT_PROCESS_TIMEOUT_MS` | `src/core/sync/sync_process_runner.nim:93` | Runtime | Default process timeout |

---

## §3. IMPLICITLY_ALLOWED Environment Variables

Standard POSIX and widely-recognized environment variables whose VALUES are used for non-semantic purposes (path resolution, locale, temporary file location). These variables MUST NOT carry semantic meaning in Axiom's verification logic.

| Variable | Usage Constraint |
|----------|------------------|
| `HOME` | Path resolution only; value does not affect verification outcome |
| `PATH` | Binary discovery only; value does not affect verification outcome |
| `TMPDIR` | Temporary file location only; value does not affect verification outcome |
| `LANG` | Locale/display only; value does not affect verification outcome |
| `LC_ALL` | Locale/display only; value does not affect verification outcome |
| `USER` | Identity display only; value does not affect verification outcome |
| `PWD` | Current directory detection only |
| `SHELL` | Shell invocation only |
| `TERM` | Terminal capability detection only |

**Rule**: If any of these variables begins to influence verification semantics (result computation, gate pass/fail, certificate generation), it MUST be moved to DECLARED and registered in the `EnvVar` enum.

---

## §4. FORBIDDEN_TO_AFFECT_SEMANTICS

Any environment variable not listed in §2 (DECLARED) or §3 (IMPLICITLY_ALLOWED) is implicitly forbidden from affecting canonical execution semantics. This includes:

- Arbitrary user-defined variables (e.g., `MY_CUSTOM_FLAG`, `DEBUG_MODE`)
- Third-party tool variables not explicitly registered (e.g., `JAVA_HOME`, `PYTHONPATH`)
- CI platform variables not registered (e.g., `JENKINS_URL`, `TRAVIS_JOB_ID`)

If such a variable is consumed by Axiom code, it MUST be:
1. Read-only passthrough (forwarded to subprocesses without interpretation)
2. OR explicitly ignored

**Enforcement**: Direct `getEnv()` calls on unregistered variables in non-trusted modules violate the `enforceEnvAccess` macro (`src/core/trusted/env_access.nim`). Only `getAxiomEnv()` (enum-gated) is permitted in core modules.

---

## §5. Cross-Reference: Enum vs. Actual Usage

All variables in §2.1–§2.14 are registered in `EnvVar` enum (`src/core/trusted/env_types.nim:16–141`). Variables in §2.15 are consumed via direct `getEnv()` and are candidates for future enum registration.

**Unregistered variables found in source scan** (potential `UNDECLARED_CAP` — capabilities not covered by enum enforcement):

| Variable | File:Line | Module | Risk Level |
|----------|-----------|--------|------------|
| `NIM_EXE` | `src/gate/gateway.nim:165` | Gateway | LOW — build-time only |
| `NIM_EXE` | `src/gate/gateway.nim:247` | Gateway | LOW — build-time only |
| `NIM_EXE` | `src/gate/gateway.nim:260` | Gateway | LOW — build-time only |
| `Z3_PATH` | `tools/z3_precache.nim:27` | Z3 precache | LOW — tool script |
| `PATH` | `tools/hermetic_build.nim:386` | Hermetic build | LOW — passthrough |
| `PATH` | `tools/hermetic_build.nim:467` | Hermetic build | LOW — passthrough |
| `HOME` | `tools/ingest_audit_debt.nim:230` | Debt ingest | LOW — path resolution |
| `HOME` | `tools/ci/ci_engine.nim:196` | CI engine | LOW — path resolution |
| `USER` | `tools/ci/ci_engine.nim:410` | CI engine | LOW — identity |
| `SUDO_USER` | `tools/ci/ci_engine.nim:410` | CI engine | LOW — identity |
| `CI_COMMIT_BRANCH` | `tools/build_metrics.nim:288` | Build metrics | LOW — CI metadata |
| `CI_COMMIT_SHA` | `tools/build_metrics.nim:303` | Build metrics | LOW — CI metadata |
| `GITHUB_TOKEN` | `tools/pr_coverage_commenter.nim:380` | PR commenter | MEDIUM — credential |
| `GITHUB_TOKEN` | `tools/ci/ci_health_checker.nim:292,352` | CI health | MEDIUM — credential |
| `CIRCLE_PR_NUMBER` | `tools/pr_coverage_commenter.nim:387` | PR commenter | LOW — CI metadata |
| `GITHUB_PULL_REQUEST_NUMBER` | `tools/pr_coverage_commenter.nim:390` | PR commenter | LOW — CI metadata |
| `GITHUB_REPO` | `tools/pr_coverage_commenter.nim:398` | PR commenter | LOW — CI metadata |
| `BASE_REF` | `tools/pr_coverage_commenter.nim:519` | PR commenter | LOW — CI metadata |
| `CIRCLECI_TOKEN` | `tools/ci/ci_health_checker.nim:292,352` | CI health | MEDIUM — credential |
| `GHCR_TOKEN` | `tools/ci/ci_engine.nim:180` | CI engine | MEDIUM — credential |
| `MISTRAL_API_KEY` | `tools/ci/ci_engine.nim:186` | CI engine | MEDIUM — credential |
| `TREE_SITTER_VERSION` | `tools/ci/ci_engine.nim:460` | CI engine | LOW — version string |
| `TREE_SITTER_NIM_VERSION` | `tools/ci/ci_engine.nim:461` | CI engine | LOW — version string |

**Assessment**: Most unregistered variables are in `tools/` scripts (CI/infrastructure), not in core verification logic. Core modules enforce enum-gated access via `enforceEnvAccess`. Credential-bearing variables (tokens, API keys) in tools are operational concerns, not semantic threats.

---

## §6. XDG and PathProvider Extension Policy

> Deferred — productization 이후 계약 수정.

Environment variable extension mechanisms such as XDG Base Directory Specification compliance or custom `PathProvider` abstractions are OUT OF SCOPE for this specification. Any future expansion to support XDG-conventional paths or provider-based path resolution MUST be governed by a separate contract revision. No implementation of XDG or PathProvider semantics is authorized until this document is formally updated.

---

## §7. Enforcement Summary

| Mechanism | Scope | Enforcement Point |
|-----------|-------|-------------------|
| `enforceEnvAccess` macro | `src/` core modules | Compile-time rejection of direct `getEnv()` |
| `EnvVar` enum exhaustiveness | All modules | New variable requires enum addition |
| `getAxiomEnv()` / `getAxiomEnvOr()` | Trusted access layer | Single accessor for all env reads |
| `ast_invariant_checker.nim` | `tools/` scripts | Lint warning for direct `getEnv()` |
| Manual review | New variables | PR review required for enum additions |
