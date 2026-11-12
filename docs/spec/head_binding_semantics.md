# HEAD Binding Semantics — "git HEAD"의 3분법과 세대 스코프 결정 기록

> **Status**: Phase 2 — 의미 확정 기록 (NORMATIVE, docs-only). 코드·워크플로·스키마 변경 0건.
> 본 문서는 Judgment CAS(Execution CAS / test-judgment CAS) 문맥에서 혼용되기 쉬운
> **"git HEAD"의 세 가지 서로 다른 의미**를 3분법으로 고정하고, 세대 축(성분 ⑤ — v1.0.0
> 당시 B^{tree}, 현행 v3 semantic set digest S = TreeUniverse(R) − N, R = 후보 M^{tree})의
> **유지 결정**과 그 축소 조건의 **범위 밖** 판정, `test_d2_golden` 14테스트에 대한 **독립
> stage 계약 판정**을 기록한다.
> **정본 계약**: `docs/spec/test_judgment_cas_contract.md` (§4 9성분, §5 REUSED 5조건 —
> 본 변경으로 v1.0.2: §4에 3분법 교차참조 추가. 본 문서 v1.0.1은 계약 v1.0.6 — §4 성분 ⑤
> R = 후보 M^{tree} 실측 정정 — 과 동기화).
> **근거 문서**: `docs/evidence/judgment_cas_reused_hit_root_cause_2026-10-09.md` (#611 HIT vs
> #613 MISS 실측 — 본 문서가 "§4.4 후속"으로 수용하는 잔여 보수성 여유의 실측 원천).
> **비개정**: `docs/spec/obligation_semantics.md` §2.1a `|git=`(subjectGitRef) — §1.4에서
> 명시적으로 개정하지 않음을 선언한다. `docs/spec/productization_contract_freeze_v1.md`
> (FROZEN, E1–E5)도 개정하지 않는다.
> **작성일**: 2026-10-09. **최종 개정**: v1.0.1 (2026-11-01 — pre-split B^{tree} 서술 정정,
> 결정·판정·스킴 무변경). 브랜치 `docs/head-binding-semantics`.

---

## 1. "git HEAD"의 3분법 (Trichotomy)

Judgment CAS 논의에서 "HEAD"는 세 개의 서로 다른 질문에 답하는 서로 다른 참조다.
혼용은 세대 축의 불필요한 축소(§1.2) 또는 불필요한 확장(§1.3)으로 이어지므로, 본 절이
어휘를 고정한다. 9성분 클로저(`test_judgment_cas_contract.md` §4)는 아래 셋으로 분해된다.

| 축 | 의미 | 클로저 성분 | identity 참여 |
|---|---|---|---|
| ① | **인과 입력** (causal inputs) — 이 판정은 무엇을 읽고 무엇으로 실행되었는가 | 성분 1–4·6–9 (테스트 소스·전이 소스 클로저·픽스처 digest, 툴체인 번들, env 스냅샷, recipe, NimVersion, 실행 구성) | 예 — 매칭은 컨텐츠 digest로만 |
| ② | **검증자 세대** (verifier generation) — 이 판정을 산출한 검증자는 어느 트리인가 | 성분 ⑤ = **semantic set digest** S = TreeUniverse(R) − N (도출 권위 `src/verification/semantic_set_derivation.nim`; 피험 트리 R = **후보 M^{tree}** — `admission-check.yml` judgment plan이 `AXIOM_JUDGMENT_CAS_TESTED_TREE_OID`로 export). v1.0.0 당시의 "⑤ = B^{tree} — executor/workspace 트리 OID 전체 결속" 서술은 pre-split 기록이며 B/M 분할(f96f37f5d, 2026-10-20)으로 대체됐다 | 예 — **유지·약화 금지 (§1.2)** |
| ③ | **기록 정체성** (record provenance) — 이 실행 기록은 어느 run 소속인가 | 9성분 어디에도 없음 — run HEAD(H·G), `mergeSha`/`mergeTreeDigest`, `github.run_id`/`run_attempt`, `prHeadSha` | **아니오 — provenance 블록 한정** |

### 1.1 축 ① — 인과 입력 (fixture·검증 소스·툴체인·recipe)

매칭은 컨텐츠 digest로만 이루어진다. 브랜치명·커밋 제목·run 소속 커밋 문자열은 축 ①의
구성원이 아니다. 이는 축 ③의 필드가 identity에 들어가지 않는 이유이기도 하다(§1.3) —
같은 클로저라면 어느 run이 찍어도 같은 키여야 한다.

### 1.2 축 ② — 검증자 세대 (closure 성분 ⑤ — 현행 v3: semantic set digest) — 유지·약화 금지

성분 ⑤는 **검증자 세대**를 고정한다 — 현행(v3) 도출은 **semantic set digest**
S = TreeUniverse(R) − N(`src/verification/semantic_set_derivation.nim`)이고, 피험 트리
R은 **후보 M^{tree}**(베이스 팁 ∪ PR 변경의 merge-queue 후보 머지 커밋 트리 — 워크플로가
`AXIOM_JUDGMENT_CAS_TESTED_TREE_OID` = M^{tree}를 export)다 — `admission-check.yml:3132`·`:3216`.
R 자체는 키 밖 probe 앵커다. v1.0.0(2026-10-09) 당시의 "⑤ = B^{tree} — 피험 트리가
아니라 검증자(실행자) 세대" 전체 결속은 pre-split 기록으로, B/M 분할(f96f37f5d,
2026-10-20)로 대체됐다(정본: `test_judgment_cas_contract.md` v1.0.6 §4). 이 축의 축소·대체
(예: "검증자 바이너리 의미만 불변이면 충분하다"는 이유로 세대 축 ⑤를 빼거나 더 거친
grain으로 바꾸는 것)는 금지된다. 근거는 두 가지이며, 어느 하나만으로도 금지가 성립한다:

