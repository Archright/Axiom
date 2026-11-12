# CI Epoch Record — 재진입(재arm) 경로 수리 (2026-10-23)

> **권위**: Reporter only. GitHub merge authority(ruleset·required checks·merge queue·MERGE)를 대체하지 않는다(AGENTS.md §2.3). 본 문서는 `docs/agents/ci_epoch_cutover.md`(AGENTS.md §2.5)의 10단계 중 이 슬라이스가 수행한 단계의 기록이다.

## 변경 내용 (coherent generation 단위)

| 구성 | 내용 |
|---|---|
| Workflow | `.github/workflows/merge-queue-rearm.yml` — condition 6 run 해석을 **페이지 소진 전수 조회**(10×100 = API pagination 상한 1,000건, 이 저장소 MG cadence에서 **실측 5.15일** — 2026-10-24 정정)로 교체하고, **admission-gate name 필터를 이중 형식 허용**(`name == "admission-gate"` 또는 `.yml` 경로형 — 2026-10-09/10-12 관측 형식)으로 보강. branch prefix `^gh-readonly-queue/main/pr-<N>-` 결속 유지. condition 9 arm 스텝에 `GH_TOKEN: ${{ secrets.REARM_ARM_TOKEN }}` (step-scope) + 부재 시 가시적 `token-missing` fail-safe |
| Credential | `REARM_ARM_TOKEN`(Actions secret) — fine-grained PAT, repo=Archright/Axiom 전용, **Pull requests RW + Issues RW**(condition 9 내 호출: `gh pr view`·`gh pr merge --auto`·라벨 POST — 읽기 호출은 job-level GITHUB_TOKEN이 담당하므로 Checks/Actions/Contents RO 불요). `DEPENDABOT_ARM_TOKEN`(Dependabot secret) — 별도 소비자, PR RW + Contents RO. **두 저장소는 별개 객체**(공식 문서: Dependabot-triggered 워크플로는 Actions secrets 접근 불가) |
| 무변경 | 클래스 폐쇄 열거(T1/T2/Permanent)·retry budget·fail-closed semantics·ruleset·required checks 5종·trustSurface. `merge-queue-rearm.yml`은 trustSurface 17항목 밖(CONTROLLED v80) — 정책 재등록 불요 |

## 10단계 수행 기록

