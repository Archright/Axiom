# GPA Phase 0 조사 최종 보고서 — 기준선 · 유일성 · 권한

| 항목 | 값 |
|---|---|
| **관측 시각 (UTC)** | **2026-10-21T18:42:35Z** (KST 2026-10-22 03:42:35 +09:00) |
| 대상 저장소 | `Archright/Axiom` (private, repo id **1182104685**) |
| 기준 트리 | `origin/main` = **e75f005c73b1aa54a179345f12b4f5e95013a1b1** |
| 로컬 상태 | `test/v5-acceptance-c` (HEAD `50a46da2ba70…`), **working tree dirty 파일 0건** |
| 임무 성격 | **읽기 전용 관측 전용** — 저장소 파일 미변경, 브랜치/워크트리 미생성, 출력은 `/tmp/gpa_phase0/` 하위만 |
| 산출물 | `baseline.json` · `uniqueness.md` · `authorities.md` · `report.md` (본 문서) + 원본 증거 파일 |

---

## 1. Phase 0 산출물 요약

| 파일 | 내용 |
|---|---|
| `/tmp/gpa_phase0/baseline.json` | 기준선 스냅샷 전체 (repo/org SHA, ruleset 6+2건, pin 3중 정합성, workflow 24건, 최근 run 5×5건) |
| `/tmp/gpa_phase0/uniqueness.md` | "generation-acceptance" check-context 유일성 사전 검증 (§6.1) |
| `/tmp/gpa_phase0/authorities.md` | bypass integration 신원, org ruleset 가독성 증거, 권한 매트릭스 |
| `/tmp/gpa_phase0/report.md` | 본 문서 (요약 + operator-adapter 필요 목록) |
| `/tmp/gpa_phase0/drift_run_39622835490.log` | admission-ssot-drift run 원본 로그 (leg 2 증거 원문) |
| `/tmp/gpa_phase0/*.json` (보조) | API raw dump (`repo_ruleset_20303214.json`, `org_ruleset_*.json`, `push_ruleset_*.json`, `checkruns_main10.json`, `org_installations.json`, `workflows_list.json`, `runs_*.json`, `epoch_manifest_origin_main.json`, `trusted_writer_set_origin_main.json`, `merge_admission_policy_origin_main.json`) |

---

## 2. 기준선 요약 (baseline.json 핵심)

### 2.1 저장소·조직

| 항목 | 값 |
|---|---|
| Axiom default branch | `main` (private, repo id 1182104685) |
| `origin/main` SHA | `e75f005c73b1aa54a179345f12b4f5e95013a1b1` |
| **open PR 수** | **0** |
| `Archright/.github` repo id | **1182157951** (org ruleset의 `repository_id`와 동일) |
| `Archright/.github` main SHA | **7fffee318b9fada32d13dd9c88d74869e343f9cc** ("Merge PR #247 from Archright/ci/pin-admission-check-v51", 2026-10-21T16:21:43Z) |

### 2.2 repo ruleset 20303214 ("main")

- `target=branch`, `conditions.ref_name.include=["~DEFAULT_BRANCH"]`, `enforcement=active`, **`bypass_actors=[]`**, `current_user_can_bypass="never"`.
- **required_status_checks 3종** (모두 `integration_id=15368`): `admission-check` / `bsec-integrity` / `debt-registry-gate`.
  - `strict_required_status_checks_policy=false`, `do_not_enforce_on_create=false`.
- `pull_request` rule: `required_approving_review_count=0`, `allowed_merge_methods=["merge"]`, `require_extra_approval_for_unattributed_changes=true`, 그 외 review 규칙은 전부 비활성.
- `merge_queue`: `merge_method=MERGE`, `grouping_strategy=ALLGREEN`, `check_response_timeout_minutes=120`, `max_entries_to_build=2`, `min/max_entries_to_merge=1`.

