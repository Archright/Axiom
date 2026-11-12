# Baseline 고정 — eaed53d8a (immutable)

> 날짜: 2026-09-05 · **Baseline = `eaed53d8a`** (feat(experiment-acceleration): canonical execution semantics + selection infrastructure + plan-driven prove (S0–S4 wiring complete))

## 1. 고정 선언

`eaed53d8a`는 **S0–S4 correctness substrate의 immutable checkpoint**이다. 이후 모든 CI rollout 변경·측정·회귀 판정의 비교 기준:

```
Baseline = eaed53d8a
```

## 2. 분리 원칙 (섞지 않음)

| 계층 | 상태 |
|---|---|
| S0–S4 correctness substrate (설계·타입·선택·plan·실행·패키지 캐시) | **frozen at eaed53d8a** |
| CI rollout (shadow→enforce, ci.yml 관련) | **new change** — 문제 발생 시 원인을 rollout에 정확히 귀속 |

CI rollout 중 결함이 발견되면 기반이 아닌 rollout 변경으로 원인을 귀속한다.

## 3. 이 시점의 검증 상태 (커밋 직전 기록)

- 게이트: 16게이트(워크트리) + pre-commit 훅(nim_check/anti_theater/layer/stale-cert) + push-admissibility(70/70) 전부 PASS
- 훅이 실제 차단·수정한 결함 3건: 극장 1(benchmark_cost_probe 오류 삼킴), 레이어 6(tools→verification whitelist), stale 인증서 1(NO_OBLIGATION 전환)
- pruning 입증: T_full 45.4s vs T_accelerated 34.9s (요청 5→4), Selected 4/23
- 주요 산출물: docs/spec/canonical_execution_semantics.md · docs/audit/selection_independence_audit.md · docs/reports/(checkpoint·cost_probe·parity·measurements·infra_approval) · data/benchmarks/(gitignored)

## 4. 기준점 이후 허용되는 변경

- CI rollout 계약·shadow 자산 (C2/C4) — 기반 코드 미변경
- 측정/문서 (C3/C6 등)
- governance 문서 교정 (rules_workflow.md stale 참조 등 — 별도 커밋)