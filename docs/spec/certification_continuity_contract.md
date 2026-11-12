# Certification Continuity Contract

> **Status**: RATIFIED — Model B revision (Verdict B, 2026-09-10). GitHub native
> MERGE commit is the canonical landing mechanism; rebase-only landing and
> exact-object publication are **superseded** (superseded sections are kept in
> strikethrough form in git history only — this revision replaces them).
> **2026-09-12 revision (ADR-0021)** — verification execution authority moved to
> repository state transitions (`workflow_run` chain); `workflow_dispatch` entry
> for candidate verification removed (trusted/untrusted executor boundary
> retained — ADR-0021 strengthens it). Trigger row in §4.2 reflects the
> implementation direction; INV-13 (one certificate per subject) added in §5.
> **2026-09-27 revision (실행 authority 단일화 계획 Phase 0, rev.7)** — INV-13의 D6
> 멱등 판정 해석을 개정한다: ledger record 재계산 정당성(subjectId·certTree 재유도 —
> 키 멤버십 1차 검사는 유지) · witness digest 조건 폐기(run-scoped — 교차 런 정체성
> 금지) · CAS 3분기 reconciliation · exactly-once(첫 publish append=1, 동일 subject
> 재실행 append=0). 발행(ledger append) writer = publish 단일(단일 writer) —
> verdict/post-verdict append는 폐기. INV-13 "subject당 certificate 1개" 불변은
> 그대로 유지된다(상세: §5 INV-13 D6 해석 개정 노트).
> **2026-10-12 revision (closure-candidate-delta 선결 ①)** — §7 `:291` "git 버전
> 고정"의 구체 핀 값을 §11로 선언한다: 기능 하한 `git >= 2.40.0`, 재현 기준
> `2.43.0`, 상한 미고정(runner 이미지 git 부유 — 발산은 1차 방어 등식
> `derived(M) == tree(G)`이 흡수). merge-tree의 merge.* 구성·.gitattributes
> merge driver 민감도는 git 2.43.0 기계 관측으로 확정(§11.2).
> 현행 merge admission 계약은 [merge_admission_controller.md](merge_admission_controller.md).
> **§-1 경계**: 본 아키텍처가 `.github/workflows/ci.yml`(CI=0 cutover, 2026-09-20로 삭제)를 변경하는 것은 Phase 5c(연속성
> cutover)뿐이며 architect 승인(AGENTS.md §-1)을 전제로 한다(Phase 5 본체 — admission +
> exact publication — 는 ci.yml 변경 없이 랜딩됨). 나머지 단계는 §-1 밖의 일반 절차를 따른다.
> (ci.yml 및 CI=0 전후 clean-slate/cutover(2026-09-16~21, 커밋 `fa069d610`/`4619699c3`/`ce92fc2d1`)로 삭제된 워크플로 대부분과 달리, `.github/workflows/`에는 `repository_surface.yml`(PR 관측
> 전용 — required check 아님)과 `runner-pool-acceptance.yml`(push@main, 9-job) 2개가 잔존/복구되어 있다(2026-09-22 기준) — §7 Phase
> 표의 workflow 구현 기록은 point-in-time 산출 기록이며, 현행 경로는 로컬 게이트 +
> native MERGE + 인증서 원장이다.)
> **Doc-first(§0.5)**: 본 문서가 참조한 외부 공식 문서 전체는 §8에 기록되어 있다.

## 0. 목적

PR CI가 검증한 merge 결과를 main이 다시 전체 검증(L2)하는 중복을, 이벤트 중심
트리거 최적화가 아니라 **검증 대상의 identity와 인증서 승계**로 제거한다.

> **Axiom never certifies an event. Axiom certifies an immutable subject.**

merge는 "이미 certified subject의 publication"으로 재정의되며, main push 이후에는
전체 재검증 대신 **certificate continuity check**가 수행된다(Phase 5, 조건부 —
nightly full L2가 backstop으로 잔존, §7).

## 1. 용어

| 용어 | 정의 |
|---|---|
| **formally bounded certification** | project-defined 용어(공식 용례 부재 — §8.4): "선언되고 버전 고정된 언어 subset 위에서, 경계 구성요소가 declared trust boundary 또는 qualified component로 지위가 선언된 인증". 선행 사례: SPARK(subset 선언), CompCert Clight(subset + 미검증 parser 동시 자인), Lean FAQ(번역 도구 가정 = TCB), DO-330(도구 자격). |
| **Certified subset of Nim** | pinned Nim frontend(Nim 2.2.10)가 수용하고 canonical AST identity 계약([canonical_ast_identity.md](canonical_ast_identity.md)) 아래 직렬화 가능하며 IR 하강이 loss-free(`translationLossFree=true`)인 프로그램. subset 밖은 인증 커버리지 밖(SPARK "not in SPARK" 모델). |
| **Certified subject (Model B)** | 인증 대상은 **착지 전 입력 상태** `(baseSha, headSha, headTreeDigest, policyDigest, scopeDigest, evidenceDigest)` — 사전 생성된 synthetic commit OID가 아니다. GitHub native MERGE commit이 착지 객체를 생성하며, continuity가 그 결과의 parents/tree로 인증 입력의 상속을 검증한다. |
| **Subject Certificate** | M에 대한 증거 E의 서명된 canonical JSON(RFC 8785 + Ed25519 — 기존 v3 certificate 확장): subject identity + kernel verdict + provenance + env/policy digest. |
| **Trusted Attestation Boundary** | 검증 실행(untrusted)과 발급·원장·publication(trusted)의 분리 경계 — 트리거·실행 파일 버전·권한·시크릿 4축(§4.2). |
| **Kernel re-execution** | trusted 계층이 pinned Lean kernel / Z3로 evidence를 재실행해 verdict를 독립 재확인하는 행위 — certificate의 유일한 unforgeable 근거 계열(§5 INV-6). |
| **Side-ref ledger** | main tree 밖 `refs/heads/axiom/certificates`의 FF-only append-only 인증서 원장(§4.3). Git object는 content-addressed로 불변(gitglossary) — tamper-evident. |

## 2. 인증 스코프 선언 (HARD)

Certificate가 증명하는 문장(스냅샷 계약 — INV-9가 과잉 주장을 차단한다):

> 이 certificate는 pinned frontend(Nim 2.2.10)가 산출한 **선언된 subset의 canonical
> AST**에 대해, kernel-executed 독립 reference extractor와 Nim extractor의 합의
> IR의 denotation 위에서, 정책이 요구한 proposition을 **pinned Lean kernel이
> 증명했음을 증명한다**.

| 증명하는 것 | 증명하지 않는 것 |
|---|---|
| 선언된 subset의 canonical AST에 대한 이중 extractor 합의 IR | Nim frontend 자체의 정확성(qualified — verified 아님) |
| 그 IR denotation 위의 정책 요구 proposition(pinned kernel) | author의 spec(postcondition)이 의도를 정확히 표현함(spec은 정책/author의 정의) |
| 검증 환경(RunnerPoolSpecDigest)·정책 digest의 일치 | Nim 언어 전체의 의미론(subset 밖은 커버리지 밖) |

## 3. TCB 5층 선언

| 층 | 지위 | 관리 기제 | 선례 |
|---|---|---|---|
| Nim lexer/parser/macro runtime | **Qualified**(verified 아님) | Nim 2.2.10 6계층 버전 고정(설치·CI·RunnerPoolSpecDigest·buildEnvHash·AST 해시 계약·toolchain fingerprint) + AST identity 계약 | CompCert CACM §5 항목 2(미검증 parser); DO-330 도구 자격 |
| Subset 경계 | **Declared** | lossy fail-closed(`translationLossFree=false` → 인증 거부) + `verification_scope.lock` 승격(§6) | SPARK SPARK_Mode / "not in SPARK" |
| AST→IR 이중 extractor 합의 | **TCB 감축 메커니즘**(폐쇄 아님) | per-run differential fail-closed(INV-4); 구조적 독립성 불변식 | Lean FAQ TCB 문구; Pnueli translation validation |
| IR→denotation→kernel 증명 | **Kernel-verified** | Lean kernel이 증명 term을 검사; `#print axioms` allowlist(INV-6) | Lean Reference Tactic-Proofs |
| Lean toolchain 연쇄(kernel+컴파일러) | Declared TCB | lean-toolchain 4.33.0 고정 | CompCert §5 항목 3 |

> **Rust subject boundary note**: The 5 layers above cover the Nim-subject certification path only. The trust-boundary register (`src/core/trusted/trust_boundary.nim`, `AxiomTrustBoundary`) additionally declares 3 Rust subject boundaries (ADR-0029 D3) — `rustc to LLBC lowering`, `LLBC to shared canonical translation`, `dual IR derivation from shared canonical` — all `tcRecorded` with `exists: false` (declared, not yet implemented; no trust over-claim). They are not an additional layer here and are not covered by the table.

## 4. 아키텍처 (확정 요약)

### 4.1 파이프라인 (Model B — ratified Verdict B, 2026-09-10)

