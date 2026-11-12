# S5 관측: stale-base 중립 PR의 candidate-delta 분류

- 목적: 핀 회전이 선착지한 뒤 파생된 중립 PR이 회전으로 오분류되지 않는지의 운영 실측.
- 대상: 본 문서 추가(비closure 파일) — closure 멤버 변경 없음.
- 기대: `qualification: NORMAL` — 기준선 드리프트(핀 재앵커 2회: c1ed88be / 516f5878·73a00289)가
  본 PR에 귀속되지 않음. 구 식(`derivedH == derivedB`)이라면 오판 가능했던 시나리오.
- 판정 근거: `closureChange = (derived(M) != derived(B))`, M = merge(B, H) (ADR-0025 Amendment F).
