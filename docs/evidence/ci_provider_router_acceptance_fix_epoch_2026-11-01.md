# CI Epoch Record — ci-provider-router return-acceptance 기록 경로 jq 배열 축약 수리 (2026-11-01)

- **절차 정본**: `docs/agents/ci_epoch_cutover.md`(AGENTS.md §2.5 — 규모 불문
  의무; required check의 workflow_run **제어기** 변경이므로 절차 적용).
  anti-rationalization 조항에 따라 "로그 라인 1줄" 판단으로 절차를 축약하지
  않았다.
- **대상**: `.github/workflows/ci-provider-router.yml`(:464, `[acceptance-job]`
  관측 로그 라인) — surface **CONTROLLED**(v88 등록,
  `config/repository_surface.json` — 기존 파일 수정이므로 정책 PR 불필요).
- **원자성**(절차 5단계): workflow 1줄 수리 + Q17/Q18 quirk + 본 기록 +
  PR-2 증거 기록 갱신(항목 5–8 실측 + 결함 발견)이 하나의 세대 전환 단위로
  본 PR에 탑재된다.
- **병합 입장 조건**(실판정 2026-11-01, PR #1160 시점과 동일): ruleset
  20303214 — `required_approving_review_count: 0`, `require_code_owner_review:
  false`, merge queue MERGE/ALLGREEN(max build 2). CODEOWNERS는 리뷰 *요청*뿐.

## 결함 (root cause)

- `ci-provider-router.yml:464` `jq -c '{name,…}'` — `ACC_NON_SKIP`은
  **배열**(`jq -c '[.[] | select(…)]'`)인데 객체 축약을 `.[]` 분배 없이
  적용해 `Cannot index array with string "name"` jq 런타임 에러(exit 5).
  `shell: /usr/bin/bash -e`가 잡을 종료시킨다. Q17
  (`docs/spec/ci_provider_failover_quirks.md`) 참조.
- **발화**: GHEC 복귀(PR #1160 + force_trial, 2026-11-01 08:35:59Z 라우터
  clock) 이후 첫 required workflow_run 완료 이벤트에 라우터가 3회 연속
  failure로 사망 — run 41295714292(10:02:50Z)·41295753737(10:03:21Z)·
  41296106985(10:07:58Z, 로그 확인). 공통 패턴: `[acceptance] …
  executed=1 blocked=0 all_ghec=true` 판정 출력 직후 jq error → exit 5.
- **판정은 이미 충족 관측됐다**: 41296106985 로그 — 관측 대상 run 41295610611
  (axiom-operational-slice, merge_group, conclusion=success, head_branch
  `gh-readonly-queue/main/pr-1162-18e5602b…`, created 10:01:23Z > 전이
  08:35:59Z): `executed=1 blocked=0 all_ghec=true`. 실패는 판정이 아니라
  **판정 직후 관측 로그 라인**이며, `return_acceptance=confirmed` write
  (:476-478) 도달 불가로 CI_RUNNER_MAP이 `pending`에 정체됐다.
- PR #1160(Q16, canary :94)과 동일 계열의 "판정 전 jq 사망"이지만 결함
  원인이 다른 별개 인스턴스(labels 인덱싱 vs 배열 축약) — canary 수리
  시점에 라우터 본체의 이 라인은 발화 조건(GHEC_ACTIVE + 전환 이후 완료된
  required run)이 성립한 적이 없어 관측 불가능했다.
- **부수 발견(Q18)**: 전수조사에서 `gh api` 403 에러 본문이 `--jq >file`
  리다이렉트로 관측 파일을 오염시켰다(250 part) — quirk 문서에 기록하고
  집계 단계 스키마 검증 + exit code 판별 재조회로 계약을 복원했다.

## 세대 전환 10단계 (ci_epoch_cutover.md)

1. **Freeze** — pre-fix 정본: workflow blob SHA
   `d78aaccece588eb33bd0d0b14c6e67548fb6e5d1`(main `946123193` 기준).
   CI_RUNNER_MAP freeze 시점 상태: `mode=ghec, GHEC_ACTIVE, generation=15,
   return_acceptance=pending, last_transition_reason=GHEC_TRIAL_SUCCESS`.
2. **Record** — 본 PR HEAD(수정 1줄: `:464` `jq -c '{name,…}'` →
   `jq -c '.[] | {name,…}'` + Q17/Q18 + rule 16/17 + 본 기록 + PR-2 증거
   갱신; PR merge 시 기록).
3. **Tombstone** — N/A: retirement 없음(관측 로그 라인의 스트림 분배 교체,
   실행 경계·권한·판정 의미론 유지).
4. **New Epoch** — acceptance 관측 로그 v2: 배열에 `.[]` 분배 — row별
   `[acceptance-job]` 출력(의도된 원형 복원). 판정값(ACC_*)·write 경로
   (:474-495) 무변경.
5. **Atomic Binding** — workflow + quirk + epoch record + PR-2 증거 갱신 =
   단일 PR·단일 merge.
6. **Local/Targeted Verification** — 아래 표, 관측 완료.
7. **Short Validation** — 라우터는 dispatch가 아닌 `workflow_run(completed)`
   트리거이므로 로컬 재현이 곧 생산 전 검증이다(수리 전 발화 3회가 결함의
   실측 재현). 병합 후 첫 실제 발화가 운영 검증을 수행한다(9단계).
8. **Canonical Cutover** — 본 PR의 merge queue 통과 + native MERGE(main).
   required-check identity/trust 의미론 무변경(수리 대상은 관측 로그 라인이며
   판정·라우팅 로직은 불변).
9. **Production Acceptance** — 본 PR merge_group의 required run 완료 →
   라우터 workflow_run 발화 → 수리된 :464 통과 → :474 조건(executed>0 ∧
   blocked=0 ∧ all_ghec) → `return_acceptance=confirmed` write → GET 검증
   (CI_RUNNER_MAP). 결과는 PR-2 증거 기록의 갱신 각주로 종결.
10. **Rollback** — 단일 줄 revert PR. 결함 상태에서도 라우터는 fail-closed
    (routing untouched, write 불가 시 UNKNOWN 기록)이므로 롤백 상태도 안전하다.

## 로컬 검증 (2026-11-01 관측 완료)

| 검증 | 명령 | 관측 결과 |
|---|---|---|
| 결함 재현 | `printf '%s' '[{"name":"j1",…}]' \| jq -c '{name,…}'` | `jq: error: Cannot index array with string "name"`, **exit 5** |
| 수정식 통과 | `… \| jq -c '.[] \| {name,…}'` | row별 정상 출력, **exit 0** |
| 운영 재현(결함) | 라우터 run 41296106985 로그(10:08:20Z) | 판정 직후 동일 error/exit 5 — 3회 연속 발화 |
| workflow shell 게이트 | `bash tools/ci/validate_workflow_shell.sh --scan-dir .github/workflows` | PASS (아래 커밋 시점 관측) |

## 시계 병기

라우터 clock(`last_transition_at=08:35:59Z`)과 GitHub API 표시
(created_at 등, +1h 상대 관측)의 오프셋은 본 수리의 판정 경로를 바꾸지
않는다 — :449 비교(created_at > last_transition_at)는 전환 이후 관측 창을
넓히는 방향으로만 작용하고, 실측 발화 41295610611(created 10:01:23Z)은
양 체계 어느 기준으로도 전환 이후다.

## 실행 순서 (운영 — 권한 전면 승인됨)

1. 본 PR 병합(merge queue — 현재 활성 공급자 GHEC에서 실행).
2. 본 PR merge_group의 required run 완료 → 라우터 workflow_run 발화
   (수리된 경로).
3. 라우터가 `return_acceptance=confirmed` + `return_acceptance_run_id` write
   (단일 writer 보존 — 수동 PATCH 없음).
4. GET 검증 + PR-2 증거 기록 갱신 각주 종결.