1. **극장(theater) 경로**: 새 검증자 세대가 구세대 판정을 무재측정으로 통과시키면,
   검증자 회귀가 낡은 판정을 통과시키는 길이 열린다. 이는 Gate A의 자가인증 금지
   (`build_sha==B` — "no self-build — authority 정규성 [B1]")과 계약 §5(e)(도구 정체성
   일치)이 존재하는 이유 그 자체다 (root-cause 문서 §4.1 실측 판정).
2. **원장 same-key/different-payload 충돌**: 세대 축을 키에서 제거하면 서로 다른 세대가
   **같은 키**를 산출하면서 페이로드(클로저 지문·`executionEpoch`)는 서로 달라진다.
   원장 append의 멱등성 계약은 "same key + same payload bytes — the append is an
   idempotent no-op"(`.github/workflows/admission-check.yml` append 주석, 현행 :1227·:1251;
   계약 §7.2)인데, same-key/different-payload는 이 계약과 정면충돌한다 — append는
   거부되거나, consult가 현재 클로저와 일치하지 않는 세대의 페이로드를 되돌려주는
   부정 재사용 경로가 된다. 업계 선행도 동일 경고를 한다: Gradle build cache —
   "Missing task inputs can cause **incorrect cache hits**, where different results are
   treated as identical because the same cache key is used by both executions"
   (§4 Gradle 항).

### 1.3 축 ③ — 기록 정체성 (run HEAD/mergeSha/runId/prHeadSha = provenance 한정)

- run의 HEAD 커밋(H — PR head), merge head(G — mergeSha), `github.run_id`/`run_attempt`,
  `prHeadSha`는 **기록의 소속·추적성 서술**이지 재사용 키의 구성원이 아니다.
