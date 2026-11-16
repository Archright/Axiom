# 관측 보강 기록 — 잡 단위 created(queued) 시각 원천의 랜딩 문서 결속 (2026-11-16)

> **종류**: 관측 보강 기록 (evidence provenance note). 착지된 SLO 문서 2건(n=0 기록·창 등록)의 잡
> 수준 타임스탬프 원천이 랜딩 체인에 결속돼 있지 않았던 갭을 닫는다 — 분석 세션에서 인용된 "8회 ×
> 119 잡" 관측의 코호트·판독 규칙·재현 명령을 랜딩 문서로 등록한다. 본 문서는 **판정이 아니며**
> 측정 계약·창 등록의 어떤 값도 변경하지 않는다(append-only 보강 — 기존 문서 수정 0건).
> **권위**: 본 문서는 **Reporter**다 — GitHub merge authority(required checks·merge queue·MERGE
> commit)를 대체하지 않는다(AGENTS.md §2.3). 어떤 게이트도 본 문서의 값을 소비하지 않는다.
> **Date**: 2026-11-16 · **Branch**: `docs/slo-job-created-at-provenance-20261116` · **Scope**: 본 문서
> 1건(docs-only — 코드·워크플로우·게이트·핀·도구 변경 0건, trust surface 비관여, 정상 merge queue 경로).
> **관측 규율**: GET-only · `gh` 네이티브 인증(AGENTS.md §2.4) · REST core 5,000 req/h 이내 ·
> 타임스탬프 초 단위(±1s). **재검증 선언**: 본 문서의 핵심 수치(8런 잡 전수·created_at 존재·갭 통계)는
> 조사 서브에이전트 산출을 Reporter가 원본 GET으로 재검증한 뒤 재인용했다(census_dual_lane §6 셀프
> 한정의 동일 규율).

---

## §0. 상속·참조 권위 (본 문서는 아래를 대체하지 않는다)

| 권위 | 내용 | 위치 |
|---|---|---|
| 측정 계약(동결 본체) | 공식 지표·모집단·R-7·n≥30·관측 프로토콜·소급 수정 금지 — 본 문서는 계약 값을 1도 변경하지 않는다 | `docs/evidence/slo_official_measurement_prereg_2026-11-01.md` 전체 |
| 보강 대상 관측 기록 | 룩백 R1·§3.1 잡 분해 인용 지점 — 본 문서는 그 값을 수정하지 않고 잡 수준 원천을 결속해 보강한다 | `docs/evidence/slo_n0_fixed_window_record_2026-11-16.md` §3.1·§3.5 |
| 판정창 등록(계약 불변) | 본 문서는 창·모집단·판정 규칙에 관여하지 않는다(§4는 판독 투영 보강일 뿐) | `docs/evidence/slo_judgment_window_prereg_2026-11-16.md` |
| 잡 created_at quirk(정본 판독 규칙) | jobs-API 공식 문서 예시는 `created_at` 누락 — **실측 응답이 정본**(2026-11-03 등록, 120런·실행 잡 340 무결성, med 3s [2,39]) | `docs/spec/gh_run_observation_quirks.md` Q18 |
| 잡 시각 재현 명령 선례 | `gap = started_at − created_at`의 GET 재현 경로(§5 F-1(b), n=340) | `docs/evidence/census_dual_lane_unknown_closure_2026-11-03.md` §5 |
| skipped잡 타임스탬프 역전 quirk | skipped잡의 completed<started 관측 — '실행 안 됨' 처리, 해석 금지 | `docs/evidence/node24_merge_group_job_decomposition_2026-11-02.md` §7 ④·부록 A |

## §1. 갭 정의 — 무엇이 결속돼 있지 않았는가

- 착지된 SLO 문서 2건의 모든 `created_at`은 **런 수준**뿐이다(grep 전수 확인). 잡 수준 `created_at`
  (queued 시각) 투영은 창 등록 문서 §8 (4) 잡 재현 템플릿에도 없다(`[.id,.name,.started_at,
  .completed_at,.conclusion]` — `created_at` 부재).
