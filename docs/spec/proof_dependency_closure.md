# Proof Dependency Closure — 증명 의존성 폐쇄 규칙

> **Status**: Normative contract — B-2 hermetic proof capsule의 증명 의무 범위를 결정하는 정식 계약 (구현에 선행하는 사전등록)
> **Created**: 2026-11-04
> **Written at**: branch `work/b2-1b-dep-closure-2026-11-04` (base = main `50d781e82`)
> **Related**: [obligation_semantics.md](./obligation_semantics.md) (심볼 단위 canonical obligation identity — 본 문서의 캡슐 단위 폐쇄와 상보, 충돌 없음) · [hermetic_gate_framework.md](./hermetic_gate_framework.md) · [docs/evidence/b1_gate_a_minimal_proof_2026-11-04.md](../evidence/b1_gate_a_minimal_proof_2026-11-04.md) (§8 적용 사례의 근거 — B-1 Gate A, 이하 "B-1") · [docs/evidence/b1_gate_b_capability_census_2026-11-04.md](../evidence/b1_gate_b_capability_census_2026-11-04.md) (§7 반례의 근거 — Gate B §5.7, 이하 "Gate B")
> **AGENTS.md 참조**: §0.5 (Documentation-First — 계약이 구현에 선행), §0.9 (Theater 금지), §0.9b (무한 후퇴 종료), §0.12 (제품 계약과 수직 슬라이스 우선), §2.2 (완료 = 기계 검증·발견 ≠ 권한), §4 (GUARDIAN — 검증 불가·오래된 증거 = fail closed)

---

## 1. 목적 (Purpose)

이 문서는 B-2 hermetic proof capsule(독립 명제 + 추출 산출물(LLBC) + 손모델 + 커널 증명으로 구성되는 증명 산출물 단위)이 **무엇을 증명해야 하는가** — 증명 의무 범위 — 를 결정하는 규칙을 계약으로 고정한다.

B-1 Gate A 관측(B-1 §4.3–4.4)에서 `serde_json::value::Value::as_bool`의 LLBC 최소 추출은 fun_decls 21(본문 Structured 1·Opaque 20)·type_decls 11로 닫힌 폐쇄를 실측했고, 그 위에서 커널 승인(sorryAx 0)·mutation 음성·cold 재현 5축 폐쇄에 도달했다(B-1 §4.8–4.11). 이 문서는 그 폐쇄가 **왜 그 크기인가**를 만든 규칙을 정본 계약으로 등록한다 — 이후의 증명 작업이 임의로 범위를 넓히거나(도구 능력에 따른 확장 추출) 좁히지(의존성 누락) 못하게 하는 것이 유일한 목적이다.

이 계약이 규정하는 것: 폐쇄의 출발점(§4 — 명제), 계산 절차(§4), 5분류 규칙(§5), fail-closed 조항(§6), 손모델·대체 계약의 요건(§3, §5), 제외 근거 기록 의무(§4 Step 4, §5).

이 계약이 규정하지 **않는** 것: 추출·번역 도구의 채택 결정(charon/aeneas 어댑터 여부 — 별도 계약 개정 사항, Gate B §Non-decision 준용), 게이트·레인·인증서의 승인 계약, 측정 절차 문서화 방법.

## 2. 적용 범위 (Scope)

- **적용 대상**: B-2 hermetic proof capsule 이상의 모든 커널 증명 작업 — 하나의 독립 명제 집합과 그에 대응하는 추출 산출물·손모델·커널 증명으로 구성되는 캡슐 전체.
- **적용 시점**: 명제가 확정된 이후, 커널 증명의 수용(acceptance) 판정 이전. 폐쇄 계산의 결과는 수용 판정의 입력이다 — 폐쇄가 성립하지 않으면 증명은 수용되지 않는다(§6).
- **증명 의무의 단위**: 캡슐 단위 — 동일 문서 계약에서 정의된 명제 집합당 하나의 폐쇄.
- **범위 밖**: Axiom 자체 Nim 커널의 IR→Lean 파이프라인이 지배하는 심볼 단위 의무 — 그 canonical identity와 생성 규칙은 [obligation_semantics.md](./obligation_semantics.md) §2–3(`obs:*`)이 정한다. 본 문서는 그 계약을 대체하지 않는다(캡슐 단위 폐쇄 ⊃ 심볼 단위 의무가 아님 — 두 계약은 서로 다른 단위를 규율하며 충돌 시 각자의 단위 기준이 지배한다).
- **주장 경계**: 본 계약이 하는 주장은 "폐쇄 규칙을 만족하는 증명만 수용된다"는 절차적 의무뿐이다. 특정 캡슐의 증명 성공, 도구(추출기·번역기)의 능력, 손모델의 일반적 정확성은 본 계약이 주장하지 않는다.

