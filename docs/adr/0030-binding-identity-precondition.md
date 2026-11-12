# ADR-0030: lexical binding의 권위와 선행조건 — 이름 유일성만으로는 불충분하다

## Status

**PROPOSED (2026-10-05)** — workstream `feature/binding-smt-let-slice`. 소스에서 이미 존재하는
lexical binding을 SMT-LIB `let`을 거쳐 solver 판정까지 연결하는 첫 통로의 결정 기록이다.
본 ADR은 **판정만 기재한다.** 코드의 착지·게이트 통과는 PR 리뷰와 게이트가 판정한다.

선행 문서: `docs/adr/0029-nim-semantic-authority-and-unresolved-facts.md` (Nim 언어 의미의 권위).
본 ADR은 그 §D5(source-local fact는 계산 가능)를 **적용의 방법을** 정하며, §U3(IR 대체 여부)을
**전면 배제**한다 — binding은 IR을 대체하지 않고 SMT-LIB의 표준 binder로 전달된다.

---

## Context

### C1 — binding의 권위는 소스이며, 이미 IR에 있다

`let x = expr`의 권위자는 Axiom이 아니라 **원본 소스**다. 그리고 그 정의식은 이미 IR에 남아 있다:
`src/core/trusted/axiom_ir.nim:98` `letVal*: IRExpr`. 두 방언(NimNode · CanonNode) 모두
`identDefs[2]`에서 이 값을 만든다. 텍스트 직렬화와 바이너리 wire(`ir_binary_codec.nim`) 왕복에서도
보존된다. 즉 **Axiom이 새로 알아야 할 것은 없다 — 지금 버려지고 있는 것을 버리지 않으면 된다.**

### C2 — 문제는 정보 보존 실패다

현재 경로는 다음과 같다.

```
source → IR → [사실은 이미 있음] → eligibility에서 버림 → SMT에도 없음
```

버리는 지점은 `obligationsWithinDeclaredUniverse`
(`src/verification/obligation/candidate_eligibility.nim:346-358`)다. 본문 로컬 `let` 이름이
선언 파라미터가 아니므로 자유변수로 남고, 그 후보는 `semantic.unresolved-fact`로 거부된다.

### C3 — 하지만 binding identity는 지금 IR에 없다

- `irVar`는 **이름만** 가진다 — `src/core/trusted/axiom_ir.nim:94` `varName*: string`.
  `IRFuncDef.symbolTable`은 `:170`에 **선언되어 있고 채워지지 않는다**.
- **`ckBlockStmt`에 case arm이 없다.** 이 kind는 정의되어 있다
  (`tools/shared/canonical_ast.nim:44`, `nnkBlockStmt`에서 매핑 `:196`) 그러나
  `src/core/trusted/ast_to_ir.nim`에 등장 횟수가 **0**이다. 따라서 block 본문은 변환기의 fallback에
  떨어진다.
- 실측: `let x = 1; block: let x = 2; x` → `translationLossFree=false`, 안쪽 `let x = 2`는 **삭제**된다.
  소스에는 shadowing이 있는데 IR에는 **이름이 유일해 보인다.**

### C4 — 그러므로 이름 유일성만으로는 불충분하다

위 실측이 결정적이다. IR의 `letName`이 유일하다는 것은 **바인딩이 정확히 하나 존재한다는 보장이
아니다** — 조용히 삭제된 바인딩은 흔적도 없이 유일성을 유지한다. 따라서 순서가 적재다.

```
proposition region loss-free?  ├─ NO → 거부
binding RHS loss-free?         ├─ NO → 거부
freeVars ⊆ closure?            ├─ NO → semantic.unresolved-fact
중복 binding 이름?              ├─ YES → 거부 (이름은 binding identity가 아니다)
```

유일성 검사를 먼저 돌리면, **바인딩이 조용히 사라진 lossy 번역을 통과시킨다.**

### C5 — 기존 정규화 패스는 재사용할 수 없다

`canonicalizeIR`(`axiom_ir.nim:475`)는 지역을 `v0, v1, …`로 alpha-renaming한다. 두 가지 이유로
기각한다.
1. **호출이 digest 전용이다** — 유일한 production 호출은 `:498`(내부 computeIrDigest 경로).
   증명 경로에는 적용된 적이 없다. `ir_to_smt_chunk3.nim:5-6`도 이를 명시한다.
