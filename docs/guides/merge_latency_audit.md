# merge_latency_audit.sh — 병합 지연 측정 하니스 사용법

> **도구**: `tools/ci/merge_latency_audit.sh` — measure→change→measure→re-check 루프의 BEFORE/AFTER 측정 계기.
> **계약 근거**: `docs/evidence/e3_measurement_contract_2026-10-11.md` (§5.2·§7.1·§7.2) + `docs/evidence/e3_amendment_a2_2026-10-11.md` (A2.1·A2.2.7).
> **등록 베이스라인**: `docs/evidence/merge_latency_baseline_2026-10-12.md` + `data/merge_latency/baseline_2026-10-11.*`.
> **성격**: GET-only 관측기(Reporter) — 판정 권위 없음 (AGENTS.md §2.3 Authority ≠ Adapter). `/timing` 엔드포인트는 호출하지 않는다 (E3 §7.1 금지 준수).

## 측정 정의 (사전 고정 — 데이터 관측 후 재조정 금지)

런 1건당 성분:

| 성분 | 정의 |
|---|---|
| `wall_s` | `updated_at − run_started_at` (E3 §7.1) |
| `dur_sum_s` | 실행된(=skipped 제외, success·failure 모두) job 구간의 합집합 크기 — 평행 job에 가려진 구간은 0 (망원 항등식: `dur_sum + gaps_sum = 마지막 job 종료 − 첫 job 시작`) |
| `gaps_sum_s` | 임계경로 인접 세그먼트 사이 대기 (`선행 completed_at → 후속 started_at`) |
| `residual_s` | `wall − dur_sum − gaps_sum` (시작·종료 오프셋; 관측 범위 1–5 s — 이탈 시 job 세트 변화 신호) |
| `go_step_s` | 소비 job의 `[check] GO-critical` 스텝 합 (E3 §5.1 이름 규칙) |
| `a_restore_ms` | `##[end-action id=__self.a-restore …duration_ms=…]` 로그 필드 (E3 §5.2 권위) |

층: **분류** = A2.1.2 기계 판별 (SKIP>0 ∧ RUN=0 → `FULL_REUSE`, SKIP=0 ∧ RUN>0 → `EXECUTED`, 혼합 → `PARTIAL_REUSE(k)`, 로그 소실 → `UNKNOWN_LOG`). **레짐** = a-restore ms ≤/> 40,000 (L/H), 마커 소실 → `unknown` + A2.2.7 fail-closed(더 엄격한 H 밴드 적용).

통계 규칙: **소요 통계(dur/gaps/residual/go_step)의 분모는 EXECUTED 런만** — FULL_REUSE는 별도 층으로 보고되고 절대 소요 통계에 평균되지 않는다. 운영 wall-clock은 전체를 유지한다. 보고: mean/p50/p90/min/max + 표본 sd(n−1).

## 모드

### measure — 런 집합 1개 측정

```bash
# 런 ID 목록
tools/ci/merge_latency_audit.sh --runs ID1,ID2,… --out data/merge_latency/이름

# 시간 창 (≤1일 슬라이스 스캔 + 1,000건 결과-상한 하드페일 — 무음 잘림 방지)
tools/ci/merge_latency_audit.sh --since 2026-10-11T00:00:00Z --until 2026-10-12T00:00:00Z

# 옵션: --boundary-note "경계 기록" (출력물에 기록 — 변경은 창 중간에 착지한다, PR #729 선례)
#       --no-logs   로그 채널 생략 → 분류·레짐 UNKNOWN (fail-closed 기록)
#       --now ISO8601  collected_at 고정 (재현 검증용)
```

출력: `PREFIX.runs.jsonl`(런별 레코드 — jobs 원시 듀레이션·갭 세그먼트·임계경로·분류 근거 완비) + `PREFIX.summary.json`(성분×층 통계 + 종료 입력).

### compare — BEFORE/AFTER 비교 (루프의 재검증 단계)

```bash
tools/ci/merge_latency_audit.sh \
  --compare data/merge_latency/baseline_2026-10-11.runs.jsonl data/merge_latency/after.runs.jsonl \
  --boundary-note "착지 변경: <PR/커밋> — 경계 <시각>" \
  --out data/merge_latency/compare-<변경-ID>
```

