# Bug Verdict Glossary — BUG_FOUND / NO_BUG_PROVED 운영 판정 용어

> **Status**: Committed terminology contract — S0 of the nim-stew `BUG_FOUND`/`NO_BUG_PROVED` 운영 판정 milestone (contract slice S0–S3)
> **Created**: 2026-10-08
> **Revised**: 2026-10-10 — §2.4 귀속 라벨 `BUG_SUSPECTED` 추가 (SPEC-B36-COUT slice S0 — 판정 값 아님, enum·producer·gate·required check 추가 없음)
> **Revised**: 2026-10-10(b) — 2축 표시 어휘: §2.2 공용 4요소 단일 정의 · §2.4 RULE/귀속 축 분리 + 승격 목표 **Bug Confirmed** 개칭 · §2.4a–§2.4c 신설 (표시 라벨 전용 — enum·producer·gate·required check 추가 없음)
> **Revised**: 2026-10-11 — §2.4d 스코프·표시 결속 규칙 신설 (주체-스코프 판정 투영 — 표시 라벨 전용, enum·producer·gate·required check 추가 없음)
> **Revised**: 2026-10-31 — 2차 판정 모델: §2.2 정준 발견 모델 4필드 + 판정표 신설 · 기계 별칭 `BUG_FOUND` 은퇴 → 기계 출력 용어 `PROPOSITION_DISPROVED` · `BUG_FOUND` = DISPROVED ∧ recordedBinding 전용 귀속 값 재정의 · §2.4a E1 필요근거 + E2/E3 비충분·비소급 · §2.4c `requirementSourceStatus` 제4값 `unknown` · §1 귀속 상태 = 보고 입력 상태 (upstream reporter 전용 소비 — 게이트·enum·required check 금지 불변)
> **Revised**: 2026-11-01 — §2.2 운영 관측 지점 노트 신설 (vrFail = machineTuple run verdict `$`-철자 관측 · icCounterexample = ce-replay 반례 quartet 라인 관측 + `findingEvidence` 정본 증거 영속 · NOT_DISPROVED = vdVerified 미직렬화로 표시 계층 미관측 → fail-closed UNKNOWN · rowStatus 폴백 금지 — 기존 값 소비 정합일 뿐, enum·producer·gate·required check 추가 없음)
> **Revised**: 2026-11-03 — BYO-Agent Phase 5.1: §2.2 명제 capability 축 노트 신설 (`CAPABLE`/`INCAPABLE` + 사유 폐쇄 집합 — intake/dispatch가 결정한 사실이지 gate-consumed verdict가 아님; `display.propositions[]` rollup 투영; `propositionVerdict` 3-value 무변경, enum·producer·gate·required check 추가 없음 — [byo_agent_proposition_contract.md](./byo_agent_proposition_contract.md) §3)
> **AGENTS.md 참조**: §0.5 (문서 우선), §0.11 (어휘), §0.9 (극장 금지), §0.12 (제품 계약 선행), §2.4 (자격 증명 권한 — upstream 보고 경로)
> **Related**: [authority_contract.md](./authority_contract.md) §2, [uap_logic.md](./uap_logic.md), [base36_sizing_binding_contract.md](./base36_sizing_binding_contract.md), [nim_stew_base36_cout_contract.md](./nim_stew_base36_cout_contract.md), [counterexample_replay_adapter.md](./counterexample_replay_adapter.md) (S4-S5 구현 계약), [upstream_reporting_contract.md](./upstream_reporting_contract.md) (보고 계약 — findingKey·legacyFingerprints — v2 정체성 모델 개정 참조)
> **Projection record**: [bug_verdict_contract_slice_2026-10-08.md](../evidence/bug_verdict_contract_slice_2026-10-08.md) — S1 subject 바인딩 실측 · S2 property 결정(P2 비채택) · S3 semantic 충분성 노트

---

## 1. 성격 — 판정 값 생성 금지 + 귀속 상태는 보고 입력 상태 (HARD RULE)

`NO_BUG_PROVED`(§2.1)는 기존 verdict 어휘 위의 **읽기 전용 별칭(projection alias)**으로 유지된다. `BUG_FOUND`의 **기계 별칭 지위는 2026-10-31 개정으로 은퇴**했다 — 기계 반증 출력 용어는 `PROPOSITION_DISPROVED`(§2.2)이며, `BUG_FOUND`는 이제 정준 발견 모델(canonical finding model)의 귀속 값이다(§2.2).

