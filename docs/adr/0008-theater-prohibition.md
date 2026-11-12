# ADR-0008: Theater Prohibition

## Status
Accepted

## Context
As the gate system grew, several patterns emerged that created the appearance of rigor without actual guarantees: hardcoded PASS results, empty except blocks, mock runners returning true, and unenforced documentation claims. These "theater" patterns undermined trust in the entire verification system.

## Decision
Formalize the theater prohibition policy (per AGENTS.md §0.9). Any code that claims to provide a guarantee while actually guaranteeing nothing is classified as theater and registered in `data/debt_registry.json`. Theater signatures include always-pass results, swallowed failures, disguised stubs, vacuous proofs, dead gates, and unenforced claims. Theater debt must be tracked, never silently patched.

## Consequences
- New agents and contributors have a clear checklist of anti-patterns to avoid.
- Theater audit process catches regression before it reaches main branch.
- Debt registry provides visibility into known gaps in verification coverage.
- Resolving theater entries improves genuine system reliability, not just perception.
