# Legislator LLM-Only Policy (HARD RULE)

## Rationale

The Legislator persona is defined in the Axiom Specification as the "Architect / AI" — the Vibe Coding / LLM-based invariant drafter. Static heuristic-based invariant generation violates this architectural contract and creates a false confidence layer that cannot learn from counterexamples.

## Rule

Legislator invariant drafting MUST use LLM-based auto-formalization (`callLeanstral` or equivalent). Static heuristic methods (`selectEvolutionHit`, `buildRefinedInvariant`, `runNegativeInvariantSearch` as primary invariant sources) are FORBIDDEN in the Legislator module.

## Scope

- 본 정책의 의무 대상은 **Axiom 저장소 내부의 Legislator 페르소나** — 명제 입법자(`legislator.nim`)다. **BYO 고객 외부 에이전트**(고객이 자신의 AI 에이전트로 명제를 제출하는 BYO Agent intake — `ax prove --proposals`, [byo_agent_proposition_contract.md](./byo_agent_proposition_contract.md))는 Legislator 페르소나가 **아니다** — AGENTS.md §0.2a와 본 정책의 Leanstral 전용 의무는 고객 외부 에이전트에 **적용되지 않는다**(2026-11-02 범위 명확화).
- 고객 외부 에이전트는 Axiom의 명제 입법을 수행하지 않는다 — 그 제출물은 커밋된 카탈로그 specId의 참조·파라미터화에 한정되고(`soExplicit` 신규 약속화는 인간 커밋 경로 전용), `explanation`은 증거가 아니며(byo_agent_proposition_contract.md §2·§5), 검증 판정은 기존 결정적 레인(`ax prove`)이 생산한다. 본 정책의 Enforcement는 Axiom 내부 Legislator 모듈에 한정된다.

## Enforcement

1. **Compile-time**: `legislator.nim` MUST import `leanstral_gateway` and transitively call `callLeanstral`.
2. **Architecture gate**: `nimtry` may be extended to verify that `legislator.nim` does not contain static heuristic imports (e.g. `core/verification_unit`) without an accompanying LLM gateway import.
3. **Runtime**: Any `LegislatorArtifact` produced without LLM invocation is considered invalid and MUST be rejected by the pipeline.

## History

- **2026-06-04**: Policy enacted after Notion Spec v0.3.7 audit revealed `legislator.nim` was using only static heuristics (`VerificationUnit.runSelfHealing`, `selectEvolutionHit`, `buildRefinedInvariant`) with no LLM invocation.