## 3. 용어 (Definitions)

- **명제 (proposition)** — 구현에서 역유도하지 않고 **문서 계약에서 독립 정의**된 증명 목표. 선례: B-1 §4.8 — `as_bool_bool_some`·`as_bool_non_bool_none`은 serde_json `as_bool` 문서 계약("If the `Value` is a Boolean, returns the associated `bool`. Returns `None` otherwise.")으로부터 2절로 정의되었으며, 구현 코드에서 유도되지 않았다. 명제의 독립성이 폐쇄의 출발점을 "구현"이 아니라 "명제"로 만든다(§4 Step 0).
- **증명 의무 (proof obligation — 본 문서의 범위 의미)** — 커널이 명제를 승인하기 위해 폐쇄에 반드시 포함되어야 하는 항목의 집합: 명제에 직접 연결되는 코드, 필요한 호출 함수, 필요한 ADT·타입, opaque/external 항목의 대체 계약. [obligation_semantics.md](./obligation_semantics.md)가 정의하는 심볼 단위 canonical obligation과 구분된다.
- **폐쇄 (closure)** — 명제로부터 출발한 **필요 의존성의 전이적 집합**. 결정적이다: 동일 (명제 집합, 추출 산출물 identity) → 동일 폐쇄. 폐쇄는 "가져올 수 있는 것"(추출 능력)이 아니라 "증명에 필요한 것"(명제에서 계산된 필요성)만 포함한다(§7 반례).
- **손모델 (hand model)** — opaque/external 항목의 빈자리를 대신하는 증명자 작성 명시적 정의·가정 계약. 선례: B-1 §4.7 — `F64`(`structure F64 where val : Float`)·`BTreeMap`(`structure … where entries : List (K × V)`). 손모델의 충실성은 **해당 명제의 필요 범위에서만** 정당화된다 — 모델의 일반적 정확성 주장은 극장(AGENTS.md §0.9)이다(B-1 §Non-claims 동일 원칙).
- **대체 계약 (surrogate contract)** — 본문이 제공되지 않는 항목에 대해 그 빈자리가 무엇으로 채워지는지를 명시하는 기록: (a) 모델 정의(직접 작성하거나, 검증된 번역 라이브러리의 기존 모델 수용), (b) 신뢰 가정의 명시, (c) 그 모델이 해당 명제의 진위에 영향 불가능함을 확정한 근거(추출 산출물 서명 기반). 대체 계약 부재 = 수용 불가(§5, §6-F2).
- **제외 근거 (exclusion ground)** — 폐쇄에서 빠진 항목에 대해 "명제가 도달하지 않는다"는 것을 확인한 기록. 무관 코드의 제외는 근거가 확인되고 기록되는 경우에만 허용된다(§5).

## 4. 폐쇄 계산 절차 (Closure Computation Procedure)

폐쇄 계산은 다음 순서를 따른다. 각 단계의 산출물은 원문 관측(LLBC·추출 산출물 identity 해시)으로 재검증 가능해야 한다.