2. **shadowing에서 건전하지 않다.** 평면 `renameMap` 덮어쓰기 때문에 실측 캡처가 발생한다:
   `let a = 1; let a = a + 1` 에서 **바깥** `a`가 안쪽 바인더의 `v1`로 이름 변경된다.
   저장소도 이미 이를 별도 WP로 기록하고 있다(`experiments/act2-wpj2-semantic-facts/probe/ingress-fidelity.md`).

---

## Decision

### D1 — lexical binding의 권위자는 소스다

`irLet.letVal`(`axiom_ir.nim:98`)은 **source-local fact**다. ADR-0029 §D2(컴파일러 의미 금지)와
§D4(플랫폼 미제공)는 적용되지 않는다 — 여기서 필요한 정보는 원본 소스에 이미 있다. §D5가 이
계산을 허용한다.

### D2 — eligibility 게이트는 위 C4의 순서로 판정한다

`candidate_eligibility.nim`의 binding 판정은 다음 4단계를 **이 순서로** 실행한다.

| 단계 | 조건 | 실패 사유 |
|---|---|---|
| (a) | proposition region이 translation-loss-free | `buvLossyPropositionRegion` |
| (b) | 기록된 모든 binding의 RHS가 loss-free | `buvLossyBindingRegion` |
| (c) | 자유변수가 `closure(params ∪ loss-free bindings)`에 포함 | `buvUnresolvedName` |
| (d) | 기록된 binding 이름에 중복이 없음 | `buvAmbiguousBindingName` |

(a)가 (d)보다 앞서는 것이 본 ADR의 핵심이다. (a)는 `IRFuncDef.propositionRegionLossFree`
(`axiom_ir.nim:184`)로 읽고, (d)는 `IRFuncDef.recordedBindings`(`:181`)로 판정한다.

**loss를 3종으로 구분한 이유**(`ast_to_ir.nim:46-77`):
- `markLoss` — 이 IR이 **표현 못 하는** 표현 → 자리표시자. 구조는 살아 있고 잎만 틀렸다.
- `markRegionDrop` — 본문이 **순회조차 되지 않는** 문장 형태. 그 안의 `let`은 *표시된 lossy가 아니라
  부재한다*. **이것만이 binding identity를 위협한다.**
- `markGuardLoss` — guard/루프 조건 내부의 손실, 또는 만들어낸 case ordinal. 값이 아니라 **전제**를
  만들어낸다.

판별자는 `traversesSubtreeAsExpression`(`ast_to_ir.nim:81`, `:98`)이다. body 변환기의 fallback은
인식하지 못한 문장의 **값**을 보존해 후행 표현식으로 변환한다. 표현 변환기가 그 kind를 이해하면 모든
부분 표현이 여전히 도달하므로 그 문장은 선언을 숨기지 않는다(값 손실). 그렇지 않으면(`ckBlockStmt`,
`ckIfStmt`, 루프) **실제 drop**이다.

### D3 — IR에 `bindingId` 필드를 추가하지 않는다

`IRExpr`에 필드를 추가하면 비용은 다음과 같다(저장소의 자체 비용 체크리스트:
`experiments/.../ingress-fidelity.md:81-84`): `serializeIRExpr`(`axiom_ir.nim:238`),
`parseIRExpr`(`:728`), `canonicalizeExpr`(`:355`), `src/infrastructure/ir_binary_codec.nim:249-257`
및 `:365-375` — **새 wire 태그가 필요하다**(현재 `0x04` LET / `0x0E` CLET만 존재), Lean parity
`proofs/IR/AxiomIRExpr.lean:46,322-331`, 그리고 lowering 헬퍼들.

**이 결정을 가능하게 한 비대칭**: `translationLossFree`와 `bindingUniverseComplete`는 이미
`serializeIRFuncDef`/`computeIrDigest`에서 **제외**되어 있다(`axiom_ir.nim:172-175`). 따라서
`IRFuncDef`에 추가한 증거 필드는 identity를 흔들지 않는다. B가 추가한 4개 필드가 그 증거다 —
digest 비변경이 테스트로 고정되어 있다.

### D4 — binding은 SMT-LIB `let`로 전달한다. equality assertion이 아니다