### 2.3 org rulesets 2건 (양쪽 모두 `bypass_actors=[]`, `repository_name.include=["Axiom"]`, `ref_name.include=["refs/heads/main"]`)

| id | name | workflow path | repository_id | sha |
|---|---|---|---|---|
| 25218071 | axiom-admission-gate | `.github/workflows/admission-gate-v2.yml` | 1182157951 (= **Archright/.github**) | `7fffee318…` |
| 23943917 | landing-integrity | `.github/workflows/landing-integrity.yml` | 1182157951 (= **Archright/.github**) | `7fffee318…` |

- `sha`는 **커밋 SHA**로 확인(blob hash 아님): 해당 커밋에서 `admission-gate-v2.yml` blob=`b4444b00…`, `landing-integrity.yml` blob=`c998cfac…` 실재 확인.
- ⚠️ 해석 주의: **핀은 커밋 고정**이므로 `.github` main이 전진해도 pin은 유효. "org ruleset pin sha ≠ .github main sha"는 **drift가 아니다** — GPA 모니터가 이 조건을 drift로 오판하지 않도록 명시 필요.

### 2.4 push rulesets

| id | name | target | 내용 | bypass_actors |
|---|---|---|---|---|
| 23967915 | execution-surface-create | push | `file_path_restriction` restricted=`.github/workflows/**/*`, `.github/actions/**/*` / ignored=[] | `OrganizationAdmin:always`, `Integration 29110:always`, `Integration 4879411:always` (`current_user_can_bypass=always`) |
| 23916707 | cas-probe-scratch | branch (`refs/heads/cas-probe/*`) | update / deletion / non_fast_forward | `Integration 4879411:always` (`current_user_can_bypass=never`) |
| 23969951 | artifact-hygiene | push | (요약에만 존재 — 지시서 범위 밖) | — |

`conditions=null`인 23967915는 **모든 ref에 적용**된다.

### 2.5 pin 3중 정합성 — **PASS**

| 값 | 소스 | SHA |
|---|---|---|
| `productionExecutionPin` | `git show origin/main:config/policy/epoch_manifest.json` | `83260f72a8e47645f30618fc426bc1fd7561587f` |
| `trustedAdmissionWorkflowSha` | `git show origin/main:config/trusted_writer_set.json` | `83260f72a8e47645f30618fc426bc1fd7561587f` |
| admission-check.yml blob | `git rev-parse origin/main:.github/workflows/admission-check.yml` (object type `blob`, ls-tree `100644 blob`) | `83260f72a8e47645f30618fc426bc1fd7561587f` |

**→ 전부 일치 (CONSISTENT).**

### 2.6 정책 v1.15.0 (`config/policy/merge_admission.json`)

- `requiredValidations`: `bsec-integrity`(workflowId 381835906), `debt-registry-gate`(workflowId 389486255)
- `requiredWorkflowDetection`: `repositoryId=1182157951`(=.github), `workflowPath=.github/workflows/admission-gate-v2.yml`, `verdictJob=admission-check`
- `trustSurface`: 15개 경로 (`.github/workflows/**` 4 + `.github/actions/setup-axiom-toolchain/**` + `config/` 4 + `src/` 4 + `experiments/…/replay.sh`)
- ⚠️ `trustSurface`에 **`.github/workflows/admission-ssot-drift.yml`, `closure-watcher.yml`, `merge-queue-rearm.yml`은 없다**. GPA가 첫 승격 대상으로 삼는 drift/closure 경로는 현재 trust surface 밖 → **Phase 1에서 policy v1.16.0에 반영 여부를 결정해야 한다**(GPA 자체가 trust surface에 들어가야 자기 yaml 파손이 막힘).

### 2.7 최근 5 run × 5 workflow