- **Step 0 — 명제 확정 (출발점 고정)**: 명제는 구현에서 역유도하지 않고 문서 계약에서 독립 정의한다(B-1 §4.8 원칙). 폐쇄 계산의 출발점은 **항상 명제**다 — 구현 전체, 크레이트 전체, 추출기의 출력 전체가 아니다. 명제가 정의되지 않으면 폐쇄 계산은 성립하지 않는다(fail-closed, §6-F1).
- **Step 1 — 타입 closure 전수 분석**: 명제의 서명과 참조 본문에 등장하는 모든 타입을 식별하고, 추출 산출물의 type_decls를 **전수** 분류한다 — B-1 §4.4 방식(local/external × 투명/Opaque 전수 표). 투명 타입은 정의와 의미를 폐쇄에 포함하고, Opaque 타입은 대체 계약(손모델·신뢰 가정)을 요구한다(§5).
- **Step 2 — 호출 closure**: 폐쇄에 포함된 본문이 호출하는 함수를 전수 식별한다. 각 호출 함수는 본문을 포함(Structured)하거나 명시적 대체 계약으로 대체한다. 명제에서 도달할 수 없는(호출 경로가 없는) 항목은 제외 후보이며, 제외에는 근거 기록이 필요하다(§5).
- **Step 3 — opaque/external 처리**: 본문을 제외한 모든 항목의 빈자리 계약을 확정한다. 손모델의 최소성은 추측이 아니라 추출 산출물에서 확정되어야 한다 — 선례: B-1 §4.7, "명제가 모델 내부에 의존할 수 없는 구조를 LLBC 서명으로 보장받아 opaque-최소성이 추출 산출물에서 확정된다". 라이브러리가 이미 명시적 모델을 제공하면 그 수용이 대체 계약이 된다(수용한 모델의 identity — 라이브러리 버전·태그·원문 — 는 폐쇄 기록에 포함한다).
- **Step 4 — 폐쇄 기록 (양방향 근거)**: 폐쇄 멤버십에는 포함 근거(명제 → 참조 경로)와 제외 근거(명제가 도달하지 않는 경로)가 **모두** 필요하다. 근거 없는 포함도, 근거 없는 제외도 금지한다. 근거 확인이 불가능하면 §6 fail-closed다.

**결정성**: 동일 입력(명제 집합 + 추출 산출물 identity) → 동일 폐쇄. 폐쇄는 임의 시점에 관측 기록으로부터 재계산·재검증 가능해야 하며, 재계산 결과가 기록과 다르면 그 폐쇄는 수용되지 않는다(§6-F4).

## 5. 폐쇄 규칙 표 (5분류)

대상 5분류와 fail-closed 마지막 행(§6의 표 형태 재현):

| 대상 | 규칙 |
|---|---|
| 명제에 직접 연결되는 코드 | 증명 의무에 포함 |
| 증명에 필요한 호출 함수 | 본문 포함 또는 명시적 계약으로 대체 |
| 필요한 ADT·타입 | 정의와 의미 포함(타입 closure 전수 분석 — B-1 §4.4 방식) |
| opaque/external 항목 | 명시적 손모델·신뢰 가정 요구(모델 없이는 수용 금지) |
| 증명에 무관한 코드 | 근거가 확인되면 제외(제외 근거 기록 의무) |
| 의존성 누락·불확실 | fail-closed(수용 금지) |

- "증명에 필요한"의 판정 기준은 명제에서의 도달 가능성이다 — 명제가 참조하는 서명·본문으로부터 호출 그래프·타입 그래프를 따라 도달하는 항목만 "필요"다.
- "증명에 무관한"의 판정도 동일한 기준이다 — 도달하지 않음이 확인되어야 제외할 수 있고, 확인 기록이 곧 제외 근거다. 도구 출력에 포함되었다는 이유만으로 포함하지 않는다(§7), 도구 출력에 없다는 이유만으로 제외하지도 않는다(§6-F1).

## 6. Fail-closed 조항

다음 각 항목에 해당하는 증명 캡슐은 수용되지 않는다. AGENTS.md §4 GUARDIAN("검증 불가·오래된 증거 = fail closed")의 준용이다.

