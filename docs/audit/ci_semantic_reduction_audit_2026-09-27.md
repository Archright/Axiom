# CI Semantic Reduction Audit — 2026-09-27

> **작업 성격**: 감사·분류·삭제 후보 도출 ONLY. 코드/workflow/runner/cache 수정 없음.
>
> **Ultimate Purpose**: 특정 landing candidate SHA에 대해 MUST 16이 성립한다는 결정론적
> 증거를 만들고, 그 결과를 native MERGE authority에 전달하는 데 필요하지 않은 CI 구조를
> 제거 후보로 식별한다.
>
> **판정 기준**: PROOF / IDENTITY / AUTHORITY / POLICY는 기본 보존 검토.
> TRANSPORT / ORCHESTRATION / CONVENIENCE는 존재 이유를 별도로 증명하지 못하면 제거 후보.

---

## Phase 1. Architecture Hard Assumption 추출·분류

분류 규칙 (사용자 지시):

- **MUST** — 요구사항. Axiom 검증 의미·증거·권위·결정론의 성립 조건. CI 요소 제거 판정의 유일한 보존 기준.
- **POLICY** — 다이얼 값. 값 변경은 decision-binding 개정(§0.10)으로만 가능하나 **요구사항이 아니며** 검증·변경 가능한 가정으로 취급한다 (ADR-0023 A1.8(f) "K=8 등 = MUST 아님").
- **IMPLEMENTATION CHOICE** — 구현 선택. Axiom 의미에 기여하지 않으면 변경·제거 가능.
- **UNKNOWN** — 분류 보류. 근거 기록.

### 1.1 MUST (요구사항 — 유일한 보존 기준)

#### A. Identity (SHA/tree/subject 결속)

| ID | 내용 | 근거 |
|---|---|---|
| M-ID-1 | 착지 전 identity 3중 등식 `testedTree == mergeTree == certTree` | `certification_continuity_contract.md` INV-1 |
| M-ID-2 | 착지 = GitHub native MERGE commit shape(parents/tree)로 인증 입력 상속 검증 | INV-2 |
| M-ID-3 | continuity tree 재유도 금지 — parent2 tree OID **대조만** | INV-3 |
| M-ID-4 | conflict/lossy = 인증 거부 (subset 경계 fail-closed) | INV-11 |
| M-ID-5 | mint 경로: H는 data-only input, 실행 주체 아님 | ADR-0025 §4(b) |
| M-ID-6 | SHA pin 2층 고정 (Platform SHA + Axiom SHA), `@<40-hex>`만, mutable 참조 0건 | ADR-0025 §5 |
| M-ID-7 | cert field binding: subjectId/baseSha/headSha/certTree/evidenceDigest | ADR-0026 §7-3 |
| M-ID-8 | sourceHash/irHash 기반 input identity | readiness R4 `inputIdentity` |

#### B. Authority (상태 변경·권위 행위)

| ID | 내용 | 근거 |
|---|---|---|
| M-AU-1 | main 변경 정본 행위 = GitHub native MERGE 단일 (M-B) | AGENTS.md §2, ADR-0025 §1 |
| M-AU-2 | required status check = `admission-check` **정확히 1개** + `strict` freshness (0개 불가 — strict는 status ≥1에서만 성립; 2개 이상 금지 = 단일 verdict) | ADR-0025 §2 |
| M-AU-3 | CI는 candidate당 **1회만 실행** (required workflow ≠ 두 번째 테스트 — 동일 실행의 플랫폼 강제) | ADR-0025 §2 ①′ |
| M-AU-4 | **post-merge gateway = 0** — 착지 후 발화는 가드 불가 (구조적 사실) | ADR-0025 코어 불변식, `canonical_run_graph.md:73` |
| M-AU-5 | certificate = admission predicate 필수 증거, ≠ authority | ADR-0025 §3 |
| M-AU-6 | certRequired = true — PR head 결속 subject-continuity cert. missing = NO_CERT (missing ≠ valid empty) | merge_admission.json v1.3.0, merge_cli Pass 2.96 |
| M-AU-7 | trustSurface 변경 → auto-merge 거부 (rename source 포함) | merge_admission.json |
| M-AU-8 | acceptableConclusion = exactly `success` (skipped/neutral/cancelled/failure 미인정) | merge_admission.json |
| M-AU-9 | publish = 단일 writer, ledger append exactly-once (첫1/재실행0) | ADR-0025 §14·Amendment A1, ADR-0026 §4 |
| M-AU-10 | certificate-mint = sole ledger writer (FF-CAS side-ref) | canonical_run_graph §A |
| M-AU-11 | mint write boundary: B-pinned code만 실행 + write destination = ledger 한정 + main 직접 mutation 코드 0건 | ADR-0025 §4 |
| M-AU-12 | execution authority = org required workflow @SHA (플랫폼 고정) | ADR-0026 authority 표 |
| M-AU-13 | freshness authority = GitHub ruleset strict — Axiom 재구현 금지 | ADR-0025 §2 |
| M-AU-14 | VERDICT만 merge 허용 판단 | ADR-0026 §1-9 |

#### C. Evidence (증거·검증 의미)

| ID | 내용 | 근거 |
|---|---|---|
| M-EV-1 | **증거 강도(MUST 16) 불변** — 의미 변경 금지 (열거본은 저장소 부재 → §1.4 UNKNOWN) | ADR-0026:29, :211 |
| M-EV-2 | INV-4 구조적 독립성 — 동일 생성기 산출물 간 등가는 증거 불인정 | certification_continuity INV-4 |
| M-EV-3 | INV-5 evidence 등급 R-derive > T-tool > L1 (L1 채용 = 인증 거부) | INV-5 |
| M-EV-4 | INV-6 kernel verdict만 unforgeable; `#print axioms` allowlist = {propext, Classical.choice, Quot.sound, funext} | INV-6 |
| M-EV-5 | INV-9 cert 의미론 스냅샷 + 금지 주장 정적 스캔 | INV-9 |
| M-EV-6 | INV-10 Z3 결정론 = 공학 고정(바이너리 체크섬·seed 0·rlimit), 재실행 불일치 = fail-closed | INV-10 |
| M-EV-7 | INV-12 continuity verdict self-contained (입력 = main object + side-ref 원장 cert + tracked policy/scope 파일뿐) | INV-12 |
| M-EV-8 | INV-13 subject당 certificate 정확히 1개 (D6 멤버십 검사) | INV-13 + D6 해석 개정 |
| M-EV-9 | **산출물별 생성 authority 정확히 1개 + 소비자 재생성 금지** | ADR-0026 §1-1 |
| M-EV-10 | **cache ≠ evidence** — cache miss = 성능(J3), 검증 의미 변화 없음 | ADR-0026 §1-5, verification_dag_contract:107 |
| M-EV-11 | artifact-evidence 결속 5종: artifact identity(run-scoped+trusted-name+artifact-ids) / file digest / field binding / signature closure / CAS 원자성 | ADR-0026 §7 |
| M-EV-12 | authority 산출물 = immutable artifact + digest 기록 + 필드 결속 + 서명 (전송 무결성 = 플랫폼 TCB, 중복 구현 금지) | ADR-0026 §1-2 |
| M-EV-13 | tamper 6종 전부 fail-closed | ADR-0026 §7 |
| M-EV-14 | 같은 바이트 2회 자체는 버그 아님 — **버그 = 산출물별 authority 2개 또는 소비자 재생성** | ADR-0026 §3·§4 |
| M-EV-15 | 결정론: 동일 canonical 입력 + 동일 실행 계약 → 동일 canonical projection | R3/R5, productization_entry_contract REPRODUCIBLE_RESULT |

#### D. Determinism / Fail-closed / Boundary

