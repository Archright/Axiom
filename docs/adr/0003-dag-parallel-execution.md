# ADR-0003: DAG Parallel Execution

## Status
Accepted

## Context
Gate execution in the Axiom pipeline has linear dependencies — some gates must run before others, but many can execute in parallel. The original sequential executor wasted CPU cycles on independent gate runs. With 80+ gates, total verification time exceeded practical limits for pre-commit hooks.

## Decision
Model gate dependencies as a directed acyclic graph (DAG). Schedule independent nodes for concurrent execution using the malebolgia library. Respect dependency edges strictly — a node only starts when all predecessors complete successfully. Use a work-stealing scheduler to balance load across available cores.

## Consequences
- Pre-commit gate time reduced from ~60s to ~15s on average (4-core machine).
- DAG construction adds ~50ms overhead per run, negligible compared to savings.
- Dependency errors produce clear cycle-detection diagnostics.
- malebolgia value-type constraint means gate state must be serialized via shared files.
