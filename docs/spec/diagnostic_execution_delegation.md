# 진단 실행 위임 계약 (diagnostic_execution_delegation)

**Status**: Normative contract (2026-10-12 — M7 위임 실행 모델, 사용자 승인 작업 "진단 execution의 Actions 위임").
**Related**: `docs/spec/merge_authority_integrity.md` M7 (진단 순수성 · Tier 0/1) ·
`docs/spec/merge_authority_integrity.md` §4 (Administration write 게이팅) ·
`.github/workflows/release-ship.yml` (environment + App-token 선례) ·
`.github/workflows/diagnostic-authority.yml` (본 계약의 실행체) ·
`.github/workflows/trusted-writer-set.yml` (TWS CI 배선) ·
`tools/ci/m7_canary_drill.sh` (canary 계약 §5) · AGENTS.md §2.3 (merge-admission authority = GitHub) · §2.4 (credential authority).

## 1. 목적 · 위임 모델

신뢰 계약: **"감시 identity는 merge 상태를 바꿀 수 없다"** 가 6개 제어 계층에서 구조적으로
성립해야 한다 — (1) 설치 권한 상한(App installation ceiling), (2) 발급당 축소(per-issuance
reduction), (3) 응답 증거(issuance response), (4) 발급 경로·키 보관(issuance path & key
custody), (5) 로컬 수명(local lifetime), (6) 순환 재검증(rotation re-verification).