- 실측 근거 (root-cause 문서 §2 표): #611 사이클에서 PR-run(37811664465)과 MG-run
  (37813905412)은 run HEAD도 runId도 다르지만 성분 ⑤(당시 결속 = B^{tree} — pre-split
  시대 실측)가 동일했고 → 동일 키 `b5b10096…`로 **REUSED**. #613 PR-run도 cross-run
  REUSED로 동일 실증. run 정체성이 identity에 참여했다면 cross-run REUSED는 원천적으로
  불가능했을 것이다.
- witness 필드의 의미는 ADR-0027 α가 고정한다: `prHeadSha`는 SUBJECT head(H_PR),
  `mergeSha`/`mergeTreeDigest`는 RUN head(G)를 결속하는 provenance 서술이다 —
  둘 다 reuse 키가 아니다. 본 문서는 이 지위를 **변경하지 않는다**.

### 1.4 `obligation_semantics.md` §2.1a `|git=`(subjectGitRef) — 개정 없음

§2.1a의 `|git=` 세그먼트(subjectGitRef)는 본 3분법의 어느 축과도 다른 수준의 참조다 —
**증거 대면(evidence-facing) bound identity**에서 피험 subject(verified code)를 고정하는
성분이다. "이 증거가 무엇에 대한 것인가"(§2.1a)와 "이 test-judgment를 어느 세대에서
재사용할 수 있는가"(축 ②)는 서로 다른 질문이며, 전자의 `|git=`는 subject 고정 identity로
**그대로 유지한다 — 개정 없음**. 본 문서는 §2.1a의 어떤 문구도 변경하지 않으며, "HEAD
바인딩" 논의에서 §2.1a의 `|git=`를 축 ②/③과 동일시하는 것을 어휘 오류로 본다.

---

## 2. 결정 기록 — "docs-only main 커밋 → 세대 전진 → 세대당 1회 재측정" 수용

> **[2026-11-01 각주 — 본 절 본문은 2026-10-09 시점의 결정 기록이다]** 아래 결정과
> "축소 금지" 재확인은 pre-split(B^{tree} 세대) 시대 기록으로, 이후 계약 개정으로
> **대체·정밀화**됐다: v1.0.3(2026-10-10)이 성분 ⑤를 semantic set digest
> S = TreeUniverse(R) − N으로 정밀화해 N-class 비영향 문서의 과잉 무효화를 제거했고
> (normative 면 — docs/spec·docs/agents·config/policy·config/templates — 변경은 여전히
> 키를 전진), B/M 분할(f96f37f5d, 2026-10-20)과 계약 v1.0.6이 피험 트리 R을 **후보
> M^{tree}**로 확정했다. 현행 세계에서 docs-only main 커밋은 normative 면을 바꿀 때만
> 키를 전진시킨다. 정본: `test_judgment_cas_contract.md` v1.0.6 §4·§4.1 +
> `docs/evidence/judgment_key_v5_adjudication_2026-10-31.md`. 본문은 역사로 그대로
> 보존한다.

**결정 (root-cause 문서 §4.4 후속 수용 — 2026-10-09 시점)**: docs-only main 커밋도
B^{tree}를 전진시키며,
그 결과 세대당 1회의 fail-closed 재측정이 발생한다. 이 **과잉 무효화(over-invalidation)는
수용한다** — 검증자 바이너리 의미가 불변인 docs 커밋도 재측정 비용을 지불한다. 이는
root-cause 문서 §4.4가 "후속 후보(본 사건 원인 아님)"로 유보했던 항목에 대한 판정이며,
세 가지 이유로 축소보다 수용이 옳다:

1. **오류 비대칭** — 누락(부정 HIT)의 비용이 과잉(재실행 비용)보다 크다. Gradle의
   선언이 그 방향을 고정한다: "If a task property affects the output, **be sure to
   register it as an input**, otherwise the task will be considered up to date when
   it's not" (§4 Gradle 항). docs 커밋이 검증자 트리(B)의 일부라는 사실은 측정된
   실측(root-cause §2: `99e3e640…` 전진)이며, "의미 불변" 주장은 B 트리 전체의
   의존 그래프를 재검증해야만 안전하게 만들 수 있는 주장이다 — 그 비용이 재측정 1회보다
   크다.
