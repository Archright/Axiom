# M7 진단 App 활성화 런북 (휴먼 게이트 — 2026-10-12)

**Status**: Runbook — 집행 주체는 **인간**이다. GitHub은 App 생성 API를 제공하지 않으므로
에이전트는 이 절차를 수행할 수 없고, 수행해서도 안 된다(credential 발견·생성 금지 —
AGENTS §2.4). 본 문서는 `docs/spec/diagnostic_execution_delegation.md` §2 등록 스펙의
실행 절차판이다.
**실행체**: `.github/workflows/diagnostic-authority.yml` (PR #775 착지, 905e53e9d)
**선행**: PR #779 (c01a8316e) — bsec-integrity merge_group `base_sha` 필드 정정(아래 §6 실측)

---

## 0. 등록 전 현재 상태 — fail-closed 실측 (2026-10-12)

- 진단 App **미등록**. 환경 레코드 `diagnostic-authority`는 첫 dispatch가 자동 생성했다
  (생성 2026-10-12T07:53:37Z) — **protection_rules 0건(무보호)**, 시크릿 없음.
  따라서 §1.3의 인간 작업은 "환경 생성"이 아니라 **"기존 레코드에 보호규칙·시크릿 추가"**다.
- 등록 전 워크플로 실행은 게이트 스텝에서 실패하는 것이 **정상**이다. 실측 run
  **38220304031** (main @ 4b7efdcdf, workflow_dispatch):
  - `[gate] Fail closed when diagnostic App secrets are absent (human registration gate)`
    → failure, `##[error]diagnostic-authority: DIAG_APP_ID / DIAG_APP_PRIVATE_KEY absent
    from environment 'diagnostic-authority' — the diagnostic App is not registered yet
    (human gate, docs/spec/diagnostic_execution_delegation.md §2). Failing closed: no
    diagnostic credential, no delegated execution.`
  - 이후 전 스텝 **skipped**(checkout·민팅·진단·canary 미실행) — 조용한 폴백 경로 0.
- 로컬 no-fallback 가드 실측(같은 날, `AXIOM_DIAG_TOKEN` 미설정):
  - `AXIOM_DIAG_STRICT=1 bash tools/ci/landing_observe.sh 775` →
    `landing_observe: FAIL — AXIOM_DIAG_TOKEN absent and AXIOM_DIAG_STRICT=1: gh-auth
    credentials (operator PAT) are refused for diagnostic execution (M7 no-fallback —
    docs/spec/diagnostic_execution_delegation.md §4)` + `VERDICT: UNKNOWN` + **exit 2**.
  - `bash tools/ci/m7_canary_drill.sh --canary-pr 999 --repo Archright/Axiom`(실모드) →
    `m7_canary_drill: FAIL — AXIOM_DIAG_TOKEN absent. The canary is only meaningful with
    the credential under test; gh auth / GITHUB_TOKEN fallbacks are structurally absent`
    + **exit 2**.

## 1. 휴먼 절차 (순서 고정)

### 1.1 진단 GitHub App 생성

- 위치: `https://github.com/organizations/Archright/settings/apps/new` (조직 소유 GitHub App)
- **이름**: `axiom-diagnostic-authority`
- **Webhook**: Active 해제(비활성)
- **Repository permissions — 상한 그 자체. 이 5개 read-only만 설정한다**:

  | 권한 | 값 |
  |---|---|
  | Contents | **Read-only** |
  | Metadata | **Read-only** |
  | Merge queues | **Read-only** |
  | Pull requests | **Read-only** |
  | Checks | **Read-only** |

- **명시적 부정**: 위 5개 외 전부 No access — 모든 write 스코프 불허,
  **Administration 불허**, Organization permissions 전부 No access.
- 생성 후 General → About의 **App ID(숫자)** 를 기록한다(Client ID 아님).
- **Private key 생성(Generate a private key)** → PEM은 표시 1회. 로컬 파일시스템·저장소에
  저장 금지(AGENTS §0.4c/§2.4) — 발급 루트는 GitHub 측에만 존재해야 한다(계약 §1).
  바로 §1.3 예치로 이행하고 임시 사본은 즉시 파기한다.

### 1.2 저장소 설치 (설치 상한)

- Install App → `Archright` → Repository access: **Only select repositories —
  `Archright/Axiom` 단일**. 다른 저장소에 설치하지 않는다(계약 §2 설치 상한).
- 설치 승인 화면에서 요청 권한이 §1.1의 5개 read-only와 정확히 일치하는지 확인 후 Approve.

### 1.3 환경 보호 + 시크릿 예치

- Settings → Environments → **`diagnostic-authority`**(이미 존재하는 레코드 — §0)에서:
  1. **Required reviewers**: 소유자 1인 추가(release-authority 환경과 동일 패턴 —
     `.github/workflows/release-ship.yml:193,219-225` 선례).
  2. (선택) Deployment branches: `main`만 허용.
  3. **Environment secrets** 2건 추가:
     - `DIAG_APP_ID` = §1.1의 숫자 App ID
     - `DIAG_APP_PRIVATE_KEY` = PEM 원문(`-----BEGIN ... END-----` 포함 전체)
- 환경 스코프 시크릿이므로 이 환경을 참조하는 job에서만 주입된다 — 다른 워크플로는
  접근할 수 없다.

## 2. 첫 활성화 실행 — 반드시 관측되어야 하는 것

발화:

```bash
gh workflow run diagnostic-authority --ref main            # repo-scope 기본 진단
# PR 진단: -f diag_pr=<N> -f diag_main_sha=<base sha>  추가
# canary 포함: -f run_canary=true -f canary_pr=<TEST_PR> 추가 (§3)
```

required reviewers 승인(환경 게이트) 후 job 진행. **판정 기준**:

1. 게이트 스텝이 통과한다: `registration gate: DIAG_APP_ID present (id never printed),
   DIAG_APP_PRIVATE_KEY present`.
2. 민팅 스텝이 성공한다(pinned `actions/create-github-app-token@bcd2ba4` v3.2.0).
3. **issuance evidence** 블록이 Step summary에 기록된다: 관측 outputs
   `installation-id=… app-slug=…` + 요청 축소 명세(contents=read metadata=read
   merge-queues=read pull-requests=read checks=read; repositories=`Axiom` 단일).
   ⚠️ 발급 **응답**의 `permissions`/`repositories`/`expires_at`은 pinned 액션이 노출하지
   않는다(action.yml@bcd2ba4 실측 — outputs는 token/installation-id/app-slug뿐). 따라서
   실효 스코프는 **UNKNOWN으로 기록 유지**가 정상이다(계약 §3 — "지정했다"를
   "검증됐다"로 서술 금지). 응답 관측 경로가 확보되면 그 원문으로 갱신한다(§5).
4. 진단 **GET이 성공**한다: `merge_ruleset_drift_monitor` exit 0(EXPECTED holds),
   `observe_fault_streak` exit 0. (`diag_pr` 지정 시 `landing_observe.sh` 0/1/2/3 중
   실측 판정값, `diag_pr`+`diag_main_sha` 지정 시 `ax merge --dry-run` 0/1.)
5. canary 활성화 시 **WRITE가 거부**된다: 판정 `PERMISSION_LACK_PROVEN` — 403 + GitHub
   Apps 정식 거부 본문("Resource not accessible by integration") + `X-GitHub-Request-Id`
   원문 캡처. `WRITE_SUCCEEDED`(2xx) = 상한 위반 **치명** — 즉시 App 설치 제거 + 키
   롤레이션 + 사고 기록. 그 외 전부 `UNKNOWN` = fail-closed(exit 3) 재판정.
6. 그 외 어떤 스텝도 조용히 우회하지 않는다 — 실패 시 로그 원문을 `docs/evidence/`에
   남긴다(fail-closed 관측도 증거다).

## 3. canary deny drill 호출법

- **정본 경로 = 위임 실행**(발급 토큰은 러너 밖으로 나오지 않으므로 로컬 단독 실행은
  원칙적으로 불가):

  ```bash
  gh workflow run diagnostic-authority --ref main \
    -f run_canary=true -f canary_pr=<TEST_PR>
  ```

  `canary_pr`은 TEST base를 가진 open PR이어야 한다(스크립트가 구조적으로 강제).
  운영 ruleset 20303214는 거부 목록, 운영 main 병합은 base-guard가 차단한다.
- dry-run(네트워크 0, 판정 규칙 출력, exit 0 — 2026-10-12 실측, PR #775 §4):

  ```bash
  bash tools/ci/m7_canary_drill.sh --canary-pr 999 --repo Archright/Axiom --dry-run
  ```

- 수명 규율(계약 §5): canary는 통제 계층 6이다 — 진단 App 설치·권한을 건드리는 변경마다
  재실행한다.

## 4. 6-계층 통제 체크리스트 — 상태표 (2026-10-12, 등록 전 기준)

| # | 통제 계층 | 장치 | 상태 | 근거 |
|---|---|---|---|---|
| 1 | 설치 권한 상한 | App installation — read-only 5개 상한(spec §2) | **미폐쇄 — 휴먼게이트 대기** | App 미등록. §1.1–1.2 수행 시 상한 고정 |
| 2 | 발급당 축소 | explicit `permission-*` + `repositories` 등식 요청 | **구조 착지 — 첫 민팅 때 효력** | diagnostic-authority.yml:96-103; 요청이 상한과 등식(§2) |
| 3 | 응답 증거 | issuance evidence 블록 | **UNKNOWN 기록(규율 착지)** — 응답 관측 경로 확보까지 유지 | pinned 액션 비노출 실측; run 38220304031 이후 첫 성공 run에서 installation-id/app-slug 관측 예정 |
| 4 | 발급 경로·키 보관 | 로컬 민팅 코드 0; PEM 소비 경로 = 워크플로 step 유일 + 환경 시크릿 | **구조 성립 — PEM 예치 전** | git_access_scan sites=64 breakers=0(착지 실측); 예치 전 fail-closed 실측 run 38220304031 |
| 5 | 로컬 수명 | in-job 소비 + post-step revoke + add-mask + artifact 0 | **구조 성립 — 첫 발행에서 재확인** | 토큰은 러너 밖으로 나가지 않음(워크플로 계약 §3) |
| 6 | 순환 재검증 | m7_canary_drill.sh | **드릴 준비 완료 — 첫 실실행 대기** | dry-run exit 0 + no-token guard exit 2 실측(§0·§3); TEST PR + 활성 credential 후 입증 |

요약 — **오늘 구조 폐쇄**: 2·4·5 / **휴먼게이트 대기**: 1 / **첫 실행 대기**: 2(효력)·
5(재확인)·6(입증) / **UNKNOWN 유지**: 3.

## 5. 활성화 후 갱신 의무

1. `docs/evidence/m7_delegated_execution_2026-10-12.md` §3 논항 표에 첫 실행 관측값·근거
   기입(관측값은 실측과 함께 — AGENTS §2.2).
2. 발급 응답 관측 경로 확보(액션 후속 버전 또는 검증된 토큰 자기소개 경로) 시 §3의
   UNKNOWN을 응답 원문으로 갱신 — 추측으로 채우지 않는다.
3. `trusted-writer-set.yml` required 승격은 별개 인간 액션이다(ruleset required checks
   편입 — 승격 전 어드바이저리 관측, 계약 §8).
4. 권한·설치 변경마다 canary 재실행(통제 계층 6 수명 규율).

## 6. 부록 — 착지 후 검증 실측 기록 (2026-10-12)

- bsec 필드 정정(PR #779) 효과 실측: 수정 전 merge_group run **38214224657**(pr-776 큐,
  06:46:54Z)는 `[gate] base commit resolvable in candidate tree (fail-closed)` 스텝에서
  failure. 수정 착지(c01a8316e, 06:48:12Z) **이후 merge_group run 전체 success** —
  38214361827(pr-779 그룹 @ c01a8316e), 38216902321·38217260018(pr-781),
  38217750807(pr-780), 38217752296, 38218678258(pr-775 그룹 @ 905e53e9d — 본 모델 착지
  그룹), 38218852819(pr-781 @ 4b7efdcdf). "base commit resolvable" 게이트는 이제 실제
  base(`merge_group.base_sha`)를 받는다.
- 본 런북이 문서화하는 fail-closed·no-fallback 실측은 §0에 기재(run 38220304031 + 로컬
  가드 2건).