이전 계획의 모순(해소됨): "App 개인키는 로컬 프로세스에 접근 불가" ∧ "로컬 토큰 민팅 코드
부재" ∧ "로컬 도구에 `actions/create-github-app-token` 단기 토큰 사용"은 동시에 성립할 수
없다 — 그 액션은 워크플로 job 안에서만 동작하고 post step에서 revoke하며("cannot be passed
to another job"), 토큰은 로컬 기계에 도달하지 않는다.

**채택된 해소: 토큰을 로컬로 가져오지 않는다 — 진단 EXECUTION 자체를 위임한다.** 진단
명령은 보호된 GitHub Actions 환경(protected environment + required reviewers)에서, job 안에서
민팅된 단기 installation 토큰과 함께 실행된다. 토큰은 러너 밖으로 나가지 않고(발급 루트인 App
PEM은 GitHub 측에만 존재), 로컬 진단 프로세스는 발급 루트에 접근할 수 없다. 이것이
merge_authority_integrity §6 Tier 1(구조적 identity 분리)의 위임 실행판이다: 진단 credential의
쓰기 경로는 존재하지 않는 것이 절차적으로 금지된 것이 아니라 **상한으로 만들어진다**.

## 2. 진단 App 등록 스펙 (인간 게이트)

GitHub은 App 생성 API를 제공하지 않는다(merge_authority_integrity §6 Tier 1의 인간 의존과
동일). 따라서 아래 등록은 **인간이 수행하는 게이트**이며, 에이전트는 이 스펙을 제공하는 것만이
범위다. 등록 전까지 `.github/workflows/diagnostic-authority.yml`의 job은 시크릿 부재로
실패한다 — 그것이 fail-closed다(조용한 우회 없음).

| 항목 | 값 |
|---|---|
| App 이름 | `axiom-diagnostic-authority` |
| App 유형 | GitHub App (조직 소유, Archright) |
| 설치 대상 | `Archright/Axiom` 단일 저장소 (설치 상한 — 다른 저장소에 설치 금지) |
| 설치 권한 상한 (read-only 5개) | **Contents: read** · **Metadata: read** · **Merge queues: read** · **Pull requests: read** · **Checks: read** |
| 명시적 부정 | 쓰기 스코프 전부 불허 — Contents/PR/Checks/Merge queues **write 불허**, **Administration 불허**, 그 밖의 모든 스코프 불허 |
| Webhook | 비활성 |
| 키 보관 | App private PEM은 발급 시 1회만 표시 — 로컬 파일시스템·저장소에 저장 금지(§0.4c/§2.4); environment 시크릿으로만 예치 |
| 환경 | repository environment **`diagnostic-authority`** — protected: required reviewers(소유자 1인, release-authority 선례 — release-ship.yml:193,219-225와 동일 패턴), deployment branches 제한(선택) |
| 시크릿 | 환경 스코프: `DIAG_APP_ID` (numeric App ID), `DIAG_APP_PRIVATE_KEY` (PEM 원문) — 환경 밖 job에서는 접근 불가 |

**per-issuance reduction**: 워크플로의 민팅 step은 App 설치 상한과 동일한 최소 집합만
요청한다(`permission-contents/metadata/merge-queues/pull-requests/checks: read` +
`repositories: <단일 저장소>`) — 미지정 권한의 기본 상속을 만들지 않는다. 설치 상한이 이미
read-only이므로 이 요청은 축소가 아니라 **등식**이지만, 요청측 등식을 유지하면 설치 상한이
완화되는 사고에서도 요청이 상한을 암묵 수용하지 않는다.

## 3. 워크플로 계약 (diagnostic-authority.yml)

- **트리거**: `workflow_dispatch` 단일 (push/pull_request 발화 없음 — 관측 대상 아님).
- **권한 천장**: 최상위 `permissions: contents: read` 단일; 모든 external action은 커밋 SHA 고정.
- **민팅**: pinned `actions/create-github-app-token@bcd2ba49218906704ab6c1aa796996da409d3eb1`
  (v3.2.0 — release-ship.yml과 동일 핀), §2의 explicit 입력. 같은 job 안에서 소비; 액션의
  post step이 job 종료 시 토큰을 revoke한다(로컬 수명 = 0).
- **토큰 비기록**: `add-mask` 등록 + 출력 금지 + artifact 업로드 없음. 증거에는 토큰 값이
  절대 포함되지 않는다.
- **증거 규칙 (UNKNOWN 규율)**: pinned 액션의 outputs는 `token`/`installation-id`/`app-slug`
  3개뿐이며 발급 응답의 `permissions`/`repositories`/`expires_at`을 노출하지 않는다
  (action.yml@bcd2ba4 실측). **요청에 그것들을 지정했다는 사실은 실효 스코프의 증거가
  아니다** — 응답 관측이 없는 한 실효 스코프는 **UNKNOWN으로 기록**한다. 응답을 관측하는
  경로(예: 발급 응답을 노출하는 후속 액션 버전, 또는 검증된 토큰 자기소개 엔드포인트)가
  확보되면 그 응답 원문으로 UNKNOWN을 갱신한다 — 추측으로 채우지 않는다(M6 어휘 규율).
- **진단 실행**: 같은 job에서 merge_ruleset_drift_monitor · observe_fault_streak ·
  landing_observe.sh · (`ax merge --dry-run`)을 `AXIOM_DIAG_TOKEN` + `AXIOM_DIAG_STRICT=1`
  로 실행한다 — §4 가드가 credential-source를 강제한다.
- **canary**: 같은 job에서 §5의 drill을 실행한다(기본 off — dispatch input으로 화이트스위치).

## 4. 로컬 no-fallback 계약 (AXIOM_DIAG_TOKEN / AXIOM_DIAG_STRICT)

로컬 진단 도구는 진단 credential이 없을 때 운영자의 `gh auth` PAT로 **조용히 폴백하지
않는다**. 도구별 현재 auth 경로에 맞는 최소 결정론 메커니즘:

| 도구 | 현재 auth 경로 | 가드 |
|---|---|---|
| `tools/merge_ruleset_drift_monitor.nim` | `gh api` (gh keyring) | 라이브 fetch 경로에서 `AXIOM_DIAG_TOKEN` → `GH_TOKEN` 주입; `AXIOM_DIAG_STRICT=1` ∧ 토큰 부재 → exit 1; credential-source 항상 출력 (`--ruleset-file` 오프라인은 무관) |
| `tools/ci/landing_observe.sh` | `gh api`/`gh pr view` | 동일 (`GH_TOKEN` export; strict 부재 → UNKNOWN exit 2 fail-closed) |
| `tools/ci/pareto_harness.nim` | `gh api` ingest (`--github-run`) | ingest 경로 진입 시 동일 가드 (`--from-json` 오프라인 재생은 무관) |
| `tools/ci/observe_fault_streak.nim` | `gh api` GET | main 진입 시 동일 가드 |
| `tools/ci/local_ci_gates.nim` | `gh api` (`--pr` 경로) | `--pr` 경로에서 동일 가드 (strict 부재 → exit 2) |
| `ax merge` (`src/cli/merge_cli.nim`) | `GITHUB_TOKEN` env | **계약 확정 · 착지는 후속 rotation slice**(본 PR 제외 — 아래 착지 경로 주석). 계약: credential 선택 순위 `AXIOM_DIAG_TOKEN` > `GITHUB_TOKEN`; `AXIOM_DIAG_STRICT=1` ∧ `AXIOM_DIAG_TOKEN` 부재 → fail-closed; credential-source 항상 로그. strict 미설정 + AXIOM_DIAG_TOKEN 미설정은 기존 동작 유지(admission-check CI 경로 불변) |

착지 경로 주석: `src/cli/merge_cli.nim`은 `trustedCheckerTreeClosure` pin 멤버(864)라
그 변경은 트리 closure을 바꿔 ADR-0025 §7 ROTATION 주체가 된다. 본 PR의 changed set에는
비멤버 경로(docs/spec·tools·workflow 신규 등 14건)가 포함되어 회전 allowlist ①(A2 (i) —
비멤버 production 경로 회전 승인 금지)을 영구 만족할 수 없다(merge_group verdict
2026-10-12 06:25 UTC 실측 — prNumber 775, ROT_ALLOWLIST, newAnchorOk=false). 따라서
본 PR은 merge_cli 변경을 제외해 NORMAL 주체로 착지하고, credential 선택은
`merge_cli.nim`(pin member) + `config/trusted_writer_set.json`(pin 재앵커, ④
pin@H==derived(H)) + A2 companion(tests/architecture_debt)만으로 구성된 **별도 rotation
slice**로 직후 착지한다 — 전 changed path가 allowlist 내라 A2가 설계한 정합 경로다.

불변식: (a) credential-source는 **항상** 출력된다(침묵 폴백 금지). (b) strict 모드에서
`AXIOM_DIAG_TOKEN`은 **유일한** 수용 source다. (c) 도구는 credential을 **발견하지 않는다** —
명시적으로 지정된 단일 env 1개만 읽는다(AGENTS.md §2.4의 credential 발견 금지와 정합;
"명시 프로비저닝 시크릿은 발견 대상 아님"). (d) 위임 워크플로의 러너에는 gh keyring 자체가
없어 폴백 경로가 구조적으로 부재하다 — 로컬보다 강한 보장.

## 5. canary deny drill 계약 (tools/ci/m7_canary_drill.sh)

운영 credential과 동일 권한 구성의 진단 credential으로 merge-affecting 쓰기를 **시도**하고
거부를 캡처한다 — "안 하면"이 아니라 "하면 거부된다"의 입증.

- **대상**: TEST PR(기본 base 브랜치가 아닌 TEST base를 가진 open PR — 스크립트가
  구조적으로 강제) + 선택적 TEST ruleset(verbatim GET-body PUT-back = no-op 쓰기).
  **운영 ruleset 20303214는 거부 목록**, 운영 main 병합은 base-guard가 차단.
- **증거**: HTTP status + 응답 body + `X-GitHub-Request-Id` 원문.
  `X-Accepted-GitHub-Permissions`는 **보조 전용** — 엔드포인트의 요구사항이지 토큰의
  부여가 아니다; 스코프 증거로 인용 금지.
- **판정 어휘 (닫힌 집합)**:
  - `PERMISSION_LACK_PROVEN` — 403 + GitHub Apps 정식 거부 본문("Resource not accessible
    by integration"). 403은 mergeability/ruleset 평가에 선행하므로 거부 사유가
    **권한 결핍**임이 확정된다(branch-protection·체크 미완료·merge-state가 아님).
  - `WRITE_SUCCEEDED` — 2xx. 상한 위반(치명적, exit 1; 즉시 대응 지침 출력).
  - `UNKNOWN` — 그 외 전부(404·405/409/422 평가 도달·5xx·모호 본문). UNKNOWN은 성공도
    입증된 거부도 아니다 — **실패 폐쇄**(exit 3).
- **credential**: `AXIOM_DIAG_TOKEN` 단일 — gh auth/GITHUB_TOKEN 폴백은 구조적으로 부재
  (검증 대상 credential이 아니면 canary는 무의미). `--dry-run`은 네트워크·토큰 없이 요청
  계획+판정 규칙을 출력하고 exit 0.
- **수명**: canary는 순환 재검증 계층(제어 계층 6)이다 — 진단 App 설치·권한을 건드리는
  변경마다 재실행한다.

## 6. 종료 조건 (완료 서술의 정본 어휘)

이 모델의 완료 문장은 다음 **4개 논항의 논리곱**이다:

> **감시 정상 작동 ∧ 로컬 진단 프로세스의 발급 루트 접근 불가 ∧ 진단 App의 상한 밖 권한
> 발급 불가 ∧ 운영 credential의 변경 행위 거부 입증**

단순한 "발급 권한 없음"으로 줄여 서술하지 않는다. 근거: (a) 진단 App이 토큰을 **발급하는
능력** 자체는 상한 경계 안에서 존재한다(민팅 권한 없음이 아니라 **상한 밖 발급 불가**);
(b) 로컬 프로세스의 발급 루트(App PEM) 접근 불가는 **다른 속성**이며 전자가 후자를 함축하지
않는다 — 위임 모델은 이 둘을 분리해 각각 성립시킨다. (c) 4번째 논항("운영 credential의 변경
행위 거부 입증")은 §5 canary drill의 `PERMISSION_LACK_PROVEN`이 그 증거 위치다 — 운영 감시
구성과 동일 권한으로 merge-affecting 쓰기를 시도해 거부됨을 입증한다. 참고: 인간 운영자의
`gh auth` PAT 자체는 merge_authority_integrity §7 executor inventory상 선언된 수동 병합
주체로 남는다 — 거부 입증의 대상은 감시 identity 구성이지 운영자의 수동 권한이 아니다.

각 논항의 현재 상태는 `docs/evidence/m7_delegated_execution_2026-10-12.md`의 논항 표가
정본 위치다(관측값은 실측과 함께 기입 — AGENTS.md §2.2).

## 7. 실행 가능성 (feasibility) 실측

| 진단 명령 | Actions 러너 요구물 | 판정 |
|---|---|---|
| merge_ruleset_drift_monitor.nim | Nim 2.2.10(setup-axiom-toolchain — repository_surface.yml 동일 공급 경로), nimble `checksums@0.2.2`(repository_surface.yml 선례 — integrity manifest bootstrap), `gh`(러너 프리인스톨) | **실행 가능** — 워크플로가 컴파일·실행 배선 |
| observe_fault_streak.nim | 위 + `unzip`(러너 프리인스톨 — artifact payload 판독), `gh` | **실행 가능** |
| landing_observe.sh | `gh`+`jq`(러너 프리인스톨) — Nim 불요 | **실행 가능** |
| pareto_harness.nim ingest | Nim + `gh api` | **실행 가능**(기본 dispatch에서는 제외 — run-id 입력 필요; 오프라인 재생은 `--from-json`) |
| `ax merge --dry-run` | `bin/ax` 빌드(nim c src/cli/main.nim — 콜드 수 분) + `AXIOM_MAIN_SHA` | **실행 가능하나 중량** — `diag_pr`+`diag_main_sha` 입력이 모일 때만 opt-in |
| local_ci_gates.nim | Nim + gh + 대상 ref 서브스트레이트 빌드(게이트 러너 전체 컴파일) | **실행 가능하나 최중량** — 위임 워크플로 기본 경로에서 제외; 필요 시 수동 dispatch로 문서화(기본 미배선 — 제품 계약 밖 측정 중량) |

공통 전제: repo checkout(actions/checkout v4 핀, `persist-credentials: false`), 네트워크
egress(api.github.com — 러너 기본 허용). 차단 요소 없음.

## 8. 인간 게이트 이후 미해결 항목

1. §2 등록 수행(App 생성 + 설치 + `diagnostic-authority` 환경·시크릿) — 등록 전
   diagnostic-authority job은 fail-closed가 정상 동작이다.
2. 발급 응답(`permissions`/`repositories`/`expires_at`) 관측 경로 확보 시 §3 UNKNOWN 갱신.
3. `trusted-writer-set.yml`의 required check 승격(ruleset required checks 편입) — 승격 전
   어드바이저리 관측이다.
4. 최초 canary 실행(TEST PR 준비 후) — §5 수명 규율로 이후 권한 변경마다 재실행.