2. **fail-closed 기본값과의 일관성** — 계약 §6은 조건 불충족 시 원 실행으로 회귀한다.
   세대당 1회 재측정은 그 기본값의 자연스러운 발현이지 새 경로가 아니다.
3. **실측 정합** — #611 HIT / #613 MG-run MISS가 정확히 이 모델로 관측됐다
   (root-cause §2). 모델을 축소하면 관측을 부정하는 쪽으로 개정이 필요하다
   (§0.6 Static-Analysis-First: 관측 우선).

**축소 조건 (전부 충족 시에만 검토 — 현 범위 밖, 본 문서는 수행하지 않음)**:

1. 계약 §4(성분 5 정의)·§5(e)(도구 정체성)·`obligation_semantics.md` §2.1a의 명시적 개정.
2. 소비처 재감사 — 실측 2026-10-09: `grep -rln
   'computeBoundObligationId\|ObligationSubjectBinding\|subjectGitRef\|AXIOM_JUDGMENT_CAS\|judgment_cas'
   src/ tools/ tests/ .github/workflows/` → **18파일**(workflows 2, src 11 — 생성
   메타데이터 1 포함, tests 5; 목록은 §2 각주) — 세대 축의 grain을 바꾸면 이 표면 전체의
   재감사가 필요하다.
3. payload 스키마 버저닝 — `axiom.judgment.cas.v1` → v2 마이그레이션(§3 판정 2 참조).
4. 기존 원장 레코드의 grandfathering 규칙(구 v1 레코드의 세대 재해석 여부).

§2.2(작업 범위 폐쇄)에 따라 위 4항 중 어느 것도 본 변경에서 수행되지 않으며, 본 결정은
"축소 금지"를 재확인하는 방향으로만 기록된다(§1.2).

**§2 각주 — 18파일 실측 목록** (2026-10-09, 위 grep 명령의 그대로의 출력):
`.github/workflows/admission-check.yml`, `.github/workflows/certificate-mint.yml`,
`src/cli/cert_cli.nim`, `src/gate/slice_catalog.nim`, `src/generated/type_registry_metadata.json`,
`src/verification/attestation_witness.nim`, `src/verification/counterexample_replay.nim`,
`src/verification/judgment_cas.nim`, `src/verification/obligation/canonical_verification.nim`,
`src/verification/obligation/golden_fixture_ir.nim`,
`src/verification/obligation/kernel_acceptance_authority.nim`,
`src/verification/obligation/lean_kernel_boundary.nim`,
`src/verification/obligation/obligation_types.nim`,
`tests/unit/obligation_subject_binding_test.nim`, `tests/unit/test_bug_verdict_projection.nim`,
`tests/unit/test_counterexample_replay.nim`, `tests/unit/test_judgment_cas.nim`,
`tests/unit/test_s1a_lean_golden.nim`.

---

## 3. d2_golden 판정 기록

**판정 1 — 14테스트는 중복이 아니라 독립 stage 계약의 증거다.**
`tests/unit/test_d2_golden.nim`은 5개 suite에 걸쳐 정확히 **14개 테스트**를 가지며
(실측: `grep -c '^\s*test "' tests/unit/test_d2_golden.nim` = 14), 각 suite는
canonical 체인의 **서로 다른 단계의 계약**을 검증한다:

| Suite | Stage 계약 |
|---|---|
| Stage 1 | real Lean kernel check — `KernelCheckBoundary` receipt (real kernel ACCEPT, receipt 필드 64-hex·관측 시각) |
| Stage 2 | receipt → KAA (Authority B) — opaque receipt의 정당한 결속 |
| Stage 3 | KAA → vdVerified (Authority C) — 정책 판정 |
| Stage 4 | C1 identity closure — 5개 C1 identity |
| Golden Summary | 결정론 (same input → same output) |

