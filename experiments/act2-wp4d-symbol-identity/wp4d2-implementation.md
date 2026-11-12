# WP4-d-2 — resolveCallTarget generalization (구현 기록)

EXPERIMENT_ID=act2-wp4d-symbol-identity
SUB_TASK=WP4-d-2
DATE=2026-08-28

## 목적

WP4-d-1 에서 func `getBitsBE` 와 template `getBitsBE` 가 같은
SorterNodeId(`modulePath::functionName`) 를 공유하는 상황에서, dependency
resolution 이 둘을 구분하지 못하고 **첫 번째 후보를 임의로 선택**하던 문제를
제거한다. 임의 선택은 false self-dependency 와 잘못된 dependency edge 를
유발할 수 있는 근원이었다.

## 핵심 원칙 (변경 불가)

- SorterNodeId(ScopeIdentity) = `modulePath::functionName` 은 **외부 계약 identity**. 불변 유지.
- 호출 사이트(`rawCallTargets`) 는 **이름만** 담고 있으므로, 같은 모듈에
  func+template 같은 이름 후보가 여럿 공존하면 어느 쪽을 의도하는지 판별할
  **정의적 근거가 없다**. 따라서 임의 선택 대신 **명시적 rrAmbiguous** 로 귀결.
- rrAmbiguous/rrUnresolved 시 의존성 edge 를 **추가하지 않음** (안전 보존).

## 변경 파일 목록 (2개 + 신규 테스트 1개)

### src/core/topology/topology_dependency.nim
- `ResolutionKind*` enum 추가: `rrUnique` / `rrAmbiguous` / `rrUnresolved`
- `ResolutionResult*` object 추가:
  ```nim
  kind*: ResolutionKind
  resolvedIdx*: int       ## rrUnique 일 때 유효
  candidates*: seq[int]   ## rrAmbiguous 일 때 후보 목록
  ```
- `resolveCallTarget` 반환 타입을 `int` → `ResolutionResult` 로 변경.
  `-1` 반환 완전 제거.
- 결정 로직:
  - 후보 0개 → `rrUnresolved`
  - sameModule 후보 1개 → `rrUnique(resolvedIdx)`
  - sameModule 후보 2+개 → `rrAmbiguous(candidates)`
  - sameModule 없음 (다른 모듈에만 존재) → `rrUnresolved`

### src/core/topology/topology_engine.nim (호출점, line 45-47)
- 기존: `let resolvedIdx = resolveCallTarget(...); if resolvedIdx >= 0 and resolvedIdx != idx`
- 수정: `let res = resolveCallTarget(...); if res.kind == rrUnique and res.resolvedIdx != idx`
- rrAmbiguous/rrUnresolved 시 dependency 추가 안 함.

### tests/unit/topology_resolution_result_test.nim (신규)
- 7개 케이스, 모두 PASS:
  1. 후보 0개 → rrUnresolved
  2. 후보 1개 → rrUnique + 정확한 idx
  3. 같은 module 같은 name func+template → rrAmbiguous + candidates==2
  4. 후보 2개 중 정확히 1개만 같은 module → rrUnique (모듈 우선)
  5. rrAmbiguous → buildTopologyAnalysis 에서 의존성 edge 미추가
  6. rrUnresolved → buildTopologyAnalysis 에서 의존성 edge 미추가
  7. rrUnique → buildTopologyAnalysis 에서 의존성 edge 정상 추가

## 검증 결과

- 신규 테스트: `AXIOM_CI_PRESERVE_CACHE=1 nim c -r --hints:off -o:/tmp/opencode/ax-resolution-test tests/unit/topology_resolution_result_test.nim`
  → **7 / 7 PASS**
- 기존 회귀 (직접 재실행):
  - topology_engine_test.nim → 4 / 4 PASS
  - topology_types_test.nim → 20 / 20 PASS
  - frontier_target_selection_test.nim → 5 / 5 PASS
  - sorter_core_test.nim → 17 / 17 PASS
- 빌드: `make build` → bin/ax 생성 성공.
- Zero-drift: 단일 후보/단일 module 케이스에서 이전과 동일 결과 산출.

## 남은 미해결 (Open Issue — 별도 문서화)

호출 사이트가 이름만 담아 시그니처 기반 semantic resolution 이 불가능한 한계.
→ `wp4d-open-issue-callsite-signature-resolution.md` 로 기록.
AA: func/template 공존 시 rrAmbiguous → edge 누락될 수 있으나 **안전하게 방어됨**.
