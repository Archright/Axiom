# ADR-0005: Predicate-Based Gates

## Status
Accepted

## Context
Early gate implementations mixed routing logic (which files to check) with verification logic (what to check). This made it impossible to reuse gate logic across different stages (pre-commit vs CI) or to compose multiple checks into a single gate. Each gate duplicated file-walking and filtering code.

## Decision
Separate gate behavior into two layers: predicates (what conditions trigger the gate) and runners (what verification executes). Predicates match changed filenames against patterns defined in the registry. Runners receive only the filtered file set. This allows the same runner to execute under different predicate configurations.

## Consequences
- File matching logic lives in one place (`topology_spec.nim`), eliminating duplication.
- New gates inherit predicate infrastructure automatically.
- Runners are simpler, testing-focused procedures without filesystem concerns.
- Predicate evaluation happens before subprocess spawn, reducing unnecessary gate invocations.
