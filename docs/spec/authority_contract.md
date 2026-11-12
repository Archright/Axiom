# Authority Contract (authority_contract)

> **Status**: Normative contract (2026-10-07). PR-A — 이후 정리 시리즈(PR-B~E)가 인용하는 단일 SSOT.
> **원칙**: authority-per-fact — authority-bearing 사실마다 정확히 하나의 authority가 있다.
> Adapter·reporter·변환기는 authority가 아니다 (Authority ≠ Adapter).
> **Related**: `AGENTS.md` §2.3 · `docs/spec/merge_admission_controller.md` §1 (Enforcement authority) ·
> `docs/spec/merge_authority_integrity.md` (M1–M7) · `docs/spec/certification_continuity_contract.md` (INV-2) ·
> `docs/spec/execution_accounting_contract.md` §9 (INV-X1) · `config/trusted_writer_set.json` (ADR-0022 §4)

기존에 분산 선언된 authority(evidence_truth_boundary_gate의 T1–T4, trusted_writer_set,
merge_admission_controller §1)를 한 문서로 고정한다. 본 문서는 새 권위를 만들지 않고
기존 정본을 인용해 4개 authority의 경계를 선언한다. 측정·역사 데이터는 담지 않는다.

---

## 1. Semantic authority — Nim 컴파일러/툴체인 (pinned)

**Authority**: pinned Nim 툴체인 (Nim 2.2.10 — `Makefile:184-188` 3-pin core의 nim 핀
`Makefile:185`; `nimble.lock:5`; `axiom.nimble:5`).

**결정하는 것** — subject 소스의 의미. 외부 Nim subject의 "이 소스가 무엇을 계산하는가"
(평가 결과, overflow 도달 가능성 등 언어 의미)의 유일한 원천이다.

**결정하지 않는 것** — 판정(verdict)·저장·merge. 컴파일러는 의미를 결정할 뿐 verdict를
선언하거나 산출물을 창작·저장하지 않는다. formal denotation도 새 진실을 발명하지 않는다:
`proofs/IR/Denotation.lean`은 certified subset 위의 hand-written denotation으로 Nim
renderer와 독립이고(`proofs/IR/Denotation.lean:4-5`), 그 스코프 주장은
"renderer ≡ denotation; Nim 관계는 Nim 자신이 total인 지점에서 성립"으로 제한된다
(`proofs/IR/Denotation.lean:27-28`). Nim 컴파일러가 의미를 결정하고, denotation은 그
의미를 보존·표현한다.

**fail-closed** —

- 툴체인 drift: `nim`/`z3`/`lean` 버전이 pin과 다르면 pin 소비 게이트가 FAIL 한다 —
  `check-determinism`(`Makefile:190`, NEVER reset/clean)과
  `local-verify-contract-exact`의 `check-toolchain-pin` 소비(`Makefile:378-382`,
  규칙 정의 `Makefile:387`).
- denotation 공백: certified subset 밖 연산에는 Certified proof가 없고 명시적 실패다.
  renderer가 denotation에 없는 subject op을 만나면 빈 결과가 아니라 fail-closed —
  음성 테스트 `tests/negative/rem_body.nim:4-5`(`renderLeanForFuncDef`가 `""` 반환).
- denotation 치환: denotation artifact hash가 실제 파일과 묶여 있다 —
  `tests/unit/obligation_subject_binding_test.nim:309`
  (`measured.denotationLean == sha256Hex(readFile("proofs/IR/Denotation.lean"))`).

**제2 authority 부재 확인 방법** —

- Denotation은 `NO native_decide, NO sorry, NO trustCompiler`로 컴파일러-외부 신뢰를
  금지한다(`proofs/IR/Denotation.lean:22`). translator 등가성은 operator·type
  preservation으로 증명된다(`proofs/IR/TranslatorEquivalence.lean:2-5`).
- render ≡ denotation 등가는 실제 Lean 실행 스위트로 감시된다
  (`tests/verification/test_semantic_closure.nim:188`). 즉 denotation이 Nim 의미를
  이탈하면 음성·등가 테스트가 적발한다 — denotation이 제2의 semantic authority가 될
  수 없다.

## 2. Verdict authority — VerificationDecisionAuthority

**Authority**: `src/verification/obligation/verification_decision_authority.nim` —
"The ONLY authority that may produce a verified verdict from a
KernelAcceptanceAttestation"(`verification_decision_authority.nim:7-9`; 불변식
`:15`). Run-level: `evaluateRunOutcome`이 `vrPass`와 basis의 유일 생산자다
(`src/verification/accounting/run_accounting.nim:94`, `:878`).

