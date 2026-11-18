# Ruleset bypass 범위·venue 실험 (2026-11-18, T2)

**목적**: `bypass_actors`가 실제로 어떤 venue(native merge / merge queue)에서 작동하는지, 그리고 서로 다른 ruleset 사이에 교차 적용되는지를 실측한다.

**방법**: `main`에 영향을 주지 않도록 `refs/heads/probe/base`만 대상으로 하는 임시 ruleset 2개를 만들고, commit status를 직접 발행해 required check를 통제했다. 실험 후 ruleset·브랜치·PR을 전부 삭제했다.

---

## 1. 구성

| ruleset | required context | bypass | 목적 |
|---|---|---|---|
| `probe-A-immutable` (27523561) | `probe-green` | 없음 | 불변 병합 통제 |
| `probe-B-bypassable` (27523562) | `probe-red` | `User/53123826` (`pull_request`, 이후 `always`) | 우회 대상 판정 |

- 두 ruleset의 조건은 `refs/heads/probe/base`만 포함한다.
- status는 `POST /repos/Archright/Axiom/statuses/{sha}`로 발행했다.
- queue 실험을 위해 `probe-A`에 `merge_queue`(`MERGE`, `ALLGREEN`, 1/1/1, 0분 대기, 60분 timeout)를 추가했다.
- merge는 `PUT /repos/Archright/Axiom/pulls/{n}/merge`로 실행했다.

---

## 2. 결과

| # | venue | bypass mode | A | B | 결과 | 해석 |
|---|---|---|---|---|---|---|
| T2-1 | native | pull_request | 미보고 | failure | **405** `Required status check "probe-green" is expected` (PR #171) | B bypass가 A로 교차하지 않음 |
| T2-2 | native | pull_request | success | failure | **merged** `3f870f61` (PR #169, 05:31:49Z) | bypass가 서버 측 REST merge에서 작동 |
| T2-3a | queue | pull_request | success | failure(merge group) | **removed** 05:42:52Z (PR #173) | queue venue에서 bypass 미적용 |
| T2-3b | queue | pull_request | success | success(merge group) | **merged** `3f0e0d21` (05:44:48Z) | 대조군: 큐 자체는 정상 |
| T2-4 | queue | **always** | success | failure(merge group) | **removed** 05:48:03Z (PR #174) | `always`도 queue venue에서는 미적용 |

### T2-3a/3b/4의 결정성

- T2-3a와 T2-4에서 merge group의 required check는 `failure`였고, 제거는 `github-merge-queue[bot]`이 수행했다.
- 제거 시점에 merge group workflow run들은 **아직 queued**였다. 즉 제거 원인은 workflow 실패가 아니라 required check 실패다.
- T2-3b에서 동일한 큐·동일한 status 발행 방식으로 둘 다 `success`를 주면 **정상 병합**됐다. 큐 메커니즘과 수동 status가 유효함을 확인했다.

**결론**: `bypass_actors`는 merge queue가 만든 merge group의 required check 평가에는 적용되지 않는다. 이는 queue ref 갱신 주체가 `github-merge-queue[bot]`이고 그 actor가 bypass 목록에 없기 때문이라는 구조적 설명과 일치한다.

---

## 3. 운영적 함의

1. **trust rotation PR은 queue를 통과할 때 bypass로 통과할 수 없다.** A(불변 통제)가 queue를 강제하는 한, B(App admission)의 required check를 우회하는 경로는 queue에 존재하지 않는다.
2. 따라서 VS-1의 T3/T5는 bypass actor를 쓰지 않고 **B를 `enforcement: disabled`로 전환하는 bounded window**를 사용한다. A(merge_queue + 6 contexts + no bypass)는 창 전체에서 active로 유지된다.
   - 이 방식은 특정인에게 merge 권한을 주지 않는다.
   - App check는 계속 실행되어 PR에 failure로 남는다(판정 은폐 없음).
   - 창의 시작·종료는 ruleset version history에 남는다.
3. `gh pr merge`는 서버 판정 전에 자체 pre-check로 거부한다. 거래 실행은 반드시 `PUT /pulls/{n}/merge`를 사용한다.
4. required check가 있는 ruleset은 **direct push에도 적용**된다. 조건을 base branch로 좁히지 않으면 head 브랜치 push가 거부된다.
5. 이미 merge된 PR에 `PUT /pulls/{n}/merge`를 호출하면 `{merged:true, sha:<과거 merge commit>}`가 반환된다. 응답의 `merged:true`만으로 성공을 판정하지 말고, 요청한 PR 번호·head SHA와 merge commit을 대조해야 한다.

---

## 4. Raw

- `raw/probe_A_final.json` — `probe-A-immutable` 최종 상태
- `raw/probe_B_always.json` — `probe-B-bypassable`의 `always` 상태
- `raw/probe_observations.json` — 실험별 status·timeline·판정 요약

---

## 5. 정리(cleanup) 확인

- ruleset 27523561, 27523562 **DELETE** → `GET /rulesets` readback에 존재하지 않음.
- PR #171, #174 **closed**; #169, #173은 probe/base로 병합됨(실험 데이터).
- 브랜치 `probe/base`, `probe/pr1`~`pr4` **deleted** (`git ls-remote`에서 사라짐).
- `main` ruleset(27097366)은 이 실험 동안 변경되지 않았다.