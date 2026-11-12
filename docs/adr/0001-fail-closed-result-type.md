# ADR-0001: Fail-Closed Result Type

## Status
Accepted

## Context
The Axiom integrity engine must guarantee that any verification failure is surfaced, never silently swallowed. Previous patterns used bare `bool` returns or unhandled exceptions, which could hide failures during gate execution or proof runs. We needed a type-level guarantee that every operation explicitly communicates success or failure.

## Decision
Adopt a fail-closed result type pattern across all core modules. Every gate runner and pipeline stage returns an explicit result discriminating between success and failure paths. Failure cases carry structured error context (message, code, location). The compiler enforces exhaustiveness — unchecked results produce warnings during CI lint gates.

## Consequences
- All gate runners must handle both branches of the result type at compile time.
- Silent failures are impossible without violating the exhaustiveness check.
- Error messages are machine-readable, enabling automated triage in CI.
- Slight verbosity increase in calling code is offset by guaranteed correctness.
