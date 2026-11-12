# Nim `{.deprecated.}` Enum Field Pragma Quirk

## 증상 (Symptom)

Nim 2.2.10에서 `{.deprecated: "message".}` (문자열 메시지 포함 형태)를
**enum 값(field)**에 적용하면 컴파일 에러가 발생한다:

```nim
type SmtLogic* = enum
  slQfAxDeprecated {.deprecated: "Use slQfAufbv instead".}  # ← Error
```

```
Error: annotation to deprecated not supported here
```

## 원인 (Root Cause)

Nim 컴파일러에서 `{.deprecated: "message".}` 문자열 메시지 형태는
`proc`, `type`, `var` 등 **최상위 선언(top-level declaration)**에만
지원된다. `enum` 값(필드)은 이 메시지 형태를 지원하지 않으며,
**bare `{.deprecated.}`** (메시지 없음)만 허용된다.

## 해결책 (Workaround)

```nim
type SmtLogic* = enum
  slQfAxDeprecated {.deprecated.}  ## 설명은 doc comment에 기록
  slQfAufbv
```

설명 메시지는 `##` doc comment에 기록한다.

## 영향 범위 (Impact)

- `src/core/types/smt_types.nim:14` — `slQfAxDeprecated` enum 값
- `src/core/logic/smt_logic.nim:27,38` — `case` arm에서 사용 시
  `Warning: slQfAxDeprecated is deprecated [Deprecated]` 경고 발생
  (컴파일 에러 아님, 빌드 성공)

## 발견 (Discovered)

2026-08-10, Axiom 이슈 A (`slQfAxDeprecated` rename) 구현 중 발견.
AGENTS.md §0.5b에 따라 문서화.

## 참고 (References)

- AGENTS.md §0.5b (Quirk Documentation Mandate)
- `src/core/types/smt_types.nim:14`
- `src/core/logic/smt_logic.nim:27,38`