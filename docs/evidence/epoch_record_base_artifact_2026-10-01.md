# CI Epoch Record — admission-check base artifact 완비성 (`build/nimcache` 동봉): Freeze / Record / Tombstone

> **성격**: AGENTS.md §2.5(CI Epoch Cutover Protocol) 단계 1–3 — **FREEZE / RECORD / TOMBSTONE** 기록 문서. 변경 = `.github/workflows/admission-check.yml`의 `admission-check-base-artifacts` upload path 목록에 `build/nimcache` 1줄 추가 (3파일 원자 단위: `admission-check.yml` + `config/trusted_writer_set.json` + `config/policy/epoch_manifest.json`).
> **작성일**: 2026-10-01.
> **작업 브랜치**: `fix/ci-base-nimcache-warm` (linked worktree `Axiom-ci-warmbase`), HEAD == origin/main == freeze 대상 **`827329cbd8a95d614c09aa600cb7385307e66178`** — 2026-10-01 실측, **편집 후에도 불변**(미커밋 상태).
> **편집 후 상태 (2026-10-01, 워킹트리 실측)**: 3파일 편집 **적용 완료 — 미커밋**(커밋/푸시는 부모 에이전트 소관). `git status --short` = 페이로드 3파일 modified + 본 기록 문서 untracked; `git hash-object .github/workflows/admission-check.yml` = **`691517e73a850b958fd496cc560b8b83e8a69016`** — 예측값과 **정확 일치** ✓; 쌍 핀(`trustedAdmissionWorkflowSha`·`productionExecutionPin`) 둘 다 동일 값으로 **3-way 일치** ✓ (상세 §2.2·§6). **커밋 전제**: PR-1(surface v39 등록, §0)이 먼저 main에 착지해야 본 문서를 포함한 커밋이 `check-repository-surface`를 통과한다 — 게이트는 BASE 정책 기준(Makefile:393~399)이라 같은 커밋 내 등록은 효력이 없다.
> **기록 관례**: `docs/evidence/epoch_record_oracle_select_2026-09-30.md`(정본 구조 템플릿) + `docs/evidence/ci_toolchain_scope_2026-09-30.md`(freeze/record/검증 표현) 선례. 별도 ADR 부록 신설 없음(연결은 §4).

---

## §0. 표면(record) 등록 경로 — PR-1 선행 의존 (필수 전제)

**본 문서 경로**: `docs/evidence/epoch_record_base_artifact_2026-10-01.md` — **별도 PR-1이 CONTROLLED 등록 예정**(`config/repository_surface.json` policyVersion 38 → **39**, surface `defaultClass: FROZEN`·`docs/**` glob·`binding: base-policy`).

**실측 (2026-10-01, 모두 read-only)**:

- `config/repository_surface.json` `policyVersion` = **38** (직접 읽음); `"FROZEN": [ …, "docs/**", … ]`(`:184`)·`"defaultClass": "FROZEN"`(`:197`) → base 정책 기준으로 신규 `docs/evidence/*.md` 파일은 FROZEN 클래스, `ADD: FAIL`.
- `make check-repository-surface`(Makefile:393–399)는 **BASE 정책** 기준 판정 — `mb=$(git merge-base origin/main HEAD)` → `git show "$mb:config/repository_surface.json"` → `bin/surface_guard --policy <base>` (Makefile:395-399 실측). 즉 **같은 PR 내 등록은 효력이 없고** PR-1이 먼저 main에 착지해야 한다.
- PR-1 브랜치 `policy/surface-v39-epoch-record`는 로컬 worktree **`Axiom-surface-v39`**에 존재(HEAD `827329cbd`, `git worktree list` 실측), 원격 미푸시(`git ls-remote --heads origin` 0건 실측) — 착지는 별도 순서를 따른다.

