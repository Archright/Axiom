# E6 — 저장소 재생성(Rip-and-Replace) 전환 기록

**실행일**: 2026-11-06 · **판정**: RECREATION_BOOTSTRAPPED (main·태그·LFS 랜딩 + 통제 체계 재구성 · 공개 전환은 사용자 전용)

## 관측 정정 — observed-at 재기록 (2026-11-07, authority rotation 실측)

본문 기록 시점에는 1차 clean-origin 세대가 현행으로 보였으나, **저장소가 한 세대 더 재생성되었다**. 2026-11-07 실측(전부 GET read-only)으로 확정된 **3세대 체인**:

| 세대 | repo id | 이름 이력 | 상태·근거 |
|---|---|---|---|
| 구 정본 | **1182104685** | Axiom → **Axiom-archive** | 현존(private, Actions 동결) — `GET repos/Archright/Axiom-archive` 실측 id 일치 |
| 1차 clean-origin | **1447964055** | Axiom → **Axiom-legacy** 개명 후 **삭제(2026-11-06T18:10:53Z)** | org 감사로그 `repo.destroy` 이벤트(actor 원본 그대로, `Archright/Axiom-legacy`, timestamp 1793988653554 ms = 2026-11-06T18:10:53Z) — 아래 404 실측과 일치 |
| 현행 | **1448376585** | **Axiom-clean → Axiom** | 현존(private, default main, created 2026-11-06T14:42:31Z, **Actions disabled/동결**) — `GET repos/Archright/Axiom` 실측 |

감사로그 근거: `gh api "orgs/Archright/audit-log"`의 `repo.destroy @ Archright/Axiom-legacy`(2026-11-06T18:10:53Z)가 유일하게 잔존하는 파괴 이벤트다 — 개명(rename) 이벤트는 감사로그 보존 창 밖이므로 체인의 개명 구간은 현존/부재 실측(archive id 1182104685 현존, 구 id 1447964055 부재·신규 id 1448376585가 `Archright/Axiom` 이름 보유)로 소급 정정한다.

**ruleset observed-at (2026-11-07 실측)**: 현행 repo ruleset 4종 = `main` **26702792**(필수검사 5종 integration_id 15368·merge_queue MERGE/ALLGREEN/max2 — 본문의 26678552 후속)·`cas-probe-scratch` 26702920·`execution-surface-create` 26702960·`artifact-hygiene` 26702965. 구 ruleset id(20303214 포함 26678xxx 계열)는 전부 구 저장소 소속이며 현행에서 404 — 숫자 id는 저장소 스코프 자원이므로 live 조회 경로는 전부 **이름 해석**("main")으로 전환됐다(config/policy/merge_admission.json v1.19.0 hybrid authority rotation, PR: chore/authority-rotation). 워크플로 id 4종도 재발급 실측: bsec-integrity 409432614·debt-registry-gate 409432630·generation-acceptance 409432642·axiom-operational-slice 409432611(observedAt 2026-11-07T05:23:47Z).

이하 본문은 2026-11-06 부트스트랩 실행 기록 그대로다(1차 세대 id·ruleset id 4종이 시점 기록으로 등장 — 위 표의 매핑으로 읽는다).

## Ultimate Purpose

GitHub Support 의존 경로(PR refs·LFS orphaned 객체 서버 측 제거)를 폐기하고, 신규 repo를 유일 공개 표면으로 삼아 과거 실행 이력·PR 참조·artifact 노출을 원천 차단한다.

## 경로 전환 결정

- 사용자 결정(2026-11-06): Support 티켓 경로 폐기, 하이브리드 아카이브 경로 승인("아카이브도 괜찮아")
- **옛 repo** → `Archright/Axiom-archive` (ID 1182104685) — private 영구 보존·Actions 동결. 과거 Actions 실행·artifact·PR #≤1290 참조는 이곳에만 존재
- **신규 repo** → `Archright/Axiom` (ID 1447964055 ← 1차 세대 시점 기록; **현행은 1448376585** — 위 관측 정정 표 참조) — 유일 공개 표면 예정(공개 전환은 사용자만 실행)
- **PR 번호 연속성**: PR #≤1290 및 재생성 전 참조는 전부 아카이브를 가리킴. Gate 3 PR부터 신규 번호 체계

## 부트스트랩 범위·근거

- `main` = `b4c08e94e`(E2 MERGE 커밋, 재작성 세대) + **태그 85개** + LFS KEEP 1종 `8c744d79…`(SVF-SVC CC-BY, 10,076,526B)
- 미이월(의도적): 워크스트림 브랜치 111개·`gh-readonly-queue/*`·과거 Actions runs(34,548)·artifacts·시크릿 실값(값 이전 API 미제공)·issues/PR 메타데이터
- 부트스트랩 클론: `/tmp/axiom_bootstrap`(아카이브 신선 클론, LFS skip-smudge)

## 장애 해제 — org required workflows (GH013)

신규 repo `main` 생성 push가 org ruleset 2종(`axiom-admission-gate`·`landing-integrity`, `.github` repo 핀 참조)에 거부됨 — 브랜치 생성 시점에 required workflow 만족 이력이 존재할 수 없음(`do_not_enforce_on_create=false` + bypass_actors `[]`).

