# Hermetic Gate Framework

> **Status**: Active  
> **Version**: v28 (Hermetic Build Orchestrator)  
> **SSOT**: `src/gate/topology_spec.nim` (`const TopologySpec*`)  

## Overview

The Hermetic Gate Framework is Axiom's compile-time gate verification system. It ensures that all gate definitions are:
1. **Single Source of Truth (SSOT)** — `TopologySpec` is the canonical definition
2. **Hermetically Isolated** — gates run in subprocesses with `--panics:on`
3. **Statically Verified** — `static_gate_scanner.nim` detects theater at compile time

## Architecture

### 1. SSOT Topology (`topology_spec.nim`)

- **File**: `src/gate/topology_spec.nim`
- **Type**: `const TopologySpec*: array[52, TopologyEntry]`
- **Purpose**: Master registry of all gates with metadata (id, entry, layer, stages, category)

### 2. Manifest Generation (`sync_topology.nim`)

- **Tool**: `tools/sync_topology.nim`
- **Inputs**: `TopologySpec`
- **Outputs**:
  - `src/gate/manifest.d/*.json` — per-gate JSON manifests
  - `src/gate/manifest.d/_index.json` — sorted gate ID index
  - `src/generated/manifest_registry.nim` — Nim const array
  - `src/generated/gate_registry.nim` — `AllGateConfigs*` sequence
  - `config/gates.manifest.toml` — TOML for `static_gate_scanner.nim`

### 3. Anti-Theater AST Engine (`static_gate_scanner.nim`)

- **File**: `src/gate/static_gate_scanner.nim`
- **Purpose**: Compile-time verification of gate implementations
- **Checks**:
  - Trivial body detection (`result = true` / `return true`)
  - `{.axiomGate: "id".}` pragma presence
  - Manifest-file path consistency
- **Feature Flag**: `AXIOM_ENFORCE_GATE_PRAGMAS` (default: `1` = enabled)

### 4. Hermetic Build Isolator (`hermetic_build.nim`)

- **File**: `tools/hermetic_build.nim`
- **Purpose**: Pre-build verification before `nim c`
- **Checks**: Import boundaries, Z3 version, git hash, invariant hashes

## Gate Registration Flow

```
topology_spec.nim (SSOT)
        │
        ▼
sync_topology.nim (auto-generates)
        │
        ├──► manifest.d/*.json (runtime data)
        ├──► gates.manifest.toml (scanner input)
        ├──► manifest_registry.nim (compile-time)
        └──► gate_registry.nim (runtime)
                │
                ▼
static_gate_scanner.nim (compile-time verification)
        │
        ▼
nim c bin/axiom.nim (build with gate checks)
```

## Pragma Standard

### `{.axiomGate: "gate-id".}`

- **Declaration**: `template axiomGate*(gateId: static string) {.pragma.}` in `axiom_pragmas_macros.nim`
- **Placement**: Module-level (top of file)
- **Purpose**: Declares gate identity for compile-time verification
- **Example**:
  ```nim
  {.axiomGate: "anti-theater".}
  import core/trusted/layer_declaration
  # ... gate implementation
  ```

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `AXIOM_ENFORCE_GATE_PRAGMAS` | `1` | Enable strict pragma checking |
| `AXIOM_BYPASS_SIGNATURE` | (none) | Ed25519+TOTP signed emergency bypass signature |
| `AXIOM_BYPASS_PUBKEY` | (none) | Ed25519 public key authorizing the bypass |
| `AXIOM_BYPASS_REASON` | (none) | Bypass reason (must match signing-time reason) |
| `AXIOM_EMERGENCY_NO_VERIFY` | `0` | Required bypass flag; alone it is not sufficient (signature required) |

## Related Specifications

- [`src/gate/topology_spec.nim`](../../src/gate/topology_spec.nim) — Gate topology definitions (SSOT source)
- [4-Tier Verification Pipeline](./4_tier_verification_pipeline.md) — Verification workflow
- [BSS Segment Architecture](./bss_segment_architecture.md) — Static Project Matrix
- [State Ledger Architecture](./state_ledger_architecture.md) — Cross-process state
- [Nim Effect System Quirks](./nim_effect_system_quirks.md) — §14 Hermetic Build Orchestrator

## Single Reconciler Pattern

### Principle: One Tool, One Command

The framework uses a **Single Reconciler** (`tools/sync_topology.nim`) to maintain consistency between:
1. **SSOT** (`topology_spec.nim`)
2. **Generated artifacts** (`gates.manifest.toml`, `manifest.d/*.json`, `manifest_registry.nim`, `gate_registry.nim`)
3. **Gate pragma annotations** (`{.axiomGate.}` in gate files)

### Workflow

```bash
# Developer runs single command after modifying topology_spec.nim
nim r tools/sync_topology.nim

# This automatically:
# 1. Regenerates gates.manifest.toml
# 2. Injects missing {.axiomGate.} pragmas into gate files
# 3. Updates all derived artifacts
```

### Git Drift Guard (CI Enforcement)

The CI pipeline enforces that committed code matches the SSOT output:

```yaml
# .circleci/config.yml (verify-static job)
- run:
    name: Verify topology drift
    command: |
      nim r tools/sync_topology.nim
      git diff --exit-code -- src/gate/manifest.d/*.json config/gates.manifest.toml
      # If drift detected → build fails with E_DRIFT
```

This ensures developers cannot commit code that diverges from the SSOT.

## Related Specifications

- [`src/gate/topology_spec.nim`](../../src/gate/topology_spec.nim) — Gate topology definitions (SSOT source)
- [4-Tier Verification Pipeline](./4_tier_verification_pipeline.md) — Verification workflow
- [BSS Segment Architecture](./bss_segment_architecture.md) — Static Project Matrix
- [State Ledger Architecture](./state_ledger_architecture.md) — Cross-process state
- [Nim Effect System Quirks](./nim_effect_system_quirks.md) — §14 Hermetic Build Orchestrator

## CI Baseline Gate Contract (Zero-Theater)

### Exit Code 계약
| 조건 | Exit | 극장 방지 |
|------|------|-----------|
| totalCount == 0 (빈 vault) | 2 (ERR_EMPTY_VAULT) | Fail-Open(#1) 차단 |
| VKD_current < VKD_baseline | 1 (ERR_BASELINE_DEGRADED) | 상세 후퇴(#6) 차단 |
| VKD_current >= VKD_baseline | 0 (OK) | 정량 게이트 통과 |

### Provenance 계약 (TCB)
- Z3 실제 실행 경로만 solverVersion + z3RawVersion 기록.
- Tautology/커널 정적 경로는 Z3 지문 미기록 (solver: "kernel-*" 명시).
- parseSolverProvenance의 unknown → low-trust (spZ3SAT 기본 인상 금지).

### Cache Contract
- .axiom/vault는 로컬 휘발성 — CI 캐시 미사용 (Zombie Certs 차단).
- restore_cache는 Exact Key Match만 (fallback prefix 금지) — 만약 캐시 도입 시.

### Vault 경로 SSOT
- CanonicalVaultDir = ".axiom/vault" (로컬 런타임). 
- src/verification/certificates = stable(개발 커밋용, gitignore).

## Change Log

- **2026-08-03**: Added CI Baseline Gate & Zero-Theater Vault Contract (ADR-0010)
- **2026-07-31**: v28 — Added Single Reconciler Pattern and Git Drift Guard
- **2026-07-31**: v27 — Initial version — documents Zero-Heuristic Manifest-AST Binding