| workflow | id | 최근 5 run (conclusion / event / created) |
|---|---|---|
| admission-ssot-drift | 391703936 | success/39622835490/wd 15:07Z · failure/39610756667/wd 13:45Z · failure/39604571246/wd 13:02Z · failure/39603184495/wd 12:52Z — **총 4 run, 전부 workflow_dispatch, schedule 0건** |
| closure-watcher | 380058433 | success ×5 (전부 `schedule`, 10-21T17:11Z ~ 10-20T17:02Z), 총 48 run, **신규부터 연속 15회 success** |
| merge-queue-rearm | 383466559 | success ×5 (전부 `pull_request_target`), 총 267 run |
| bsec-integrity | 381835906 | success ×5 (merge_group 3 + pull_request 2), 총 762 run |
| debt-registry-gate | 389486255 | success ×5 (merge_group 3 + pull_request 2), 총 192 run |

**drift cron 0건의 설명 (중요)**: `.github/workflows/admission-ssot-drift.yml`은 `schedule: cron '37 4 * * *'`(매일 04:37 UTC)를 **선언**하지만, 워크플로 파일이 main에 **추가된 시점**이 `f77fea55… @ 2026-10-21T12:05:37Z`로 **그날 04:37Z 슬롯보다 늦다**. → 첫 발화 가능 시점은 **2026-10-22T04:37Z**(관측 시점 기준 ~10h 뒤). **즉 0건은 "cron 누락/드랍"이 아니라 "아직 발화할 시간이 오지 않음"**이다. (계획 UNKNOWN#2는 여전히 미해결 — 첫 발화는 미관측.)

---

## 3. 유일성 판정 (§6.1) — **"generation-acceptance" 이름 충돌: 없음**

> 근거: ① 최근 main 10커밋의 check-runs에서 수집된 **distinct check name 40개 어디에도 `generation-acceptance` 없음**(부분문자열 `generation`/`acceptance` 포함 명칭도 **0건**). ② `origin/main` 전체 트리 및 **origin의 모든 remote ref** 전수 grep에서 문자열 **0건**. ③ `dynamic/dependabot/*` 2건은 저장소-resident 파일이 아니므로(트리 0개, `event=dynamic`, `actor=dependabot[bot]`) 동명 producer가 될 수 없음. ④ open PR 0건.

**단 — "유일 producer" 선언이 아니다.** 잔여: ① 같은 GitHub Actions App(15368) 내부의 **same-name 스푸프**(플랫폼은 이름만 보고 required check 충족 처리 — 저장소 `docs/evidence/merge_freeze_spoof_probe_2026-10-12.md`가 실측 기록) ② `dynamic/`가 향후 저장소-resident해질 경우 push rule 사각.

**`dynamic/dependabot/*` 실체 (관측된 것)**
| workflow id | name | API path | state | runs | 트리 존재 | 발화 |
|---|---|---|---|---|---|---|
| 362065556 | Dependency Graph | `dynamic/dependabot/update-graph` | active | 2 | **없음** | `event=dynamic`, `actor=dependabot[bot]` |
| 366563934 | Dependabot Updates | `dynamic/dependabot/dependabot-updates` | active | 99 | **없음** | `event=dynamic`, `actor=dependabot[bot]` |

- `file_path_restriction` 경로(`.github/workflows/**/*`, `.github/actions/**/*`)에 **`dynamic/dependabot/**`는 포함되지 않음** → 그러나 **우회 벡터가 아님**(push 불가능한 경로). 위험은 "향후 resident화"의 잠재축이다.
- 저장소 `.github/dependabot.yml`은 `github-actions` 에코시스템 **주간** 업데이트만 선언(관측).

---

## 4. 권한·신원 실측 (authorities.md 요약)

### 4.1 bypass integration

| actor_id | 판정 | 근거 |
|---|---|---|
| **4879411** | **확정: `axiom-ci-elastic`** (installation_id `160192931`, `repository_selection=all`, `contents:write`+`organization_self_hosted_runners:write`) | `GET /orgs/Archright/installations` 실측 + `config/app_landing_binding.json`·`docs/spec/merge_authority_integrity.md:128` 일치 |
| **29110** | **UNREADABLE — 미확정** | 11개 경로 전 실패(org installations `total_count=2`에 부재 / `/apps/29110` 404 / `/app?app_id=` 401 / `/users/wintrover/installations` 404 / `/user/installations` 403 / `/repos/…/installation` 401 / `/orgs/Archright/installations/29110` 404 / `/installations/29110` 404 / installation 단일·repositories 404). **대조 실험상 `/apps/{id}`는 15368(공개)조차 404 → 판별력 없음.** Axiom 최근 40커밋 check-suite app id는 15368 단일(694건) → 29110은 이 repo에서 check 생산 이력 없음. 문서 2곳(ADR-0027:35, merge_freeze_spoof_probe:46)에도 ID만 있고 신원 미기재 |

### 4.2 org ruleset 가독성

- **repo ruleset 20303214 → job GITHUB_TOKEN으로 실측 PASS** (run 39622835490, `credential-source=GH_TOKEN`, `live Archright/Axiom ruleset 20303214`, `ruleset drift: 4/4 expectations hold`, producer 3/3, 최종 `admission-ssot-drift: OK`). `--allow-unavailable-ruleset`가 켜진 상태에서 `NOT PERFORMED`가 0건 → **조용한 생략이 아니라 실제 읽기 성공**이 증명됨.
- **org ruleset 25218071/23943917 → 직접 실측 없음.** 로그에 org ruleset 조회 시도 자체가 **0건**(monitor가 repo ruleset만 조회). 근거는 (a) 플랫폼 문서의 Administration org write 요구, (b) 저장소의 **의도된 배제 설계**(워크플로 주석: "tier 2: Administration:read credential가 없다"), (c) 저장소 코드 어디에도 org ruleset job-token 조회 경로 없음(`git grep` 결과 전부 문서/예시) — **모두 간접 증거**.
- → **T1(직접) 티어 실증: repo ruleset + epoch/TWS/blob 정합성 + 정책 파일. T2(operator-adapter): org rulesets·pin·bypass_actors·push ruleset. UNKNOWN: 29110 신원.**

---

## 5. UNREADABLE / UNKNOWN 목록 (정확)

| # | 항목 | 분류 | 사유 | 해소 경로 |
|---|---|---|---|---|
| U-1 | **bypass integration 29110의 신원** | **UNREADABLE** | §4.1의 11경로 전 실패. App 설치 목록 전수 조회는 App JWT 필요(§2.4 자격증명 권한상 시크릿 발급·복제 금지). `/apps/{id}` 404는 판별력 없음 | **인간 operator가 org Settings → GitHub Apps 화면에서 actor_id 29110 확인** (A-1) |
| U-2 | **job token의 org ruleset 읽기 불가** | **직접 실측 부재** | repo workflow가 시도하지 않음(설계상 배제). 간접 증거만 존재 | operator(admin PAT)로 readback 수행 후 **operator-adapter provenance**로 manifest에 기록 (A-2) |
| U-3 | org ruleset의 `bypass_actors` 전체 | **UNKNOWN** | 플랫폼 규칙상 write 접근자에게만 반환(현재 admin 토큰은 반환). **job token 경로는 존재하지 않음** | operator-adapter (A-2) |
| U-4 | **drift cron(`37 4 * * *`) 첫 발화** | **UNKNOWN(미관측)** | 워크플로가 2026-10-21T12:05Z에 main 추가 → 첫 슬롯 2026-10-22T04:37Z가 아직 오지 않음 | 발화 후 run 관측. **"cron 누락 자동 감지" 주장 금지 상태 유지** (계획 §6.3) |
| U-5 | queue와 push rule의 상호작용 역학 | **UNKNOWN** | 관측은 통과(#1019)까지. 역학(왜 통과했는지)은 미확인 | 첫 GPA 승격(Phase 3) 시 manifest에 관측 기록 |
| U-6 | `dynamic/dependabot/*` 생성 메커니즘의 공식 규격 | **UNREADABLE** | GitHub 내부 구현 — API로 규격 관측 불가. 관측된 사실(event=dynamic, actor=dependabot[bot], 트리 부재)만 확보 | **UNREADABLE로 유지** — GitHub 공식 문서 참조로만 보강 |
| U-7 | `axiom-release-authority`(5082347)의 repo 선택 목록 | UNREADABLE(부분) | `/orgs/…/installations/{id}/repositories` 404 | Axiom 포함 여부만 필요 → Axiom repo ruleset 적용 실측으로 간접 확인 가능 |
| U-8 | 29110의 Axiom 적용 여부 | **UNKNOWN** | org installation 목록에 없어 적용 여부도 확인 불가 | U-1 해결과 동일 (A-1) |

**Phase 0에서 UNREADABLE로 남긴 것의 요약**: 요청된 baseline 항목은 **전부 읽기 성공**했다. UNREADABLE은 위 8건이며, 그중 **GPA 구현에 직접 영향을 주는 것은 U-1(29110)** 하나이고, 나머지는 "operator-adapter로 채우거나 UNKNOWN으로 기록"하면 되는 항목이다.

---

## 6. operator-adapter 증거 필요 목록 (GPA Phase 1 착지 전 확보 권고)

> 본 목록은 **Phase 0 조사자가 실행할 수 없는 단계**(AGENTS.md §2.4 자격증명 권한: 외부 자격증명은 네이티브 클라이언트로만, 파일시스템·환경변수·키링 경로 스캔·복제 금지) 또는 **구조적으로 job token 범위 밖**인 항목이다.

| # | 필요한 증거 | 제공 주체 | 소비 형태 | 우선도 |
|---|---|---|---|---|
| **A-1** | bypass actor **29110**의 App slug·설치 대상·권한(그리고 현재 Axiom 적용 여부) | **인간 operator** (org Settings → GitHub Apps) | ADR-0036 + manifest `operator-promotion-adapter` provenance | **높음** — 잔여 위험 R-2 |
| **A-2** | org ruleset **25218071 / 23943917** 전체 readback (workflows rule의 `path`/`repository_id`/`sha`, `bypass_actors` 전체, `enforcement`) | **operator-adapter** (org-admin PAT) | manifest의 operator-adapter 필드. GPA는 **소비만** | **높음** — U-2/U-3 |
| **A-3** | push ruleset **23967915 / 23916707 / 23969951**의 승격 직전 readback(스냅샷 바이트) | operator-adapter | Phase 2 "주입 전후 live ruleset·pin readback 바이트 불변" 증빙 | 중간 |
| **A-4** | `axiom-ci-elastic`(4879411)의 **현재 권한** 확인(`contents:write` 유지가 필요한지, `organization_self_hosted_runners:write`이 남는지) | operator | R-1 잔여 위험 정량화 | 중간 |
| **A-5** | `dynamic/dependabot/*`가 **저장소-resident하게 될 경우**의 push rule 사각 → 정책상 `dynamic/**`를 execution-surface로 유지할지 결정 | **인간 아키텍트**(정책 결정) | ADR-0036 §위험 | 낮음 |
| **A-6** | drift cron 첫 발화(run id·created_at) | 자동(관측) | U-4 폐기 | 낮음(시간) |

---

## 7. GPA 관점의 주목 사항

1. **"직접 조회 가능" 티어의 경계가 실측으로 확정되었다.** repo ruleset은 job token으로 읽힌다(4/4 PASS, `NOT PERFORMED` 0건). org ruleset은 **읽히지 않는다는 사실이 아니라, 읽으려 시도조차 하지 않는다**는 것이 현재 상태다. → GPA가 org ruleset을 읽으려 시도하면 실패할 것이 아니라 **시도하지 말아야 한다**(권한 상승 시도 자체가 §2.5 "GPA workflow 전체에 조직 관리 권한 부여 금지" 위반).

2. **rule 20303214의 bypass_actors가 비어 있다는 사실은 "우회 불가능"이 아니라 "이 ruleset은 push-rule 우회와 무관한 방어선"이다.** `.github/workflows/**` 변경 통제는 23967915가 담당하고, 그 ruleset에는 `OrganizationAdmin` + `Integration 29110`(미확정) + `Integration 4879411`(확정) 우회가 있다. **즉 두 ruleset의 우회 표면은 별개**이며, repo ruleset의 `current_user_can_bypass=never`를 "전체 시스템 우회 불가"로 읽으면 안 된다.

3. **4879411(`axiom-ci-elastic`)은 "CI 권한 그 자체"다.** `contents:write` + `organization_self_hosted_runners:write` + push rule 완전 우회. GPA는 이 권력을 **약화**하지 못한다. GPA가 얻는 것은 (a) 우회 실행의 **감지 창을 좁히고** (b) 우회 시도가 **PREVENT되는 병합 경로**를 만드는 것. → Phase 1의 "4번째 required check 등록"이 무엇을 실제로 막는지, 그리고 무엇을 **못 막는지**를 ADR-0036에 정확히 적어야 한다(극장 방지 §0.9).

4. **`integration_id` 결속의 실측 위치.** repo ruleset의 required 3-check는 **전부 `integration_id=15368`**로 결속되어 있고, drift monitor가 job token으로 그 사실을 재확인했다(producer 3/3). GPA를 `generation-acceptance` + `integration_id=15368`로 등록하면 **다른 App의 동명 check는 매칭되지 않는다** → P0#2의 3-레이어 중 **1-레이어(integration_id)가 실측 근거로 성립**한다. 반대로 **같은 App(15368) 내부의 스푸프는 막히지 않는다**(플랫폼 한계, 저장소 실측 기록 있음) → 이 부분은 ADR의 명시적 위험 수용 대상으로 남는다.

5. **trust surface 갭.** `config/policy/merge_admission.json` v1.15.0의 `trustSurface` 15개 항목에 GPA가 승격 대상 삼는 `admission-ssot-drift.yml`(Phase 3)과 `closure-watcher.yml`(Phase 4)이 **없다**. → Phase 1의 policy v1.16.0에서 **GPA 자신(generation-acceptance.yml)과 drift/watchdog 경로를 trust surface에 포함**하는지 여부를 먼저 결정해야 한다. 포함하지 않으면 "GPA 자기 파손" 시나리오의 push rule 차단은 `.github/workflows/**` file_path_restriction에만 의존하게 된다.

6. **`dynamic/`은 "push rule 밖 + 저장소 밖"의 교차점이다.** `file_path_restriction`이 `.github/workflows/**`·`.github/actions/**`만 보호하고 `dynamic/**`는 보호하지 않으나, 현재 `dynamic/`은 저장소에 존재하지 않는다(0개). GPA의 execution-surface 정의가 `dynamic/**`를 포함하는 것은 **올바르나**, push rule이 못 막는 영역이라는 점을 **ADR에 명시**해야 "3-레이어 방어"가 사실과 어긋나지 않는다.

7. **"유일 producer"를 아직 선언할 수 없다.** 이름 충돌 없음은 확정했다. 그러나 동일 App 내부 스푸프가 **실측으로 존재**함을 저장소가 이미 기록하고 있다(`merge_freeze_spoof_probe_2026-10-12.md` — `spoof-probe-a81de2`가 required check로 통과). 따라서 Phase 1의 등록 순서는 **uniqueness 통과 → ruleset PUT → readback** 순서를 지키되, ADR에는 "이름 유일 ≠ producer 유일"을 명시해야 한다. **추가로**: 워크플로 API 레지스트리에는 `origin/main` 트리에 파일이 없는 항목이 **4건**(spoof-probe-a/b는 `active` 잔존, pr-verification·scaleset-canary는 `disabled_manually`) 남아 있다 → "workflow API에 없음"은 등록 부재의 증명이 아니므로, GPA 파일 추가 시 **얻어지는 workflow id가 신규인지 이미 점유됐는지**를 ruleset PUT 전 readback으로 반드시 확인할 것.

8. **drift cron은 아직 한 번도 발화한 적이 없다.** cron 0건은 "설정 오류"가 아니라 "main 추가가 첫 슬롯보다 늦었기"의 자연스러운 결과다. 그러나 **관측 시각 기준 첫 발화는 아직 오지 않았다** → §6.3의 "cron 누락 자동 감지 보장" 주장은 **여전히 금지 상태**이며, closure-watcher watchdog(Phase 4)이 착지되기 전까지는 수동 점검 + UNKNOWN 표기만 가능.

9. **모든 측정은 하나의 관측 시점에 묶였다.** baseline / uniqueness / authorities의 모든 값은 **2026-10-21T18:42:35Z** 상태로 읽혔다. Phase 1 착지(PR 머지 → ruleset PUT) 시점에는 **반드시 readback을 다시 찍어** baseline과 diff를 남길 것 — 특히 25218071/23943917의 `updated_at`은 이미 관측 직전(2026-10-22T01:21:47/49 +09:00 = 2026-10-21T16:21Z)에 갱신된 상태였다(**ruleset이 아직 움직이고 있음**).

---

## 8. 재현 명령 (읽기 전용)

```bash
# 기준선
gh api /repos/Archright/Axiom --jq '{default_branch,private,pushed_at}'
gh api "/repos/Archright/Axiom/pulls?state=open&per_page=100" --jq 'length'
gh api /repos/Archright/.github/commits/main --jq '.sha'
gh api /repos/Archright/Axiom/rulesets/20303214
gh api /orgs/Archright/rulesets/25218071
gh api /orgs/Archright/rulesets/23943917
gh api /repos/Archright/Axiom/rulesets/23967915
gh api /repos/Archright/Axiom/rulesets/23916707

# pin 3중 정합성
git show origin/main:config/policy/epoch_manifest.json          # productionExecutionPin
git show origin/main:config/trusted_writer_set.json             # trustedAdmissionWorkflowSha
git rev-parse origin/main:.github/workflows/admission-check.yml # blob sha

# 유일성
gh api "/repos/Archright/Axiom/commits?sha=main&per_page=10"
gh api /repos/Archright/Axiom/commits/<sha>/check-runs --jq '.check_runs[].name'
git grep -n "generation-acceptance" origin/main -- .
git ls-tree -r --name-only origin/main -- dynamic/              # → 0개

# 권한
gh api "/orgs/Archright/installations?per_page=100"             # app_id 4879411 = axiom-ci-elastic
gh run view 39622835490 -R Archright/Axiom --log                # leg 2 = ruleset 20303214 4/4 PASS
```

---

## 9. Phase 0 판정

- **기준선 확보**: ✅ 완료 (요청 항목 전량 실측, UNREADABLE 0건)
- **유일성 사전 검증 (§6.1)**: ✅ 통과 — **이름 충돌 없음**. 단, "유일 producer" 선언은 **보류**(잔여 위험 §7.7)
- **integration 신원**: 4879411 ✅ 확정(`axiom-ci-elastic`) / 29110 ❌ **미확정 — operator 확인 필요(A-1)**
- **org ruleset 가독성**: repo ruleset ✅ 실측 가능 / org ruleset ⚠️ **직접 실측 없음 → operator-adapter(A-2)**
- **다음 액션 (Phase 1 착지 전)**: A-1·A-2 확보, policy v1.16.0의 trust surface에 GPA·drift·watchdog 포함 여부 결정, uniqueness 재점검(착지 시점 check name 1회 추가 수집)