SMT-LIB 2.7 §3.6.1: `let`은 **동시(parallel)**로 정의된다. Remark 4: *"No sequential version of let.
Its effect is achieved by nesting lets."* §3.6.2: 각 바인드 변수의 **scope는 본문**이다.
`let`은 **term former**이므로 부정된 obligation 전체를 감쌀 수 있고, 순수 치환이다.

실측으로 확인된 사실: **평행 `let`은 Z3 4.13.3이 거부한다** —
`(error "line 7 column 47: unknown constant bytesCount")`. 즉 중첩은 스타일이 아니라 **필수**다.
IR이 이미 `irLet`을 중첩하므로 중첩은 공짜로 따라온다. 발신은 이미 존재한다
(`src/core/trusted/private/ir_to_smt_chunk2.nim:62`).

**기각한 대안** — `assert (= x rhs)`: 논리적으로 가능하나, (i) 별도 공리가 되고,
(ii) **여러 assert가 x를 언급하면** 단일 `let`과 의미가 달라진다(단일 `let`은 그 본문 밖 언급을
흡수하지 않는다). 이 차이는 명시적으로 기록한다.

### D5 — scoped closure이며, 전역 "fact 시스템"이 아니다

```
freeVars(obligation) ⊆ closure(params ∪ bindings)
  각 binding의 RHS 자유변수도 closure 안에
```

이는 **자격 정책**이고 위 구현은 그 정책을 강제하는 **한 가지 방법**이다. Axiom은 binding 의미를
구현하지 않는다 — SMT-LIB가 정의한다.

측정된 사실 하나를 기록한다: **obligation의 자유변수가 이미 전부 파라미터이면 이 채널은 no-op이다.**
`rbTreeRotateSingle`과 `collectFieldsInHierarchy`가 그것이다. 아무것도 소거하지 않는 binding은
진행으로 세면 안 된다.

### D6 — `len`의 의미를 발명하지 않는다

SMT-LIB 공식 이론 목록에 **Sequences 이론이 없다**(`smt-lib.org/theories.shtml`). `len`은 어떤
공식 이론에도 없다. 저장소의 기존 대응(`irtList → Array` + `seq_len`)은 Z3에서 **파싱 오류**다
(실측). `docs/spec/axiom_core_ir_spec.md:198`이 이미 "QF_BV에 리스트 sort 없음"을 인정한다.

결정: `len`을 **uninterpreted**로 선언한다. 이는 `len`을 **과대 근사**하므로 증명을 더 어렵게만
만들고 거짓 `unsat`을 만들어낼 수 없다. 시맨틱을 발명하는 것은 D1의 위반이다. 이 조각은
`QF_AUFBV`를 요구하며(측정: `QF_BV`는 `unknown sort 'Array'`와
`logic does not support uninterpreted functions`를 낸다), 로더는 **fail-closed**로 그 요구를
알린다.

### D7 — 영구 범위 밖

- **generic instantiation**, **generic을 통과하는 `sizeof`** — 플랫폼 미제공(ADR-0029 §D4/D5).
  영구 fail-closed. 이번 통로가 성공해도 확장하지 않는다.
- **enum member resolution** — 첫 판정에 불필요하다. 넣으면 binding resolver + 모듈 선언 resolver +
  모호성 resolver + enum 의미론이 한꺼번에 들어가고, 무엇이 원인인지 다시 불분명해진다.
- **전체 symbol table / 두 번째 parser.**

### D8 — UNSAT가 필요하면 다른 메커니즘이다

index guard는 `0 ≤ i ∧ i < len(s)`이고 `i := len(s) − 1`이다. 첫 conjunct는 `len ≥ 1`을 요구하는데,
**binding 해소는 값을 줄 뿐 비어 있지 않음 전제를 주지 않는다.**

측정(길이 0..7): 역례 집합이 **binding 없음 8/8 → 있음 1/8**로 줄었다. `L = 1`에서 2²⁰ 범위에 대해
**binding 없이는 1,048,575개 실패, binding 있으면 0개.** 그러므로 binding 해소는 **실측 가능한
 tightened** 다. 남는 역례는 `len = 0` — 빈 배열에서 `bytes[-1]`을 읽는 **실제 결함**이며, 판정은
정직하게 **`sat`**다.