| ID | 내용 | 근거 |
|---|---|---|
| M-DE-1 | 검증 불가·오래된 증거 = 비성공 (fail closed) | GUARDIAN §4 |
| M-DE-2 | RUNTIME_BOUNDARY R6: `TrackedDelta ⊆ SanctionedProductWrites`, `TrackedDelta ∩ Source/Config/Input = ∅` | productization_entry_contract_v1 §RUNTIME_BOUNDARY |
| M-DE-3 | Closed-World / Zero-Input: 정책 문서 compile-time embed, runtime policy read 금지 | architecture 1.1a |
| M-DE-4 | 결정 바인딩: 변경은 커밋된 결정/정책에 구속 | §0.10 |
| M-DE-5 | 극장 금지 + 감사 추적 없는 게이트 우회 금지 | §0.9, §4 |
| M-DE-6 | hermetic entry: `nimble build` / `nimble test` / `bin/run-gate` | architecture 1.1 |
| M-DE-7 | git-tree purity: manifest 기록 = `build/`, `.axiom/`, `logs/` 한정 | verification_dag_contract:107 |
| M-DE-8 | Layered gate L0/L1/L2 — L1은 L0 참조 금지 (compile-time assert) | architecture 1.1 |
| M-DE-9 | §-1 불변 파일: `import_encapsulation_gate.nim` + `AGENTS.md` | AGENTS.md §-1 |
| M-DE-10 | 프로젝트 소스 = Nim only (Python/Shell 금지) | architecture 1.1 |
| M-DE-11 | untrusted tier = contents:read + 시크릿 미참조 (정적 게이트 강제) | INV-7 |
| M-DE-12 | Zero-Footprint Integrity + CLI First | §0.1 |

### 1.2 POLICY (다이얼 — 요구사항 아님, 개정 경유로만 변경)

