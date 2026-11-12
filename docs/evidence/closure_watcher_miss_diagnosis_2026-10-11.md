# closure-watcher 결손 슬롯 진단 + 드리프트 이슈 멱등성 (2026-10-11)

선행: `closure_watcher_operational_addendum_2026-10-11.md` §5 — 슬롯 원장
(expected 7 / observed 5 / missed 2, 결손 원인 미분류). 본 문서는 그 결손 2건의
원인을 기계적으로 분류하고, 원장 수집을 전 이벤트 전수 census로 확장하며,
드리프트 추적 이슈의 멱등 upsert 상태 기계를 착지한 기록이다.

## 1. 결손 슬롯 원인 분류 — 양쪽 모두 **high-load drop**

대상 슬롯: **2026-10-10T06:17Z**, **2026-10-11T06:17Z** (cron '17 */6 * * *' 격자,
등록 시점 2026-10-09T21:20:30Z 이후 7슬롯 중 미관측 2건).

방법: runs API의 created 범위 필터로 **모든 이벤트**(schedule·workflow_dispatch)의
런을 전수 수집했다. 해당 워크플로의 전체 런 수는 `total_count=9`로 1,000건 필터
상한과 무관하다 — 누락 가능성 없는 전수 census다. 슬롯 귀속은 기존 계약(run_started_at
기준, 지연 런은 지연 창에서 귀속)을 유지한다.

| 증거 | 10-10 06:17Z | 10-11 06:17Z |
|---|---|---|
| 슬롯 창 내 런 기록 (전 이벤트) | **0건** | **0건** (dispatch 3건은 전부 슬롯 +3.6h 이후 생성 — 아래) |
| 슬롯 시점 그룹 상태 | 유휴 — 직전 런 38028948066 완료 05:53:10Z (슬롯 23.8분 전) | 유휴 — 직전 런 38115808935 완료 05:46:26Z (슬롯 30.5분 전) |
| cancelled 런 (원장 전체) | 0건 | 0건 |

원인 클래스 판정(공식 문서 대조):