- **F1 — 의존성 누락·불확실**: 폐쇄에 필요한 항목이 누락되었거나, 참조 경로·멤버십이 불확실하면 수용 금지. "추출 산출물에 없다"는 것은 "증명에 불필요하다"의 근거가 아니다.
- **F2 — 대체 계약 부재**: 본문을 제외한 항목은 그 빈자리를 대신하는 계약(손모델·신뢰 가정)이 명시되지 않으면 수용 불가. "본문이 Opaque라서 뺐다"는 제외 근거가 되지 못한다 — 제외가 아니라 대체 계약의 의무다.
- **F3 — 손모델 과잉 주장**: 손모델의 충실성을 해당 명제의 필요 범위 밖에서 주장하면 그 주장은 극장이다(AGENTS.md §0.9). 필요 범위의 정당화 없이 손모델을 수용하지 않는다.
- **F4 — 오래된·검증 불가 증거**: 폐쇄의 포함·제외 근거로 인용되는 관측은 identity 해시·원문으로 재검증 가능해야 한다. 검증 불가·오래된 증거 = fail-closed.
- **F5 — 추출 능력 기반 범위 확장**: 추출 능력 관측(§7)은 증명 의무 범위의 근거가 아니다. "추출 본문이 늘었다"는 것만으로 폐쇄를 확장하는 계산은 수용 금지.

## 7. 반례 — 추출 능력 관측은 증명 의무 범위가 아니다

**관측 (Gate B §5.7, charon 0.1.304 + `--preset=aeneas`)**: `--extract-opaque-bodies` 변이에서 as_bool 기본 행 fun_decls 22(Structured 1 / Opaque 20 / null 1) → 변이 fun_decls **1525 전부 Structured**, type_decls 241 (LLBC `5a9663421be3f9f576206f46adf23ff7828e9cfa470f2420b000a44623a55eff`). 같은 변이의 aeneas 번역은 exit **1** — 부분 생성(52 errors, 7 unique classes)으로 종료해, 본문 추출 확장은 번역 성공으로 이어지지 않았다.

**규칙**: 이 관측(22→1525 확장 추출)은 **증명 의무 범위의 근거로 사용 금지**다.

1. 폐쇄의 출발점은 명제이지 추출기가 아니다(§4 Step 0). "도구가 추출할 수 있는"과 "증명에 필요한"은 동등하지 않다 — 추출 능력(coverage) ≠ 증명 의무 범위(obligation scope).
2. 관측 기록은 서명·투명성·본문 존재 등 폐쇄 계산의 **입력 데이터**로는 참조할 수 있으나, 범위 확장의 **권위**로는 무권위다 (발견 ≠ 권한 — AGENTS.md §2.2).
3. 대조: B-1의 정식 폐쇄는 확장 추출 없이(기본 최소 추출, B-1 §4.3) 커널 승인·mutation 음성·cold 재현에 도달했다(§8). 확장 추출은 폐쇄의 필요조건도 충분조건도 아니다 — Gate B 변이에서 번역 실패가 오히려 관측됐다.

## 8. B-1 적용 사례 — as_bool에서 이 규칙이 만든 실제 폐쇄

근거: B-1 (docs/evidence/b1_gate_a_minimal_proof_2026-11-04.md §4.3–4.11, §5). 아래 수치는 관측 원문이다.

**입력** — 명제 2절(독립 정의, 구현 역유도 없음, B-1 §4.8):

1. `as_bool_bool_some : ∀ (b : _root_.Bool), value.Value.as_bool (value.Value.Bool b) = ok (some b)`
2. `as_bool_non_bool_none : ∀ (v : value.Value), (∀ b : _root_.Bool, v ≠ value.Value.Bool b) → value.Value.as_bool v = ok none` (6-변형 전체 case analysis)

**계산** — Step 0(명제) → Step 1(타입 closure 전수, B-1 §4.4 type_decls 11개 전수) → Step 2(호출 closure — as_bool 직접 callee 0, B-1 §4.4) → Step 3(opaque 처리) → Step 4(기록).

**폐쇄 (실측)**:

