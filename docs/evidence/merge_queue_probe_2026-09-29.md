# Merge Queue Phase 0 측정 — GitHub Merge Queue 착지 그래프 (run 1/2)

- 측정일: 2026-09-29 (UTC)
- ADR: [docs/adr/0027-queue-delegation.md](../adr/0027-queue-delegation.md) (PROPOSED — Phase 0 측정)
- 판정 규칙: α = parents(L)==[B, H_PR]; β = parent2(L)==G ∧ tree(L)==tree(G); γ = 그 외 → 즉시 STOP·재의결
- 측정 워크플로: `.github/workflows/probe-merge-queue.yml` (merge_group payload v2 capture + push judge)
- 스코프 브랜치: `queue-probe` (scratch; main에는 merge_queue 미적용 — ADR-0027 범위 유지)

## 0. 측정 전 상태 점검 시 발견한 차단 및 해소 (사전 수리)

| 항목 | 발견 | 조치 |
|---|---|---|
| probe-merge-queue 워크플로 전체 이벤트 `startup_failure` (job 0개) | 저장소 Actions 설정 `allowed_actions=selected` + `sha_pinning_required=true` → `actions/checkout@v4`·`upload-artifact@v4` 가변 태그 거부 (run 생성 단계) | SHA 핀 교체: checkout `11d5960a326750d5838078e36cf38b85af677262`, upload-artifact `ea165f8d65b6e75b540449e92b4886f43607fa02` (repo 관례 22/15 회 사용). bisect 증거: 36532038699/36533440173/36533420461(startup_failure) → EXP-3d 36535181133/EXP-3f 36535429549(checkout@v4 재현) → fix 36535715731(success). 수정 commit 2cef5c38d (#359) 동일 essence로 main+queue-probe 착지 |
| 기존 ruleset `queue-probe-scratch`(24162466, 선행 에이전트 생성)의 required check context | 본 저장소는 check run 이름을 **job 이름(bare)** 으로 등록한다(API 실측: `probe-capture` — `probe-merge-queue / probe-capture` 아님; main ruleset 20303214도 bare `admission-check` 사용) | 신규 ruleset `queue-probe`(24164452) + 24162466 PUT 동일 규칙으로 정렬 — required context `probe-capture` 단일 |
| head_ref의 PR 번호 포함 | `refs/heads/gh-readonly-queue/queue-probe/pr-<N>-<base_sha>` — 비계약(P1) — 정보용 관측만 | 파싱하지 않음 (payload 원문 보존) |

## 1. ruleset 구성 (API 실측 echo, 2026-09-29)

- **24164452 `queue-probe`** (본 측정용 생성): target branch, enforcement active, conditions `ref_name.include=[refs/heads/queue-probe]`
  - `merge_queue`: merge_method MERGE · grouping_strategy ALLGREEN · max_entries_to_build 2 · min_entries_to_merge 1 · max_entries_to_merge 1 · min_entries_to_merge_wait_minutes 0 · check_response_timeout_minutes 60
  - `required_status_checks`: strict false · `[{"context":"probe-capture"}]`
  - `pull_request`: allowed_merge_methods [merge] · required_approving_review_count 0 · code_owner false · last_push_approval false · thread_resolution false · extra_approval false
  - `non_fast_forward` · `deletion`
- **24162466 `queue-probe-scratch`** (선행 에이전트 생성): 위와 **동일 규칙**으로 PUT 정렬 (최초 생성본은 context `probe-capture`·wait 1 — 본 저장소 실측 naming과 일치; 미정렬 시 이중 ruleset 결합 불확실성)

## 2. 기존 ruleset의 queue-probe 적용 여부 (조건 실측)

| ruleset | scope (api 실측) | queue-probe 적용? |
|---|---|---|
| 20303214 `main` (repo) | `ref_name.include=[~DEFAULT_BRANCH]` | 아니오 |
| 24041674 `axiom-admission-gate` (org) | `ref_name.include=[refs/heads/main]` + repo Axiom | 아니오 |
| 23943917 `landing-integrity` (org) | `ref_name.include=[refs/heads/main]` + repo Axiom | 아니오 |
| 23969951/23967915 (push) | push 타깃, 경로 제한 | 아니오 (실행 경로 아님) |

## 3. 원시 측정 기록 (raw measurements)

### Run 1 — PR #361 (head `mq-probe/measure-1`, marker `data/mq-probe/measure-1.md`)

payload artifact: `merge-group-payload-a01480d15…` (artifact id 11019131674, schema v2, runId 36537112800)

| 필드 | 값 |
|---|---|
| G (merge_group.head_sha) | `a01480d156574404ec45933cfe61be9dd3dbeee8` |
| head_ref (verbatim) | `refs/heads/gh-readonly-queue/queue-probe/pr-361-e5a37e7148cbd5ceab29418115d82ad9ef7b10a1` |
| head_ref에 PR 번호 포함? | **예** (`pr-361`) — 정보용, 비계약 |
| base_sha (B) | `e5a37e7148cbd5ceab29418115d82ad9ef7b10a1` |
| base_ref | `refs/heads/queue-probe` |
| head_commit.tree_id | `44eb0a9a0d2fb1c0720a4cc346ea6ed837b45aae` (**존재**) |
| GITHUB_SHA (교차검증) | == G |
| L (착지, queue-probe tip) | `a01480d156574404ec45933cfe61be9dd3dbeee8` |
| parents(L) | `[e5a37e7148cbd5ceab29418115d82ad9ef7b10a1, 96e1fb05e7d1fcd54be44a304a069545c5f5d12d]` |
| tree(L) | `44eb0a9a0d2fb1c0720a4cc346ea6ed837b45aae` |
| H_PR (PR #361 head commit) | `96e1fb05e7d1fcd54be44a304a069545c5f5d12d` |

판정 질의 4종: **L==G: true · parent1(L)==B: true · parent2(L)==G: false · tree(L)==tree(G): true**

judge PROBE_VERDICT (run 36537172536, push@queue-probe):
`PROBE_VERDICT payload=payload.json L==G:true parent1(L)==B:true parent2(L)==G:false tree(L)==tree(G):true parents(L)=[e5a37e7148cbd5ceab29418115d82ad9ef7b10a1,96e1fb05e7d1fcd54be44a304a069545c5f5d12d]`

### Run 2 — PR #363 (head `mq-probe/measure-2`, marker `data/mq-probe/measure-2.md`)

payload artifact: `merge-group-payload-22e1d2667…` (artifact id 11019415507, schema v2, runId 36537690546)

| 필드 | 값 |
|---|---|
| G (merge_group.head_sha) | `22e1d2667d473eebba4ae77a32c0daed7c1c6f4f` |
| head_ref (verbatim) | `refs/heads/gh-readonly-queue/queue-probe/pr-363-a01480d156574404ec45933cfe61be9dd3dbeee8` |
| head_ref에 PR 번호 포함? | **예** (`pr-363`) — 정보용, 비계약 |
| base_sha (B) | `a01480d156574404ec45933cfe61be9dd3dbeee8` (= run 1의 L — 순차) |
| base_ref | `refs/heads/queue-probe` |
| head_commit.tree_id | `6b9b4226d310cc63ec9ca1438aee13ed6e326c81` (**존재**) |
| GITHUB_SHA (교차검증) | == G |
| L (착지, queue-probe tip) | `22e1d2667d473eebba4ae77a32c0daed7c1c6f4f` |
| parents(L) | `[a01480d156574404ec45933cfe61be9dd3dbeee8, baab18262979e9ae2b86f6450be0047516d33728]` |
| tree(L) | `6b9b4226d310cc63ec9ca1438aee13ed6e326c81` |
| H_PR (PR #363 head commit) | `baab18262979e9ae2b86f6450be0047516d33728` |

판정 질의 4종: **L==G: true · parent1(L)==B: true · parent2(L)==G: false · tree(L)==tree(G): true**

judge PROBE_VERDICT (run 36537749568, push@queue-probe — 2건 payload 전부 판정):
- run-1 payload 대조 (기대: 불일치): `L==G:false parent1(L)==B:false parent2(L)==G:false tree(L)==tree(G):false`
- run-2 payload 대조: `PROBE_VERDICT payload=payload.json L==G:true parent1(L)==B:true parent2(L)==G:false tree(L)==tree(G):true parents(L)=[a01480d156574404ec45933cfe61be9dd3dbeee8,baab18262979e9ae2b86f6450be0047516d33728]`

## 4. 판정 (classification)

- **Run 1: α** — parents(L)==[B, H_PR] (동시에 L==G, tree(L)==tree(G))
- **Run 2: α** — parents(L)==[B, H_PR] (동시에 L==G, tree(L)==tree(G))
- β 조건( parent2(L)==G ∧ tree(L)==tree(G) )는 **두 런 모두 미충족** (parent2 = H_PR).
- **γ 없음** — STOP 조건 미발동.

### 관측 사실 (형상 확정 아님 — Phase 0 측정값)

1. **L == G**: merge group의 검증된 SHA(= `gh-readonly-queue` 임시 ref tip)가 **그대로** 타깃 브랜치에 착지했다 (2/2).
2. **착지 커밋 형태**: 단일 PR 큐 그룹에서 L = 일반 MERGE 커밋 `[B, H_PR]` — GitHub UI 수동 MERGE와 동일 모양.
3. **tree(L) == tree(G) == tree_id**: payload의 `head_commit.tree_id`는 G의 트리와 일치 (2/2) — 문자열 비교로 G 객체 부재에서도 판정 가능.
4. **head_ref 형식**: `refs/heads/gh-readonly-queue/<base>/pr-<N>-<base_sha>` — PR 번호 포함 — **비계약(P1)**; 파싱하지 않았다.
5. `merge_group` group ref 이름에 base_sha가 붙는다 (예: `pr-363-a01480d1…`).
6. judge는 저장소 전체 payload를 열거해 **모든** 판정을 수행한다(교차-런 비교 포함 — 위 run-2의 run-1 대조 라인).

## 5. 측정 환경 노트

- 순차성: run 1 착지 후 run 2 enqueue — 큐는 단일 항목 그룹으로 즉시 구성·착지 (wait 0, ALLGREEN, max_entries_to_merge 1).
- 프로브 존재로 인한 간섭 없음: 프로브는 status/check API를 호출하지 않으며 required check도 아님 (`probe-capture`는 merge_group/PR 이벤트 확인용 — 큐 required check로 등록됨).
- 기여: 측정 PR (#361/#363)은 병행 재개된 선행 에이전트 세션이 생성; ruleset 정렬·워크플로 수리·run 1 enqueue·판정 수집은 본 세션. 두 세션 모두 동일 ADR-0027 Phase 0 계획 실행 — 큐가 순차화하여 측정 간섭 없음.
- 파생 파일: 페이로드 원본 JSON은 아티팩트 `merge-group-payload-<G>` (retention 90일), 본 문서의 표 값은 해당 아티팩트 원문 + `git cat-file` 실측.

---

## 부록 2 (close-out 보존): 규칙셋 동시성 사고 기록 (원문 출처 PR #365, 병행 세션 보고서)

> 본 절은 PR #365(병행 세션의 별개 증거 초안, superseded)의 **고유 감사 기록**을
> 무변경으로 보존한다. 본 문서의 본체는 1회 측정의 정본(#364 계열)이며, 아래는
> 측정기 생성 시점의 규칙셋 경합 관측이다. (2026-09-29 close-out 시점 이식)

## 부록 (2026-09-29 16:48+09): 규칙셋 동시성 사고 기록

- **관측**: 측정 완료 후 재조회에서 `queue-probe-scratch`(24162466)의 일부 파라미터가
  복원 값과 달랐다(`min_entries_to_merge_wait_minutes` 1→0 · `strict` true→false ·
  required-status 컨텍스트 `probe-merge-queue / probe-capture`→`probe-capture` ·
  extra-approval true→false). `updated_at`이 복원 PUT과 **같은 초(16:27:19+09)** —
  동시 진행 중인 형제 에이전트의 동일 초 PUT과 last-writer-wins 레이스로 판정된다.
- **형제 규칙셋 발견**: 같은 ref 스코프(`refs/heads/queue-probe`)의 **두 번째 규칙셋
  id 24164452**(생성 16:27:06+09, 이름 = `"$( [ $id = 24164452 ] && echo queue-probe || echo queue-probe-scratch )"` —
  셸 주입형 문자열)가 존재한다 — 형제 에이전트(`feature/merge-queue-candidate-cert` 계열,
  `evidence/mq-probe-phase0` 브랜치 실측)가 생성한 것으로 보이며, wave 2에서
  규칙셋 병합·충돌 판정이 필요하다(본 보고서 작성 시점엔 수정하지 않음).
- **측정 유효성**: α/β/γ 분류는 큐의 **착지 그래프**(group 커밋 구성·착지 형태) 관측이며,
  위 파라미터(체크 컨텍스트 문자열·strict·wait)는 진입/평가 의미론에는 관여하나
  착지 커밋 형태에는 무관 — 측정 1·2의 α 판정은 유효.
- **원상 복구**: 24162466을 승인 구성으로 재복원(16:48:31+09, live 검증 완료).

