# CI Epoch Record — ghec-canary M6 labels 검증 술어 수리 (2026-11-01)

- **절차 정본**: `docs/agents/ci_epoch_cutover.md`(AGENTS.md §2.5 — 규모 불문
  의무; dispatch-only 비-required 프로브도 명시 포함). anti-rationalization
  조항(:113)에 따라 "작은 변경" 판단으로 절차를 축약하지 않았다.
- **대상**: `.github/workflows/ghec-canary.yml`(dispatch-only GHEC 가용성
  프로브, required check 아님) — surface **CONTROLLED**(v88 등록,
  `config/repository_surface.json` — 정책 PR 불필요).
- **원자성**(절차 5단계): workflow 변경 + Q16 quirk + 본 기록이 하나의 세대
  전환 단위로 본 PR에 탑재된다.
- **병합 입장 조건**(실판정 2026-11-01): ruleset 20303214 —
  `required_approving_review_count: 0`, `require_code_owner_review: false`,
  merge queue MERGE/ALLGREEN(max build 2). CODEOWNERS는 리뷰 *요청*뿐(단일
  아키텍트 자기승인 금지 → 구조적 데드락 방지, `docs/agents/rules_workflow.md`).
  최근 40/40 병합 PR(.github 수정 #1128·#1142·#1125 포함)이 리뷰 0건으로
  큐 통과 — 인간 리뷰 선행 단계 없음.

## 결함 (root cause)

- `ghec-canary.yml:94` `labels_j="$(jq -c '[.labels[]?.name]' <<<"$job")"` —
  jobs-API `labels`는 **문자열 배열**(REST 스키마 `labels: array of string`)이므로
  `.name` 인덱싱이 jq 런타임 에러(exit 5)를 일으키고 `set -e`가 identity 스텝을
  **판정 이전**에 종료시킨다. Q16(`docs/spec/ci_provider_failover_quirks.md`) 참조.
- 발화: 2026-11-01T01:36:46Z 라우터 월간 trial(자동 push-트리거, PR #1159 merge,
  generation 13→14)의 canary run 41261811139 / job 124716440849 — 로그
  `jq: error (at <stdin>:1): Cannot index string with string "name"` →
  `Process completed with exit code 5`.
- **GHEC는 가용이었다**: 잡이 실제 GitHub-hosted 러너에 배정·실행
  (runner_id=1000035432, runner_group_id=0, runner_group_name="GitHub
  Actions", steps=3, 01:36:58→01:37:02Z). 10/24의 0-step 예산 차단(Q1/Q11)과
  정반대 — 2026-11 청구주기(달력월 경계 리셋, Q11 documented basis) 포함량
  복구의 운영 증거. 즉 실패 원인은 쿼터가 아니라 **복귀 게이트(검증 술어)
  자체의 결함**이다.
- canary 9회 전체 이력: 41261811139만이 identity 스텝에 도달했다 — 스크립트
  본문의 첫 실제 실행이자 결함의 첫 발화. 10/23~10/26의 8건은 전부 0-step
  예산 차단이라 스크립트가 실행된 적이 없었다(결함은 사전에 관측 불가능).
- **반증된 사전 기대**: `docs/evidence/ci_provider_epoch_2026-10-30.md` §6.5는
  11월 창 시험을 "GHEC blocked → 0-step canary failure → keep Ubicloud"로
  선언했다. 실측은 정반대(GHEC 가용 + 프로브 결함) — RESID-13 관측의 전제가
  반증됐다(ledger amendment는 PR-2에서 수행, 아래 "RESID-13 충돌 해소").

## 세대 전환 10단계 (ci_epoch_cutover.md)

1. **Freeze** — pre-fix 정본: workflow blob SHA
   `27eb01be956139218a96c7f174f8c35481106e87`(main 38941dab9 기준).
   CI_RUNNER_MAP freeze 시점 상태: `mode=ubicloud, state=UBICLOUD_ACTIVE,
   generation=14, trial_attempts_period=1/3, last_trial_run_id=41261811139,
   last_transition_reason=GHEC_TRIAL_FAILED`.
2. **Record** — 본 PR HEAD(수정 1줄 + Q16 + 본 기록; PR merge 시 기록.
   :94 `[.labels[]?.name]` → `[.labels[]? | (.name? // .)]`).
3. **Tombstone** — N/A: retirement 없음(검증 술어 교체, 실행 경계·권한 유지).
4. **New Epoch** — canary 검증 술어 v2: labels를 평탄 문자열 배열로 정규화
   (라우터의 `map(.name? // .)` 관용구와 동일 원소 매핑; :111
   `index("ubuntu-24.04")` 검사 호환 — 중첩 배열은 불가).
5. **Atomic Binding** — workflow + Q16 quirk + 본 기록 = 단일 PR·단일 merge.
6. **Local/Targeted Verification** — 아래 표, 전 항목 관측 완료.
7. **Short Validation** — force_trial canary run(§ "실행 순서" 2단계).
   dispatch-only 프로브: 병합 의미론과 무관하며 프로브 본체가 곧 생산 검증.
8. **Canonical Cutover** — 본 PR의 merge queue 통과 + native MERGE(main).
   required-check identity/trust 의미론 무변경(수리 대상은 required path가
   아닌 프로브다).
9. **Production Acceptance** — 전환 후 첫 실제 required run의 GHEC 실행 +
   PR-2 merge_group의 GHEC 착지(`tools/ci/landing_observe.sh --main <sha>`).
   결과는 PR-2 증거 기록에 반영.
10. **Rollback** — 단일 줄 revert PR. 라우터는 어떤 canary 실패에도
    fail-closed(Ubicloud 유지)이므로 롤백 상태도 안전하다. force_trial 실패 시
    counter는 미소비(11/2·11/3 자동 재시도 잔여)이나 same-day/20h 게이트가
    arm된다(다음 자동 기회 11/3 02:05Z).

## 로컬 검증 (6단계 — 2026-11-01 관측 완료)

| 검증 | 명령 | 관측 결과 |
|---|---|---|
| 결함 재현 | `gh api repos/Archright/Axiom/actions/jobs/124716440849 \| jq -c '[.labels[]?.name]'` | `jq: error: Cannot index string with string "name"`, **exit 5** |
| 수정식 통과 | `… \| jq -c '[.labels[]? \| (.name? // .)]'` | `["ubuntu-24.04"]` |
| 게이트 호환 | `\| jq -e 'index("ubuntu-24.04") != null'` | `true` (GATE_OK) |
| fail-closed 보존 | `echo '{"labels":[]}' \| jq -c '[.labels[]? \| (.name? // .)]' \| jq -e 'index("ubuntu-24.04") != null'` | `false` → 차단(의도된 fail-closed 유지) |
| workflow shell 게이트 | `bash tools/ci/validate_workflow_shell.sh --scan-dir .github/workflows` | **PASS — run blocks checked=230 failures=0 lane-guard violations=0** |

## 실행 순서 (운영 — 권한 전면 승인됨)

1. 본 PR 병합(merge queue — 현 활성 공급자 Ubicloud에서 실행, 정상 경로).
2. `gh workflow run ci-provider-router.yml --repo Archright/Axiom -f
   force_trial=true` — 설계된 수동 검증 경로(월간 창/same-day/20h/상한 우회,
   **시도 counter 미소비**, UBICLOUD_ACTIVE 전용 — 현재 충족; 운영 전례
   `docs/evidence/ci_provider_failover_2026-10-23.md` :167).
3. canary 성공 → 라우터가 CI_RUNNER_MAP을 `mode=ghec / GHEC_ACTIVE /
   return_acceptance=pending / generation+1`로 전이(단일 writer 보존 —
   **수동 PATCH 없음**).
4. PR-2(acceptance 증거 + RESID-13 amendment)의 check run이 **전환 이후
   생성**되어 GHEC에서 실행 → 라우터가 `executed>0 ∧ blocked=0 ∧ all_ghec`
   판정으로 `return_acceptance=confirmed` 기록(rerun은 증거 아님 — 문서 계약).
5. PR-2 merge_group의 GHEC 착지 + landing observe가 production acceptance를
   종결한다.

## 최종 증거 세트 (한 세트로 보존 — PR-2에서 완결)

1. PR-1 전후 workflow blob SHA(`27eb01be…` → PR-1 HEAD) + CI generation
   (14 → 15).
2. force_trial router run ID + canary run ID.
3. canary job의 `runner_group_id=0`, `runner_name`, 실제 step 결과.
4. 라우터의 변수 write 결과 + GET 검증값(byte-compare).
5. 새 generation에 귀속된 PR-2 required runs의 workflow run ID·attempt·head
   SHA·job 목록.
6. PR-2 merge_group의 GHEC runner identity + required check 결과.
7. merge SHA + `landing_observe.sh` OBSERVED_SUCCESS.
8. **전환 시각 이후 전체 모집단** Ubicloud 신규 job 0건 조사(전 run 완전
   페이지네이션 + rerun attempt 포함 + org required workflow 포함, skipped/미배정
   제외, `runner_group_id==1` = 0 — 관측계기는 양성 대조군으로 사전 검증).

## RESID-13 충돌 해소

RESID-13(11/1~3 창 관측, "관측만 수행·변경 금지")의 선언된 기대는 첫 시험에서
반증됐다. 창 내 대기는 11/2·11/3 자동 재시도가 **같은 결정론적 결함**으로 실패하며
시도 2/3·3/3을 소진해 복귀를 12월로 밀어낸다 — 잔여 관측 가치 0, 비용은 창 전부.
반증된 전제를 기록하고(ledger amendment, PR-2) 수리를 진행하는 것이 관측 계약에
부합한다. 관측된 사실 자체(시험 발화·실패·원인 귀속)는 본 기록이 보존한다.
