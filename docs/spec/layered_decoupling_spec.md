# Layered Decoupling Specification

> SSOT for "Base-Macro Layered Decoupling" pattern and Package-Root Absolute Addressing.
> Context7 validated: Nim `export` forwarding, Refactoring Guru "Extract Class", `switch("path", "src")`.

---

## 1. 패턴 정의: Base-Macro Layered Decoupling

순환 참조가 있는 모듈을 3계층으로 분리하여 선형 의존성 그래프를 만든다.

```
gateway_types.nim          ← 최하단: 순수 데이터 구조 (타입, 상수, enum)
  ↑
gateway_macros.nim          ← 중간: 타입 + domain_types + results만 의존
  ↑
gateway.nim (facade)        ← 최상단: re-export만, consumer 변경 불필요
```

### 적용 사례: `src/core/gateway/gateway.nim`

**Before**: 타입 + 매크로 + 함수 + re-export가 한 파일에 혼재. `gateway_constraint.nim`과 순환 참조.

**After**:
| 파일 | 내용 | 의존성 |
|------|------|--------|
| `gateway_types.nim` | `ConstraintDefinition`, `TypeConstraint`, `maxStateValue` 등 7 타입 + 2 상수 | `domain_types`, `results`, `options` |
| `gateway_macros.nim` | `makeGateway`, `makeEnumGateway`, `lowerFirstAscii` | `domain_types`, `results`, `macros` |
| `gateway.nim` | re-export facade | `gateway_types`, `gateway_macros`, `gateway_helpers`, `gateway_main`, `gateway_constraint`, `gateway_json` |

**결과**: `gateway_constraint.nim`이 `gateway_types`만 import → 순환 참조 해소.

---

## 2. Package-Root Absolute Addressing

### 원칙
모든 import는 `src/`를 기준으로 한 절대 경로를 사용한다.

```nim
# ✅ 올바른 패턴 (이동 불변성)
import core/proof/proof_budget
import verification/cegar_engine
import gate/nimtry/nimtry_cli

# ❌ 잘못된 패턴 (이동 시 깨짐)
import ../core/proof_budget      # 상대 경로
import ./sibling_module          # 같은 디렉토리 상대 경로
import bare_module_name          # bare import (동일 디렉토리 의존)
```

### 설정
`config.nims`에 이미 설정됨:
```nim
switch("path", "src")       # core/X, verification/X, gate/X 등 절대 경로 지원
switch("path", "tests/gateway")
```

### 이동 불변성 (Location Invariance)
파일이 어떤 하위 디렉토리로 이동하더라도, 파일 내부의 import 선언문은 변경 불필요.

```
# 이동 전: src/core/proof_budget.nim
import core/domain_types     # ← 이 경로는 이동 후에도 동일

# 이동 후: src/core/proof/proof_budget.nim
import core/domain_types     # ← 여전히 유효 (config.nims의 path("src") 덕분)
```

---

## 3. domain_layout.json SSOT

### 위치
`src/core/domain_layout.json` (v2.0, 27 domains)

### 구조
```json
{
  "version": "2.0.0",
  "import_base": "core",
  "root_primitives": ["domain_types", "constants", "results", "metrics", "layer_guard"],
  "domains": {
    "json": {
      "prefix": ["json_"],
      "import_path": "core/json",
      "description": "JSON utilities"
    }
  }
}
```

### 도구
~~`bin/refactor-domain`~~ — ~~이 파일을 읽어서 자동 실행~~ **[DEPRECATED]** (deleted 2026-07-07 per Language Ban; 이 도구는 제거되어 더 이상 실행되지 않음 — 도메인 레이아웃 검증은 `architecture_invariants.nim` 컴파일 타임으로 대체):
- ~~`--dry-run`~~: ~~시뮬레이션 (temp 디렉토리에서 nim check)~~
- ~~`--execute`~~: ~~실제 이동 + import 갱인~~
- ~~`--domain=X`~~: ~~특정 도메인만 처리~~

---

## 4. 검증 루프 (4단계)

각 도메인 이동/전환 후 반드시 실행:

```
1. nim c --hints:off -d:<moved_files>     # 이동된 파일 컴파일
2. nim c --hints:off <consumer_files>                        # consumer 파일 컴파일
3. src/gate/nimtry/nimtry_cli.nim src/core/ 2>&1 | grep -i 'violation'           # nimtry 의존성 그래프 검증
4. git commit                                                 # 체크포인트
```

---

## 5. 골든 룰

1. **스냅샷 없이 시작 금지**: `git tag pre-refactor-snapshot` 후 시작
2. **도메인 단위 점진적 전환**: 전체 일괄 금지, ~~`refactor-domain --domain=X`~~ 단위로 ([DEPRECATED] deleted 2026-07-07)
3. **nimtry 쿼리 필수**: 상대→절대 전환 후 누락 import 즉시 감지

## 6. Persona Boundary Rule

`src/personas/*.nim` MUST import core/ only through `core/boundary/persona_boundary.nim`. Direct imports from `core/types/*`, `core/logic/*`, `core/gateway/*`, etc. are violations. Enforced by `import-encapsulation-gate`.