해제(E2 핀 회전과 동일한 통제 전환 패턴):
1. 양 ruleset 전체 백업(`…_boot_backup.json`) → PUT으로 `do_not_enforce_on_create=true` 임시 전환(핀 불변)
2. 신규 repo Actions 비활성화(`enabled:false` — 부트스트랩 push의 실패 run 노출 방지)
3. `main` push 성공 + LFS KEEP 업로드 실측("100% (1/1), 10 MB")
4. 백업 페이로드로 **원복 실측**: 플래그 `false` 복원·핀 `c77509c5…`/`d8f04c56…` 무결

## 태그 85개 — 안전성 3중 확증 후 배치 push

- 태그 68개(v0.x.y 버전 태그 전체 포함)가 main 이력 바깥 커밋을 가리킴 → **재작성 전 이력 부활 가능성** 검증 필요였음
- 확증: (1) commit-map에서 재작성 후 SHA 확인(예: v0.5.1 `0c876bd58…`→`f52e92384…`) (2) cutover 6차 검증 5종이 전 브랜치·태그 대상 PASS (3) **로컬 독립 검증: 85개 태그 통합 이력 × `invert_paths_final.txt` 117 경로 → 잔존 0**
- docs/spec PDF는 KEEP 대상 SVF-SVC만 존재(2026-06-10 "Windows-safe filenames"로 콜론 파일명→언더스코어 개명. 과거 실체 blob `686b8da1…`도 동일 CC-BY 콘텐츠 10,076,526B)
- `--tags` 일괄 push는 SSH 원격 끊김으로 실패(원격 도착 0개) → 날짜순 10개×9배치·1회 재시도 스크립트로 전환. 추가 대상 객체 92,738개
- **배치 결과: **9/9 배치 OK(재시도 0회)·원격 태그 85개 실측**(ls-remote, 16:50~16:58 약 8분)**

## 통제 체계 재구성 (스냅샷 대비 실측)

- Actions 변수 2종: `CI_RUNNER_MAP`(ghec 모드 그대로)·`REARM_APP_ID` — total_count 2 확인
- 환경 3종: `ci-provider-router`(branch_policy 커스텀·허용 브랜치 `main`)·`diagnostic-authority`(보호 없음)·`release-authority`(required reviewer = Licensor)
- 러너 그룹 3종 소속: axiom-ci(3)·axiom-publisher(4)·axiom-control(7) — `allows_public_repositories=false` **flip 시 참고**: public 전환 후 해당 그룹 접근 재검토 필요(현행 hosted 모드 무영향)
- repo ruleset 4종: 4종 active 생성·실측 — `main`(26678552 ← 1차 세대 시점 기록; **현행 26702792**: 필수검사 5종 integration_id 15368·merge_queue MERGE/ALLGREEN/max2 원본 동일)·`cas-probe-scratch`(26678554→현행 26702920)·`execution-surface-create`(26678565→현행 26702960)·`artifact-hygiene`(26678566→현행 26702965 — 위 관측 정정 참조). push 2종은 POST 시 `conditions:null` 키 거부(422) → 키 생략로 생성 (push ruleset 2종은 부트스트랩 push 완료 후 생성 — 순서 제약)
- Actions 재활성: enabled:true·allowed_actions:all 실측 (구성 완료·Gate 3 PR 직전)
- 시크릿 2종(`REARM_APP_PRIVATE_KEY`·`REARM_ARM_TOKEN`): 값 이전 불가 — 사용자 항목. 유일 소비자 `merge-queue-rearm.yml`(비필수 검사)로 Gate 3 차단 아님. 재생성 시점까지 신규 repo에 부재 → rearm 기능 비활성 상태로 기록

## 공개 표면 영향 (Gate 4 대상)

- 신규 repo는 부트스트랩 이력만 보유: 과거 Actions 로그·artifact 12,172개·PR refs 1,266개 전원 아카이브 존속(private) → Support 경로의 노출 우려 원천 종결
- Gate 3 CI부터 신규 run·artifact만 발생 → Gate 4 스윕 대상
- `credential_handoff_PRIVATE.md`·kimi-export·session ZIP 등 E2 제거 자료는 신규 repo에 존재하지 않음(부트스트랩 원천 불포함)

## 2단계 랜딩 (B-judge 아키텍처 대응)

Gate 3 본체(SAL 적용)는 계약 등록 **선행 착지 이후** 랜딩됐다. 근거: landing venue(merge queue)의 루트 게이트는 **B(base=main) 소스로 빌드한 검증자**가 후보 트리를 심사한다("A PR never grades itself with a judge it ships" — 핀 `admission-check.yml@686f613f`). 신규 루트 엔트리 3종은 등록이 main에 존재해야 B-판사가 승인한다.

- 1단계: **PR #5**(계약 등록 단독, `work/sal10-root-registration`) — 2026-11-06 merge queue MERGE 랜딩(`bb251eb342`, 큐 merge_group 8/8 SUCCESS·admission-gate root-layout B-판사 PASS)
- 2단계: **PR #4**(SAL 본체 6커밋, `work/sal10-gate3` rebase) — 본 PR
- 실측 근거: PR #4 첫 큐 시도(등록 없는 B)에서 admission-gate FAIL — root-layout 3 violations(THIRD-PARTY-NOTICES.md·LICENSES·CLA unknown)