- **신규 enum 금지** — `RunVerdict`(`src/verification/accounting/run_accounting.nim:85-94`), `VerificationDecision`(`src/verification/obligation/verification_decision_authority.nim:64`), `VerificationOutcomeRef`(`src/core/trusted/assurance_profile.nim:14-21`), `InputClassification`(`src/core/trusted/claim_authority.nim:28-35`) 외에 판정 값을 도입하지 않는다. 정준 발견 모델의 4필드(`propositionVerdict` · `requirementSourceStatus` · `bugAttribution` · `reportStatus`)는 이 enum들에 어떤 값도 추가하지 않는다 — 보고 계층의 필드다(§2.2).
- **신규 producer 금지** — `vr*` 어휘는 VDA 전용 guarded 생산이다(`evidence_truth_boundary_gate.nim:31-37` [T4-a]/[T4-b]; `authority_contract.md` §2 80-88행 — 어휘 전체가 보호되며 value-producing 발생의 authority 모듈 밖 출현은 위반). `vdVerified`는 `evaluate`/`makeVerifiedDecision` 단일 경로(`verification_decision_authority.nim:69-119`), `cl*` outcome은 `deriveClaim` 단일 경로(`claim_authority.nim:85-135`)다. 기계 사실(`propositionVerdict`)은 이 값들의 **소비(projection)만**이고, `bugAttribution`은 §2.2 판정표에 따른 귀속 분류기(attribution classifier)만이 산출한다 — 어느 쪽도 기계 verdict enum 값을 생산하는 코드 경로를 추가하지 않는다.
- **신규 required check 금지 + 보고 입력 상태 소비 경계 (2026-10-31 재선언)** — 별칭·귀속 상태 정의는 CI·게이트 표면을 만들지 않는다(§0.12: 계약 없는 표면 확장 금지). 귀속 상태(`BUG_FOUND`/`BUG_SUSPECTED`/귀속 Unknown)와 `reportStatus`는 **보고 입력 상태(report-input states)**다 — 소비자는 upstream reporter(`ax report --upstream`, [upstream_reporting_contract.md](./upstream_reporting_contract.md)) **하나뿐**이다. **게이트·CI required check·기계 verdict enum은 이들을 소비하지 않는다** — 2026-10-10(b) 이래 "표시 라벨 전용" 금지는 소비자를 reporter로 한정하면서 그대로 유지된다(표시 계층 규율 §2.4d 포함).

근거: verdict authority는 모듈 고정이며, 측정 권위 없는 값 생성은 금지·fail-closed다(`authority_contract.md` §2, §5 정리 방향 3번 — "판정·저장 경로의 모든 수치·digest는 측정된 것", `authority_contract.md:167-169`).

## 2. 정의

### 2.1 NO_BUG_PROVED

**주어진 property `P`와 domain `D`에 대해**:

```
NO_BUG_PROVED(P, D)  :=  vrPass ∧ vdVerified ∧ clProved
```

- 세 conjunct는 서로 다른 계층의 **기존 어휘 실측 값**이다: run-level `vrPass`(VDA 전용, `run_accounting.nim:94`), artifact-level `vdVerified`(KAA + 정책 충족, `verification_decision_authority.nim:64`), claim-level `clProved`(solver psUnsat → 증명, `assurance_profile.nim:15`, `claim_authority.nim:105-106`).
- **범위 한정 필수**: `NO_BUG_PROVED` 주장은 반드시 (P, D)를 명명해야 한다. P·D 없는 "NO_BUG_PROVED"는 전체주장 허언이며 금지된다(external verification workspace AGENTS.md §7 scope discipline, §15 claims discipline — "Axiom verified the selected slice" 이상의 주장 금지).
- `vrPass` 단독으로는 부족하다 — `vrPass`의 basis는 PROVEN / NO_OBLIGATION / REUSED다(`run_accounting.nim:96-101`), NO_OBLIGATION·REUSED는 반례 부재가 아니라 정의상 proof가 아니다. proof-level PASS(rbProven)와 artifact 증명(vdVerified), claim 증명(clProved)의 논리곱만이 "증명됨"의 운영 의미다.

### 2.2 PROPOSITION_DISPROVED + 정준 발견 모델 (canonical finding model — 2026-10-31 개정)

**기계 별칭 은퇴 (HARD RULE)**: 구 어휘 `BUG_FOUND`의 기계 별칭 의미 —

```
vrFail ∧ clDisproved ∧ classified(icCounterexample)
```

— 는 **`PROPOSITION_DISPROVED`로 명칭 변경**되며, 모든 기계 출력(stderr·JSON·문서)에서 이 이름으로 진술된다. 기계 수준 반증 상태를 `BUG_FOUND`로 내보내는 출력·문서는 본 개정 위반이다(구 의미는 은퇴 — 역사 인용 전용).