```
[Capture — I/O boundary]
  baseSha = origin/main (fetch + rev-parse) · headSha = refs/pull/N/head
  headTreeDigest = sha256Hex(git rev-parse <headSha>^{tree})

[Untrusted verify — 실행하되 신뢰 재료 아님]
  checkout headSha (데이터) → main-built 도구로 gate·재유도
  → evidence artifacts (subject digest + toolchain fingerprint 바인딩)

[Trusted attest — Verify(E, subject)]
  kernel re-execution(leanSource typecheck + #print axioms allowlist
  + Z3 재실행) + 바인딩 재유도 + 정책 커버리지
  → Certificate mint(Ed25519, subject v2 wire) → side-ref 원장 FF-only append

[Admission — Axiom]
  MergeAdmissible (requiredValidations check-runs, trustSurface,
  base/head freshness, policy/scope digest equality)

[Native MERGE — GitHub execution]
  REST PUT /pulls/{N}/merge merge_method="merge", expected head sha
  → GitHub constructs the merge commit (parent1 = base, parent2 = head)

[Continuity — Model B predicate]
  2-parent merge commit ∧ parent1==cert.baseSha ∧ parent2==cert.headSha
  ∧ sha256(parent2^{tree}) == cert.headTreeDigest
  ∧ policy/scope digest current ∧ Ed25519 valid ∧ ledger present
  → journal (forensic only)
```

### 4.2 Trusted Attestation Boundary

| 축 | Untrusted tier | Trusted tier |
|---|---|---|
| 트리거 | workflow_run (downstream of ci.yml PR-path success; ADR-0021) | workflow_run (downstream of verify-candidate success; ADR-0021) |
| 실행 파일 버전 | main (trusted executor set 멤버십) | 기본 브랜치 |
| checkout | headSha(데이터) | main 전용 — head checkout·실행 없음 |
| permissions | contents: read | contents: write, actions: read (attest.yml:57-59 실측 — F8 evidence artifact 다운로드, ADR-0021) |
| 시크릿 | 미참조 — 정적 게이트로 강제 | 시크릿 미참조 — Ed25519 서명키는 **소스 하드코딩 공개 상수**(secret 아님): `AttestationDomainSeed = "axiom-attestation-v1-sha256"`(`src/infrastructure/certificate_attestation.nim:185`, "PUBLIC by design") → `createKeypair(sha256(seed))`; 검증은 고정 공개키 literal(`:192-193`)만 사용. Python 독립 재유도로 실제 유도 공개키 == 상수 일치 증명 완료(2026-09-18) |

### 4.3 Publication (Model B)

- GitHub native MERGE가 착지 커밋을 생성한다 — Axiom은 `commit-tree`/rebase
  replay/FF-CAS publication을 소유하지 않는다. 착지 방식은 repo 설정으로 고정:
  merge commit 활성, rebase/squash 비활성.
- 착지 후 merge commit의 parent1/parent2가 인증된 (baseSha, headSha)와
  정확히 일치하는지 continuity가 검증한다 — "certified inputs ⇒ certified main
  state"의 승계 판정.
- head race는 REST merge의 expected-head `sha` 파라미터(409)로, base race는
  admission-time base 재확인으로, 착지 후 위반은 continuity fail-visible로 처리한다.
  커스텀 queue/orchestrator는 재도입하지 않는다.

### 4.4 Continuity

**결정 구조 (determination structure, Model B)** — PR(provenance) · certified
input subject (certification subject) · main(native MERGE의 publication)을 구분한다:

- **PR** = provenance(어떤 리뷰 절차를 거쳤는가) — certification의 대상이 아니다.
- **Subject** = `(baseSha, headSha, headTreeDigest, policyDigest, scopeDigest,
  evidenceDigest)` — certificate가 증명하는 인증 입력 상태.
- **main** = certified subject의 publication — GitHub가 생성한 merge commit.
- **PR MERGED** = GitHub merge bookkeeping — continuity predicate의 입력이
  아니다. Model B에서는 head가 merge commit의 parent2로 직접 참조되므로
  GitHub "Indirect merges" 표기가 자연 발생하며, 이는 순수 bookkeeping이다.

**C1 (Model B)** — continuity가 검증하는 결정 문장:

> C1 := (main head is a 2-parent merge commit)
>     ∧ (parent1 == cert.baseSha)
>     ∧ (parent2 == cert.headSha)
>     ∧ (sha256Hex(parent2^{tree}) == cert.headTreeDigest)

- **parent1 == cert.baseSha** — 착지 merge commit이 인증 시점 base 위에서
  생성되었음(정확 일치 — descendant-base semantics 없음; base가 이동하면
  admission 단계에서 재인증 필요).
- **parent2 == cert.headSha** — 인증된 PR head 객체가 merge commit의 두 번째
  부모로 직접 상속된다(MERGE 방식의 구조적 이점 — rebase replay와 달리 head
  객체의 도달성이 보존된다).
- **headTreeDigest** — 인증된 head의 tree 내용이 착지 merge commit에 그대로
  상속되었음을 내용주소로 검증.
- **certTree (PR-3, 2026-09-26 — identity chain 결속)** — certificate는 착지 전
  등식의 인증서 측 반영으로 `certTree`(merge-candidate tree OID = tree(github.sha),
  the test merge ref)를 서명 바인딩 블록에 기록한다:
  `certTree == witness.mergeTreeDigest == gateway testedTreeDigest == mergeTree`
  (ADR-0025 §11). mint는 witness.mergeTreeDigest를 tree(mergeSha) 재유도와
  fail-closed 대조한 뒤에만 certTree를 서명하며, 착지 후 `M.tree == certTree`
  대조는 **audit observation**(게이트 아님)으로 C1의 기계 검증 conjunct 집합
  (2-parent ∧ parents ∧ headTreeDigest)은 변경되지 않는다.
- **[ADR-0027 Phase 0 측정 확정 — α (2026-09-29)]** — 큐 경유 착지에서
  **cert.headSha는 PR head H에 결속된다** (기존 C1 문구 무변경, 개정 없음).
  probe 실측 2회 연속(`docs/evidence/merge_queue_probe_2026-09-29.md`):
  착지 커밋 L == 머지그룹 커밋 G이며 `parents(L) == [B, H_PR]` — G의 두 번째
  부모가 PR head이므로 C1의 `parent2 == cert.headSha`가 그대로 성립한다.
  merge_group 런에서 subject head는 `G^2`로 유도하며, G가 2-parent가 아니면
  fail-closed (측정된 α 형태의 가정이 깨짐 = γ 탐지). identity 분리:
  **실행·아티팩트·run identity = G** (`github.event.merge_group.head_sha` —
  ADR-0027 P2 candidate-key 소스 선택, 아티팩트 `admission-check-<G>-<run_attempt>` — 2026-10-04 개정: attempt 결속 복원),
  **인증 subject = (B, H_PR = G^2)** — §2.6 IDENTITY에 따라 둘을 혼동하지 않는다.
- **기계 검증**: `ax cert continuity --main <sha> --cert <path>` (cert_cli) —
  parents/tree는 I/O 경계에서 `git rev-parse <main>^1` `^2` `^{tree}`로 해석.

**PR MERGED bookkeeping 주석 (Model B → CAS 랜딩)** — native MERGE 방식에서는 PR head가
merge commit의 parent2이므로 GitHub가 PR을 merged로 표기한다(rebase replay의
"Indirect merges 미발화" 문제는 rebase-only 설계의 전유물로 소멸). PR close는
GitHub가 자동 수행하지 않는다 — `updateRefs` ref 업데이트는 PR을 닫지 않으며, PR
close·PR MERGED 표기는 **Landing App이 수행하는 bookkeeping**이다(§10.6). PR MERGED
표기는 순수 bookkeeping으로 continuity predicate의 입력이 아니다.

- **I-1 (정적)**: main을 전진시킬 수 있는 workflow = actuator 전용 —
  workflow-permissions 계약 게이트(ci_dag_contract_gate 선례).
- **I-2 (런타임 감지)**: continuity workflow — Model B predicate 검사.
  push 트리거는 외부 착지 감지; actuator는 착지 직후 동일 술어를 실행.
  **I-2 verdict는 SELF-CONTAINED(인가된 journal-free predicate)**: verdict 입력 =
  main merge-commit object(parents/tree) + side-ref 원장 certificate +
  **tracked policy/scope 파일** 전부. **trust journal(`data/trusted/journal/`)은
  audit/forensic record일 뿐이며 verdict에 절대 consult되지 않는다** — journal
  부재/공백은 결과를 바꿀 수 없다. envDigest/toolchainIdentity는 서명된 기록
  사실로 형식 검증만 하며 런타임 재계산하지 않는다. certificate 자체 무결성
  (Ed25519 attestation · 현재 policy/scope digest)으로 판정한다(INV-12).
- **I-3 (원장)**: side-ref FF-only + webhook `forced`/`deleted` 감사 + gate_history
  병합 감사. 방지(prevent)는 플랜 상승 후 branch protection/rulesets(Phase 6).

**I-2 transport revision (2026-09-18, ADR-0022)** — canonical-main.yml의 3-job
실행 경계(bind → continuity(workflow_call `merge_continuity.yml`) → accept)는
**단일 job의 ordered steps**(bind → continuity → accept)로 축소된다. authority
semantics 불변: 술어 전부 · reasonCode(L0_*/L2_*/L3_*/L4_CERT_LINK_FAILED/cc*) ·
fail-closed 경계 · accept-last · R(H) CAS append · top-level read-only +
job-level contents: write(기존 패턴) · push-event-as-transport · mint/attest 호출
없음. 기계적 변경: 단일 checkout(ref: github.sha, fetch-depth: 0), 단일 bin/ax
build, toolchain-cache restore 제거(dependency probe — receipt 경로는
cache/toolchain 자산 비참조), deps는 host-side fail-closed 검증(설치 없음), token
= GITHUB_TOKEN env(기존 script 계약). `merge_continuity.yml` 호출 종료(유일 호출처
canonical-main.yml:144) — continuity 로직은 `tools/ci/run_landing_continuity.sh`로
기계 추출(equivalence golden test `tools/ci/test_run_landing_continuity.sh`: 동일
입력 → 동일 cert 선택 · 동일 메시지 · 동일 exit status), 파일 자체를 수정하지 않는
retirement(caller-0 artifact)는 별도 slice로 이연. §-1 승인: ci.yml-family 권위
파일 — 본 세션 architect 명시 지시 2026-09-18(선례: ci.yml tombstone fa069d610,
2026-09-16). 범위 밖(불변): admission_producer.yml(CI=0 cutover로 삭제됨) · merge_admission.json 정책 ·
bind 술어 · branch protection(Phase 6 deferral 유지) · nightly backstop. 상세:
ADR-0022 D8 · `tools/ci/run_landing_continuity.sh`.