- n0 기록 §3.1의 잡 수준 유일 증거는 "선행 심층 관측(최근 완료 3런 잡 분해)" — **미랜딩 관측 인용**
  (커맨드·run ID 없음). 분석 세션에서 인용된 "8회 × 119 잡" 관측의 코호트·원천도 랜딩 문서 어디에도
  존재하지 않았다.
- 결과: 잡 queued 시각을 읽는 판독 규칙(Q18 — 실측 응답이 정본)과 재현 명령이 SLO 문서 체인에서
  끊겨 있었다. 본 문서가 그 결속을 랜딩한다.

## §2. 코호트·관측 사실 (2026-11-16T05:2XZ 관측·재검증, GET-only)

**코호트 식별(역산 최적 일치 — 성격 명시)**: 룩백 R1(n0 기록 §3.1)의 **첫 8개 merge-queue 라운드**가
실행 잡 정확히 119개다 — "8회 × 119 잡" 실험 코호트로 특정된다. 해당 실험을 문자 그대로 기재한
랜딩 문서가 존재하지 않아, 식별은 라이브 잡 수 역산에 근거한다(§5 UNKNOWN (i)).

| run id | PR(head_branch) | conclusion | 잡 전수 | 실행 잡(conclusion≠skipped) | missing created_at | 실행잔 runner_group_id |
|---|---|---|---|---|---|---|
| 43671765678 | pr-78 | success | 26 | 15 | 0 | [0] |
| 43671902223 | pr-77 | success | 26 | 15 | 0 | [0] |
| 43673367785 | pr-79 | success | 26 | 15 | 0 | [0] |
| 43674152596 | pr-80 | success | 26 | 15 | 0 | [0] |
| 43676407342 | pr-81 | success | 26 | 15 | 0 | [0] |
| 43677390737 | pr-83 | success | 26 | 15 | 0 | [0] |
| 43677582560 | pr-82 | success | 26 | 15 | 0 | [0] |
| 43677909905 | pr-84 | **failure** | 26 | 14 | 0 | [0] |
| **합계** | — | 7 success·1 failure | **208** | **119**(7×15 + 14) | **0** | 전부 0(GHEC) |