테스트 파일 자체의 서술: "walks the REAL canonical chain on a REAL source and **proves
each stage executed**: real source → … → actual Lean kernel ACCEPT → opaque
LeanKernelCheckReceipt → bind(receipt) → KAA → evaluate(KAA, Policy) → vdVerified →
CanonicalVerificationResult → identity closure". receipt→KAA→verdict→identity closure은
한 단계의 반복이 아니라 단계별 불변식이므로, "같은 것을 14번 검증"이라는 축소는
성립하지 않는다. (참고: `CanonicalProbeCount = 14`, `src/verification/judgment_cas.nim:145`
— payload의 probeCount는 s1a 측정의 정준 값이며 d2_golden의 14테스트와 무관한 우연한
일치다. 두 14를 혼동하지 않는다.)

**판정 2 — GO-critical 3종 확장의 실제 전제는 payload schema v2다.**
GO-critical 테스트 집합을 확장하면(예: s1a 외 추가 producer E2E) 측정 카운트가 변한다.
그런데 현재 검증은 s1a 형상을 fail-closed로 고정한다 —
`validateJudgmentPayloadNode` (`src/verification/judgment_cas.nim:474`):

- `schemaVersion == "axiom.judgment.cas.v1"` (:496 — 상수 :103)
- `kernelAcceptCount == 17 ∧ probeCount == 14 (the canonical set)` (:502-504 — 상수 :140·:145)
- `acceptsByTheorem == the canonical distribution (sum == 17)` (:521 — 정준 정리 집합 외 비정준 키 기각 포함)

즉 테스트 목록 편집만으로 확장은 불가능하고, **payload schema v2** (스키마 상수·정준
카운트·버저닝 마이그레이션·원장 신구 스키마 공존 규칙)가 선행 계약이다. 이는 §2 축소
조건 3과 같은 버저닝 재원이다.

---

## 4. 업계 근거 (Industry priors — 원문 인용)

1. **in-toto attestation v1** — subject 매칭은 digest로만:
   > "IMPORTANT: **Subject artifacts are matched purely by digest**, regardless of
   > content type." — `in-toto/attestation` `spec/v1/statement.md` (subject 필드 서술)

   축 ①/③의 근거: 매칭 키는 컨텐츠 digest다. run 소속 커밋·브랜치명 같은 이름 축은
   매칭에 참여하지 않는다 (§1.3 실측과 동일 결론).

2. **SLSA v1.1 Provenance** — 인과 입력이 정체성의 본체:
   > `buildDefinition { buildType, externalParameters, internalParameters,
   > resolvedDependencies }`; "The **resolvedDependencies** captures these dependencies,
   > if known. For example, a build that takes a git repository URI as a parameter
   > might record the specific git commit that the URI resolved to as a dependency."
   > — https://slsa.dev/spec/v1.1/provenance

   축 ①의 근거: 빌드 정의는 파라미터와 resolved dependencies(인과 입력)로 구성되고,
   출력 subject는 그 결과물이다. 우리의 9성분 중 인과 축(성분 1–4·6–9)이 이 구조와
   대응한다.

