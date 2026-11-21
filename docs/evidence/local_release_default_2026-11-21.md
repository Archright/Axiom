# VS-LOCAL-RELEASE-DEFAULT — 로컬 기본 빌드 release 전환 acceptance (2026-11-21)

> 범위: `make build` 기본 recipe를 debug → `-d:release`로 전환한 단일 변경(PR #283)의
> 사전 동등성·성능·identity 회전 측정과 canonical main 착지 후 재관측.
> 기록자 ≠ 승인자: 작성자는 agent, 승인자는 사용자(wintrover)다.
> 이 문서는 측정·관측만 기록한다. 판정 계약의 정의는 `docs/spec/productization_contract.md`가 소유한다.

## §1. 기준점과 환경

| 항목 | 실측값 | 명령 |
|---|---|---|
| 변경 전 canonical main | `223c534c55a7f04b4789424ff1bf8133a1422053` | `git log -1 origin/main` |
| 변경 브랜치/커밋 | `perf/local-release-default` / `51ef923a27869db7128bb14c069fd439d0bb32fe` | `git log -1` |
| 착지 merge commit | `fc19eb71ba18cb4b9c88e8b9000e61e23a1bebc3` (PR #283, 2026-11-21T01:39:28Z) | `gh pr view 283 --json mergeCommit` |
| 호스트 | 16 CPU / 30 GiB / Linux 6.17.0-42-generic x86_64 | `nproc`, `free -g`, `uname -srm` |
| Nim | 2.2.10 (`~/.choosenim/toolchains/nim-2.2.10/bin/nim`) | `nim --version` |
| toolchainIdentity | `nim-2.2.10|lean-4.33.0|z3-4.13.3|int64bit|linux-amd64` (modelprofile 포함 전체 값은 `report --json`) | `ax report --json` |

측정 중 다른 worktree의 release 빌드가 병행되어 절대 시간은 보수적이다(경쟁 상태).
모든 prove 측정은 동일 저장소·동일 입력·동일 baseline state에서 교차 실행했다.

## §2. Release가 제거하는 guard의 MUST 분류 (전환 전 필수 관문)

결론: **MUST = 0**. release 전환으로 사라지는 제품 필수 검증 조건은 없다.

| 대상 | 분류 | 근거 |
|---|---|---|
| `requires`/`ensures`/`contractProc` 매크로 | DIAGNOSTIC (호출 0) | `src`에서 `requires(`·`ensures(`·`{.contractProc.}` 호출 사이트 0. `spec_binding_macro.nim:107,115,180,188`의 `when not defined(release)`는 확장되지 않는 매크로 본문을 감싼다. |
| `src`의 계약 표기 15건 | DIAGNOSTIC (코드 생성 없음) | Nim **내장** pragma(`compiler/pragmas.nim:1319-1324`, `pragmaProposition`/`pragmaEnsures`). `TEffects.requiresEffects/ensuresEffects`에만 저장되고 codegen 소비자 없음. 모든 모드에서 불활성. |
| `assert`/`doAssert`/bounds/range/overflow | 유지 | Nim 2.2.10 `config/nim.cfg:86-94`의 release 블록은 stack/line trace·debugger·opt만 바꾼다. checks/assertions 해제는 `danger`/`quick`(`:72-78`)뿐이다. Context7 공식 문서(`nimc.html`)도 "danger가 모든 런타임 체크를 끈다"로 일치한다(`tut1.html`의 상충 서술은 pinned 구현이 nimc 쪽). |
| vacuity 제품 가드 | 유지 (무조건) | `hasNonSubstantiveSmtAssertion`(`gateway_main.nim:236`), 빈 공식 거부(`:150,239`), `z3GateVacuousContradiction`(`:109-119,278-285`), vault 실질성, Lean sorry/negative-mutation은 release 가드가 없다. |
| `injectContradiction` fault injector | DIAGNOSTIC (테스트 전용) | `gateway_main.nim:192,233` + `orchestrator_request_types.nim:53`만 release에서 제외. CLI/MCP setter 0건, 모든 제품 생성자가 기본값 false. 유일 사용처 `tests/unit/integrity_check_test.nim:33-42`는 `when not defined(release)`로 이미 보호된다. 테스트는 debug(`make test-fast-one` = `nim c -r --passC:-O2`)로 계속 실행 가능하다. |
| `debt_integrity_gate` | MUST (release가 더 엄격) | `debt_integrity_gate.nim:301-306` — debug는 WARN, release는 FAIL. `Makefile:189-196`이 이미 `-d:release`를 강제한다. |
| `except Defect` 8곳 | 동작 차이 수용 | `config.nims:47-49`의 release `--panics:on`으로 `Defect`는 uncatchable → `rawQuit(1)`. fail-closed(비영 exit)는 유지되고 진단 출력만 다르다. |
| `makeAxiomSession` `updatedAt >= createdAt` | UNKNOWN (양 모드 미강제) | `session_parser.nim:131-133`은 내장 pragma라 **debug에서도** 코드가 없다. release delta가 아니며 본 변경의 blocker가 아니다(§7 후속). |

## §3. 동등성 (canonical main `223c534`, 동일 트리·동일 입력)

| 관측 | debug | release | 판정 |
|---|---|---|---|
| `ax --check-provenance` | exit 0 | exit 0 | 동일 |
| `AXIOM_CI=1 ax prove --target normalizeMaxWorkers` | exit 0, PASS/PASS, verified=1 | exit 0, PASS/PASS, verified=1 | 동일 |
| `ax report --json` | — | — | volatileKeys 제외 시 byte-identical (차이는 `parallelOverheadMs`·`totalWallTimeMs`뿐) |
| `ax report --canonical-digest` | `f37e23f1…` | `f37e23f1…` | 동일 |
| state 누락 | exit 3 | exit 3 | stderr byte-identical |
| state 파손 | exit 3 | exit 3 | stderr byte-identical |
| schemaVersion 불일치 | exit 3 | exit 3 | stderr byte-identical |
| `git status --porcelain` | empty | empty | 동일 |

## §4. Identity 회전 — 정확히 한 필드

전환 전 PASS state와 전환 후 PASS state의 재귀 diff(volatileKeys 제외) 결과:

| 필드 | 전환 전 | 전환 후 |
|---|---|---|
| `executionIdentity.verifierBuildId` | `80bb07900ea29fb71ea69994fe0e85cb2be7098189c72f30d16b0c89038c53e0` | `fffae7647f9fda909e8e7afbc2398428de9895de7ff501ebde3dfd741873814c` |

그 외 `nodeReports`, `summary`, `toolchainIdentity`, `data/trusted/certificates`(manifest 포함)는 동일하다.
`Makefile`은 `tools/hermetic_build.nim`의 `VerifierBuildId` 입력이므로 이 회전은 의도된 identity epoch 전환이며,
기존 저널 claim은 새 epoch에서 재증명된다(동일 실행에서 PASS 재확립).
빌드 **모드**는 identity 입력이 아니므로 동일 트리의 debug/release 바이너리는 같은 epoch를 공유한다(§3 digest 동일).

## §5. 성능 (교차 5쌍, warm)

| run | debug (ms) | release (ms) |
|---|---|---|
| 1 (cold) | 45189 | 5775 |
| 2 | 14794 | 5471 |
| 3 | 16807 | 6852 |
| 4 | 18464 | 7939 |
| 5 | 18094 | 8436 |
| **median (all)** | **18094** | **6852** |
| median (warm, run2–5) | 17451 | 6852 |

warm 기준 **2.55×**, 전 런 exit 0 / PASS/PASS.
컴파일: `make build` cold 102.4 s(경쟁 상태), warm 23.0 s — warm 비용은 debug(24.7 s)와 동등하고
cold 증가분은 prove 약 2.2회로 상각된다.

## §6. 착지 후 canonical main 재관측

관측 시각 2026-11-21 01:40:45–01:41:58 UTC, 대상 `fc19eb71ba18cb4b9c88e8b9000e61e23a1bebc3`
(PR #283 직전에 PR #284 `c74707f`가 함께 착지해 `src/verification/*` 26개 파일이 변경된 트리다).

| 관측 | 값 | 명령/증거 |
|---|---|---|
| `make build` | exit 0, wall **66,102 ms**, `bin/ax` 13,400,480 bytes | `make build` (`/tmp/vs-local-release/post_merge/make_build.out`) |
| provenance | `OK — embedded BuildSourceHash == live src tree (vs1-tree-hash/1:-1832953073443090932)` | `bin/ax --check-provenance` |
| `ax prove` | exit 0, wall **6,374 ms**, PASS/PASS, `[VERIFIED]`, lean-verify PASS | `AXIOM_CI=1 bin/ax prove --target normalizeMaxWorkers` |
| report canonical digest | `17e1021281f3a24bf8ccdf64d2d623f1d4bcbed23552cd0ad9851d0d28007686` | `bin/ax report --canonical-digest` |
| `verifierBuildId` (canonical main) | `bc4b8870cebad4a2b65ddfa83fe967dfc493a5347f53e87e5b5b89660a5c5671` | `bin/ax report --json` · `executionIdentity` |
| summary | `verified=1`, `failedCount=0`, `verificationSuccessRate=1.0`, `symbolCount=16735` | `bin/ax report --json` |
| `git status --porcelain` | empty | `git status --porcelain=v1` |

- canonical main의 `verifierBuildId`가 사전 측정값 `fffae764…`와 다른 것은 #284의 `src` 변경이 같은 tree에
  포함됐기 때문이다. 동일 트리에서 Makefile만 바꾼 통제 실험(§4)이 identity 회전의 인과를 분리해 보여준다.
- prove 출력의 IR pipeline FAIL 2건(`calcDynamicTimeoutCore`, `safeSpeedupRatioCore`)은 변경 전 debug
  (`main_prove_debug.out:27-32`) 및 feature-branch release(`prove_after_build.out:27-32`)와 동일하다.
  대상 판정은 PASS/PASS exit 0이며 이 변경으로 새로 생긴 실패가 아니다.
- 착지 트리에서 release 가드 분류를 재확인했다: `223c534..fc19eb7`의 `src` diff에
  `defined(release)`/`defined(danger)` 추가 **0건**, `requires(`/`ensures(`/`{.contractProc.}` 호출 사이트 **0건**.
- 기본 빌드 recipe는 main에서 `$(NIM) c -d:release --hints:off -o:bin/ax src/cli/main.nim`이고,
  debug 경로는 `Makefile:1049` 주석으로 보존돼 있다.

## §7. Out of scope / Follow-up

| 항목 | 처리 |
|---|---|
| `makeAxiomSession` timestamp ordering | 양 모드 미강제 — 제품 불변식 여부 판정 + 명시적 `return err` 필요(별도 계획) |
| 다른 checkout에서 빌드한 `bin/ax`를 실행할 때 `subjectTreeMerkleRoot unmeasurable` | 내장 build-time root로 subject를 해석해 `""`(fail-closed)가 된다 — 소스 트리와 바이너리의 provenance가 다를 때의 정상 거부이나 진단이 간접적이다. 동일 checkout에서 `make build` 후에는 merkle이 통과하고, 남은 선행조건은 `proofs/.lake/build/bin/ircheck`(Lean 산출물)다. fresh-clone 셋업 문서화 + `--check-provenance` preflight 진단 개선은 별도 계획. |
| `parallelBuild` | §2.5 Epoch Cutover + 실제 CI 러너 측정 후 |
| `--passC:-O2` §2.5 분류 | 권한 있는 주체 판정 대기 |
| `injectContradiction` 공개 API 파라미터 | release에서 무시됨 — API 정리/문서화 판단 필요 |
| `topology_analysis_cache` | DEBT#561 (PR #279) |