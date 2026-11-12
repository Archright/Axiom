# Phase 14: Symbolic Test Synthesis Engine

## Objective

Phase 14의 핵심 목표는 **Phase 11/12에서 추출된 Axiom IR 제약 조건식을 SMT Solver(Z3)에 입력하여 경계 조건(Boundary Conditions)을 결정론적으로 역산해내는 '심볼릭 테스트 합성(Symbolic Test Synthesis)' 엔진을 구축하는 것**이다.

## Motivation

현재 `bin/pbt_generator`가 무작위 값을 대입하는 저품질 테스트를 생성한다. 이 접근법은:
- 경계 조건(0, -1, MAX_INT 등)을 보장하지 못함
- IR 전제조건(`preConditions` — `contract_synthesis.nim`이 생성)을 활용하지 못함
- 복잡한 제약식에서 유효 입력을 찾지 못함

## Proposed Solution

### Core Mechanism

1. **IR → SMT-LIB Forward Path** (이미 존재): `ir_to_smt.nim`이 IR을 SMT-LIB으로 변환
2. **SMT → Test Input Reverse Path** (신규): Z3에 `sat` 모델을 요청하여 유효 입력값 역산
3. **Boundary Condition Extraction**: `contract_synthesis.nim`의 division guard + index bounds → Z3가 경계 조건 탐색

### Architecture

```
IR Function Definition
    ↓
contract_synthesis.nim → preConditions (division guards, index bounds)
    ↓
ir_to_smt.nim → SMT-LIB constraints
    ↓
Z3 Solver → sat model (if satisfiable)
    ↓
Model Extraction → Nim test input values
    ↓
pbt_generator.nim → High-precision test cases
```

### Target Coverage

- Gate layer 12 untested modules (M3 from Phase 13 survey)
- Current coverage: 15.4% (137/890 modules)
- Target coverage: 60%+ (534+ modules)

### Key Components

| Component | Source | Status |
|-----------|--------|--------|
| IR constraints | `contract_synthesis.nim` | ✅ Phase 12 |
| IR → SMT-LIB | `ir_to_smt.nim` | ✅ Existing |
| Z3 solver | `z3_pool_exec.nim` | ✅ Existing |
| SMT model extraction | `z3_solver_wrapper.nim` | 🆕 Phase 14 |
| Test case generation | `tools/pbt_generator.nim` | 🆕 Phase 14 |
| Coverage measurement | `tools/measure_coverage.nim` | ✅ Existing |

### Dependencies

- C1 (Test Coverage 15.4% → 60%+)
- M3 (12 untested API modules)
- Phase 12 IR pipeline (contract_synthesis + ir_inline_pass)

## Status

**Status**: Planned — Phase 14 execution pending Phase 13 completion.
