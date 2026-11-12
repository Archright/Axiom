# G1 Lever-B — 워크플로 파일 경로 리네임 실험 기록 (2026-10-16)

> G1 Lever-A 판정(g1_leverA_create_experiment_2026-10-16.md — PUT 재생성·DELETE+CREATE 모두 무발화, 결함 소재가 워크플로 객체 정체성 id 367727531로 지목)의 후속. Lever-B = **등록 표면(registration surface) 레버 중 마지막 남은 경로**: required-workflow 바인딩 키가 `repository_id + path`이므로 파일 경로 변경은 진짜 NEW 등록을 강제하고, 고착된 객체 정체성과 구조적으로 충돌할 수 없다.

## 전제 사슬 (리네임이 단독으로 성립하지 않는 이유 — 선행 PR 필요)

`certificate-mint.yml`(게이트 callee)의 fail-closed 오케스트레이터 런 정체성 검증이 run object path를 핀한다 — 리네임 후 오케스트레이터 런 path가 `admission-gate-v2.yml`이 되면 기존 검증 4곳이 전부 red. 단일 세대 전환(§2.5)으로 세 겹이 한 창에 함께 뒤집힌다:

| 단계 | PR | 내용 | 결과 |
|---|---|---|---|
| 1. callee 경로 가드 전환 | Axiom **#877** | certificate-mint.yml — r_path 검증 3곳(step 0/1/P0) + `GATE_PATH` 상수(step 2a) → `admission-gate-v2.yml`, 결합 주석 4곳 갱신 (+12/−8) | **MERGED 06:53:12Z, H_mint `9aaee76f09748837ecf0c04779b8d2bdbc9a71c3`** — MG run #1663(id 38862277241) success |
| 2. 컨트롤러 리네임+재핀 | Archright/.github **#226** | `git mv` admission-gate.yml → admission-gate-v2.yml (**R100 바이트 동일**, `name: admission-gate` 유지 — publisher 트리거 필터·rearm 런 해석이 이름 기반이라 무영향) + certificate-mint 핀 `7072f9382` → `9aaee76f`(2곳) + pin-promotion-gate 헤더 주석 갱신 | **MERGED 06:56:09Z, H_v2 `5bfc911448a56d3e600aa06552291fb405898a46`** — pin-promotion-gate (DEBT#473) pass, "PINNED … blob f2ad3b03 (manifest == TWS, 3-way binding verified)" 로그 |
| 3. ruleset PUT | (본 의식) | 25218071: path → v2 + sha → H_v2 — 빈-큐 창 + 20303214 mq 동결 하 실행 | 아래 기록 |

PINNED 사전 검증: `manifest.productionExecutionPin == TWS.trustedAdmissionWorkflowSha == f2ad3b03` ∧ `blob(admission-check.yml@9aaee76f) == f2ad3b03` — 핀 커밋이 승격 에포크 내부에 존재.

## 의식 (빈-큐 창, 2026-10-16 07:31Z)

| 단계 | 관측 |
|---|---|
| 창 | queue totalCount=0 ∧ admission-gate in-flight=0 (#878·#879 착지 직후 재확인 후 진입) |
| 동결 | 20303214 mq 2→0 PUT·readback **0** |
| PUT | **25218071은 org 소유 ruleset** — `/repos/.../rulesets/25218071` PUT은 404, org 스키마(conditions에 `repository_name: {include: [Axiom]}`)로 `/orgs/Archright/rulesets/25218071` PUT 성공. 본문 = org 뷰 원본, 변경은 workflows[0]의 path·sha 2필드만 |
| readback | `{path: .github/workflows/admission-gate-v2.yml, repository_id: 1182157951, sha: 5bfc911448a56d3e600aa06552291fb405898a46}` — **ref 없음** |
| 해제 | mq 0→2 readback **2** (동결 창 ~2분) |
| 대조군 | 23943917 landing-integrity active·구 sha 무훼손 |
| 태그 | `admission-gen-h6-20261016` → H_v2 (Archright/.github) |

20303214는 repo 소유(/repos/ 엔드포인트), 25218071은 org 소유(/orgs/ 엔드포인트) — 소유 주체별 엔드포인트가 다르다는 실측(첫 PUT 404 → org 뷰 재구성 → 성공).

## 관측 (본 착지 후 기입)

- 관측차량 본 PR(#880)의 게이트 실행은 **새 등록 객체에서 수행됨을 직접 확인**: PR 이벤트 런 **run_number=1**(id 38866640608, path `.github/workflows/admission-gate-v2.yml`, **workflow_id 386419787**) — 러너 넘버가 1부터 재시작 = 신규 등록의 직접 증거. 큐 MG 런 **#2**(id 38867729895) **success 07:46:58Z**, 본 PR 무인 착지.
- 객체 레지스트리 참고: 신규 객체(386419787)도 `/actions/workflows` 목록(22객체)과 직접 GET에서 **404/부재** — 구 고착 객체(367727531)와 같은 레지스트리 비가시성 증상. 그러나 **런 생성·실행은 정상**(구 객체는 런 자체가 부재했던 것이 발화 측 비대칭의 핵심이었다).

## 발화 판정 (FIRE — 2026-10-16 07:47Z)

- MG 런 #2 완결 **07:46:58Z** → **+2초** 뒤 publisher 런 **38869397558 생성·실행(07:47:00Z)**, 가드 로그 런타임 라인:
  `[publish-skip] run path '.github/workflows/admission-gate-v2.yml' != .github/workflows/admission-gate.yml (orchestrator identity)`
  — **이벤트가 새 등록 객체의 게이트 완결에 도달했고, 가드가 실제 런 객체(path=v2)를 검사했다** = 구경로 하드코딩 skip(사전 예고된 1차 발견). 창 내 제2 런 38869463179/38869463297(07:47:39Z, 착지 push 이벤트 귀속).
- **판정: FIRE** — workflow_run 이벤트 전달이 신규 등록에서 복원. G1의 결함(구 객체 367727531의 발화 측 사망)은 경로 리네임으로 우회 확정. 잔여 = publisher 가드 경로 갱신(본 PR) 후 실제 publish 재관측 → S3 사슬(같은 키의 다음 게이트 복원)까지.

## 발화 판정법 (사전 고정)

- publisher(`ci-cache-publisher`)의 트리거는 `workflow_run: workflows: ['*', '!ci-cache-publisher']` — 이름 필터 의존이 이미 제거된 상태이며, 게이트 신원 판정은 인잡 가드(run.path 대조)가 유일 authority.
- 따라서 **발화 신호 = 게이트 완결 후 ~90초 내 생성된 publisher 런의 가드 로그에 `run path '.github/workflows/admission-gate-v2.yml'` 귀속 라인이 존재**하는 것. 구경로 하드코딩(`!= .github/workflows/admission-gate.yml`)으로 skip하더라도 이벤트 도달 자체가 발화 증거(예상 1차 발견) — 이후 publisher 가드 경로 갱신 PR로 실제 publish를 재관측.

## 잔여 (사전 기록)

- `admission-check.yml` 주석 1곳(`(Archright/.github admission-gate.yml): mergeTree = tree(github.sha)`) — 비기능 문서 참조. 수정 시 admission-check.yml blob sha가 변해 epoch 승격 기계(manifest pin == TWS == blob)가 재동기화를 요구하므로 본 실험 범위에서 무변경(주석 1곳, 다음 승격 주기에 정리).
- `certificate-mint.yml` 내 역사 실측 주석(367694978 ≠ 367727531, 2026-09-26) — 역사 기록으로 보존.
