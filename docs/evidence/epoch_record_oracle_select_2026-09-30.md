# CI Epoch Record — 검증 비용 = 증명 필요 집합 3-PR 계획 (PR-B): landingFloor Freeze / Record / Tombstone

> **성격**: AGENTS.md §2.5(CI Epoch Cutover Protocol) 단계 1–3 — **FREEZE / RECORD / TOMBSTONE** 기록 문서. 계획 "검증 비용 = 증명 필요 집합"의 PR-B 문서 트랙 산출물.
> **작성일**: 2026-09-30.
> **작업 브랜치**: `fix/claim-proportional-verification-execution` (linked worktree `Axiom-worktree`), HEAD == origin/main **56a7ab1ef** (freeze 시점 실측 `56a7ab1efd7ddac4e4576211dbf34ecaebda4882`).
> **병렬 편집 주의**: 동일 worktree에서 다른 에이전트가 `.github/`·`tools/`·`tests/` 코드를 병렬 편집 중(예: `tools/ci/impact_closure_selector.nim`은 본 문서 작성 시점 이미 +148줄 오라클 소비 구현이 존재). 본 문서의 라인 인용은 2026-09-30 실측값이며 **라인 이동 가능** — 의미 기준으로 판독할 것.
> **기록 관례**: `docs/evidence/ci_toolchain_scope_2026-09-30.md`("CI Epoch Record" — §2.5 Freeze/Record 템플릿: freeze tag 표 + org callee pin + repo twin pin + rollback reference)를 선례로 발견·따름. 별도 ADR 부록 신설은 하지 않음(연결은 §4).

---

## 1. Freeze (AGENTS.md §2.5 단계 1)

### 1.1 명명 결정

- `git tag -l` 조사 결과(2026-09-30): **epoch freeze 태그 관례가 이미 존재** — `ci-frozen-2026-09`(annotated, "forensic baseline: pre-rebuild CI state"), `ci-frozen-2026-09-28`(annotated, "forensic baseline: pre-cutover CI state"), `ci-epoch-pre-mq-freeze`(annotated), `ci-postmerge-2026-09`(annotated) 외 `archive/`·`ci-*` 계열.
- 계획서의 예비 명명(`ci-epoch-freeze-2026-09-30-56a7ab1ef`)은 "**v0.5.x 릴리스 태그만 있으면** 관례가 없는 것이므로"라는 조건부 지침이었으나, 조건이 성립하지 않음(관례 존재) → **기존 관례 `ci-frozen-YYYY-MM-DD`(annotated)를 채택**하기로 결정하고 본 절에 그 결정을 명기한다.

### 1.2 태그

| 항목 | 값 |
|---|---|
| freeze tag | **`ci-frozen-2026-09-30`** (annotated) |
| 태그 타입 | annotated — tag object `e8560e39a` → commit `56a7ab1ef` (기존 시리즈와 동일 형식) |
| freeze 대상 | origin/main `56a7ab1efd7ddac4e4576211dbf34ecaebda4882` (= 정본 CI epoch tip, 병렬 편집 전) |
| 실측 검증 | `git rev-parse ci-frozen-2026-09-30^{commit}` == `git rev-parse origin/main` == `56a7ab1ef…` ✓ |
| push | **아니오 — 로컬 전용** (작업 지침: 허용된 git 변형 = annotated 태그 생성 1건뿐; push·commit 금지) |
| 태그 메시지 | `forensic baseline: pre-oracle-select CI state (PR-B freeze — claim-proportional verification 3-PR plan; origin/main 56a7ab1ef). Local only, not pushed.` |

---

## 2. Record (AGENTS.md §2.5 단계 2)

### 2.1 현행 CI epoch의 실행 정의 — 워크플로 blob sha

| 파일 | blob sha (@56a7ab1ef) | 역할 |
|---|---|---|
| `.github/workflows/runner-pool-acceptance.yml` | `1c342f0a53fd74fd9590d3563312b2cb16508a20` | 현행 CI 전체 실행 인프라 — 9-job(ci-bootstrap + gateway-shard×8 + gateway-identity-gate) + select job(decision envelope — `landingPolicyFloor`·`scope_sl09`/`scope_sl10` NO-FIRE) |

