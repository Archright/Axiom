{.push raises: [].}
## env_access.nim — Centralized environment variable access layer
## Part of the Guard Ring system for Axiom-core.
##
## All environment variable access MUST go through getAxiomEnv().
## Direct getEnv() calls will be rejected by the enforceEnvAccess macro.
##
## This provides:
## - Type-safe enum keys (no typos in env var names)
## - Single point of audit for all env access
## - Compile-time enumeration of all allowed env vars
## - Default value documentation
##
## Core types and accessors (EnvVar, envName, getAxiomEnv, etc.) are
## defined in env_types.nim and re-exported here for backward compatibility.

import core/trusted/layer_declaration
axiomLayer "domain"
import core/trusted/env_types
export env_types  # 100% 호환: EnvVar, envName, getAxiomEnv, getAxiomEnvOr, hasAxiomEnv, setAxiomEnv 전부 재수출
# ── Convenience procs for high-frequency env var patterns ────────────────
# These consolidate the most duplicated getEnv patterns across gate runners.

func currentUser*(): string =
  ## Read USER env var with fallback "unknown".
  getAxiomEnv(evUser, "unknown")
