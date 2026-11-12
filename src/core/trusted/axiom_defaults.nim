import core/trusted/layer_declaration
axiomLayer "trusted.core.defaults"

## § 계층별 컴파일 타임 기본값 SSOT
## axiomCoreDefaults: Core 레이어 — 예외 완전 금지
## axiomGateDefaults: Gate 레이어 — CatchableError 허용
## axiomCliDefaults: CLI 레이어 — CatchableError 허용

template axiomCoreDefaults*(body: untyped) =
  {.push raises: [].}
  body
  {.pop.}

template axiomGateDefaults*(body: untyped) =
  {.push raises: [CatchableError].}
  body
  {.pop.}

template axiomCliDefaults*(body: untyped) =
  {.push raises: [CatchableError].}
  body
  {.pop.}
