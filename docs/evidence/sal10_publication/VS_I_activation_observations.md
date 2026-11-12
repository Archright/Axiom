# VS-I Publication Integrity Gate — 활성화·음성제어 관측 기록

> 착지(2026-11-09T11:58:29Z, merge commit `a104d7c411`, 위임 기록 §2.2) 이후의
> Phase 3(ruleset 활성화)·Phase 4(음성제어 3건) 관측 기록. 관측 도구의 권위
> 계층: ruleset/branch-rules readback = REST, PR 판정 = GraphQL
> (`statusCheckRollup.contexts` + `isRequired(pullRequestNumber:)`) — CLI
> rollup 출력은 요약일 뿐 권위가 아니다.

## §1. Phase 3 — ruleset 활성화 readback (2026-11-09T~12:00Z)

- `GET /repos/Archright/Axiom/rulesets/26702792` (6-context 복원 PUT 직후):
  enforcement active, `bypass_actors: []`, rules 5종(deletion·
  non_fast_forward·pull_request·required_status_checks·merge_queue),
  required_status_checks 6 contexts = admission-check·bsec-integrity·
  debt-registry-gate·generation-acceptance·axiom-operational-slice·
  **publication-integrity** (integration_id 전부 15368).
- `GET /repos/Archright/Axiom/rules/branches/main` projection: 동일
  6 contexts + workflows/file_path_restriction 규칙 원본 보존.
- 드리프트 창: 병합(11:58:29Z) → 6-context PUT(11:58:43Z) = **14초**,
  같은 UTC 일 내 폐쇄(스펙 §7 항목 2의 activation manifest 기록 — 본 파일과
  위임 기록 §2.2가 그 기록이다). 상시 감시는 admission-ssot-drift
  workflow_dispatch로 leg2(policy↔ruleset)·leg3(producer)를 관측한다
  (첫 큐 착지 이후 실시 — 관측 SHA 해석이 "착지 완료된 merge_group run"을
  요구하므로 직접 REST 병합 커밋은 leg3 관측 대상이 아니다).

## §2. Phase 4 — 음성제어 3건 (PR #47/#48/#49, 전부 미병합 close)

공통 설계: main(a104d7c411) 기준 별도 브랜치, 각 1파일, PR 오픈 →
publication-integrity 라운드 관측 → close. Push Protection 실측: 가짜
secret(무접두사 랜덤 32-hex)은 push 차단 없이 통과(예측대로 — GitHub
탐지기는 공급자 패턴 기반, gitleaks generic-api-key keyword+entropy만 감지).

### §2.1 NC-1 secret-scan — PR #47 (`workstream/vsi-nc-secret`, head 1d75b3f7aa)