**결정하는 것** — 검증 판정. artifact-level `evaluate(KAA, Policy) → vdVerified`와
run-level `evaluateRunOutcome → vrPass/vrInconclusive/vrFail/vrBlocked + basis`.

**결정하지 않는 것** — raw evidence의 생성(T1 receipt는
`src/verification/obligation/lean_kernel_boundary.nim`, T2 KAA bind는
`src/verification/obligation/kernel_acceptance_authority.nim` 단일 sink —
`evidence_truth_boundary_gate.nim:12-13`), 저장(§3), merge(§4). Lean kernel·Z3 등
solver는 raw evidence만 만들며 verdict를 선언할 권한이 없다(§5.1).

**fail-closed** —

- 사실 없는 판정 금지: Policy 입력은 KAA를 전제로 하며, KAA 입력 타입 자체가 genuine
  kernel evidence의 존재를 보증한다(`verification_decision_authority.nim:52-57`).
  별도 boolean으로 "KAA 있지만 불요"인 제2 evidence 체제를 만들지 않는다.
- verdict 생성자는 비공개다: `makeVerifiedDecision`은 모듈 외부 참조 금지
  (`verification_decision_authority.nim:69-75`; 게이트 강제
  `evidence_truth_boundary_gate.nim:42-43`).
- 어휘 전체가 보호된다: PASS만이 아니라 `vr*`/`rb*` 전 어휘의 value-producing 발생이
  authority 모듈 밖이면 위반([T4-a] `evidence_truth_boundary_gate.nim:31-33`), guarded
  outcome 키를 vocabulary literal로 직렬화하는 것도 위반([T4-b]
  `evidence_truth_boundary_gate.nim:33-37`).

**제2 authority 부재 확인 방법** — 소유 지도가 상수로 고정되어 있다:
`evidence_truth_boundary_gate.nim:90`(`runVerdictOwner`), `:91`
(`verdictVocabularySource` = run_accounting.nim). 정적 게이트가 이 매핑을 강제하므로
제2 verdict 생산 경로는 게이트 시점에 적발된다.

## 3. Evidence authority — Evidence CAS + certificate writer

**Authority**: identity-bound 산출물의 창작·저장 경로 —
`src/verification/evidence_cas.nim`(semantic identity CAS; EvidenceKey
`evidence_cas.nim:16-17`) + `src/verification/cert_writer.nim`(certificate 작성;
persisted certificate의 kernel=true에 대한 유일 forge-proof 경로는
canonicalLeanKernelCheck → bindReceipt — `cert_writer.nim:279-281`). 원장
publication의 유일 privileged authority는
`.github/workflows/certificate-mint.yml`이다(`config/trusted_writer_set.json:11-14`).

**결정하는 것** — evidence·certificate의 identity-bound 생성·저장·재사용. EvidenceKey는
모든 semantic 입력을 포함하고 provenance(runId, 타임스탬프, 빌드 스탬프 등)는 배제한다
(`evidence_cas.nim:16-31`).

**결정하지 않는 것** — verdict(§2), merge 수용(§4), 정책 내용(`config/`). evidence는
사실의 저장이지 판정이 아니다.

**fail-closed** — digest 수집은 명시적 I/O 경계에서 FAIL-CLOSED다: missing/unreadable
입력은 오류이다, empty/zero digest가 아니다(`evidence_cas.nim:41-42`).

**제2 authority 부재 확인 방법** —

- 쓰기 경로 등식: `contents: write`를 가질 수 있는 workflow는
  `config/trusted_writer_set.json` 집합과 정확히 일치해야 하고(MUST), 이는
  `tools/ci/verify_trusted_writer_set.sh`가 검증한다(`trusted_writer_set.json:3-5`).
- 단일 sink: T1 receipt → T2 KAA → T3 verified의 각 전이는 단일 소유 모듈로 고정되며
  `evidence_truth_boundary_gate.nim:12-16`이 강제한다. guard 심볼의 guard 밖 발생은
  문맥 무관 위반이다 — "unresolvable → pass" 경로가 없고, parse 불가 소스 자체가
  위반이다(`evidence_truth_boundary_gate.nim:46-52`).

## 4. Merge authority — GitHub (required check + merge queue)

