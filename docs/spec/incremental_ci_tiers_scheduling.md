# L0/L1/L2 Verification Tiers & Deterministic CI Scheduling Spec

> **종류**: Normative specification (P3 design input).
> **작성일**: 2026-08-28.
> **권위 입력**: P2 계약 §4–§5 (원 anchor `docs/spec/incremental_ci_contract.md`는 CI=0 cutover, 2026-09-20로 삭제 — 보존된 ADR-0017이 P2 계약 참조본), `docs/reports/ci_observed_dag_p1_2026-08-28.md` (W1–W11 관찰), `tools/ci/impact_closure_selector.nim` (L1 selector 구현).
> **범위**: 증분 검증의 등급(tier) 정의, 결정적 스케줄링 불변식, impact-closure selector의 L1 피딩. CI wiring(`.github/workflows/ci.yml`)은 CI=0 cutover(2026-09-20)로 소멸 — CI 적용 경로는 종료, tier·스케줄링 모델은 설계 계약으로 유지.

---

## 1. 목적

이 사양은 P2 증분 검증 엔진(P2 계약 — 원 anchor `docs/spec/incremental_ci_contract.md`는 CI=0 cutover, 2026-09-20로 삭제, ADR-0017이 참조본)에서 정의한 안전 Skip 사다리(§5)를 **구체적 검증 등급(Tier)**으로 세분화하고, 각 Work Unit(W1–W11)의 등급 멤버십을 선언하며, 동일 커밋+동일 그래프+동일 계약 → 동일 작업 단위 선택을 보장하는 **결정적 스케줄링 불변식**을 정의한다.

---

## 2. Tier 정의

### 2.1 L0 — 즉시 (Immediate)

| 속성 | 값 |
|---|---|
| **대상** | 문법/정적 검증 + 타겟 로컬 테스트 |
| **소요시간** | **초 단위** (≤ 3분) |
| **실행 조건** | 변경이 순수 문법/주석/비-normative 문서에 한정되거나, 캐시 히트가 확실한 경우 |
| **스케줄링** | `SelectedWorkUnits(Commit) ∩ L0` — 영향 폐쇄가 비어있으면 L0만 실행 |
| **목적** | 가능한 한 자동화된 즉시 피드백. 캐시 히트로 0-cost 반환. |

L0 Work Unit은 **변경에 독립적으로 항상 실행 가능**하며, 영향 폐쇄가 공집합이더라도 실행되어야 한다(정적 검증은 항상 유효).

### 2.2 L1 — 변경 영향 검증 (Change-Impact Verification)

| 속성 | 값 |
|---|---|
| **대상** | 일상 개발 반복(day-to-day dev iteration)에서 **여야 하는** 변경 |
| **소요시간** | **초~분 단위** ( tens of seconds to minutes) |
| **실행 조건** | `DependencyClosure(Change, ContractGraph)`가 비어있지 않은 Work Unit만 선택 |
| **스케줄링** | `SelectedWorkUnits(Commit) = DependencyClosure(Change, ContractGraph) ∩ {W | tier(W) ≤ L1}` |
| **목적** | 작은 변경은 작은 폐쇄에 소요. **대부분의 개발 반복이 여기 착지**. |

L1은 **impact-closure selector** (`tools/ci/impact_closure_selector.nim`)가 결정적으로 계산한다. L1은 L0를 포함하지 않으며, L0은 캐시 히트로 즉시 반환되고 L1은 영향받는 Work Unit만 재실행한다.

### 2.3 L2 — 전체 인증 (Full Certification)