**의존성 명시**: PR-1(main 착지) **전에** 본 문서를 포함한 PR이 `check-repository-surface`를 돌리면 **FAIL이 예상 동작**이다(기대값 §6 #7의 주석). 이것은 블로커가 아니라 **순서 의존**이며, 페이로드 3파일(`admission-check.yml`·`trusted_writer_set.json`·`epoch_manifest.json`)은 전부 CONTROLLED MODIFY=PASS이므로 PR-1 착지 후에는 surface 게이트가 통과한다. (v17/v34/v36/v38 2단계 등록 선례 준용.)

---

## 1. Freeze (AGENTS.md §2.5 단계 1)

### 1.1 명명 결정

- `git tag -l 'ci-frozen-*'`(2026-10-01 실측): `ci-frozen-2026-09`, `ci-frozen-2026-09-28`, `ci-frozen-2026-09-30`, **`ci-frozen-2026-10-01`** — **관례 `ci-frozen-YYYY-MM-DD`(annotated) 존재**. 기존 시리즈와 동일 형식으로 `ci-frozen-2026-10-01` 채택(생성 완료 — §1.2).

### 1.2 태그 (전 필드 확정 — 초안의 PENDING 해소)

| 항목 | 값 |
|---|---|
| freeze tag | **`ci-frozen-2026-10-01`** (annotated) |
| 태그 타입 | annotated — `git cat-file -t ci-frozen-2026-10-01` = `tag` ✓ |
| tag object | **`39352ea9bc10832e78ba4d3aeb222179b3d154bc`** (`git rev-parse ci-frozen-2026-10-01` 실측) |
| freeze 대상 | origin/main == HEAD == **`827329cbd8a95d614c09aa600cb7385307e66178`** (`git rev-parse origin/main`·`git rev-parse HEAD` 실측; commit subject "Merge pull request #413 from Archright/docs/identity-acceptance-judgment") |
| 실측 검증 | `git rev-parse ci-frozen-2026-10-01^{commit}` == `827329cbd8a95d614c09aa600cb7385307e66178` == `git rev-parse origin/main` — **일치 ✓** |
| push | **아니오 — 로컬 전용** (`git ls-remote --tags origin`에서 `ci-frozen-2026-10-01` 매칭 **0건** 실측) |
| 태그 메시지(실측) | `forensic baseline: pre-base-nimcache CI state (CI Epoch Cutover for admission-check base nimcache completeness). origin/main 827329cbd8a95d614c09aa600cb7385307e66178. Local only, not pushed.` (`git cat-file -p` 실측 — 초안의 제안 문구와 다르므로 **실측 문구를 정본으로 기록**) |

---

## 2. Record (AGENTS.md §2.5 단계 2)

### 2.1 현행 CI epoch의 실행 정의 — 워크플로 blob sha (@freeze tip 827329cbd, `git rev-parse HEAD:<path>` 실측)

| 파일 | blob sha | 역할 |
|---|---|---|
| `.github/workflows/admission-check.yml` | `fa57673341a4bcb12bdc3785bc75d4caf7d0080c` | **핀 엔진(G2a 대상)** — workload: build-base-artifacts → admission-check(job2 GATE A) DAG; SL-01/03/05/08 소유 |
| `.github/workflows/certificate-mint.yml` | `04bfd3491a0bdbeb45f76b50e67314b73c11c806` | 비핀 엔진 — mint 발행 authority |
| `.github/workflows/runner-pool-acceptance.yml` | `7b9af52ce7c956035a23119a990385e7b37c6194` | 비핀 엔진 — B-페이로드 save-side(`ci-bootstrap-artifacts` 9-path, :581-589) |

변경 대상 step(2026-10-01 직접 읽음·`cat -A` 실측) — `.github/workflows/admission-check.yml` `[build] Upload base-built artifacts`: `name: admission-check-base-artifacts`, path 4줄(`bin/ax`, `bin/install_ax_cas`, `proofs/.lake/build/bin/ircheck`, `manifest.txt`(:321, 12-space 들여쓰기)), `if-no-files-found: error`. **변경 = `manifest.txt` 줄 다음에 12-space 들여쓰기 + `build/nimcache` 1줄 삽입** (5번째 path 줄) — **적용 완료**: 편집 후 워킹트리 실측(`cat -A`)에서 `build/nimcache`가 5번째 path 줄(12-space, `manifest.txt` 다음, `if-no-files-found: error` 앞)로 존재(§2.2·§6 #3).

### 2.2 repo twin pin + 신규 blob sha (독립 재검증 완료)

- **변경 전(freeze tip 기준) 값** (직접 읽음): `config/trusted_writer_set.json:41` `"trustedAdmissionWorkflowSha": "fa57673341a4bcb12bdc3785bc75d4caf7d0080c"`; `config/policy/epoch_manifest.json:9` `"productionExecutionPin": "fa57673341a4bcb12bdc3785bc75d4caf7d0080c"` — **일치 ✓** (freeze tip에서는 `git rev-parse HEAD:.github/workflows/admission-check.yml` == `fa57673341…` — **핀 == freeze blob 실측 일치**; mint witness가 비교하는 admission blob@B 핀 == manifest 실행 핀). **현재 워킹트리의 핀은 신규 값** — 아래 "편집 후" 실측을 정본으로 한다.
- 신규 blob sha — **편집 전 예측(독립 재검증)과 편집 후 실측 모두 확정**: ① 예측 — 컨트롤로 HEAD blob 추출(`git show HEAD:.github/workflows/admission-check.yml` → `/tmp/acw_head_blob.yml`) 후 `git hash-object` = `fa57673341a4bcb12bdc3785bc75d4caf7d0080c` **일치 ✓**; `awk`로 :321(`manifest.txt`) 뒤 12-space `build/nimcache` 삽입(`diff` 결과 `321a322` 1줄 추가뿐 — 바이트-정확) 후 `git hash-object /tmp/acw_new.yml` = **`691517e73a850b958fd496cc560b8b83e8a69016`**. ② **편집 후 실측 (2026-10-01, 워킹트리)**: `git hash-object .github/workflows/admission-check.yml` = **`691517e73a850b958fd496cc560b8b83e8a69016`** — **예측값과 정확 일치 ✓**; 컨트롤 재현(`git rev-parse HEAD:…` = `fa576733…` — HEAD 불변) ✓. 값은 content-addressed이므로 커밋 직전 1바이트라도 바뀌면 달라진다 — `axiom-gate commit` 경로에서 재확인된다.
- **쌍 핀 갱신 완료 (워킹트리 실측, 미커밋)**: `trustedAdmissionWorkflowSha`(:41) = `691517e73a850b958fd496cc560b8b83e8a69016`, `productionExecutionPin`(:9) = 동일 값 — `git hash-object`와 **3-way 일치 ✓** (§6 #4). `trustedCheckerTreeClosure`는 **무변경**(구성원 무변경 — ROTATION 절차 대상 아님).
- epoch 상태 필드 **전부 무변경** (2026-10-01 `config/policy/epoch_manifest.json` 직접 읽음): `ciEpochId: "N+6"` · `implementedSlices: [SL-08, SL-01, SL-03, SL-04, SL-12, SL-10]` · `notYetImplementedSlices: [SL-02, SL-05, SL-06, SL-0713, SL-09, SL-11, SL-14..SL-17]` · `mode: "ci-migration"` — 슬라이스 승격 없음(§4).

### 2.3 artifact / authority binding

| binding | 값 | 출처(2026-10-01 read-only 실측) |
|---|---|---|
| artifact | `admission-check-base-artifacts` (build-base-artifacts job 업로드, admission-check.yml:316; 소비자 = job2 `[check] Download base-built artifacts` :435 → `[check] Verify artifact manifest` build_sha==B :443 이하; runner-pool의 `candidate-arm64`/`ci-bootstrap-artifacts` 소비 경로와는 별개) | 직접 읽음 |
| required check | `admission-check` @ workflowId **365692388** — `gh api repos/Archright/Axiom/actions/workflows/admission-check.yml` → `{"id":365692388,"name":"admission-check","state":"active"}`; main ruleset **20303214** required_status_checks = `admission-check` (integration_id 15368, `gh api .../rulesets/20303214` 실측) | gh api |
| repo rulesets | main **20303214**, artifact-hygiene **23969951**, cas-probe-scratch **23916707**, execution-surface-create **23967915**, + org 규칙 2종(아래) (초안 실측 인용 — 전부 `enforcement:active`) | gh api (초안) |
| org rulesets | `axiom-admission-gate` **24233738** — workflows 규칙 `admission-gate.yml @ ref:main`(repository_id 1182157951, **sha-less ref 핀** — 구 24041674의 sha PUT 500 버그 대체, `epoch_record_oracle_select §8.3` 선례), `landing-integrity` **23943917** (초안 실측 인용) | gh api (초안) |
| org callee pins (초안 실측 인용 — Archright/.github `admission-gate.yml` base64 디코드) | **:94** admission-check.yml `@4b7719e15382405c641f79c2f95db32218c90bcf` · **:120/:154** certificate-mint.yml `@4b7719e15…`(동일) · **:179** runner-pool-acceptance.yml `@48cb16ab2fcc78011f178ed7388cde64046e4d75` (org PR #37 선행 회전 완료) | gh api (초안) |
| cache identity (점유 사실) | 현재 base 캐시 키 **이미 점유**: B 키 version `c0438c1375be91f572fabf9274f8a410747e60f11bf0f189c5731c9c782c1c06` (예: `axiom-b-73b467b7…` 2026-09-30T20:58:09Z, `gh api repos/Archright/Axiom/actions/caches` 실측 — total_count 27) → **효과는 다음 unseeded base sha부터 시작** (Phase 0 측정 인용) | gh api (초안) |
| trust layer | Trust Layer **무변경**: build_sha==B 매니페스트 검증, B/H identity 재유도, fail-closed verdict 그대로. 변경 = Execution Adapter의 artifact payload 완비성만(§2.6: 신뢰 사실과 실행 방법 분리). `build/nimcache`는 이미 B-페이로드 9-path의 구성원(action.yml:59 "Contents: build/nimcache, .axiom/cache, proofs/.lake, proofs/build + the 4 ci-compile binaries", runner-pool-acceptance.yml:584) — 신규 권한·신규 writer **없음** | 직접 읽음 |

### 2.4 Rollback reference

- rollback 기준 = freeze tag **`ci-frozen-2026-10-01`** (immutable baseline — §2.5에 따라 **삭제 금지**).
- 재-핀 복원 대상(**변경 전 = freeze 값**): `trustedAdmissionWorkflowSha`/`productionExecutionPin` → `fa57673341a4bcb12bdc3785bc75d4caf7d0080c`(현재 워킹트리는 신규 값 `691517e73a…` — 미커밋 상태에서의 rollback은 3개 페이로드 파일 복원과 동일 결과); admission-check.yml blob → freeze blob; org callee :94 → `@4b7719e15382405c641f79c2f95db32218c90bcf`(회전 후라면 이전 값으로 복원).

---

## 3. Tombstone (AGENTS.md §2.5 단계 3)

**대상: N/A — 본 변경은 폐기되는 CI 구현이 없다** (폐기되는 job/조건식/게이트 없음; upload path 목록의 페이로드 완비성 추가 1줄 — "무언가를 종료"하지 않음). 프로토콜이 형식을 요구하므로 5점 형식으로 명시한다 — **5점 전부 N/A이며 사유를 병기한다**:

1. 본 Tombstone은 **게이트 우회(break-glass)가 아니다** — N/A(폐기 대상 없음). 실행 권한·검증 의무 제거 없음: verdict 체인(`admission-check` required check, org gate, mint) 무변경.
2. 본 Tombstone은 **면제(waiver)가 아니다** — N/A. `config/decision_binding.waiver.*` 등록 없음(2026-10-01 기준 본 변경 관련 면제 0건).
3. 본 Tombstone은 **required-check 제거가 아니다** — N/A. `admission-check`(ruleset 20303214)·org required workflow·verdict 체인 **무변경 유지**.
4. 본 Tombstone은 **검증 면제를 의미하지 않는다** — N/A. 검증 의미 변경 없음(빌드/검증 계약 전부 그대로; 수용 기준 §6).
5. Tombstone은 역사적 폐기 기록이며 실행·검증 권한을 갖지 않는다(AGENTS.md §2.5 Mandatory Invariants) — N/A이면서 이 원칙 자체는 본 기록에 준용된다.

---

## 4. ADR·레지스트리 연결

| 연결 대상 | 내용 |
|---|---|
| `docs/adr/0025-gateway-landing-authority.md` **Amendment B (2026-09-29)** | 퍼블리셔 권위 근거: B-cache 단일 씨딩 writer = `ci-cache-publisher`(workflow_run, ADR-0025 Amendment B §2) — 9-path B-페이로드(list 내 `build/nimcache` 포함)의 유일 writer. 본 변경은 이 권위를 **소비만** 함(admission artifact가 B-페이로드 구성원을 추가 동봉 — 신규 authority/경쟁 writer 없음, §2.6 AUTHORITY 6문항: 기존 산출물 소비, 재생성 없음) |
| `docs/adr/0022-admission-artifact-authority.md` §4–5 | `trustedAdmissionWorkflowSha` = blob-addressed(git hash-object), admission-check.yml과 원자 갱신 — 본 3파일 단위가 ADR-0022 §5의 정본 구현 |
| `src/gate/slice_catalog.nim` `EngineMappingFiles`(:302, 2026-10-01 grep 실측) | **무변경**(3종 그대로) → **G1 비발화**; layer-1 G1 대상(SliceCatalog+manifest slice 필드) 무터치 확인 |
| `tools/ci/epoch_transaction_gate.nim` G2a | 핀 엔진(admission-check.yml) 변경 = `{TWS record path, manifest pin VALUE}` 동일 커밋 전진 필수(헤더:15-35·:576-592, 초안 실측 인용) — 정확히 파일 2·3에 대응. G2b 경로(슬라이스 승격/repair) 불요 |
| `config/policy/epoch_manifest.json` | `productionExecutionPin` 필드만 갱신(슬라이스·mode 필드 무변경 — §2.2) |
| `config/repository_surface.json` | §0 — 신규 기록 문서의 **PR-1 등록(v39) 선행 필수**(FROZEN ADD=FAIL, base-policy binding) |

---

## 5. DEBT 등록 요약

**신규 DEBT 등록 없음 — 명시적 근거**: 본 변경은 순수 페이로드 완비성 수정(artifact path 목록에 기존 B-페이로드 구성원 1개 추가). ① 동작 의미 변경 없음(scope 게이트 발화 조건·selector·verdict 전부 무변경 — `scope_*` if: 조건 수와 `[slice-engine]` step 수 불변, G2b (b) 표면 비감소 충족) ② 새 quirk 없음(§0.5b Quirk Mandate 대상 아님 — 엔진 pin 편집과 twin pin 회전은 문서화된 정본 경로 ADR-0022 §5/G2a) ③ 추적 마커 제거 없음 ④ Theater 의심 없음(항상 통과·실패 삼킴·죽은 게이트 어디에도 해당 없음 — 추가는 검증 강화 방향). 레지스트리 churn 회피(`epoch_record_oracle_select §7`의 DEBT#471 비등록 선례 준용).

---

## 6. 검증 / Completion Evidence (단계 6 Local/Targeted — 기대값 확정, 미실측 항목은 착지 PR에서 갱신)

| # | 명령 | 기대 | 실측 (2026-10-01) |
|---|---|---|---|
| 1 | `git rev-parse ci-frozen-2026-10-01^{commit}` | `827329cbd8a95d614c09aa600cb7385307e66178` | **✓** (== `git rev-parse origin/main` == HEAD) |
| 2 | `git rev-parse ci-frozen-2026-10-01:.github/workflows/admission-check.yml` | `fa57673341…`(freeze blob) | **✓** HEAD 기준 blob 일치 실측; 태그 경유 동일(태그가 freeze tip을 가리킴 — #1) |
| 3 | `git hash-object .github/workflows/admission-check.yml` (편집 후) | `691517e73a850b958fd496cc560b8b83e8a69016` | **✓ 확정 (워킹트리 실측)**: 편집 후 실측 = `691517e73a850b958fd496cc560b8b83e8a69016` — 시뮬레이션 예측값과 **정확 일치**; 컨트롤(`git rev-parse HEAD:…` = `fa57673341…`, HEAD 불변) 재현 ✓ (§2.2). 커밋 시 `axiom-gate commit`이 재확인 |
| 4 | 쌍 핀 등식: `git hash-object …` == `jq .trustedAdmissionWorkflowSha config/trusted_writer_set.json` == `jq .productionExecutionPin config/policy/epoch_manifest.json` | 3-way 일치 | **✓ 워킹트리 확정**: hash-object == TWS(:41) == manifest(:9) == `691517e73a850b958fd496cc560b8b83e8a69016` (2026-10-01 실측). freeze 시점 3-way `fa57673341…` ✓ 별도 실측. **커밋 후 상태는 `axiom-gate commit`으로 commit-confirmed** |
| 5 | `make gate-binaries` | PASS — pre-push liveness 6종 + gate-runners 최신(Makefile:754) | **△ (2026-10-01 기록 갱신 시점 재실측 — `Axiom-j3-probe` worktree)**: liveness 6종(`debt_engine`·`check_nim_theater`·`doc_path_validator`·`proof_unit_consistency_gate`·`proof_reconcile_gate`·`epoch_transaction_gate` — `make bin/…` 규칙 fresh compile) **PASS**; `gate-runners`(`src/gate/runners` 100종 `build_all_gates --release`)는 컴파일-타임 `bin/ax` 존재 자기검증(`[Integrity Violation] bin/ax is missing` — SourceCoherence 계열)이 선행이라 본 worktree(미빌드 bin/ax)에서 81종 FAIL — **빌드 순서 의존(CI 경로 = `make ci-bootstrap`이 bin/ax를 선행 빌드)이며 회귀 아님**; 착지 당시(PR-415 worktree)의 1차 실행 기록은 보존되지 않아 원-런 값은 검증 불가 — 재실측만 기록 |
| 6 | `make check-epoch-transaction` (Makefile:281) | **PASS 예상** — G2a 충족(admission-check.yml 변경 + TWS + manifest pin 동일 커밋 전진; EngineMappingFiles·슬라이스 필드 무변경 → G1/G2b 판정 대상 아님). 부분 갱신(2/3만)이면 `EPOCH_TRANSACTION_INCOMPLETE` — 그 경우 FAIL이 **정상 동작**(원자성 강제) | **✓ (2026-10-01 재실측 — 기록 갱신 커밋 `2c701ca71` 상태)**: `MODE: --diff 373220ede… HEAD` → `PASS  pin consistency — base leg @base + new-state 3-way equality @HEAD` → `EXIT 0: epoch promotion transaction binding consistent — fail-closed PASS` — **후속 커밋(프로브 PR, blob `7539c163…` 전진)의 G2a 3-way도 동일 출력으로 재확인됨 (#8)** |
| 7 | `make check-repository-surface` (Makefile:393) | PASS — 페이로드 3파일 CONTROLLED MODIFY=PASS | **✓ (2026-10-01 재실측)**: PR-1(v39) 착지 후 base-policy **v42**(직접 실측) 기준 — 기록 갱신 커밋 `2c701ca71`의 diff 5파일(`admission-check.yml`·`ci-cache-publisher.yml`·epoch 기록·`trusted_writer_set.json`·`epoch_manifest.json`) 전부 CONTROLLED MODIFY=PASS — **#8의 `make push-admissibility` 전체 PASS로 확정** |
| 8 | `make push-admissibility` — `PUSH_ADMISSIBILITY_GATES`(Makefile:54) 10개: check-debt check-nim-theater doc-path-validator check-determinism check-proof-unit-consistency check-proof-unit-reconcile check-repository-surface check-git-access check-workflow-shell-syntax check-epoch-transaction | 전체 PASS | **✓ (2026-10-01 재실측 — 커밋 `2c701ca71` 기준, exit 0)**: `PASS: check-debt check-nim-theater doc-path-validator check-determinism check-proof-unit-consistency check-proof-unit-reconcile check-repository-surface check-git-access check-workflow-shell-syntax check-epoch-transaction green (snapshot)` — 개별 출력: `validate_workflow_shell: PASS — run blocks checked=110 failures=0`(프로브 run 블록 포함), `git_access_scan: PASS — 0 history/parent access`, `Toolchain pins OK`, `✅ debt_registry_open PASS (projection=42 == ledger 42)`·`closed PASS (projection=159 == ledger 159)`, `PASS: no theater patterns detected`, `✅ A0′ consistency gate PASS`, `✅ A3 reconcile gate static PASS`, `epoch transaction gate PASS (4-way)` |
| 9 | `make check-push-admissibility-integrity` (Makefile:432 — subset ⊆ GATES ∪ push-only) | PASS | **✓ (2026-10-01 재실측)**: `✅ push-admissibility subset is within the known gate universe (+ push-only surface/git-access/workflow-shell-syntax)` — exit 0 |
| 10 | 9-path 목록 불변성 + **digest 정정**(§6 해설) | 항목·순서 일치 유지 — 정규화 diff `CACHE_VERSION_INVARIANT_OK_NORMALIZED` | **✓** (아래 해설 — 2026-10-01 편집 후 워킹트리에서 재실행, 동일 출력) |

**§6 #10 해설 — 캐시-버전 불변성 검사 (digest 주장 정정)**: 초안이 인용한 digest **`0bc2a8a2a5eb4e85…`는 재현 불가로 폐기** — 두 차례 독립 조사에서 어떤 직렬화 변형으로도 재현되지 않았고 저장소 어디에도 존재하지 않는다(거짓 주장). 대신 **명령으로 기계 검증 가능한 불변식**을 정본으로 기록한다:

- B-페이로드 9-path 목록 3개 사이트 (2026-10-01 `cat -A` 바이트 실측):
  - `ci-cache-publisher.yml:256-264` (lane save) ≡ `:416-424` (base save) — **바이트-동일**(12-space 들여쓰기)
  - `.github/actions/setup-axiom-toolchain/action.yml:295-303` (b-restore) — **항목·순서 내용-동일**, 들여쓰기만 2칸 얕음(10-space, YAML 중첩 레벨 차이) — 바이트-동일은 **아님**
- 기계 검사 실측 출력:
  - 원문(바이트) diff 명령(`diff <(sed -n '256,264p' ci-cache-publisher.yml) <(sed -n '416,424p' ci-cache-publisher.yml) && diff <(…256,264…) <(sed -n '295,303p' action.yml)`) — **`CACHE_VERSION_INVARIANT_OK` 미출력**: 첫 diff(퍼블리셔 2사이트)는 통과, 두 번째 diff는 action.yml 들여쓰기(10 vs 12-space)로 실패. 즉 "3개 목록 바이트-동일"이라는 전제는 **사실과 다름** — GitHub cache version 유도 입력은 path **목록 내용**(공백 무관)이므로 실질 불변성은 성립한다.
  - 공백-정규화 diff 명령(아래) — `sed 's/^ *//'` 후 3사이트 diff → **`CACHE_VERSION_INVARIANT_OK_NORMALIZED` 출력 ✓** (2026-10-01 실측; **편집 후 워킹트리에서 재실행 — 동일 출력**, 9-path 사이트는 무접촉 확인)
- GitHub-관찰 캐시 version 실측 인용(`ci-cache-publisher.yml:64-66·401-403` 직접 읽음): 9-path = **`c0438c13…`**, 4-path = **`6a4c304a…`** — 레포에 기록된 유일한 version 관측값.
- 불변 근거: 본 변경은 9-path 목록의 구성원을 하나도 바꾸지 않는다(`build/nimcache`는 이미 9-path의 6번째 구성원 — admission artifact에 *추가 동봉*만) → B 캐시 키 유도 입력(트리 OID + 레시피 + A-지문, action.yml B-layer 계약) 무변화 → version `c0438c13…` 유지. **효과 시작 조건**: 현재 base sha의 B 키가 이미 점유(§2.3)이므로 변경 실효는 **다음 unseeded base sha**부터(Phase 0 인용).

**금지-편집 4종 검사 (본 변경이 접촉하지 않음을 기계 확인)**:

1. **`manifest.txt` sha256 루프의 3개 바이너리 유지** — `admission-check.yml:306` `for f in bin/ax bin/install_ax_cas proofs/.lake/build/bin/ircheck` (직접 읽음; :300-310 매니페스트 생성 step) — 본 변경(:321 삽입)은 이 step에 접촉하지 않음.
2. **9-path 3개 사이트 무접촉** — 위 정규화 diff로 기계 검증 (`CACHE_VERSION_INVARIANT_OK_NORMALIZED`).
3. **`action.yml` 무접촉** — `action.yml:163`의 `script_hash="$(sha256sum .github/actions/setup-axiom-toolchain/action.yml nimble.lock …)"`이 **action.yml 자신을 해시 입력에 포함**하고, `:173` `a_key="${a_prefix}${RUNNER_OS}-${gcc_fp}-${glibc_fp}-${script_hash}"`에 직결 → action.yml 1바이트 변경 = **모든 A/B 캐시 항목 회전**(직접 읽음). 접촉 금지가 원자 단위의 경계가 된다.
4. **`src/gate/slice_catalog.nim` 무접촉** — `EngineMappingFiles`(:302, grep 실측) 포함 slice 카탈로그 변경 = **G1 발화**; 무터치 확인 → G1 비발화(§4).

**Phase 0 측정 컨텍스트 (재측정 금지 — 인용, 초안 실측)**: 4-way baseline `PR n=32, median 390s, spread 200` / `merge_group n=28, median 374s, spread 145` (`/tmp/baseline_0930_final.tsv` 수집 시점 값). ⚠️ 각주: 추가 수집분으로 TSV는 63행(n=34 PR median 386.5 / n=29 MG median 377.0)까지 성장 — 본 기록의 기준선은 **Phase 0 수집값**이다. 임계 경로 귀속: base compile `criticalPathContribution = 32s(PR)/109s(MG)`, cushion C로 캡; `ci-bootstrap` compile은 기여 0으로 실격. 국소 측정: warm B-HIT 중복 C-compile = **0**; Σ97.35s 국소 빌드 분해 = front **28%** / C **1%** / link **70%**.

---

## 7. org callee pin 회전 — 효과-선행조건 (repo PR merge는 차단하지 않음 — 분류 확정)

| 항목 | 값 |
|---|---|
| 분류 | **효과(effect)-선행조건 — repo 병합 차단 아님**. 근거 ① required check는 **workflowId 365692388에 path-bound**(`config/policy/merge_admission.json:6-11` 실측 — content-bound가 아님) ② 선례 **PR #391**: `state=MERGED`·`mergedAt=2026-09-30T06:59:31Z`(`gh pr view 391 --json state,mergedAt,mergeCommit` 실측) — org 회전(`.github` #37, 07:15, `epoch_record_oracle_select §8.1` 인용) **이전에 repo 머지 완료**. 즉 회전 미착지가 repo PR 착지를 막지 않지만, 신규 아티팩트 페이로드의 실효는 org gate가 신규 blob을 호출하는 시점부터다 |
| 대상 | `Archright/.github` `.github/workflows/admission-gate.yml` **:94** — `uses: Archright/Axiom/.github/workflows/admission-check.yml@4b7719e15382405c641f79c2f95db32218c90bcf` → **`@20aa15873f6c9d27a91a1b77829471ae0ce4af72`** (**완료** — org PR **#38** `rotate/admission-check-pin-20aa15873`: head `fc1353cb`, merge `43125c166627b708646de38d490286dc6a7b849b`, mergedAt `2026-10-01T04:15:29Z`; `gh api repos/Archright/.github/contents/.github/workflows/admission-gate.yml?ref=main` base64 디코드 — **:94 실측 = `@20aa15873f6c9d27a91a1b77829471ae0ce4af72`**, 2026-10-01) |
| 미회전 범위 | :120/:154 certificate-mint `@4b7719e15…`, :179 runner-pool `@48cb16ab2…` — **그대로** (해당 blob 무변경) — **재실측 (2026-10-01, org main 디코드)**: :120/:154 `certificate-mint.yml@4b7719e15382405c641f79c2f95db32218c90bcf`·:179 `runner-pool-acceptance.yml@48cb16ab2fcc78011f178ed7388cde64046e4d75` — **불변 확인 ✓** |
| ruleset | org ruleset **24233738**은 `admission-gate.yml @ref:main` sha-less 핀(§2.3) → **ruleset PUT 불요** (구 24041674 era와 달리 callee 회전 = 파일 편집 1건) |
| 선례 | org PR **#37** (`epoch_record_oracle_select §8.1` — gateway callee `runner-pool@4b7719e1 → 48cb16ab2`) |
| 기록된 교훈 | `epoch_record_oracle_select §8.2` — "runner-pool 변경이 pin에 갡힘 → 조직 SHA **회전 선행 후 재관측**": pin 회전 전 착지/실행은 구 버전 callee 호출로 신규 동작 미발화(런 36682252299 run-0 블로커 실증 `mode=selected{W8}`·`oracleEvidence=null`) → 본 변경도 **회전 → 재관측 런 1건**으로 단계 9 수용(landing run에서 `build/nimcache`가 아티팩트에 존재 + 소비자 warm 경로 확인) |
| landing 경로 | 본 변경은 **trustSurface 구성원 2개**(`.github/workflows/admission-check.yml`·`config/trusted_writer_set.json` — `merge_admission.json` trustSurface 실측, v1.9.0)를 터치 → **auto-merge 거부** → 표준 **native-MERGE 경로**로 착지(AGENTS.md §2 — GitHub 네이티브 MERGE 커밋) |

절차: `.github` PR 병렬 준비 → repo 착지(native MERGE) → org 회전(`:94`) → 재관측 런 1건(단계 9). **완료 (2026-10-01)**: repo MERGE(PR #415, `20aa15873`, 04:00:09Z) → org 회전(#38, `43125c16`, 04:15:29Z) → 재관측 런 §8.

---

## 8. Production Acceptance (단계 9 — 착지 후 코디네이터 append 자리)

**착지 후 기입 필드 — 전부 확정 (2026-10-01 실측)**:

| 필드 | 값 | 증거 명령 |
|---|---|---|
| repo PR | **#415** `fix(ci): base-artifact에 build/nimcache 포함 — base 콜드 컴파일 warm 전환 (CI Epoch Cutover)` — head `874a0b482ab86e720e890770eae87d9016865771` | `gh pr view 415 --json state,mergedAt,mergeCommit` → `{"state":"MERGED","mergedAt":"2026-10-01T04:00:09Z","mergeCommit":{"oid":"20aa15873f6c9d27a91a1b77829471ae0ce4af72"}}` |
| merge commit | `20aa15873f6c9d27a91a1b77829471ae0ce4af72` (native MERGE, parents `0530d6b55` + `874a0b482`) | `git log --format="%H %P %s" -1 20aa15873` |
| org 회전 PR | **Archright/.github #38** `rotate/admission-check-pin-20aa15873` — merge `43125c166627b708646de38d490286dc6a7b849b`, `2026-10-01T04:15:29Z` — org main :94 = `@20aa15873f6c9d27a91a1b77829471ae0ce4af72` | `gh api repos/Archright/.github/pulls/38 --jq '{state, merge_commit_sha, merged_at}'` + contents API base64 디코드 |
| 재관측 런 | **36814420847** (`admission-gate`, event=**merge_group**, queue commit `9d1a8cff…` — pr-418, `status=completed`, `conclusion=success`, 04:17:32→04:24:18Z) — **회전 후 신규 blob 최초 실행 런** | `gh api repos/Archright/Axiom/actions/runs/36814420847 --jq '{id,event,head_sha,status,conclusion,created_at,updated_at}'` |
| 아티팩트 존재 증거 | `admission-check-base-artifacts` **11140954008** = **84,035,134 B**, `build/nimcache` **1,571 entries** (다운로드+카운트 실측) | `gh api repos/Archright/Axiom/actions/artifacts/…/zip` → unzip → `find build/nimcache -type f \| wc -l` = **1571** |
| BEFORE 대비 | PR-415 merge_group 런 **36812543825** (queue commit `20aa15873`, 성공, 03:53:04→04:00:05Z) 아티팩트 **11140466146** = **38,149,683 B** — `build/nimcache` **0 entries** (아티팩트에 build/ 자체 부재) — **0 → 1571 전후 대비 확정** | 동일 다운로드+카운트 실측 (`find … = 0`) |
| 후속 일관성 | 회전 후 7개 런 아티팩트 전부 84,0xx,xxx B대 (11140954008=84,035,134 · 04:25:13=84,038,985 · 04:35:41=84,048,665 · 04:42:57=84,039,508 · 06:00:11=84,040,162 · 06:07:33=84,040,185 · 06:31:12=84,048,742 · 06:39:36=84,039,714) — 신규 blob 재현성 | `gh api …/actions/artifacts?per_page=100` 실측 |
| warm 소비자 경로 | POST 런 artifact의 `build/nimcache` 존재(1,571) — 소비자(job2 b-restore 9-path, action.yml:295-303) 복원 대상 일치; 소비 런에서 nimcache 포함 페이로드 업로드 지속 | 위 아티팩트 실측 (소비 단계 로그 원-런은 보존되지 않아 **재관측 런의 artifact 존재로 갈음** — §8 로그 세부는 검증 불가로 명시) |

**관측 3층 (AGENTS.md §2.3 증거 귀속 블록 — PR #415)**:

- **L1 (pr-head 투영)**: `gh api repos/Archright/Axiom/commits/874a0b482ab86e720e890770eae87d9016865771/check-runs` → `{"name":"admission-check","status":"completed","conclusion":"success","started_at":"2026-10-01T03:49:07Z","completed_at":"2026-10-01T03:49:10Z"}` — ruleset 20303214 required_status_checks(`admission-check`) 컨텍스트와 교차 확인(§2.3). **context = pr-head (874a0b482)**.
- **L2 (결정 층·큐)**: PR-415는 merge queue 경유 착지 — merge_group 런 36812543825(queue commit `20aa15873`, branch `gh-readonly-queue/main/pr-415-0530d6b5…`) success(04:00:05Z) 직후 04:00:09Z MERGE 종결. **context = merge_group (20aa15873) — PR-head check-run과 구분 귀속**.
- **L3 (종결)**: `gh pr view 415 --json state,mergedAt,mergeCommit` → `state==MERGED` ∧ `mergeCommit.oid==20aa15873…` (위 표).
- 관측 원문(JSON)은 위 각 행의 명령 출력; UTC 타임스탬프 = 2026-10-01 (04:00:09Z 착지 / 04:15:29Z 회전 / 04:22:11Z 재관측 아티팩트).

**후속 epoch 트랜잭션 (2026-10-01 — 이 기록 갱신 PR `fix/j3-nimcache-probe`)**: admission-check.yml에 nimcache 기능 프로브 스텝 추가(J3 §3.4)로 blob이 `7539c1638f9e4c3023867f608b9b64c1f2714c06`으로 전진 — G2a 원자 단위로 `trustedAdmissionWorkflowSha`·`productionExecutionPin` 동일 커밋 전진(3-way 재일치). **org callee :94 재회전(`@<해당 PR merge sha>`) 필요** — §7 절차와 동일(회전 전에는 org gate가 기존 blob `20aa15873…` 호출 — 신규 프로브는 회전 후 발효).

**기입 시 사용할 정확한 명령 (미리 지정)**:

- L1 상태 판정(정본, REST): `gh api repos/Archright/Axiom/commits/<head_sha>/check-runs` → `name=="admission-check" ∧ status=="completed" ∧ conclusion=="success"` (ruleset 20303214 required_status_checks 컨텍스트와 교차 확인)
- L1 adapter 완료 대기: `gh pr checks <PR> --required --watch --interval 30` → exit 0
- L2 결정 층·큐 상태: `gh api graphql -f query='query{repository(owner:"Archright",name:"Axiom"){mergeQueue{entries(first:5){nodes{state position pullRequest{number}}}}}}'` → entry state 관측
- L3 종결: `gh pr view <PR> --json state,mergedAt,mergeCommit` → `state=="MERGED"` ∧ `mergeCommit.oid` 존재
- 재관측 런: `gh run watch <RUN_ID> --exit-status --interval 30` (완료 후 로그/아티팩트는 `gh run view --log`/`gh run download`)

롤백 참조: §2.4.

---

## 부록: 본 기록에 사용된 실측 명령 요약 (2026-10-01, 전부 read-only)

`git branch --show-current` / `git rev-parse HEAD`·`origin/main` / `git cat-file -t ci-frozen-2026-10-01`(=`tag`) / `git rev-parse ci-frozen-2026-10-01`(=`39352ea9bc…`) / `git rev-parse ci-frozen-2026-10-01^{commit}` / `git cat-file -p ci-frozen-2026-10-01`(태그 메시지) / `git tag -l 'ci-frozen-*'` / `git ls-remote --tags origin`(로컬 전용 확인) / `git ls-remote --heads origin`(v39 미푸시 확인) / `git worktree list`(Axiom-surface-v39 존재) / `git rev-parse HEAD:.github/workflows/{admission-check,certificate-mint,runner-pool-acceptance}.yml` / `git hash-object /tmp/acw_head_blob.yml`·`/tmp/acw_new.yml`(컨트롤+신규 sha 예측) / `git show HEAD:.github/workflows/admission-check.yml`(바이트-정확 편집 재구성) / `diff`+`awk` 삽입 검증(`321a322` 1줄) / `cat -A`(들여쓰기 바이트 검증) / 9-path diff·정규화 diff(`CACHE_VERSION_INVARIANT_OK_NORMALIZED` — 편집 후 재실행 동일) / **편집 후 실측**: `git status --short`(3 modified + 본 문서 untracked), `git hash-object .github/workflows/admission-check.yml`(=`691517e73a…` — 예측값 일치), `grep trustedAdmissionWorkflowSha`/`cat config/policy/epoch_manifest.json`(쌍 핀 3-way 일치), `sed -n '313,324p' … | cat -A`(삽입 위치 바이트 확인) / `awk` 직접 읽기: ci-cache-publisher.yml:60-70·399-405, admission-check.yml:294-311·312-324, action.yml:155-170·288-305, Makefile:388-404, repository_surface.json:176-200, slice_catalog.nim:302 / `grep` trustSurface·trustedAdmissionWorkflowSha:41 / `gh api repos/Archright/Axiom/actions/workflows/admission-check.yml`(id 365692388) / `gh api repos/Archright/Axiom/rulesets/20303214`(`admission-check` @ integration_id 15368) / `gh pr view 391 --json state,mergedAt,mergeCommit,title`(MERGED 06:59:31Z) — 전부 read-only. 편집 시뮬레이션은 /tmp 작업파일로만 수행(저장소 미기록); 실제 3파일 편집은 선행 에이전트가 적용(본 문서 작성자는 미수행), 커밋/푸시 없음.

**미해결/보류 (부모·코디네이터 소관)**: ① ~~신규 blob sha 재확정~~ → **해소 완료**: 편집 후 실측 `git hash-object .github/workflows/admission-check.yml` = `691517e73a850b958fd496cc560b8b83e8a69016` == 예측값(§2.2, §6 #3); 커밋 시 `axiom-gate commit`이 재확인 ② §6 #5–9 실측 → **착지 후 재실측 완료(§6 — 기록 갱신 PR에서 실행)** ③ PR-1(v39 표면 등록) 착지 — **완료(surface v42, 2026-10-01 실측)** ④ org 회전 PR·재관측 런 id → **해소 완료**: org **#38**(merge `43125c16`, 04:15:29Z) + 재관측 런 **36814420847**(아티팩트 11140954008 = 84,035,134 B, nimcache **1,571** entries — §8).