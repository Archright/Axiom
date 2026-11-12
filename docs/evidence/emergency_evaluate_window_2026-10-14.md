# 비상 evaluate 창 감사 기록 — 2026-10-14 (GO-critical 병렬화 원자 리버트, PR #829 착지)

> `docs/agents/quality-gates.md:69` §3.5 Emergency Override의 사후 문서화 의무와
> `docs/spec/github_ruleset_api_quirks.md` "비상 창 절차 사용 시 의무(HARD RULE)"에
> 따른 시간제 ruleset 전환(enforcement evaluate) 창의 감사 기록. 시각은 전부 UTC.
> 전환은 GitHub ruleset history(REST `…/rulesets/{id}/history`) 버전으로 교차 검증 완료.

## 사유

- 2026-10-14T05:02:17Z PR #826(병합 커밋 `3fafce5a25`) 착지로 attest 스테이지의
  GO-critical admission 스텝이 **4레인 병렬** regime으로 전환됐다(2c94c9914 병렬화 reland
  + c2142ec37 j4-cold-guard). 09:34:22Z의 #827 merge_group run 38543329104는
  **REUSED로 레인 전체 SKIP** 하에 success였다 — 즉 병렬 레인은 green MG에서 단 한 번도
  실행된 적이 없었다.
- 09:44:40Z #827 착지가 세대를 876으로 회전(base `1b187d1a5`)한 뒤, #828(문서 단독)의
  merge_group 평가가 병렬 레인의 **최초 실행**이 되었고 4연속 failure였다:
  38578920996(14:15:39Z) · 38580760673(14:28:02Z) · 38583637985(14:47:19Z) ·
  38587538612(15:14:09Z). 원인 규명(포렌식 F1/F2) 결과: 콜드 캐시에서 4레인이
  **공유 출력 경로의 도구를 동시 relink하는 경합**(J4 잔여 — 웜업 가드 밖 hermetic
  3종)으로 레인 1~3/4가 27~64s에 비결정적 사망. `EXECUTED — no record for the current
  closure` 로그는 정상 CAS arming line(benign)이며 패배 원인이 아니다.
  전문: `docs/evidence/mg_red_forensics_2026-10-14.md`.
- 실패한 EXECUTED 런은 판정 기록을 mint하지 않으므로 모든 재시도가 동일 MISS → 동일
  게일런트를 재실행하는 자기영속 적색 루프가 되었고, **모든 PR의 큐 착지가 구조적으로
  봉쇄**됐다. 사전등록된 리버트 PR #829 본인의 큐 시도(admission-gate run 38595964298,
  16:11:37Z 생성)조차 org callee 핀이 병렬판인 동안은 failure였다.
- 유일한 자구 착지 경로로 시간제 evaluate 창을 사용했다(사용자 전면 허가 하,
  `docs/evidence/merge_latency_decision_prereg_2026-10-14.md` §5.1의 원자 revert 수송
  규정 이행 목적).

## 창 이력 (ruleset history 교차 검증)

| ruleset | id | 전환 | 수행(로그) 시각 | history 버전 | 기록 시각 |
|---|---|---|---|---|---|
| main (repo) | 20303214 | active→evaluate | 16:14:41.119Z | 53194257 | 16:14:41.887Z |
| main (repo) | 20303214 | evaluate→active | 16:14:49.412Z | 53194327 | 16:14:50.608Z |

- ruleset 20303214("main", node_id `RRS_lACqUmVwb3NpdG9yec5GdXxtzgE1zW4`).
  actor: GitHub User id 53123826 (wintrover), 양 전환 동일.
- 총 창 길이: **8.293초** — 병합 1건에 필요한 최소 순간만 개방(선례 2026-10-12의
  repo 창 66초보다 짧다). org ruleset은 전혀 건드리지 않았다 — 24233738의 history
  최신 버전은 52838211(2026-10-12T12:41:49Z), 23943917의 최신 버전은
  52680025(2026-10-10T13:22:06Z)로, 어느 쪽에도 10-14 전환 레코드가 없다(10-12 창과
  달리 단일 ruleset 최소 창).

## 창 내 착지 (전수 검증: first-parent·커밋 조회)

- **정확히 1건**: `dc527994c` — PR #829 "revert(ci): atomically revert GO-critical
  4-lane parallelization (PR #826) — pre-registered recovery" (head `a937f27f6`,
  mergedAt 2026-10-14T16:14:46Z). `dc527994c`의 부모는 `1b187d1a5`(창 개방 시 main)와
  `a937f27f6` 뿐이며, `1b187d1a5..dc527994c` 커밋 수 = 2(병합 커밋 + head 1개).
- PR #829 병합은 GitHub MERGE API로 수행됐으며, evaluate 전환은 그 순간만큼 큐 강제와
  필수검사 차단을 일시 해제한 **소유자 비상 경로**다 — 본 문서와 감사 로그가 그 감사
  추적이다(§3.5 사후 문서화 대상).

## 창 최소화 조치

- 창 개방 전 `[pre]` 관측: 큐 refs 4(적색 실패의 잔재 `gh-readonly-queue/main/pr-828-*`
  계열), PR #829 head `a937f27f6…` state=OPEN, main=`1b187d1a5` 확인.
- ruleset 스냅샷 1,504바이트를 전환 전 저장, evaluate PUT 본문(name=main, rules=5)은
  스냅샷 내용과 동일한 규칙 집합에 enforcement만 evaluate로 바꾼 것이었다.
- 창 내 외부 쓰기 없음 — 창은 병합 1건에 필요한 최소 시간만 유지됐다.

## 복원 관측 (완료 조건 — 주장 아닌 관측)