- **pending-replacement 기각**: 기본 동시성(1 running + 1 pending)에서 신규
  pending이 이전 pending을 대체할 때 대체된 런은 **cancelled 기록을 남긴다**
  (docs.github.com, *Skipping queued workflow runs / concurrency*: "any
  additional pending runs cancel the previous one"). census상 cancelled 런이
  0건이고 슬롯 시점 그룹이 유휴(대체할 pending도, 대체할 running도 없음) —
  대체는 발생하지 않았다.
- **manual/cancellation 기각**: 위와 동일 — cancelled 런 0건.
- **competing-entry 기각**: 10-11 창 내 dispatch 런 3건(38130079957 09:55:13Z,
  38130258653 09:58:15Z, 38131967208 10:26:41Z)은 슬롯 +3.6~4.2h 이후 생성이다.
  그룹은 05:46:26Z부터 유휴였으므로, 06:17 firing이 런으로 생성됐다면 수 분 내
  시작됐을 것이다(대기할 running이 없음). 생성 자체가 안 된 것이다.
- **high-load drop 채택**: 공식 문서는 고부하 시 scheduled 실행이 지연되고 일부가
  **폐기**될 수 있음을 명시한다(docs.github.com, *Triggers that cause workflows
  to run / schedule event*: "The schedule event can be delayed during periods of
  high loads of GitHub Actions workflow runs... If the load is sufficiently high
  enough, some queued jobs may be dropped"). SLA는 없다. 양 결손 모두 이
  클래스다 — 부재만이 증거인 클래스(addendum §5의 "런 기록 전무" 관측과 일치).
- 상관 관계(인과 주장 아님): 양 결손 모두 06:17Z 슬롯이며, 직전 00:17Z 슬롯의 런이
  양일 모두 +5.5h 지연(05:45/05:51Z 발화)돼 같은 심야 고부하 밴드에 놓였다. GitHub의
  고부하 설명("High load times include the start of every hour")과 정합하는
  관측이지만 단 2표본이므로 인과 단정하지 않는다.

## 2. `queue: max` 판정 — **미채택**

`queue: max`(concurrency 블록, GA — cancel-in-progress false/unset 하에서 최대
100 pending 대기, docs.github.com *control-workflow-concurrency* + 2026-05
changelog)는 **pending 대체(cancellation)만 방지한다**. 본 결손 2건의 원인 클래스는
pending 대체가 아니라 생성 자체의 부재(드롭)이므로 queue: max는 이 결손에
무효다 — 근거 없는 설정 추가는 금지(최소 변경 원칙)하므로 채택하지 않는다.

잔여 리스크(문서화된 유지): 고부하 드롭은 재발할 수 있다. 완화는 (a) :17 off-hour
cron 유지(공식 권고 — 정각 회파), (b) 완료 조건을 충족하는 원장 관측 — **W=60
(N≥60 슬롯 = 15일×4슬롯)**: 첫 슬롯 2026-10-10T00:17Z .. 제60 슬롯
2026-10-24T18:17Z, 마지막 슬롯의 +6h 결손 컷오프 경과 후 **2026-10-25T00:17Z
이후** 최종 수집. 기존 "14일 원장(W=56, 2026-10-24 경)" 목표는 95% 기준 미달로
**정정**된다(§5 산술 — 정확 이항: 56/0 상계 5.21% > 5% FAIL, 60/0 → 4.87% ≤ 5%
PASS). queue: max 재판단은 그 데이터 이후 별도 슬라이스에서 — workflow 헤더의
follow-up 노트를 본 판정으로 갱신했다.

## 3. 원장 수집의 재현 가능화 (전 이벤트 census 확장)

`tools/ci/closure_watcher_slot_ledger.py`를 schedule 전용 필터에서 **전 이벤트
census**로 확장했다. 결손 슬롯에 대해 `cause_class`(pending-replacement /
no-record-high-load-drop)와 `competing_entries`(창 내 전 이벤트 런),
`last_run_before_slot`(그룹 유휴 증거 — 완료 시각 대조)를 기록한다. 원인 분류는
기계 판정이다: 창 내 cancelled 런 존재 = 유일한 대체 서명, 그 외 무기록 =
드롭 클래스.

재현 명령(addendum 창 고정 — 본 문서 §1 수치):

```
python3 tools/ci/closure_watcher_slot_ledger.py --repo Archright/Axiom \
  --registered-after 2026-10-09T21:20:30Z \
  --window-start 2026-10-09T21:20:31Z --window-end 2026-10-11T12:54:58Z \
  --out-json /tmp/ledger.json --out-md /tmp/ledger.md
```

확장 도구로 기존 addendum 원장 수치(7/5/2/3/2, cancelled 0, hollow 0,
unattributed 0)를 그대로 재현함을 확인했다 — 스키마는 추가 전용(backward
compatible)이다. 수정 원장(전체 창, 수집 2026-10-11T13:44:07Z):
`closure_watcher_slot_ledger_hardening_2026-10-11.{json,md}` — miss_causes
`{"no-record-high-load-drop": 2}`.

## 4. 드리프트 추적 이슈 멱등 upsert 상태 기계 (Task 2)

불변식: **OPEN 추적 이슈 ⇔ 라이브 드리프트** (양방향 결정론적).

| 전이 | 수행자 | 동작 |
|---|---|---|
| 드리프트 최초 관측 | report (if: failure) | 생성 — 기존 마커 토큰 검색(`closure mismatch in:title`)으로 계열 식별 |
| 동일 계열 추가 관측 | report (if: failure) | **코멘트 추가**(HEAD·run URL·차집합) — 중복 생성 금지. 동일 런 재시도는 run URL로 중복 억제(멱등 no-op) |
| 탐지 녹색 | sweep resolve 스텝 (detect success에서만) | **해결 코멘트와 종결** — detect 녹색 = 라이브 드리프트 부재 |
| 이미 종결된 이슈 | report/sweep 모두 | open 검색에서 제외 → 재발 시 새 관측이 재생성(상태 기계 자기 수렴) |

- 테스트 이슈(`[closure-watcher-test]` 마커 + 동일 런 sweep + crash-safe)는
  기존 계약 그대로 유지 — 상호 오염 없음(검색 토큰 분리). fixture 시험 런은
  detect가 적색이므로 resolve 스텝이 발화할 수 없다(실드리프트 종결 오염 불가).
  upsert 분기는 실/시험 양 모드가 동일하게 통과한다(모드별 차이는 TITLE/SEARCH/
  가이드뿐) — 구 시험 모드의 "열린 마커 이슈 존재 시 생성 생략"은 후속 관측을
  조용히 소실시키는 마스킹이므로 동일 upsert로 교체됐다. 이 덕분에 upsert 기계는
  마커 채널에서 종단간 검증 가능하다(남은 열린 마커 이슈에 관측 추가 → sweep
  종결 수렴).
- report의 구 동작("열린 이슈 존재 시 생성 생략")은 후속 관측이 소실되는
  마스킹이었다 — upsert로 교체하되 run URL 재실행 억제를 추가해 멱등을 보존한다.
- 감시자 무권한 불변식 유지: 본 변경은 관측·보고 표면만이며 config/ 정책 SSOT을
  수정하지 않고 merge admission을 차단하지 않는다.

## 5. 완료 조건 산술(W≥60) + 사전 등록 가설 — 정정·추가 (2026-10-11 리뷰 반영)

**완료 조건 정정**: "0 missed"의 95% 신뢰 주장은 정확 이항 상계로 판정한다 —
0결손 관측에서 일측 95% 상계는 p_UB = 1 − 0.05^(1/N):

| N (슬롯) | 0결손 시 일측 95% 상계 | 5% 기준 |
|---|---|---|
| 56 (14일×4 — 기존 목표) | 1 − 0.05^(1/56) ≈ **5.21%** | **미달 (FAIL)** |
| 60 (15일×4) | 1 − 0.05^(1/60) ≈ **4.87%** | 충족 (PASS) |

rule of three 근사(3/N)도 동일 결론이다: 56 → 5.36%, 60 → 5.00%. 따라서 완료
조건은 **N≥60 슬롯 = 15일 창**으로 확정한다 — 관측 창은 첫 슬롯
2026-10-10T00:17Z부터 제60 슬롯 2026-10-24T18:17Z까지이고, 마지막 슬롯의 +6h
결손 컷오프 경과 후 **2026-10-25T00:17Z 이후** 최종 수집이 완료 조건 시점이다.
addendum §6의 "14일 원장(W=56 슬롯) 완성 — 2026-10-24 경 재수집" 목표는 본
산술로 **정정**된다. 원장 도구(tools/ci/closure_watcher_slot_ledger.py)의 기본
창(--days)도 14→15일로 정렬했고 docstring에 동일 산술을 기록했다.

**사전 등록 가설 (pre-registered — 결손을 확정으로 닫지 않음)**: 두 결손은
**연속일(10-10·10-11)의 동일 06:17Z 슬롯**이며, 각각 직전 00:17Z 런의 극단 지연
(+334.8/+328.3분 — 05:51:50Z·05:45:18Z 발화) 직후에 놓여 있다. 재수집 창(위
완료 조건 창)에서 다음과 같이 판정한다:

- **가설 H (watchability 결함)**: 06:17Z 슬롯이 재수집 창에서 **반복 결손(또는
  반복 극단 지연)**되면, 이는 무작위 드롭이 아니라 **일일 탐지 간격 2배화
  결함**이다 — 심야 밴드에서 지연된 00:17Z 런이 06:17Z 슬롯을 흡수/폐기하는
  스케줄러 패턴으로, 실 드리프트 탐지 간격이 12h까지 열리는 watchability
  결함으로 분류하고 수선 슬라이스(예: 06:17Z cron 이동·스케줄 중복화)의 근거로
  삼는다.
- **반증 조건**: 재수집 창에서 06:17Z 슬롯이 정상 발화되거나, 결손이 다른
  슬롯에서 산발적으로 발생하면 가설 H는 **기각**되며 본 문서 §1의 high-load
  drop(무작위 클래스) 판정이 유지된다.

본 문서 §1의 원인 분류는 현재 관측의 기록일 뿐이며, 가설 H의 채택·기각은
재수집 원장의 기계적 판정에 맡긴다 — 슬롯별 결손·지연 분포는 확장된 원장 도구가
slot 단위로 기록한다.

## 6. 신뢰 한계 (정정 반영)

rule of three — "0 missed"의 95% 신뢰 주장은 N≥60 슬롯(15일)을 요구한다(§5
산술 — 14일/56슬롯은 95% 기준 미달). 본 진단은 결손 2건의 **원인 분류**이지
결손률의 신뢰 진술이 아니다. 완료 조건 수집 시점은 **2026-10-25T00:17Z 이후**
(제60 슬롯 2026-10-24T18:17Z + 6h 결손 컷오프; §5)로 정정된다.
