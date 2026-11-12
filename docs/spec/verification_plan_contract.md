# VerificationPlan 계약서 (Phase P)

> Phase S(2026-09 승인)의 semantic contract를 코드로 고정한 Phase P 구현 계약.
> SSOT: 본 문서 + `src/core/types/verification_plan.nim` + `src/core/types/execution_witness.nim`
> + `src/verification/selection/verification_plan.nim` + `src/verification/selection/request_oracle.nim`.
> 생성/관측 데이터는 §5 SSOT 규칙에 따라 AGENTS.md나 본 문서에 두지 않는다.

---

## 1. 목적

CI selective-verification 최적화에서 "무엇을 검증해야 하는가"(Requirement decision)와
"그것을 어떻게 만족시킬 것인가"(Execution disposition)를 분리한다.

- **VerificationPlan** = cache/pre-sieve/execution에 독립적인 순수 semantic artifact.
- **ExecutionPlan** = VerificationPlan을 기반으로 cache/pre-sieve를 적용한 cache-dependent artifact.

## 2. 확정된 집합 관계

| 집합 | 의미 | 의존 |
|---|---|---|
| `Universe` | 검증 가능한 전체 커널 영역 | — |
| `Affected(seed, graph)` | 이번 변경/seed가 dependency graph상 영향을 미치는 집합 | seed + graph |
| `Required` | semantic verification obligation decision | scope, obligation, policy |
| `Reusable` / `Fresh` | execution satisfaction classification | cache, pre-sieve |

관계:

```text
Affected ⊆ Universe
Required ⊆ Universe
Executed  ⊆ Required          (execution layer)
Reusable / Fresh ⊆ Required   (execution layer)
```

**Affected와 Required 사이에 inclusion law가 없다.** (Phase A 실측: Affected=5, Required=23 —
교차 관계이며 어느 쪽도 다른 쪽의 부분집합이 아니라고 단정하지 않는다.)

## 3. Required predicate

```text
Required(u, P)
  ⟺ ScopeEligible(u)
  ∧ HasObligation(u)
  ∧ PolicyAllows(u, P)
```

- **Affected(u, S)는 포함하지 않는다** — Required는 seed/change 영향과 무관.
- **dependency-satisfiability는 포함하지 않는다** — dependency BLOCKED/UNRESOLVED는
  execution layer의 별도 dimension. `BLOCKED ≠ NOT_REQUIRED`, `UNKNOWN ≠ SAFE`.
- seedSet은 `affectedUnitIds` 계산에만 사용되고 `requiredUnitIds`에는 영향을 주지 않는다 (INV-1).
- VerificationPlan은 `verifiedSet`을 읽지 않는다 — verified subtraction은 execution-layer concern.

### 3.1 PolicyAllows (budgetCap)

`budgetCap > 0`이면 canonical(sorted) 순서로 처음 `budgetCap`개 유닛만 허용된다.
budget 초과 유닛은 per-unit decision에서 `NOT_REQUIRED` (reason: "policy budget cap exceeded")로
표기되며, `requiredUnitIds`에서 제외된다. — production Plan은 policy-aware이며,
정책-무지 reference oracle(`computeRequiredRequestsFull`)의 부분집합을 산출한다 (P3-3).

## 4. VerificationPlan 구조

```text
VerificationPlan {
  subjectDigest, semanticPolicyDigest, universeDigest,
  affectedUnitIds[],          // seed-dependent
  requiredUnitIds[],          // seed-independent, policy-aware
  perUnitRequirement[{
    unitId, decision (REQUIRED|NOT_REQUIRED|UNRESOLVED), reason }],
  planState (COMPLETE|UNRESOLVED|FAILED),
  semanticModelVersion
}
```

### 4.1 불변식

- **INV-1** RequiredSet은 seed-independent — seedSet을 바꿔도 `requiredUnitIds` 불변.
- **INV-2** `computeVerificationPlan`은 순수 함수 — cache, execution result, scheduler state,
  current wave, mutable vault를 읽지 않는다. 같은 입력 → 같은 PlanDigest.
- **INV-3** `planState == COMPLETE` ⟺ 모든 unit이 REQUIRED/NOT_REQUIRED (UNRESOLVED 0개).
  UNRESOLVED가 하나라도 있으면 `planState = UNRESOLVED` (fail-closed).
- **INV-4** `requiredUnitIds ≡ {u | perUnitRequirement(u).decision == REQUIRED}` (내부 일관성, P3-2).

### 4.2 Digest

```text
subjectDigest        = H(canonical sorted universe)
semanticPolicyDigest = H(budgetCap, fallbackOn)
universeDigest       = H(canonical sorted universe)
```

- `semanticModelVersion`은 semantic model의 버전; planner/toolchain implementation version과 분리.
- SelectionDigest/PlanDigest/ExecutionIdentity/RunResultDigest는 서로 섞지 않는다.

## 5. ExecutionWitness

```text
ExecutionWitness {
  executionIdentity,   // canonical ExecutionIdentity — obligation/identity.nim:252
  prover ("z3"|"lean"),
  invocationId
}
```

- **INV-4(witness)**: `Executed(u)` ⟺ canonical ExecutionIdentity(u)에 귀속된 실제
  prover/solver invocation witness가 존재한다.
- **Result는 독립 domain**: PASS/FAIL/TIMEOUT/ERROR는 witness 존재와 무관하다.
  TIMEOUT/FAIL/ERROR도 EXECUTED일 수 있다. (TC-2)

## 6. P0–P3 테스트 계약 (committed)

| 파일 | 계약 |
|---|---|
| `tests/unit/requirement_decision_test.nim` | TC-1 two-axis: REQUIRED/NOT_REQUIRED + dependency dimension 분리 |
| `tests/unit/execution_witness_test.nim` | TC-2 + INV-4: witness ≠ result |
| `tests/unit/verification_plan_invariants_test.nim` | INV-1..3 |
| `tests/unit/verification_plan_differential_test.nim` | P3: Reference==Production(allow-all), budgetCap 부분집합, seed 독립, per-unit 일관성 |

P0 (fixture, ecdb88bde) → P1 (real types, 6ffa9584e + a15c1ea87) → P3 (differential, 2094a5629).

## 7. Scope / Out of Scope

**Scope**: Semantic planning layer + witness contract. Differential validation.
**Out of Scope (이 문서에서 정의하지 않음)**: execution economics(DAG parallelism),
cache admission, scheduler, ci.yml 변경, T_CI wall-clock benchmark —
Phase X/D 이후 승인 절차에 따른다.

## 8. 변경 이력

- 2026-09: Phase P — VerificationPlan/ExecutionWitness 고정, differential validation 추가.