양변은 런 ID 쉼표열, `@ID파일`, 또는 기존 `*.runs.jsonl` 아티팩트(재인출 없이 재사용) 어느 쪽이든 된다. 출력: `PREFIX.compare.json` + `PREFIX.compare.md`.

표: `component | baseline mean±sd | after mean±sd | delta | Δ_L | Δ_H | REUSED counts/side` — 성분별 delta와 **레짐 분할 delta**를 나란히 보고한다(레짐 혼합 변화와 실개선의 구별 — §3.4 경고). `--compare`로 두 *artifact*를 주면 API 재인출 없이 즉시 재계산된다.

### snet — 핸드오프 변경의 S_net 헬퍼

```bash
tools/ci/merge_latency_audit.sh --snet \
  --baseline <BEFORE runs> --after <AFTER runs> \
  --producer-steps '\[check\] Upload folded nimcache' \
  --consumer-steps '\[check\] Download base-built artifacts|\[check\] Verify artifact manifest' \
  [--producer-job RE] [--consumer-job RE]      # job 이름으로 범위 한정
  [--baseline-provision 64.7]                   # T_old_provision 상수 오버라이드
```

계산: `S_net = T_old_provision − ΔT_producer − ΔT_consumer`.
- `T_old_provision` = 기본값: 베이스라인 런의 producer 스텝 **보이는 벽시계** 평균 (또는 `--baseline-provision` 상수).
- `ΔT_producer` = after−baseline producer visible 평균.
- `ΔT_consumer` = after−baseline consumer visible 평균 (신규 추가 비용이면 전체가 delta).
- **겹침 이중계산 없음**: 스텝이 평행 선행 job 구간에 가려지면 보이는 몫만 계수(스텝 구간 − 타 job 구간의 합집합). 같은 집합 내 겹치는 스텝은 합집합으로 1회 계수.

출력: `PREFIX.snet.json` + `PREFIX.snet.md` (런별 visible/total/hidden 표 포함).

## variance-aware 종료 지원

모든 요약/비교 출력은 성분별 sd와 `required_min_saving_s = max(resolution_s=1, sd_baseline, sd_after)`를 낸다. 루프 종료 규칙 — "다음 레버의 기대 절감이 측정 분해능과 런간 변동을 모두 초과하지 못하면 종료" — 를 이 값으로 기계 판정한다.

## 결과 해석 수칙

1. delta 주장에는 반드시 **레짐 분할 delta**를 나란히 첨부한다 (레짐 혼합 변화 ←→ 실개선 구별).
2. FULL_REUSE 런은 운영 wall에는 남고 **소요 통계에서는 분리**된다 — REUSED가 섞일 때 풀링 평균으로 "개선"을 주장하지 않는다.
3. `residual_s` 이탈(>5 s)은 성분 변화가 아니라 **job 세트 구조 변화** 신호 — 먼저 jobs 원시 듀레이션을 확인한다.
4. 결론 기록은 `docs/evidence/`에 새 날짜 문서로, 본 문서와 등록 베이스라인을 인용한다.

## 순수성·한계

- 모든 네트워크 호출은 API GET. 재실행·취소·쓰기 경로 없음. no-polling(런당 1패스).
- quirks: Q2(merge_group 로그는 `/actions/jobs/{id}/logs` 경유)·Q3(`--allow-escape-sequences` 필수) 준수. 재실행 런은 attempt별 별도 관측.
- 측정 기준은 API 초 해상도(±1 s). 7자리 로그 타임스탬프 채널이 필요한 정밀 판정(E3 Δ̂ 확증)은 본 도구 소비 대상이 아니다 (A2.3.4 방화벽).
- Σdur/Σgaps 분할은 API 초 반올림 경계의 영향을 받는다 (등록 베이스라인 문서 §7 — dur+gaps 합과 wall·residual은 경계 정의에 불변).
- exit codes: 0 정상(UNKNOWN 기록 포함), 1 하드페일(상한 초과·비-admission-gate 런·구조적 API 실패 — fail-closed), 2 사용 오류.
