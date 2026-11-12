# Authority Boundary Simplification — 실행 증거 (2026-10-07)

Workstream: `policy/surface-v58-authority-boundary` (#514) + `refactor/gates-authority-boundary` (#515)
목적: 각 불변식의 판정을 단일 authority에 수렴시키고, 그 권한을 늘리지 않는 중복 통제만 제거.
이 문서는 slice 착지 후 실측 증거의 정본 기록이다.

## 착지 내역

| PR | 내용 | 병합 커밋 |
|---|---|---|
| #514 | policy(surface) v58 — `.githooks/pre-push` CONTROLLED 재승인 (FROZEN→CONTROLLED, v57 선례 동일형) | `84910e859` |
| #515 | 본체 3건 — pre-push Part 2(anti_theater) 제거, `TOOLCHAIN_PIN_CORE` 공유, `check-debt` 건전 조건부 | `a4da3c0a7` |

정책 PR의 push는 `docs/spec/repository_surface_contract.md` §18(c)의 문서화된 경로(정책 PR 한정, 본문 PR 미적용)를 사용했다. 사전 관측된 자기-승인 차단: `check-repository-surface` FAIL / `SURFACE_FORBIDDEN` / base policyVersion 57 (v51 knownBlindSpots의 의도된 판정). 본문 PR(#515) push는 hooks 활성 상태에서 정상 수행(`--no-verify` 미사용).

## 변경 내용과 근거

1. **pre-push `anti_theater_gate` 재실행 제거** — 이 실행은 `git diff --cached`/`git diff HEAD`만 스캔(`anti_theater_gate.nim` getDiffOutput)해 푸시 시점 diff가 공백이면 아무것도 보지 않고 PASS한다(푸시된 OID를 결코 검사하지 않음). 커밋된 내용은 OID 스냅샷의 `check_nim_theater`(전체 트리)가, staged 추가분은 pre-commit이 계속 담당. 부정 행동 변경: 푸시하지 않는 WIP에 대한 tripwire 상실(의도).
2. **`TOOLCHAIN_PIN_CORE` 공유** — `check-toolchain-pin`과 `check-determinism`의 3-pin(nim 2.2.10/z3 4.13.3/lean 4.33.0) 이중 표현 제거. `check-determinism`의 git ≥2.40 floor(repo 유일)는 유지. `make -n` 전개가 원본 레시피와 바이트 동일 확인.
3. **`check-debt` 건전 조건부(push-admissibility thin target 한정)** — skip iff 브랜치 diff(`merge-base..HEAD`) ∩ debt 실입력집합 = ∅. 실입력집합 = `data/architecture_debt.json` 504파일 ∪ open/deferred registry `files[]` ∪ 9개 고정 파일. 오류 시 항상 실행(fail-safe). `GATES_FAST`/`local-ci`의 `check-debt`는 무조건 유지.

## 실측 증거

| 항목 | 관측 |
|---|---|
| 부정 PR 차단 (GitHub fail-closed) | PR #513: `trusted-writer-set-pairing` FAIL — `ATOMICITY: FAIL — atomicity violation: PR modifies trusted_writer_set.json or admission-check.yml but not both — both must be in the diff (fail-closed)` (job 112340234844). `mergeStateStatus: BLOCKED`, 미변식, 이후 close. main 무오염 |
| 본체 push (hooks 활성) | `[PASS] Pre-push checks passed`, 스냅샷 `84097ca88` PASS. 단, 이 push는 Makefile을 건드리므로 registry(DEBT#418/430/431/432/438/481이 `files[]`에 Makefile 기재)상 debt 입력과 교집합 → `[check-debt] RUN … 1 hit(s): Makefile` — SKIP이 아니라 RUN이 건전한 판정. duration 52s(기준 53–55s, 유지) |
| SKIP 패스 경로 검증 | docs-only diff → `SKIP (loud) … (1 changed paths, 0 debt inputs)` exit 0. `src/**` 변경 → RUN. 비-git 디렉터리·JSON 누락 → predicate error → fail-safe RUN |
| feature 변경 시 check-debt 실행 | 스냅샷(thin target)에서 Makefile+`src/gate/manifest.d/core-invariant-gate.json`(DEBT#418) probe → `RUN … 2 hit(s)` → `All debt validation checks passed` (~20s+) |
| G7-full (main, `a4da3c0a7`) | `make verify-contract-release-e2e-full` → `✅ verify-contract-release-e2e-full PASSED` (G7 pass, exit 0) |
| 결정론 (main) | `bin/ax report --canonical-digest` ×2 → 동일 `294239a36a03460452f33c636cda75ca9b744fb3fa67f03a330edbcacbfb57aa` |
| layer 집행 불변 | `bin/layer_enforcement_gate --strict` → PASS, exit 0 (pre-push Part 3 보존 확인) |
| docs-only push SKIP 실측 | `git push`(hooks 활성, 본 문서 커밋 `a13b1df06`) → `[check-debt] SKIP (loud): branch diff disjoint from debt input set (1 changed paths, 0 debt inputs)` 출력, `log.jsonl`: `duration_s: 47` (기준 53–55s). 스냅샷 재현에서도 동일 SKIP 라인 + 전체 `push-admissibility` 44.8s. 실측 절감 ≈ 6–8s/push — 역사 추정치(21–26s, 2026-08-29)보다 작음(현 스냅샷의 잔여 비용은 `check_nim_theater` 전체 트리 스캔 등에 분산). SKIP 메커니즘·건전성·loud 기록은 전부 관측됨 |

## follow-up (범위 밖, 기록용)

- registry 위생: Makefile을 `files[]`로 기재하는 6개 open/deferred 항목 정리 시 Makefile-only push도 SKIP 가능
- DEBT#287(layer 게이트 unknown-layer fail-open) 수정 — `src/gate/**` FROZEN
- Nim 컴파일러 네이티브 위임(`.raises`/`.tags`/`warningAsError`)으로 문자열 스캐너 대체
- Slice B: B-build 2→1, verdict overhead, measurement workflow 정리 (계약 개정 수반)
