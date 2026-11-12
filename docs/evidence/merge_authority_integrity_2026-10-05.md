# Merge Authority Integrity — V2 실행 증거 (2026-10-05)

**Slice**: V2 — Merge Authority Integrity Closure
**정본**: [docs/spec/merge_authority_integrity.md](../spec/merge_authority_integrity.md) ·
[docs/agents/merge_admission_observation.md](../agents/merge_admission_observation.md) L2-R ·
[docs/agents/rules_workflow.md](../agents/rules_workflow.md) §2.8
**원시 스냅샷**: 세션 아티팩트(Rule Suite retention ≈1일 — 본 문서가 유일한 장기 기록)

모든 값은 실제 명령의 관측 결과다. 추정값은 없다. 시각은 KST(UTC+9)로 통일한다.

---

## E1. Authority Snapshot (Phase A — 관측 전용, GET/GraphQL만)

**명령**: `gh api repos/Archright/Axiom/rulesets` · `gh api .../rulesets/20303214` ·
`gh api .../rules/branches/main` · GraphQL `mergeQueue(branch:"main")`

### E1-a. Phase C 적용 전 — main ruleset `20303214` (사고 당시 구성)

`GET /rulesets/20303214` (2026-10-05 15:41 KST):

```json
{"id":20303214,"name":"main","enforcement":"active",
 "rules":["deletion","non_fast_forward","pull_request","required_status_checks","merge_queue"],
 "bypass_actors":[],"current_user_can_bypass":"never",
 "updated_at":"2026-10-05T15:00:46.151+09:00"}
```

