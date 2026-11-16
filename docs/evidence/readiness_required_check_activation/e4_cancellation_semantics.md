# E4 — 취소 의미론: cancelled는 success가 아니다 (PR #126)

> DEBT#537 청산 증거 체인의 E4. 워크플로 실행 중 취소가 required check를
> success로 위장하지 않는지 관측한다(V1 제약: check-run 수준 관측 — 큐 진입 없음).
> 원본 관측: `raw/pr2_observations_pr2c.json`, `raw/pr2_checks_pr2c.txt`.

## §1. 프로브 설계 (PR-2c)

- **PR #126** `probe/pr2c-cancel-observation` (head `b8b612f0be2bea09bcf28a632d49081d8966b270`),
  main 위 **empty commit**(zero diff) — 취소 의미론 관측 외 어떤 실패도 유도하지 않는다.
- 실행기: readiness-verdict check-run이 `in_progress` 진입 시점을 폴링으로 포착한 뒤
  `gh run cancel`로 해당 run을 취소한다.

## §2. 관측 (2026-11-16 UTC, run 43916918843)

| 항목 | 관측값 |
|---|---|
| 취소 시점 | readiness-verdict 잡 in_progress 진입 직후 (17:23:15Z 개시, 17:23:34Z 취소 종료) |
| 취소 명령 | `gh run cancel 43916918843` (관측 스크립트 pr2c 모드의 유일한 쓰기 동작) |
| readiness-verdict check-run | status=completed, **conclusion=cancelled** (NOT success) |
| axiom-operational-slice check-run | completed/success (취소 전에 E2E 잡은 종료) |
| PR 상태 | `mergeable_state: blocked`, **0 병합**, 관측 후 미병합 close |

## §3. 증명하는 것

**취소된 required check는 success로 보고되지 않는다** — 워크플로 취소는 병합 허가가
아니라 차단으로 귀결된다(fail-closed). 스펙 §3 매핑(UNKNOWN/불일치 → failure →
거부)과 함께, required check의 가능한 모든 비성공 종료 상태(실패·취소·미보고)가
병합 차단으로 수렴함을 E2(실패)·E3(미집행 아님 관측)·E4(취소)로 관측했다.
