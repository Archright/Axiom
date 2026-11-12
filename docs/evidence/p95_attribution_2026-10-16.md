# P95 귀속 분석 — 반복 실행 비용 vs 사건 꼬리 (2026-10-16)

> **종류**: 측정·분석 증거 기록. **질문**: PR→main 착지 P95를 가로막는 것은 매 런 반복되는 실행 비용인가, 드물게 발생하는 사건(venue-red→dequeue→수동 개입)의 꼬리인가.
> **선행 연구**: 없음 — SLO 선언(`ci_wall_clock_optimization_acceptance_2026-10-07.md:133-135`), 런 내 성분 분해, 사건 기록은 각자 존재하나 **두 축의 P95 기여도 비교는 본 기록이 최초**다. 기계 판독 파일: `data/ci_optimization/p95_attribution_2026-10-16.json`.
> **권위**: 런/잡 타임스탬프 = GitHub Actions API(초 해상도). 본 기록은 **Reporter다** — 병합 판정 권위(GitHub)·`go_matrix_s3_performance_verdict_2026-10-16.md`의 동결 기준을 대체하지 않는다.
> **소비처**: 다음 CI 최적화 레버의 우선순위 결정 입력 (§6).

---

## 1. 판정 (두 지표, 서로 다른 답)

| 지표 | 판정 | 근거 |
|---|---|---|
| **(i) merge_group wall P95 — SLO of record (480s)** | **반복 비용 지배 — 사건은 측정 집합 밖** | 등록 기준선 p50 923s·live p50 1000s(n=101) — **p50만으로 SLO p95 상한 위반**. 반사실: 판정 CAS FULL_REUSE(GO 0s) 런 wall 401–402s < 480s (`merge_latency_baseline_2026-10-12.md` §3.3). GO 스텝 p50 544s = wall의 59% |
| **(ii) 종단 PR→merged** | **사건이 꼬리(>1h)의 ~100%)를, 반복 비용이 평균을 소유** | 정상 착지 ~20분 vs 사건 시 40min–2h51m. 18일(큐 시대) 8건, 누적 전역 블록 ~8–9h, 착지 417건 중 2.5–3.5% 직접 차단, 착지율 반감(26.7→11.3/day, 10-13 사건 군집과 동행 — 저작량 교란 병기) |
| **SLO 480s 도달 가능성** | **등록된 레버 집합으로 불가** | 480s 도달엔 GO ≤ ~157s 필요. L레짐 s1a 실행 바닥 307.8s(Lean 커널 호출 — 캐시 불가, `go_critical_parallel_decomposition_2026-10-11.md` §4; 3밴드 = VM 속도 추첨 1:1.41:1.84, `r1_s1a_runtime_bimodal_measurement_2026-10-09.md`). GO 병렬화 후에도 p50 ≈ 684–800s |

**결론**: 두 축은 경쟁하지 않는다. SLO(지표 i)에는 반복 비용 절감만이, 종단 꼬리(지표 ii)에는 사건 workstream만이 기여한다. GO-critical 병렬화는 지표 (i)의 유일 등록-자격 레버였다(`attest_job_decomposition_2026-10-12.md` §6 "신규 고려자격 후보: 0개").

## 2. wall 분포 (전 수치 원 계산 경로)

| 데이터셋 | n | mean | p50 | p90/p95 | 비고 |
|---|---|---|---|---|---|
| 등록 기준선 10-11 | 25 | 848.4 | 923 | p90 976 | EXECUTED 23: 887.2±102.8; L층 16: 945.1±28.1 / H층 7: 754.9±86.0 (`merge_latency_baseline_2026-10-12.md`) |
| live 10-13→16 (pre-G2 포함) | 101 | 934.9 | 1000 | p95 **1148** | 실패 28건은 성공보다 142s **짧음**(초기 레인 킬) — 실패는 wall-P95를 눌러줌; 사건 비용은 캘린더 시간으로 발생 |
| **post-G2** (10-15 19:34Z→) | 24 | 951 | 977 | p90 1022 | 전부 success — §3 잡 분해 |

## 3. post-G2 잡 분해 (n=24, success 전수, 초)

| 성분 | mean | p50 | min–max |
|---|---|---|---|
| go-critical-lane (0) | 382 | 393 | 310–425 |
| go-critical-lane (1) | 295 | 306 | 214–329 |
| **build-base-artifacts (job1)** | **272** | **287** | **66–576** ← 웜/콜드 격차의 본체 |
| attest 소비자 (admission-check) | ~114 | — | 직렬 GO 포함 시 552s → 레인 이관 후 |
| verdict / mint-prepare / mint-publish | 46 / 38 / 57 | | |
| observe·bsec·closure-deriver | 283 / 97 / 86 | | 병렬 leg |

