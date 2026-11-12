# ADR-0010: CI Baseline Gate & Ephemeral Proof Pipeline

## Status
Approved (2026-08-03, human architect)

## Context
CI에서 ax baseline check가 의미 없는 게이트 리스크 (§0.9 극장: fail-open/fail-closed 모호).
CircleCI 클린 체크아웃에서 src/verification/certificates/가 0개 (gitignore).

## Decision
1. **ax scope hash**: 입력 스코프(source+config+scope.lock) 지문 — 런타임 읽기 전용.
2. **Single Hydrate Path**: Fast Path 제거, Set-Membership 단일 SSOT.
3. **매크로 I/O 격리**: generateAxiomInit의 writeFile 제거 → lock은 hermetic_build/ax scope lock.
4. **TCB provenance 진실 분리**: parseSolverProvenance spZ3SAT 기본값 제거, Z3 실사용 경로만 Raw+Hash.
5. **baseline Exit 계약**: totalCount==0 → Exit 2, VKD 후퇴 → Exit 1, 유지/상승 → Exit 0.
6. **.axiom/vault**: 로컬 휘발성 유지 — CI 캐시에 넣지 않음 (§0.2/§0.9, Zombie Certs 원천 차단).

## Consequences
- CI 증명 회귀 방지, 결정론(§0.2), 극장 방지(§0.9), 브랜치 격리.

## References
- docs/spec/hermetic_gate_framework.md
- AGENTS.md §0.2/§0.9/§-1