- 투영 근거는 기존 어휘 그대로다: `vrFail`은 run-level "proof-level failure only (counterexample/UNSATISFIED after attempt)"다(`run_accounting.nim:92`). `clDisproved`는 claim-level "solver disproved the property"다(`assurance_profile.nim:16`; 유도 경로 `deriveClaim`의 `psCounterexample → clDisproved`, `claim_authority.nim:107-108`). `icCounterexample`은 반례 구체값을 동반한 반증 분류다(`InputClassification`, `claim_authority.nim:34`) — 반례 입력이 구조화 기록(`UniversalPipelineResult.initialScan/finalScan[*].counterExampleInput`, `uap_logic.md` 파이프라인 계약)으로 포착되었음을 진술하는 **보고 요건**이다.
- `PROPOSITION_DISPROVED`는 새 판정 값이 아니다 — §1 HARD RULE(신규 enum·producer·gate·required check 금지)이 그대로 적용되는 **기존 guarded 값의 읽기 전용 명칭**이다.

**정준 발견 모델 — 서로 독립인 네 가지 사실**:

| 필드 | 값 집합 | 축 |
|---|---|---|
| `propositionVerdict` | `DISPROVED \| NOT_DISPROVED \| UNKNOWN` | 기계 명제 판정 |
| `requirementSourceStatus` | `recordedBinding \| recordedDisclaiming \| unrecorded \| unknown` | 주체 저장소의 요구 기록 상태 (§2.4c) |
| `bugAttribution` | `BUG_FOUND \| BUG_SUSPECTED \| UNKNOWN` | 최종 귀속 — 보고 입력 상태(§1) |
| `reportStatus` | `READY \| SUBMITTED \| DUPLICATE \| BLOCKED \| FAILED \| RECONCILIATION_REQUIRED` | upstream 보고 상태 ([upstream_reporting_contract.md](./upstream_reporting_contract.md)) |

- `propositionVerdict`는 기존 기계 값의 순수 투영이다: `DISPROVED` ← 상단의 구성(구 §2.2 별칭식); `NOT_DISPROVED` ← §2.1 NO_BUG_PROVED 성립; `UNKNOWN` ← §2.3 나머지 전 상태(fail-closed). 어떤 값도 새로 생산하지 않는다.
- **명제 capability 축 — 판정 축이 아니다 (2026-11-03, BYO-Agent Phase 5.1)**: BYO 명제([byo_agent_proposition_contract.md](./byo_agent_proposition_contract.md) §3)는 위 4필드에 **추가되는 축이 아닌, 별도의 두 축 사실**을 운반한다 — **capability 축**(`CAPABLE | INCAPABLE` + INCAPABLE 사유 폐쇄 집합 `UNKNOWN_SPEC`/`UNSUPPORTED_LOGIC`/`LANE_NOT_EQUIPPED`)과 **verification 축**(`attempted` + `verdict`). 이는 intake/dispatch가 결정한 **사실(fact)**이지 gate-consumed verdict가 아니다 — `propositionVerdict`의 3-value는 **무변경**이며 `INCAPABLE`은 새 판정 값이 아니다(§1 HARD RULE 유지 — capability 사실을 생산하는 intake 사유 철자는 판정 값 enum이 아니다). 투영 지점은 report `display.propositions[]` rollup(스키마 `proposition-rollup-v1`)이다: `attempted=false`(INCAPABLE) 항목의 `verdict`는 JSON null이며, **이 항목들은 아래 판정표의 입력이 아니다** — 검증이 수행되지 않았으므로 귀속 경로에 아예 진입하지 않는다. INCAPABLE은 주체에 대한 판정이 아니라 명제가 이 엔진 버전에서 검증 가능하지 않았다는 기록이다(byo_agent_proposition_contract.md §13).

**판정표 (verdict table — HARD RULE)**: `bugAttribution`은 이 표의 순수 함수다:

| `propositionVerdict` | `requirementSourceStatus` | `bugAttribution` |
|---|---|---|
| `DISPROVED` | `recordedBinding` | **`BUG_FOUND`** |
| `DISPROVED` | `recordedDisclaiming` | **`BUG_SUSPECTED`** — A-essentials(§2.4b) 충족 시; 미충족 시 `UNKNOWN` |
| `DISPROVED` | `unrecorded` | **`BUG_SUSPECTED`** — A-essentials 충족 시; 미충족 시 `UNKNOWN` |
| `DISPROVED` | `unknown` | `BUG_SUSPECTED` ∨ `UNKNOWN` — 추론 근거 + 출처 대응 증거로 결정 |
| `NOT_DISPROVED` | (전 상태) | `UNKNOWN` — 결함 미성립. **보고하지 않는다** |
| `UNKNOWN` | (전 상태) | `UNKNOWN` — fail-closed. **보고하지 않는다** |

