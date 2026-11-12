## Facade SDK for tools/ — controlled import boundary
##
## tools/ MUST import from this module instead of directly from core/,
## gate/, engine/, verification/, cli/, or infrastructure/. The
## config.nims `scanImportBoundary` lint flags any `tools/*.nim` file that
## contains a raw `import core/...` (or gate/engine/verification/cli) line.
## This facade is the single sanctioned escape hatch: it is listed in
## config.nims `skipFiles`-equivalent allowlist (via the `importLint` block
## skip pattern at the API layer) and re-exports the narrow subset of
## engine/gate/core symbols that tools are permitted to use.
##
## PHILOSOPHY: this module is a *thin re-export shim only*. It must not
## introduce logic, state behaviour. Every symbol below originates
## in an upstream module under src/.

import core/trusted/layer_declaration
axiomLayer "presentation"
# ── core: axiom pragmas (compiler annotations used by source generators) ──
import core/axiom_pragmas
export axiom_pragmas

# ── core/trusted: axiom pragmas (trusted variant used in CI/audit tools) ──
import core/trusted/axiom_pragmas
export axiom_pragmas

# ── core/trusted: env_access (hermetic env-var wrappers) ──
import core/trusted/env_access
export env_access

# ── core/utils: debt_params (registry of tech-debt tags) ──
import core/utils/debt_params
export debt_params

# ── core/utils: repo_root (hermetic repo-root locator) ──
import core/utils/repo_root
export repo_root

# ── core: import_graph (module dependency graph used by prune/discover) ──
import core/import_graph
export import_graph

# ── core: observer (pipeline progress telemetry) ──
import core/observer
export observer

# ── core/parsers: safe_parsers (Result-based numeric/bool parsing) ──
import core/parsers/safe_parsers
export safe_parsers

# ── core: results generic Result[T,E] type ──
import core/results
export results

# ── core: manifest_schema (axiom/gate manifest data model) ──
import core/manifest_schema
export manifest_schema

# ── core/vault: vault_manager_spec (proof-vault schema types) ──
import core/vault/vault_manager_spec
export vault_manager_spec

# ── core/telemetry: gate_telemetry (gate telemetry emission) ──
import core/telemetry/gate_telemetry
export gate_telemetry

# ── engine: atomic_ops (hermetic atomic file-write / flock primitives) ──
import engine/atomic_ops
export atomic_ops

# ── gate: gate_types (InProcessGate / GateRegistration / HermeticPipelineConfig) ──
import gate/gate_types
export gate_types

# ── gate: pipeline_orchestrator (top-level orchestrator entry point) ──
import gate/pipeline_orchestrator
export pipeline_orchestrator

# ── core/gate: state_ledger (cross-process pipeline state ledger v27) ──
import core/gate/state_ledger
export state_ledger

# ── core/gate: state_ledger_types (ledger data types + getStagingTreeHash) ──
import core/gate/state_ledger_types
export state_ledger_types

# ── core/crypto: hash_kernel (HashValue, isVoid, hashValueFromHex/ToHex) ──
import core/crypto/hash_kernel
export hash_kernel
