# ADR-0006: CAS Cache Engine

## Status
Accepted

## Context
Running the full gate suite on every commit was too slow for developer workflows. Many gates produce identical results when their inputs haven't changed. We needed a caching mechanism that detects input changes deterministically without storing large intermediate artifacts.

## Decision
Implement a content-addressable storage (CAS) cache keyed by SHA-256 hashes of gate inputs (source files, configuration, environment). Cache entries store gate pass/fail results. On each run, compute input hashes first — if unchanged, return cached result without executing the gate. Cache is stored under `.axiom/cache/` and is gitignored.

## Consequences
- Unchanged codebases skip gate execution entirely, reducing pre-commit time to <5s.
- Hash computation is deterministic, so cache hits are reproducible across machines.
- Cache invalidation is automatic — any input change produces a new hash.
- Cache size grows with unique input combinations; periodic cleanup via `make clean-cache` recommended.