- **`BUG_FOUND` 재정의**: `BUG_FOUND`는 이제 **오직** "주체 저장소가 명시적으로 채택한 요구(`recordedBinding`)를 위반하는 반증된 명제"만을 뜻한다. 구 기계 별칭 의미는 은퇴했다(본 절 서두).
- **A-essentials 조건**: `BUG_SUSPECTED` 행의 충족 조건은 §2.4b의 A 필수 조건 — 공용 4요소 + 독립 기대 출처(②) + 대조(③) + 역할 독립(④) — 다. 하나라도 결측이면 `BUG_SUSPECTED`가 아니라 `UNKNOWN`이다.
- **공용 4요소는 보고 전제다**: 4요소는 귀속 판정의 입력이 아니라 **보고(report)의 요건**이다 — 결측 시 어느 귀속이든 `reportStatus`는 `READY`가 될 수 없다(upstream_reporting_contract.md §11).

**공용 4요소 기록 (shared quartet) — 보고 주장의 네 가지 필수 기록** (fail-closed — 하나라도 결측이면 보고할 수 없다). 이 4요소는 **단일 정의**로서 §2.2(판정표의 보고 전제), §2.4a(C의 재현 요건), §2.4b(A의 필수 조건) 세 목록이 모두 참조한다 — A의 ①~④ = C의 재현 요소 = 이 목록이며, 어느 목록도 사본 정의를 만들지 않는다:
  1. **exact subject commit(+blob)** — 주체 저장소의 정확한 커밋 해시 + 대상 모듈 blob 해시(버전 라벨 불충분)
  2. **exact input** — 반례를 재현하는 정확한 입력(값·파라미터 전체)
  3. **위반/모순 서술** — 어느 property `P`(또는 요구 사항)의 어느 conjunct가 어느 domain `D`에서 위반되는가
  4. **reproduction 기록** — 관측 출력 + 재생 명령 + toolchain/host 폴드(동일 커밋 + 동일 입력 재생)

**운영 관측 지점 (operational observation points — 2026-11-01)**: 구성식 `vrFail ∧ clDisproved ∧ classified(icCounterexample)`의 세 conjunct는 표시·영속 계층에서 다음 지점으로 **관측**된다 — 기존 직렬화 값의 소비일 뿐이며 신규 enum·producer·gate·required check는 없다(§1):

- **vrFail** — machineTuple의 run verdict `$`-직렬화 철자 `"FAIL"`(`run_accounting.nim:92`; 라이브 bytesview 런 실측). `vs*`·`rv*` 등 corroboration 참조 철자는 이 conjunct의 관측 지점이 아니다.
- **clDisproved** — 유닛 unitEvidence의 `claimOutcome`(`deriveClaim` 단일 경로 산출값의 소비, §1).
- **classified(icCounterexample)의 구조화 기록** — ce-replay 반례 quartet 라인(① `replay.subjectGitRef=`/`replay.moduleSha256=`/`replay.treeMerkle=` ② `input.*` ③ `propertyViolated=` ④ `replay.*` — 유닛 unitEvidence `counterExample` 배열)이 이 분류의 구조화 기록 관측 지점이다. 원본 라인들은 상태 문서 **루트 `findingEvidence` 블록**(`counterExample` 멤버)에 **정본 증거로 영속**되며, 소비자는 upstream reporter([upstream_reporting_contract.md](./upstream_reporting_contract.md))다 — 표시 계층 유닛 키가 아니다(§1 보고 입력 상태 경계).
- **NOT_DISPROVED는 표시 계층에서 관측 불가 (fail-closed)** — §2.1의 `vdVerified`가 wave/runResult/unitEvidence 어디에도 직렬화되지 않아(직렬화 갭 — follow-up), `clProved`는 어떤 조합으로도 NOT_DISPROVED에 도달할 수 없다. 표시 계층은 비논리곱 입력 전부를 `UNKNOWN`으로 투영하며, NOT_DISPROVED는 미관측 상태로 남는다. 명제 rollup(`display.propositions[].verification.verdict` — 2026-11-03)도 동일 투영을 따른다 — 관측 가능한 verdict는 `DISPROVED` 또는 `UNKNOWN`뿐이고, 미수행(`attempted=false`) 항목은 null이다.
- **rowStatus 폴백 금지 (HARD RULE)** — `rowStatus`는 §2.4d RULE축 전용 전제다. rowStatus와 이 구성식 conjunct의 동등성은 양방향으로 불성립이므로, 어떤 conjunct도 rowStatus로 대용하지 않는다.