`unsat`에 도달하려면 **assert 유래 전제**가 필요하며, 그 메커니즘은 이미 존재한다 —
`src/core/trusted/contract_synthesis.nim:322-357` `collectAssertGuards`, `synthesizeContracts:363`에
배선됨. 이것은 **별도 조각**이며 본 조각이 아니다.

### D9 — 결정론은 기본값이 아니라 opt-in이다

SMT-LIB 2.7 §4.1.7: `:random-seed`의 기본값 0은 *"the solver can use any random seed—possibly even
a different one for each run"*를 뜻한다 — **0은 결정론의 opt-out**이다. Axiom은 0이 아닌 값을 고정한다.
`:reproducible-resource-limit`은 존재하나 보장은 **동일 기계**로 한정되고 `:random-seed ≠ 0`이
선행 조건이다.

또한 **SMT-LIB에는 canonical text form이 없다** — 공백과 진법은 무시된다(`1.0`/`1.00`, `#x`/`#b`는
같은 값). canonicalization은 **Axiom 자신의 책임**이며 표준에 근거를 둘 수 없다.

---

## Rejected Alternatives

| # | 대안 | 기각 이유 |
|---|---|---|
| R1 | `SemanticFact(name, rhs)` 전역 추상화 | 이름은 권위가 아니다. shadowing 아래에서 모호하다(§C3). 이름이 아닌 **scope + 정의식**이 권위다 |
| R2 | `canonicalizeIR` 재사용 | digest 전용(`:498`) + shadowing 캡처 버그 실측(§C5) |
| R3 | `IRExpr`에 `bindingId` 추가 | ≥9개 파일 + **새 wire 태그** + Lean parity(§D3) |
| R4 | `assert (= x rhs)` | 별도 공리이며, 다중 assert에서 `let`과 의미가 달라진다(§D4) |
| R5 | `len`에 실제 시맨틱 부여 | 발명 금지(§D6). 과대 근사로 충분 |
| R6 | 이름 유일성만으로 게게이트 | lossy 번역이 통과한다(§C4) |
| R7 | enum resolution을 첫 조각에 포함 | 첫 판정 원인 추적 불가능 + 4개 메커니즘 동시 도입(§D7) |

---

## Consequences

### §6 — 이 조각이 소유하는 것 / 소유하지 않는 것

**Axiom이 소유한다**: 어떤 source fact를 신뢰할지, 어떤 binding인지, 어떤 IR을 SMT로 내릴지,
어떤 입력을 solver에 줄지, 그 실행의 결정론적 identity, 결과를 어떻게 증거로 묶는지.

**Axiom이 소유하지 않는다**: Nim 의미론, generic instantiation, SMT 논리의 의미, solver의
satisfiability 알고리즘, Lean kernel, symbol resolution.

**Trust Fact vs Execution Adapter**: Nim 소스·SMT-LIB 의미론·Z3 판정은 Trust Fact다. Axiom의 역할은
Execution Adapter — 어느 fact를 신뢰할지, 어떤 binding인지, 어떤 IR을 내릴지, 어떤 입력을 줄지,
결정론적 identity와 증거 묶음.

### §6b — 함께 다룬 false-authority 결함

같은 workstream에서 **같은 실패 형태**(증거 없이 가장 강한 주장을 기본값으로 삼는 것)가 일곱 곳에서
발견되고 하나의 권위 규칙으로 수렴되었다. 이들의 존속은 본 조각의 성립 조건이기도 하다 — binding으로
도달한 판정이 그 경로에서 조작될 수 있다면 의미가 없다.

| 사이트 | 형태 |
|---|---|
| `kernel_reexecution` | `"unsat" in output` 부분일치 → `krPassed` |
| `axiom_api_verify` | `var finalStatus = "proved"` 기본값 |
| `z3_result_parser` | "마지막 상태 승리" — 첫 응답 `sat`인데 `proved` |
| `axiom_api_session_helpers` | `반례 ? "sat" : "proved"` |
| `axiom_api_session_ops` | `반례 없음 → safe_within_bound` |
| `z3_extraction` | 모순된 응답이 `psProven` |
| Z3 오류 우선순위 | `(error …)` + `sat`이 verdict로 기록 |

