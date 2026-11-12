# WP4-e — CLI exact target 0/1/>1 fail-closed

EXPERIMENT_ID: act2-wp4e-cli-exact-target
PARENT: act2-wp4d-symbol-identity (WP4-d complete)
SUBJECT: nim-stew@c75502ceedb5ed2a37b7b5e4744fc71313682859
STATUS: 구현 + 실측 검증 완료

## Question

canonical `--target module::function` 이 fail-closed 로 동작하는가?

- 0 matches → NotFound (명시적 실패)
- exactly 1 → Execute
- >1 matches → Ambiguous (명시적 실패)

기존에는 canonical target 이 frontier 에 없으면 full-frontier 로 "조용히" 폴백하여
요청하지 않은 project-wide verification 을 실행했다. 이는 사용자가 오타/모호한
canonical target 을 넘겼을 때 전체 repo 검증을 의도치 않게 트리거하는 위험이다.

## 변경 (generic rule, nim-stew 전용 예외 아님)

### src/cli/frontier_selection.nim — `selectFrontierNodes` canonical `::` 경로

기존 (lines 74-81):
```
if filtered.len == 0:  ... result = frontier   # full-frontier 폴백
elif filtered.len > 1: ... result = frontier   # full-frontier 폴백
else:                  ... result = filtered
```

수정 후:
```
if filtered.len == 0:  result = @[]   # NotFound (fail-closed)
elif filtered.len > 1: result = @[]   # Ambiguous (fail-closed)
else:                  result = filtered
```

legacy bare-name (`::` 없음) 경로는 그대로 full-frontier 폴백 유지
(non-canonical convenience 로 문서화됨).

### src/cli/axiom_engine.nim — explicit canonical target + empty frontier → error

`--target` 에 `::` 이 있고 `selectFrontierNodes` 결과가 empty 인 경우
명시적 `err(...)` 를 반환하여 실행 중단:

```
if task.target.len > 0 and task.target.contains("::") and frontier.len == 0:
  return err("--target ... resolved to no frontier nodes (NotFound or Ambiguous). ...")
```

또한 잘못된 로그 메시지 "using full frontier" 를 제거
(canonical 경로에서는 더 이상 full-frontier 를 사용하지 않으므로).

## 실측 결과

### canonical NotFound (`--target 'stew/base36.nim::doesNotExist'`)
```
EXIT=2
[INFO] frontier_selection: --target=stew/base36.nim::doesNotExist not found in frontier — canonical target: NotFound (fail-closed, empty selection)
[ERROR] --target stew/base36.nim::doesNotExist resolved to no frontier nodes (NotFound or Ambiguous). ...
```
→ 명시적 실패, 전체 검증 미실행.

### canonical 1 match (`--target 'stew/bitops2.nim::getBitsBE'`)
```
EXIT=0
--target filter: 1 node(s) match 'stew/bitops2.nim::getBitsBE'
... getBitsBE → vtStructural ... ir-cas MISS ...
[Depth 1/1] Checking: bitops2.nim::getBitsBE...
```
→ 정확히 1 매치 → 실행 경로 진입 (A3 도달, A4 illFormed 는 WP4-d-4 의 기존 blocker).

참고: func+template `getBitsBE` 는 node-level 에서 이미 단일 노드로 집약되어
frontier 에 1개로 존재하므로 ambiguous 가 아니다. ambiguous (same module::fn
2 nodes) 는 유닛테스트로 검증됨 (아래).

## 유닛테스트 (tests/unit/frontier_target_selection_test.nim)

기존 5개 + 신규 4개 = 9개 전부 PASS:

1. canonical exact match → single node
2. canonical 0 matches → fail-closed (empty, full-frontier 폴백 없음)
3. canonical >1 matches (same module+fn) → fail-closed (Ambiguous, empty)
4. legacy bare-name 0 matches → full-frontier 폴백 유지 (convenience 보존)

## 회귀 영향 평가

- 기존 self-run / regression 이 canonical `::` target 을 쓰는 사례 없음 (grep 확인).
  전부 bare name 이라 legacy 경로 사용 → 영향 없음.
- legacy bare-name 폴백 동작은 그대로 보존 (Test 5 기존 통과 유지).
- canonical 경로만 fail-closed 로 변경되어, 요청한 정확한 symbol 없이는
  자동 full-repo 검증이 절대 트리거되지 않음.

## 분류

- canonical NotFound → 명시적 실패 (exit 2)
- canonical 1 match → Execute (기존과 동일)
- canonical >1 match → fail-closed (유닛테스트로 검증, 엔진 결과로 표면화)

## Evidence

- `src/cli/frontier_selection.nim` (canonical fail-closed)
- `src/cli/axiom_engine.nim` (explicit error 승격)
- `tests/unit/frontier_target_selection_test.nim` (9 tests PASS)
- `/tmp/wp4e_notfound.log` (canonical NotFound → exit 2)
- `/tmp/wp4e_ambig.log` (canonical 1 match → getBitsBE 실행)

## Non-Claim

- 이 변경은 WP4-d-4 의 illFormed blocker (generic `type[SomeUnsignedInt]`)
  를 고치지 않는다 — 별도 blocker 로 유지.
- 이 변경은 실제 proof 성공(Z3/Lean/KAA)을 만들지 않는다.

## Next

WP4-d-4 에서 밝혀진 illFormed blocker (getBitsBE A4 스킵) 를 다음 WP 로 진행.