**Authority**: GitHub — repository ruleset, `admission-check` required status check,
GitHub Merge Queue. 착지 객체는 GitHub native MERGE commit이다
(`docs/spec/certification_continuity_contract.md:122`). 정본:
`docs/spec/merge_admission_controller.md` §1 "Enforcement authority" — "GitHub is the
sole merge ENFORCEMENT authority"(`merge_admission_controller.md:33`)과
`AGENTS.md` §2.3.

**결정하는 것** — merge admission의 최종 판정과 집행, 착지 커밋 생성.

**결정하지 않는 것** — admission predicate의 내용은 Axiom의 단일 술어 생산이고
GitHub이 집행한다("Axiom decides, GitHub enforces",
`merge_admission_controller.md:34`). GitHub은 코드 의미(§1), 검증 판정(§2), 산출물
창작(§3)을 결정하지 않는다. **Axiom 측에 별도 merge decider/guard를 만들지 않는다** —
제2 enforcement 시도였던 in-CLI auto-merge arm lane은 제거되었다
(`merge_admission_controller.md:35`), 커스텀 queue/orchestrator는 금지된다(ADR-0027;
`merge_admission_controller.md:3`).

**fail-closed** —

- required checks 0건 = UNKNOWN / NOT_READY다. SUCCESS로 해석하지 않는다
  (`AGENTS.md` §2.3).
- `mergeStateStatus`는 reason 없는 verdict이며 사유의 유일 권위는 Rule Suites다.
  원인을 모르면 UNKNOWN — 추측 금지(`docs/spec/merge_authority_integrity.md` M5·M6).
- 두 개 이상의 쓰기 경로가 live 구성을 바꿀 수 있으면 그 구성에는 권위 주체가 없다
  (`docs/spec/merge_authority_integrity.md` M1).

**제2 authority 부재 확인 방법** — in-CLI 제2 adjudication 경로의 부재는 제거 사실로
확인된다(`merge_admission_controller.md:35`). 동일 역할 경로의 신규 제안은 본 절과
merge_authority_integrity.md M1에 대비해 반려한다.

## 5. 정리 방향 계약 (Cleanup Directions)

이후 PR-B~E는 다음 방향을 계약으로 수행한다.

1. **solver = raw evidence** — Z3 등 solver는 raw output을 반환하는 증거 생산자다
   (`src/verification/solver/provers.nim:95`, "return raw output string"). solver
   출력의 verdict 승격은 오직 §2 authority를 통해서만 가능하며, 금지 흐름 edge
   (Z3Evidence/Candidate/HistoricalRecord/PersistedRecord → KAA/vdVerified/vvSafe)는
   게이트가 강제한다(`evidence_truth_boundary_gate.nim:39-43`).
2. **lowering/projection = 변환기** — projection은 proof 결과의 일부이지 판정이
   아니다. `vvSafe`는 verification_decision_authority 결정의 projection으로서
   `src/verification/universal_pipeline.nim` 내 ≤1 site에서만 생산 가능하고
   (`evidence_truth_boundary_gate.nim:15-16`), value-producing 위치 제한 [I-2]
   (`evidence_truth_boundary_gate.nim:58-63`)이 이를 강제한다. 변환기가 verdict를
   만들면 그것은 제2 authority다.
3. **측정 권위 없는 값 생성 금지, fail-closed** — 판정·저장 경로의 모든 수치·digest는
   측정 주체(§2·§3)를 거쳐야 하고, 입력 부재는 오류다(`evidence_cas.nim:41-42`).
   권위 없는 값 생성·기본값 평활화는 극장이다(`AGENTS.md` §0.9).
4. **중복 acceptance surface는 retire 대상** — 동일 역할의 제2 수용 표면을 발견하면
   신설·유지하지 않고 retire한다. 선례: in-CLI auto-merge lane 제거
   (`merge_admission_controller.md:35`). Retire는 실행 경계 변경이므로 `AGENTS.md`
   §2.5(coherent generation 전환)와 §2.6(authority·state transition·failure
   semantics·proof 선행)을 따른다.

## 6. Scope

- 본 문서는 계약 선언이다 — 새 authority·새 강제 장치를 도입하지 않는다. 강제는
  인용된 기존 게이트·검증기가 담당한다.
- 본 문서는 문서 전용이다. authority 경계 변경을 수반하는 개정은 인용된 코드·게이트와의
  일치를 전제로 하며, 측정·역사 데이터를 본 문서에 배치하지 않는다(§5 SSOT 위치 규칙).
