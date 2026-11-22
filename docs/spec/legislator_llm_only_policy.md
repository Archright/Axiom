# Legislator LLM-Only Policy (HARD RULE)

## Rationale

The Legislator persona is defined in the Axiom Specification as the "Architect / AI" — the Vibe Coding / LLM-based invariant drafter. Static heuristic-based invariant generation violates this architectural contract and creates a false confidence layer that cannot learn from counterexamples.

## Rule

Legislator invariant drafting MUST use LLM-based auto-formalization (`callLeanstral` or equivalent). Static heuristic methods (`selectEvolutionHit`, `buildRefinedInvariant`, `runNegativeInvariantSearch` as primary invariant sources) are FORBIDDEN in the Legislator module.

## Scope

- The mandatory subject of this policy is the **Legislator persona inside the Axiom repository** — the proposition legislator (`legislator.nim`). **BYO customer external agents** (BYO Agent intake, where a customer submits propositions through their own AI agent — `ax prove --proposals`, [byo_agent_proposition_contract.md](./byo_agent_proposition_contract.md)) are **not** the Legislator persona — the Leanstral-only duty of AGENTS.md §0.2a and of this policy **does not apply** to customer external agents (2026-11-02 scope clarification).
- Customer external agents do not perform Axiom's proposition legislation — their submissions are limited to referencing and parameterizing committed catalog specIds (`soExplicit` new commitment is reserved for the human commit path), `explanation` is not evidence (byo_agent_proposition_contract.md §2 and §5), and verification verdicts are produced by the existing deterministic lane (`ax prove`). Enforcement of this policy is limited to the Axiom-internal Legislator module.

## Enforcement

1. **Compile-time**: `legislator.nim` MUST import `leanstral_gateway` and transitively call `callLeanstral`.
2. **Architecture gate**: `nimtry` may be extended to verify that `legislator.nim` does not contain static heuristic imports (e.g. `core/verification_unit`) without an accompanying LLM gateway import.
3. **Runtime**: Any `LegislatorArtifact` produced without LLM invocation is considered invalid and MUST be rejected by the pipeline.

## History

- **2026-06-04**: Policy enacted after Notion Spec v0.3.7 audit revealed `legislator.nim` was using only static heuristics (`VerificationUnit.runSelfHealing`, `selectEvolutionHit`, `buildRefinedInvariant`) with no LLM invocation.