- **잡 `created_at` 존재**: 8런 208잔 전부(실행잔 119/119 포함, 누락 0) — Q18 판독 규칙("실측 응답이
  정본")의 2026-11-16 재실측 일치.
- **created→started 갭(실행잔 119)**: **min 2s · med 3s · max 8s**(n=119 — §3 명령 재현). Q18의
  선행 관측(med 3s [2,39], n=340)과 동일 채널·동일 판독, 코호트가 달라 최대값만 다르다(관측 사실
  기록 — 일반화 주장 아님).
- 실행잔 전부 `runner_group_id=0`·`"GitHub Actions"` — n0 기록 §3.1 epoch 노트(GHEC 단일 epoch)와
  정합. 선행 인용이었던 "3런 심층 관측"보다 큰 표본(8런)으로 같은 사실을 랜딩 문서가 담는다.
- skipped잔(89)의 타임스탬프는 역전 완료 시각을 가리킬 수 있다(node24 §7 ④ — 해석 금지, 본 관측도
  해석하지 않는다).

## §3. 재현 명령 (GET 전용 — 잡 queued 시각의 유일 원천은 REST jobs 응답 본문)

```bash
# 8라운드 잡 전수 + 실행잔 판별 + created_at 존재·runner_group 확인
for rid in 43671765678 43671902223 43673367785 43674152596 43676407342 43677390737 43677582560 43677909905; do
  gh api "repos/Archright/Axiom/actions/runs/$rid/jobs?per_page=100&filter=all" \
    --jq '{total: .total_count, executed: ([.jobs[] | select(.conclusion != "skipped")] | length),
           missing_created: ([.jobs[] | select(.created_at == null)] | length),
           runner_groups: ([.jobs[] | select(.conclusion != "skipped") | .runner_group_id] | unique)}'
done
# created→started 갭 통계(실행잔 전수, 초 단위)
for rid in 43671765678 43671902223 43673367785 43674152596 43676407342 43677390737 43677582560 43677909905; do
  gh api "repos/Archright/Axiom/actions/runs/$rid/jobs?per_page=100&filter=all" \
    --jq '[.jobs[] | select(.conclusion != "skipped") | ((.started_at|fromdateiso8601)-(.created_at|fromdateiso8601))]'
done | jq -s 'add | {n:length, min:min, med:(sort|.[length/2|floor]), max:max}'
```

각 런의 잡 수(26) ≤ 100이므로 단일 페이지로 완결된다(total_count 대조로 확인 — 26/26). 잡 수준
질의의 페이지네이션 완결 판정 규칙은 Q18 판정 규칙(total_count와 수집 건수 대조)을 따른다.

**판독 규칙**: (i) 실행잔 판별자 `conclusion != "skipped"` (ii) skipped잡 타임스탬프는 해석 금지(역전
quirk — node24 §7 ④) (iii) 잡 `created_at`은 REST jobs 응답 본문에서만 존재한다 — 공식 문서 예시에
누락되므로(Q18) **문서 예시가 아니라 실측 응답이 정본**이다.

## §4. 창 등록 문서 §8 (4) 잡 투영의 보강 제안 (계약 변경 아님)

창 등록 문서 §8 (4)의 잡 재현 투영은 `[.id,.name,.started_at,.completed_at,.conclusion]`이다. 잡
queued 시각이 필요한 진단은 이 투영에 `created_at`을 **추가 판독**한다(본 문서 §3이 그 경로와 판독
규칙을 등록한다). 측정 계약 §6의 판정 동반값(진단 2값 `latest_attempt_wall`·`attempt_wall`)은 잡
`[started_at, completed_at]`만을 요구하므로, 본 보강은 **계약 요구사항을 변경하지 않는다** — 판독
가능 범위의 명시적 확장이다(창 등록 문서의 body는 불변 — 해당 투영 확장은 미래 판정 보고 문서가
본 문서를 참조해 채택한다).

## §5. 본 문서가 아닌 것 · 창 내 지위 · UNKNOWN

- **판정 아님** — P95·PASS/FAIL·창 종료와 무관하다. **기존 문서 수정 아님** — n0 기록·창 등록 문서의
  body는 불변(append-only 보강). **계약 변경 아님**(§4). **최적화 트리거 아님** — 갭 통계는 관측
  사실이며 자동 후속 작업을 만들지 않는다.
- **본 문서 착지 자체의 창 내 지위(정직 기록)**: 본 문서를 착지시키는 PR의 merge_group 라운드는
  등록 창(since 2026-11-16T04:36:26Z) **내의 자연 발생 트래픽**이다 — 업무 동기(원천 결속 갭의
  폐쇄)를 가진 실제 작업 PR이며, 측정용 차량 PR·창 종결을 위한 인위적 enqueue가 아니다(창 등록
  문서 §2 자연 누적 원칙 준수 — 등록 창은 착지 트래픽이 계속되는 실제 운영 상태를 측정한다).
- **UNKNOWN**: (i) "8회 × 119"를 문자 그대로 기재한 원문이 존재하지 않아 코호트 식별은 역산 최적
  일치다 — 원실험이 다른 8라운드 조합이었다면 코호트 식별만 정정하면 된다(갭 판정 자체는 불변:
  랜딩 결속 부재는 사실이었다). (ii) skipped잔 타임스탬프 역전의 플랫폼 내부 의미(node24가 UNKNOWN로
  둔 것과 동일). (iii) `workflow_job` webhook action의 실측 전집 — 공식 문서 payload 표는 3종
  (queued/in_progress/completed), `docs/adr/0039-workflow-job-webhook-non-adoption.md` F1은 4종
  (+`waiting`)으로 기록(상이 관측). webhook은 저장소에 0건 구성이라 수신 실측 불가 — REST jobs
  응답 본문 판독으로 충분하므로 본 결속에 영향 없다.
- 런 열거 한계(org 수준 목록 부재 등)는 n0 기록 §4 계승 — 본 문서는 잡 수준 질의만 다룬다.