- 16:14:49.412Z active 복원 PUT 직후, 저장 스냅샷(1,504바이트)과의 프로그램적 비교에서
  **6개 필드 전부 IDENTICAL**: enforcement · name · target · conditions · rules ·
  bypass_actors (감사 로그 `[verify]` 라인 6건). 즉 복원은 "같다고 주장"한 것이 아니라
  바이트 수준 동일로 검증됐다.
- ruleset history에 위 2개 전환 버전(53194257 evaluate → 53194327 active, rules=5 유지)
  이 실재하며 GitHub 감사 추적과 일치한다.

## 회복 (창 이후 — 핀 재회전 → 카나리 green, prereg §5.1 이행)

- 16:17:42Z Archright/.github **#209 병합**(`abe66968d`): org callee 핀
  `admission-check.yml` → `dc527994c`(직렬 복원 promotion, 선례 #184→#188).
- 16:18:09Z #828 재시도 merge_group(그룹 브랜치 `gh-readonly-queue/main/pr-828-dc527994c…`)
  에서 **5워크플로 전부 success, attempt=1**: admission-gate run 38596908760(attest /
  admission-check · mint-publish / publish · verdict · 집계 admission-check 전부
  success), landing-integrity run 38596907859, probe-merge-queue · bsec-integrity ·
  observer-manifest-consistency. 후보에 대한 실패 런 0건.
- 16:37:03Z #828 **네이티브 MERGE**(큐 경유) → main `5f486230d`. evidence-cas side-ref는
  적색기의 `71dd9c3cba`에서 `c23a661528d2`로 전진 — P7b/P7c 기록이 정상 mint됐다(876
  베이스라인 확정). 이로써 직렬 callee 하에서 자기영속 적색 루프가 해소됐다.
- prereg §5.1 종결 조건 3요소 중 원자 revert·org 핀 재회전 2요소는 위 관측으로 완료.
  golive_detect 재관측 기록은 본 문서 작성 시점에 in-repo로 착지돼 있지 않다(잔여 항목,
  아래 잔여 위험 참조).

## 잔여 위험 인정 (정직 기록)

- **J4 잔여는 미봉쇄다.** 웜업 가드 밖 hermetic 3종 도구의 공유 경로 relink 경합은
  리버트로 회피됐을 뿐 제거되지 않았다 — 향후 세대 회전 직후 첫 EXECUTED MG에서 동형
  경합이 재발할 수 있다. 봉쇄 PR은 #830(open, 잔여 봉쇄 + 레인 transcript 공개·업로드 +
  실패 시 nimcache 환류; 재범위 대기 중).
- **4개 적색 런의 레인 stdout/stderr 텍스트는 영구 소실**이다(레인 `run.log` 폐기 결함).
  따라서 F1/F2의 infra-class 판정은 코드·타이밍·재현 증거에 기반한 추정으로 남는다.
- evaluate 창은 병합 경로 통제의 일시 해제다 — 본 문서와 감사 로그가 유일한 추적이며,
  정기 수단화는 금지된다(선례 2026-10-12 창 기록과 동일 규율).
- 병렬화 계보는 REVERTED 전환으로 종결된다 — 재도입·재측정은 새 날짜 사전등록 문서로만
  가능하다(prereg 2026-10-14 §5.2).

## 감사 로그 발췌 (전문 — `~/.cache/axiom/emergency_window_2026-10-14.log`)

```
=== EMERGENCY EVALUATE WINDOW 2026-10-14T16:14:32Z — PR #829 (owner) landing under queue-red ===
[pre] queue refs: 4
[pre] PR829 head=a937f27f62e3fdb8b0d3bda19b95c9d943b4c5a2 state=OPEN
[pre] main=1b187d1a5fa3
[snap] saved ruleset snapshot (1504 bytes)
[body] evaluate body prepared: name=main rules=5
[window-open] 2026-10-14T16:14:41Z.119
evaluate
[merge] attempting direct merge of #829 at a937f27f62e3fdb8b0d3bda19b95c9d943b4c5a2
[window-close] restoring ACTIVE 2026-10-14T16:14:49Z.412
active
[verify] PR829: {"merge":"dc527994c987cad9d7d83f1dc27650d0c15eb63e","mergedAt":"2026-10-14T16:14:46Z","state":"MERGED"}
[verify] enforcement: IDENTICAL
[verify] name: IDENTICAL
[verify] target: IDENTICAL
[verify] conditions: IDENTICAL
[verify] rules: IDENTICAL
[verify] bypass_actors: IDENTICAL
[verify] main now: dc527994c Merge pull request #829 from Archright/ci/revert-go-critical-parallel
```

## 관련 참조

- PR: Axiom #829(리버트 착지) · #828(카나리 + 인시던트 문서) · #830(J4 잔여 봉쇄, open) ·
  #826(병렬화 착지 → 리버트 대상) · #827(세대 876 회전) · .github #209(핀 재회전)
- 런: 38543329104(#827 green, REUSED skip) · 38578920996 / 38580760673 / 38583637985 /
  38587538612(적색 4연속) · 38595964298(#829 큐 시도 failure) · 38596908760 /
  38596907859(회복 후 카나리 green)
- 계보·포렌식: `docs/evidence/mg_red_forensics_2026-10-14.md` (F1/F2) ·
  `docs/evidence/merge_latency_decision_prereg_2026-10-14.md` §5.1 (리버트 수송 규정) ·
  `docs/incidents/2026-10-13_pr814_pr815_direct_merge_audit.md` (§5 TEST 관측, 직접 병합
  차단과 evaluate 창의 대비) · 선례 `docs/evidence/emergency_evaluate_window_2026-10-12.md`
