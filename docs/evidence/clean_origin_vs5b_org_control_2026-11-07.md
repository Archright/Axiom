# Clean-Origin Migration VS-5B — 조직 통제 실측 (2026-11-07)

> **Status**: 관측 증거 기록 — rename-swap(VS-5A) 후 정식명 `Archright/Axiom`에서 신규 PR이 조직 필수 Workflow 2종을 포함한 전체 경로(필수검사 5종 → merge queue → GitHub native MERGE)를 통과하는 것을 관측한다.
> **Created**: 2026-11-07
> **Base (ROOT)**: `938a49e024e4139b736ba81f568b74076d47bb2a`
> **Branch**: `clean-origin/vs5b-org-control` (main 기반, 본 문서 1건만 추가 — diff 최소, 코드 무변경)

## 1. 전제 (VS-5A rename-swap 완료)

- 구 repo `Archright/Axiom` → `<legacy-repo>` (동결 유지, main `0212bdae`)
- 신규 repo `Archright/Axiom-clean` → `Archright/Axiom` (id 1448376585, main ROOT `938a49e0` 불변)
- 조직 ruleset 2종이 `repository_name: ["Axiom"]` 정확명 대상으로 신규 repo에 정합:
  - `axiom-admission-gate` (25218071): required workflow `.github/workflows/admission-gate-v2.yml` @ `c77509c5298d84cd15900113602ec1a362da3fe1` (Archright/.github)
  - `landing-integrity` (23943917): required workflow `.github/workflows/landing-integrity.yml` @ `d8f04c5602a1dc27b4edd908ef9536709edc2665` (Archright/.github)
- `repos/Archright/Axiom/rules/branches/main`에 Organization-source `workflows` 규칙 2건 출현, `<legacy-repo>`에서는 소멸 확인 완료.

## 2. 기대 경로

1. 본 PR의 `pull_request` 이벤트가 조직 required workflow 2종을 발화시킨다 (org workflow run 생성).
2. repo 필수검사 5종(admission-check · bsec-integrity · debt-registry-gate · generation-acceptance · axiom-operational-slice)이 전부 보고·통과한다 — VS-4에서 구조적으로 미보고였던 `admission-check`가 조직 admission-gate 경유로 이번에는 보고되어야 한다.
3. merge queue 적재 후 GitHub native MERGE 병합 — 부모 2: main + 본 브랜치 팁.
4. 병합 후 브랜치 자동 삭제 (delete_branch_on_merge=true).

## Non-claims

- 본 문서는 관측 계획·검증 목적을 기록한다. 판정(검사 결과·org workflow 식별·큐·MERGE SHA)은 GitHub 관측이 권위이며, 결과 요약은 세션 보고서(`vs5_report.md`)에 기록된다.

## 3. VS-5B' 의존성 회전 기록 (2026-11-07, 본 커밋)

> VS-5B STOP 원인(조직 admission-gate callee 핀 `Archright/Axiom@686f613f…` = 구 repo 히스토리 전용 커밋 → run 42246968076 job 0개 failure → admission-check 미보고)의 복구 회전. **핀 값만 회전 — 규칙 구조·약화·완화 무변경.**

1. **.github callee 핀 회전 커밋** `4877e30b5c118b400d4bc1b08459125ffd5b14c4` (브랜치 `chore/rotate-admission-pin-clean-origin`, PR Archright/.github#259): `admission-gate-v2.yml`의 활성 핀 6개(`.github/actions/setup-axiom-toolchain` 1 · `admission-check.yml` 2 · `certificate-mint.yml` 2 · `runner-pool-acceptance.yml` 1) `686f613f6b30c8c38e8661dddd765c8430845692` → `938a49e024e4139b736ba81f568b74076d47bb2a`(ROOT). 회전 대상 4경로 전부 ROOT tree에 존재 검증 완료. 핀-게이트 3-way 결속 사전 검증: `productionExecutionPin == trustedAdmissionWorkflowSha == blob(admission-check.yml)@938a49e0 = 38ceca693187997866f1e1d582bf13ce8c2103e9` (N+7 홍보 blob).
2. **조직 ruleset 25218071(axiom-admission-gate) sha 회전**: `c77509c5298d84cd15900113602ec1a362da3fe1` → `4877e30b5c118b400d4bc1b08459125ffd5b14c4`. GET 전문 기반 재구성, sha 필드만 교체 — 회전 후 GET diff 검증: sha 1필드 외 byte 불변 (enforcement=active, conditions=refs/heads/main + repository_name Axiom, do_not_enforce_on_create=false, bypass_actors=[] 그대로). ruleset 23943917(landing-integrity)은 `landing-integrity.yml`에 Archright/Axiom 핀이 없어 미수정.
3. **본 커밋 push → synchronize 이벤트**로 조직 admission-gate가 회전 핀에서 재실행되어야 하며, 이번에는 `admission-check`가 보고되어야 한다 (VS-5B 관측: run 42246968076 jobs=[], `referenced_workflows: []`).

### VS-5B' 발견 (App 설치 — 사용자 판정 항목, 본 세션 미조치)

- PR .github#259의 필수검사 `pin-promotion-gate (DEBT#473)`는 REARM App(`axiom-rearm` 177083524, `repository_selection: selected`) 토큰 mint가 `GET /repos/Archright/Axiom/installation` 404로 fail-closed — rename-swap 시 App 설치가 구 repo(현 `<legacy-repo>`)를 따라가고 신규 repo(1448376585)에는 설치가 없다. VS-5B §2.8이 사용자 UI(Settings → Applications) 항목으로 지정한 바와 동일(신규 repo `vars.REARM_APP_ID=5550340`는 프로비저닝됨 — 설치 의도는 존재). PR #259는 정상 경로 랜딩 대기로 open 유지하며, admission-gate callee 실행 자체는 App을 요구하지 않아 본 PR 경로에는 영향 없음.