| 폐쇄 성분 | 개수 | 내용 | 근거 |
|---|---|---|---|
| 명제에 직접 연결되는 코드 | fun 1 | `as_bool`(def_id 11, Structured 본체) — fun_decls 21 중 유일한 투명 본체 | B-1 §4.4 |
| 필요한 ADT·타입 | type 11 | type_decls 전수 — local 4(`Value`·`Number`·`N`·`Map`, 투명) · external 투명 3(`Range`·`Global`·`Option`) · external Opaque 4(`String`·`Vec`·`BTreeMap`·`Tuple`) | B-1 §4.4 |
| opaque/external 대체 계약 | 손모델 2 | `F64`(`structure F64 where val : Float` — aeneas 라이브러리에 f64 모델 부재) · `BTreeMap`(`structure … where entries : List (K × V)` — axiom 템플릿 형태 커널 거부) | B-1 §4.7 |
| 제외 | fun 20 | Opaque fun_decls — as_bool 직접 callee 0으로 명제가 참조하지 않음 | B-1 §4.4 |

- **String·Vec의 위치**: 직접 손모델 없이 대체 계약이 성립한 케이스 — `String`은 Aeneas 라이브러리 매핑(Lean core `String`, `body := .opaque`)을, `Vec`은 라이브러리의 computable 모델(`ListN` 기반)을 그대로 수용했다(B-1 §4.7, 재모델링 없음). §4 Step 3의 규칙대로, 수용된 라이브러리 모델의 identity(번들 태그 `nightly-2026.11.03-ab34bd2`)가 폐쇄 기록에 포함된다.
- **손모델 최소성의 근거**: 두 모델 모두 "as_bool 명제가 모델 내부에 의존할 수 없는 구조"(함수가 payload를 읽지 않음)를 LLBC 서명으로 보장받아, opaque-최소성이 추측이 아니라 추출 산출물에서 확정됐다(B-1 §4.7). 일반 map 내용은 명제의 전칭 case analysis가 담당한다(B-1 §4.8).
- **커널 승인 결과**: `#print axioms` → `[propext, Quot.sound]` 양절 — `sorryAx` 0, `Classical.choice` 미사용(B-1 §4.8). 구체 입력 7건 커널 평가·Rust 실행 대조 불일치 0(B-1 §4.9)·mutation 음성(clause 1만 킬, B-1 §4.10)·cold 재현 5축 폐쇄(B-1 §4.11).
- **이 사례가 입증하는 것**: 폐쇄 규칙(명제 출발 계산)이 "증명에 필요한 최소 집합"(fun 1·type 11·손모델 2)을 만들어내며, 그 집합은 도구 출력 크기(fun 21)와 다르고, 확장 추출(§7) 없이도 커널 승인에 충분했다. 폐쇄 크기와 도구 출력 크기의 차이는 규칙 — 무관 코드의 근거 확인 제외(§5) — 이 만든다.

## 9. 참조 (References)

- [docs/evidence/b1_gate_a_minimal_proof_2026-11-04.md](../evidence/b1_gate_a_minimal_proof_2026-11-04.md) — B-1 Gate A 최소 증명 실험 (§4.4 타입 closure 전수 분석, §4.7 손모델, §4.8 독립 명제·커널 승인, §8 적용 사례의 근거)
- [docs/evidence/b1_gate_b_capability_census_2026-11-04.md](../evidence/b1_gate_b_capability_census_2026-11-04.md) — Gate B 능력 census (§5.7 `--extract-opaque-bodies` 22→1525 관측 — §7 반례의 근거)
- [docs/spec/obligation_semantics.md](./obligation_semantics.md) — 심볼 단위 canonical Verification Obligation identity (본 문서와 단위가 다른 상보 계약)
- [docs/spec/hermetic_gate_framework.md](./hermetic_gate_framework.md) — hermetic 게이트 무결성 프레임워크
- AGENTS.md §0.5, §0.9, §0.9b, §0.12, §2.2, §4 — 문서 우선, 극장 금지, 무한 후퇴 종료, 계약 선행, 완료 = 기계 검증, GUARDIAN fail-closed

## Change Log

- **2026-11-04**: v1 — B-2 Stage 1b 사전등록. 폐쇄 출발점(명제)·5분류 규칙·fail-closed 조항·손모델 계약 요건을 B-1/Gate B 관측 근거로 확정.