- `update`·`creation` 규칙 **부재**. bypass actor **0명**.
- effective rules(4 ruleset 합산, `GET /rules/branches/main`): **9개** — org `workflows` 2
  (admission-gate.yml · landing-integrity.yml, ruleset 24233738/23943917) + repo
  `file_path_restriction` 2 (build/** · .github/**, ruleset 23969951/23967915) + main ruleset 5.

### E1-b. Phase C 적용 후 (2026-10-05 16:0x KST 재관측) 및 롤백 후 최종 구성 (16:57:39 KST)

```json
{"rules":["deletion","non_fast_forward","pull_request","required_status_checks",
          "merge_queue","update","creation"],
 "bypass_actors":[{"actor_id":118344674,"actor_type":"User","bypass_mode":"pull_request"},
                  {"actor_id":53123826,"actor_type":"User","bypass_mode":"pull_request"}],
 "enforcement":"active"}
```

- 추가 규칙: `update`(update_allows_fetch_and_merge) · `creation`.
- bypass actor: `github-merge-queue[bot]`(118344674) · `wintrover`(53123826), 모두
  `pull_request` 모드 — **직접 push 우회 불가**(§E4 참조).
- **롤백(2026-10-05 16:57:39 KST)**: 큐 EMPTY 확인(M2 순서 준수) 후 ruleset `20303214`를
  control 5규칙으로 PUT 롤백(`updated_at:"2026-10-05T16:57:39.440+09:00"`) —
  rules `[deletion, non_fast_forward, pull_request, required_status_checks, merge_queue]`,
  `bypass_actors: []`, `current_user_can_bypass:"never"`. **최종 구성 = control 5규칙.**
- **인과 대조**: 롤백 직후 동일 GraphQL mutation `enqueuePullRequest`가
  `{"mergeQueueEntry":{"position":1,"state":"QUEUED"}}`로 성공 → Phase C의 `update` 규칙이
  큐 진입 경로 자체를 막았음이 확정. Phase C의 `update`·`creation`·bypass 2명은 T2(Case B)를
  차단한 원인으로 **제거**되었다 — "PR·큐 경로만 허용" 정책은 `pull_request`+`merge_queue`
  규칙이 이미 집행한다.

### E1-c. 사고 Rule Suite (E2와 동시 확보)

`GET /rulesets/rule-suites` (15:45 KST, 100건 보존분):

```
4360251067  github-merge-queue[bot](118344674)  refs/heads/main  fail  before=692056d1  2026-10-05T14:14:29+09:00
```

→ 사고(큐 착지 중 update 규칙 추가 → 큐 ref 갱신 거절 → main ≈49분 동결)의 권위 신호.
사유의 유일 권위(`rule_evaluations[].details`)는 이 REST 엔드포인트뿐이다(M5).

---

## E2. 진단 중 ruleset/queue mutation = 0 (E3)

- Phase A 전체(스냅샷 7종 수집)는 **GET/GraphQL query만** issuing했다.
- 세션 전체에서 live 구성에 대한 쓰기는 **2회**(Phase C PUT 1회 + 롤백 PUT 1회)이며, 각 쓰기의
  전제가 `drain → (pre-snapshot) → change → snapshot → resume` 순서였다:
  1. 큐 EMPTY 확인 — GraphQL `mergeQueue(branch:"main"){entries}` → `{"totalCount":0,"nodes":[]}` (15:41 KST)
  2. pre-snapshot — `GET /rulesets/20303214` 5-rule 상태 저장
  3. **`PUT /rulesets/20303214` 1회** (phaseC payload: 7 rules + bypass 2 actor)
  4. post-snapshot — 재관측(E1-b)

  롤백 창(16:57:39 KST): 큐 EMPTY 확인(M2 순서 준수) → **`PUT /rulesets/20303214` 1회**
  (control 5규칙, bypass []) → post-snapshot(E1-b 롤백분). 직후 동일 `enqueuePullRequest`
  mutation 성공으로 인과 대조 확정(E1-b · E5).
- 두 쓰기 창 사이·이후의 모든 관측(T1 probe, T2 차량, 착지 전후 rule-suites 캡처 포함)은
  다시 GET/GraphQL/primitives뿐이다.

## E3. E4/T1 — 비인가 직접 push 거부 (구조 강제 실측)

**명령**: 보호된 main에 직접 push 시도 (`git push origin HEAD:main`, probe 커밋)

**관측**: push 거부 + GitHub 측 Rule Suite 기록 — `GET /rulesets/rule-suites/4361198253`
(15:49:11 KST, actor `wintrover`(53123826), `refs/heads/main`, **result: fail**):

| rule_type | result | details |
|---|---|---|
| update | **fail** | `Cannot update this protected ref.` |
| pull_request | fail | `Changes must be made through a pull request.` |
| required_status_checks | fail | `Required status check "admission-check" is expected.` |
| merge_queue | fail | `Changes must be made through the merge queue` |
| workflows | fail | `Required workflow 'landing-integrity' is not satisfied` / `'admission-gate' is not satisfied` |
| creation · non_fast_forward · deletion · file_path_restriction ×2 | pass | — |

→ `bypass_actors`에 `wintrover`가 `pull_request` 모드로 등록되어 있어도 **직접 push는
차단된다** — bypass 모드가 PR 우회(머지 시 규칙 면제)만 허용함이 실측됨. T1 PASS.

## E4. E7 — L1 green ≠ main landed

- PR #478 (스냅샷, 04:45–14:14 KST 경과 중): `admission-check` **SUCCESS** + `isRequired:true`
  상태에서도 `state: OPEN`, `isInMergeQueue: false` — required check 단일 성공으로는 착지를
  주장할 수 없음을 실측.
- PR #482 (T2 차량, 16:21 KST auto-merge arm): `repository-surface` ·
  `merge-admission-sanity` · `trust-surface-codeowners` · `trusted-writer-set-pairing` ·
  `gateway / select` 전부 SUCCESS인 상태에서 `state: OPEN`, 큐 미착지 — 동일 재확인.
  (단, `attest / build-base-artifacts`는 `isRequired:false` — M4 권위 신호
  `CheckRun.isRequired(pullRequestNumber:)`로 판정)

## E5. T2 — 정상 merge-queue 착지 (update: fail 0건)

- PR #482 **MERGED** — merge commit `888575faa031ff54ece3cea5513675618002e415`,
  mergedAt `2026-10-05T08:10:53Z`, mergedBy `wintrover` (L3: `state=="MERGED"` ∧
  `mergeCommit.oid` 존재).
- 착지 전후 rule-suites 캡처(2026-10-05 17:01 · 17:14 KST,
  `GET /repos/Archright/Axiom/rulesets/rule-suites`): suite IDs `4362123444` ·
  `4362123586` · `4362123754` · `4362298950` · `4362299064` · `4362299205` —
  **전부 result pass**, 평가는 `file_path_restriction`뿐. **fail 평가 0건.**
- 관측 공백(정직 기록): 성공적인 큐 착지는 `refs/heads/main` rule-suite를 **발행하지
  않았다**(사고 때의 fail suite `4360251067`과 대조) — "정상 착지의 rule-suite 부재"
  자체가 관측 사실이다. V2의 판정은 fail 0건이며, suite 미발행을 성공의 증거로 읽지 않는다.
- **정정 (2026-10-05 후속 관측 — pr_liveness C5)**: 위 "미발행" 기록은 당일 캡처 범위
  아티팩트로 판명됐다. `per_page=100` 전수 수집에서 성공 착지마다 `result=pass`
  suite가 발행됨을 확인: `4362082437`(16:57:51 KST, `0ea53af18→888575faa`) ·
  `4362205564`(17:06:56, `→42aceb791`) · `4363455435`(18:34:42, `→0541e6f`) —
  actor 전부 `wintrover`(53123826). suite `pushed_at`은 실제 착지 시각이 아니라 큐의
  ref-update 사전 평가 시각이다(4363455435: 18:34:42 평가 → 18:46:13 착지). V2 판정
  자체는 변하지 않는다 — 착지 window `{update, fail}` 0건. "미발행" 서술만 정정한다.

## E6. main ref updater identity (L3)

- PR #482 착지의 mergedBy는 **`wintrover`**(53123826)이며 경로는 **merge queue**다 —
  `enqueuePullRequest` 성공(`{"mergeQueueEntry":{"position":1,"state":"QUEUED"}}`,
  16:57:39 KST 롤백 직후) → MERGED(mergedAt `2026-10-05T08:10:53Z`).
- 관측 공백(정직 기록): 이 착지는 `refs/heads/main` rule-suite를 발행하지 않았으므로(E5),
  ref 갱신의 **suite 레벨 actor 기록은 존재하지 않는다**. §7 inventory의 자동 경로
  (`github-merge-queue[bot]`)·수동 경로(`wintrover`) 어느 쪽과도 상충하는 관측은 없으며,
  actor attribution은 관측된 사실(mergedBy `wintrover`, 큐 경로) 그대로 기술한다.
- **정정 (2026-10-05 후속 관측)**: E5 정정에 따라 성공 착지의 suite 레벨 actor 기록은
  **존재한다** — 착지 pass suite(`4362082437` 등 3건)의 actor는 전부 `wintrover`
  (53123826)다. 즉 GitHub는 큐가 수행한 ref 갱신을 arm identity로 attribution한다
  (mergedBy `wintrover`와 부합). 자동 경로 executor가 `github-merge-queue[bot]`임은
  사고 suite `4360251067`의 actor로 여전히 실측되어 있다.

## E7. Landing App 선언 vs 실행 (staleness 재확인)

- `config/app_landing_binding.json`은 `axiom-ci-elastic`(app 4879411)을 main 갱신 authority로
  선언하나, E2의 rule-suites 100건 보존분과 §docs/adr/0025 실측에 따르면 해당 App의
  main ref 갱신 이력은 **0건** — main을 실제로 갱신한 주체는 `github-merge-queue[bot]`(자동)과
  `wintrover`(수동, 12:21/12:39/15:03 KST suite)뿐이다.
- 선언을 사실로 재확정하지 않는다 — 정정은 ADR-0025 후속 개정 경로(스펙 §8).

## E8. 진단 권한 분리 수준 (정직 기록)

- 본 세션의 관측은 **Tier 0**(절차 계약)다 — 진단에 쓴 `gh` identity는 `Administration: write`
  를 보유하므로(POST/PUT 발행 가능), M7의 구조 강제(Tier 1, `Metadata:Read` 전용 PAT)는
  **미확립**이다. PAT 생성은 GitHub API가 제공하지 않아 인간 액션이 선행된다(스펙 §6).
- 다만 관측 결과로서: 세션 전체의 실제 구성 쓰기는 E2의 **2회**(Phase C PUT 1회 + 롤백 PUT 1회,
  16:57:39 KST)뿐이며, 모두 drain·큐 EMPTY 확인과 snapshot을 앞세운 **선언된 Mutator 창**
  안에서 수행됐다. 롤백으로 최종 구성은 control 5규칙으로 복귀했으며, Phase C의
  `update`·`creation`·bypass 2명은 T2를 차단한 원인으로 제거되었다(E1-b 인과 대조).
