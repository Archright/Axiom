# nimtry 규칙 제안서: 동시성 정책 자동 검증

> **상태**: 제안 (Proposal) — 구현 전 검토 필요
> **근거**: `docs/spec/concurrency_policy.md` + `AGENTS.md` §0.6a

---

## 규칙 1: `acyclic_missing` (Warning)

### 목적
순환 참조가 불가능한 `ref object`에 `{.acyclic.}` 누락 시 경고.

### 검증 로직
```pseudocode
for each file in changed_files:
  for each type declaration in file:
    if type is "ref object" or "ref object of X":
      if type has {.acyclic.} pragma:
        PASS
      elif type is in async context (parent file imports asyncdispatch):
        SKIP (async may create cycles)
      elif type inherits from RootObj AND has no ref fields:
        WARN: "consider {.acyclic.} — no ref fields, method dispatch only"
      elif type has only value-type fields:
        WARN: "consider {.acyclic.} — all fields are value types"
      else:
        PASS (has ref fields, may form cycles)
```

### 예외 처리
- `lean_lsp.nim`의 타입: async 컨텍스트이므로 검증 제외
- `RootObj`를 상속하는 타입: method dispatch용이므로 `{.acyclic.}` 적용 가능
- `ref object` 필드가 있는 타입: 순환 가능성이 있으므로 경고하지 않음

### 구현 위치
`src/gate/nimtry/ssot_queries.nim` 또는 `src/gate/nimtry/solid_queries.nim`

### 우선순위
Low — 경고 수준. 에이전트에게 `{.acyclic.}` 적용을 상기시키는 용도.

---

## 규칙 2: `spawn_ref_capture` (Error)

### 목적
malebolgia `spawn`에 `ref object`를 전달하는 코드를 컴파일 타임에 차단.

### 검증 로직
```pseudocode
# malebolgia가 allowed_imports.lock에 등록된 경우에만 활성화
if "malebolgia" not in allowed_imports.lock:
  SKIP

for each file in changed_files:
  if file imports malebolgia:
    for each spawn call in file:
      if spawn argument type is ref object or contains ref fields:
        ERROR: "malebolgia spawn with ref object is forbidden — use value types"
```

### 예외 처리
- `ptr` 타입은 이미 별도로 검증됨 (Nim 컴파일러의 gcsafe 검증)
- `Locker[T]`로 래핑된 타입은 허용 (malebolgia의 안전한 공유 메커니즘)

### 구현 위치
`src/gate/nimtry/solid_queries.nim`

### 우선순위
Medium — 에러 수준. malebolgia 재도입 시 필수적 안전장치.

---

## 테스트 케이스

### acyclic_missing 테스트
```nim
# tests/unit/nimtry_fixtures/acyclic_violation.nim
type
  BadRef = ref object  # {.acyclic.} 누락 → 경고
    name: string
    children: seq[BadRef]

  GoodRef {.acyclic.} = ref object  # OK
    name: string
    children: seq[GoodRef]

  AsyncRef = ref object  # async 컨텍스트 → 검증 제외
    data: string
```

### spawn_ref_capture 테스트
```nim
# tests/unit/nimtry_fixtures/spawn_ref_violation.nim
import malebolgia

type
  MyRef = ref object
    value: int

proc process(item: MyRef) {.gcsafe.} =  # ref 전달 → 에러
  echo item.value

var master = createMaster()
master.spawn process(MyRef(value: 42))  # 에러!
```
