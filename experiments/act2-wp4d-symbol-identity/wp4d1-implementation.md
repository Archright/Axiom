# WP4-d-1 — definitionFingerprint additive discriminator (구현 기록)

EXPERIMENT_ID=act2-wp4d-symbol-identity
SUB_TASK=WP4-d-1
DATE=2026-08-28

## 목적

nim-stew 외부 프로젝트에서 `func getBitsBE`와 `template getBitsBE`가 같은
SorterNodeId(`modulePath::functionName`)를 가지는 스캐너 충돌을 분리한다.
WP4-d-0에서 함수형 심볼 선언 텍스트(decl-text) digest가 둘을 완벽히 분리함을
실측 판정했고, WP4-d-1은 이를 **additive** `definitionFingerprint` 필드로
데이터 계층에 materialize한다.

## 핵심 분리 (변경 불가)

- SorterNodeId(ScopeIdentity) = `modulePath::functionName` 은 **외부 계약 identity**. 이번 WP에서 **불변 유지** (nodeId 계산 경로 변경 없음).
- DefinitionIdentity = SorterNodeId + definitionFingerprint 는 **topology 전용 내부 discriminator**.

## 변경 파일 목록 (6개)

### src/core/topology/topology_types.nim
- `DeclParseResult` 에 `signatureText*: string` 추가 (line 73)
- `TopologySymbol` 에 `definitionFingerprint*: string` 추가 (line 32)

### src/core/topology/topology_parser.nim
- `detectKeywordDeclaration` Nim 키워드 경로에서 `result.signatureText` 채움 (line 134-137):
  - `=` 가 있으면 시그니처 = `trimmed[0 ..< bodyEq]` (body 제외)
  - `=` 가 없으면 시그니처 = `trimmed.strip()`
- 이를 통해 func(3-param)와 template(2-param)이 서로 다른 signatureText 산출

### src/core/topology/topology_symbol_scanner.nim
- `beginTopologySymbol` 에서 fingerprint 계산 (line 31-32, 51):
  ```nim
  let fingerprintInput = modulePath & "||" & parsed.functionName & "||" & parsed.signatureText
  let defFingerprint = sha256Hex(fingerprintInput)
  ```
  → `TopologySymbol.definitionFingerprint` 에 저장
- **nodeId (line 37)는 변경 없음**: 여전히 `sorterNodeId(modulePath & "::" & parsed.functionName)`
- `sha256Hex` import 추가 (core/crypto/hash_kernel)

### src/core/sorter/sorter_core_index_base.nim
- `SorterNode` 에 `definitionFingerprint*: string` 추가 (line 34)
- `makeSorterNode` 에 `definitionFingerprint: string = ""` 파라미터 추가 (line 101) — **기본값 필수** (기존 호출자 보존)
- SorterNode 생성자에 전달 (line 111)

### src/core/topology/topology_engine.nim
- `buildTopologyAnalysis` 의 makeSorterNode 호출 2곳(line 41, 48)에 `symbol.definitionFingerprint` 전달
- JSON round-trip: `topologySymbolToJson` (+필드), `jsonToTopologySymbol` (+getStr fallback, line 205)
- incremental `CachedTopologySymbol` ↔ `TopologySymbol` 3곳(line 365, 400, 426)에 필드 전달

### src/core/topology/merkle_cache.nim
- `CachedTopologySymbol` 에 `definitionFingerprint*: string` 추가 (line 55)
- `entryToJson` (+필드, line 169), `jsonToEntry` (optional read, 기본 "" 로 backward-compatible, line 251-254, 270)

## 검증 결과

### 1. 빌드
`make build` → `nim c --hints:off -d:allowMissingZ3 -o:bin/ax src/cli/main.nim` → **✅ Build successful**
(모든 topology 코드가 bin/ax 에 transitively 컴파일 — 가장 강한 컴파일 보장)

### 2. 신규 유닛테스트: tests/unit/topology_definition_fingerprint_test.nim
- `func getBitsBE* (3-param)` vs `template getBitsBE* (2-param)` → **다른 fingerprint, 같은 nodeId** ✅
- 동일 시그니처 → 동일 fingerprint (결정론) ✅
- 다른 modulePath → 다른 fingerprint ✅
- (nodeId 문자열 = `stew/bits.nim::getBitsBE` 로 SorterNodeId 불변 확인)

### 3. 기존 유닛테스트 회귀 (전부 PASS)
- `topology_engine_test.nim` — 4 OK ✅
- `topology_types_test.nim` — 18 OK ✅
- `frontier_target_selection_test.nim` — 5 OK ✅
- `sorter_core_test.nim` — 21 OK ✅
- `topology_cache_test.nim` — standalone compile fail (`cannot open: core/file_utils`). **사전 존재**:
  파일 diff 0 (본 WP가 이 파일을 건드리지 않음), canonical `TESTS_FAST_UNIT` 에 포함되지 않음,
  import-resolve 문제로 WP4-d-1과 무관.

### 4. SorterNodeId 불변 확인
테스트에서 func/template 동일 module::functionName → 같은 nodeId 검증 완료.
nodeId 계산 경로(`sorterNodeId(module & "::" & name)`) 변경 없음.

### 5. fingerprint 상이 확인
func(3-param) / template(2-param) 이 서로 다른 sha256(64 hex) digest 산출 확인.
(WP4-d-0의 decl-text discriminator가 데이터 계층에 materialize됨)

## zero-drift

- 모든 변경은 **추가(additive) 필드 + 기본값 파라미터 + optional JSON field** 로만 이루어짐.
- 기존 동작 경로(parse → symbol → nodeId → dependency → frontier) 에는 영향 없음.
- bin/ax 빌드 성공 + 4개 기존 유닛테스트 PASS 로 zero-drift 확인.

## 결정론

fingerprint = sha256(modulePath || "||" || functionName || "||" || signatureText)
- 순서 고정, 구분자 고정 → 동일 입력 = 동일 digest.
- 물리경로/타임스탬프 미포함 → canonical identity에 물리경로가 들어가지 않음 (AGENTS.md §12, §15 일치).

## 산출물

- 코드 변경: 위 6개 파일
- 유닛테스트: `tests/unit/topology_definition_fingerprint_test.nim`
- 본 문서: `wp4d1-implementation.md`

## 다음 (WP4-d-2)

`resolveCallTarget` (topology_dependency.nim) 를 `ResolutionResult` enum 으로 일반화 —
definitionFingerprint 로 func/template 을 구분하므로 dependency 해석에서 false
self-dependency 방지. 임의 선택 금지, ambiguous/unresolved는 candidate 목록 반환.
