# Loop BMC Soundness — 고정 깊이 언롤의 건전성 게이트

**Date:** 2026-08-06
**Phase:** 2 (AST soundness)
**Decision:** OPTION ① (architect-approved) — 정적 상한이 감지되고 `<= 10`일 때만
Tier-2 루프를 SMT-eligible로 취급, 그 외에는 정직한 skip.
**소스**:
- `src/verification/ax_classify.nim` — `loopBoundOf`, `isSmtLoopSound`,
  `TierClassification.loopBound`, `classifyFunction`
- `src/core/trusted/ir_to_smt.nim:28` — `const irLoopBmcBound* = 10`
- `src/core/trusted/ir_to_smt_chunk2.nim:176-186` — `buildBmcMatrixFor/While`
- `src/verification/batch_uap/ir_pipeline_runner.nim` — 라우팅 사이트
  (임베디드 게이트, §6)
- `src/core/trusted/axiom_ir.nim` — loopCond/loopStep 타입 재귀 + CAST 파싱

**AGENTS.md 참조**: §0.9 (Theater Prohibition), §0.6 (Static First), §1 (IR Pipeline v31)

---

## 1. 문제 정의: 고정 깊이 언롤은 under-approximation

SMT emitter는 루프를 **고정 깊이**로 언롤한다:

```
src/core/trusted/ir_to_smt.nim:28
  const irLoopBmcBound* = 10

src/core/trusted/ir_to_smt_chunk2.nim:176-186
  buildBmcMatrixFor / buildBmcMatrixWhile  → 최대 10회 언롤
```

`recfun`(재귀 함수 인코딩) 의미론에서, **고정 깊이 `N`에서의 UNSAT는
under-approximation**이다. 즉 "깊이 N까지 반례 없음"은 "전체 실행에서 반례 없음"을
증명하지 **못한다** — 반례가 깊이 N+1 이후에만 존재할 수 있기 때문이다
(Z3 fixed-point / BMC 참조: `recfun`은 `(define-fun-rec)`로 낮춰지며, 유한
언롤 경계는 오직 정확한 상한이 존재할 때만 건전하다).

### 1.1 건전한 패턴

- **depth 증가(증분)**: 깊이를 늘려가며 UNSAT을 재확인 → 고정점이 되면 건전.
- **UNKNOWN**: 경계 밖 잠재 반례가 있음을 인정 → skip.
- **정적 상한 == 정확한 반복 횟수**: 상한이 감지되고 emitter 깊이(`<= 10`) 안에
  들어오면, 정확히 그 횟수만큼 언롤하는 것은 under-approximation이 **아니다** —
  faithful 인코딩이다.

⚠️ **고정 깊이 10에서 UNSAT을 검증으로 제시하는 것은 극장(§0.9)이다**:
루프가 10회를 넘어 반복될 수 있다면, "깊이 10 UNSAT"은 아무것도 보증하지 않는다.

---

## 2. 결정 (OPTION ①)

Tier-2 루프는 **다음 조건을 모두 만족할 때만** SMT-eligible:

1. **정적 상한이 감지**된다 (기호/호출/불확정 형태가 아님).
2. 감지된 상한 `B` 가 **`0 <= B <= 10`** (emitter 고정 깊이 `irLoopBmcBound`).

그 외의 모든 경우(while 루프, 기호 경계, 상한이 10 초과, 초기값 음수, 증가량
`!= 1`, 불확정)는 **정직한 skip** — SMT로 보내지 않는다.

근거: emitter는 정확히 `irLoopBmcBound`회만 언롤하므로, `B <= 10`이면
"B회 언롤"이 under-approximation이 아니다. `B > 10`이면 10회 언롤은
잠재 반례를 놓치므로 거부해야 한다.

---

## 3. 구현: `loopBoundOf` (정적 상한 감지)

`src/verification/ax_classify.nim` — 순수 함수, `{.raises: [].}`.

