# Nim 2.2.10 json.getOrDefault nil Quirk (DEBT#393)

## 증상 (Symptom)

`JsonNode.getOrDefault(key)`로 키가 없는 필드를 조회하면 `nil`을 반환한다.
반환값에 `.kind`를 직접 접근하면 SIGSEGV가 발생한다:

```nim
let vcs = item.getOrDefault("vcs")   # 키가 없으면 nil
if vcs.kind == JObject:              # SIGSEGV: read from nil
  discard
```

## 근본 원인 (Root Cause)

Nim 2.2.10 `lib/pure/json.nim`의 `getOrDefault` 시그니처:

```nim
proc getOrDefault*(node: JsonNode, key: string): JsonNode =
  ## Gets a field from a `node`. If `node` is nil or not an object or
  ## value at `key` does not exist, returns nil
  if not isNil(node) and node.kind == JObject:
    result = node.fields.getOrDefault(key)
  else:
    result = nil
```

기본값(default) 파라미터가 없으며 **항상 nil**을 반환한다. `.getStr("")`, `.getInt(0)`은 내부적으로 nil-safe하지만, `.kind`/`.fields`/`.len` 직접 접근은 nil 역참조 크래시를 일으킨다.

## 안전 패턴 (Safe Patterns)

```nim
# 패턴 1: nil 가드
let vcs = item.getOrDefault("vcs")
if not vcs.isNil and vcs.kind == JObject:
  discard

# 패턴 2: hasKey 가드 (키 존재가 확인되면 안전)
if item.hasKey("vcs") and item.getOrDefault("vcs").kind == JObject:
  discard

# 패턴 3: [] 직접 접근 (JObject 타입 확정 시)
if item.kind == JObject and item.hasKey("vcs"):
  let vcs = item["vcs"]
```

## 영향 범위 (Impact)

프로젝트 전역 877개 `getOrDefault` 사용처 중 대부분은 `.getStr("")`/`.getInt(0)` 체이닝으로 nil-safe하다.
`.kind` 직접 접근 패턴: `grep -rn "getOrDefault(.*)\.kind" src/ tools/` — hasKey 가드 없는 사용처만 위험
(현재 확인된 위험 사용처는 수정 완료: `tools/ci/ci_health_checker.nim`).

## 참조 (References)

- 수정: `tools/ci/ci_health_checker.nim` parseCircleCiPipelines (nil 가드 추가)
- 표준 라이브러리: Nim 2.2.10 `lib/pure/json.nim` getOrDefault