org orchestrator `Archright/.github/.github/workflows/admission-gate.yml`(저장소 밖, ruleset **24041674** 핀)의 callee 핀 값은 본 freeze 시점 재실측 불가(org 저장소 접근 범위 밖) — **마지막 기록값 인용**: `docs/evidence/ci_toolchain_scope_2026-09-30.md §2.2`(2026-09-30 측정 — admission-check/certificate-mint/runner-pool-acceptance 전부 `@3156f9246`). 재확인은 코디네이터 소관으로 남긴다.

### 2.2 repo twin pin (직접 읽음, 2026-09-30)

- `config/trusted_writer_set.json` — `"trustedAdmissionWorkflowSha": "fa57673341a4bcb12bdc3785bc75d4caf7d0080c"` (주석: git hash-object `.github/workflows/admission-check.yml` — content-addressed)
- `config/policy/epoch_manifest.json:9` — `"productionExecutionPin": "fa57673341a4bcb12bdc3785bc75d4caf7d0080c"` — **일치 ✓** (mint witness 비교 대상 admission blob@B 핀 == epoch manifest 실행 핀)
- `config/trusted_writer_set.json` `trustedCheckerTreeClosure` — ci/checker.mk `cef1df553c…`, config.nims `0c8e50ff4…`, tools/ci/impact_closure_selector.nim `cc85db420…`, tools/ci/derive_checker_closure.nim `6ed19322d…` 등 30+ 항목(ADR-0025 §6 — ROTATION 절차로 갱신)
- `config/policy/epoch_manifest.json` — `ciEpochId: "N+6"`, `implementedSlices: [SL-08, SL-01, SL-03, SL-04, SL-12, SL-10]`, `notYetImplementedSlices: [SL-02, SL-05, SL-06, SL-0713, SL-09, SL-11, SL-14..SL-17]`

### 2.3 artifact / authority binding

| binding | 값 | 출처 |
|---|---|---|
| main ruleset required check | `admission-check` (ruleset 20303214) + cross-repo required workflow `landing-integrity` (23943917) | `docs/evidence/canonical_run_graph.md:95` |
| execution authority / freshness | org `workflows` ruleset 24041674 @SHA · strict required status check | ADR-0025 §2 |
| K DAG | admission callee 2 + mint-prepare prepare + mint-publish publish + gateway callee(select 등) + verdict — "구 엔진 job 0건", release-ship → runner-pool force_full 위임 | `docs/evidence/canonical_run_graph.md §I`(:292-331) |
| certificate 3-way identity | `testedTree == mergeTree == certTree` (gateway testedTreeDigest → mergeTree → mint provenance → certTree 서명) — **mint [B2](c) 재조정 메모: ADR-0025 Amendment C §(5)** | `docs/adr/0025-gateway-landing-authority.md:282`, src/cli/cert_cli.nim:1113 |
| select decision envelope(현행) | `mode=selected ciBootstrap=true gatewayTestScope=ALL shards=[0..7] landingPolicyFloor=true` (run 36495330895 실측) | `docs/evidence/canonical_run_graph.md:314` |

### 2.4 Rollback reference

- rollback 기준 = freeze tag `ci-frozen-2026-09-30`(immutable baseline — §2.5에 따라 **삭제 금지**).
- 재-핀 시 복원 대상: `trustedAdmissionWorkflowSha`/`productionExecutionPin` `fa57673341a4bcb12bdc3785bc75d4caf7d0080c`, runner-pool blob `1c342f0a53fd74fd9590d3563312b2cb16508a20`, org callee pin(§2.1 인용값).

---

## 3. Tombstone (AGENTS.md §2.5 단계 3)

**대상**: `tools/ci/impact_closure_selector.nim:1414` — `let landingFloor = true` (2026-09-30 실측 위치; 병렬 편집 중 라인 이동 가능 — 주석: "Landing floor (plan Phase 2): the gateway lane must execute on EVERY candidate — unconditionally").

**선언**: 이 하드코딩의 **무조건 착지-잡(landing gateway lane) 실행 동작**은 **본 PR-B로 종료된다**. 계획상 조건부식(`lgPolicyNonEmpty ∧ ¬oracleDerivedEmpty` — 검증된 oracle-evidence(`axiom/oracle-evidence/v1`, 5축)의 `derivedEmpty=true`가 유일한 floor 해제 조건)으로 교체되며, 병렬 코드 에이전트가 동일 PR-B에서 구현 중(selector working tree +148줄 — `loadOracleEvidence`·`oracleEvidence` envelope 필드·`DECISION-CPV-01/02` pragma, cross-ref: ADR-0017 Amendment A2(2026-09-30)).

