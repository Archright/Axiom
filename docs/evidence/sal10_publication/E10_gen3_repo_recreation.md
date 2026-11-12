# E10 — gen-3 저장소 재생성(Repo Recreation) 컷오버 기계 관측 기록

**실행일**: 2026-11-11 (동결창 개시 2026-11-11T00:39:09Z · Phase 4 완료 readback 01:00:00Z · Phase 5 rotation PR 착지 **2026-11-11T02:04:47Z** · capsule 재봉인·최종 PR #10 착지 **2026-11-11T06:32:54Z** · 종단 4조건 ALL TRUE **06:33Z** · Phase 7 구세대 폐기 관측 **07:12:14Z**) · **판정**: GEN3_RECREATION_COMPLETE (Phase 1–7 완결 — Phase 7은 인간 수동 실행·에이전트 관측)

> **개정 상태**: 본 문서는 rotation lane PR #4(착지 2026-11-11T02:04:47Z·MERGE `894defc7`)로 착지된 초안의 **E10 완성 개정**이다 — Phase 5 관측을 확정 기록한다. 각 관측 행은 관측 시점의 스냅샷이다. 관측되지 않은 값은 지어내지 않고 PENDING/UNKNOWN으로 남긴다.

## Ultimate Purpose

공개 전환의 유일한 기계적 차단 — 구 repo(id 1448376585)의 `refs/pull/*`가 사전 침소 세대(E7 재작성 전 루트 `938a49e` — 제거 경로 포함)에 도달 가능(E9 조건 2 잔여 관측: `refs/pull/24` 경유 pre-E7 세대 도달) — 을, **이력 재작성 없이 같은 커밋 그래프 push로 저장소 신원만 리셋**하여 해소한다. `refs/pull/*`는 사용자측에서 삭제 불가하므로(E5:45 교리: 실제 접근 차단은 "Support dereference 또는 저장소 삭제·재생성"뿐 — Support 경로는 2026-11-06 폐기, E6:26), E6 체인의 2차 적용으로 세대를 교체한다:

- **gen-2** `Archright/Axiom`(id **1448376585**) → 리네임 `Archright/Axiom-gen2`로 격리(private·Actions 동결 유지)
- **gen-3** 신규 `Archright/Axiom`(id **1453354095**) 부트스트랩 — 태생부터 구세대 PR refs 미보유
- 콘텐츠 정체성 유지: GEN3_BOOTSTRAP_SHA `d753d923` — 같은 커밋 그래프 계승, 재작성 0

공개 전환(private→public)은 본 문서 범위 밖 — 사용자 전용, Capsule 착지가 전제(실행 계획 v2).

## 기준 SHA 체계

| 기준 | 값 | 의미·상태 |
|---|---|---|
| **GEN3_BOOTSTRAP_SHA** | `d753d92356cbb1d7e0195b57ac9f6245a2951dba` | **Phase 3 검증용 초기 계승 SHA** — 구세대 main을 변경 없이 계승(재작성 0). 본 문서 Phase 3 관측으로 확정 |
| **GEN3_FINAL_MAIN_SHA** | `74e27ee2` | **capsule 재봉인 시점의 main**(`ls-remote origin main` 실측) — 봉인 이후 최종 착지 `CAPSULE_MERGE_SHA`(parent[0]=74e27ee2)가 main을 전진시키며 종단 4조건 ③④로 검증 |

종단 검증(2026-11-11T06:33Z 실측 — **전부 TRUE**): ① `merge-base --is-ancestor d753d923 74e27ee2` TRUE ② capsule `binding.targetCommitSha`(74e27ee2) == 봉인 시점 `ls-remote main`(74e27ee2) MATCH ③ `CAPSULE_MERGE_SHA adfbc8a7` parent[0] == 74e27ee2 TRUE ④ rotation·E10·baseline·capsule 4개 MERGE 전부 main 도달 TRUE×4.

## 관련 규칙

- **§0.3 신뢰 경계 (HARD RULE)** — "차단 해제"를 위한 신뢰 경계·정본 계약 우회 금지. 본 컷오버의 잠금 해제(org ruleset GH013 `do_not_enforce_on_create` 1필드 PUT 등)는 전부 백업 → 최소 변경 → readback 대조의 문서화된 절차로 수행됐다(우회 아님).
- **§2.5 CI Self-Bootstrap Bottleneck (HARD RULE)** — 활성 실행 경계를 in-place 부분 수정하지 않고 **일관된 세대(coherent generation) 전환**으로 착지. 동결창(구 repo 정지) → 리네임 격리 → 신규 repo 부트스트랩 → 통제 평면 재구성의 전체 시퀀스가 하나의 세대 전환이다.
- **§2.6 변경 불변조건 프로토콜 (HARD RULE)** — 산출물당 생성 authority 하나·실행은 산출물·상태가 아님. 같은 커밋 그래프 push(`d753d923`)는 재실행이 아닌 **계승**으로 identity를 불필요하게 변동시키지 않으며, repo id·ruleset id·workflow id 등 저장소 스코프 자원의 신규 발급은 readback 관측으로 기록한다. 완료 주장은 기계적 관측 증거로만.
- **§2.4 자격 증명 권한 (HARD RULE)** — 시크릿 실값·GitHub App 설치는 값 이전 API 부재로 **인간 전용 체크포인트**로 분리(Phase 4) — 발견·대체 수단 사용 없음.

## 관측 경계

- 실행 계약: gen-3 컷오버 계획 v2(리네임 → 재생성 → 검증 → 삭제) — 본 문서는 그 관측 기록의 Phase 1–4분.
- repo 내용은 격리 fresh 클론(`/tmp/gen3-verify`)·mirror(`/tmp/gen2-mirror.git`)에서 읽었다(문서 작성 시점 대조: main `d753d923` · 커밋 178 · 루트 `6104b249` tree `22538ce0` · 태그 5 · 레저 ref 2 · LFS OID `8c744d79…61eaa` — 본문 기록값과 정합).
- 스냅샷 산물(bundle·refs 목록)은 사적 캐시 보관 — repo/Actions 업로드 금지(E7 사적 캐시 관례).

## Phase 1 — 동결창 (구 repo 정지)

**개시 2026-11-11T00:39:09Z** · 종료(신규 repo Actions 재활성 readback) **2026-11-11T01:00:00Z** — gen2의 Actions 동결은 격리 상태로 유지(Phase 7 삭제 시점까지).

| # | 검사 | 기준 (계획 v2 동결 조건) | 본 실측 | 판정 |
|---|---|---|---|---|
| 1 | 비종료 run 6종 | `status ∈ {queued, in_progress, waiting, pending, requested, action_required}` 각 `total_count == 0` | 6종 전부 `total_count == 0` | PASS |
| 2 | 오타 방지 불변식 | `status=completed` total_count == 무필터 total_count | **1932 == 1932 → MATCH** | PASS |
| 3 | 열린 PR | `pulls?state=open` → 0 | **0** | PASS |
| 4 | merge queue 이중 신호 | GraphQL `mergeQueue{entries}` 0 **∧** `gh-readonly-queue/*` refs 부재 | entries **0** ∧ refs **부재** — 양 신호 일치 | PASS |
| 5 | Actions 비활성 | PUT `enabled=false` → GET readback | readback **`{enabled:false}`** | PASS |
| 6 | TOCTOU 재관측 | 비활성 직후 재관측 1회 — gap 발화 run 기록 | 신규 발화 run **0** | PASS |

동결창 스냅샷 (사적 캐시):

| 산물 | 실측 |
|---|---|
| `gen2-full.bundle` (`git bundle create --all`) | sha256 `c1742c20ac1d1907268e894e76de715825d2570c1bc51454c67f352a48eb3bcb` · **21,947,736 bytes** |
| `pre-cutover-refs.txt` (`git ls-remote origin` 전수) | **80줄** = HEAD 1 + heads 3 + tags 5 + pull 71 |
| LFS 객체 | 확보(`git lfs fetch --all`) |

**E8 기준선 불변** (동결창 내 대조): 아카이브 `Archright/Axiom-archive` id **1182104685** · refs **1,527** · main `b4c08e94e` · Actions **disabled** — 전 항목 불변 확인.

## Phase 2 — 리네임 (격리 — 공개 안전성 MUST 확보 시점)

| 항목 | 기준 (계획 v2) | 본 실측 | 판정 |
|---|---|---|---|
| 리네임 | `PATCH name=Axiom-gen2` → readback | **Axiom → Axiom-gen2** (2026-11-11T00:40:23Z 관측) | PASS |
| repo id | 1448376585 불변 | **1448376585 불변** | PASS |
| 가시성 | private 유지 | private 유지 | PASS |
| Actions 동결 | 유지 | 동결 유지 | PASS |
| 공개 안전성 (MUST) | 리네임 시점 확보 | **확보** — 신규 repo는 태생적으로 구세대 PR refs 미보유 (§MUST/POLICY 분리 참조) | 기록 |

리네임 = 신원 보존 격리(E6이 gen-1을 `Axiom-archive`로 보존한 방식과 동일 — id·객체·이력 전부 보존, 이름만 격리).

## Phase 3 — gen-3 부트스트랩 (Git Continuity — 같은 그래프 push)

실행 관측:

| 항목 | 기준 (계획 v2) | 본 실측 | 판정 |
|---|---|---|---|
| 신규 repo 생성 | `gh repo create --private` → 신규 id ≠ 1448376585 | **`Archright/Axiom` id 1453354095** (2026-11-11T00:41:33Z) | PASS |
| 초기 Actions 상태 | 비활성 시작 | **Actions disabled로 시작** | PASS |
| GH013 언락 | org ruleset 2종(**25218071**·**23943917**) 전체 GET 백업 → `do_not_enforce_on_create=true` **1필드만** PUT → readback | 백업 → 1필드 PUT → **readback 확인** | PASS |
| main push | 격리 mirror(`/tmp/gen2-mirror.git`)에서 push — 같은 SHA | main **`d753d923`** (GEN3_BOOTSTRAP_SHA) | PASS |
| 레저 이월 | side ref 그대로 push | `axiom/certificates` **`84f30200`** · `axiom/evidence-cas` **`555c9c99`** | PASS |
| 태그 5종 push | 5종 | `ci-frozen-2026-11-10-pi-shard` `f519fa1` · `v0.6.0` `70d1b66f` · `v0.6.1` `5ff3ce7e` · `v0.6.2` `c602a362` · `v0.6.3` `87cf67b9` | PASS |
| LFS push | "100% (1/1)" | **"100% (1/1)"** | PASS |
| org ruleset 원복 | 백업 페이로드 그대로 PUT → readback | flag **false** 복원 · 핀 **`1eed0a48`/`ff516bab` 무변** · readback diff **1필드** · 2026-11-11T**00:42:50Z** | PASS |

GH013 근거: 신규 repo의 초기 main push는 org required workflow 만족 이력이 존재할 수 없어 거부됨(구조적 제약 — E6 실측과 동일) — 1필드만 PUT·즉시 원복(00:42:50Z)의 최소 무효화·복원 경로.

검증 관측 (Phase 3 직후 — 신규 repo):

| 검증 | 기대 | 본 실측 | 판정 |
|---|---|---|---|
| 핀 루트 존재 | 루트 `6104b249`(`.github` callee 핀 대상) 서버 존재 | **존재** — tree `22538ce0` | PASS |
| 조상성 (스쿼시 방어) | `compare/6104b249...main` ahead | **ahead 177** (전체 커밋 **178** — 핀 루트가 main의 조상) | PASS |
| LFS 무결성 | fresh 클론 sha256 == OID | `/tmp/gen3-verify` — sha256 == OID **`8c744d79…61eaa`** | PASS |
| PR refs | `refs/pull/*` 0건 | **0건** | PASS |

## Phase 4 — 통제 평면 재구성 (repo-scoped)

관측 완료:

| 항목 | 기준 (계획 v2) | 본 실측 | 판정 |
|---|---|---|---|
| repo ruleset 4종 재생성 | 4종 active | `main` **26996019** · `cas-probe-scratch` **26996020** · `execution-surface-create` **26996021** (구 26702960) · `artifact-hygiene` **26996023** — 전부 **active** | PASS |
| ruleset readback | repo 4 + org 2 = 6종 | **org 2종 포함 readback 6종** (25218071·23943917 포함) | PASS |

적용 완료 (관측 readback — 2026-11-11T00:58:46Z–01:01:50Z):

| 항목 | 적용값 | 관측 readback |
|---|---|---|
| 저장소 설정 (병합·트래커) | allow_merge_commit **true** · allow_squash_merge **false** · allow_rebase_merge **false** · allow_update_branch **false** · delete_branch_on_merge **true** · has_issues **true** · has_wiki **true** | PATCH readback 전 필드 일치 |
| Actions 변수 2종 | `REARM_APP_ID=5550340` · `CI_RUNNER_MAP`(ghec 상태 JSON — gen2 백업값 그대로) | POST readback **total_count=2** |
| 환경 3종 + 보호규칙 | `ci-provider-router`(id **26900896602**, branch_policy **72023200**, custom_branch_policies=true·protected_branches=false + deployment-branch-policy **main** id 66258401) · `diagnostic-authority`(id **26900898648**, 규칙 0) · `release-authority`(id **26900897338**, required_reviewers **72023201** — reviewer wintrover id **53123826**, prevent_self_review=false) | GET readback 전부 일치 |
| 러너 그룹 3종 | `axiom-ci`(3)·`axiom-publisher`(4)·`axiom-control`(7)에 신규 repo **1453354095** 추가 | readback 각 그룹 3 repo(archive+gen2+신규) |
| Actions 재활성 | enabled=true · allowed_actions=all · sha_pinning_required=false / workflow perms: default=read · can_approve_pull_request_reviews=false | readback 전부 일치 — **2026-11-11T01:00:00Z** |
| workflow 신규 ID | **29종**(28 `.github/workflows` + 1 dynamic/dependabot) 전부 active | admission 5종: bsec-integrity **414023973** · debt-registry-gate **414023986** · generation-acceptance **414023995** · axiom-operational-slice **414023971** · publication-integrity **414024007** (관측 2026-11-11T01:01:50Z — merge_admission.json v1.21.0 workflowIdObservation으로 등록) |

전이 불필요 확인 (gen2에서 0건 — 복사 대상 없음): repo secrets · org secrets · org vars · teams · direct collaborators · repo hooks 전부 0건.

org ruleset 2종(25218071 `axiom-admission-gate`·23943917 `landing-integrity`)은 `repository_name include ["Axiom"]` + `refs/heads/main` 타겟팅 — 신규 repo가 이름 타겟팅으로 **자동 커버**(ruleset 본체는 수정·재생성 불필요; GH013의 원인과 동일 메커니즘).

### Phase 4 부수 관측 (정직 기록)

- **dependabot PR #1–3 존재** (신규 repo, 2026-11-11T00:42–43Z): repo 생성 직후 디폴트 Actions 활성 창에서 dynamic dependabot(`dependabot-updates`)이 actions 버전업 PR 3건 개설(`actions/cache/save`·`actions/upload-artifact`·`actions/checkout`). Phase 3 "refs/pull/* 0건" 관측은 **2026-11-11T00:41:33–00:43 사이 유효한 스냅샷**이다(시점 주석 — E7 양식) — 이후의 PR refs #1–3은 전부 신세대(main `d753d923` 분기)로 구세대 도달 경로가 아니다(격리 목표 무영향). rotation lane PR 번호는 #4 이상.
- **00:43Z admission 런 3건의 2초 전-스킵 failure**: org `admission-gate`·`landing-integrity`가 dependabot PR에서 발화했으나 잡 전부 skipped·run failure(2초). 타이밍상 `vars.CI_RUNNER_MAP` 미생성 시점(`fromJSON(vars.CI_RUNNER_MAP)` → 무효 러너 라벨)의 워크플로 레벨 실패로 진단 — 변수는 00:58Z 생성 완료로 원인 제거. 이 실패는 stale 관측이며 최초 정상 실행 관측은 rotation lane PR의 admission 런으로 수행한다.
- **A-2 핀 해석 증거(절반)**: 00:43Z 런(run 42933562365, org `admission-gate`)의 `referenced_workflows`가 **3종 전부 sha `6104b249c14c50c183dd54a428168b29a9561f10`** — 재생성 repo에서 org callee 핀이 SHA로 해석됐음의 플랫폼 관측. 실행 성공 관측(잡 로그 `Uses:` 라인·rollup isRequired)은 Phase 5 rotation PR 런에서 확정한다.
- **A-1.6 기준선 실측(예상치 정정 포함)**: Axiom 자체 `.github/`의 `@6104b249` 핀은 **0개**(192개 `uses:` 라인 전수 분류: 내부 로컬 경로 39 = composite action 35 + 로컬 재사용 워크플로 4 · 외부 액션 153 전부 풀 40-hex SHA 핀). **핀 9개의 소재는 org 저장소 Archright/.github**(id 1182157951 — 재생성 안 됨) @ `1eed0a48`: parse-probe.yml 3(:21·:30·:39) + admission-gate-v2.yml 6(setup-axiom-toolchain :266 · admission-check :440·:666 · certificate-mint :492·:549 · runner-pool-acceptance :584). TWS = **889 엔트리**(예상 885는 PR #71 `reanchor_pin` 회전 이전 구값 — `external_verification_campaign_001` §4 관측과 정합; 정본 `config/trusted_writer_set.json` `trustedCheckerTreeClosure` — blob-sha 핀은 내용 주소라 repo 재생성에 불변) · bsec = **140**(file 128 + archive 12, MANIFEST 정본).

**인간 전용 체크포인트 (§2.4 — 에이전트 수행 불가)**:

- GitHub App 재설치 — **REARM App 5550340**
- Actions 시크릿 **6종** 값 재입력 — **값 이전 API 부재**(NON_TRANSFERABLE — E8 인벤토리 #12와 동일 근거) → 정직 기록 후 비필수 검사로 진행 (선례 **E6:63**: 시크릿 부재·rearm 비활성 기록 후 진행)

## Phase 5 — 신원 재결속 (rotation lane PR #4 착지 — gen-3 첫 native MERGE)

**PR #4** `workstream/gen3-identity-rebinding` @ `5496af5a78ee78f5066f81429ccce50160469f04` → **MERGED 2026-11-11T02:04:47Z** · mergeCommit **`894defc7baa7b540cd583a8665db429989c11efa`**

lane 구성(3 파일): `config/policy/merge_admission.json` **v1.21.0**(workflowIdObservation 5종: bsec-integrity 414023973 · debt-registry-gate 414023986 · generation-acceptance 414023995 · axiom-operational-slice 414023971 · publication-integrity 414024007, observedAt 2026-11-11T01:01:50Z) · `tools/ci/m7_canary_drill.sh:71` PROD_RULESET_ID 26702792→**26996019** · 본 E10 초안.

| 항목 | 기준 | 본 실측 | 판정 |
|---|---|---|---|
| 로컬 게이트 | pre-commit·pre-push | pre-commit **PASS**(44.7s) · pre-push 15종 **green**(95s, snapshot 5496af5) | PASS |
| PR-venue admission | 발화 런 전 green | 12 런 발화 → **32 pass / 0 fail** · mergeStateStatus **CLEAN** · TRUST_SURFACE_MODIFIED required context exit 0(PR-venue PREFLIGHT) | PASS |
| 병합 권한 | MUST-T2a — PR 본문에 위임 기록(사용자 2026-11-11 "권한이 필요한 부분은 전면 승인한다." 원문 인용 · executor 표기 · 일회성 `gh pr merge 4 --merge` 명시 · `--auto` 금지)을 병합 명령 **전에** 선반영 | 위임 기록 선반영 확인 후 일회성 실행 **exit 0** → merge queue 진입(entries 1·position 1) → merge group `894defc7baa7` 빌드 | PASS |
| merge-group 체크 | 전 green이어야 착지 | **9종 전부 SUCCESS**(branch `gh-readonly-queue/main/pr-4-d753d923…`): probe-merge-queue 42941293182 · debt-registry-gate 42941293175 · generation-acceptance 42941293162 · bsec-integrity 42941293173 · observer-manifest-consistency 42941293165 · axiom-operational-slice 42941293217 · publication-integrity 42941293244 · admission-gate 42941293354 · landing-integrity 42941293191 | PASS |
| native MERGE | mergeCommit parents=2(FF 아님·수동 재무장 없음) | parents=2: `d753d923`(main) + `5496af5`(lane) | PASS |
| 조상 관계 | d753d923 ancestor of 착지 main | `merge-base --is-ancestor` **OK** — 초기 계승 SHA 보존(재작성 0 재확인) | PASS |
| main tip 일치 | ls-remote main == mergeCommit | **894defc7** 일치 | PASS |
| mergedBy | 운영자 gh auth 세션(MUST-T2a 조건 2) | **wintrover** | PASS |

**Phase 4 보완 교정(착지 경로에서 발견·정직 기록)**: repo 설정 `allow_auto_merge=true` PATCH — Phase 4 백업 필드 누락으로 첫 병합 명령이 1차 거부됨 → gen2 정본 대조 후 교정·readback 일치. merge queue 착지의 구조 전제(신규 repo 자동병합 설정)로, 권한 우회가 아니라 설정 재구성 누락의 최소 보완이다.

### A-2 핀 실행 관측 — 완결

| 증거 | 관측 시점 | 실측 |
|---|---|---|
| referenced_workflows | 00:43Z (Phase 4) | run 42933562365(org admission-gate) referenced_workflows **3종 전부 sha `6104b249`** — 재생성 repo에서 SHA 해석 관측 |
| PR-venue 잡 실행 | 01:24:09Z | run **42938691258**(org required-workflow admission-gate, pull_request) — 잡 130255815922 `attest / admission-independents` · 130256360027 `attest / admission-check` · 130256980599 `verdict / admission-check` 전부 **SUCCESS**, 잡 로그 `Uses: Archright/Axiom/.github/workflows/admission-check.yml@6104b249c14c…` 3종 |
| merge-group 잡 실행 | 01:45:55Z | run **42941293354**(merge_group) — **26잡 전부 SUCCESS**(핀 callee 재사용 `attest / admission-check`·`verdict / admission-check` 포함) |
| 메커니즘 확정 | 02:05Z | org ruleset **25218071** `axiom-admission-gate`(active · rule type `workflows`): path `.github/workflows/admission-gate-v2.yml` · **repository_id 1182157951**(org Archright/.github) · sha `1eed0a48` — required workflow가 **Axiom 컨텍스트에서 실행**(`repository_name include ["Axiom"]` · `refs/heads/main` 자동 커버)되므로 callee 핀 `Archright/Axiom/…@6104b249`은 실행 컨텍스트에서 same-repo로 해결된다. Axiom 트리에 admission-gate-v2.yml은 존재하지 않는다(런 path는 caller 측 파일 위치 — run 42938691258·42941293354의 path 관측과 정합). |

### parse-probe 직접 디스패치 관측 — 422 차단 · 원인 확정 · 공개 전환 이연

- **실측 (2026-11-11T01:53Z)**: `gh workflow run parse-probe.yml --repo Archright/.github` → **HTTP 422** `failed to parse workflow … Archright/Axiom/.github/workflows/admission-check.yml@6104b249…: workflow was not found`.
- **원인 (공식 문서 확정)**: GitHub Docs "Reusing workflow configurations — Access to reusable workflows" 호출자 접근 표: **호출자 public ⇒ 접근 가능 callee는 public뿐**. org Archright/.github는 **public**, Axiom는 **private** → .github 자체 컨텍스트 실행에서는 cross-repo callee 핀이 해석 불가. 대조 관측: 핀 루트 `6104b249`는 신규 repo에 존재(tree `22538ce0`) · 파일 blob `38ceca69`(295,682B) 존재 · allowed_actions 양측 `all` — **소실이 아니라 접근 규칙**이다.
- **회귀 아님(반증 관측)**: 재생성 이전 2026-11-07/08의 .github 자체 PR admission-gate 런 42354731415 · 42497740896 — **jobs=0**(같은 파스 실패)로 실패. 이 표면은 공개 .github→비공개 callee 구조에서 원래부터 불능이었다(Oct-12 parse-probe 런 38273175092 jobs=1은 당시 해석 성공 — .github 가시성 이력의 시점 차이로, 본 컷오버와 무관).
- **판정**: 운영 경로(org required-workflow의 Axiom 컨텍스트 실행)는 정상 작동 — **A-2 완결이 재생성의 핀 생존 실측을 충족**한다. parse-probe 직접 디스패치는 진단 보조 경로로서 **공개 전환(public→public) 후에만 해석 가능** — 해당 관측은 공개 전환 시점으로 **이연**하며, 본 문서는 이연을 "미관측·메커니즘 동일"이 아니라 **관측된 차단 + 문서 확정 원인**으로 기록한다.

### 착지 후 main 관측 (02:04:48Z 발화)

- 착지 push로 main 발화: trusted-writer-set **SUCCESS**(42943477134) · axiom-operational-slice 42943477141 발화(본 기록 시점 in_progress — 최종 판정은 Phase 6 admission-ssot-drift leg 기록과 함께 확정).
- **ci-provider-router fail-closed(설계대로·Theater 아님)**: 착지 전후 workflow_run 발화 5건(42941475099 · 42941549931 · 42941618960 · 42942184492 · 42942748987) 전부 동일 단계 failure `[gate] Fail closed when router App secrets are absent (human registration gate)` — §2.4 인간 전용 체크포인트(환경 시크릿 CI_ROUTER_APP_ID/CI_ROUTER_APP_PRIVATE_KEY 미재입력)의 문서화된 fail-closed 작동. merge-admission 필수 체크가 아니므로 착지·capsule 무영향.

## Phase 6 — 운영 인수 (NC 음성제어·baseline 등록·capsule 재봉인)

### Phase 6b — 음성제어 3건 (PR #6/#7/#8, 전부 미병합 close)

공통 설계: main(E1 `1a62ff9f`) 기준 별도 브랜치, 각 1파일, PR 오픈 →
publication-integrity 런 관측 → close + 브랜치 삭제 (pull ref 영속 — §2.4 전이성).

#### NC-1 secret-scan — PR #6 (`workstream/vsi-nc-secret`, head `4284a2f5`)

- 픽스처: `experiments/vsi-nc/nc_probe_secret.txt` — 무접두사 랜덤 32-hex 합성 토큰
  `a7f3c9d2e5b8a4f6c1d9e2b7a5f4c8d3` (정직 기록: 최초 준비 토큰 entropy 3.441<3.5
  미탐지 → 로컬 gitleaks 8.30.1 사전검증 포착·교체).
- run 42949275336: secret-scan **FAILURE**, 나머지 4차원(license·dependency·
  sbom·provenance) PASS — 차원 고립. 종합 **FAILURE**.
- report_secret.json verdict=FAIL newFindings 2 (masked):
  history `4284a2f5…:nc_probe_secret.txt:generic-api-key:2` +
  tree `nc_probe_secret.txt:generic-api-key:2`.
- GraphQL: publication-integrity **FAILURE**·isRequired=true·**BLOCKED**.
- close 03:1xZ·브랜치 삭제·mergedAt=null.

#### NC-2 license-scan — PR #7 (`workstream/vsi-nc-license`, head `e7592d7f`)

- 픽스처: `experiments/vsi-nc/nc_probe_gpl3.txt` — GPL-3.0 SPDX 정본 전문
  (34,674바이트, 232행 — FSF 저작권 라인 4).
- run 42951527248: license-scan **FAILURE**(시험 차원) + secret-scan **FAILURE**
  (교차오염 — newFindings 정확히 1건: NC-1 history 지문; GPL 텍스트 신규 시크릿 0) →
  종합 **FAILURE**.
- report_license.json verdict=FAIL: licenseViolations=[nc_probe_gpl3.txt
  atom=gpl-3.0-only deniedFamily=true "neither declared (source-origin.yml) nor
  attributed (license-attribution.yml)"] + copyrightViolations=[FSF holder
  startLine=4 not accounted] — gen2 §2.2(PR #48)과 동일 패턴.
- GraphQL: publication-integrity **FAILURE**·isRequired=true·**BLOCKED**.
- close·브랜치 삭제.

#### NC-3 provenance — PR #8 (`workstream/vsi-nc-origin`, head `d5270110`)

- 픽스처: 루트 `nc_probe_origin.bin` (1,036B — 불활성 filler, 로컬 gitleaks 0건
  선검증).
- run 42953722068: provenance **FAILURE**(시험 차원) + secret-scan **FAILURE**
  (교차오염) + license-scan **SUCCESS**(고립 실증 — license 스캔은 tree-scope라
  NC-2 GPL pull ref가 오염시키지 않음; gen2 §2.3과 동일) → 종합 **FAILURE**.
- report_provenance.json verdict=FAIL: checkedFiles=6594, declarations=64,
  undeclared=[nc_probe_origin.bin], undeclaredVerdict=**DENY**.
- GraphQL: publication-integrity **FAILURE**·isRequired=true·**BLOCKED**.
- close·브랜치 삭제.

**판정**: 3차원 전부 fail-closed 실증 — 극장(§0.9) 없음. 교차오염·고립 관측
모두 gen2 원판 §2 패턴과 정합.

### Phase 6c — baseline 감사 등록 (PR #9)

- `compliance/policy/secret-scan-baseline.json`에 NC-1 지문 2건 등록
  (classification `synthetic-test-fixture`, basis = E10 NC-1·run 42949275336,
  말미 append 최소 diff 17행 — gen2 §3.3 선례).
- 자기 검증: 등록 PR의 secret-scan은 트리 내 갱신 baseline으로 판정 —
  history leg가 NC-1 pull ref 지문을 재발견해도 등록 상태 → PASS.
- 착지: PR #9 MERGE 74e27ee2002e164a25e7d39bffe8c2f0b6d25e48 @04:33:19Z (merge queue 경유 native MERGE, 부모 2: 1a62ff9f+bb72521, merge-group 런 6종 필수 전부 SUCCESS, landing-integrity green — 정상 큐 1순위 착지, MUST-T2a 위임 기록은 본문 선반영되었으나 불개입)
- 착지 후 main = **E2 = 74e27ee2002e164a25e7d39bffe8c2f0b6d25e48**

### Phase 6d — E9 재판정·fresh gitleaks·ssot-drift

- ssot-drift (run 42949586921, E1 시점 dispatch): **GREEN** — leg1
  constant-mirror 2/2·leg2 ruleset 4/4 (main=26996019, required 6-context 일치)·
  leg3 producer 6/6 (app 15368). "policy SSOT·compiled-in constants·live
  platform agree" 판정.
- E9 재판정: 조건 1·2·5a·6·7 관측 완료(스냅샷 02:33:35Z–02:43:53Z), 조건 3은
  비적용(같은 커밋 그래프가 의도 — d753d923 tree 53723d45가 gen2 E9 인증
  tree와 객체 동일), 5b/5c·최종 refs는 E2 착지 후 재수집.
- fresh 재클론 gitleaks: E2 착지 후 신규 클론 + pull refs fetch →
  baseline 대조 신규 미등록 0건 확인. fresh clone /tmp/gen3-verify2 @E2 + pull refs fetch: history leg (origin/main + pull refs glob) 449건·미등록 0, tree leg (--no-git 상대경로) 448건·미등록 0 — 양 leg PASS (방법론 정정 기록: 초기 git-모드 오스캔은 스코프 외 ref 포함 아티팩트)
- E9 최종 판정: 조건 1·2·5a·6·7 (02:33Z-02:43Z 스냅샷) + 5b 9/9·5c pull-ref 교집합 0 (ls-remote 교집합 5는 승인 allowlist 태그의 동일-SHA 계승 — 설계)·5d 외부 URL 0·5e LFS 단독 해소 — 전 조건 관측 완료 (조건 3 비적용: 같은 그래프가 의도, d753d923 tree 53723d45가 gen2 E9 인증 tree와 객체 동일)

### Phase 6e — capsule 재봉인·최종 PR

- capsule dispatch: main(E2)에서 publication-integrity workflow_dispatch —
  **run 42960853729** (head 74e27ee2, 04:41:xxZ 디스패치 → 05:00:36Z completed,
  conclusion **success**, 종합 verdict **PASS**) — 6차원 잡 전부 green
  (secret-scan·license-scan·provenance·sbom·dependency-scan + shards). 핵심 관측:
  **secret-scan PASS on main dispatch** — history leg가 NC-1 pull ref 지문을
  재발견하나 등록 상태(baseline E2 반영) → 차단 없음. 봉인 전제 관측:
  `ls-remote origin main` == 74e27ee2 (05:0xZ 실측, seal precondition 성립).
- publication-readiness.json 갱신: binding.targetCommitSha=E2·gateRun.runId=신규·
  차원 리포트 sha256·requiredChecksOnTarget·ssotDriftMonitor=42949586921·
  negativeControlEvidence{PR #6/#7/#8, BLOCKED, 본 문서}.
- 최종 PR (capsule binding + E10 완결): 착지 = CAPSULE_MERGE_SHA.
- **최종 PR 자기 검증 (정직 기록 — gen2 48788d4·VS-I §2.2 선례 준용)**: 재봉인 커밋이
  capsule 라인 27의 sha256 값을 교체 → round-1 런(42964019203) secret-scan이
  history 지문 1건을 측정(예측 일치) → 같은 PR에서 `synthetic-hash-or-cas-key`로
  baseline 등록(commit 79e2f20) → round-2(42966288867) secret-scan PASS. round-1·2의
  license-scan은 본 문서 Phase 6b의 NC-2 인용 산문이 scancode 탐지 유발
  (gpl-3.0-only + json atom) → `license-attribution.yml`에 본 문서 documentary-mention
  엔트리 등록(VS-I §2.2 선례) → **round-3 PASS** (런 42968872950, 8/8 잡 green) → 최종 PR #10 착지.
- 종단 4조건 검증 (2026-11-11T06:33Z 기계 관측 확정 — **ALL TRUE**):
  ① `merge-base --is-ancestor d753d923 74e27ee2` → **TRUE** (04:34Z 실측) — 초기 계승 SHA 조상 관계
  ② capsule `binding.targetCommitSha` (74e27ee2) == 봉인 시점 `ls-remote origin main` (74e27ee2, 05:0xZ 실측) → **정합**
  ③ `CAPSULE_MERGE_SHA` = `adfbc8a7a9a654121f0b52c2965f87eb20c3f0a4` (PR #10 MERGE 2026-11-11T06:32:54Z) parent[0] == 74e27ee2 → **TRUE** (exclusiveLandingWindow — 개입 착지 부재 관측됨)
  ④ rotation(#4 `894defc7`)·E10(#5 `1a62ff9f`)·baseline(#9 `74e27ee2`)·capsule(#10 `adfbc8a7`) MERGE 전부 main 도달 → **TRUE × 4** — 착지 merge-group 9런 전부 SUCCESS (publication-integrity 42971106269 포함)

## Phase 7 — 구세대 폐기 (인간 수동 실행·에이전트 관측)

**권한 구조 (정직 기록 — 실행 주체 변경)**: 계획 v2는 에이전트의 API `DELETE /repos/Archright/Axiom-gen2` 집행을 상정했으나, 실행 주체가 인간 운영자로 변경됐다.

| 시점 | 관측 |
|---|---|
| 사전 관측 (05:3xZ) | 열린 PR 0 · 비종료 run 5종(queued/in_progress/requested/waiting/pending) 전부 0 · id 1448376585 · private · not archived — 삭제 전제(동결 유지) 성립 |
| 에이전트 DELETE 1차 시도 | `DELETE /repos/Archright/Axiom-gen2` → **HTTP 403** "Must have admin rights to Repository." — 원인: 운영자 토큰 `delete_repo` 스코프 부재(보유 스코프 admin:org·gist·read:packages·read:project·repo·workflow — org repo 관리자 role은 별도 정상 확인). 공식 문서상 repo 삭제는 admin 권한과 `delete_repo` 스코프를 모두 요구한다 |
| 스코프 획득 시도 | 디바이스 플로우 3회(코드 436B-8A20 — 15분 만료·478B-F0BF — 폴링 태스크 600초 타임아웃 폐기·6067-5E61 — 중단) 후, 사용자 지시 **"repo delete는 내가 수동으로 하겣다."**(2026-11-11)로 실행 주체 인간 전환·스코프 획득 폐기 |
| 인간 수동 실행 | wintrover 수동 삭제 — 감사로그 `actor=wintrover`로 확정(웹 경로) |
| 기계 관측 (07:12:14Z) | **이중 관측 성립**: ① 감사로그 `repo.destroy` — actor **wintrover** · created_at **2026-11-11T07:12:14.354Z** · operation_type **remove** · repo `Archright/Axiom-gen2` ② `GET /repos/Archright/Axiom-gen2` → **HTTP 404** (`{"message":"Not Found","status":"404"}`) — 20초 간격 404 폴링 2회차(07:12:14Z) 감지 + 직접 재확인. 삭제 시점은 폴링 1회차(~07:11:54Z, 존재)와 2회차(07:12:14Z, 404) 사이 — 감사로그 타임스탬프(07:12:14.354Z)와 정합 |

감사로그 부가 관측 — Axiom-gen2 라이프사이클 전체: `repo.rename` (Axiom → Axiom-gen2, 00:40:22Z — Phase 2 기록과 정합) → `repo.destroy` (07:12:14.354Z) → 삭제 직후 시스템 정리 이벤트 `repository_vulnerability_alerts.disable` (07:12:15Z, actor=null).

**판정**: 삭제 실행·정상 조회 불가의 관측 증거는 완결. **90일 복구창·GitHub 내부 물리 파기 범위는 여전히 UNKNOWN**(관측 불가 목록 1·2번 — 삭제 완료가 물리 소멸의 증명은 아니다). 로컬 대체 자산: 동결창 스냅샷 `gen2-full.bundle`(sha256 `c1742c20…`·21,947,736 B)·`pre-cutover-refs.txt`(80줄)·LFS 객체 — 90일 창 내 복구 필요 시 대응 기반(§gen2-full.bundle의 정의 한계 참조).

## 관측 불가 목록 (UNKNOWN — 정직 기록)

1. **90일 복구창은 복구 수단이지 물리 파기 증명이 아니다** — 삭제 후 90일 창은 운영 안전망(복구 가능 창)이며, `repo.destroy` 감사로그·GET 404는 삭제 실행·정상 조회 불가의 증거일 뿐이다(Phase 7 관측 완료 — 2026-11-11T07:12:14Z 이중 관측).
2. **GitHub 내부 객체·백업의 물리 파기 범위 = UNKNOWN** — 서버 내부 저장·백업에서 구세대 데이터가 언제·어디까지 물리 소멸하는지는 관측 표면 밖이다. 본 문서는 비노출 표면을 추정해 채우지 않는다(E8 §6·E9 "관측 불가" 선언과 동일 원칙).
3. (부가) **시크릿 실값** — 이전·판독 API 부재로 관측 불가. Phase 4 인간 전용 체크포인트로 처리(값 재입력 후에도 판독 불가 — 존재·이름만 관측 가능).

## MUST/POLICY 분리 — 공개 안전성과 신원 리셋 완결

- **MUST (공개 안전성)**: **Phase 2 리네임 시점(2026-11-11T00:40:23Z 관측)에 확보** — (i) 구 repo가 `Axiom-gen2`(id 1448376585, private)로 격리되어 `Archright/Axiom` 이름이 구세대 PR refs 보유 저장소에서 분리 (ii) 공개 표면이 될 gen-3 신규 repo는 태생부터 구세대 PR refs를 보유하지 않음. 공개 안전성은 **Axiom-gen2의 존폐와 무관**하다.
- **POLICY (신원 리셋 완결 — 사용자 목적)**: 구세대 서버측 참조 경로 자체의 제거. **Phase 7의 Axiom-gen2 삭제는 인간 수동 실행으로 완결**(2026-11-11T07:12:14Z·`repo.destroy` + GET 404 이중 관측) — 순서 준수 확인(신세대 production acceptance 06:33Z 완결 이후 — MUST-5).
- 실무적 의미: 삭제의 지연·보류는 공개 안전성(MUST)을 훼손하지 않는다 — 사용자 목적(신원 리셋 완결)은 Phase 7 관측으로 완결됐다.

## gen2-full.bundle의 정의 한계

- **정의**: 동결창 내 로컬에 확보한 **Git ref·객체 백업**(`git bundle create --all`) — ref 도달 커밋·tree·blob·태그 객체의 복원 수단. 판독: sha256 `c1742c20ac1d1907268e894e76de715825d2570c1bc51454c67f352a48eb3bcb` · **21,947,736 bytes**.
- **한계 (명시)**: **GitHub 서버의 PR·Actions 등 메타데이터 전체 백업이 아니다** — PR 본문·리뷰·issues·Actions runs·로그·artifact·시크릿 등 GitHub 호스팅 메타데이터는 어느 수단으로도 이관 불가(E8 disposition 행렬 — 대부분 NON_TRANSFERABLE·ARCHIVED). bundle은 Git 객체 영역의 보존을 보장할 뿐, 서버 메타데이터의 보존·복원을 주장하지 않는다.
- `pre-cutover-refs.txt`(80줄) 역시 동결창 시점 **Git ref 목록** 스냅샷이다 — PR 메타데이터가 아니라 ref 존재 목록.

## 완결 전 남은 관측 (PENDING 체크리스트)

**Phase 4 잔여 (적용 예정 readback) — 완료 (2026-11-11T01:07:59Z 관측 기준)**

- [x] 저장소 설정(병합·트래커) readback — 전 필드 일치
- [x] Actions 변수 2종 readback — total_count=2
- [x] 환경 3종 + 보호규칙 readback — 전부 일치 (+ 러너 그룹 3종·org ruleset 자동 커버 확인)
- [x] Actions 재활성 readback + 동결창 종료 시각 기록 — 2026-11-11T01:00:00Z
- [x] workflow 신규 ID 관측 — 29종(admission 5종 상기 표, v1.21.0 등록)
- [ ] 인간 전용: REARM App 5550340 재설치 + 시크릿 6종 재입력 (관측: 설치·시크릿 이름 존재) — **PENDING·인간 대기**

**Phase 5 — 신원 재결속 (rotation lane PR #4) — 완료 (2026-11-11T02:04:47Z 착지)**

- [x] rotation lane PR 번호·착지 관측 — **PR #4** MERGE `894defc7`(부모 2 · main 도달 · mergedBy wintrover) — PR 구성: `merge_admission.json` workflowIdObservation 5종 갱신 + `m7_canary_drill.sh` PROD_RULESET_ID + 본 E10 초안
- [x] A-2 핀 실행 관측 — **완결**: referenced_workflows 3종 sha `6104b249`(00:43Z 런) + PR-venue run 42938691258 잡 로그 `Uses:` 3종 SUCCESS + merge-group run 42941293354 26잡 전부 SUCCESS (메커니즘: org ruleset 25218071 required-workflow의 Axiom 컨텍스트 실행)
- [x] parse-probe 수동 디스패치 관측 — **관측됨: HTTP 422 차단**(공개 .github→비공개 Axiom cross-repo 파스 규칙·공식 문서 확정 — 재생성 이전과 동일 지속 조건, 회귀 아님) — 직접 디스패치 관측은 **공개 전환 시점으로 이연**, 운영 경로 실측은 A-2로 충족 (Phase 5 본문 참조)

**Phase 6 — production acceptance + 최종 검증**

- [x] **GEN3_FINAL_MAIN_SHA 확정** — 봉인 시점 E2 `74e27ee2`·최종 착지 `CAPSULE_MERGE_SHA = adfbc8a7` (parent[0]==74e27ee2 TRUE, 06:33Z 실측)
- [x] capsule 재봉인 — dispatch 42960853729 success·verdict PASS → PR #10 MERGE `adfbc8a7` @06:32:54Z (merge-group 9런 전부 SUCCESS) — Phase 6e 본문 기록 완결
- [x] 음성제어 NC-1/2/3 — PR #6/#7/#8 전부 publication-integrity **FAILURE·isRequired true·BLOCKED** 관측 후 미병합 close·브랜치 삭제 (Phase 6b 본문 — 3차원 fail-closed 실증, 교차오염·고립 관측 포함)
- [x] E9 7조건 재판정 (조건 3 비적용 — 같은 그래프 계승이 의도; 5b 9/9·5c pull-ref 교집합 0·5d 0건·5e LFS 단독 해소 — Phase 6d 본문)
- [x] fresh 재클론 gitleaks 0 — history 449건·tree 448건, 미등록 0 (양 leg PASS, /tmp/gen3-verify2 @E2)
- [x] admission-ssot-drift 전 leg GREEN — E1 시대 run 42949586921 + E2 시대 run 42960944991 모두 leg1 2/2·leg2 4/4·leg3 6/6 (Phase 6d 본문)

**Phase 7 — 구세대 폐기 (인간 수동 실행·에이전트 관측) — 완료 (2026-11-11T07:12:14Z 관측)**

- [x] Axiom-gen2 삭제 — **인간 수동 실행·기계 관측 완료**: 감사로그 `repo.destroy` (actor wintrover·2026-11-11T07:12:14.354Z·operation_type remove) + `GET /repos/Archright/Axiom-gen2` **404** (폴링 07:12:14Z 감지·직접 확인) — 실행 주체 인간 전환 경위(DELETE 403·디바이스 플로우 3회 → 사용자 수동 집행 지시) 포함 정직 기록 (Phase 7 본문)

---

## GEN3_RECREATION_STATUS (완결)

```text
repo (gen-3, 현행):     Archright/Axiom — id 1453354095 (private · Actions 재활성 01:00:00Z · allowed_actions=all)
repo (gen-2, 폐기):     Archright/Axiom-gen2 — id 1448376585 — 삭제됨 (2026-11-11T07:12:14Z · repo.destroy+404 이중 관측 · 로컬 bundle 스냅샷 존재)
동결창:                 2026-11-11T00:39:09Z 개시 (종료 = Actions 재활성 01:00:00Z)

observed (Phase 1–7):
  Phase 1 동결창        6종 조건 + 불변식(1932==1932) + 이중 신호 + TOCTOU 재관측 전부 PASS
                        스냅샷 gen2-full.bundle (sha256 c1742c20…, 21,947,736 B) 확보
  Phase 2 리네임        Axiom → Axiom-gen2 (00:40:23Z) · id 불변 · 공개 안전성 MUST 확보
  Phase 3 부트스트랩    main d753d923 · 레저 2 (84f30200/555c9c99) · 태그 5 · LFS 100% (1/1)
                        · org ruleset 원복 diff 1필드 (00:42:50Z) · refs/pull/* 0건
  Phase 4 control       repo 4종 active (26996019/26996020/26996021/26996023, 00:44:09Z readback)
                        · 병합설정·변수 2·환경 3(+branch policy main)·러너그룹 3 readback 일치
                        · Actions 재활성 01:00:00Z · workflow 29종 ID 관측 (01:01:50Z)
                        · 핀 9개 소재 = org Archright/.github @1eed0a48 (A-1.6 실측 정정)
                        · A-2 절반: 00:43Z 런 referenced_workflows 3종 = sha 6104b249
  Phase 5 rotation      PR #4 MERGE 894defc7 (02:04:47Z) · merge queue 경유 native MERGE (부모 2)
                        · merge-group 9런 전부 SUCCESS · d753d923 조상 관계 유지 · mergedBy wintrover
                        · A-2 완결: referenced_workflows 3종 sha + PR-venue 잡 3종 SUCCESS
                          (Uses: @6104b249) + merge-group 26잡 SUCCESS — 메커니즘 = org ruleset
                          25218071 required-workflow의 Axiom 컨텍스트 실행 (callee 핀 same-repo 해결)
                        · parse-probe 직접 디스패치 422 차단 관측 (public→private 파스 규칙·공식
                          문서 확정·재생성 전과 동일 지속 조건) → 공개 전환 시점 이연

  Phase 6 production   NC-1/2/3 (PR #6/#7/#8) 전부 FAILURE·isRequired·BLOCKED 실증 후 미병합
                        close · baseline 등록 PR #9 MERGE 74e27ee2 = E2 (04:33:19Z, 정상 큐
                        merge-group 6/6 required SUCCESS·자기검증 통과)
                        · E9 재판정 5b 9/9·5c pull-ref 0·5d 0·5e LFS 단독 (조건 3 비적용)
                        · fresh gitleaks 양 leg 미등록 0 (history 449·tree 448)
                        · ssot-drift E1+E2 디스패치 모두 legs GREEN (26996019·producer 6/6)
                        · capsule dispatch 42960853729 success·verdict PASS →
                          publication-readiness.json 재봉인 (binding=E2·차원 sha256·
                          requiredChecksOnTarget·NC #6/7/8) — seal precondition 실측 정합
                        · 최종 PR #10 MERGE adfbc8a7 (CAPSULE_MERGE_SHA) 06:32:54Z ·
                          merge-group 9런 SUCCESS · 종단 4조건 ALL TRUE (06:33Z 실측)
  Phase 7 retirement   인간 수동 실행(wintrover)·에이전트 관측 — repo.destroy 감사로그
                        (07:12:14.354Z·operation_type remove·actor wintrover) + GET 404
                        이중 관측 · DELETE 403(스코프 부재)→디바이스 플로우 3회→사용자
                        수동 집행 지시 경위 정직 기록 · 90일 창·내부 물리 파기 UNKNOWN

pending (컷오버 종결 후 남은 항목 — 인간 전용·본 계약 범위 밖):
  인간 전용             REARM App 5550340 재설치 · 시크릿 6종 재입력 (§2.4 — 값 이전 API 부재)
  공개 전환 시점         parse-probe 직접 디스패치 관측 (public→public 해석 가능 후)

GEN3_BOOTSTRAP_SHA:     d753d92356cbb1d7e0195b57ac9f6245a2951dba (관측 확정)
GEN3_FINAL_MAIN_SHA:    74e27ee2002e164a25e7d39bffe8c2f0b6d25e48 (capsule 재봉인 시점 실측)
CAPSULE_MERGE_SHA:      adfbc8a7a9a654121f0b52c2965f87eb20c3f0a4 (PR #10 MERGE 06:32:54Z ·
                        parent[0]=74e27ee2 TRUE · 종단 4조건 ALL TRUE 06:33Z 실측)

STATUS:                 GEN3_RECREATION_COMPLETE
                        Phase 1–7 전부 기계 관측 확정 — 동결창·리네임·부트스트랩·통치 평면
                        재구성·rotation(894defc7)·production acceptance(NC 3차원 fail-closed·
                        E2 74e27ee2 봉인·CAPSULE_MERGE adfbc8a7 착지·종단 4조건 ALL TRUE
                        06:33Z)·구세대 폐기(repo.destroy+404 07:12:14Z·인간 수동 실행).
                        남은 항목은 인간 전용(§2.4)·공개 전환 시점 이연 관측뿐 — 컷오버 종결.
```
