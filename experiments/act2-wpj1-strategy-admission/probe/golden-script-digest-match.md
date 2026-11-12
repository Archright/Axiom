# WP4-j.1 Phase D — Golden Script Digest Match (결정적 실증)

- 날짜: 2026-08-30
- 실험 ID: ACT2-WP4j1, Phase D
- Axiom rev: 44fefd470 (working tree, Phase C/D는 src 무변경), Subject rev: c75502c

## 질문

E2E에서 getBitsBE의 golden obligation 스크립트는 정확히 무엇이었고, Z3의 `sat` 결과는
진짜 counterexample인가 아니면 underconstrained 인코딩의 자명한 결과인가?

## 방법 (read-only)

1. **차등 telemetry 실험**: 동일 state에서 target만 바꿔 실행
   - Run B (`--target stew/bitops2.nim::getBitsBE`): telemetry +11 lines
   - Run E (`--target src/core/orchestrator/orchestrator_api.nim::normalizeMaxWorkers`): telemetry +9 lines, exit 0
   - digest 집합 비교: 9개 공통(커널 귀속), **2개가 getBitsBE 전용**:
     - `d067de0283743d9117ac7a7e900452bd6d7a0fab013e734e2a519ac087e30742` — result=**sat**
     - `d9f9af27c1dfa8b3b41d266f54e1850142587bf0e03c7d112dea3eb05d0588b4` — result=**sat**
   - (Run C/D 시도: `firstOneNim`은 overload 모호성, `countOnes`는 elNoObligation으로
     fail-closed 거부 — canonical target exact-1-match 규칙의 정상 동작)

2. **스크립트 재구성** (`tests/unit/wpj1_golden_script_repro.nim`):
   `semantic_target_extractor.nim:156`가 만드는 동일한 proposition IRExpr —
   `uoNot(boEq(irVar("resultBits", BitVec64), irLit(0)))` — 을 동일 lowering primitive
   (`lowerObligationToSmt`)으로 내리고 `buildZ3QueryEnvelope`로 digest를 계산해 대조.

## 결과

### 일치 (gold-standard)

QF_AUFBV + zmRaw 조합의 digest가 관측값과 **정확히 일치**:

```
(set-logic QF_AUFBV)
(set-option :rlimit 30000000)
(declare-fun resultBits () (_ BitVec 64))
(assert (not (not (= resultBits #x0000000000000000))))
(check-sat)
```

- digest zmRaw(QF_AUFBV) = `d9f9af27c1dfa8b3...` = E2E에서 관측된 getBitsBE 전용 호출, result=**sat**
- 따라서 E2E에서 실행된 golden 스크립트가 비트 단위로 이것임이 실증됨.

### 해석

이 스크립트는 `resultBits`를 **어떤 제약도 없는 자유 BitVec64 변수**로 선언한다.
`(assert (not (not (= resultBits 0))))`는 이중 부정이 상쇄되어 실질적으로
`(assert (= resultBits 0))`이며, 자유변수 모델 `resultBits := 0`이 항상 존재하므로
**Z3의 sat는 구조적으로 자명하다**.

subject(nim-stew bitops2.nim:576)에서 `resultBits`는 다음과 같다:

```nim
const resultBits = sizeof(result) * 8   # 컴파일 타임 상수, 항상 ≥ 8
```

즉 subject의 나눗셈 `a div resultBits`는 0으로 나눌 수 없다(안전). Z3의 sat는
subject의 도달 가능한 상태를 가리키는 것이 아니라, **상수 전파/가정 바인딩 없이
기호화된 proposition을 자유변수로 lower한 인코딩 아티팩트**다.

### 미귀속 1건 (정직 기록)

두 번째 getBitsBE 전용 digest `d067de02...`(result=sat)는 8가지 후보 framing
(2 logic × 2 mode × proofs on/off) 중 어느 것과도 일치하지 않았다. 가장 유력한
추정은 classic adapter(`irToSmtScript`)의 전체 함수 스크립트를 실행한 별도 호출이며,
이 경우에도 파라미터가 무제약이므로 sat가 자명하다. 정확한 재구성에는 E2E funcDef IR가
필요하므로 **partial attribution**으로 남긴다.

## 귀속 (AGENTS.md §10)

- 이것은 subject 결함이 아니다 (subject의 해당 나눗셈은 안전).
- 인프라/툴체인 결함이 아니다 (Z3는 정확히 동작했다).
- **Axiom capability 경계**: obligation proposition lowering에 상수 전포/가정
  바인딩이 없어, 컴파일 타임 상수 divisor에 대한 안전 사실이 자명하게 반박 가능한
  형태로 인코딩된다. 분류상 결과는 `Vacuous`(sat 방향의 반박은 무의미)이며,
  psFail은 이 underconstrained 인코딩에 대한 정직한 fail-closed다.