1. **Freeze**: 사전 main = `1c5c51666`(PR #1051 merge 이후, 2026-10-23). merge SHA는 불변 참조.
2. **Record**: freeze 시점 required checks 5종(admission-check·bsec-integrity·debt-registry-gate·generation-acceptance·axiom-operational-slice) + merge queue(MERGE/ALLGREEN/1:1, 120분) — 본 슬라이스에서 **무변경 확인이 완료 조건**.
3. **Tombstone**: 해당 없음 — 파이프라인 결함 수리(신규 트리거·클래스·행위 없음).
4. **New Epoch**: 위 표의 workflow 변경 + credential 배선.
5. **Atomic Binding**: workflow 수정 + 두 시크릿 저장소 배선을 하나의 cutover 단위로 결속. trust binding(핀·digest) 무변경.
6. **Local/Targeted Verification**: YAML 파싱·condition 9 `bash -n` PASS; push-admissibility 게이트(로컬) 통과; `gh workflow run … dry_run=true historical=true`로 분류 파이프라인 회귀 확인.
7. **Short Validation**: (a) #919 historical dry-run → `UNKNOWN`(no-arm) 유지; (b) **#851 = no-run 음성 대조** 유지; (c) **독립 역사 모집단**(`docs/evidence/rearm_population_2026-10.json` — 2026-10-01~10-23 `RemovedFromMergeQueueEvent` 전수: **818 케이스/574 PR**) 대조. 구 로직 재현 결과: raw miss 97/818, **진성 누락 80/801(9.99%)** — 분해: **name 형식 불일치 77건**(경로형 `.github/workflows/admission-gate.yml`, 최빈 rank 5 — top-20 안에 있었음) + **top-20 overflow 3건**(rank 34/81/167) + 정상 음성(no-run) 17건, 모순 0. 두 수리(pagination + name 이중 형식)가 80건 전부를 커버. 수정 resolver의 검증 기준 = 각 케이스 `run_id` 없이 수행한 historical dry-run 판정이 독립 truth와 일치(mismatch 0).
8. **Canonical Cutover**: 본 PR 착지로 canonical 경로 적용. required-check identity·trust semantics 무변경 확인.
9. **Production Acceptance (관측 조항 — 완료 조건 아님)**: 자연 발생 TRANSIENT dequeue 시에만 — rearm verdict `class=TRANSIENT action=arm`, `rearmed@` 라벨, `enabledAt`이 해당 run 창 내, dequeue→enqueue 사이 User timeline 행위 0회, native MERGE. **발생 전 상태 표기 = "mechanism-ready, end-to-end unproven"**. 기간 비결속(가드 이후 자연 발생 0건 실측 — 빈도 근거 C3는 원 계산 경로 미발견).
10. **Rollback**: 본 PR revert + 두 시크릿 삭제 → fail-safe no-arm 복귀. 큐 권한 무손상.

## 기록 정정 (AGENTS.md §0.6 — 관측이 정적 모델을 보정)

`docs/evidence/pr_to_main_attribution_remaining_issues_2026-10-20.md:78`의 "condition 6이 repo-wide라 #851의 admission run을 놓쳐 UNKNOWN" 서술은 **관측과 모순**한다. live 재구성(2026-10-23): PR #851 dequeue(2026-10-15T14:26:50Z) 시점에 해당 PR의 merge_group run은 **0건**(DIRTY로 그룹 미구성) — `no-run` verdict는 올바른 fail-safe였고, 2차 발화는 PR이 MERGED 상태라 condition 2에서 차단되었다. 본 기록이 그 해석을 정정한다(기존 문서는 역사 기록으로 보존). pagination 결함 자체(단일 페이지·head 미결속)는 **잠재 결함**으로 실재하며 본 수리로 닫는다.

## 자격 증명 계약 (owner 승인: '권한이 필요한 부분은 전면 허가한다' 2026-10-23)

- **행위자 귀속**: PAT는 사용자(wintrover) 신원으로 귀속된다 — "비인간 행위자"를 완료 조건으로 삼지 않는다. 무인성 증거 = rearm run 로그 verdict + `enabledAt` 창 결속 + `--match-head-commit` + 라벨 + User timeline 행위 0회. 비인간 신원이 엄격히 필요하면 GitHub App 트랙(별도 승인·설치·키 관리) — 본 슬라이스 범위 밖.
- **rotation**: 두 PAT 모두 90일 만료. 만료 감시(일일 cron이 시크릿 존재를 확인) + 동시 교체 절차: 새 PAT 발급 → `gh secret set … --app <store>` → rearm/armer 다음 실행 로그에서 토큰 사용 확인 → 구 PAT revoke. 만료 시 동작 = `token-missing`(rearm) / `::error`(armer) — **조용히 멈추지 않는다**.
- **잔여**: Dependabot PR의 dequeue 이벤트는 read-only 컨텍스트일 수 있어 rearm은 no-arm(별도 경로인 dependabot armer가 사전 arm). 관측에 기록.

## 인과 범위 (주장 한정)

본 수리는 same-head TRANSIENT 재진입 회복(16 dequeue gaps 중 ≤7 이벤트 상한, 14일 창 자연 발생 0건)만 대상이다. `between_cycle_gap` p95(5,743.8s)의 주류(author fix·ROT_NEW_PIN·human_idle)는 대상 밖 — **전체 P95 감소 주장 금지**(사전등록 계량 시에만 주장).

## 정정 (2026-10-24) — 스캔 창의 실제 범위와 역사 재판정 기준

§7(c)의 "1,000건 ≈ 수 주분"과 "run_id 없이 80건 전부 커버 / mismatch 0"은 **착지 후 실측과 모순**한다. 본 절이 그 범위를 한정한다(원문은 역사 기록으로 보존).

- **실측 스캔 창**: 최신 merge_group run 1,000건 = `2026-10-19T03:11:45Z`..`2026-10-24T06:49:53Z` — **5.15일**, 194.1 run/일. "수 주분"은 성립하지 않는다.
- **모집단 재생**(2026-10-24, 수정 resolver와 동일 필터): 진성 누락 80건은 전부 `2026-10-09`..`2026-10-13` — 창 밖 → **0/80 해석**. 창 안 truth 129건은 **87 일치 / 42 불일치**, no-run 음성 17건은 **15 no-run 유지 / 2건은 이후 시도의 run으로 해석**.
- **불일치 42건의 원인**은 이름·페이지 결함이 아니라 resolver가 `created_at <= removal_ts` 상한 없이 최신 run을 선택하기 때문이다(다중 재시도 PR). live dequeue 시점에는 후속 시도가 존재하지 않으므로 최신 run = 방금 dequeue된 run — resolver는 **live-event resolver로서 정확**하다.
- 따라서 §7(c)의 "80/80 커버"는 제거 시점에서의 **반사실적 replay**이지 운영 관측이 아니며, 창이 지나면 재실행할 수 없다. **역사 재판정은 `run_id` 명시 결속으로만** 수행한다 — 스캔 기반 역사 완전성 주장 금지.
- **live 경로 실증**(2026-10-24, main, run `40073070913`): PR #1070 historical dry-run이 실제 merge_group admission-gate run `40071744943`(G=`996bd8093c49`)을 해석 — 창 안 결속 확인. runner = `ubicloud-standard-2`(FSN1-DC21, label `ubicloud-standard-2`).
- **무변경**: ruleset·required checks 5종·merge queue·trustSurface·클래스 폐쇄 열거·retry budget. §9의 자연 TRANSIENT dequeue 관측 조항이 여전히 live acceptance다.## 정정 (2026-10-24) — 만료 감시 조항은 구현되어 있지 않다

> 원문 「자격 증명 계약」의 "만료 감시(일일 cron이 시크릿 존재를 확인)"는 **구현이
> 존재하지 않는 서술**이었다. 본 절은 그 사실을 기록한다 — 원문은 역사 기록으로
> 보존한다(`docs/spec/github_ruleset_api_quirks.md` «수정 (2026-10-15)»와 같은 추기
> 스타일).

- **실측**: 저장소에서 `cron:`을 가진 워크플로는 셋뿐이고, 어느 것도 두 토큰을
  참조하지 않는다 — `admission-ssot-drift.yml:43`(`37 4 * * *`),
  `ci-provider-router.yml:83`(`7,37 * * * *`),
  `closure-watcher.yml:141`(`17 */6 * * *`).
  재현: `grep -rn "cron:" .github/workflows/*.yml` 및
  `grep -rn "REARM_ARM_TOKEN\|DEPENDABOT_ARM_TOKEN" .github/workflows/`.
- **존재 검사조차 주기적이지 않다**: 유일한 존재 검사는
  `dependabot-auto-merge.yml:48`(`ARM_TOKEN_PRESENT: ${{ secrets.DEPENDABOT_ARM_TOKEN != '' }}`)로
  **armer 실행 시점**에만 평가된다. rearm 쪽은 `merge-queue-rearm.yml:935-939`의
  arm 직전 `-z "${GH_TOKEN:-}"` 검사뿐이다.
- **존재 ≠ 유효**: `secrets.X != ''`는 만료된 토큰에도 true다. 만료 감지는 토큰으로
  실제 API를 호출해 성공/실패를 관측하는 방법만이 가능하며, 현재 그런 검사는 없다.
- **만료는 조용히 멈추지 않는다(유지되는 조항)**: 만료 토큰은 위 존재 검사를
  통과한 뒤 arm 호출에서 실패하고, 그 경로는 명시적 terminal failure로 끝난다
  (`merge-queue-rearm.yml:64-71` 헤더 계약, `dependabot-auto-merge.yml:51`
  `::error`). 즉 **다음 사용 시점에 가시적으로** 실패한다 — 사전 예고가 없을 뿐이다.
- **따라서 현재 만료 관리는 owner의 수동 추적이다.** 사전 감시를 자동화하려면
  `.github/workflows/**`(FROZEN, `config/repository_surface.json:322`) 변경이므로
  정책 PR 또는 기존 일일 cron(`admission-ssot-drift.yml`) 편입 결정이 선행되어야
  한다 — 본 슬라이스의 범위가 아니다.