3. **Gradle** — 누락 입력 = 부정 캐시 HIT, 포함 방향은 보수적으로:
   > "Since a task describes all of its inputs and outputs, Gradle can compute a
   > **build cache key that uniquely defines the task's outputs based on its inputs**."
   > 및 "**Missing task inputs can cause incorrect cache hits**, where different results
   > are treated as identical because the same cache key is used by both executions."
   > — https://docs.gradle.org/current/userguide/build_cache.html (§ Caching task
   > inputs / cache key)
   >
   > "If a task property affects the output, **be sure to register it as an input**,
   > otherwise the task will be considered up to date when it's not."
   > — https://docs.gradle.org/current/userguide/incremental_build.html (§ Task inputs
   > and outputs)

   축 ② 유지와 §2 결정(2026-10-09 기록 — §2 상단 각주 참조)의 근거: 입력 누락이 만드는
   것은 절약이 아니라 "같은 키, 다른 결과"의 부정 HIT다. 인과 여부가 불확실한 변경(예:
   docs-only 커밋이 검증자 트리의 일부인 경우 — pre-split 시대 예시)은 **포함하는 방향**
   (재실행 비용)이 안전하다 — 이것이 "불확실 시 포함" 원칙의 오류 비대칭 근거이며, Gradle
   문서의 두 문장이 그 비대칭을 정확히 기술한다. 우리의 세대 축(성분 ⑤ — 현행 v3:
   semantic set digest S = TreeUniverse(R) − N, R = 후보 M^{tree})은 이 원칙의 채택이다.

---

## 5. 범위 밖 재확인 (Non-Goals)

- **코드·워크플로·스키마 변경 0건** — 본 문서는 규범 기록만 담는다.
- **§2.1a 개정 없음** (§1.4), **freeze 개정 없음** (E1–E5·P1–P6 무변경),
  계약 `test_judgment_cas_contract.md`의 §4 성분 집합·§5 5조건의 **약화 없음** — 본
  문서와 동반하는 계약 변경은 §4 교차참조 1건뿐이다.
- 세대 축 축소(§2 조건 4항) — 수행하지 않는다.
- 효과 수치 선주장 금지 — 재측정 비용·절감의 숫자 주장은 구현·실측 후에만.

## 6. 변경 이력

| 버전 | 날짜 | 변경 |
|---|---|---|
| v1.0.0 | 2026-10-09 | 초안 — HEAD 3분법(§1), 세대 축 유지 결정 + 축소 조건 범위 밖 기록(§2), d2_golden 14테스트 독립 stage 계약 판정 + 3종 확장 전제 = payload schema v2 판정(§3), 업계 근거 원문 인용(§4). 근거: `judgment_cas_reused_hit_root_cause_2026-10-09.md` §2·§4, `test_judgment_cas_contract.md` v1.0.1 |
| v1.0.1 | 2026-11-01 | **pre-split B^{tree} 서술 정정 — 성분 ⑤의 피험 트리 R = 후보 M^{tree} (축 ② 유지·약화 금지, §2 결정 기록·§3 판정 무변경)**: v1.0.0-era 문언(헤더·표 ②행·§1.2 제목·본문·§4(3) 말미의 "성분 ⑤ = B^{tree}" / "검증자 세대 = B^{tree}" / "우리의 B^{tree} 세대 축")을 현재 구현 시맨틱으로 정정 — 성분 ⑤는 **semantic set digest S = TreeUniverse(R) − N**이고 R은 **후보 M^{tree}**(베이스 팁 ∪ PR 변경의 merge-queue 후보 머지 커밋 트리)다. 커밋 OID는 9성분 어디에도 없으며, 트리 OID 차이와 N-class 델타 자체는 키를 움직이지 않고 normative 면(docs/spec·docs/agents·config/policy·config/templates) 변경은 키를 전진한다. §1.3 #611 실측·§2 결정 기록은 2026-10-09 시대 기록으로 보존하고 supersession 각주를 부기한다. 근거: `src/verification/judgment_cas.nim:422-468`(9성분 클로저 — digest 전용, OID 멤버 부재) + `src/verification/semantic_set_derivation.nim:14-19`(R = TESTED tree = `AXIOM_JUDGMENT_CAS_TESTED_TREE_OID`) + `.github/workflows/admission-check.yml:3132`·`:3216`(M^{tree} 유도·export) + B/M 분할 f96f37f5d(2026-10-20) + 2026-10-31 운영 실측 `docs/evidence/judgment_key_v5_adjudication_2026-10-31.md`. 계약 `test_judgment_cas_contract.md` v1.0.6 동기화 |
