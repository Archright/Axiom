# ADR-0004: SSOT Gate Registry

## Status
Accepted

## Context
Gate metadata (id, name, layer, weight, stages, dependencies) was scattered across multiple sources: JSON manifests, Nim compile-time constants, hook configurations, and CI YAML. Drift between these sources caused gates to run in CI but not locally, or vice versa. No single source of truth existed.

## Decision
Establish `src/gate/topology_spec.nim` (`const TopologySpec*`) as the single source of truth. `tools/sync_topology.nim` generates all downstream artifacts — manifest JSON files, `manifest_registry.nim`, and `gate_registry.nim` — from this SSOT at build time. `topology_checker.nim` validates 1:1 synchronization via `static: assert` at compile time.

## Consequences
- Adding or removing a gate requires editing one file; sync tool handles the rest.
- Drift is caught at compile time, never at runtime.
- CI and local environments always use identical gate definitions.
- Manual edits to generated files are overwritten on next build, preventing accidental divergence.