- 파일: `experiments/vsi-nc/nc_probe_secret.py` (선언 경로 experiments/** —
  미의도 차원이 실패하지 않도록 고립 배치; repo `*.py` gitignore에 대한
  force-add는 기존 12개 추적 .py 전례와 동일).
- run 42615462970 (2026-11-09): secret-scan **failure**, license·provenance·
  dependency·sbom 전부 success → 종합 잡 publication-integrity **failure**.
- 차원 리포트(report_secret.json): verdict=FAIL, historyFindings 1532 /
  treeFindings 448, 신규 발견 정확 1건(양 레그):
  - history 지문 `1d75b3f7aa2a359c9f61cf51066d2c4a97466c1f:experiments/vsi-nc/nc_probe_secret.py:generic-api-key:4`
  - tree 지문 `experiments/vsi-nc/nc_probe_secret.py:generic-api-key:4`
- 종합 리포트: verdict=FAIL, unresolvedUnknownCount=0, blockers=
  ["job secret-scan result=failure", "dimension secret-scan verdict=FAIL"].
- GraphQL: publication-integrity conclusion=**FAILURE**, isRequired=**true**,
  mergeStateStatus=**BLOCKED**, required 6 contexts.
- 부가 실측: generation-acceptance **SUCCESS** isRequired=true — 활성화 후
  GPA L2(policy v1.20.0 6 ↔ live ruleset 6) 불일치가 해소됐음을 같은
  라운드에서 확인.

### §2.2 NC-2 license-scan — PR #48 (`workstream/vsi-nc-license`, head 3d26142b4)

- 파일: `experiments/vsi-nc/nc_probe_gpl3.txt` (GPL-3.0 전문 35,149바이트).
- run 42615541020: license-scan **failure** + secret-scan failure(§2.4 교차
  오염), provenance·dependency·sbom success → 종합 **failure**.
- 차원 리포트: verdict=FAIL — license violation `nc_probe_gpl3.txt`
  atom=gpl-3.0-only deniedFamily=true "neither declared (source-origin.yml)
  nor attributed (license-attribution.yml)" + copyright violation(FSF
  홀더 미회계, startLine 4).
- 종합 리포트 blockers: secret-scan·license-scan 잡/차원 실패 4항.
- GraphQL: publication-integrity **FAILURE**·isRequired=**true**·**BLOCKED**.

### §2.3 NC-3 provenance — PR #49 (`workstream/vsi-nc-origin`, head e0f7ab081)

- 파일: 루트 `nc_probe_origin.md` (내용 불활성 — secret/license 텍스트 없음).
- run 42615549524: provenance **failure** + secret-scan failure(§2.4), license
  PASS(고립 실증)·dependency·sbom success → 종합 **failure**.
- 차원 리포트: verdict=FAIL — checkedFiles 6570, declarations 64,
  undeclared=["nc_probe_origin.md"], undeclaredVerdict="DENY"
  (fail-closed by construction — 선언 없는 신규 루트 파일).
- GraphQL: publication-integrity **FAILURE**·isRequired=**true**·**BLOCKED**.

### §2.4 교차 오염 — 공개 표면 스코프의 전이성 (실측·설계 속성)

secret-scan의 history leg는 `--log-opts "origin/main HEAD
--glob=refs/remotes/pr/*"`로 **모든 PR head**(닫힌 PR의 `refs/pull/N/head`
영속 ref 포함)을 스캔한다. 따라서 NC-1의 탐지 커밋(1d75b3f7aa)은 #48/#49
라운드의 secret-scan에도 발견되어 failure를 냈다(두 PR의 blockers에
명시됨). 이것은 오염이 아니라 공개 표면의 정의가 갖는 전이성 — 어느 PR에
든 실제 credential이 오면 **모든 PR의 secret-scan이 차단**된다는
실패-폐쇄 성질의 실측이다.

닫힌 PR의 pull ref는 영속하므로 NC-1 탐지는 이후 모든 라운드에 재등장한다.
정전(triage) 권위는 baseline이다(compliance/policy/secret-scan-baseline.json
_meta — "fail-closed triage"). 본 활성화에서 baseline에 NC-1 지문 2건을
**감사 등록**했다: 분류 `synthetic-test-fixture`(폐쇄 집합 내), 근거
"VS_I_publication_integrity_landing.md §3.3 negative control — inert
random-hex probe (PR #47, closed unmerged); measured run 42615462970
report_secret.json". 지문이 커밋·파일·규칙·라인을 고정하므로 이는 규칙
약화가 아니라 감사된 회계다(스펙 §8 — baseline 변경은 PR 리뷰를 타며
스캔 통과를 위한 약화는 극장).

### §2.5 정리

3 PR 전부 close(미병합), 브랜치 3종 삭제(2026-11-09 ~12:55Z). pull ref는
영속하며 §2.4의 baseline 회계로 정전된다.

## §3. Phase 5 — 정상 큐 착지 (완료 기록, 2026-11-10)

### §3.1 착지 전 데드락 — org ruleset landing-integrity의 base-읽기 구조

PR #50 head `6c71e5b433`에서 6/6 required contexts SUCCESS 관측 후에도
mergeStateStatus=BLOCKED가 지속됐다. 인과 사슬 (전부 실측):

1. GraphQL `enqueuePullRequest` 오류: "Pull request Required workflows
   'landing-integrity' failed".
2. org ruleset `23943917` "landing-integrity" (target refs/heads/main,
   repository_name include Axiom, enforcement active, bypass []) —
   workflows 규칙이 `Archright/.github`(repo id 1182157951)의
   `.github/workflows/landing-integrity.yml` @ `ff516babfc` 를 required로
   지정한다 (ruleset 26702792와 별개의 2번째 필수 체계).
3. 해당 워크플로의 잡 `trust-surface-codeowners`는 **base(main)의**
   CODEOWNERS 커버를 검사한다 (job log 실측 — head의 CODEOWNERS 클로저는
   평가되지 않음). PR #45 착지가 v1.20.0 trustSurface(신규 14경로:
   compliance 6종 + tools/ci 8종)를 base에 등록했으나 base CODEOWNERS에는
   해당 경로 커버가 없다 → 이후 **모든** 신규 PR에서 이 체크가 영구 실패.
4. PR #50은 이 커버 클로저 자체를 싣고 있으나(커버 검증: 디렉터리 prefix
   `/compliance/policy/`·`/compliance/provenance/` + tools/ci 8파일 exact —
   14/14 매칭, 체크 스크립트 매칭 semantics와 대조) 클로저가 main에
   들어가려면 PR #50이 착지해야 하고, 착지하려면 체크가 통과해야 하는
   순환 = 데드락.

### §3.2 rotation 실행 — ruleset 23943917 일시 disabled (선례 패턴)

§2.2의 rotation 레인과 동일 패턴 (승인 주체 = 사용자, §1 전면 승인).
통제 구간 진입 조건 실측: 오픈 PR = #50 단독, merge queue entries
totalCount=0 (GraphQL), auto-merge 무장 없음(autoMergeRequest=null),
main = `a104d7c4`.

- **(i) 일시 전환**: `PATCH orgs/Archright/rulesets/23943917` → 404 (org
  ruleset에는 PATCH 없음 — repo ruleset과 다름). `PUT` 전체교체로
  GET-export 원본(rules·conditions·bypass_actors []·workflow pin 무결)에
  `enforcement: "disabled"`만 변경해 PUT. readback: enforcement=disabled,
  bypass_actors=[] — 규칙 본체 무변.
- **(ii) 큐 진입**: mergeStateStatus BLOCKED→UNSTABLE(MERGEABLE). 이번엔
  `gh pr merge`가 아니라 GraphQL `enqueuePullRequest`를 사용했다 (R2 실측:
  체크 실패 상태의 `gh pr merge`는 auto-merge 무장 폴백 위험; enqueue는
  즉시 수락/오류 이원 판정이라 더 결정론적). 응답: position 1, QUEUED.
- **(iii) merge_group 빌드**: head `da3767d402`에서 6종 required contexts
  전부 SUCCESS 관측 — merge_group runs: axiom-operational-slice 42652391208,
  bsec-integrity 42652391264, debt-registry-gate 42652391203,
  generation-acceptance 42652391246, publication-integrity 42652391295
  (하위 잡 license-scan 포함 전 dimension SUCCESS),
  admission-check(org admission-gate 42652391413) — 보조:
  probe-merge-queue 42652391274·observer-manifest-consistency 42652391382
  도 SUCCESS.
- **(iv) 착지**: native MERGE 커밋 = **TARGET_SHA** `da3767d4024ba6be4b0545b385ee672261eaa70f`
  (parents: main `a104d7d4` + PR #50 head `6c71e5b`). PR #50 MERGED 관측.
- **(v) 즉시 복원**: PUT enforcement=active (원본 전체 형상). readback:
  active·bypass_actors=[]·rules 1(workflow pin `ff516babfc` 무변).

복원 semantics: rotation은 운영 복구 수단이며, 착지 창 동안 5→6 체계의
검증 강도가 일시 감소한 것은 rotation 기록으로 회계한다. 이 창에 착지한
것은 PR #50 단독(오픈 PR 단독·큐 배타 관측으로 증명).

### §3.3 착지 후 정상 상태 복귀 관측

- admission-ssot-drift workflow_dispatch run 42656617209 (2026-11-09T16:38Z,
  `observe_sha` 공란 = 최신 merge_group head 자동 선택) — **전 leg GREEN
  관측**: leg1 constant mirror 2/2 (RequiredChecks·RequiredWorkflowIds ==
  policy 유도 집합), leg2 ruleset drift 4/4 (RESOLVED main=26702792·6
  contexts 정확 일치·MERGE·ALLGREEN), leg3 producer 6/6 contexts (전부
  app id 15368 github-actions 생산). 최종 판정 "the policy SSOT, the
  compiled-in constants and the live platform agree".
- base가 클로저를 포함한 뒤 후속 PR(Capsule PR)의 `trust-surface-codeowners`
  는 base(main=TARGET_SHA)의 CODEOWNERS를 읽어 14/14 커버 → GREEN 전환
  관측 (데드락 해소의 사후 증명 — Capsule PR 체크로 관측).

## §4. Phase 6 — Capsule (완료 기록, 2026-11-10)

`workflow_dispatch`로 publication-integrity 전체 게이트를 main HEAD
(= TARGET_SHA, 공개 대상 SHA == 검증 SHA)에서 재실행했다.
run <GATE_RUN_ID> — 6종 잡 SUCCESS, 종합 보고서 verdict=PASS·
unresolvedUnknownCount=0·binding.commitSha=da3767d4024ba6be4b0545b385ee672261eaa70f.

산출물 sha256 바인딩 → `compliance/reports/publication-readiness.json`
(본 Capsule). 시점별 분리: 봉인 직전 main == TARGET_SHA 확인, Capsule 내부
targetCommitSha/targetTreeSha == TARGET_SHA/TARGET_TREE_SHA, Capsule PR
병합 후 main == CAPSULE_MERGE_SHA. 배타 착지 창: CAPSULE_MERGE_SHA의
parent[0] == TARGET_SHA (끼어든 병합 없음, 단일 사슬).

## §4. Phase 6 — Capsule (완료 기록, 2026-11-10)

`workflow_dispatch`로 publication-integrity 전체 게이트를 main HEAD에서
재실행했다: **run 42656610355** — 6종 잡 SUCCESS (secret·license·dependency·
provenance·sbom·publication-integrity), `head_sha == TARGET_SHA` (공개 대상
SHA == 검증 SHA). 종합 보고서 (artifact `publication-integrity-report`):
verdict=**PASS**·binding.commitSha=`da3767d402`·treeSha=`99bd0130`·
unresolvedUnknownCount=0·blockers 0·policyRevisions 6종 sha256 바인딩.

산출물 11파일(5차원 보고서 + 보조 증거 scancode.json·gitleaks_tree.json·
gitleaks_history.json·osv.json + SBOM 묶음 sbom.json/report_sbom.json +
종합 보고서)의 sha256을
`compliance/reports/publication-readiness.json`에 바인딩해 봉인했다.
봉인 직전 관측: `git ls-remote origin main` == TARGET_SHA (불일치 시
폐기·재검증 규칙 적용 불필요 판정).

정직 기록: dependency-scan의 선언된 커버리지 한계 — Nim(nimble.lock)·
Lean(lake-manifest.json) 생태계는 OSV 미인덱싱 ("no package sources
found — declared limitations recorded"). 판정은 정책 스코프 내 PASS다.

시점별 분리: Capsule 생성 직전 main == TARGET_SHA (관측됨) · Capsule
내부 targetCommitSha/targetTreeSha == TARGET_SHA/TARGET_TREE_SHA ·
Capsule PR 병합 후 main == CAPSULE_MERGE_SHA. **배타 착지 창**:
CAPSULE_MERGE_SHA의 parent[0] == TARGET_SHA (끼어든 병합 없음)로
본 Capsule PR 착지 시 검증한다.