### 2.3 나머지 전 상태 — fail-closed 유지 (HARD RULE)

`vrInconclusive` · `vrBlocked` · `clUnknown` · `clUnsupported` · `clNoSpecification` · `clInvalidEvidence` · `clDependencyBlocked` · `icInconclusive` 등 나머지 전 상태는 **`NO_BUG_PROVED`도 `BUG_FOUND`도 아니다**. 기존 fail-closed 의미가 그대로 유지되며, 별칭은 이들을 어떤 긍정 상태로도 접지 않는다(external verification workspace AGENTS.md §5 — 기존 카테고리의 보고 편의 붕괴 금지).

> **2026-10-31 개정**: 구 `BUG_FOUND` 기계 별칭 자리는 `PROPOSITION_DISPROVED`(§2.2)다 — 나머지 전 상태는 `propositionVerdict = UNKNOWN`으로 투영되며 fail-closed 의미는 불변이다.

### 2.4 귀속 축 — BUG_SUSPECTED / Bug Suspected (attribution label — 판정 값 아님)

`BUG_SUSPECTED`는 **판정 값이 아니다**. upstream 귀속을 표기하는 **읽기 전용 문서 라벨**(attribution label)이다 — `RunVerdict`/`VerificationDecision`/`VerificationOutcomeRef`/`InputClassification`의 어떤 값에도 대응하지 않으며, §2.3의 fail-closed 분리를 무너뜨리지 않는다.

- **2축 표시 어휘 (display vocabulary)**: RULE 판정과 BUG 귀속을 분리한다 —
  - RULE 축: **"Axiom-Defined Rule Violated"** (정밀도 규칙은 아래);
  - 귀속 축: **"Bug Confirmed"** / **"Bug Suspected"** / 귀속 **Unknown**.
  이들은 **표시 라벨**이지 절대 기계 enum 값이 아니다(§1 HARD RULE).
- **RULE 축 정밀도 규칙 (HARD RULE)**: "Axiom-Defined Rule Violated" 표시는 `vrFail ∧ clDisproved ∧ 공용 4요소 기록(§2.2)` **그리고** `claimOwnership.owner == "axiom-defined-rule"`을 요구한다 — `vrFail` 단독으로는 결코 충분하지 않다.
- **Unknown의 3중 스코프 분리**: ① 귀속 Unknown(§2.4b 우선순위 3번 — 표시 계층의 귀속 상태) ② 기계 `clUnknown`(`claim_authority.nim` — claim-level 불확실 판정 값) ③ 채택 전 Unknown(계약 미채택 지식 상태). 셋은 이름만 같고 계층이 다르며, 상호 치환은 금지된다.
- **표기 위치**: 지식 상태 표의 행 라벨 + 보고서 귀속 단락 전용. 기계 상태는 항상 병기한다(예: "Bug Suspected (기계상태: clDisproved(C_out) — 계약 계층 판정은 성립, upstream 귀속은 미확정)").
- **신규 enum·producer·gate·required check 금지**: §1의 HARD RULE가 그대로 적용된다. `BUG_SUSPECTED`는 어떤 코드 경로도 생산하지 않으며, 승격·강등 판정기도 없다.
- **의미**: A 유효(§2.4b 필수 조건 충족)이나 §2.4a의 필요충분 확정 근거는 미입증이라는 귀속 표기다. 우선순위 규칙(§2.4b)은 **rule-linked 경로에만 스코프된다** — 계약 계층 기계 기록(M)의 선행은 이 경로의 전제일 뿐, 전역 요건이 아니다(§2.4a 경로 제약).
- **승격 (fail-closed — 기본 불승격)**: 승격 목표는 **Bug Confirmed**다(구칭 `BUG_FOUND(upstream)` — 본 개정으로 폐기된 명칭). §2.4a의 (a)/(b)가 입증될 때만 승격하며, 그 근거 ①은 "약속 **위반**"이다 — "충돌"이 아니다("estimated" 같은 면책 문구는 결코 E1이 될 수 없다). 승격은 귀속 라벨 갱신이며, 새 판정 값을 만들지 않는다.

