# walkDirRec 비결정적 순서 특이사항

> Nim stdlib `walkDirRec` / `walkDir`는 파일시스템(readdir) 순서를 반환하며 **정렬을 보장하지 않습니다**.
> 같은 디렉터리라도 ext4/xfs(CI), APFS/HFS+(macOS), bind-mount 등 파일시스템에 따라 반복 순서가 달라집니다.
> 이 문서는 해당 특이사항과 필수 방어 패턴을 기록합니다 (AGENTS.md §0.5b).

---

## §1. 증상

- `walkDirRec(repoRoot / "src")`로 `.nim` 파일을 수집하면 순서가 **환경 의존적**입니다.
- 순서가 결정론적 분석 파이프라인의 입력(`seq[ModuleFacts]`)이 되면, 베어명(qualified name을 last component로 축약한) 충돌 해소가 **last-write-wins** 방식일 때 승자가 뒤집힙니다.
- 결과: 동일 커밋이 로컬에서는 `New: 0`, fresh CI(checkout)에서는 `New: N`으로 실패하는 **비결정성 버그**가 발생합니다.

## §2. 근본 원인

`nimtry` 정적 분석 엔진 (`src/gate/nimtry/`)에서:

1. `collectSourceFiles` (`nimtry_cli.nim:200-219`)가 `walkDirRec`로 소스를 수집 → 순서가 파일시스템 의존적.
2. `allModuleFacts`가 그 순서로 구성.
3. `resolveCalleeModules` (`call_graph.nim:31-46`), `buildFunctionToModuleTable` (`effect_queries.nim:21-24`), `checkProcPurity`의 독자 `fnToModule` (`purity_queries.nim:40-43`)가 베어명을 `fnToModule[fn.name] = path`로 **덮어쓰기(마지막-쓰기-승리)**.
4. 충돌 베어명 (`get`, `isDeepVerified`, `persistResult`, `runGit`, `walk` 등)이 실제로 2개 이상 모듈에 정의됨 → 순서에 따라 승자가 바뀜 → I/O 도달 집합(reverse BFS)이 뒤집힘 → 위반 세트가 달라짐.

## §3. 필수 방어 패턴 (Double-Determinism)

분석/수집 파이프라인에서는 **항상 두 층 모두 적용**해야 합니다.

### Fix 1 — 입력부 결정론화 (Deterministic Input)

`collectSourceFiles`에서 수집 후 반환 전에 `sort(result)`:
```nim
algorithm.sort(result)
```
모든 분기(fullTree / stagedFiles)에서 동일하게 적용.

### Fix 2 — 해소부 결정론화 (Deterministic Resolution)

last-write-wins 루프 입력을 경로 기준 정렬:
```nim
for moduleFacts in allFacts.sortedByIt(it.path):
```

## §4. 영향 범위 (2026-08-05 수정)

| 파일 | 함수 | 수정 |
|------|------|------|
| `nimtry_cli.nim` | `collectSourceFiles` | 반환 전 `sort(result)` |
| `call_graph.nim` | `resolveCalleeModules` | `sortedByIt(it.path)` 순회 |
| `effect_queries.nim` | `buildFunctionToModuleTable` | `sortedByIt(it.path)` 순회 |
| `purity_queries.nim` | `checkProcPurity`의 `fnToModule` | `sortedByIt(it.path)` 순회 |

추가로, 베어명 충돌로 인한 I/O 오분류를 방지하기 위해 진짜 I/O 모듈을
`io_module_registry.nim`의 `ioModules`에 등록합니다 (`git_operations.nim`, `plumbing.nim`,
`workspace_receipt.nim`, `fail_secure_state.nim`, `lean_replay.nim`, `the_judge_eval.nim`,
`documentation_first_gate.nim`, `nim_check_runner.nim`).

## §5. 회귀 방지 체크

- `bin/nimtry src/ --diff-baseline` → `New: 0` (캐시 유무, 반복 실행 모두)
- CI 이미지 fresh checkout에서도 동일 결과 확인.
- baseline 갱신은 소스 변경과 **같은 커밋**에서 수행 (`--update-baseline`).

## §6. 다른 사례

- `safety_queries.nim:514`, `test_hygiene.nim:55`, `feature_universe.nim:63,102,127`도 `walkDirRec`를 사용하지만
  per-file 검사(순서 무관)이거나 이미 정렬되어 있어 영향 없음.
- `tools/effect_closure_analyzer.nim:390,413`는 같은 베어명 패턴을 사용하나 standalone 도구로 CI 게이트 아님 (일관성 유지 권장).
