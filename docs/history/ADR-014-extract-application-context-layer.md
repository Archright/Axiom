# ADR-014: Extract Application Context Layer

## Status
Accepted

## Context
`PersonaBridge` lived in `src/core/orchestration/` and acted as a combined DI container, type hub, and re-export facade for the six personas. Its name implied "bridge" (infrastructure wiring) but its contents included application-level callback definitions and broad domain-type re-exports. This created three problems:

1. **Layer confusion:** Presentation (`src/personas/`) imported a module from the orchestration sub-layer and received both domain types and callbacks through a single facade.
2. **God-module risk:** Re-exporting ~20 domain types turned the bridge into an implicit type hub, violating ISP.
3. **Mega composition root:** `persona_bridge_init.nim` directly wired every verification implementation, making the composition root grow linearly with every new persona capability.

## Decision
1. Introduce `src/core/application/` as Axiom's Application layer.
2. Move the callback container to `src/core/application/persona_context.nim` and rename it to `PersonaContext`.
3. `PersonaContext` is a plain data object (proc-field bundle) and exports **no** domain types.
4. Add a `validate()` proc to `PersonaContext` that asserts every callback field is non-nil; `initPersonaContext()` calls it after wiring.
5. Personas import the domain modules whose types they actually reference.
6. Move concrete wiring to `src/core/application/persona_context_init.nim`, which delegates to focused composition modules under `verification/composition/`.
7. Each composition module owns one bounded context: `leanstral`, `scan`, `bmc`, `cegar`, `healing`.
8. Replace the closure PBT with a deterministic wiring test.

## Consequences
- Dependency direction is explicit: `personas → core/application → core/contract`.
- The single **Application-owned** crossing into Infrastructure is `persona_context_init.nim`. All downstream `verification/` dependencies are encapsulated by the composition modules under `verification/composition/`.
- Runtime validation guarantees that a missing registration aborts immediately at startup, before any persona runs.
- Future decomposition (e.g., `LeanContext`, `VerificationContext`, `HealingContext`) is easier because wiring is already grouped by bounded context. ADR-015 will be created when that split is undertaken.
- Persona files gain a small number of direct domain imports; this is an intentional trade-off for eliminating a god-module re-export hub.

## Deleted Files

| File | Replacement | Deletion Reason | Restoration Risk |
|------|-------------|-----------------|------------------|
| `src/core/orchestration/persona_bridge.nim` | `src/core/application/persona_context.nim` | Combined DI container + type hub + re-export facade replaced by a focused callback container | LOW — new type covers callback contract |
| `src/core/orchestration/persona_bridge_init.nim` | `src/core/application/persona_context_init.nim` + `src/verification/composition/*_registry.nim` | Mega composition root split into Application composition root and bounded-context registries | LOW — wiring preserved and validated |
| `tests/generated_pbt/persona_bridge_pbt.nim` | `tests/unit/persona_context_wiring_test.nim` | Closure PBT replaced by deterministic wiring test per AGENTS.md §0.7/§0.8 | LOW — new test verifies same contract |

## Future Work
- ADR-015: Decompose `PersonaContext` into bounded-context-specific context objects once the composition modules have stabilized. This addresses the remaining SRP concern of a 22-field object.

## References
- AGENTS.md §1.2 (Layer Architecture)
- AGENTS.md §1.3a (Import Encapsulation)
- Context7 review: `/ardalis/cleanarchitecture`, `/jasontaylordev/cleanarchitecture`, `/jkazama/ddd-java`, `/hypothesisworks/hypothesis`, `/jqwik-team/jqwik`
