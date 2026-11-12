# nim check의 고유한 가치

## Status: Implemented ✅

---

## 📋 개요

nim check는 Nim 컴파일러의 시맨틱 분석만 수행하는 도구입니다.
func 전환 시도와 비교하여 고유한 가치를 제공합니다.

---

## 🎯 nim check의 고유한 가치 (5가지)

### 1. 파일 전체 분석 (Batch Analysis)

**설명**: nim check는 파일 전체를 한 번에 분석. 여러 proc을 한 번에 분석하므로 효율적.

**func 전환 시도와의 차이**:
- nim check: 파일 전체를 한 번에 분석
- func 전환 시도: proc 단위로 변환해야 하므로 비효율적

**근거**: Context7 문서: "semantic analysis only"

### 2. 안전성 (Safety)

**설명**: nim check는 실제 코드를 변경하지 않음. 실패해도 코드에 영향을 주지 않음.

**func 전환 시도와의 차이**:
- nim check: 소스코드 변경 없음, 복원 필요 없음
- func 전환 시도: 코드를 변경해야 하므로 위험. 실패 시 복원 필요

**근거**: Context7 문서: "skip codegen"

### 3. 상세한 추론 결과 (Detailed Inference)

**설명**: `{.effects.}` pragma로 추론 과정을 확인할 수 있음. 왜 side effect가 있는지 설명 가능.

**func 전환 시도와의 차이**:
- nim check: 추론 과정 확인 가능, 왜 side effect가 있는지 설명
- func 전환 시도: 성공/실패만 알려줌. 왜 실패했는지 설명 불가

**근거**: Context7 문서: "effects pragma for effect analysis debugging"

### 4. JSON 출력 (Machine-Readable Output)

**설명**: `--output:json` 옵션으로 기계 판독 가능한 출력 가능. 자동화 파이프라인에 통합 가능.

**func 전환 시도와의 차이**:
- nim check: JSON 출력 가능, 자동화 파이프라인에 통합
- func 전환 시도: 텍스트 출력만 가능

**근거**: Context7 문서: "write output to JSON"

### 5. 증분 컴파일 (Incremental Compilation)

**설명**: nim check는 증분 컴파일 지원. 변경된 파일만 다시 분석.

**func 전환 시도와의 차이**:
- nim check: 증분 컴파일 지원, 변경된 파일만 다시 분석
- func 전환 시도: 매번 전체 컴파일 필요

**근거**: Context7 문서: "incremental compilation"

---

## 🔍 nim check와 func 전환 시도的本质的 차이

| 구분 | nim check | func 전환 시도 |
|------|-----------|---------------|
| **질문** | "이 proc은 side effect가 있는가?" | "이 proc을 func으로 변환할 수 있는가?" |
| **접근 방식** | 분석 (analysis) | 검증 (verification) |
| **코드 변경** | ❌ 변경 없음 | ✅ 변경 필요 |
| **정확성** | 추론 기반 (오류 가능성) | 검증 기반 (100% 정확) |
| **속도** | 빠름 (증분 컴파일) | 느림 (전체 컴파일) |
| **안전성** | 안전 | 위험 (복원 필요) |

---

## 💡 3-Layer 방어막의合理性

### Layer 1: nimtry (빠른 필터링)
- **속도**: ms 단위
- **역할**: 후보 proc 식별
- **고유 가치**: 그래프 경로 제공, 장애 허용

### Layer 2: nim check (안전한 분석)
- **속도**: 초 단위 (증분 컴파일)
- **역할**: side effect 추론
- **고유 가치**: 파일 전체 분석, 안전성, 상세한 추론 결과

### Layer 3: func 전환 시도 (정확한 검증)
- **속도**: 초 단위 (전체 컴파일)
- **역할**: 최종 검증
- **고유 가치**: 100% 정확성, 명확한 에러 메시지

---

## 🎯 결론

**3-Layer 방어막은 중복이 아닙니다.** 각 레이어가 고유한 가치를 제공합니다:

1. **nimtry**: 빠른 필터링으로 후보를 좁힘
2. **nim check**: 안전하게 side effect를 추론
3. **func 전환 시도**: 정확하게 검증

**nim check는 소스코드를 변경하지 않으므로 "안전"합니다. func 전환 시도는 소스코드를 변경하므로 "위험"할 수 있지만, 백업과 복원 메커니즘으로 완화할 수 있습니다.**

---

## 📚 References

### Context7 공식 문서
1. **nim check**: 시맨틱 분석만 수행, 증분 컴파일 지원
2. **`{.effects.}` pragma**: 추론 과정 확인 가능
3. **`checkForSideEffects`**: 컴파일러의 side effect 분석 함수
4. **`TSideEffectAnalysis`**: `seUnknown, seSideEffect, seNoSideEffect`

### 프로젝트 문서
- AGENTS.md §0.5b: Quirk Documentation Mandate
- `docs/spec/nim_effect_system_quirks.md`: 기존 quirk 문서화 패턴
- `docs/spec/nimtry_transitive_proc_purity.md`: proc purity 분석 문서
