# Reference Extractor Independence Audit — 2026-09-10

> **Status**: AUDIT RECORD (point-in-time; certification-continuity Phase 6-①)
> **Date**: 2026-09-10
> **Subject**: `proofs/IR/ReferenceExtractor.lean` — Tier 2 extraction agreement
> reference extractor의 독립성(INV-4) 및 지원 subset 경계에 대한 서면 감사 기록.
> **기준**: AGENTS.md §0.9b(Triple-Closure — 이 기록은 "외부 mutation harness → scanner
> audit → 독립 빌드" 중 **독립 유도(다른 언어) leg**의 서면 근거), 계약 §5 INV-4
> ([certification_continuity_contract.md](../spec/certification_continuity_contract.md)),
> §8.3 lean4lean 전례.
> **스코프**: (a) 독립성 주장의 문장·반증 조건, (b) 지원 subset 목록(경계), (c) 알려진
> 이탈, (d) 검증 근거(테스트 계수), (e) reviewer 체크리스트, (f) subset soundness 로드맵.

---

## 1. 독립성 주장 (INV-4) — 검토 기록

### 1.1 주장 (파일 헤더 원문 요지)

`proofs/IR/ReferenceExtractor.lean` 헤더가 선언하는 독립성:

- **다른 언어**: Lean 4 vs Nim — canonical extractor(`src/core/trusted/ast_to_ir.nim`)와
  언어가 다르다(INV-4 첫째 대안 "different language" 충족).
- **독립 유도**: Nim extractor 소스에서 유도되지 않았고, IRExpr 정의
  (`proofs/IR/AxiomIRExpr.lean`)와 certified-subset 판독(계약 §1)에서 직접 작성.
- **자체 wire 디코더/인코더**: AST wire(`src/verification/ast_wire.nim`)를 자체 디코더로
  판독 — 기존 `AxiomIR.BinaryCodec`는 IRExpr용이므로 AST 디코더는 신규·독립 — 산출
  IRExpr을 자체 인코더로 8-byte 정렬 IR binary로 재직렬화.
- **lean4lean 비유입 명시**: "derived directly from the C++ kernel implementation… not
  really an independent implementation"(계약 §8.3) — 동일 생성기 산출물을 증거로
  취급하지 않는 INV-4 금지 패턴을 헤더에서 배제 선언.

### 1.2 반증 조건 (주장이 거짓이면 성립해야 하는 관측)

감사자는 아래 어느 하나라도 관측되면 주장을 기각한다:

| # | 반증 관측 | 점검 방법 |
|---|---|---|
| R1 | ReferenceExtractor의 산출물이 ast_to_ir.nim의 산출물과 구조 공유(동일 생성기 흔적: 동일 버그·동일 특이 문자열·동일 비-결정 서열) | 두 산출물의 라인 대조 + 의도적 이식 버그 주입(한쪽만 변이) 여부 관찰 |
| R2 | ReferenceExtractor가 Nim side에서 생성되거나 Nim AST를 가져와 변환(언어 경계 붕괴) | `import` 스캔 — Lean 4 표준 라이브러리와 AxiomIR/IR만 참조 |
| R3 | per-run differential이 항상 일치하도록 설계된 우회(예: 합의를 강제하는 공유 oracle — theater, AGENTS.md §0.9) | `extraction_agreement.nim` 검토 — 양쪽 산출물의 직렬화 byte 비교가 실체 |
| R4 | 안전 경계 밖 construct가 silent 합의(경계 밖이 합의로 오인) | 지원 subset 목록(§2) — 밖은 디코드/추출 실패(exit 1)로 fail-closed |

### 1.3 기각 사유 없는 관측 (2026-09-10 현재)

- 언어 경계 유지: Lean 4 순수 모듈, AxiomIR/Lean std만 import — R2 해당 없음.
- 합의 기준은 **직렬화 byte 동치**이며 합의를 강제하는 공유 oracle 없음 — R3 해당 없음.
- 알려진 이탈(§3)이 EA_MISMATCH로 **silent 합의가 불가능**함을 실증 — R4의 의도적
  우회 경로가 존재하지 않음(실제 이탈 1건이 시스템에 표면화됨을 §0.9b 관점에서 긍정 신호로 기록).

## 2. 지원 subset 목록 (경계 선언)

`proofs/IR/ReferenceExtractor.lean` 헤더 + `src/verification/ast_wire.nim` wire kinds
(계약 §7 Phase 3.75와 일치):

| 종류 | 항목 |
|---|---|
| 리터럴 | int(전 폭, unified Int), char, nil(→ lit 0) |
| 식 | 식별자(var), infix `+ - * / div % mod < <= > >= == and or`, prefix `-`(bvNeg)·`not`(not_), 호출(자기 이름 → irRecCall) |
| 바인딩 | let/var/const 단일 이름 바인딩 |
| 대입 | 식별자 target 대입(이름 `result` → body 식) |
| 흐름 | return 문, 단일-분기 early-return if 문 |
| 함수 | formal params 포함 함수 정의(int-family/bool/string 타입명만) |

**경계 밖** = 디코드/추출/인코딩 실패 — `aweUnsupported`(ast_wire) / exit 1(worker),
lossy가 아닌 hard fail(fail-closed). SPARK "not in SPARK" 모델(계약 §2/§6).

## 3. 알려진 이탈 (documented divergence)

| 이탈 | 관측 | 표면화 |
|---|---|---|
| early-return if의 **0 아닌 반환값 강등** | canonical extractor(`extractReturnValueCanon`이 elif branch를 받는 구조)가 0 아닌 return value를 `irLit(0)`으로 강등 | 해당 함수는 per-run differential에서 **EA_MISMATCH**로 표면화 — 참조 extractor는 참 값을 보존 |
| 합의 불가 확인 | 이탈이 silent 합의로 이어질 수 없음 — 의도된 fail-closed(계약 §7 Phase 3.75 "알려진 이탈(문서화)") | attest 체인에서 EA_UNSUPPORTED/EA_MISMATCH는 attest FAIL |

의미: 이탈은 "구현 취약점"이면서 동시에 **differential이 실제 불일치를 소리 내는
증거**(theater 부재의 실측)다. 제거는 subset soundness 로드맵(§6 M-4)에서 함수별
정리와 함께 처리한다.

## 4. 검증 근거 (Phase 3.75 이하 테스트 계수)

| 증거 | 계수(2026-09-10 기준) | 비고 |
|---|---|---|
| `tests/verification/test_extraction_agreement.nim` (Phase 3.75) | **38 checks** | eaAgree/eaMismatch/eaUnsupported/eaReferenceError/eaInternalError 전 경로; real-lean SKIP guard 포함 |
| `tests/verification/test_semantic_closure.nim` (Phase 3.5) | **55 checks** | evalIR/render_eq_eval 등가정리 + MetaCheckIR 배선 |
| `tests/verification/test_kernel_reexecution.nim` (Phase 3) | **78 checks** | INV-6 allowlist, `#print axioms` 관측, P10 leanchecker deep-check(Phase 6-③) 포함 |
| `tests/verification/test_attestation.nim` (Phase 4) | **79 checks** | attest 체인에서 eaAgree required — 추출 합의는 인증의 경계 |
| `tests/verification/test_publication.nim` (Phase 5) | **57 checks** | 발행 전 재검증 경로 |
| 실Lean happy path | attest→mint→tamper→`ax cert verify` reject→`--kernel` roundtrip | real lean/z3/ircheck로 검증 (test_attestation.nim) |
| 구조 독립성 관점 | 언어 경계(§1.3) + 이탈 실표면(§3) | INV-4 두 대안 중 첫째("different language") 채택 |

non-real-tool 경로는 loud SKIP(exit 0) — CI는 lean 부재에서도 green이나, attest
certificate 경로는 real tool 검증에서만 mint된다(별개의 문제).

## 5. Reviewer 체크리스트 (human audit — §0.9b)

- [ ] `proofs/IR/ReferenceExtractor.lean` 헤더의 독립성 주장 재읽기 — §1.1 문장과 일치하는가
- [ ] R1: 임의 3개 함수를 ast_to_ir.nim 대응 구현과 병렬 대조 — 구조적 공유/이식 흔적 없는가
- [ ] R2: 파일 전체 `import` 목록에 Nim/공유 생성기 산출물 없는가
- [ ] R3: `src/verification/extraction_agreement.nim`의 직렬화 byte 비교가 합의를 강제하는
      공유 상태 없이 실체 비교인가(양쪽 산출물 경로 독립)
- [ ] §3 이탈 1건이 EA_MISMATCH로 표면화되는 재현(해당 subset 함수 1개로 mini repro) 가능한가
- [ ] §4 계수 재실행(extraction 38 + kernel 78) — 이 문서의 계수와 일치하는가
- [ ] attest 체인에서 eaAgree required 유지 확인(계약 §5 INV-4, Phase 4)
- [ ] subset 목록(§2)에 경계 밖 construct 추가/제거가 있었다면 이 문서 + ast_wire +
      ReferenceExtractor 헤더 3곳 동기화 확인
- [ ] leanchecker deep-check(Phase 6-③)가 부재 시 SKIP, 존재 시 lcMismatch fail-closed인가

## 6. subset extraction soundness — 종착형 로드맵 (CompCert-shaped)

**종착형**(계약 §10.5): Nim-subset **operational semantics를 Lean 4로 정의**하고
(현행 `proofs/IR/Denotation.lean` `evalIR`/`renderIR`를 전면 의미론으로 승격 — 이미
kernel-checked `render_eq_eval` 등가정리 존재), reference extractor 변환의
**soundness 정리**(정의역 = §2 certified subset; 정리 = AST denotation → IR denotation
보존)를 kernel-checked로 증명한다. **잔존 TCB = 미검증 parser**(Nim 2.2.10 앞단 —
계약 §3 1층 "qualified", CompCert CACM §5 항목 2의 parser 자인과 동형).

| 마일스톤 | 내용 | 완료 기준 |
|---|---|---|
| M-1 | subset 언어의 Lean 4 BNF/denotation 확정(식·바인딩·early-return) — `evalIR`를 정의론적 기준으로 승격 | subset 내 모든 AST node에 대한 denotation 정의 커버 |
| M-2 | per-function soundness 정리: canonical + reference 추출기의 정의역 보존 단정리(합의 IR 존재 ⇔ denotation 동치) | 각 지원 kind별 정리 kernel-checked, `#print axioms` ⊆ INV-6 allowlist |
| M-3 | 이탈 제거: §3 early-return 강등을 정리와 함께 수리 — 강등이 아닌 보존 구현 + 정리 | 재현 mini repro가 eaAgree로 전환, 회귀 집합 재실행 |
| M-4 | 추출기 증명 이관: reference extractor를 Lean 내부 함수로 확정(정리의 대상 자체가 reference) | soundness 정리가 reference 구현을 직접 명제화 |
| M-5 | 경계 fail-closed 정리: subset 밖 입력 → 디코더/추출 거부의 정리(not-in-subset ⇒ 거부) | aweUnsupported 경로의 합성 증명, parser는 declared TCB로 잔존 |

**순서 원칙**(§0.12): 각 마일스톤은 전 단계 kernel-verified 결과 위에서만 진행 —
soundness 정리는 "테스트 통과"가 아니라 계약 §2의 인증 문장(증명함: denotation 위
proposition)을 확장하는 유일 경로다.

---

- 근거: 계약 [certification_continuity_contract.md](../spec/certification_continuity_contract.md)
  §2·§3·§5(INV-4)·§7(Phase 3.75/6)·§8.3·§10.5 · [../../proofs/IR/ReferenceExtractor.lean](../../proofs/IR/ReferenceExtractor.lean) 헤더 —
  감사 대상 스스로의 선언을 1차 증거로, 반증 조건(§1.2)을 점검 수단으로 기록
- 실측(MEASURED): §4 테스트 계수 — 2026-09-10 로컬 재실행(모두 exit 0)