**명시 (우회·면제·제거가 아님)**:

1. 본 Tombstone은 **게이트 우회(break-glass)가 아니다** — 실행 권한·검증 의무를 제거하지 않는다.
2. 본 Tombstone은 **면제(waiver)가 아니다** — `config/decision_binding.waiver.*`에 등록된 면제가 없다(2026-09-30 grep 0 hits — ADR-0025 Amendment C §(1) 기록).
3. 본 Tombstone은 **required-check 제거가 아니다** — `admission-check`(ruleset 20303214)·org required workflow·verdict 체인은 무변경 유지.
4. 본 Tombstone은 **검증 면제를 의미하지 않는다** — "영향-공집합 후보는 floor 면제"라는 새 의미는 조건부식으로 **교체되는 동작**이며, 그 정합(EMPTY 의미 단일화)은 **SL-09 승격 전 선행 조건**으로 명기된다(DEBT#470, ADR-0025 Amendment C §(1)).
5. Tombstone은 역사적 폐기 기록이며 실행·검증 권한을 갖지 않는다(AGENTS.md §2.5 Mandatory Invariants).

---

## 4. ADR·레지스트리 연결 (계획 Phase 3 항목 (0))

| 연결 대상 | 내용 |
|---|---|
| `docs/adr/0017-incremental-verification-engine.md` **Amendment A2 (2026-09-30)** | oracle-evidence 계약 비준(schema ∅·5축·derivedEmpty·`oracleEvidence` binding token) + C15 4항목 요지 |
| `docs/adr/0025-gateway-landing-authority.md` **Amendment C (2026-09-30)** | floor 비준 공백 기록 + EMPTY 모순 해소("영향-공집합 후보는 floor 면제") + SL-09 승격 전 선행 조건 + mint [B2](c) 3-way identity 재조정 메모 + selector B-pin 잔존 신뢰 경계 |
| `docs/spec/canonical_execution_semantics.md` **부록 D — 2026-09-30 Amendment** | C15 4항목 — ① 오라클 스키마 ∅ 허용 ② 축의 정직한 열거(축③ 부재·§4.5 dangling) ③ CERTAIN-사유 분류 `derivedEmpty` ④ L0-baseline carve |
| `docs/spec/incremental_ci_tiers_scheduling.md` **Amendment (2026-09-30)** | L0 "영향 폐쇄가 공집합이어도 항상 실행" 문장 vs 현행 CI 불일치 기록 + Known-branch witness(W4 클래스 미실현) |
| `docs/adr/0019-verification-tiers-scheduling.md` **Status (2026-09-30)** | L0 문장 불일치·Known-branch witness·selector 신뢰 경계 역참조 |
| `data/debt_registry.json` | **DEBT#466 (b+) 개정** + **DEBT#467–470 신규** (§5) |

---

## 5. DEBT 등록 요약 (2026-09-30)

| id | 제목 | severity | status |
|---|---|---|---|
| DEBT#466 (b+ 개정) | Known-branch witness 기록 — 격자 프로젝션 밖 W4 클래스 미실현 | high | deferred (append-only 개정) |
| DEBT#467 | selector 런타임 후보-트리 빌드 — B-pin 잔존 신뢰 경계 | medium | deferred |
| DEBT#468 | 독립 오라클 축③ 부재 + §4.5 참조 dangling | medium | deferred |
| DEBT#469 | L0 "항상 실행" 문장 vs 현행 CI 불일치 | medium | deferred |
| DEBT#470 | SL-09 policy-gate EMPTY 의미 충돌 (checker.mk EMPTY=FAIL vs workflow EMPTY=PASS) | **high** | deferred |

Schema 준수: `debt_integrity_gate`(`src/gate/runners/debt_integrity_gate.nim`) 기대 필드(id 형식 / severity 5단계 / status 4종) 준수; `status: deferred` + "marker deferred"(DEBT#466 선례 — Implementation site가 src/ 밖이라 open⇒source-marker contract 적용 불가)로 **open-STALE FAIL 회피**. Theater 필수 필드(symbol/contentHash/lineRange)는 비-theater 항목이라 불요. `docs/DEBT_REGISTRY.md`는 `tools/gen_debt_registry.nim`으로 재생성 **시도했으나 선존 결함으로 보류** — §6 참조.

---

## 6. 검증 / Completion Evidence

| 명령 | 기대 | 실측 |
|---|---|---|
| `git rev-parse ci-frozen-2026-09-30^{commit}` | 56a7ab1ef | ✓ (§1.2) |
| `jq -e . data/debt_registry.json` | exit 0 | ✓ (200 entries) |
| `python3 -c json.dumps(indent=2) diff` | 항목 추가분만 | ✓ (67 insertions / 3 deletions — DEBT#466 append) |
| docs 링크(§4 대상) | 파일 존재 | ✓ (작성일 기준 생성 완료) |
| `tools/gen_debt_registry.nim` 재생성 | `docs/DEBT_REGISTRY.md` 갱신 | **보류 — 선존 생성기 결함**: 컴파일 성공(5.5s)하나 실행 시 `readEntries`:151 SIGSEGV — `files: null`인 **DEBT#453/454/455(HEAD부터 선존)**의 nil `.kind` 접근. HEAD 레지스트리로 재현 확인(본 변경 무관). 또한 현행 MD는 "Projection: P1 v1"(6열)로 현행 생성기(9열·stats)와 구조 불일치 — 재생성 시 전면 재구조화 + 도구 패치(tools/ — 타 에이전트 소관)가 필요. **사실 등록만 하고 투영은 갱신하지 않음**(SSOT = `data/debt_registry.json`). DEBT#393(closed — "json.getOrDefault returns nil for missing key (SIGSEGV on .kind access)")과 동일 결함 클래스. 코디네이터·코드 에이전트 소관으로 보고. |

> **미해결 (코디네이터 소관)**: ① org admission-gate.yml callee pin의 본 freeze 시점 실측값(§2.1 — 마지막 기록 인용만) ② selector 라인 번호의 병렬 편집 이동 ③ `docs/DEBT_REGISTRY.md` 재생성은 도구 빌드가 필요 — 실패 시 수동 최소 갱신(열 머리글 Total entries/Open 수) 후 보고.

---

*작성일: 2026-09-30. PR-B epoch cutover 문서 트랙 — Freeze/Record/Tombstone. 추가 기록은 본 문서의 이어지는 섹션(코디네이터 승인 후)에 append한다.*

---

## 7. closure-pin rotation 이관 결정 (2026-09-30 — epoch gate G2b 판정, 코디네이터 append)

**사실**: `derived(H)`를 스테이징→snapshot commit→deriver로 기계 산출 — 840멤버 membership 불변, **pin==derived(H) 정확 일치를 달성**(교체 대상 4 sha: `tools/ci/impact_closure_selector.nim` cc85db42→종료 시점值, `tools/ci/proof_reconcile_gate.nim` 322082→종료 시점值, 그리고 **선존 드리프트 2건** `src/cli/merge_cli.nim` 21b3c71e→803166b0, `src/cli/landing_cli.nim` 8e342e6e→9883645d — 후 2건은 base부터 pin이 실제 트리와 불일치한 선존 상태).

**충돌**: 로컬 `check-epoch-transaction`(S0-c) G2b 판정 — `runner-pool-acceptance.yml`(비핀 엔진) 변경 + `config/trusted_writer_set.json`(epoch 정의 = `ProductionPinRecordPath`) 터치 + 본 PR 내 slice 승격 없음 → `EPOCH_TRANSACTION_INCOMPLETE`. 두 법적 경로 모두 본 PR 범위 밖:
- **경로 1(승격 클레임)** = runner-pool의 engineFiles 소유 미승격 slice는 **SL-09뿐** — 계획상 명시적 Out of Scope + 선행조건(DEBT#470 EMPTY 모순) 미충족 + 승격 시 gateway-shard/identity-gate/proof-reconcile 8-way 발화라는 대규모 동작 전환.
- **경로 2(implemented-scope repair)** = epoch 정의(카탈로그·매니페스트 slice 필드·**TWS**·pin) 전부 무터치가 필수 — TWS 회전과 양립 불가.

**결정**: 본 PR은 **경로 2**로 진행 — TWS pin 변경을 base로 되돌림(pin = `origin/main` 동일). 회전은 **SL-09 승격 PR로 이관**(G2b 경로 1의 유일한 합법 차량: 승격 클레임이 runner-pool을 덮는 순간 epoch 정의 터치가 합법화됨). 승격 시점에 위 4 sha를 **재산출**하여 원자 갱신(계획 단계 5 본래 의미 유지).

**런타임 영향 실측**: merge_cli rotation 판정 입력(`AXIOM_DERIVED_{H,B}_PATH`·`AXIOM_PIN_H_PATH`)은 오늘 비활성 — PR-A(385) admission 런에서 rotation 발화 0건 실측, `derived(B)`는 base workflow의 `fail()` 8건 UNRESOLVED로 deriver 자체 실패(본 PR이 H에서 인라인 수정). pin 미갱신 상태의 현행 강제 리스크 = 0, org pre-gate 활성화 시점까지 SL-09 승격 PR로 회전 필수 — **DEBT#471로 등록 대신 본 기록 + PR-B 본문에 명시**(레지스트리 churn 회피).
---

## 8. Production Acceptance 실측 기록 (2026-09-30 — 단계 9 Terminal Outcome 달성)

### 8.1 랜딩 체인 (전부 GitHub 네이티브 MERGE, 머지 큐 경유)
| PR | 내용 | 머지(UTC) |
|---|---|---|
| #385 | AGENTS.md 죽은 참조 3건 (PR-A) | (기록: `gh pr view 385`) |
| #389 | surface v36 — 본 기록·계약·픽스처 3경로 CONTROLLED 선등록 (PR-B0) | 06:29:06 |
| #391 | claim-proportional PR-B — epoch cutover 단계 4–7 (**단계 8 Canonical Cutover**) | 06:59:31 |
| `.github` #37 | callee pin 회전: gateway `runner-pool@4b7719e1 → 48cb16ab2` (ADR-0025 §7 step 2) | 07:15 급 |
| #393 | vehicle Δ #1 — **run-0(구 callee, CE 미달 실측)** | 07:24:51 |
| #397 | vehicle Δ #2 — **재관측 합격(단계 9)** | 08:05:13 |

### 8.2 run-0 진단 (#393, run 36682252299 — 계획 블로커 실증)
org `admission-gate`의 gateway callee pin(`runner-pool@4b7719e1`)이 구버전 호출 → oracle 체인 미발화:
`mode=selected{W8}`·`oracleEvidence=null`(artifact에 evidence 부재)·ci-bootstrap 실주행 3m54s. decision-report 자체는 `selectedWorkUnits=[]`(분석은 정상 — legacy floor 경로만 활성). = "runner-pool 변경이 pin에 갡힘 → 조직 SHA 회전 선행 후 **재관측**" 블로커 예상 그대로.

### 8.3 회전 절차와 deviance
1. `.github` PR #37로 gateway callee pin → `48cb16ab2`(#391 머지 커밋) 회전.
2. **org ruleset `axiom-admission-gate`(구 id 24041674)의 workflows sha 갱신이 REST로 불가**: `sha` 필드 포함 PUT/POST가 전부 HTTP 500(7페이로드 변형 실증 — 조건/버전/Content-Type 배제, sha 없는 조합만 201). GitHub 측 쓰기 버그 상태.
3. **대체**: sha-less 재등록 — `landing-integrity` 규칙 선례(`ref: main`)와 동일. 구 규칙 삭제 → **신규 id 24233738**(name axiom-admission-gate, enforcement active, conditions refs/heads/main + repository Axiom, rule admission-gate.yml@ref main) 생성·검증. K 불변식 의미(`admission-gate@main == K`)는 ref 강제로도 보존; **후속: API 복구 시 sha 재핀 시도**(본 기록이 추적 근거).

### 8.4 재관측 CE 실측 (#397, run 36686145375) — 전부 합격
- **CE#15**: select 로그에 `git worktree add --detach /tmp/btree "$B"` → `cd /tmp/btree` → `nim c`(컴파일 경로 `/tmp/btree/tools/…`) → `proof_reconcile_gate` 동일 B-빌드 → `--ref $HEAD` H 데이터 실행 → decide `--oracle-evidence` 전달 — 전 흔적 확인. select steps=15(구버전 13 대비 +2).
- **CE#17**: `oracle-evidence.json` 5축 전부 `deltaAbsent/unchanged`(`executionClosure.digest=7384e5df…`, method `derive_checker_closure(B-전체트리)`), `derivedEmpty=true`, `derivationDigest=75fd068b…` 자검증 통과. `decision.json` = `mode=none ∧ selectedWorkUnits=[] ∧ executableWorkUnits=[] ∧ ciBootstrap=false ∧ landingPolicyFloor=false ∧ derivedEmpty=true` + `oracleEvidence` envelope.
- **CE#16**: ci-bootstrap·candidate-build-arm = `conclusion=skipped ∧ steps=0`(row 존재, started==completed 동일시각 = 미실행). **`startedAt=null` 기대는 GitHub jobs API의 생성시각 채움과 불일치** — 표현 차이로 기록(취소·미생성은 conclusion/steps로 기계 구분 가능 — C8 취지 유지).
- **admission-check success** → 머지 큐 → MERGED.

판정: **검증 계산 2→0 + 오라클 실사용(B-전체트리 빌드) 실측 달성** (계획 Terminal Outcome 충족).

---

## 9. 보류 항목 해소 (2026-09-30)

- §5·§6의 "`tools/gen_debt_registry.nim` 재생성 보류 — 선존 생성기 SIGSEGV(DEBT#453/454/455 `files` 키 부재 → nil `.kind`)" 항목은 **PR #400으로 도구 자체를 삭제**해 해소. SSOT는 `bin/debt_engine --codegen` 단일이며 projection byte-identity 게이트([4.5])가 정본 비교를 계속 담당함. 삭제 전 SIGSEGV 재현(exit 139)·참조 0건 실측은 PR #400 본문 참조.

---

## 10. §2.3 관측 계약 재정착 (2026-09-30 — P6 흡수, authority/adapter 분리)

**사실**: 사용자 authority-first 재정의와 R2 반박 판정(완료분)에 따라 AGENTS.md §2.3을 "GitHub authority / required-check adapter 분리"로 재구성했다. 기존 잔여 이슈 **P6(§2.3 개정)**을 본 작업이 흡수.

- **권위 모델 (R2 판정 + 사용자 3차 지시 정정 3건)**:
  ① `gh pr checks`는 끝까지 **adapter** — PR required check는 merge-admission 선행조건 중 checks 층의 **PR-head 투영**이며, 권위 상태 = ruleset 평가 + merge queue 상태 머신 + 병합 종결(`Authority ≠ Adapter`).
  ② `gh run watch`는 하위 어댑터가 아니라 **별도 관심 객체(특정 run·merge_group run)의 관측 도구** — 공식 문서에 강등 분류 없음.
  ③ hand-rolled polling 금지는 **프로젝트 정책**으로 명시(공식 근거: GitHub webhook 권장·rate-limit best practice).
- **관측 3층 확정**: L1(PR-head checks — 상태 판정 + `--required --watch --interval 30` 완료 대기) → L2(mergeQueue GraphQL entry state) → L3(`state=="MERGED"` ∧ `mergeCommit.oid` 존재). **L1 성공만으로 admission 완료를 주장하지 않는다.**
- **0 checks 원칙**: required checks 0건 = **UNKNOWN / NOT READY, SUCCESS 금지**. gh 2.45.0 `--required`는 0건 시 "no required checks reported"로 비0 종료(v2.45.0 소스 `populateStatusChecks` 확인) — adapter 수준에서도 SUCCESS 신호가 없음을 실측·소스로 뒷받침.
- **F 판정(정본 명령 형식, 로컬 실측)**: `gh pr checks <PR> --required`에 admission-check 행이 나타남(PR #403 실측) → **`--required` 포함 형식 확정**. 단 gh 2.45.0은 `--json` 미지원(`unknown flag` 실측) → JSON 기계 판정은 REST `commits/<head_sha>/check-runs`(name=="admission-check" ∧ completed ∧ success) + ruleset required_status_checks 교차 확인으로 정본화.
- **R1/R3 상태**: 백그라운드 병렬 심화 반박(기능·exit·ruleset 인식·0건 race/이슈 원문 실증) **진행 중** — 결과는 코디네이터가 별도 수금하며, 본 §10은 완료분 R2·사용자 3차 지시만 반영한다.
- **adapter 한계 각주**: cli/cli **#9228**(OPEN, org ruleset run 404)·**#7401**(CLOSED, 0-check race)·**#14253**(CLOSED, REST↔CLI check-rollup 불일치 → CLI green 오보고)·gh 2.45.0 `--json` 미지원 — 각각 `gh issue view`로 실존·상태를 직접 확인 후 기재. "새 정본이 모든 문제를 해결"이라는 표현은 쓰지 않는다.
- **증거 귀속 규약**: 모든 관측 기록에 `PR number / head SHA / timestamp(UTC) / 관측 원문(JSON) / REST check-runs 관측 / context = pr-head | merge_group` 명시 — merge_group 컨텍스트와 PR-head 컨텍스트의 구분 귀속 의무.