> **2026-10-31 개정 (supersession note)**: 귀속 축은 정준 발견 모델의 `bugAttribution ∈ {BUG_FOUND, BUG_SUSPECTED, UNKNOWN}` 필드(§2.2)로 흡수되었다 — 구칭 **"Bug Confirmed" 표시명은 `bugAttribution = BUG_FOUND`에 대응**하며, "표시 라벨 전용" 지위는 **보고 입력 상태**(report-input states — upstream reporter 전용 소비, §1)로 갱신된다. 위 구문 중 "표시 라벨", 승격 목표 "Bug Confirmed", (a)/(b) 필요충분 확정 근거는 본 개정으로 대체된 역사 기록으로 남는다 — 승격 규칙의 현행 정의는 §2.4a(E1 필요근거 + 비소급)이고, 어느 경우에도 게이트·required check·기계 enum 소비 금지는 불변이다.

근거 선례: debt universe의 quirk 귀속 3분법(`UPSTREAM_CONFIRMED | PROJECT_LOCAL | UNVERIFIED/HISTORICAL`, `debt_universe_audit.md`)은 라벨이지 판정 값이 아니었다. 같은 계층 구분을 bug-verbatim 보고에 적용한다.

### 2.4a BUG_FOUND의 근거 구조 — E1 필요근거 · E2/E3 비충분 · 비소급 (2026-10-31 개정)

> **2026-10-31 개정**: 구칭 "Bug Confirmed"의 필요충분 정의 — (a) pinned 주체에 적용 가능한 권위 있는 요구 사항의 입증된 위반, 또는 (b) 기록된 출처의 기준선(recorded-source baseline)에 대한 입증된 기능 결함 — 는 본 개정으로 **대체**된다. 구문은 역사 기록으로 남는다; 현행 규칙은 아래와 같다. 귀속 확정은 여전히 **{A, C}에 대해서만 정의되는 순수 함수**이며, M(계약 계층 기계 기록)은 입력이 아니라 보강이다.

- **E1 — 유일한 필요근거 (necessary ground)**: `bugAttribution = BUG_FOUND`(§2.2 판정표 — `DISPROVED ∧ recordedBinding`)는 **E1 — pinned 주체에 적용 가능한 명시 텍스트 약속의 위반(NOT "충돌")** — 을 요구한다. "estimated" 같은 면책 문구는 결코 E1이 될 수 없다. `requirementSourceStatus = recordedBinding` 없이는 어떤 근거 조합도 BUG_FOUND에 도달하지 못한다.
- **E2 — 호출자 피해 (영향·보고 가치의 증거)**: 유효 입력 + 광고된 사용의 피해 입증이다. E2는 영향력과 보고 가치를 증명할 뿐이며, **BUG_FOUND를 결코 생산하지 못한다** — E2 단독(또는 E2+E3)의 상한은 `BUG_SUSPECTED`(판정표의 A-essentials 조건 충족 시)다.
- **E3 — upstream maintainer 인정 (보강·사후 확인)**: 요구 출처 + 주체 바인딩 + 재현 기록을 함께 공급하는 보강이다. E3은 **BUG_FOUND를 결코 생산하지 못하고**, 기록된 요구를 소급 생성하지도 못한다(아래 비소급 규칙).
- **비소급 규칙 (non-retroactivity — HARD RULE)**: E3(또는 제3자 진술·Axiom 측 기록)은 `recordedBinding`을 소급 생성할 수 없다. `recordedDisclaiming`/`unrecorded`/`unknown` → `recordedBinding` 전환은 **오직 주체 저장소 자신이 그 요구를 기록할 때만** 일어난다(주체의 커밋·문서·스펙 기록). 권한 분리: 명제 채택 권한(사용자) ≠ 외부 요구 선언 권한(주체 저장소) — 후자는 주체 저장소만 가진다.
- **재현 요건 (반드시 C가 운반한다)**: C는 동일한 엄격도의 **공용 4요소(§2.2)를 스스로** 운반해야 한다. M의 replay는 **보강(corroboration)으로만** 인용될 수 있고 이 요건을 결코 충족할 수 없다. C는 자립(self-contained)이다 — M 무효화는 보강 가치만 감소시킨다.
- **경로 제약**: M 선행 조건(계약 계층 판정)은 **rule-linked upstream 귀속 경로**(base36형 수직 슬라이스)에만 적용되는 것이지, 전역 요건이 아니다.
- **계약의 규범성**: 본 절은 규범 계약이다 — 현행 구현이 E2/E3 단독으로 "Bug Confirmed"를 내보내는 등의 어긋남이 관측되어도 정본은 본 절이며, 구현 정합화는 별도 workstream에서 수행한다.

### 2.4b Bug Suspected / Unknown — 전함수 우선순위 ({A, C}의 전함수)

