## env_types.nim — Environment variable enum and core accessors
## Part of the Guard Ring system for Axiom-core.
##
## This module defines the EnvVar enum and basic accessors that do NOT
## depend on axiom_pragmas (to avoid circular dependency). All procs
## use plain {.raises: [].} instead of {.axiomEffect: IOEffect, raises: [].}.
##
## The higher-level convenience procs and axiomEffect-tagged wrappers
## live in env_access.nim, which imports and re-exports this module.

import core/trusted/layer_declaration
axiomLayer "domain"
import std/os

type
  EnvVar* {.pure.} = enum
    ## Exhaustive enumeration of all environment variables used by Axiom.
    ## Add new entries here when a new env var is needed.

    # ── Gate system ──────────────────────────────────────────────────────
    evAxiomEnv = "AXIOM_ENV"
    evAxiomLogLevel = "AXIOM_LOG_LEVEL"
    evDevMode = "AXIOM_DEV_MODE"
    evGateBond = "AXIOM_GATE_BOND"
    evGateSocket = "AXIOM_GATE_SOCKET"
    evGateGpgKeyId = "AXIOM_GATE_GPG_KEY_ID"
    evGateTimeout = "AXIOM_GATE_TIMEOUT"
    evBypassSignature = "AXIOM_BYPASS_SIGNATURE"
    evBypassPubkey = "AXIOM_BYPASS_PUBKEY"
    evBypassReason = "AXIOM_BYPASS_REASON"
    evShadowGate = "AXIOM_SHADOW_GATE"
    evShadowPromotion = "AXIOM_SHADOW_PROMOTION"
    evSingleGateId = "AXIOM_SINGLE_GATE_ID"
    evGateContextId = "AXIOM_GATE_CONTEXT_ID"
    evCasHashMode = "AXIOM_CAS_HASH_MODE"
    evScopeRouting = "AXIOM_SCOPE_ROUTING"
    evEmergencyNoVerify = "AXIOM_EMERGENCY_NO_VERIFY"

    # ── Build & toolchain ────────────────────────────────────────────────
    evJobs = "AXIOM_JOBS"
    evBuildJobs = "AXIOM_BUILD_JOBS"
    evCompileCores = "AXIOM_COMPILE_CORES"
    evForceMaxJobs = "AXIOM_FORCE_MAX_JOBS"
    evNimParallelBuild = "AXIOM_NIM_PARALLEL_BUILD"
    evTimeoutSla = "AXIOM_TIMEOUT_SLA"
    evHermeticBuilding = "AXIOM_HERMETIC_BUILDING"
    evStateLedgerPath = "AXIOM_STATE_LEDGER_PATH"
    evStatePath = "AXIOM_STATE_PATH"
    evInProcessDispatch = "AXIOM_INPROCESS_DISPATCH"
    evLowOverhead = "AXIOM_LOW_OVERHEAD"
    evSkipHeavyTests = "AXIOM_SKIP_HEAVY_TESTS"
    evContinueOnError = "AXIOM_CONTINUE_ON_ERROR"

    # ── Memory & resource limits ─────────────────────────────────────────
    evMemHeadroom = "AXIOM_MEM_HEADROOM"
    evMemPerJob = "AXIOM_MEM_PER_JOB"
    evCgroupMemoryMax = "AXIOM_CGROUP_MEMORY_MAX"
    evCgroupMemoryHigh = "AXIOM_CGROUP_MEMORY_HIGH"
    evCgroupCpuMax = "AXIOM_CGROUP_CPU_MAX"

    # ── Lean / verification ──────────────────────────────────────────────
    evLeanCmd = "AXIOM_LEAN_CMD"
    evProofCachePath = "AXIOM_PROOF_CACHE_PATH"
    evProveVaultDir = "AXIOM_PROVE_VAULT_DIR"
    evProveWorkers = "AXIOM_PROVE_WORKERS"
    evProveBinary = "AXIOM_PROVE_BINARY"
    evSmtTimeout = "AXIOM_SMT_TIMEOUT"
    evFreezeGraphCache = "AXIOM_FREEZE_GRAPH_CACHE"

    # ── LLM integration ──────────────────────────────────────────────────
    evLlmApiUrl = "AXIOM_LLM_API_URL"
    evLlmApiKey = "AXIOM_LLM_API_KEY"
    evLlmModel = "AXIOM_LLM_MODEL"

    # ── Debt / coverage ──────────────────────────────────────────────────
    evCriticalDebtThreshold = "AXIOM_CRITICAL_DEBT_THRESHOLD"
    evRatchetDowngrade = "AXIOM_RATCHET_DOWNGRADE"
    evRatchetReason = "AXIOM_RATCHET_REASON"
    evRatchetApproval = "AXIOM_RATCHET_APPROVAL"
    evCommitType = "AXIOM_COMMIT_TYPE"
    evCheck = "AXIOM_CHECK"

    # ── Database ─────────────────────────────────────────────────────────
    evDbBackend = "AXIOM_DB_BACKEND"
    evDbPath = "AXIOM_DB_PATH"

    # ── Logging & audit ──────────────────────────────────────────────────
    evLogDir = "AXIOM_LOG_DIR"
    evVaultDir = "AXIOM_VAULT_DIR"

    # ── CI / source control ──────────────────────────────────────────────
    evCiBaseRef = "AXIOM_CI_BASE_REF"
    evCi = "AXIOM_CI"
    evChangedFiles = "AXIOM_CHANGED_FILES"
    evStagedFiles = "AXIOM_STAGED_FILES"
    evPushCommits = "AXIOM_PUSH_COMMITS"
    evRequirePerfectAsi = "AXIOM_REQUIRE_PERFECT_ASI"

    # ── Testing / PBT ────────────────────────────────────────────────────
    evPbtSeed = "AXIOM_PBT_SEED"

    # ── Root / path ──────────────────────────────────────────────────────
    evAxiomRepoRoot = "AXIOM_REPO_ROOT"
    evRoot = "AXIOM_ROOT"
    evLegacyPythonPath = "AXIOM_LEGACY_PYTHON_PATH"

    # ── Standard environment ─────────────────────────────────────────────
    evHome = "HOME"
    evUser = "USER"
    evPath = "PATH"
    evTmpDir = "TMPDIR"
    evLang = "LANG"
    evLcAll = "LC_ALL"

    # ── CI platform ──────────────────────────────────────────────────────
    evCiEvidenceMaxAgeHours = "AXIOM_CI_EVIDENCE_MAX_AGE_HOURS"
    evCircleciEvent = "CIRCLECI_EVENT"
    evCircleSchedule = "CIRCLE_SCHEDULE"
    evGithubEventName = "GITHUB_EVENT_NAME"
    evGithubSchedule = "GITHUB_SCHEDULE"

    # ── External tools ───────────────────────────────────────────────────
    evComputerName = "COMPUTERNAME"
    evSourceDateEpoch = "SOURCE_DATE_EPOCH"
    evSourceDateRoot = "SOURCE_DATE_ROOT"
    evGitIndexFile = "GIT_INDEX_FILE"
    evGitDir = "GIT_DIR"
    evNimCacheDir = "NIM_CACHE_DIR"
    evGhcrToken = "GHCR_TOKEN"
    evMistralApiKey = "MISTRAL_API_KEY"
    evZ3Path = "AXIOM_Z3_PATH"
    evZ3Lib = "AXIOM_Z3_LIB"

    # ── Tree-sitter parser paths ─────────────────────────────────────────
    evAxiomNimParser = "AXIOM_NIM_PARSER"
    evAxiomLeanParser = "AXIOM_LEAN_PARSER"
    evAxiomTsNimParser = "AXIOM_TS_NIM_PARSER"
    evAxiomTsLeanParser = "AXIOM_TS_LEAN_PARSER"

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc envName*(key: EnvVar): string {.raises: [].} =
  ## Convert an EnvVar enum to its environment variable name string.
  ## This is the single conversion point; all procs below use this.
  repr(key)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc getAxiomEnv*(key: EnvVar, default: string = ""): string {.raises: [].} =
  ## The ONLY permitted way to read environment variables.
  ## All other modules MUST use this instead of getEnv().
  getEnv(envName(key), default)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc getAxiomEnvOr*(key: EnvVar, fallback: string): string {.raises: [].} =
  ## Variant that requires an explicit fallback (no silent empty default).
  let val = getEnv(envName(key), "")
  if val.len == 0: fallback else: val

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc hasAxiomEnv*(key: EnvVar): bool {.raises: [].} =
  ## Check if an env var is set without reading its value.
  existsEnv(envName(key))

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc setAxiomEnv*(key: EnvVar, value: string) {.raises: [OSError].} =
  ## The ONLY permitted way to set environment variables.
  ## All other modules MUST use this instead of putEnv().
  putEnv(envName(key), value)