## 4. G2 착지 상태 — 성능 판정과 그 교란

- **G2는 main에 착지·운영 중**: 승격 `0848662fb`(10-15 18:21Z) + 긴급 수복 `91a4aee7c`(19:34Z, 누락된 레인 잡 정의 복원 — 초기 승격 결함으로 큐 BLOCKED fail-closed). 직렬 스텝 제거·2-레인 매트릭스·rollup skipped→red 가드·소비 엣지(`admission-check` needs `go-critical-lane`)·prereg 2종 — 전부 main에서 확인.
- **S3 성능 판정(선행 기록)**: 신뢰성 PASS(14/14, 레인 red 0) · **성능 FAIL — D3 중앙값 1727s, 기준선 1556s 대비 +171s 악화(요구 ≤1256s)** · D4-composite 376.0s PASS(직렬 545s 대비 **−169s**) · 비용 +2.0% → **세대 유지 결정 기록** (`go_matrix_s3_performance_verdict_2026-10-16.md`).
- **본 기록이 추가하는 교란 사실**: S3 판정 창은 10-16 06:11Z에 종료했고 **G1 Lever-B(publisher 부활)는 07:19Z** — 즉 **성능 FAIL은 ci-cache-publisher 사망(10-12 10:05Z, `slice_b_s3_validation_2026-10-15.md:40`)이 만든 콜드 job1(§3: 66→576s) 조건에서만 측정됐다.** job1 콜드 인플레이션(평균 272s vs 웜 66s = +206s)은 D3 악화분(+171s)과 동등 이상의 규모다.
- **post-Lever-B 초기 신호 (n=6, ≥07:19Z)**: 947, 1019, 1000, 752, 902, **716** — 최신 2런이 최저권. 최저 런(38891209338) 분해 = job1 **66s(웜)** + lane-0 361 + 소비자 122 → **웜-바닥 ≈716s 관측**. 회복 방향이나 **본 기록은 재판정이 아니다** — 표본 확대 후 S3 재판정은 별도 차량.

## 5. 사건 인벤토리 (지표 ii의 근거 — 18일 8건)

10-04 NO_CERT 순서(~202min, `landing_latency_cutover_2026-10-05.md`) · 10-05 ruleset/큐 ~49min + #482 ~40min(`pr_liveness_fail_closed_2026-10-05.md`) · 10-09 #651/#652 deadlock(`incident_pinned_callee_deadlock_bypass_2026-10-09.md`) + 큐 블록 1h48m(`queue_unblock_track_2026-10-10.md`) · 10-12 #794 parse-poison 2h51m(`emergency_evaluate_window_2026-10-12.md`) · 10-13 #814/#815 venue RED→직접 머지 우회(`docs/incidents/2026-10-13_pr814_pr815_direct_merge_audit.md` — 근본 원인 미해결) · 10-14 #828 GO 4-레인 콜드-링크 red-loop 2h02m(`mg_red_forensics_2026-10-14.md`, `emergency_evaluate_window_2026-10-14.md`).

## 6. 다음 레버 순위 (본 분석의 소비처)

1. **job1 콜드 제거 — publisher 부활 후 웜 복귀 확인·S3 재판정** (잠재 −206s; G1 Lever-B 착지, `g1_completion_2026-10-16.md` "S3 auto-pending on next code PR")
2. **판정 CAS 재사용률 상향** (φ_pay 0.9 → 인하; FULL_REUSE 401s가 상한 증명)
3. 비-GO 성분(verdict/mint/closure ≈230s) · 4. VM 레짐(통제 불가 영역 — 러너 정책과 별도) · 5. **사건 꼬리 workstream(venue-red)** — 지표 (ii) 전용, §5가 정당화 수치

## 7. 재현 명령

```bash
gh api "/repos/Archright/Axiom/actions/runs?event=merge_group&per_page=100" --paginate \
  --jq '.workflow_runs[] | select(.name=="admission-gate") | [.id,.conclusion,.created_at,.updated_at] | @tsv'
for RUN in <ids>; do gh api /repos/Archright/Axiom/actions/runs/$RUN/jobs \
  --jq '.jobs[] | select(.started_at != null) | [.name,.conclusion,.started_at,.completed_at] | @tsv'; done
git log --merges --since=2026-09-29 --pretty=%H | wc -l   # 착지 수 (417)
```

## 8. 한계 (정직 기록)

live 런 수준 API로 L/H 레짐 분리 불가(a-restore 마커는 잡 로그 전용) · 종단 지연 전수 분포 부재(사례 기반 추정) · post-Lever-B n=6 · D3 비교 창은 h4 세대 결함 사건(#862 D3 7080s) 포함 · 관측은 GET 전용.