> **2026-10-31 개정**: 본 우선순위 함수의 상태 1(Bug Confirmed)은 §2.2 판정표에 **종속**된다 — `bugAttribution = BUG_FOUND`는 E1 ∧ `requirementSourceStatus = recordedBinding`(§2.4a)을 추가로 요구하며, A·C가 아무리 충족되어도 이 없이는 상태 1에 도달하지 못한다(E2/E3 경로의 상한 = Bug Suspected). 아래 "A의 필수 조건(essentials)" 정의는 그대로 판정표 `BUG_SUSPECTED` 행의 충족 조건으로 현행이다.

- **A의 필수 조건 (essentials)** — **공용 4요소(§2.2)**에 다음이 추가된다:
  - ②의 **독립 외부 출처** — pipeline verdict 경로는 A가 아니다;
  - ③ 주체가 수용하는 입력에서의 **대조(contrast)**;
  - ④ **역할 독립** — M의 내용만으로 A를 구성할 수 없다.
- **이중 용도 규칙 (dual-use)**: C가 A의 조건을 충족하면 그 C가 A로 계수된다 — **명시 표기 필수**.

**정준 우선순위 (상호 배타적 · 전체 — 이 순서로 세 상태가 겹치지 않고 모든 입력에 결과 하나)**:

1. **Bug Confirmed**: C 유효 ∧ (A 유효 ∨ C 자체가 A의 모든 필수 조건을 충족)
2. **Bug Suspected**: 위 조건 미충족 ∧ A 유효
3. **Unknown**: A 무효 ∧ C도 A 조건을 겸용해 충족 못함

- **단조성 (monotonicity)**: Unknown → Suspected → Confirmed 전이는 **기록을 추가할 때만** 일어난다. 주체 이동(subject move)은 전부를 만료시킨다.

### 2.4c requirementSourceStatus — upstream-spec 판정 표

`requirementSourceStatus ∈ {recordedBinding, recordedDisclaiming, unrecorded, unknown}` (2026-10-31 — 제4값 `unknown` 추가; **닫힌 집합** 유지 — 집합 밖 값은 거부다):

| 값 | 의미 | upstream-spec 플래그 | `BUG_FOUND` 도달 (§2.4a E1) |
|---|---|---|---|
| `recordedBinding` | 바인딩 약속이 기록됨 | **없음** | **허용** (E1 필요) |
| `recordedDisclaiming` | "약속이 없다는 사실이 기록됨" | 표시 | 차단 |
| `unrecorded` | "출처 미기록" — **탐색했으나 발견하지 못함**(searched, not found) | 표시 | 차단 |
| `unknown` | **출처 판정 미완료** — 아직 판정되지 않음(not yet determined; 탐색 미수행 또는 판정 진행 중) | 표시 없음 — 플래그는 확정 기록 위에서만 유도(아래) | 차단 |

- **`unrecorded` ≠ `unknown` (2026-10-31)**: `unrecorded`는 "탐색 결과 부재"의 **확정 기록**이고, `unknown`은 "판정 자체가 미완료"인 **미결 상태**다. `unknown`은 조사 진행으로 나머지 셋 중 하나로 수렴해야 하는 잠정 상태이며, 어느 확정 상태로도 서술해서는 안 된다.
- 비바인딩 세 상태(`recordedDisclaiming`, `unrecorded`, `unknown`)는 **서로 다른 이유**로 `BUG_FOUND`(및 구칭 (a)형 확정)를 차단한다(E1 근거 부재 — §2.4a) — 보고서는 셋을 구분해 서술해야 한다.
- **불확실성 플래그 유도 (표시 계층 전용)**:
  - `upstream-spec` ⇔ Suspected ∧ status ∈ {recordedDisclaiming, unrecorded}
  - `verification-proof` ⇔ Suspected ∧ (status = recordedBinding ∨ 기계 불확실 상태 ∈ {clUnknown, vrInconclusive, vsInconclusive, cvUnresolved})
  - `unknown` 상태는 플래그 유도 대상이 아니다 — 플래그는 확정 기록 위에서만 유도되며, 판정 미완료는 플래그로 봉인되지 않는다.
- **교차 유도 금지 (HARD RULE)**: 기계 상태 ↔ 기록 필드 사이의 교차 유도는 금지된다 — 기계 상태는 기계 authority가 생산하고 기록 필드는 기록이 운반하며, 어느 방향으로도 서로를 유도하지 않는다. 두 플래그는 **공존할 수 있다**.