수렴 지점은 `classifySolverVerdict` → `solverResponse`(`src/core/trusted/solver_invocation.nim`)이며,
`srNoDecision`은 **판정을 제거할 수만 있고 추가할 수 없다.** `proved`는 `sat | unsat | unknown`만
가진 enum으로 표현 불가하게 만들어졌다.

### §6c — anomaly 규칙의 전제(기록)

응답이 2개 이상이면 anomaly이며 아무것도 방출하지 않는다 — **단 첫 응답이 `sat`이면 유지한다.**
역례는 adverse evidence이므로 anomaly가 숨기지 않는다. fail-closed는 과대 주장을 막는 것이지
반례를 버리는 게 아니다.

이 규칙이 정당한 것은 **Axiom의 production envelope가 정확히 하나의 `check-sat`을 낸다**는 전제
때문이다(`src/core/contracts/z3_extraction.nim:497`). 여러 `check-sat`을 쓰는 envelope가 도입되면
**응답 페어링 규칙을 명시적으로 추가해야 하며**, 조용히 완화하지 않는다.

---

## Residual Limits

- **U1** 본 ADR의 게이트를 강제하는 것은 코드이지, "재구현 금지"를 검사하는 별도 게이트가 아니다.
  현재의 기계 강제는 §D2의 게이트와 배선뿐이며, 재구현 재발을 막는 것은 리뷰와 결정 바인딩이다.
  (ADR-0029 U1과 같은 종류의 한계.)
- **U2** `convertExprCanon`에 `ckIfStmt`/`ckElifBranch` arm이 없다. 그래서
  `collectFieldsInHierarchy`가 closure 검사까지 도달하지 못한다. (a)를 완화하면 shadowing 구멍이
  다시 열리므로 완화하지 않았다. 정식 해법은 arm 추가이거나 drop된 영역에서 선언을 회수하는 것.
- **U3** `toCanonKind`(`src/core/trusted/pnode_to_canon.nim`)가 `nkCommentStmt`을 매핑하지 않는다
  (`nimKindToCanon`은 매핑) → doc comment가 `ckUnknown`으로 도착하여 **주석이 있는 모든 함수**가
  lossy로 보였다. 두 테이블의 정렬이 정식 해법이며, 현재는 자식 없는 `ckUnknown`을 값 손실로 보는
  좁은 우회가 있다.
- **U4** obligation identity 계약과 구현이 다르다 — `docs/spec/obligation_semantics.md:30-33`은
  `‖` 연결을 규범으로 서술하고, 구현은 `|` 구분자 + length-prefixed atom framing을 쓴다
  (`src/verification/obligation/obligation_types.nim:315-326`). 본 조각은 identity 수식을 바꾸지
  않으므로 선행 불요하나, **spec-conformant라고 주장하지 않는다.**
- **U5** `ckBlockStmt` arm 추가는 `bitsLen`/`add`의 결정적 경로가 아니다 — 이들의 손실 원인은
  `ckPar`, `ckElifBranch`, `ckElse`, `ckCommand`, `ckUnknown`이다.

---

## References

- `docs/adr/0029-nim-semantic-authority-and-unresolved-facts.md` — Nim 언어 의미의 권위, D2/D4/D5, U3
- `docs/spec/axiom_core_ir_spec.md:198` — QF_BV에 리스트 sort 없음
- `docs/spec/obligation_semantics.md:30-33, 291-300` — identity 규범(구현과 불일치, U4)
- `docs/spec/certification_continuity_contract.md:235` — INV-4 구조적 독립성
- SMT-LIB 2.7 `smt-lib-reference-v2.7-r2026-09-09.pdf` §3.6.1, §3.6.2, Remark 4
- SMT-LIB 공식 이론 목록 `smt-lib.org/theories.shtml` — Sequences 이론 부재
- SMT-LIB §4.1.5 `⟨check_sat_response⟩ ::= sat | unsat | unknown` · §4.1.7 `:random-seed` 기본값 0의 정의
- 소스 실측: nim-stew @ `c75502ce`, 고정 스냅샷, 신규 state dir

*작성일: 2026-10-05. PROPOSED — 판정 기록이며 제품 계약 확정을 포함하지 않는다. §Residual Limits의
U1~U5가 닫히기 전 "재구현 금지"와 "fail-closed 강제"가 완전히 기계 강제되었다고 주장하지 않는다.*