감지 대상 형태 (`lkFor` 한정):

```
init  = 리터럴  c         (c >= 0)
cond  = i < L  또는 i <= L   (L은 컴파일타임 int64 리터럴)
step  = i + 1              (동일 루프 변수, 리터럴 1)
```

- `i < L`  → `Some(L)`
- `i <= L` → `Some(L+1)` (L+1이 int64에 들어갈 때만, 아니면 None)
- 그 외 형태 → `None` (보수적).

`init >= 0`을 요구하는 이유: 반복 횟수는 `L - c`(또는 `L - c + 1`)이다.
`c < 0`이면 반복이 `L`을 초과하므로 상한 `L`이 unsound해진다.

---

## 4. 구현: `isSmtLoopSound` 와 `TierClassification.loopBound`

```nim
func isSmtLoopSound*(bound: int): bool =
  ## 10 = irLoopBmcBound (src/core/trusted/ir_to_smt.nim:28)
  bound >= 0 and bound <= 10
```

`TierClassification`에 `loopBound*: Option[int]` 추가. `classifyFunction`에서
본문에 `irLoop`가 있으면(tier `vtStructural` 유지):

- `collectLoopBounds`가 본문의 **모든** 루프(중첩 포함)의 상한을 수집.
- 모든 루프가 상한을 갖고 **모두** `<= 10`이면 `loopBound = Some(MIN(bounds))`.
  - MIN을 저장하는 이유: eligibility는 **모든** 루프가 건전해야 하므로, 최소
    상한이 대표값. (MIN이 `<= 10`이어도 다른 루프가 `> 10`이면 None — §4 로직 참조.)
- 루프 중 하나라도 상한 없음/불확정/`> 10`이면 `loopBound = None` (정직 skip).

루프가 없는 본문(기존 심볼)은 `loopBound = None` 유지, tier/reason 불변 → 기존
동작 변경 없음.

---

## 5. 라우팅 사이트 (임베디드 게이트)

`src/verification/batch_uap/ir_pipeline_runner.nim` — `classifyFunction(funcDef)`
직후(=~line 164)에 건전성 게이트 삽입:

```
tier == vtStructural  AND  loopBound == none  → IrPipelineResult(vpBmcSkipped,
  skipped: true, success: true), logInfo "loop bound unresolved — honest skip".
tier == vtStructural  AND  loopBound has Some → Stage 2-4 (SMT)로 통과.
```

이 게이트가 없으면 고정 깊이 10 UNSAT이 건전한 검증으로 오인될 수 있다(극장).
정확한 패치는 §6 및 에이전트 보고서의 "INTEGRATION PATCH" 참조.

---

## 6. 파일:라인 앵커

| 역량 | 위치 |
|------|------|
| 정적 상한 감지 | `src/verification/ax_classify.nim` — `loopBoundOf` |
| 상한 건전성 | `src/verification/ax_classify.nim` — `isSmtLoopSound` |
| 분류 (vtStructural + loopBound) | `src/verification/ax_classify.nim` — `classifyFunction` |
| emitter 고정 깊이 | `src/core/trusted/ir_to_smt.nim:28` |
| 언롤 구현 | `src/core/trusted/ir_to_smt_chunk2.nim:176-186` |
| 라우팅 (임베디드) | `src/verification/batch_uap/ir_pipeline_runner.nim` `classifyFunction` 직후 |

---

## 7. 관련 AST soundness (Phase 2)

- **loopCond/loopStep 타입 재귀**: `axiom_ir.validateExprTypes` irLoop case가
  이제 `loopCond`, `loopStep`을 `loopBody` 이전에 재귀(불균형 해소).
- **CAST 라운드트립**: `parseIRExpr`에 `CAST(<expr>,<from>-><to>)` 파싱 추가,
  `serializeIRFuncDef → deserializeIRFuncDef`가 `castFrom/castTo/castExpr` 보존.