**렌더링 예시 (조합 매트릭스 행)** — 표시명은 라벨이며 어떤 기계 판정 값·게이트로도 소비되지 않는다(§1). 표시명 "Bug Confirmed"는 `bugAttribution = BUG_FOUND`에 대응한다(2026-10-31 — §2.2 판정표):

| RULE 축 | 귀속 축 | requirementSourceStatus | 플래그 | 표시 행 |
|---|---|---|---|---|
| Axiom-Defined Rule Violated | Bug Suspected | recordedDisclaiming | upstream-spec | `Axiom-Defined Rule Violated — Bug Suspected (upstream-spec; recordedDisclaiming)` |
| Axiom-Defined Rule Violated | Bug Suspected | recordedBinding | verification-proof (기계 불확실 동반 시) | `Axiom-Defined Rule Violated — Bug Suspected (verification-proof)` |
| Axiom-Defined Rule Violated | Bug Confirmed | recordedBinding | 없음 | `Axiom-Defined Rule Violated — Bug Confirmed` |
| RULE 축 미충족 (예: vrFail 단독) | Unknown | unrecorded | upstream-spec | `(rule 미확정) — Unknown (upstream-spec)` |
| RULE 축 미충족 | Unknown | unknown | 없음 (판정 미완료) | `(rule 미확정) — Unknown (requirementSourceStatus=unknown — 출처 판정 미완료)` |

### 2.4d 스코프·표시 결속 규칙 (subject-scoped display binding — HARD RULE)

표시 측 정준 RULE 전제("Axiom-Defined Rule Violated")의 구현은 **유닛-스코프 논리곱**이다: `선택된 실행 행 존재 ∧ 행 == overlay.subject.module::overlay.subject.symbol ∧ 행 상태 failed ∧ 그 유닛의 clDisproved ∧ 그 유닛의 공용 4요소 비어있지 않음 ∧ claimOwnership 유효 ∧ 주체 커밋·blob 일치` — 런-스코프(전역 판정) 전제만으로는 결코 충족되지 않는다. 스코프 표: 주체 커밋 또는 blob 불일치 → 표시 블록 없음; 커밋을 검증할 수 없어도 blob이 동일하면 → 표시 블록 없음(exact-commit 결속 미충족 — Unknown이 **아니며** 블록 부재는 해당 실행에서 적용 불가를 뜻한다); 커밋·blob 전부 일치 + 근거 결손/무효 → RULE 축은 현재 실행의 유효 증거를 따르고 귀속은 Unknown+사유; 전부 일치 → 양 축 모두 표시. Unknown은 **적용 가능하나 증거가 결손**한 상태일 때만 쓰인다(불명확한 타깃을 가리는 용도가 아니다) — §2.4b의 우선순위 함수는 이 표를 통과한 스코프-유효 주체에 대해서만 정의된다.

## 3. 반례 미발견 ≠ 안전 (HARD RULE)

"counterexample not found is not equivalent to `safe`; engine-limited or unverifiable verdicts must be explicitly stated in `soundnessNote`" — [uap_logic.md:15](./uap_logic.md).

- `NO_BUG_PROVED(P, D)`는 **P∧D에 대한 증명이 존재할 때의 서술**(§2.1의 논리곱 충족)이지, "반례를 못 찾았다"는 서술이 아니다.
- SMT가 반례를 내놓지 않는 것만으로 안전으로 승격하는 것은 UAP 파이프라인 계약이 금지한다(`uap_logic.md` — SMT 부반례 결과는 Lean replay·soundness note와 교차검증 없이 safe 승격 금지).
- `vrInconclusive`·timeout·engine-limit·evidence-failure 상태는 soundness note에 명시되어야 하며, 어떤 경우에도 `NO_BUG_PROVED`로 보고될 수 없다(§2.3).

## 4. 캠페인 적용 — nim-stew 운영 판정

- **Subject**: status-im/nim-stew, **읽기 전용**(Zero-Footprint Integrity — `git status --porcelain` 상시 공백 유지). 주체는 버전 라벨이 아니라 **exact commit + 파일 blob 해시**로 바인딩한다. S1 실측값: [evidence 레코드](../evidence/bug_verdict_contract_slice_2026-10-08.md).
- **Property**: `P_rel` — [base36_sizing_binding_contract.md:25-33](./base36_sizing_binding_contract.md)의 커밋된 관계 정리를 **변경 없이** 사용한다(S2에서 재확인 완료). `P2`(sizing soundness)는 **비채택** — 판정·근거·실측은 evidence 레코드 S2.
- 별칭은 캠페인 **보고 어휘**일 뿐이며, 코드·게이트·required check를 추가하지 않고 주체 트리에 어떤 산출물도 남기지 않는다.