| 속성 | 값 |
|---|---|
| **대상** | 릴리스 경계(release boundary) — **필수**; main 착지의 UNCERTAIN fallback |
| **소요시간** | **1h 이하 적절** (현재 기준 69m26s post-opt) |
| **실행 조건** | release 출하(release-ship dispatch) = 모든 Work Unit(W1–W11 + W9) 실행(예외 없음) — 현행 CI 9-job 전체 기준(미실행 격자 W1·W3–W7·W9–W11은 **DEBT#466**) (ADR-0024 결정 #15 — A1.3 supersede); main 착지 = `provenRequired(Δ)`만 실행, UNCERTAIN이면 전체(§5) |
| **스케줄링** | release tag: `SelectedWorkUnits(Commit) = {W1, W2, …, W11, W9}` — 영향 폐쇄와 무관하게 전체; main 착지: `SelectedWorkUnits(Commit) = provenRequired(Δ)`, UNCERTAIN → 전체 |
| **목적** | 깨끗한 빌드 + 전체 통합 + 증명 우주 + 전체 커버리지. **L2 티어는 소거되지 않음(티어 소거 금지 ≠ 개별 착지 전체 실행).** |

L2는 **작은 변경이 L2 비용을 지불하지 않도록** 하는 경계이다. 작은 변경은 L0/L1만 통과한다. **L2 티어 자체는 소거되지 않으며**, release 출하 경로(release-ship dispatch, 태그 생성 전 — ADR-0024 결정 #15)에서는 반드시 full L2(전체 실행)가 수행되고, main 착지(merge-to-main)에서는 `provenRequired(Δ)`만 실행된다(UNCERTAIN이면 full L2 — ADR-0017 Amendment A1).

---

## 3. Tier Membership of Work Units (W1–W11)

**Tier membership의 유일 권위 = `src/gate/proof_unit_catalog.nim` (2026-09-23).**
W1–W11의 `id`/`name`/`pathPatterns`/`durationMin`/`tier`/`requiredForFullCertification`/`subunits` 값은 Catalog(`ProofUnitCatalog`)에만 존재하며, 이 문서는 **값을 재선언하지 않는다** — 표와 값 요약은 의도적으로 생략한다(중복 선언 시 drift 위험, §5 SSOT 원칙). 서브유닛 멤버십(W4/G7 등)은 Catalog의 `subunits` 필드로 표현된다.

역사적 근거 (결정 입력, 2026-08-28): P1 관찰 DAG(`docs/reports/ci_observed_dag_p1_2026-08-28.md` §1)와 P2 계약 §2.1(원 anchor `docs/spec/incremental_ci_contract.md`는 CI=0 cutover, 2026-09-20로 삭제 — ADR-0017이 참조본). 당시 값 요약: L0={W3, W4/G7, W10, W11}, L1={W1, W2, W4(컨테이너), W4/G1, W4/G2, W4/G6+G4, W5, W6, W7, W8}, L2=전체 파이프라인.

### 3.1 Tier Membership 요약 — 참조

멤버십 값의 나열은 의도적으로 생략한다. 유일 권위: `src/gate/proof_unit_catalog.nim` `ProofUnit.tier` (2026-09-23).

### 3.2 Tier 전이 규칙

- **L0 → L1**: L0 단위가 항상 실행되고, L1 단위가 영향 폐쇄에 의해 선택됨. L0는 L1의 선행 조건이 아님 (L0는 독립 실행).
- **L1 → L2**: L1에서 선택된 단위 + L0 + L2 전용 단위(W9) = 전체 파이프라인.
- **L0 단독 실행 (PR/개발 반복에 한정)**: 변경이 비-normative 문서(README 등) 또는 캐시 히트인 경우, L0만 실행하고 L1/L2는 스킵. 이 규칙은 **PR 브랜치 푸시(개발 반복)에만** 적용되며 main 착지·릴리스 경계에는 적용되지 않는다 — main 착지는 `provenRequired(Δ)`(§5), release 출하는 full L2(§2.3)가 실행된다(ADR-0024 결정 #15 — A1.3 supersede). **(:71 vs §5 내부 긴장 해소 — 해석 기준은 Amendment A1 + ADR-0024 supersede 표기가 최우선)**

---

## 4. 결정적 스케줄링 불변식 (Deterministic Scheduling Invariant)

### 4.1 불변식 선언

> **SelectedWorkUnits(Commit) = DependencyClosure(Change, ContractGraph)**

동일한 커밋 + 동일한 ContractGraph + 동일한 변경 집합 Δ → **동일한 Work Unit 선택**. 인간 판단(judgment) 없이, 결정적 알고리즘만으로 선택이 산출된다.

형식적으로:

```
SelectedWorkUnits(C) ≡ { U | closure(Δ_C) ∩ inputClosure(U) ≠ ∅ ∧ tier(U) ≤ Tier(C) }
```

여기서:
- `C` = 커밋 (base + head + repo state)
- `Δ_C` = C의 변경 집합 (git diff에서 결정적 산출)
- `closure(Δ_C)` = Δ_C의 전이적 종속성 폐쇄 (§3.1 추적 체인)
- `inputClosure(U)` = Work Unit U의 입력 폐쇄 (§2.1)
- `tier(U)` = Work Unit U의 등급 (L0/L1/L2, §3)
- `Tier(C)` = 커밋 C에 적용할 최대 등급 (L0/L1/L2, §5 스케줄링 정책에 의해 결정)

### 4.2 결정성 보장 조건

1. **Change Fingerprint**: `impact_closure_selector.nim` §6의 `computeFingerprint`는 변경 파일의 `(path, blobHash)` 쌍을 정렬하여 SHA256을 산출. 동일한 변경 → 동일한 지문.
2. **ContractGraph**: P2 계약 §2.1의 W1–W11 입력 폐쇄 정의 + §3 종속성 폐쇄 규칙이 유일한 참조 (원 anchor `docs/spec/incremental_ci_contract.md`는 CI=0 cutover, 2026-09-20로 삭제 — ADR-0017이 참조본). W1–W11 입력 폐쇄 값(`pathPatterns`)의 편집 권위: `src/gate/proof_unit_catalog.nim` (2026-09-23).
3. **TierPolicy**: `Tier(C)`는 CI 트리거 유형(PR vs release — push-to-main는 2026-09-29 트리거 폐기, ADR-0025 Amendment B)에 의해 결정되며, 이 문서 §5에서 정의. 동일 트리거 유형 → 동일 TierPolicy.
4. **정렬(Deterministic Ordering)**: `impact_closure_selector.nim` §7 `mapToWorkUnits`는 결과를 `unit.id` 기준 정렬(`result.sort(proc(a, b: AffectedUnit): int = cmp(a.unit.id, b.unit.id))`). 동일 입력 → 동일 순서.

### 4.3 비극장적(non-theater) 요구사항

- `SelectedWorkUnits(C)`는 **vacuous하지 않다** — `closure(Δ) ∩ inputClosure(U)`는 구체적인 파일/모듈 집합의 교차이다.
- Skip은 `affected(U, Δ) == false`가 **provably**일 때만 허용된다(§0.9b triple-closure 검증 대상).
- "아마 영향을 받지 않았을 것이다"와 같은 판단은 허용되지 않는다.

---

## 5. 스케줄링 정책 (Tier Assignment by Trigger)

| CI 트리거 | Tier(C) | SelectedWorkUnits | 정당화 |
|---|---|---|---|
| **PR branch push** (소규모 변경) | L0 | L0만 실행 (W3, W4/G7, W10, W11) | README/주석 변경 등은 L0만 통과하면 충분 |
| **PR branch push** (일반 변경) | L1 | `DependencyClosure(Δ, ContractGraph)` ∩ {L0, L1} | 일상 개발 반복의 기본. 대부분의 PR이 여기 착지 |
| ~~Push to main / merge-to-main (main 착지)~~ **트리거 폐기 (2026-09-29, ADR-0025 Amendment B)** | — (main 착지 Actions 실행 0) | 의무는 candidate(PR 게이트)가 승계: `provenRequired(Δ)`는 게이트 런에서 실행, 판정 **UNCERTAIN → L2 전체**; 머지 시 씨딩만 = workflow_run `ci-cache-publisher`(가속) | 머지 = 순수 GitHub 네이티브 ref 이동. (기존 문언: L1 provenRequired · L2 fallback — ADR-0017 Amendment A1) |
| **Release 출하 (release-ship dispatch)** | L2 | {W1, W2, …, W11, W9} 전체 | 릴리스 경계에서 전체 인증 **필수(예외 없음)** — 현행 CI 9-job 전체 기준(미실행 격자 W1·W3–W7·W9–W11은 **DEBT#466**) (ADR-0024 결정 #15 — A1.3 supersede, tag push 트리거 제거) |
| **Manual `ax prove --full`** | L2 | 전체 파이프라인 | 명시적 전체 실행 요청 |

### 5.1 Tier(C) 결정 규칙

`Tier(C)`는 `impact_closure_selector.nim`이 아닌 **CI 워크플로 수준**에서 결정되었으려 했다 (원 정의처 `.github/workflows/ci.yml` — CI=0 cutover, 2026-09-20로 삭제됨; CI wiring은 아키텍트 승인 제안에 의해 연기된 뒤 종료). 이 문서에서는 Tier(C)의 결정 규칙만 정의한다:

1. PR branch에서 `paths-ignore`에 매칭되는 변경(비-normative 문서) → L0
2. PR branch에서 그 외 변경 → L1
3. Push to main / merge-to-main (main 착지) → **2026-09-29 트리거 폐기(ADR-0025 Amendment B): main 착지 Actions 실행 0** — `provenRequired(Δ)` 의무는 candidate(PR 게이트)가 승계 실행 (기존: ADR-0017 Amendment A1 A1.2).
   `docs/spec/` normative 문서 변경 등 G4 갭 영향은 conservative over-approximation으로 처리하며,
   판정이 **UNCERTAIN이면 Tier(C) = L2 전체**로 fail-closed.
4. Release 출하(release-ship dispatch, 태그 생성 전 — v* tag push 발화 경로는 ADR-0024가 폐기) → L2 전체 (필수, 예외 없음 — ADR-0024 결정 #15; A1.3 supersede)
5. `ax prove --full` CLI flag → L2

---

## 6. Impact Closure Selector의 L1 피딩

### 6.1 역할

`tools/ci/impact_closure_selector.nim`은 L1 스케줄링의 **결정적 엔진**이다. 이 도구는:

1. `git diff --name-status base..head`로 변경 파일 목록을 취득 (§5, `getChangedFiles`)
2. 각 변경 파일에 대해 `pathPatterns` 기반 직접 매칭 + `semanticRules` 기반 의미적 매칭을 수행 (§7 `mapToWorkUnits`)
3. `computeFingerprint`로 변경 지문을 결정적으로 산출 (§6, SHA256 of sorted `path blobHash` lines)
4. 영향받는 Work Unit 목록을 정렬하여 출력 (§7, `result.sort` by `unit.id`)
5. `ShadowReport` JSON으로 출력 (§9 `reportToJson`)

### 6.2 L1 선택 알고리즘

```
Input:  base ref, head ref, ContractGraph (W1–W11 inputClosure + semanticRules)
Output: AffectedUnit[] (정렬, 결정적)

Algorithm:
  1. changedFiles ← git diff --name-status base..head
  2. fingerprint ← SHA256(sorted(changedFiles × blobHash))
  3. For each WorkUnit U in catalog:
       a. Direct match: any changed file matches U.pathPatterns → AFFECTED
       b. Semantic rule: U.semanticRules triggers on changed file set → AFFECTED
       c. Transitive closure: core import graph BFS → AFFECTED
       d. Conservative over-approximation (§3.2): unknown → broader unit AFFECTED
  4. Sort selected units by unit.id
  5. Return AffectedUnit[]
```

### 6.3 L1에서 L0으로의 연계

L0 Work Unit(W3, W4/G7, W10, W11)은 impact-closure selector의 선택 범위에 **항상 포함**된다. 이들은 영향 폐쇄와 무관하게 실행되어야 하며, selector는 L0을 "baseline"으로 항상 출력에 포함한다. L1 선택은 L0 baseline 위에 추가되는 영향받는 Work Unit들이다.

### 6.4 한계 (documented in source)

`impact_closure_selector.nim`의 주석(라인 16–22)에서 문서화된 한계:

- `import_graph.nim`을 import할 수 없음 (checksums/sha2 의존성 갭) → core transitive-dependency resolution은 inline BFS로 재구현
- W9(ci-lake-build) duration이 UNKNOWN → 비용 합계에서 제외
- G4 (normative doc → cache-key invalidation) 미연결 → conservative over-approximation 적용
- Makefile 보편적 인보크 과대추정 → W1–W9를 과도하게 claim할 수 있음

---

## Amendment (2026-09-30): L0 "항상 실행" 문장 vs 현행 CI 불일치 기록 + Known-branch witness (PR-B 문서 트랙)

> **개정(amendment) 선언**: 본 절은 이 문서에 대한 개정 노트이다. §2.1·§5·§6.3 본문의 L0 관련 문장(:25-28, :71, :116, :166-168 — "영향 폐쇄가 공집합이어도 L0은 항상 실행")을 **수정·재해석하지 않으며**, 계약(설계)과 현행 CI(실행) 사이의 불일치 사실을 병존 기록한다. 연동: ADR-0017 Amendment A2 · ADR-0025 Amendment C(2026-09-30) · `docs/evidence/epoch_record_oracle_select_2026-09-30.md`.

1. **L0 문장 불일치 기록**: §2.1(:28 — "영향 폐쇄가 공집합이더라도 실행되어야 한다(정적 검증은 항상 유효)") 및 ADR-0019:25·:66·:92의 "L0는 항상 실행" 문장은 격자 모델의 **계약(설계)**이다. 현행 CI(CI=0 cutover 이후 유일 실행 인프라 `.github/workflows/runner-pool-acceptance.yml`, 9-job)는 L0 격자(W3·W4/G7·W10·W11)를 별도 실행하지 않으며 DEBT#466(2026-09-23)으로 미실현이 공식 등재되어 있다. 본 개정은 두 문장이 **계약과 실행 사이의 불일치 상태**임을 명시한다(DEBT#469).
2. **Known-branch witness 기록**: 현행 9-job CI가 제공하는 검증 witness는 **known branch**(착지 candidate admission · release 출하 경로)에 한정되며, 격자 프로젝션 밖 W4 클래스(컨테이너 W4·서브유닛 G1/G2/G6/G7)의 실행·witness는 현재 미실현이다(DEBT#466 b+ 개정, ADR-0019 Status 2026-09-30).
3. **L0-baseline carve 연동**: L0 단위는 오라클 예측(`ExpectedAffected`) 대상 밖 carve — `docs/spec/canonical_execution_semantics.md` 부록 D ④(2026-09-30 Amendment)에서 설계 계약으로 기록(현행 미실현).

---

## 7. CI Wiring 연기 (Deferred — CI=0 종료, 2026-09-20)

`.github/workflows/ci.yml`은 과거 §-1에 의해 **불변(immutable)**이었고, CI wiring은 아키텍트 승인 제안(proposal)을 기다렸다. **CI=0 cutover(2026-09-20)로 워크플로가 전부 제거되어 해당 wiring 경로는 종료됨.** 이 문서는 **설계 문서만** 제공하며, 실제 CI 파이프라인에 Tier(C)와 impact-closure selector를 연결하는 것은 별도의 아키텍트 승인 프로세스를 거쳐야 했다.

### 7.1 연기 항목

| 항목 | 상태 | 참조 |
|---|---|---|
| CI 워크플로에 Tier(C) 스케줄링 통합 | **종료** — CI=0 cutover, 2026-09-20 (워크플로 제거) | `.github/workflows/ci.yml` (§-1 불변 → 삭제됨) |
| `impact_closure_selector.nim`을 CI job에 연결 | **종료** — CI=0 cutover, 2026-09-20 | `tools/ci/impact_closure_selector.nim` |
| Per-step cache key wiring (G4, G8) | P3로 연기 | P2 계약 §7 (원 anchor `docs/spec/incremental_ci_contract.md`는 CI=0 cutover로 삭제, ADR-0017 참조본) |
| `ci-lake-build`(W9) duration 측정 | G1 갭, 독립 측정 필요 | `docs/reports/ci_observed_dag_p1_2026-08-28.md` §4 |

---

## 8. 참고 문헌

- P2 계약 SSOT (Work Unit 모델, 불변식, 종속성 폐쇄 규칙) — 원 anchor `docs/spec/incremental_ci_contract.md`는 CI=0 cutover, 2026-09-20로 삭제, 보존된 ADR-0017이 P2 계약 참조본.
- `docs/reports/ci_observed_dag_p1_2026-08-28.md` — 관찰된 CI DAG (W1–W11 + G1/G2/G4/G6/G7 provenance).
- `docs/reports/ci_avoidable_work_matrix_p1_2026-08-28.md` — Δ×work-unit 행렬 + §5.3 cache-key wiring 요구사항.
- `tools/ci/impact_closure_selector.nim` — L1 impact-closure selector 구현 (P3 shadow mode).
- `src/gate/proof_unit_catalog.nim` — W1–W11 catalog SSOT (id/name/pathPatterns/duration/tier, 2026-09-23 cutover).
- `src/verification/obligation/identity.nim` — `CanonicalExecutionBundle`, `ExecutionContract`, `ExecutionIdentity`.
- `.github/workflows/ci.yml` — CI 파이프라인 정의 (CI=0 cutover, 2026-09-20로 삭제됨).
- `docs/spec/productization_contract.md` — v1 제품 계약 (CI 플랫폼 자체는 non-goal).

---

*작성일: 2026-08-28. P3 증분 CI 등급 & 스케줄링 normatvie 사양. 모든 Work Unit, 등급, 불변식은 P1/P2 보고서에 기반하며 UNKNOWN 항목은 정직하게 미기재됨. CI wiring은 아키텍트 승인 제안에 의해 연기됨.*
