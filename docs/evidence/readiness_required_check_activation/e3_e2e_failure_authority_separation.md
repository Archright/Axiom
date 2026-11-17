# E3 — E2E 실패 전파 관측: 권한 분리와 fail-closed (PR #125)

> DEBT#537 청산 증거 체인의 E3. 스펙 §4 "스킵=Success 함정 방어"의 실험 관측 —
> 선행 E2E 잡이 실패해도 판정 잡이 실행되는지(`needs` + `if: !cancelled()`), 그리고
> E2E 실패가 병합 차단으로 이어지는 경로가 무엇인지. 원본 관측:
> `raw/pr2_observations_pr2b.json`, `raw/pr2_checks_pr2b.txt`.

## §1. 프로브 설계 (PR-2b)

- **돌연변이**: `tests/gateway/deterministic_parallel_proof_test.nim:294` EXIT PIN
  `serial==1` → `serial==0` (래칫 단계 E2E 실패 유도).
- **PR #125** `probe/pr2b-e2e-failure` (head `71f6641c5cefa35742dd31940850ff5751afa90e`),
  병합 금지 프로브.

## §2. 관측 (2026-11-16 UTC, run 43914887490)

| 항목 | 관측값 |
|---|---|
| axiom-operational-slice (E2E 래칫) | **fail** (4m43s, 잡 133466259712) |
| readiness-verdict | **pass** (6m15s, 잡 133469521384) — 선행 실패 후에도 **실행되어 판정 산출** (`needs` + `!cancelled()` 계약 실증) |
| readiness-verdict 판정 원문 | `verdict: CONDITIONAL GO`, R1–R6·R8 = PASS, **R7 = FAIL** (기준선 상태 — E2/E5와 동일) |
| PR 상태 | `mergeable_state: blocked`, **0 병합**, 관측 후 미병합 close |
| 차단 주체 | E2E required check(axiom-operational-slice) FAILURE |

## §3. 증명하는 것 — authority-per-fact의 실측

1. **판정 잡은 선행 실패에 스킵되지 않는다** — `!cancelled()` 계약이 실제로 동작하여,
   판정이 "SKIPPED → success 위장"이 아니라 실행·보고된다(스킵=Success 함정 방어).
2. **E2E 실패는 그 잡 자체의 required check가 집행한다** — readiness-verdict는
   R1–R8 증거만 소비해 판정하고, E2E 레인의 성패를 중복 판정하지 않는다
   (같은 사실에 판정 권위가 두 개 존재하지 않는다 — 스펙 §1 위임 모델).
   결과적으로 병합은 **두 required check의 논리합(fail-closed)**으로 차단된다:
   E2E 실패 → axiom-operational-slice FAILURE → BLOCKED.
3. 이 관측은 설계 의도(판정 근거의 분리)이지 전파 누락 결함이 아니다 — E2E 레인의
   집행은 E2가, R1–R8 근거의 집행은 readiness-verdict가 각각 독점한다.