**R(H) accept retirement note (2026-10-07, authority_contract.md §5.4)** — 위 I-2
transport revision(2026-09-18)이 기술한 accept-last · R(H) CAS append 단계는
**RETIRED**다. GitHub required check(`admission-check`) + merge queue가 이미
authoritative acceptance이므로(`authority_contract.md` §4 merge authority), 동일
역할의 제2 수용 표면인 canonical-acceptances ledger writer(`ax admission accept`
서브커맨드 + `acceptLanding`/`readAcceptanceForLanding`/`acceptanceRewriteSeen`)
가 폐기되었다. 위 원 문구는 역사 보존을 위해 그대로 둔다(retirement만 본 note로
기록). `refs/heads/axiom/canonical-acceptances` ref 자체는 보존된다(비가역 삭제
금지 — AGENTS.md §2.5); writer만 retire되어 해당 ref는 읽기 전용 역사 증거가
된다. 상세: ADR-0022 실행 기록(2026-10-07, canonical-acceptances writer
retirement).

**Publication method note (Model B)** — GitHub MERGE 방식의 merge commit은
"whose parents are the latest commit on the base branch and the pull request's
head commit"(공식 문서 + 실측)이므로 인증된 (base, head)가 착지 커밋에 직접
기록된다. rebase 방식("Always updates the committer information and creates new
commit SHAs")은 head 객체 도달성을 파괴하므로 Model B에서 금지된다 — repo
설정에서 rebase/squash를 비활성화하는 것이 이 계약의 강제 수단이다.

## 5. 불변식 (HARD RULES)

| ID | 불변식 | 위반 시 | 근거 |
|---|---|---|---|
| INV-1 | merge admissible ⇔ certified subject (`baseSha, headSha, headTreeDigest, policyDigest, scopeDigest, evidenceDigest`) == actual merge inputs **∧ certificate `certTree` == merge-candidate tree OID — 착지 전 identity 3중 등식 `testedTree == mergeTree == certTree`(ADR-0025 §11, mint fail-closed 재검증 + 게이트 verdict 대조)** (Model B — OID binding은 사전 예측을 요구하므로 폐기) | fail-closed abort | gitglossary: object 불변성; GitHub MERGE commit parents 구조(공식+실측); ADR-0025 §11 |
| INV-2 | 착지는 GitHub native MERGE commit — continuity가 merge-commit shape(parents/tree)로 인증 입력 상속을 검증 (Model B; exact-object FF-CAS는 superseded) | parents/tree 불일치 → continuity FAIL(fail-visible) | 공식 문서 merge-commit parents + 실측 8a44110c |
| INV-3 | continuity의 tree 재유도 금지 — 착지 merge commit의 parent2 tree OID 해시만 대조 | 계약 위반 = 구현 결함 | 내용주소 검증은 재유도가 아니라 대조 |
| INV-4 | 구조적 독립성 — 동일 생성기 산출물 간 등가는 증거 불인정; 대응 검사 구현은 (다른 언어) 또는 (다른 유도·다른 spec 판독)이어야 함 | differential 무효화 | lean4lean: "not really an independent implementation"; Knight–Leveson |
| INV-5 | evidence 등급: R-derive(재유도) > T-tool(main-built 도구 산출) > L1(생산자 자체 receipt — 인증 근거에서 배제) | L1 채용 = 인증 거부 | SLSA L1 "trivial to bypass or forge" |
| INV-6 | kernel verdict만 unforgeable; `#print axioms` allowlist = {propext, Classical.choice, Quot.sound, funext}; `native_decide`/`Lean.trustCompiler` 계열 자동 거부 | 인증 거부 | Lean Reference §8.4/§8.5, ValidatingProofs |
| INV-7 | untrusted tier는 contents:read + 시크릿 미참조(정적 게이트로 강제) | 매트릭스 위반 = gate FAIL | same-repo PR은 시크릿·write token 수급(fork만 샌드박스) |
| INV-8 | certificate 원장은 main tree 밖 side-ref, FF-only append | 변조 감지(I-3) | git object 불변성 |
| INV-9 | certificate 의미론 문장(§2) 스냅샷 + 금지 주장("Nim semantics certified", "최종 TCB 폐쇄" 등) 정적 스캔 | gate FAIL | §8.4 — 용어의 정직성 |
| INV-10 | Z3 결정론은 공학 고정(바이너리 체크섬·seed 0·rlimit)이지 보장이 아님 — 재실행 verdict 불일치 시 fail-closed | 인증 거부 | z3guide `random_hammers` 기본 true |
| INV-11 | conflict/lossy = 인증 거부(subset 경계 fail-closed) | 인증 불가 | merge-tree exit status; lossySeen |
| INV-12 | continuity verdict는 self-contained — verdict 입력 = main object + side-ref 원장 certificate + tracked policy/scope 파일뿐; trust journal·build 환경 재현·treeDigest 재유도 미요구(INV-3) — journal은 audit/forensic record | verdict 미성립 = 계약 위반(구현 결함) | SLSA "Verify the envelope's signature… the subject matches the digest of the artifact"(provenance가 artifact digest와 직접 대조 — 외부 입력 미요구) + reproducible-builds.org "byte-for-byte identical build output" 기반 checksums — journal-free predicate이 두 공식 근거를 만족 |
| INV-13 | subject당 certificate 1개 — side-ref 원장에는 동일 subjectId에 대한 certificate가 정확히 1개만 존재한다(mint 직전 `listLedgerCertIds` 멤버십 검사로 강제 — ADR-0021 D6; **D6 멱등 판정 해석 2026-09-27 — record 재계산 정당성, §5 아래 노트**) | 중복 mint = 계약 위반(fail-closed) | ledger 멤버십(INV-8) + ADR-0021 D6(duplicate-subject predicate before mint) — rerun 재발화와 무관하게 authority 중복은 ledger 단일 소스로 차단 |

**INV-13 소급(2026-09-12)**: INV-13 도입 이전의 중복 cert(`cb18ed82`/`dfd70bf9`, headSha `bfc4899a`)는 append-only 원장의 historical record로 보존하며, canonical authority = createdAt 기준 최신 cert. 이후 신규 mint는 D6로 차단.

**INV-13 D6 멱등 판정 해석 개정 (2026-09-27, 실행 authority 단일화 계획 rev.7 D6)**:
멱등 판정 = 원장 record로부터 subjectId 재계산 == 키 ∧ record certTree == re-derived
tree(mergeSha) — **키(주장된 subjectId) 멤버십이 아니라 record 정당성** 검사이며,
손상·불일치 = fail-closed. **witness digest 조건은 폐기** — witness digest는
run-scoped(provenance 기록용)이며 runId/createdAt이 digest 내부에 있어 **교차 런
정체성 비교가 성립하지 않는다**(계획서 D6-A). 발행 원자성 = **CAS 3분기**: 성공 →
append 1 / 실패 → 재조회 → (record 재계산) 성립 → PASS(0) / 불성립 → FAIL-CLOSED
(재시도 루프 내부 reconciliation — ADR-0025 §14 bounded retry-on-conflict 유지,
`force:false` 불변). 따라서 **exactly-once**: 첫 publish append = 1, 동일 subject
재실행 append = 0(계획서 [B1]·[D]). INV-13 "1 cert per subjectId" 불변은 이 해석
아래 그대로 강제된다.

## 6. Subset 멤버십 기제

- **현행**: (a) extraction 하강의 lossy 경로 — fail-closed(`translationLossFree`
  플래그), (b) `verification_scope.lock`(kernel symbol universe).
- **계획(Phase 2)**: 흩어진 판정 근거([ir_pipeline_integration.md](ir_pipeline_integration.md),
  nim_if_elif_ir_quirk.md, known-limitations.md LIM-2026-07-08-001)를 **단일 정책
  아티팩트**로 통합 — SPARK Language Restrictions 대응. subset 밖 construct는
  인증 커버리지 밖(SPARK "not in SPARK" 모델).

## 7. Phase roadmap + 기존 문서 갱신 매핑

| Phase | 내용 | §-1 |
|---|---|---|
| 0(본 문서) | 계약 선언 + TrustSurface 선행 등록 | 없음 |
| 1 | chain materializer(merge-tree ≥2.40 + commit-tree, git 버전 고정) | 없음 |
| 2 | evidence 스키마 + untrusted tier 재구성(dispatch ref=main) — **Phase 2 subject certification foundation DONE**: `src/verification/verification_subject.nim`(VerificationSubject 모델 + subjectId canonical wire + `verifySubject`/`verifySubjectMatch` equality-only verdicts), `src/verification/subject_store.nim`(append-only `data/trusted/subjects/` store), `data/verification_subject_schema.json`(draft-07), golden fixtures `data/trusted/subjects/*.json`(3), `merge_materializer.subjectFromCandidate` + `ax merge subject`(발급·영속화). 테스트: `tests/verification/test_subject.nim` | 없음 |
| 3 | kernel re-execution(`ax cert verify` 확장 — 현행 "zero solver calls" 한계 해소) — **Phase 3 DONE**: `src/verification/kernel_reexecution.nim`(KernelVerdict 9-분류, INV-6 `#print axioms` allowlist {propext, Classical.choice, Quot.sound, funext} + sorry/native_decide/trustCompiler deny, `reexecuteLean`/`reexecuteZ3` — rlimit-primary envelope 재사용·fresh 실행·temp-file 채널, INV-10 z3 바이너리 체크섬 정책), `src/cli/cert_cli.nim`(`ax cert verify --kernel` — 구조 검증 통과 후 재실행, 비-krPassed → 비-영 exit + 사유), `src/core/contracts/z3_extraction.nim`(`-T:` wall-clock 제거 → `buildRlimitPrimaryEnvelope` rlimit-primary), `data/policy/z3_binary_checksums.json`(4.13.3 sha256), 테스트 `tests/verification/test_kernel_reexecution.nim`. 테스트: 71 checks 통과 (lean/z3 부재 시 loud SKIP, exit 0) | 없음 |
| 3.5 | Tier 1 kernel-inside closure(수기 Lean denotation, render_eq_eval 등가정리, MetaCheckIR 배선, 이중 렌더러 differential) — **Phase 3.5 DONE**: `proofs/IR/Denotation.lean`(hand-written denotation — `evalIR`/`renderInt`/`renderIR`/`Certified`/`certifiedSubset`, kernel-checked `render_eq_eval`·`renderInt_eq_eval`·`renderIR_eq_eval`(certified subset 위 rendering=denotation, #print axioms ⊆ INV-6 allowlist), `proofs/IR/AxiomIRExpr.lean`(irCast 0x0D inductive+decoder 추가 — 코드 갭 폐쇄), `proofs/IR/MetaCheckIR.lean`(checkIRFromBytes 실배선 + irCast case), `proofs/IR/LeanWorker.lean`+`proofs/IR/IRCheckWorker.lean`(--check-file 모드 + standalone `ircheck` exe, lakefile.lean), `src/verification/kernel_reexecution.nim`(`checkIRWithLeanWorker` — temp-file 채널 + argv-quoting, QUIRK(quirk#runGitEx-argv-flattening)), `src/verification/renderer_differential.nim`(canonical vs ir_to_lean overlap differential — rdAgree/rdDisagree/rdSkip), 테스트 `tests/verification/test_semantic_closure.nim`(55 checks — real-lean SKIP guard 포함) | 없음 |
| 3.75 | Tier 2 extraction agreement(AST wire codec, 독립 유도 reference extractor, fail-closed 배선) — **Phase 3.75 DONE**: `src/verification/ast_wire.nim`(certified-subset canonical-AST wire codec — magic 0xA0 + version; tag style는 ir_binary_codec과 동일하게 8-byte 정렬; 지원 kind: int/char/nil literals, ckIdent, ckInfix, ckPrefix, ckCall, ckStmtList, ckLet/Var/ConstSection(단일 ckIdentDefs), ckAsgn(ckIdent target), ckReturnStmt, early-return ckIfStmt, ckProcDef/ckFuncDef+ckFormalParams — 나머지 전부 aweUnsupported fail-closed), `proofs/IR/ReferenceExtractor.lean`(수기 Lean 4 reference extractor — INV-4 독립 유도: 다른 언어 + 자체 wire 디코더 + 자체 IR 인코더; lean4lean 스타일 derivation 아님을 헤더에 명시, subset 위 byte-equal) + `proofs/IR/IRCheckWorker.lean`(`ircheck extract --ast <astwire> --out <ir.bin>` 모드, exit 0/1/2), `src/verification/extraction_agreement.nim`(per-run differential — Nim extractor(axiomBodyCanon) vs Lean reference, 직렬화 IR byte-equal 검증; eaAgree/eaMismatch/eaUnsupported/eaReferenceError/eaInternalError, temp-file 채널 QUIRK(quirk#runGitEx-argv-flattening)), `src/cli/merge_cli.nim`(`ax merge agree --ref <candidateRef> --func <f> --file <path>` + stage merge-extraction-agreement journaling — verdict + 양쪽 IR digest), 테스트 `tests/verification/test_extraction_agreement.nim`(38 checks — real-lean SKIP guard 포함; dual-frontend 미중복 참조: wp15). **알려진 이탈 해소(2026-10-19)**: canonical extractor의 early-return-if가 0 아닌 return value를 irLit(0)으로 강등하던 결함(extractReturnValueCanon이 elif branch를 받는 구조)이 수정됨 — `convertBodyFromCanon`이 이제 then-body(branch.child[1])를 전달하며 양측 추출기가 조기-리턴 위 byte-equal 합의(래퍼런스는 원래 참 값 보존). 해당 함수는 더 이상 eaMismatch로 표면화하지 않음 | 없음 |
| 4 | trusted attest tier + MergeAdmissible 확장 + publication 전환 — **Phase 4 (Trusted Attestation) DONE**: `src/verification/attestation_orchestrator.nim`(`attest(subject, evidence)` — trusted Verify(E,M) chain IN ORDER, fail-closed: (a) store subject reload + `verifySubjectMatch` exact equality, (b) Tier-2 extraction agreement `eaAgree` required — EA_UNSUPPORTED는 여기서 FAIL, (c) `reexecuteLean`+`reexecuteZ3` 둘 다 krPassed, (d) policy digest = sha256(config/policy/merge_admission.json), (e) D2 pinned toolchain identity `nim-<v>|lean-<v>|z3-<v>`, (f) scope digest = sha256(data/verification_scope.lock), (g) ALL PASS → mint), `src/verification/cert_writer.nim` 확장(`writeSubjectContinuityCertificate` — v3 certificate extension, kind `subject-continuity`, claim.type 동일; subject binding(candidateCommit/treeDigest/baseSha/prHeadSha/chain entries+dropped/envDigest/policyDigest/scopeDigest/evidenceDigest/toolchainIdentity/subjectId) + 기존 TrustCommit journal binding + 기존 Ed25519 attestation block), `src/verification/ledger_side_ref.nim`(side-ref `refs/heads/axiom/certificates` FF-only append ledger — Git Data API blob→tree(base=tip)→commit(parent=tip)→PATCH force=false CAS; injectable transport; `appendCertificate`/`listLedgerCertIds`), `src/cli/cert_cli.nim`(`ax cert attest --ref <candidateRef> [--pr N] [--evidence <path>]` + `ax cert subject-register --base <B> [--pr N] [--head-tree <oid>] [--evidence <path>]` — **F8 2026-09-12**: trusted-boundary subject registration from VERIFIED evidence (canonical 6-field subjectId re-derived, append-only store; never trusted from the artifact) + `ax cert ledger-append <certPath>` + `ax cert ledger-list` — merge-attestation/ledger-append/merge-subject-register journaling, exit 0 only on atPassed), `.github/workflows/attest.yml`(trusted tier만 — workflow_dispatch, checkout=main, contents: write + **actions: read — F8 2026-09-12**: untrusted-tier evidence artifact download + binding verification(dispatch headSha == evidence.prHeadSha; GitHub API tree re-derivation; policy/scope/toolchain recomputation — bind fail = mint refused, fail-closed) + subject-register before the chain; §4.2 boundary header + INV-5 run.conclusion 비증거 주석), `.github/workflows/verify-candidate.yml`(**F8 2026-09-12** — untrusted-tier evidence EMISSION step: after the same Make gates the PR CI runs, assembles `axiom.attestation.evidence.v1` from `git show <head>:continuity_probe.nim` + checked-in probe fixtures `data/certification/probe_sanity.{lean,smt2}` + sha256(policy/scope/env/toolchain); jq -cS = RFC 8785 byte-identical to the Nim canonicalJsonString SSOT; uploads as artifact `attestation-evidence-<headSha>`), evidence record schema `axiom.attestation.evidence.v1`(untrusted-tier 검증 기록 — kernel/extraction 입력 + digest 바인딩), 테스트 `tests/verification/test_attestation.nim`(체인 순서·fail-closed 전 경로 + real lean/z3/ircheck happy path mint→tamper→`ax cert verify` reject→`--kernel` roundtrip + fake-transport ledger FF/non-FF/malformed). MergeAdmissible 확장 + publication 전환은 후속 단계 (관련 워크플로 — verify-candidate.yml·attest.yml 등 CI=0 cutover, 2026-09-20로 삭제됨) | 없음 |
| 5 | continuity 게이트 + main CI 전환(continuity-only, nightly backstop 유지) — **Phase 5 (Admission + Exact Publication) DONE** (ci.yml 전환 = 5c, 미착수): `src/cli/merge_cli.nim` `MergeAdmissible` Pass 2.96 certificate-continuity(인증서 존재 NO_CERT(missing ≠ valid empty — `certRequired`) · Ed25519 서명 CERT_INVALID · `cert.candidateCommit == actualCandidateCommit` SUBJECT_MISMATCH(INV-1 exact-object; 재유도 금지 INV-3) · policy/scope digest POLICY_MISMATCH/SCOPE_MISMATCH — 후속 base-freshness 패스는 불변 STALE_BASE; `CertificateContinuityFacts` + `collectCertificateContinuityFacts`(side-ref 원장 listLedger+download, injectable transport)), [REMOVED 2026-09-10 — superseded by native MERGE + continuity] `publisher.nim` `publishM` FF-CAS publication (historical), `src/verification/ledger_side_ref.nim`(`downloadLedgerCertificate`+`blobEntrySha`+`decodeBlobContent` — 원장 cert read 경로), [REMOVED 2026-09-10 — Model B] `ax merge publish` path and `tests/verification/test_publication.nim` (historical); the actuator (`ax merge --apply`) is the single certified landing path — merge_admission_controller.md §10/§11. **병존 (2026-10-09)**: subject-continuity Pass 2.96은 무변경이며, 형제 pass 2.96b(vault cert — [proof_required_admission_contract.md](proof_required_admission_contract.md))가 code 어휘를 공유하고 독립 판정한다 (전환 계약 §4) | **ci.yml — §-1 PENDING (5c cutover)** — 아티팩트: `config/changes/ci-continuity-cutover.patch`(5c 행/§10 상세) |
| 5b | continuity workflow + publication-scope static gate — **Phase 5b (Continuity Workflow + Publication-Scope Static Gate) DONE**: `src/verification/continuity_check.nim`(`verifyContinuity` — 예외 없는 pure verdict: main tip == certified M OID exact object-level compare(INV-1/INV-2), cert 부재 → `ccNoCert`(missing ≠ valid empty), 변조/구조 검증 실패 cert → `ccError`(기존 structural closure `verifyCertificateClosure` + Ed25519 attestation 재사용 — tampered cert에 대한 continuity는 반드시 실패), `verifyContinuityCert`(I/O 경계), `continuityVerdictCode`; **CHEAP post-merge check — full L2 아님을 명시**(kernel 재실행 없음; full-L2 backstop은 nightly)), `src/cli/cert_cli.nim` `ax cert continuity --main <sha> --cert <path>`(구조 검증 + 서명 + exact compare; `merge-continuity` journal; exit 0은 ccPassed뿐 — fail-visible), `src/gate/runners/publication_scope_gate.nim`(I-1 정적 게이트 — hand-rolled line parser로 **모든** `.github/workflows/*.yml` 트리거+permissions 파싱, unknown workflow → FAIL("register in publication_scope.json"), rule 위반(contents: write / pull-requests: write drift)·contract 미존재·파싱 불가 → FAIL; `--selftest` golden mini-workflows 5케이스), `config/publication_scope.json`(11 workflow 규칙 — attest.yml 유일 contents_write: true; auto_merge.yml 유일 pull_requests_write: true), `.github/workflows/merge_continuity.yml`(push: branches[main] + workflow_dispatch; contents: read만; GITHUB_TOKEN 무트리거 recursion + actuator 명시 dispatch 요구를 헤더에 문서화 — human/PAT push = mismatch fail-visible, actuator dispatch = explicit path; main tip == 최신 ledger cert의 certified M OID 비교), topology 등록(`src/gate/topology_spec.nim` publication-scope-gate entry + `tools/sync_topology.nim` 재생성 — gates.manifest.toml/manifest.d/_index/gate_registry) + Makefile `check-publication-scope`(GATES_STATIC/GATES_CI_VERIFYSTATIC), 테스트 `tests/gate/test_publication_scope_gate.nim`(real workflows PASS + rogue workflow/contents:write/undeclared trigger/unparsable FAIL) + `tests/verification/test_continuity.nim`(ccPassed/ccMismatch/ccNoCert/ccError 전 verdict + 구조 검증 fail-closed) (해당 워크플로 auto_merge.yml·merge_continuity.yml 등은 CI=0 cutover, 2026-09-20로 삭제됨 — publication_scope.json 규칙은 역사 설계 기록) | 없음 |
| 5c | main full-L2 → continuity-only cutover(ci.yml `if:` 가드 5건 적용 — verify-static/verify-integration-r1/verify-integration-r2-unit/verify-integration-r2-proof/verify-coverage-guard를 push:main에서 제외; continuity = merge_continuity.yml(push: main, Phase 5b)이 담당; PR cert = merge-boundary 인증의 권위 경로 유지; **nightly full L2 = 독립 backstop 불변**) — **Phase 5c APPLIED 2026-09-11**: `config/changes/ci-continuity-cutover.patch`를 본 세션 사용자 명시 승인(§-1 예외) 하에 적용 — `git apply --check` 통과 후 정확히 5행 치환(+5/−5), nightly·generate-docs·coverage needs-edge·workflow_run admission 불변 확인. readiness_start.yml push:main trigger도 동시 제거(PR+merge_group만 유지 — byte-identical 중복, 소비자 없음; `continual_revalidation.md` §3/§6 동기화). E2E 증거는 Phase 13 실측으로 확정 예정 | **APPLIED — E2E 증명 진행 중**(아키텍트 승인 = 본 세션 사용자 지시 기록; 적용 대상 워크플로 readiness_start.yml·ci.yml 등은 CI=0 cutover, 2026-09-20로 삭제됨 — 상기 트리거 서술은 역사 기록) |
| 6 | end-state hardening(구현 가능 scope + 문서만) — **Phase 6 DONE/DEFERRED (2026-09-10)**: ① reference-extractor 독립성 감사 기록 DONE — `docs/audit/reference_extractor_audit_2026-09-10.md`(INV-4 독립 유도, subset 목록, 알려진 이탈, Phase 3.75 검증 근거, reviewer 체크리스트); ② subset extraction soundness 로드맵 DONE(CompCert 종착형 — §10.4, 감사 문서 §6); ③ leanchecker 독립 커널 교차검증 **DONE** — `src/verification/kernel_reexecution.nim` `checkLeanWithLeanChecker`(elan 제공 `leanchecker` 존재 시 재검증, 부재 시 loud SKIP, 불일치 시 fail-closed — `ax cert verify --kernel`/`ax merge publish` 배선, 테스트 P10); ④ GitHub App minter — 재개 승인(§10.2, ADR-0024); ⑤ 플랫폼 prevent **DEFERRED**(§10.2 — branch protection/rulesets는 플랜 제약) | 없음(③은 §-1 밖 일반 절차) |

**기존 문서 갱신 매핑**(구현 phase와 동반): ADR-0020 D8 개정(Phase 1) ·
[merge_admission_controller.md](merge_admission_controller.md) §2b/§8/§10(Phase 3-4) ·
§7/§8/§10/§11(Phase 5 — certificate-continuity admission + exact-object publication) ·
rules_workflow.md:118/:120 landing path(Phase 3) · operations.md Merge-Boundary
(Phase 5c) · L2 정의(Phase 5c; 원 anchor `incremental_ci_contract.md`는 CI=0 cutover, 2026-09-20로 삭제 — 보존된 ADR-0017이 P2 계약 참조본).

## 8. 외부 공식 근거 (§0.5)

### 8.1 Git

- gitglossary: "It is uniquely identified by the SHA-1 of its contents. Consequently, an object cannot be changed." — INV-1/INV-8 기반. https://git-scm.com/docs/gitglossary
- git-push(1): "only fast-forward updates are allowed, which means the destination must be an ancestor of the source commit." — INV-2. https://git-scm.com/docs/git-push
- git-merge-tree(1): "Performs a merge, but does not make any new commits and does not read from or write to either the working tree or index."; EXIT STATUS 0/1/기타; `--merge-base`는 v2.40 도입(v2.38 아님). https://git-scm.com/docs/git-merge-tree
- git-commit-tree(1) + git(1) ENVIRONMENT: GIT_AUTHOR_*/GIT_COMMITTER_* 고정 — chain 결정론. https://git-scm.com/docs/git-commit-tree
- git-fetch(1)/gitprotocol-pack: advertised tip fetch + 조상 전달; SHA fetch는 server gating에 의존. https://git-scm.com/docs/git-fetch
- git RelNotes: v2.38.0 — "git merge-tree" learned a new mode where it takes two commits and computes a tree that would result in the merge commit(`--write-tree` 도입); v2.40.0 — "merge-tree" learns a new `--merge-base` option; v2.41.0 — "git merge-tree" reads the basic configuration(b6551feadf — merge-tree 구성 읽기 체계 경계); v2.43.0 — `-X` 전략 옵션. — §11.1 핀 근거. https://github.com/git/git/tree/master/Documentation/RelNotes
- actions/runner-images Ubuntu2404-Readme: GitHub-hosted 이미지의 git은 이미지 롤에 따라 부유한다(2026-10-12 기준 Git 2.55.0 기재; Git LFS 3.8.0) — §11.1 상한 미고정 근거. https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md

### 8.2 GitHub

- events-that-trigger-workflows: `pull_request`는 merge result를 checkout("Your CI tests run against the merged result"); fork PR 시크릿 비노출; GITHUB_TOKEN 무트리거("if a workflow run pushes code using the repository's GITHUB_TOKEN, a new workflow will not run…"); workflow_dispatch 파일 = dispatch ref 버전. https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows
- about-workflows: "Each workflow run will use the version of the workflow that is present in the associated commit SHA or Git ref of the event." — dispatch-ref 파일 버전 구멍의 근거이자 해법. https://docs.github.com/en/actions/using-workflows/about-workflows
- security hardening: "pwn request"("root cause of multiple supply-chain compromises"); "For privilege separation between workflows, workflow_run is a better trigger"; self-hosted 러너 경고; "Workflows triggered on workflow_run should treat artifacts uploaded from other workflows with caution". https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions
- workflow-syntax: permissions 표, reusable workflow @SHA pin("Using the commit SHA is the safest option"), callee 권한 downgrade-only. https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax
- REST git/refs: `force=false` = "make sure you're not overwriting work"(FF CAS); REST pulls: merge 결과 SHA는 응답 전용. https://docs.github.com/en/rest/git/refs
- merging: "Always updates the committer information and creates new commit SHAs" — rebase merge는 새 commit SHA 생성 → certified M과 상이(§4.4 publication path note). https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/merging-a-pull-request
- "Indirect merges" — "A pull request can be marked as merged if its head branch commits become reachable from the base branch outside that pull request… pushed directly to the default branch" — PR head == M 직접 push는 GitHub "indirect merges"로 처리되며 이는 bookkeeping(PR MERGED 표기)일 뿐 I-2 입력이 아님(§4.4 결정 구조). https://docs.github.com/en/pull-requests/reference/pull-request-merges
- caching-dependencies: "Cache contents are not signed or verified" — certificate 저장소 부적격. upload-artifact v4: "Artifacts created by upload-artifact@v4 are immutable."
- plan 제약: branch protection/rulesets/environments는 private+free org 불가(공식 플랜 문구); pre-receive는 GHES 전용 → §4.4의 방지(defer) 근거.
- troubleshooting-required-status-checks: required check는 test merge commit(없으면 head commit)만 평가 — merge result 보장은 merge queue 외 불가.
- SLSA (supply-chain levels for software artifacts), v1.0 "Verifying artifacts": verification = "Verify the envelope's signature using the roots of trust" + "Verify that statement's subject matches the digest of the artifact in question" — provenance 검증은 artifact digest와의 직접 대조이며 외부·비재현 입력을 요구하지 않음 — INV-12(continuity verdict는 main object + 원장 cert + tracked policy/scope 파일로만 산출). https://slsa.dev/spec/v1.0/verifying-artifacts
- reproducible-builds.org (cryptographic checksums): "byte-for-byte identical" build output 위에서만 "cryptographic checksums"가 성립 — checksum이 build output 자체에서 계산 가능해야 검증 의미를 가짐 — I-2의 fingerprint/identityDigest/policy·scope digest 재계산이 output이 곧 검증 입력인 구조(journal-free). https://reproducible-builds.org/docs/checksums/

### 8.3 Lean / SMT

- Lean Reference: kernel = "a minimal kernel that does nothing other than check proof terms… bugs in tactics do not threaten the soundness of Lean as a whole"(§2.3); `#print axioms`(§8.5); sorryAx "can be used to prove anything"(§8.4); `decide`/`native_decide`(ValidatingProofs — native는 "can be used to create invalid proofs whenever the native evaluation of a term disagrees with the kernel's evaluation"); Tactic-Proofs: "Each proof is checked in the kernel, and can be verified with independently-implemented external checkers". https://lean-lang.org/doc/reference/latest/
- Lean 4 paper(CADE-28): "relatively small trusted kernel, and the rich API allows users to… implement their own reference checkers". lean4checker: "This is not an external verifier, as it uses the Lean kernel itself"; lean4lean: "derived directly from the C++ kernel implementation… not really an independent implementation" — INV-4의 생태계 전례.
- Lean FAQ: 번역 도구의 대응 가정 "become part of the TCB"; "Multiple checkers can be used to further increase confidence". https://lean-lang.org/faq/
- Aeneas use-case: "generates Lean code that faithfully represents the original Rust program… preserves the semantics" — 외국어→Lean 인증 패턴. https://lean-lang.org/use-cases/aeneas
- SMT-LIB v2.6 §4.2/§5.1: unsat = "the solver has established there is no model"; assert/check-sat 의미론. https://smt-lib.org/
- z3guide Parameters: `random_hammers` 기본 true 등 — INV-10(결정론 무공식 보장). https://microsoft.github.io/z3guide/

### 8.4 선례·학술 (프레이밍 앵커)

- SPARK 2014 LRM: "SPARK is based on Ada, both subsetting the language to remove features that defy verification…"; UG: "'not in SPARK'… is not amenable to formal verification"; GNATprove는 SPARK_Mode 부분만 분석. — §2/§6의 모델.
- CompCert CACM: "machine-checked proof of a semantic preservation property"; Clight = "a large subset of the C programming language"; §5 잔존 TCB(미검증 parser 포함) 자인; "Despite intensive testing, bugs in compilers do occur". https://xavierleroy.org/publi/compcert-CACM.pdf
- Pnueli et al., translation validation(TACAS'98): "each individual translation… is followed by a validation phase which verifies that the target code produced on this run correctly implements the submitted source program."
- Necula, Proof-Carrying Code(CMU): "the receiver is able to use a simple and fast proof validator to check, with certainty, that the proof is valid".
- Knight–Leveson: N-version 실패 독립성 가정 통계적 기각 — INV-4. Dijkstra EWD249: 테스트는 버그 존재만 보여줌 — INV-5의 L1 배제.
- FAA AC 20-115D / DO-330: 도구 자격(tool qualification) — frontend의 "qualified" 지위.
- Nim manual: prose spec("This manual is constantly evolving into a proper specification") — 형식 의미론 부재 → subset denotation 정의가 유일 경로.
- **"formally bounded certification"은 공식 용례가 없다**(2026-09-09 검색 0건) — 본 문서가 정의하는 project-defined 용어다.

## 9. 잔존 리스크 (정직한 한계)

1. **proposition 정책 커버리지**: kernel이 증명한 proposition 집합이 merge 승인에
   불충분하면 "kernel이 True를 증명했다"는 공증(극장)이 됨 — 정책 정의(Phase 2)가
   최우선이며, 커버리지 게이트가 이를 강제한다.
2. **인코딩 충실도**: P(M)과 M의 연결은 Tier 2 합의 + 선언된 subset으로 경계 —
   extractor 자체는 qualified TCB이며, 종착형(soundness 정리)은 Phase 6.
3. **Z3 verdict**: pinned solver 정확성 가정 + self-validation 수준 — Lean kernel
   (독립 체커 보유)과 등급 구분 표기(INV-10).
4. **self-hosted 러너 상 untrusted 빌드**: 시크릿 제거로 피해 상한을 러너 자체로
   제한; VM-per-job 로드맵은 기존 [self_hosted_ci_migration.md](self_hosted_ci_migration.md)(CI=0 cutover,
   2026-09-20로 삭제 — self-hosted 러너 인프라 자체가 제거됨)에 위임.
5. **원장 ref 강제 push/삭제 방지 불가**(플랜) — I-3 감지로 흡수.
6. **bookkeeping**: rebase chain publication은 GitHub merged 표기를 만들지 않음 —
   journal이 SSOT(§4.3, 의도된 수용).

---

## 10. Phase 5c — Main full-L2 transition (§-1 PENDING)

> **§-1 PENDING — architect approval required before applying the ci.yml diff.**
> `.github/workflows/ci.yml`(CI=0 cutover, 2026-09-20로 삭제됨)은 AGENTS.md §-1 절대 불변 파일이다(당시 기준). 본 절의 diff는
> **준비(prepared) 상태로만 커밋**되며(아티팩트 `config/changes/ci-continuity-cutover.patch`),
> 적용은 아키텍트 명시 승인이 있을 때만, 본 문서의 전제조건 체크리스트(§10.3)와
> 아티팩트 재검증을 거쳐 수행한다.

### 10.1 적용 대상 ci.yml diff (정확 사양, 아티팩트 문헌)

아티팩트: `config/changes/ci-continuity-cutover.patch` — `git apply` 적용 준비 완료
(`git apply --check` 검증됨). 변경은 **5개 verify-\* job의 `if:` 가드 1행씩**뿐이며,
line은 추가/제거되지 않는다.

```yaml
# 5개 job (verify-static, verify-integration-r1, verify-integration-r2-unit,
#           verify-integration-r2-proof, verify-coverage-guard) 공통 — 1행 대체:
-    if: github.event_name != 'schedule'
+    if: github.event_name != 'schedule' && !(github.event_name == 'push' && github.ref == 'refs/heads/main')
```

- **효과**: main push 경로는 full L2 검증을 더 이상 수행하지 않는다. push:main의
  검증 책임은 (a) PR certification + trusted attestation(merge-boundary 권위 경로,
  Phase 4/5)과 (b) continuity verification — `merge_continuity.yml`은 이제
  workflow_call 전용 reusable component로서 **canonical-main.yml이 호스팅**(bind →
  verify → continuity → accept; ADR-0022 D10, post-merge verification authority
  단일화)하며, certificate continuity check + unexpected-push fail-visible을 담당한다.
- **계약 §4.4 정합**: I-1(정적 publication-scope 게이트)는 ci.yml 트리거 변경과
  독립적으로 유지된다(actuator 전용 main 전진 — 본 diff는 verify job만 제외).
- **nightly 불변**: `nightly` job(§7, schedule + `[run-nightly]`)는 **독립 backstop**으로
  그대로 full L2(verify-all + `ax prove` + trajectory 검증)를 유지 — diff에 포함되지 않는다.
- **pull_request/schedule/docs-\* 경로 불변**: PR certification 경로와 schedule은
  가드의 영향 밖이며, `docs/**` 브랜치 push도 기존 trigger 의미론을 유지한다.
- **되돌림**: 동일 가드 5행의 원상 회복(`git apply -R`)만으로 즉시 복구 가능 —
  단일 커밋/단일 아티팩트로 시행·철회 모두 저위험.
- `generate-docs`(main 전용, 문서 생성)와 `pr-coverage-comment`(PR 전용)는
  검증 job이 아니므로 변경 대상이 아니다.

### 10.2 Phase 6 deferred — GitHub App minter & 플랫폼 prevent (문서만)

> **2026-09-26 재개 승인 (ADR-0024 결정 #15 — release-boundary authority)**: 아래
> "GitHub App minter" 항목은 **재개 승인**되어 `axiom-release-authority` App
> (Contents:write 전용, 키=environment 스코프 시크릿)으로 구현된다 — 이연 사유였던
> 플랜 제약(§8.2, private+free org App 설치 불가)은 org `plan: enterprise` 실측
> (2026-09-26)으로 소멸했다. 대상은 release 출하 v* tag 생성이며, 발행 경로·실패
> 처리(FAIL/UNCERTAIN)·검증/확인 순서는 ADR-0024가 정의한다. 아래 minter 항목은
> 이 승인으로 대체되며, "플랫폼 prevent" 항목은 그대로 DEFERRED 유지(별도 승인).

- **GitHub App minter(우선순위 4) — DEFERRED**: 요구사항은 Actuator가 GitHub App
  identity(전용 서명·게시 키, install-scoped token)로 `ax merge publish`를 수행 —
  PAT/세션 토큰 비의존, 감사 가능한 publication 주체. 이연 사유: plan/App-identity
  제약(§8.2 plan — 사설+free org에서 App 설치·ruleset/environment 불가,
  App 인증 흐름은 플랜 상승한 org에서만 온전히 성립), 그리고 publication 경로가
  이미 cert 기반 안전장치(서명·원장·FF CAS)로 경계되므로 minter는 위험 감소가
  아니라 운영 편의·감사성 개선으로 등급됨. 재개 조건: 플랜 상승 확정 후 별도 승인.
- **플랫폼 prevent(우선순위 5) — DEFERRED**: 요구사항은 branch protection/rulesets로
  main 전진을 actuator 전용으로 차단(prevent) — 현재는 I-2/I-3 감지(fail-visible)로
  흡수 중. 이연 사유: §8.2 plan 제약("branch protection/rulesets/environments는
  private+free org 불가", pre-receive는 GHES 전용). 재개 조건: 동일 — 플랜 상승 후
  별도 승인.

### 10.3 전제조건 체크리스트 (CURRENT — 2026-09-10)

| # | 전제조건 | CURRENT |
|---|---|---|
| 1 | Phase 2–5b GREEN — 커밋: Phase 2 `137c11b91` · Phase 3 `00c8bb9d9` · Phase 3.5 `7c8cd303f` · Phase 3.75 `d1251b97f` · Phase 4 `99d8ec628` · Phase 5 `856a43b5b` · Phase 5b `461af2ae9` | **[x] GREEN** |
| 2 | ≥10 real merges via the new path(인증서 기반 admission + exact-object publication) | **[ ] 미충족** (실측 필요) |
| 3 | mixed PR types(단순/충돌/드롭 PR, base 이동 포함) 실운영 검증 | **[ ] 미충족** (실측 필요) |
| 4 | ≥1 base-movement re-certification(재materialize + 재attest 후 정상) | **[ ] 미충족** (실측 필요) |
| 5 | ≥1 intentional mismatch test(비정상 push → continuity FAIL fail-visible 확인) | **[ ] 미충족** (실측 필요) |
| 6 | nightly full L2 retained — `nightly` job 미변경(독립 backstop) | **[x] 충족** (diff에 미포함) |
| 7 | continuity failure runbook — §4.4 I-2(incident path) + §9 잔존 리스크 5 + `merge_continuity.yml` 헤더(fail-visible 의미론 문서화) | **[x] 충족** |
| 8 | unexpected-push detection — publication_scope(§-1 밖, 배포됨) + `push: main` trigger | **[x] 충족** |
| 9 | ledger reconcile — `ax cert ledger-list` + `ax cert reconcile` 경로 | **[x] 충족** |
| 10 | kernel/Z3 re-execution GREEN(Phase 3 `ax cert verify --kernel`) + Phase 6 leanchecker deep-check(부재 시 SKIP) | **[x] 충족** |

> #2–#5 미충족 항목은 cutover 시행 **전체 조건**이다 — 아키텍트 승인 요청 시 이표의
> 실측 상태를 갱신해 첨부한다(느슨한 서술 금지; 병합·push 이벤트 로그 기반).

### 10.4 계약 개정문 (approval 시 본문 반영)

- **기존**: "main CI = post-merge full certification"(push:main full L2가 merge
  결과를 재검증하는 이중 인증).
- **개정**: "PR certification + trusted attestation이 merge-boundary 인증의
  **권위 경로**이며(merge는 certified subject의 publication — §0/§4.1), main CI는
  **certificate continuity verification**(§4.4 I-2, cheap identity check)이고,
  nightly full L2는 **독립 backstop**으로 잔존한다."
- §2"증명하는 것" 불변, INV-1/INV-8/INV-10 불변 — cutover는 실행 중복 제거만이지
  인증 문장의 축소가 아니다.

### 10.5 subset extraction soundness — 종착형 로드맵 (감사 문서 §6)

CompCert 종착형: Nim-subset **operational semantics를 Lean 4로 정의**하고
(`proofs/IR/*` 확장 — `evalIR` 계열의 전면 의미론으로 승격), reference extractor의
함수별 **soundness 정리**(정의역 = certified subset, 정리 = AST denotation → IR
denotation 보존)를 kernel-checked로 증명, 잔존 TCB = pinned 앞단 parser(§3 1층,
"qualified" 지위 — CompCert §5 항목 2와 동형의 자인). 단계별 마일스톤과 진료는
`docs/audit/reference_extractor_audit_2026-09-10.md` §6.

- **Phase 6 구현 현황 요약**: ① audit record DONE · ② 로드맵 DONE · ③ leanchecker
  deep-check DONE(`src/verification/kernel_reexecution.nim` `checkLeanWithLeanChecker` —
  elan 제공 `leanchecker` 존재 시 fresh-compile .olean 재검증, 부재 시 loud SKIP,
  불일치/행 fail-closed; `ax cert verify --kernel`·`ax merge publish` 배선; 테스트 P10) ·
  ④ GitHub App minter — 재개 승인(§10.2, ADR-0024) · ⑤ 플랫폼 prevent DEFERRED(§10.2).

### 10.6 계약 개정문 — CAS 랜딩 & 커스텀 TCB 최종 목록 (Owner 결정 #11, 2026-09-24)

Owner 결정([`repository_surface_contract.md`](repository_surface_contract.md) §Owner
결정 기록 #11)으로 merge queue가 소거되고, 단일 **Landing App**이 기계적 수용
술어를 실행해 GitHub merge-tree → CreateCommit([B,H], tree) → `updateRefs` CAS로
착지한다. 본 절은 그 계약 개정을 확정한다(§10.4 개정문 스타일에 따름). §2
"증명하는 것" 불변, INV-1/INV-8/INV-10/INV-12 불변 — 본 개정은 착지 메커니즘
서술만 변경하며 인증 문장을 축소하지 않는다. **2026-09-29 (ADR-0027)**: 'merge
queue 소거' 전제는 supersede — GitHub Merge Queue = **채택된 위임 대상**(커스텀
queue/orchestrator 금지는 유지). 아래 개정문 중 queue 소거 전제 문구는 ADR-0027이
대체하며, CAS 착지·continuity 경로와의 정확한 결합은 ADR-0027 + Phase 0 측정이
확정한다.

- **§8.2 `:274` 주석 supersede** — "merge result 보장은 merge queue 외 불가"는
  **CAS 랜딩 경로로 대체**된다: 착지된 merge result는 GitHub-returned merge
  tree(GitHub merge 의미론 산출, §10.6 merge 의미론 TCB 수용) + `updateRefs`
  beforeOid CAS가 보장하며, merge queue 자체는 소거 대상이었다(2026-09-24 시점
  판정). **ADR-0027 (2026-09-29) supersede**: GitHub Merge Queue = **채택된 위임
  대상**(후보 인증 경로; 커스텀 queue/orchestrator 재도입 금지는 유지). 착지된 merge
  tree에 대한 **nightly full-L2는 backstop으로 잔존**한다.
- **신뢰 경계 공지** — 실제 보안 경계는 **`certificate → Landing App →
  updateRefs`**이다. required checks·CODEOWNERS·PR review는 보조 관측/UX일 뿐
  보안 경계가 아니며, 유일한 통제 장치는 **ruleset(Restrict updates + Landing
  App bypass)**이다.
- **merge 의미론 TCB 수용** — **MUST**: 결과 tree == GitHub-returned merge 계산
  결과. **MUST NOT**: 자체 merge 알고리즘으로 재계산하거나 merge 의미론을
  (재)정의하지 않는다.
- **커스텀 TCB 최종 목록** — **Axiom**: Certificate / MergeAdmissible; Landing
  App(certificate 검증 → GitHub merge-tree 요청 → CreateCommit([B,H], tree) →
  `updateRefs`). **GitHub**: runner, merge semantics, Git object store, atomic ref
  CAS, ruleset enforcement.
- **Landing App 성격** — "판단 0"이 아니다: 이미 정의된 **기계적 수용 술어
  (mechanical admission predicate)**를 실행할 뿐 MergeAdmissible의 의미를
  재정의하지 않는다. 각 단계(cert 서명 검사, (B,H) 바인딩, branch 비교,
  tree/parent 형태)는 각각 보안 관련 판정이며, 실패 = 착지 없음.
- **CreateCommit = 정당한 최소 커스텀 층** — merge 재구현이 아니다: GitHub
  merge 의미론이 tree를 소유하고, Axiom은 저수준 Create a commit API로 최종
  Git 객체([B,H] + returned tree)만 조립한다. `POST /merges`는 `head`를 커밋
  SHA로도 수용한다 — 브랜치 ref만이 아니다.

## 11. Git merge-tree 버전·구성 핀 (Git Version & Merge-Config Pin)

> **Status**: RATIFIED 2026-10-12 — closure-candidate-delta workstream 선결 ①.
> §7 Phase 1 행(`:291` "merge-tree ≥2.40 + commit-tree, git 버전 고정")의 구체
> 핀 값을 선언하고, merge admission 분류식
> `closureChange = (derived(M) != derived(B))`, `M := git merge-tree --write-tree B H`
> (도입 예정 — 본 절은 그 **재현 조건 선행 계약**이다)의 실행 전제를 고정한다.

### 11.0 두 방어의 구분 (HARD)

| 층 | 기제 | 지위 |
|---|---|---|
| 1차 방어 (런타임) | `derived(M) == MERGE_TREE_OID(=tree(G))` 등식 대조 — `MERGE_TREE_OID`는 `tree(github.sha)` 객체 해석(admission-check.yml:1291) | **tree identity의 유일 권위 판정**. 불일치 · exit 1(충돌 — INV-11) · exit ≥2(오류) → **UNSPECIFIED fail-closed** |
| 2차 조건 (재현 보장) | 본 절의 버전·구성 핀 | **재현 조건 보장 수단** — 핀은 tree identity를 증명하지 않는다. 하한 미충족 환경의 `derived(M)`은 판정 입력으로 불인정 |

merge-tree 출력은 git 버전·merge 구성·속성(merge driver)에 의존할 수 있으므로,
환경 간 재현 조건을 핀이 고정하고, 고정에도 불구하고 실제 결과가 달라진 경우는
1차 방어 등식이 흡수한다(UNSPECIFIED). **핀 위반을 등식 대조로, 등식 불일치를
핀으로 설명하는 치환은 금지** — 두 근거는 독립이며, 대조는 fail-closed이고 핀은
재현 조건이다.

### 11.1 버전 핀 값

| 항목 | 값 | 근거 |
|---|---|---|
| **기능 하한 (HARD floor)** | `git >= 2.40.0` | `--write-tree` 모드는 v2.38 도입, `--merge-base`는 v2.40 도입(RelNotes 2.38.0/2.40.0 원문 — §8.1 `:314` 기존 기록과 일치). §7 `:291` "merge-tree ≥2.40"의 출처. 역사 chain materializer 모듈의 `MinimumGitVersion = "2.40.0"`(커밋 47c3bea8f 당시 인프라 계층 위치, 51행 — Verdict B 전환 35665483a로 모듈 삭제됨)과 동일값 |
| **재현 기준 버전 (reference)** | `2.43.0` | 실측: 개발 환경 git 2.43.0(2026-10-12 measured) — §11.2의 기계 관측 전체가 이 버전에서 수행됨. 역사 materializer quirk 기록("git 2.43 merge-tree --merge-base requires a commit oid", 47c3bea8f)의 측정 환경이기도 함 |
| **상한** | 고정하지 않음 | 아래 기각 근거 |

- **동등성 핀(`== 2.43.0`) 기각**: GitHub-hosted runner 이미지의 git은 이미지 롤에
  따라 부유한다(2026-10-12 실측 — actions/runner-images main의 Ubuntu2404-Readme가
  Git 2.55.0을 기재; noble apt 기본 2.43.0을 이미지 구성이 이미 상회).
  `==` 핀은 전 CI 런을 상시 실패시키는 사문 강제(theater)가 되고, cross-version
  tree OID 안정성을 실제로 보장하지 못하므로(정보 메시지는 공식 문서 명시상
  "may change in future Git versions") 가용성만 파괴한다.
- **상한 미고정의 위험 흡수**: merge 기계는 진화한다(RelNotes 실측 — 2.38
  directory-rename 코너 수정, 2.43 `-X` 옵션, 2.45 3-way tree 입력 확장 등). 이로
  인한 `derived(M)` 발산 가능성의 방어는 §11.0 1차 방어 등식이지 핀이 아니다 —
  핀은 환경 간 재현 조건을 좁히는 역할만 한다.
- **2.41 체계 경계**: v2.41에서 merge-tree가 기본 구성을 읽기 시작했다(RelNotes
  2.41.0, b6551feadf). 하한 2.40은 2.40.x를 허용하나, 본 저장소는 replace ref
  부재 + merge.* 구성 무정의(§11.2 실측)라 2.40.x–2.41+ 간 발산 입력이 없다.
  그래도 재현 기준은 실측 환경인 2.43.0으로 둔다.

### 11.2 merge 구성·속성 표면 (machine-observed, git 2.43.0)

| 입력 | merge-tree에의 영향 | 실측/근거 |
|---|---|---|
| `merge.renames` / `merge.directoryRenames` / `merge.renormalize` | git-merge-tree(1)이 읽는 merge.* 구성 | 역사 MergeConfigPin = `[merge.renames=true, merge.directoryRenames=true, merge.renormalize=false]`(47c3bea8f 원문 — "Pinned per invocation so the constructed tree depends only on declared inputs + this pin set") |
| `merge.conflictStyle` | **충돌 트리 OID 변경** — 충돌 마커 내용이 결과 트리 blob에 새겨짐 | 실증(2026-10-12, git 2.43.0): 동일 충돌 입력에서 default `27ac2c86…` → zdiff3 `26f13e32…`. 충돌은 INV-11 fail-closed라 인증 입력이 아니므로 발산은 1차 방어로 흡수 |
| `.gitattributes` merge driver | **외부 merge driver를 실행한다** — driver 성공 시 clean 귀결(실증: driver `true` → exit 0, %A 내용 채택), driver 정의 부재는 **exit 128 fatal**("custom merge driver X lacks command line") | 실증 2026-10-12, git 2.43.0. 본 저장소 LFS 경로(`.gitattributes:10-13` `*.pdf/*.so/*.bin/*.png`에 `merge=lfs`)에서 충돌이 나면 실행 환경에 git-lfs의 `merge.lfs.driver`가 없는 경우 fail-closed 종료(침묵 오염 아님). CI 이미지는 Git LFS 포함(2026-10-12 실측 3.8.0) |
| eol / working-tree-encoding | merge 입력은 object store의 blob 내용 — `* text=auto eol=lf` + `working-tree-encoding=UTF-8`(`.gitattributes:1-6`)는 identity(UTF-8) 변환이라 merge-tree 결과 불변 | renormalize=false(기본 + 역사 핀)에서 병합 중 재정규화 없음 — `merge.renormalize=true` 전환은 GVP-2 위반 |
| 저장소 로컬 구성 | merge.*·replace.* 재정의 없음(hooksPath=.githooks만) — 기본값이 곧 핀 | 실측 2026-10-12 `.git/config` |
| replace refs | 부재(실측) — 2.41 구성 체계 경계의 발산 입력 없음 | 실측 2026-10-12 `git replace -l` |

### 11.3 불변식 (HARD RULES)

| ID | 불변식 | 위반 시 |
|---|---|---|
| GVP-1 | merge-tree 실행 환경은 `git >= 2.40.0`을 만족해야 한다 — 미충족 환경의 `derived(M)`은 판정 입력으로 불인정 | fail-closed(재현 조건 부재) |
| GVP-2 | merge 구성 유효값은 역사 MergeConfigPin과 동일해야 한다 — `merge.renames=true`, `merge.directoryRenames=true`, `merge.renormalize=false`(명시 구성 또는 기본값 일치) | `merge.renormalize=true` 전환 = derived(B)/derived(M) 무효화 → fail-closed |
| GVP-3 | 1차 방어 등식 `derived(M) == tree(G)`의 불일치 · merge-tree exit 1(충돌, INV-11) · exit ≥2(오류 — driver 부재 128 실증 포함) · 출력 파싱 불가 → UNSPECIFIED — 정상 간주 금지 | fail-closed |
| GVP-4 | 버전·구성 단언은 재현 조건이지 tree identity의 증거가 아니다 — identity 권위는 1차 방어 등식 대조에만 있다 | 권위 치환 = 계약 위반 |

### 11.4 강제선 현황 (measured 2026-10-12)

- `Makefile:247` — `git --version | grep -E 'git version 2\.(4[0-9]|[5-9][0-9])\.'`
  (≥2.40 floor). `check-determinism`(:243)이 GATES_FAST(:37)·
  PUSH_ADMISSIBILITY_GATES(:61)에 배선 — GVP-1의 현행 강제선. **주의**: 직전 행
  주석(:246)은 삭제된 모듈을 참조한다("mirrors assertGitCapability in
  merge_materializer.nim" — Verdict B 35665483a에서 삭제됨). Makefile은
  repository_surface v51 FROZEN이므로 본 개정에서 수정하지 않는다 — GVP 계약의
  정본은 본 절이며, 주석 정리는 소비 PR에서의 재승인 follow-up이다.
- CI: setup-axiom-toolchain 액션은 nim 2.2.10/lean 4.33.0/z3 4.13.3/jq 1.7.1만
  핀하고 git은 핀하지 않는다(action.yml:874-890 "Verify toolchain pins" — git
  부재; 액션 자체는 `git rev-parse`/`git archive`를 사용, action.yml:244/:248/:611).
  runner의 git은 이미지 암묵값이다 — GVP-1 하한은 Makefile 강제선 + 로컬 게이트가
  담당하고, CI 이미지 git의 부유는 §11.0 1차 방어 등식이 흡수한다.