| ID | 내용 | 근거 |
|---|---|---|
| P-1 | K=8 (matrix/SHARD 통합 16→8) — **명시적 MUST 아님** | ADR-0023 A1.8(b)(f), ADR-0026 §1-7 |
| P-2 | speculativeDepth = 3 | merge_admission.json |
| P-3 | D3 scale_set_capacity = 16 (runner 상한) | ADR-0023 A2/D3 |
| P-4 | CI wall-clock ≤ 15분 지연 예산 | ADR-0023 A1.8 |
| P-5 | trustSurface 경로 목록의 실제 내용 | merge_admission.json |
| P-6 | requiredValidations 목록 내용 (fail-closed 의미 자체는 M-AU) | merge_admission.json |
| P-7 | cache-key-prefix 이름 (`axiom-toolchain` / `-readiness` / `axiom-canary`) — **분리 자체는 불변(M-EV 계열)**, 이름은 policy | verification_dag_contract:99 |
| P-8 | acceptableConclusion 값 문자열 | merge_admission.json |
| P-9 | ratchet/hotspot baseline·임계값 | config/policy/*, data/* |
| P-10 | gate enable/disable 生命周期 | gate_admin, gates.waiver.toml |
| P-11 | 비용 예산 (billed ≤192h 등) | ADR-0023 A1.8 |
| P-12 | maxCapacity=16 hosts, burst-16 수용 | ADR-0023 |

### 1.3 IMPLEMENTATION CHOICE (검증·변경 가능한 가정)

| ID | 내용 | 비고 |
|---|---|---|
| I-1 | 워크플로 8개 분할 구조 그 자체 | 의미 무관 시 통합·삭제 가능 |
| I-2 | admission-check.yml / certificate-mint.yml 내부 step 배치 순서 | |
| I-3 | certificate-mint의 `workflow_run` 후행 트리거 | ADR-0025 §3이 `workflow_call` 전용 재정의를 명시 — 이미 결함(구멍 15)으로 식별 |
| I-4 | GHA cache 사용 경로/방식 | M-EV-10: 가속 전용 |
| I-5 | composite action 1개로 툴체인 준비 | |
| I-6 | runner label / hosted 배치 | |
| I-7 | tools/ci 게이트 개수·구성 | |
| I-8 | job/step 이름, YAML 구조 | |
| I-9 | measure 워크플로 존재(gateway-jobs-measure, h4-routing-measure) | MUST 미연결 시 제거 후보 |
| I-10 | DAG 직렬/병렬 형태 | 실제 의존만 존중하는 한 자유 |
| I-11 | artifact 이름/네임스페이스 | 단, identity 결속(M-ID-7)은 MUST |
| I-12 | Lake smoke 위치 | D5 |
| I-13 | ci-bootstrap 중복 빌드 위치 | 단, mint 자체 빌드 = 계약 C1 (M-EV-14) |

### 1.4 UNKNOWN (분류 보류 — 근거)

| ID | 내용 | 근거 |
|---|---|---|
| U-1 | **"MUST 16"의 열거본이 저장소에 없음** — ADR-0026만 "증거 강도(MUST 16) 불변 / 의미 변경 = 범위 밖"으로 인용. 후보 판독: (a) INV-1..13 + 3, (b) 증거 4분리 [W][B1][X][B2][F]+[D]+[E], (c) 외부 계획서(black-hawk-carnage-rogue rev.7)의 독립 목록. **문서화 결함으로 표기** | ADR-0026:29,:211 전수 검색에서 유일 인용 |
| U-2 | authority 서술 충돌: `app_landing_binding.json` "Landing App = ONLY authority that mutates refs/heads/main via CAS" vs ADR-0025 §1 "Landing App CAS = 비authoritative 예비(DEBT#462 open, E2E 0건), 정본 = native MERGE" | ADR-0025 §1-2가 서술 정정 예정 |
| U-3 | DEBT#462 open 상태 유지 여부 / CAS E2E 실증 부재 | debt_registry:3761-3774 |
| U-4 | merge_admission.json v1.6.0 "mutation authority → Landing App CAS" 이전의 ratification 상태 | policy description |
| U-5 | PERSISTABLE_CERTIFICATE = OPEN (launch requirement 편입 미확정) | productization_entry_contract §2 |
| U-6 | [B2](b) semantic domain 미확정 → 데이터 인과 (b) 구현 금지 | ADR-0026 §8 |
| U-7 | gateway-jobs-measure / h4-routing-measure의 MUST 연결 | 후속 inventory에서 판정 |
| U-8 | hardware-falsification-smoke / release-ship의 MUST 연결 | 후속 inventory에서 판정 |

---

## Phase 2~4. Inventory / Removal / Minimal Boundary

(서브에이전트 전수조사 결과 반영 — 아래 절부터)

---

## Phase 2. Component Inventory (서브에이전트 전수조사)

### 2.1 워크플로 master table

| Workflow | Triggers | Jobs | Class | Verdict |
|---|---|---|---|---|
| admission-check.yml (686) | **workflow_call only** (org `admission-gate`가 유일 caller) | build-base-artifacts + admission-check | PROOF/IDENTITY | KEEP |
| certificate-mint.yml (1075) | **workflow_call only** (legacy workflow_run 제거됨) | prepare + publish | CERTIFICATE/PUBLICATION | KEEP |
| runner-pool-acceptance.yml (725) | workflow_call + dispatch + **push@main(캐시만)** | select / ci-bootstrap / candidate-build-arm / gateway-shard×8 / identity-gate / proof-reconcile | ORCHESTRATION+PROOF | KEEP (단 push@main 발화 = 캐시 유지 = 성능 전용) |
| repository_surface.yml (73) | pull_request@main | 1 | OBSERVATION | KEEP(trustSurface) / 유일 PR 관측 |
| release-ship.yml (440) | workflow_dispatch | freeze / full-l2 / publish | AUTHORITY(ADR-0024) | KEEP |
| gateway-jobs-measure.yml (261) | workflow_dispatch | provision / measure | OBSERVATION(측정 plane) | REMOVE-CANDIDATE(캠페인 종료 시) |
| h4-routing-measure.yml (561) | workflow_dispatch | provision / measure / r5-select-leg / r5-shard-leg | OBSERVATION | REMOVE-CANDIDATE(캠페인 종료 시) |
| hardware-falsification-smoke.yml (166) | dispatch + self-path push | arm-falsification / slim-light-falsification | OBSERVATION | KEEP(arm/slim falsification) |
| setup-axiom-toolchain (427, composite) | 11 call sites | 13 steps | TRANSPORT(가속 전용) | KEEP |

중요: 두 랜딩 워크플로는 **이미 `workflow_call` 전용** — ADR-0025 §3의 "workflow_run 후행 트리거 제거"가 구현되어 있음. Phase 1 가정 I-3은 현재 코드에 더 이상 해당 없음(역사적 결함, 수정 완료).

### 2.2 admission-check.yml 상세 (AUTHORITATIVE — required check)

**Job 1 `build-base-artifacts`** — B(pr.base.sha)만 체크아웃, H 절대 미체크아웃.
- checkout B (:124) → setup-axiom-toolchain (:130, restore-only) → Lake smoke fail-closed (:138) → `make ci-bootstrap` + ircheck (:160) → manifest.txt(build_sha=B) (:181) → upload `admission-check-base-artifacts` (:196)
- authority: **execution** (read-tier B-verifier 단독 생산 — ADR-0026 §4)

**Job 2 `admission-check`** — B-built 바이너리만 실행, H는 `_candidate/` data-only.
- checkout B (:224) / H data-only (:242) / download+manifest 검증 build_sha==B (:260) / identity 재유도 B·H·mergeTree (:299) / D9 staging (:361) / subject-register (:433) / **attest --witness-only → witness.json** (:474) / D6 로그 (:506) / scope+baseline (:525) / derived-closure 로드 (:570) / `ax merge --dry-run` → admission-verdict.log (:577) / upload `admission-check-<PR>` (:628) / Check Run `landing-trigger` POST (:657)
- authority: execution(증거 생산). 판정 authority = org gate.

### 2.3 certificate-mint.yml 상세

**Job `prepare`** (contents:read, C1 자체 빌드):
- activation guard API 재검증 (:188) / B·H 유도 (:264) / checkout B (:322) / toolchain (:334) / `make ci-bootstrap` 자체 빌드 (:339) — **계약 C1 예외, 제거 금지** / TrustedWriterSet@B 검증 (:369) / witness run-scoped artifact retrieval+provenance (:445) / mergeTree 대조 (:509) / `ax cert attest --sign` → certificate.json (:544) / cert manifest+sha (:591) / upload `subject-certificate-<runAttempt>` (:636)

**Job `publish`** (contents:write — 유일 writer):
- P0 activation guard+B2(a) (:713) / P1 [X]1 artifact identity (:767) / P2 [X]2 cert_sha256 대조 (:808) / P3 bin/ax 소비(재빌드 0) (:836) / P4 [X]3 field binding 5종 (:862) / P5 [B2](b) 3중 트리 동등식 (:934) — **`tested-tree-digest` 아티팩트를 runner-pool select에서 소비** / P6 [B2](c) gateway lane success (:985) / P7 D6+FF-CAS **ledger-append (유일 mutation)** (:1033)

### 2.4 runner-pool-acceptance.yml 상세

| Job | Gate | 산출 | Authority | 판정 |
|---|---|---|---|---|
| select (:115) | event≠push | `tested-tree-digest`(:142-159), `ci-select-decision`, `ci-select-verifier` | 결정(순수 함수), verdict 아님 | KEEP — **mint [B2](b)의 유일 producer** |
| ci-bootstrap (:275) | always | B cache save(push@main only, ONE-WRITER), manifest, executed record | B-layer 캐시 writer | KEEP(캐시=성능) |
| candidate-build-arm (:443) | event≠push | `candidate-arm64` | candidate 1/arch (재생성 0) | KEEP |
| gateway-shard ×8 (:496) | event≠push | junit, executed-shard-N | 검증 증거 | KEEP |
| gateway-identity-gate (:645) | event≠push | union==86/쌍별 배타 | identity 판정 | KEEP |
| proof-reconcile (:678) | event≠push | executed==selected 대조 | SKIPPED=Success 간극 봉쇄 | KEEP |

push@main 발화 시 **ci-bootstrap만 실행** → post-merge 검증 아님, 캐시 유지뿐.

### 2.5 비랜딩 상세 (요약)

- **release-ship**: freeze(4중 바인딩+유일성, read-only) → full-l2(runner-pool workflow_call force_full) → publish(App token, POST /releases, peel provenance) — ADR-0024 publication authority. MERGE 미행사.
- **repository_surface**: PR diff 분류 관측 전용, **강제는 로컬** `make check-repository-surface`(Makefile:370, push-admissibility:350). required check 아님.
- **measure plane 3종**: Owner 결정 #14 "비authoritative 측정 plane". exp- 네임스페이스로 B cache 격리 — production B key와 경쟁 불가. authority 6종 중 아무것도 행사 안 함. h4 R2가 production ledger를 `|| true`로 읽기만 함(append 0).
- **setup-axiom-toolchain**: exact-key only(restore-keys 금지), 지문 검증 불일치 시 discard→native build. A save=lock-guarded, B save=caller-owned. **"cache is acceleration, never evidence"** 명시 계약(action.yml:7).

### 2.6 교차 발견 (drift/결함)

| # | 발견 | 근거 | 의미 |
|---|---|---|---|
| X-1 | cache-prefix drift: 계약은 `axiom-toolchain`/`-readiness`/`axiom-canary`, 실제 코드는 `axiom-a-`/`axiom-b-` + exp-/sha 세그먼트 | verification_dag_contract:99 vs action.yml:95,100 | 원칙(레이어별 exact-key 분리)은 유지, **문서 표기는 stale** |
| X-2 | stale recipe 인용: "Makefile:762-773" → 실제로는 ci/checker.mk:40-51 | gateway-jobs-measure:27-31 등 | 문서 drift |
| X-3 | "9 jobs" 표기 vs 실제 13 job 인스턴스(full L2 10) | merge_admission.json:4 | 정책 서술 stale |
| X-4 | `tools/ci/run_landing_continuity.sh` 인용됐으나 파일 부재 | merge_admission_controller.md:6 | dangling 참조 |
| X-5 | tcb_judgments J3: B-manifest 순환성 — manifest가 자기가 인증하는 payload 안에 존재 | tcb_judgments.nim:403 | **B 지문 = acceleration-grade**, evidence 금지 계약과 일치 |
| X-6 | `ci-bootstrap-artifacts`(runner-pool:418-428) **in-repo 소비자 0건** | grep 결과 | 관측/디버그 전용 |
| X-7 | admission D6 step(:506-518) always-green — `set -e`에서 conditional-left로 ledger 실패가 else로 빠짐 | admission-check.yml:513-518 | 라벨 "fail-closed"가 사실과 불일치 |
| X-8 | merge tree OID **6회 재유도**(admission:340, mint 3b:524, P4:903, P5:965, runner-pool select, org gate) | INV-1 설계 | 의도된 신뢰 경계별 대조. 단 P4/P5는 동일 object 이중 호출 |
| X-9 | D9 staging이 삭제된 스크립트의 inline port (TODO: tracked tool로 재상륙) | admission-check:352-359 | 복붙 3번째 사본 |

---

## Phase 3. DAG Edge Semantic Audit

### 3.1 `needs:` 엣지 14개 전수

| # | Edge | 끊기면 깨지는 것 | 판정 |
|---|---|---|---|
| E1 | build-base-artifacts → admission-check | B-built bin/ax 미존재 → Gate A 붕괴 | KEEP (데이터) |
| E2 | select → ci-bootstrap | mode/decisionHash 결속 불가 → A3 계약 붕괴 | KEEP (데이터) |
| E3 | select → candidate-build-arm | 발화 결정 불가 | KEEP (데이터) |
| E4 | select → gateway-shard | 발화 결정 + decisionHash 결속 | KEEP (데이터) |
| **E5** | **ci-bootstrap → gateway-shard** | **없음 — shard는 candidate-arm64만 소비, always()로 실패 결합도 없음** | **REMOVE-CANDIDATE (순수 직렬화)** |
| E6 | candidate-build-arm → gateway-shard | arm 바이너리 부재(x64 재사용 금지) | KEEP (데이터) |
| E7 | gateway-shard → gateway-identity-gate | junit 부재 → union==86 검증 불가 | KEEP (데이터) |
| E8 | select → gateway-identity-gate | gatewayTestScope 부재 | KEEP (데이터) |
| E9 | select → proof-reconcile | decision+verifier 부재 | KEEP (데이터) |
| E10 | ci-bootstrap → proof-reconcile | executed-ci-bootstrap 레코드 부재 | KEEP (데이터) |
| E11 | gateway-shard → proof-reconcile | executed-shard 레코드 부재 | KEEP (데이터) |
| E12 | freeze → full-l2 | frozen_sha 미결속 → 검증 대상 불명확 | KEEP (데이터) |
| E13 | freeze → publish | tag/release 구성 불가 | KEEP (데이터+authority) |
| E14 | full-l2 → publish | 데이터 없음 — 단 **검증 선행 authority 순서** | KEEP (authority 순서, ADR-0024) |
| E15 | r5-select-leg → r5-shard-leg | 데이터 없음 — 단 **직렬화 자체가 측정 대상**(chain-W) | KEEP(측정 목적) / 데이터 관점 독립 |

### 3.2 트리거·트리거 커플링

- `workflow_run` / `schedule` / `release` 트리거 **전무** — CI=0 cutover로 폐기. 현행 = org gate의 `workflow_call` 조합 + release-ship in-repo call.
- admission-check: `workflow_call` only. runner-pool: workflow_call + dispatch + push@main(캐시 authority only). release-ship: dispatch only. measure 3종: dispatch only. repository_surface: pull_request@main.
- concurrency: runner-pool(event_name 분리 — B3 충돌 방지), repository_surface(per-PR cancel), release-ship(`release-ship-<sha>` cancel:false = **동일 SHA 직렬화 = freeze 경합 제거, authority 유일성 기구**), hw-smoke(run_id 키 = no-op).

### 3.3 독립인데 직렬화된 pair

| Pair | 메커니즘 | 데이터 인계 | 판정 |
|---|---|---|---|
| gateway-shard×8 × ci-bootstrap | needs:497 | **없음** | **제거 후보 1순위** — 벽시계 arm-shard 6.6m에 직렬 대기 |
| r5-shard-leg × r5-select-leg | needs:490 | 없음(측정 대상) | 측정 목적상 유지 |
| prepare × publish | caller stage-split | 실재(artifact+B2) | 유지 |
| full-l2 × publish | needs + if | 없음(순서) | 유지(authority) |

### 3.4 ruleset/required check 결속

- `requiredValidations` = `admission-check` **단일**(workflowId 365692388) + `requiredWorkflowDetection`(repositoryId 1182157951, path admission-gate.yml, verdictJob admission-check)
- `merge_cli.nim` 이중 바인딩: RequiredChecks/RequiredWorkflowIds(:76-90) + CertRequired(:112) — Pass 2.6 fail-closed
- `certRequired: true` — 미보유 = NO_CERT
- **org gate(`Archright/.github admission-gate.yml @SHA`)가 실제 오케스트레이터** — out-of-repo이므로 **UNKNOWN-by-scope**. in-repo callee는 전달된 사실을 전부 fail-closed 재검증

### 3.5 벽시계 매핑 (ADR-0026 실측)

29.2min full PR gate = 검증 4.3m + 중복 B-빌드 8.2m(정당 two-product) + 툴체인 6.7m + arm-shard 6.6m.
재팽창 원인: `93c758c2d`(workflow_call 전환 — 빌드가 전부 gate run 내부로) + `7606e0580`(C3 select→slim, shard→arm) + 직렬 DAG.
in-repo 직렬 척추: `select → {ci-bootstrap ∥ candidate-build-arm} → gateway-shard×8 → {identity-gate, proof-reconcile}`.
**가장 큰 제거 가능 직렬화 = E5** (shard를 select 완료 시점에 시작 가능).

---

## Phase 4. Artifact Producer/Consumer Graph (핵심 21종)

저장소 분류: GHA-artifact(run-scoped 전송) / GHA-cache(evictable 가속) / durable CAS(`.axiom/cache`) / git-tracked.

| # | artifact | producer | consumers | identity | mutation authority | 판정 |
|---|---|---|---|---|---|---|
| 1 | witness.json+sha256 (`admission-check-<PR>`) | admission job2 attest --witness-only (:474-496) | mint prepare(3), mint publish(P4), Landing App check-run | witness.sha256 + provenance(B,H,runId,mergeTree…) | admission 단독 | KEEP — 최종 검증 산출물 |
| 2 | `admission-check-base-artifacts` (bin/ax, ircheck, manifest) | build-base-artifacts (:124-205) | admission job2 (manifest build_sha==B 검증) | manifest sha256 + build_sha | read-tier 단독 (§4) | KEEP |
| 3 | `subject-certificate-<runAttempt>` | mint prepare (:636-645, C1 자체빌드) | mint publish P1–P7 | cert_sha256 + 5필드 결속 + Ed25519 | mint prepare (C1) | KEEP |
| 4 | ledger record (`refs/heads/axiom/certificates`) | **mint publish P7만** (FF-CAS append) | admission D6(읽기), mint D6, merge_cli Pass 2.96 | subjectId, 1 cert/subject | publish 단독 | KEEP |
| 5 | `tested-tree-digest` | runner-pool select (:142-159) | **mint publish P5 [B2](b)**, org gate | 40-hex tree OID | select 단독 | KEEP — `needs:` 없는 실제 데이터 엣지 |
| 6 | `ci-select-decision` + `ci-select-verifier` | select (:247-265) | ci-bootstrap/shard decisionHash 결속, proof-reconcile | decisionHash=sha256(decision.json) | select (순수 함수) | KEEP |
| 7 | executed-ci-bootstrap / executed-shard-N | ci-bootstrap (:398-416), shard (:587-605) | proof-reconcile | decisionHash 결속 | 실행 job 자체 | KEEP |
| 8 | `candidate-arm64` | candidate-build-arm (:443-494, 1/arch) | gateway-shard×8 (다운로드+sha 검증, compile=0) | manifest sha256 | candidate-build 단독 | KEEP |
| 9 | `ci-bootstrap-artifacts` | ci-bootstrap (:418-428) | **없음(in-repo 소비자 0)** | manifest | ci-bootstrap | **REMOVE-CANDIDATE** |
| 10 | gateway-junit-shard-N | shard (`make test-gateway`) | identity-gate (union==86) | testcase 이름 집합 | shard leg | KEEP |
| 11 | B/A cache | B: runner-pool push@main만(ONE-WRITER) / A: action | 전부 restore-only 7 call sites | exact-key + 지문 검증, 불일치→discard | B 단일 writer | KEEP(가속) |
| 12 | durable CAS `.axiom/cache` | bin/ax 실행 (gate_memo CAS) | 재사용 lookup | content hash | ax 실행 | KEEP — **단 GHA cache에 포장(P5-2)** |
| 13 | `.axiom/gate_history.jsonl` | merge_cli append | 업로드 tail, cache_gc 회전 | 없음(journal) | merge_cli | KEEP(감사) |
| 14 | evidence 레코드 draft/subjectId | admission stager + subject-register | attest, mint 유도 | subjectId=커널 유도 | admission | KEEP |
| 15 | scope.lock / baseline.json | `ax scope lock`/`baseline update` (per-run 재생성) | policyDigest/scopeDigest 결속 | sha256 | 검증 커널 | KEEP |
| 16 | exp-h4/gateway-jobs payload·측정 | measure plane | cross-run 다운로드 | manifest build_sha==ref | experiment(비권위) | 측정 종료 시 REMOVE-CANDIDATE |
| 17 | `derived-closure` | **org gate(외부)** | admission (:570-614) | 바이트 정렬 라인 | org gate | KEEP (외부 결속) |
| 18 | Release + v* tag | release-ship publish | peel provenance | tag==VERSION ∧ peel==FROZEN_SHA | App(Contents:write) | KEEP (ADR-0024) |
| 19 | artifact_spec.json 3종 | discover_test_debt.nim | debt_engine --validate | sha256sum | 단일 generator | CI 아티팩트 **미관할 = 거버넌스 공백** |
| 20 | test-harness 바이너리 8종 | **모든 실행 지점이 재컴파일** | 자기 자신 | 없음 | 없음 | **P2 소비자 재생성 패턴** |
| 21 | hotspot/perf/ci-pareto | tools/ci/* | 게이트·제네레이터 | sha256/source_hash | 생성 도구 | 일부 **producer 부재 orphan** |

### Flagged problems

**P1 — 다중 producer**
- `bin/ax`+3 바이너리 **7개 빌드 사이트**. ADR-0026 §4이 정당화 = 3(admission read-tier, candidate 1/arch, mint C1). 잉여 4곳(h4-warm, gateway-jobs-warm, hw-smoke, runner-pool B-cache path)은 ADR-0026 §2 6문항(Q3 재생성 아닌가) 정당화 필요.
- `manifest.txt` **동일 파일명·서로 다른 의미 5 producer** — 네임스페이스 충돌 위험.
- `build/.axiom-b-fingerprint.json` 2 producer(prod/exp 네임스페이스 분리, 주석만 좌표).

**P2 — 소비자 재생성**
- test-harness 8종을 shard마다 재컴파일 — ADR-0026 §4 "shard 재생성 0"은 bootstrap 4종만 커버. **two-product 정의의 공백**.

**P3 — 동일 의미 다중 이름**
- merge tree OID가 4개 이름(testedTreeDigest/mergeTreeDigest/tree(github.sha)/certTree) — 설계된 이중 결속이지만 어휘 sprawl 무거버넌스.
- witness.json이 2개 네임스페이스(admission-check-<PR> / exp-h4-*), cert 3처 저장(transfer/workspace/ledger).

**P4 — 전송 대신 재계산**
- harness per-leg 재컴파일, selector/reconcile verifier 재컴파일, hw-smoke·h4의 툴체인 재다운로드(의도적 falsification).
- 검증 목적 재유도(mint tree 대조, field binding 등)는 **계약상 정당** — 오탐 아님.

**P5 — cache-as-evidence 인접**
- measure plane이 `.axiom/cache/lean_verify_hash.txt` 캐시 복원 파일을 **초기 상태 증거로 하드 요구**(gateway-jobs-measure:201) + hash-hit skip 경로. 측정 plane 한정(dispatch-only).
- durable CAS가 evictable GHA cache 내부에 포장 — B restore 지문 검증은 4 바이너리만 커버, `.axiom/cache`/nimcache는 per-entry restore 검증 없음(단 CAS 자체 read-time contentDigest + §3.3 CONFLICT→re-execute가 방어).
- **production에서 캐시 hit로 PASS를 내는 경로 없음** (확인됨 — 긍정 통제).

---

## Phase 5. Removal Candidates (삭제 실험 — 논리적 판정)

### 5.1 유형 1 — 검증하지 않는 작업

| 후보 | 위치 | 삭제 시 사라지는 것 | MUST/CE 연결 | 판정 |
|---|---|---|---|---|
| gateway-jobs-measure.yml (261행, 2 jobs) | 전체 | 측정 기록(junit, workload 데이터) | **없음** — required 아님, admission/mint 미참조 | **REMOVE-CANDIDATE** (캠페인 종료 시). 의미 변화 0. 잔여 위험: data/ci_pareto baseline 갱신 중단 |
| h4-routing-measure.yml (561행, 4 jobs) | 전체 | R1–R5 라우팅 측정 궤적 | **없음** | **REMOVE-CANDIDATE** (캠페인 종료 시). 단, 측정 종료 전 제거 시 성능 불변식(P-4 벽시계 예산) 실측 근거 상실 |
| hardware-falsification-smoke.yml (166행, 2 jobs) | 전체 | arm/slim falsification 증거 | **없음** | **REMOVE-CANDIDATE**. 잔여 위험: arm 하드웨어 가정 반증 능력 상실 |
| repository_surface.yml (73행, 1 job) | 전체 | PR 시점 surface 관측 로그 | trustSurface 편입(=변경 시 auto-merge 거부)뿐 — **검증 증거 아님**. 강제 = 로컬 `make check-repository-surface`(Makefile:370) | **REMOVE-CANDIDATE**. 잔여 위험: PR 시점 조기 경고 상실(로컬 강제는 무손실) |
| runner-pool `push@main` 발화(ci-bootstrap만) | :67-72, :276 | B cache 갱신 | **없음** — 착지 후 발화라 가드 불가(canonical_run_graph:73), cache=성능(M-EV-10) | **REMOVE-CANDIDATE(의미 기준)** / 성능 기준 유지 시 **명시적 성능 불변식으로 승격 필요** |
| release-ship.yml (440행) | 전체 | 릴리스 발행 | 랜딩 MUST에 연결 **없음** — 별도 계약 ADR-0024 | **랜딩 경계 밖**. 삭제 대신 범위 분리가 정답 |

### 5.2 유형 2 — 중복 계산

| 후보 | 위치 | 삭제 시 | 판정 |
|---|---|---|---|
| admission `[check] D6 duplicate check` | admission-check.yml:506-518 | 로그 1줄 | **REMOVE-CANDIDATE** — always-green, 실제 INV-13 차단 = mint P7 |
| admission `[check] Scope + baseline integrity` | :525-534 | 조기 경고 | **SIMPLIFY** — job1 ci-bootstrap-cheap 재계산, 비교 대상 없음 |
| `ci-bootstrap-artifacts` 업로드 | runner-pool:418-428 | 디버그 산출물 | **REMOVE-CANDIDATE** — in-repo 소비자 0 |
| tree OID 6회 재유도 중 P4/P5 이중 호출 | mint:903, :965 | 없음(같은 object) | **SIMPLIFY 가능** — 단 [X]3와 [B2](b) 결속 목적은 상이 |
| harness 8종 per-leg 재컴파일 | ci/checker.mk:42-50 | 없음(성능) | two-product 공백 — **권위 부여 또는 전송으로 통합** 검토(구현은 범위 밖) |
| D9 staging inline 3번째 사본 | admission:361-425 | 없음 | **SIMPLIFY** — tracked tool 재상륙 TODO |

### 5.3 유형 3 — 불필요한 DAG 직렬화

| 후보 | 위치 | 근거 | 판정 |
|---|---|---|---|
| **E5 `ci-bootstrap → gateway-shard`** | runner-pool:497 | 데이터 인계 0, always()로 실패 결합 0 | **REMOVE-CANDIDATE 1순위** — shard 8개를 select 완료 시점에 병렬 시작 가능(arm-shard 6.6m 직렬 대기 해소) |
| r5-select-leg → r5-shard-leg | h4:490 | 없음(측정 대상) | 측정 목적상 유지 / 제거 후보는 아님 |

### 5.4 유형 4 — 레거시/역사적 편의 구조

| 후보 | 근거 | 판정 |
|---|---|---|
| cache-prefix 문서 표기(`axiom-toolchain`/`-readiness`/`axiom-canary`) vs 실제 `axiom-a-`/`axiom-b-` | verification_dag_contract:99 vs action.yml:95,100 | **문서 drift — 정정 대상**(구조는 원칙 유지) |
| "Makefile:762-773" 등 stale 인용 | gateway-jobs-measure:27-31 | 문서 drift |
| "9 jobs" 정책 서술 vs 실제 13 job 인스턴스 | merge_admission.json:4 | 문서 drift |
| `tools/ci/run_landing_continuity.sh` dangling 인용 | merge_admission_controller.md:6 | 문서 drift |
| `bin/publication_scope_gate` — config 부재, vacuous-pass tombstone | DAG 감사 §2 | **극장 위험 게이트** — 제거 또는 규칙 재부여 |
| admission D6의 "fail-closed" 라벨 | :513-518 | 라벨-현실 불일치 |

### 5.5 삭제 실험 형식 예시

```text
삭제: runner-pool E5 (needs: ci-bootstrap)
사라지는 것: 직렬 대기뿐 (산출물 0, 실패 결합 0)
검증 의미 변화: 없음 — shard는 candidate-arm64만 소비
판정: ORCHESTRATION / REMOVE-CANDIDATE
```

```text
삭제: certificate-mint prepare의 make ci-bootstrap
사라지는 것: write-tier 자체 빌드
Y가 필요한 계약: C1(ADR-0022) + TrustedWriterSet 의미
판정: CERTIFICATE / KEEP — 제거하려면 계약 개정 필요
```

---

## Phase 6. Minimal CI Architecture (최소 실행 경계)

### 6.1 랜딩 증거 전달에 필수인 최소 경계

```text
landing candidate SHA (PR head H, base B)
  ↓  [org gate admission-gate.yml @SHA — 외부, UNKNOWN-by-scope]
  ├─▶ admission-check.yml                    ← required check (유일)
  │     ├─ build-base-artifacts  [PROOF: B-built verifier]
  │     └─ admission-check      [PROOF+IDENTITY: witness + identity 3중 등식]
  ├─▶ runner-pool-acceptance.yml (gateway lane — workflow_call)
  │     ├─ select               [IDENTITY: tested-tree-digest → mint P5]
  │     ├─ candidate-build-arm  [IDENTITY: candidate 1/arch]
  │     ├─ gateway-shard ×8     [PROOF: 86 gateway tests]
  │     ├─ gateway-identity-gate[IDENTITY: union==86]
  │     └─ proof-reconcile      [PROOF: executed==selected]
  ├─▶ certificate-mint.yml
  │     ├─ prepare  [CERTIFICATE: C1 자체빌드 + attest --sign]
  │     └─ publish  [AUTHORITY: 유일 ledger append, FF-CAS]
  └─▶ setup-axiom-toolchain (composite)      [TRANSPORT — 가속, cache≠evidence]
  ↓
admission-check GREEN (required status, 정확히 1개 + strict freshness)
  ↓
GitHub native MERGE (유일 main 변경 authority)
  ↓
main
```

### 6.2 최소 경계에서 제외되는 구조

| 제외 | 이유 |
|---|---|
| gateway-jobs-measure / h4-routing-measure / hardware-falsification-smoke | 측정 plane — 랜딩 증거 미생성 |
| repository_surface | 관측 전용, 강제는 로컬 |
| runner-pool `push@main` 트리거 + B-cache save 경로 | 착지 후 발화 = 가드 불가, 성능 전용 |
| release-ship | 랜딩 계약 밖(ADR-0024 별도) |
| E5 직렬 엣지 | 의미 없음 |
| admission D6/scope-baseline step, ci-bootstrap-artifacts 업로드 | 의미 없음/재계산 |

### 6.3 성능·비용 불변식 (승격 대상)

반복되는 아키텍처 전제이므로 **명시적 invariant로 승격**해야 한다:

| 불변식 | 현행 근거 | 판정 |
|---|---|---|
| full gate wall-clock ≤15m | ADR-0023 A1.8 | POLICY 다이얼 — 승격 검토 |
| build-once / consume-many (bootstrap 4종 compile=0) | ADR-0026 §4 | MUST급 승격 권장 |
| shard compile 금지 | runner-pool:513, :548-569 | 승격 |
| 동일 logical artifact producer 단일화 | ADR-0026 §1-1 | MUST(M-EV-9) |
| cache ≠ evidence | ADR-0026 §1-5, DAG:107 | MUST(M-EV-10) |
| B-layer cache ONE-WRITER | runner-pool:297, PR #95 E1 | 승격 (cache-save race 방지) |
| cache-key 레이어 분리 | DAG:99(표기 stale) | 승격 + 문서 정정 |
| x64→arm 재사용 금지 | ADR-0026 §4 | 승격 |
| retry idempotency (D6 멱등) | ADR-0026 §10 | MUST(M-EV-8) |

---

## Phase 7. Gate/Script Inventory 핵심 발견

### 7.1 실행 표면 6종

| 표면 | 진입점 | 실제 실행 게이트 |
|---|---|---|
| S1 pre-commit hook | .githooks/pre-commit | nim_check_gate, anti_theater, layer_enforcement, stale_cert, canonical build check |
| S2 pre-push hook | .githooks/pre-push | gate_tier_integrity, anti_theater, layer_enforcement, **push-admissibility 9게이트** |
| S3 `axiom-gate commit` | gateway.nim:316-482 | TopologySpec 57게이트(스테이지 필터), live 증거: stagedFiles=0 시 2게이트만 |
| S4 GitHub workflows | 8개 | **B-built ax 체인 + gateway 86테스트만** |
| S5 Makefile | verify-contract G1–G7 등 | 수동 |
| S6 org gate | 외부(UNKNOWN-by-scope) | verdict, closure derivation |

### 7.2 치명 발견 — CI 휴면 게이트

**41개 skCI 게이트(nim-check, import-encapsulation, evidence-truth-boundary, tcb-coverage, sorry-audit, spec-presence 등)가 CI=0 이후 전부 휴면** — 어떤 workflow도 `AXIOM_CI=1`을 설정하지 않음(`gate_utils.nim:71`).
→ "CI가 게이트 X를 강제한다"는 주장은 현재 극장이다. 실제 CI 검증 = B-built attestation 체인 + gateway 86 tests + identity/reconcile 게이트뿐.

### 7.3 orphan·구조적 사망

- **tools/ci orphan 26종**(실행 경로 없음): self_heal_agent(변이 도구, 최고 위험), verify_trusted_writer_set.sh(**주석에서만 인용, 미실행**), validate_gate_exceptions(대상 config 부재), vc_generator/vc_complete, ratchet_check/shrink, pre_commit_gate/batch_nim_check, tcb_judgments, strace/reuse 실험 5종, pareto_harness, annotation_hygiene_gate 등
- **구조적 사망**: `baseline-migration-gate`(`stages=@[]` — topology_spec:617, 구조상 발화 불가), Makefile `hotspot-check`(source 부재), `bin/ci_dag_contract_gate`(source·참조 모두 없음)
- **config 비활성**: golden-master-gate, static-analyzer(DEBT#426), unstaged-guard, emergency-bypass-commit

### 7.4 always-pass / 실패 삼킴

| 위치 | 동작 | 판정 |
|---|---|---|
| gateway.nim:175-177 | feature_manifest_generator verify 실패 = logWarn만 | 극장 위험 |
| executor.nim:809-812, :948-955 | 빈 게이트 집합/0 영향 → PASS | alwaysRun 2게이트가 유일 방어 |
| executor.nim gsWarn 3게이트 | FAIL → continue (문서화된 fail-open) | §0.9 예외 요건 충족(문서화+로깅) |
| gateway.nim:644-654 | CAS cache-hit → 전체 게이트 skip | 문서화+bypass_audit 로깅 = 허용 |
| Makefile:388-392 | 스캐너 부재 시 loud-SKIP | 스냅샷 한정 문서화 |

### 7.5 중복 강제 클러스터

극장 스캔 ×3(anti_theater / check_nim_theater / S3 node) · nim syntax ×2 live + 2 dead · **debt ×5** · doc-ref ×3 · vacuity ×4 · sorry ×2 · stale-cert ×2 · coverage ×3

---

## Phase 8. 최종 판정 — 두 핵심 질문

### Q1. "Axiom의 검증 의미를 보존하면서 현재 CI의 몇 %를 제거할 수 있는가?"

**측정 기준을 명시한다:**

| 기준 | 제거 가능 | 근거 |
|---|---|---|
| **워크플로 표면(행 기준)** | **≈34%** (4,411행 중 1,499행) | 측정 plane 3종 988행 + repository_surface 73행 = **24%**는 랜딩 증거 미생성으로 즉시 제거 가능. release-ship 440행(10%)은 랜딩 계약 밖(ADR-0024 별도) — 삭제가 아니라 **범위 분리** |
| **PR 게이트 런타임** | **≈0% 즉시 / 벽시계 단축 가능** | 제거 후보 전부 dispatch-only이거나 게이트 미포함. 단 E5 직렬화 제거로 arm-shard 6.6m의 대기 해소 가능(제거가 아닌 재배치) |
| **tools/ci 부속물** | **≈44%** (59종 중 26종) | 미실행 orphan |
| **의미론적 최소 경계** | 워크플로 4종 = 2,912/4,411 ≈ **66%** | admission-check + certificate-mint + runner-pool gateway lane + setup-axiom-toolchain |

**결론: 랜딩 검증 의미를 보존하면서 CI 구조 표면의 약 1/3(34%)을 제거할 수 있다. 단, 이 제거는 PR 게이트 벽시계를 거의 줄이지 않는다 — 벽시계 단축은 E5 직렬화 해소·캐시 불변식 승격으로 별도 달성해야 한다.**

### Q2. "검증·증거·권위·결정론에 아무것도 추가하지 않는 작업은 정확히 무엇인가?"

**정확한 목록:**

| # | 작업 | 위치 | 아무것도 추가하지 않는 이유 |
|---|---|---|---|
| 1 | gateway-jobs-measure 전체 | 261행 | 측정 기록만. authority 6종 행사 0, required 아님 |
| 2 | h4-routing-measure 전체 | 561행 | 동일 |
| 3 | hardware-falsification-smoke 전체 | 166행 | 동일 |
| 4 | repository_surface 전체 | 73행 | 관측 전용 — 강제는 로컬 pre-push에 이미 존재(D7) |
| 5 | runner-pool `push@main` 발화 | :67-72 | 착지 후 발화 = 가드 불가. 산출 = B cache 갱신 = 성능만 |
| 6 | `ci-bootstrap-artifacts` 업로드 | runner-pool:418-428 | in-repo 소비자 0 |
| 7 | admission D6 로그 step | admission:506-518 | always-green, 실제 INV-13 차단은 mint P7 |
| 8 | admission scope+baseline step | :525-534 | 비교 대상 없는 재계산 |
| 9 | E5 직렬 엣지 | runner-pool:497 | 데이터 인계 0, 실패 결합 0 |
| 10 | tools/ci orphan 26종 | tools/ci/ | 실행 경로 없음 |
| 11 | verify_trusted_writer_set.sh | tools/ci/ | 주석에서만 인용, 미실행 |
| 12 | baseline-migration-gate | topology_spec:617 | stages=@[] — 구조상 발화 불가 |
| 13 | hotspot-check 타겟 | Makefile:842 | 대상 source 부재 |
| 14 | bin/ci_dag_contract_gate | bin/ | source·참조 모두 없음 |
| 15 | config 비활성 게이트 4종 | gates.json | 비활성 상태로 존재 |
| 16 | hw-smoke concurrency 그룹 | hw:32-33 | run_id 키 = no-op |
| 17 | D9 staging inline 3번째 사본 | admission:361-425 | 삭제된 스크립트의 복붙 |

**반대로, "없으면 안 되는" 유일한 실행 경계:**

```text
admission-check(build-base-artifacts + admission-check)
  + runner-pool gateway lane(select, candidate-build-arm, shard×8, identity-gate, proof-reconcile)
  + certificate-mint(prepare, publish)
  + setup-axiom-toolchain
→ admission-check GREEN → GitHub native MERGE
```

### Completion Evidence (기계 판정)

```text
1. 모든 CI job/step 목적·authority 설명        → Phase 2 표 (file:line 전수)
2. 모든 중요 artifact producer/consumer 설명   → Phase 4 (21종 + flag 5군)
3. 모든 DAG edge semantic dependency 설명      → Phase 3 (needs 14개 전수, 13 KEEP / 1 제거후보)
4. 모든 요소의 MUST/CE 연결 판정              → Phase 1 MUST 28+ / POLICY 12 / IMPL 13 / UNKNOWN 8
5. 삭제 후보 식별                             → Phase 5 (4유형 + Phase 7 orphan 26종)
6. 최소 실행 경계 정의                        → Phase 6.1
7. 코드 변경 없음                             → git status 확인 필요
```

### 잔여 한계 (Residual Limits)

- **org gate(`Archright/.github admission-gate.yml`)는 out-of-repo** — 실제 PR admission 오케스트레이터이며 감사 불가(UNKNOWN-by-scope). 최소 경계의 DAG 순서(prepare←admission, publish←gateway+prepare)는 그쪽에 있다.
- **"MUST 16" 열거본이 저장소에 없음** — ADR-0026만 인용. 본 감사는 "증거 강도 불변"을 보존 기준으로 사용했으나, 정확한 16항목 대조는 문서화 결함 해소가 전제되어야 한다.
- ADR-0025/0026 모두 PROPOSED 상태 — 확정 전까지 본 감사의 authority 해석은 현행 계약(merge_admission v1.8.0, INV-1~13)에 근거한다.
- Wall-clock 수치는 ADR-0026이 인용한 실측(29.2m 분해)에 의존 — 본 작업에서 재측정하지 않음(코드 수정 금지 원칙).

*작성일: 2026-09-27. 감사·분류·삭제 후보 도출 ONLY — 구현 없음.*

---

## Phase 9. Gateway 86 Semantic Reduction (2026-09-28 보충)

### 9.1 "86"의 정체 — 확정

```text
86 = $(ls tests/gateway/*_feature_test.nim | wc -l)     ← ci/checker.mk:88, :89(total)
```

- JUnit testcase 이름 = **파일 basename**(`all_gateway_runner.nim`가 파일당 1 엔트리 기록)
- identity-gate(`ci/checker.mk:87-112`)의 `union==86` = junit 이름 집합 == 파일 목록 집합 + 중복 0 + 누락 0
  → **파티션 완전성 bookkeeping**. 무결성 불변식 개수가 아니다.
- 결론: **86 test cases ≠ 86 integrity properties ≠ 86 MUST** — 코드로 확인된 사실.
- `known_failing_gateway.txt` = 주석만 존재(xfail 0건) → 86개 전부가 landing blocker로 발화.

### 9.2 판정 소비 구조 — 개별 테스트는 verdict를 읽지 않는다

```text
shard job → make test-gateway → all_gateway_runner (파일당 junit 1)
   → shard conclusion (실패 시 quit(1))
   → lane conclusion (aggregate)
   → certificate-mint P6 [B2](c): gateway/* job conclusion==success만 소비
   → publish 선행 조건 → certRequired → Pass 2.96
```

`merge_cli.nim` Pass 2.x는 **어떤 개별 junit 테스트 이름도 소비하지 않는다**(전수 grep 0).
→ "테스트 실행 완전성(A)"과 "무결성(B)"의 분리가 확인됨. 현재 구조는 A를 B의 감독자로 세웠고, B의 실질 결정은 attestation 체인(mint)이 담당한다.

### 9.3 86개 전수 분류 (서브에이전트 7병렬, 파일별 매핑)

| 판정 | 개수 | 비율 |
|---|---|---|
| **KEEP-IN-LANDING-GATE** | **12** | 14% |
| MOVE-TO-LOCAL-OR-NIGHTLY | 24 | 28% |
| MERGE-WITH-OTHER (중복 병합) | 16 | 19% |
| **REMOVE-CANDIDATE** | **34** | 40% |

분류: CORE PROOF ≈ 4 · NEGATIVE PROOF ≈ 4 · COVERAGE ≈ 33 · OBSERVATION ≈ 2 · REDUNDANT/DEAD ≈ 43

#### Landing gate 유지 12개 (유일하게 정당화된 집합)

`anti_theater_gate`(§0.8/§0.9 탐지기) · `import_encapsulation_gate`(§-1 불변) · `core_invariant_gate` · `command_policy_gate` · `conflict_marker_gate` · `git_wrapper`(네거티브) · `run_gate`(네거티브) · `cegar_engine` · `formal_text_diff` · `hotspot_coverage` · `context_size_guard` · `productization_start_vertical_slice`(caveat)

#### 제거 후보 34개 — 유형

1. **§0.8 스텁/공허** (실패 불가): `manifest_integrity_gate`(3/3 검사가 상수 길이 — 주장 runner 자체가 repo에 없음), `axiom_prove`(2/2 `check <const len> > 0`), `stages`(2/2 스텁), `manifest_consistency_gate`(임베디드 가짜 샘플 자가검증 — 실물은 `gate_manifest_schema_test`가 담당)
2. **§0.8 재구현 극장** (실제 모듈 미import): `function_verification_summary`(존재하지 않는 API를 로컬 재정의), `sync_metadata`(100% 재구현)
3. **죽은 모듈/미연결**: `flat_vfs`, `cst_adapter`, `drnim_gate`, `precompile_gates`, `process_sandbox`, `sandbox_launcher`, `state_ledger`, `reliability_gate`(단, live critical gate의 테스트 — **재작성 없이 제거 금지**), `gate_daemon`, `gateway_test_gate`, `loop_driver`, `smtlib2_parser`, `z3_proof_to_lean`, `proof_verifier`, `proof_witness_checker`, `proof_artifact_types`, `proof_typestate` 등
4. **이미 다른 검사가 보장**: `nim_check_gate`, `hotspot_coverage_gate`, `monotonic_whitelist_gate`, `bypass_audit`, `dead_code_gate`, `ast_integrity_gate` 등

### 9.4 구조적 발견 — 테스트 인프라가 trust surface로 전이됨

현재 production admission path에는 86개 파일 실행을 위한 machinery가 들어 있다:

```text
impact_closure_selector → shard×8 → junit → identity-gate(union==86) → proof-reconcile
```

이 machinery 자체가 Axiom의 trust boundary처럼 행동하기 시작했고, 이는 지난 CI 팽창 경로와 동일한 패턴이다.
**Axiom의 실질 trust primitive**(testedTree==mergeTree==certTree, native MERGE, certRequired, single writer, D6, kernel verdict, SHA pin)는 86개 functional tests와 **다른 수준의 존재**이며, 실제로는 attestation 체인이 결정한다.

### 9.5 최소 gateway 경계 (제안)

```text
landing blocker (12)        ← PR admission에서 유지
local/nightly (24)          ← 랜딩 차단 아님, 진단
merge/dedup (16)            ← 동일 불변식 테스트 통합
remove (34)                 ← 스텁·죽은 코드·중복
```

86 → **12** 가 landing-blocking으로 정당화됨 (86% 감축 후보).
단, 제거·이전 시 `union==86` identity 계약(`ci/checker.mk:87-112`)과 ADR-0025 §10 집합 계약을 **동시에 개정**해야 한다 — identity-gate의 expected set이 86에 하드코딩되어 있지 않고 `ls`로 유도되므로, 파일 삭제 시 자동으로 축소되지만 **계약 문서화가 선행되어야** 한다.

### 9.6 잔여 한계

- 개별 테스트의 "verdict 소비"는 전부 lane aggregate 경유 — 12개 유지 집합조차 개별 이름으로 판정되지 않는다. 따라서 12개의 정당성도 "lane 결론을 구성하는 최소 검증"이라는 의미에서만 성립한다.
- org gate(외부)가 lane을 어떻게 소비하는지는 미감사.
- reliabilty_gate는 live critical gate의 유일 검증 — 제거가 아니라 **재작성**(runGate() 실훈련) 과제.

---

> **부록 — ADR-0027 supersession note (2026-09-29, append-only)**: 본 표는
> 2026-09-27 시점의 관측이며 아래 노트는 그 사실을 변경하지 않는다. §Phase 4
> 행1의 `admission-check-<PR>` 명명은 ADR-0027 P2(후보 인증 위임 — GitHub Merge
> Queue)가 명시 개정으로 **de-contractualize**한다: 아티팩트 identity =
> candidate identity(`admission-check-<candidate head>`, candidate head =
> `pull_request.head.sha || merge_group.head_sha || github.sha`). 행3
> `subject-certificate-<runAttempt>` 표기는 현행(2026-09-29 실측)과 일치하여
> 그대로 둔다.

> **부록 — `ci-bootstrap-artifacts` 소비자 supersession note (2026-10-11, append-only)**: 본 표는
> 2026-09-27 시점의 관측이며 아래 노트는 그 사실을 변경하지 않는다. Phase 4 행9(:289), Phase 5.2(:347),
> Phase 6.2(:425), Phase 7 Q2 #6(:511)이 `ci-bootstrap-artifacts`(당시 위치 `runner-pool:418-428`)에 대해
> 기록한 `없음(in-repo 소비자 0)` 근거와 **REMOVE-CANDIDATE** 판정은 2026-09-27 기준으로 유효했다.
> 소비자는 2026-09-29 커밋 `994467412`로 착지한 `.github/workflows/ci-cache-publisher.yml`이다 — 존재
> 가드(`ci-cache-publisher.yml:199-207`, 비존재 시 `[publish-skip]`)와 cross-run 다운로드(`:264-274`,
> `run-id: ${{ github.event.workflow_run.id }}`)가 이 아티팩트를 입력으로 삼는다. 2026-10-11 기준
> in-repo 활성 소비자는 이 fail-open 1곳뿐이다(측정: 퍼블리셔 실행 698건 / 7일 창 2026-10-04..2026-10-10,
> GitHub Actions API `repos/Archright/Axiom/actions/workflows/ci-cache-publisher.yml/runs` total_count,
> 2026-10-11 조회). 따라서 위 4개 행의 REMOVE-CANDIDATE 판정은 **현재 시점의 삭제 근거로 인용되어서는
> 안 된다**. 현행 처분은 **KEEP @ `retention-days: 3`**(`runner-pool-acceptance.yml:670` — 브랜치
> `feat/storage-retention-policy` @ `4554c48f3`, PR #710)이며, 값의 근거는 관측 소비 시점 + 운영 마진
> (`docs/evidence/epoch_record_storage_retention_2026-10-10.md` §6 retry 실측·§7 선언 창)이다. 삭제는
> Slice 3에서 (a) Slice 3 가치 판정과 (b) out-of-repo 소비자 배제가 확정된 이후에만 다시 검토한다.
