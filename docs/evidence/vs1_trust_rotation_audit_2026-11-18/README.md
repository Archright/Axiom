# VS-1 T1 — Ruleset 27097366 bypass window 전수 감사 (2026-11-18)

**대상**: `Archright/Axiom` ruleset `27097366`(`main`, branch, `enforcement: active`)
**기준 commit**: `cc63569` (origin/main, PR #162 merge)
**관측 시각**: 2026-11-18 (KST)
**목적**: trust rotation에 사용된 모든 bypass 창을 API 원본으로 복원하고, 각 창의 merge venue·감사 기록 유무를 확정한다.

---

## 1. 방법

`rulesets/{id}/history` 목록 API의 각 행은 `bypass_actors`를 포함하지 않는다.
따라서 목록으로 버전 ID를 수집한 뒤 **버전별 상세 조회**(`rulesets/{id}/history/{version_id}`)로
`bypass_actors`·`rules`·`required_status_checks`를 개별 확인했다.

```bash
gh api repos/Archright/Axiom/rulesets/27097366/history --paginate > raw/ruleset_history_rows.json
# 각 version_id에 대해:
gh api repos/Archright/Axiom/rulesets/27097366/history/{version_id} > detail.json
```

- 수집된 history 버전: **39개**
- `bypass_actors`가 비어 있지 않은 버전: **13개** → 12개 close 버전과 짝을 이루고, 1개는 merge 없이 닫힘
- 각 창의 merge 대조: `GET /repos/{owner}/{repo}/pulls/{n}` + `GET /actions/runs?event=merge_group` + timeline events

---

## 2. Ruleset 현재 상태 (2026-11-18, `bypass_actors: []`)

| 항목 | 값 |
|---|---|
| rules | `deletion`, `non_fast_forward`, `pull_request`, `required_status_checks`, `merge_queue` |
| required contexts (7) | `admission-check`→**5795152**, `bsec-integrity`→15368, `debt-registry-gate`→15368, `generation-acceptance`→15368, `axiom-operational-slice`→15368, `publication-integrity`→15368, `readiness-verdict`→15368 |
| `pull_request` 파라미터 | `required_approving_review_count: 0`, `allowed_merge_methods: ["merge"]`, `require_extra_approval_for_unattributed_changes: true` |
| `merge_queue` 파라미터 | `MERGE`, `ALLGREEN`, `max_entries_to_build: 2`, `max_entries_to_merge: 1`, `min_entries_to_merge: 1`, `check_response_timeout_minutes: 120` |
| `current_user_can_bypass` | `never` |
| classic branch protection | `GET .../branches/main/protection` → **404 (Branch not protected)** |
| `rule-suites` API | **404** (Free 플랜) |
| org audit log API | **404** (Free 플랜) |
| org rulesets API | **403 Upgrade to GitHub Team** |

→ 이 저장소에서 bypass의 유일한 API 감사 표면은 `rulesets/27097366/history`이며,
repo-side evidence가 권위다.

---

## 3. Bypass 창 13개 (버전 ID와 KST 시각)

| # | open version | open (KST) | actor | mode | close version | close (KST) | 창 길이 | PR | merge commit | venue |
|---:|---:|---|---|---|---:|---|---:|---|---|---|
| 1 | 58030608 | 2026-11-17 01:50:14 | OrganizationAdmin | pull_request | 58030755 | 01:50:56 | 42.5s | #121 | `e3ec8ae1f475` | native |
| 2 | 58043542 | 2026-11-17 03:16:30 | OrganizationAdmin | pull_request | 58043550 | 03:16:35 | 4.4s | #127 | `aba60b3f60dd` | native |
| 3 | 58053443 | 2026-11-17 04:06:36 | OrganizationAdmin | pull_request | 58053484 | 04:06:53 | 17.3s | #128 | `e88962e3994d` | native |
| 4 | 58121984 | 2026-11-17 14:20:24 | OrganizationAdmin | always | 58121996 | 14:20:29 | 4.5s | #133 | `e07a648e3b02` | native |
| 5 | 58130640 | 2026-11-17 16:08:54 | User `53123826` | always | 58130653 | 16:09:05 | 10.6s | (없음) | — | — |
| 6 | 58130708 | 2026-11-17 16:09:48 | User `53123826` | always | 58130717 | 16:09:53 | 4.7s | #136 | `916a9bdb7334` | native |
| 7 | 58144103 | 2026-11-17 18:08:00 | User `53123826` | always | 58144129 | 18:08:14 | 13.8s | #139 | `88406c61e748` | native |
| 8 | 58200591 | 2026-11-18 00:14:49 | OrganizationAdmin | pull_request | 58200678 | 00:15:10 | 20.1s | #130 | `b075690044d8` | native |
| 9 | 58213324 | 2026-11-18 01:18:48 | User `53123826` | always | 58213340 | 01:18:54 | 6.1s | #144 | `9b3d87c3a325` | native |
| 10 | 58214455 | 2026-11-18 01:24:27 | User `53123826` | always | 58214470 | 01:24:33 | 5.5s | #146 | `ed014de81e54` | native |
| 11 | 58294264 | 2026-11-18 10:14:23 | User `53123826` | always | 58294288 | 10:14:28 | 4.7s | #153 | `983e8360f876` | native |
| 12 | 58299317 | 2026-11-18 10:56:42 | OrganizationAdmin | pull_request | 58299321 | 10:56:47 | 4.2s | #155 | `ad96ed2aacda` | native |
| 13 | 58302871 | 2026-11-18 11:29:10 | OrganizationAdmin | pull_request | 58302886 | 11:29:14 | 4.4s | #159 | `b41b56840a1c` | native |

`OrganizationAdmin` 행의 `actor_id`는 API에서 `null`이다 — GitHub 문서상 `OrganizationAdmin`은
`actor_id`를 무시하고 org admin 전체를 포함한다. `User 53123826` 창은 5·6·7·9·10·11에서 사용됐고,
그중 5번은 merge 없이 닫혔다.

---

## 4. Merge venue 대조 — 12건 전부 native merge

각 창의 merge를 `merge_group` run 존재 여부와 timeline 큐 이벤트로 판정했다.

- 13창 중 merge가 발생한 창: **12개**
- 그 12개 merge의 `merge_group` run: **전부 0건** (timeline 큐 이벤트도 없음)
- 별도 대조군: 저장소의 `merge_group` run 총 **1,378건** (`head_branch = gh-readonly-queue/main/pr-N-<base_sha>`)
  → 이 저장소는 큐를 정상 사용하며, 위 12건만 큐를 경유하지 않았다.

**귀결**: bypass 창 하에서 merge queue를 경유한 사례는 **0건**이다.
따라서 "queue venue에서 bypass가 어떤 의미를 갖는가"는 이 저장소의 실측으로 확정할 수 없다 (**UNKNOWN**).

---

## 5. 감사 기록 커버리지 — 13창 중 6창만 per-window 기록

| 구분 | 창 | 근거 |
|---|---|---|
| per-window 기록 있음 (PUT·readback·restore) | 1 (#121) | `docs/evidence/readiness_required_check_activation/raw/rotation_execution_record.md` |
| 〃 | 5·6 (#136, 2창) | `docs/evidence/free_authority_migration_phase0_proof.md:165-180` — open/close 시각·readback·merge 기록 |
| 〃 | 11 (#153) | `docs/evidence/debt545_policy_v102_landing.md` §2 — pre snapshot, bypass 1건, RESTORE_IDENTICAL |
| 〃 | 12 (#155) | `docs/evidence/vs_auth_fresh_acceptance_2026-11-18.md` §5.1 — 활성 시각 01:56:42Z, 복원 readback |
| 〃 | 13 (#159) | 동 문서 §5.2 — 활성 시각 02:29:09Z, 복원 readback |
| 서술만 있고 창 단위 기록 없음 | 2 (#127), 7 (#139) | `vs_perf_attr_acceptance_2026-11-16.md:224`는 3단계 lane을 서술하지만 version ID·시각 없음. #139는 bypass 기록 없이 착지 서술만 존재 |
| 기록 없음 | 3 (#128), 4 (#133), 8 (#130), 9 (#144), 10 (#146) | `docs/evidence/`에서 해당 PR의 bypass 창 기록을 찾을 수 없음. #130은 `debt545_policy_v102_landing.md:110`이 "ruleset pre/post 스냅샷 부재"로만 언급 |

부수 관측: #121 기록의 required contexts는 7개 전부 `integration_id: 15368`이다.
현재 live는 `admission-check`만 `5795152`이며, 그 사이에 App 발행으로 전환된 것이다.
이 전환 자체의 창 기록은 이 감사 범위 밖이다.

---

## 6. 확정할 수 없는 것 (UNKNOWN)

1. **queue venue에서의 bypass 적용 여부** — 문서 SILENT, 실측 0건. 4개 (actor_type, mode) 조합 전부 UNKNOWN.
2. **bypass 감사 항목의 정확한 이벤트명** — Free 플랜에서 org audit log API가 404이므로 직접 확인 불가.
3. **창 중 다른 merge 발생 여부** — 12개 창의 `merged` 목록은 각 1건이며, 창 밖 merge는 창 시각과 겹치지 않는다(초 단위 대조).
   단, PR #130 창은 20.1초였고 그 사이 다른 merge는 관측되지 않았다.
4. **#130의 bypass 사용 자체** — 창 8은 API로 확정됐다. 이전 문서의 "스냅샷 부재"는 창 기록의 부재를 뜻하며, 창이 없었다는 뜻이 아니다.

---

## 7. Raw 데이터 (sha256)

| 파일 | bytes | sha256 |
|---|---:|---|
| `raw/api_snapshot.json` | 23736 | `22597b14e014d1f4659097dd49c413b174f0f17ee35f70a66bcf17b9e365e5f2` |
| `raw/ruleset_history_rows.json` | 6125 | `b1bafc6b8d9f36be9eccd03682725afea2e1575b8e212d6ed5d4f951a210b653` |
| `raw/ruleset_history_details.json` | 19482 | `5ea299efe5fdc9723b29e85b769c9defa3bbfe1eb22eb61c8dd4b495be4a0891` |
| `raw/bypass_windows.json` | 14616 | `fe79847e117b8787dba341db16d0aaf1e5a30074a8fdbd99f3006a121854dcf0` |
| `raw/window_merges.json` | 8461 | `16baab5543668f58176077cb32ef23aa8742f08df648ec2b73c35d1b4d22d891` |

---

## 8. 재현

```bash
cd <repo>
gh api repos/Archright/Axiom/rulesets/27097366 | jq '{id,name,enforcement,bypass_actors,rules}'
gh api repos/Archright/Axiom/rulesets/27097366/history --paginate | jq '.[].version_id'
# 각 version_id 상세에서 bypass_actors 확인
gh api repos/Archright/Axiom/rulesets/27097366/history/<version_id> | jq '.bypass_actors'
# merge venue
gh api repos/Archright/Axiom/pulls/<n> | jq '{merged_at,merge_commit_sha,head:.head.sha,base:.base.sha}'
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&per_page=100" --paginate | jq '.total_count'
```

`raw/bypass_windows.json`은 `{open: <version detail>, close: <version detail>}` 13쌍이고,
`raw/window_merges.json`은 각 창의 `merged[]`(PR 번호·merge commit·`merge_group_run`)이다.

---

## 9. 범위 정직성

이 감사는 **창의 존재·시각·actor·mode·merge venue**를 확정한다.
다음을 주장하지 않는다:

- bypass가 "안전했다"는 주장 — 창 중 다른 조작이 없었다는 증거는 ruleset history와 PR timeline 범위에서만 성립한다.
- queue venue bypass의 의미 — 실측 0건이므로 UNKNOWN이다.
- #130의 인과 — App check failure가 실제 merge commit의 second parent를 판정했다는 사실은
  `docs/evidence/debt545_policy_v102_landing.md`에 기록되어 있으나, bypass 창 8의 상세 실행 기록은 없다.

이 공백은 `DEBT#560`으로 등록한다.