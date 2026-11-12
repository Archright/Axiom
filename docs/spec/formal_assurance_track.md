# Formal Assurance Track — Productization Boundary (Architecture Decision Record)

Status: Accepted (frozen)
Date: 2026-08-13

## Context
Axiom의 검증 증거는 productization 이전에 하나의 결정론적 calculus로 통합되어야 한다. 그러나 전체 형태적 검증(IR semantics, semantic preservation, proof replay, independent checker, T1)은 릴리즈를 차단해서는 안 되는 별도의 장기 연구/엔지니어링 트랙이다. 본 ADR는 productization 경계를 동결하고, 후속 트랙의 계약(extension point)을 지금 바로 고정하되 실제 구현은 연기하기 위한 것이다.

## Decisions

1. **P0 (Trust Boundary), P1 (Evidence Calculus), P1.5 (VKD evidence wiring), P2 (Certificate Identity + provenance)**는 PRODUCTIZATION FOUNDATION이며 릴리즈에 **필수**이다. (네 가지 모두 DONE.)

2. **P3 (scalar subset + IR operational semantics), P4 (Nim → IR → QF_BV soundness), P5 (replayable proof contract), P6 (independent checker), P7 (first T1)**는 POST-PRODUCTIZATION FORMAL ASSURANCE TRACK이다. 이들의 **계약/extension point는 지금 바로 고정**되어 있다 (`docs/spec/evidence_calculus.md` 참조). 그러나 **구현은 연기**된다.

3. **T1은 릴리즈 blocker가 아니다.** T1의 부재는 제품 결함이 아니라 assurance 로드맵 상의 현재 위치이다. 제품은 현재의 assurance 수준(T0-style: 기록된 solver 증거, VKD=0)을 정직하게 명시하며, 과장하지 않는다.

4. **현재의 assurance 제한 사항은 반드시 정직하게 표현되어야 하며, 절대 숨겨져서는 안 된다.** (기록된 것 ≠ 신뢰된 것; Z3 unsat은 증명이 아니라 기록이다.)

## Phase Contracts (frozen now, implementation deferred)

- **P3**: Scalar subset 범위 + Canonical IR 문법 + IR operational semantics (`evalIR`) 필요
- **P4**: Theorem A (Nim subset → IR soundness) 및 Theorem B (IR → QF_BV soundness)
- **P5**: `axiom-proof-v1` proof artifact 계약; `proofArtifact` extension point
- **P6**: 독립 producer (Z3) ≠ 독립 checker (Axiom); `replay` extension point
- **P7**: T1 수락 기준 — formal spec + scalar IR + semantic proof + QF_BV + proof artifact + independent replay + complete provenance, 가장 작은 완전 함수에서; 목표는 **T1=1, VKD=6이 아님**.

## What this document prevents
이 문서는 기여자/에이전트가 "VKD를 올리기 위해 T1을 먼저 구축해야 한다"거나 "릴리즈 전에 IR semantics를 완성해야 한다"는 방향으로 설계를 되돌리는 것을 방지한다. 또한 현재의 assurance 제한 사항을 숨기거나 과장하는 것 역시 방지한다. productization 경계는 영구적이며, P3–P7의 계약만이 미래 구현을 위한 고정된 anchor이다.

## Definition of Done (productization exit line)
Axiom이 현재 가진 증거가 무엇인지, 그 증거로 무엇을 주장할 수 있는지, 그 주장이 어떻게 결정론적으로 계산되는지가 완전히 고정되어 있다.