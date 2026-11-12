# DEBT#478 Ambient Severity Authority Closure — 실행 증거 (2026-10-07)

Workstream: `fix/debt478-ambient-closure` (착지 base: origin/main `0b4309420` = 정책 v61(#542) — v60(#536) 위에 #541 포함; v60-era 베이스 `eb1ea92ec`에서 리베이스)
목적: 게이트 판정을 좌우하던 ambient 환경변수 3종(`AXIOM_GATE_SEVERITY` · `AXIOM_REBASELINE` ·
`AXIOM_UPDATE_BASELINE`)의 판정 입력 경로를 독자 권한으로 제거한다. 판정은 선언되고 감사된
표면(manifest severity · CLI 플래그)으로만 형성되며, ambient 입력은 어떤 경로로도 판정에
도달하지 않는다.
정책 근거: repository surface v60 (PR #536, merge `eb1ea92ec`)이 본 클로저 대상 3 reader
경로(`import_encapsulation_gate.nim` · `effect_inference_gate.nim` ·
`orchestrator/hook/executor.nim`)를 CONTROLLED 재승인 — v60 설명에 human-architect-approved
DEBT#478 Closure plan (2026-10-07) 명시, AGENTS.md §-1 불변 파일 편집의 근거다.

## 결함 요약 (pre-closure, 2026-10-04 최초 측정)

| ambient 입력 | 좌우하던 판정 | 위치 (pre-closure) |
|---|---|---|
| `AXIOM_GATE_SEVERITY=warn` | svError 게이트의 FAIL → PASS (`[GUARD:WARN]` + exit 0) | `import_encapsulation_gate.nim:110-114,137,230` · `effect_inference_gate.nim:151` |
| `AXIOM_REBASELINE=1` | orchestrator가 전 게이트 argv에 `--update-baseline` 주입 → baseline 재작성 + PASS | `executor.nim:186-187` ← `gateway.nim:532` · `gate_hook.nim:166`의 putEnv |
| `AXIOM_UPDATE_BASELINE=1` | runner가 baseline을 재작성하고 SKIP (interlock 없음, argv `--update-baseline` 은폐) | `baseline_manager.nim isUpdateMode` ← `asset_hygiene_gate.nim` · `coverage_ratchet_gate.nim` |

orchestrator는 하위 차이를 관측 불가(`executor.nim:216`은 exitCode만, `:1146-1155`는 성공 시
stdout 폐기) — `[GUARD:WARN]` 마커는 어느 호출자에게도 도달하지 않았다.

## 제거 설계 (reader에서의 제거 — scrub이 아니라 경로 소멸)

1. **Severity**: 두 reader 삭제. `import_encapsulation_gate.nim`(§-1 불변, v60 승인)의 스캔
   proc은 manifest 선언 severity만 받는다(기본 `error`) → warn-only `ok:true` 분기는 모든
   경로에서 도달 불가. `effect_inference_gate.nim`은 기본 `warn` 유지(WarningViolated exit 1
   의미론 보존) — reader만 삭제.
2. **Rebaseline**: putEnv 전송 채널 삭제(`gateway.nim` · `gate_hook.nim`). 승인된 `--rebaseline`
   플래그는 명시적 `updateBaseline: bool` 파라미터로 스레드:
   gateway/gate_hook → runSingleGateIfRequested / runPreCommit / runPrePush / runCi →
   runAllGatesParallel → L2GateWorkerCtx / dispatchGate → runSingleGateImpl — argv 주입은
   파라미터에서만. 승인된 기능은 종단간 생존, ambient 전송은 소멸.
3. **UpdateBaseline**: env 단일 요인 판정(interlock 없음)이 asset_hygiene의 명시적 argv
   `--update-baseline` 경로를 은폐. reader + `updateBaselineFromCurrent` + `atomicWriteBaseline`
   삭제 후 importer 0건 → `src/core/gate/baseline_manager.nim` **모듈 통째 삭제**(원자적,
   dead scrub 없음, §0.9a). coverage_ratchet의 env-only 재작성 분기(명시적 대응물 부재)는
   분기와 함께 제거.
4. **enum 정리**: `EnvVar` 멤버 `evGateSeverity` / `evUpdateBaseline` / `evRebaseline` 삭제
   (DEBT#476 선례). 2026-10-04물인 `bootstrapGateEnvironment` delEnv scrub도 삭제 — 존재하지
   않는 reader를 지키는 scrub은 그 자체가 dead theater.
5. **테스트 재작성**: 불변식 테스트를 바이너리 수준 주입으로 재작성 — 러너 바이너리를
   `AXIOM_GATE_SEVERITY` unset/warn/error로 직접 실행, 세 설정 모두 동일 판정·위반 수
   (exit 1, `[GUARD] 1`) 요구. bootstrap 스크럽 의존 제거.
6. **문서**: `docs/spec/environment_inputs.md` — DECLARED 3행 삭제 + Principle 강화
   ("감사 없는 ambient 입력은 어떤 경로로도 게이트 판정에 영향 불가").
   `docs/spec/nim_effect_system_quirks.md` §18 — 삭제된 `rewriteGateSeverity` 템플릿의
   stale 블록을 closure 노트로 교체.

## DEBT#478 레지스트리 종결

- closed / FIXED / resolvedAt 2026-10-07, resolvedBy `debt478_ambient_severity_closure`, files 13.
- contentHash 재바인딩: post-closure `bootstrapGateEnvironment` 본문
  `sha256:6a3b5f503c50406f52abb9a52ba1f9c956d60d89ee4737ef36454ed70d504ee6`
  (extractProcText). 구 해시 `2cf985465…`는 비커밋 중간상태에서 계산되어 git에서 비재현 —
  lineRange 노트에 기록. §0.9a skip-matching은 생존 아티팩트 해시에 대해 해소된다.
- `--codegen`(상수+투영) → `--sync-budget` → `--validate`: **checks 전부 통과
  (리베이스 전 1400 / 리베이스 후 1411 — main #541/#542분 증가), metric 5 PASS 0 DRIFT**.

## nimtry 재앵커 (v18·#528 선례)

본문 편집으로 4개 기존 앵커 함수의 fingerprint(라인·SLOC)가 이동해 `check-arch`가
신규 위반 4건을 보고했다: `runHookPreCommit` 125→127 SLOC, `runAllGatesParallel`
700→703, `runSingleGateIfRequested` 87→88, `runCoverageRatchet` 64→57(분기 삭제로
축소 — 악화 아님). 4건 전부 baseline 기존 항목의 fingerprint 변형이며 신규 비대칭이
아니므로, 선례 절차대로 `bin/nimtry --update-baseline src/`로 재앵커(4,091 violations,
diff 45+/73−) → `--sync-budget`(`nimtry_violations` current 재수렴) → `--validate`
1400/1400 PASS → `make check-arch` PASS. 함수 분해 등 구조 리팩터링은 수행하지 않았다
(기회적 리팩터링 금지, §2.2).

**리베이스 후 상태(2026-10-07 실측)**: `make check-arch`는 본 diff와 무관한
**main 측 pre-existing 위반 1건**을 보고한다 — `SAFETY-no-main-module-in-src`,
`src/verification/projections/effect_contract_projection.nim:312` `when isMainModule`.
기계 확정: (1) 본 diff는 해당 파일을 건드리지 않음(`git diff origin/main...HEAD --name-only`
0경로), (2) 위반 도입 커밋은 `c0d1a80d3`(PR #539, main), (3) origin/main의
`data/nimtry_baseline.json`에도 해당 앵커 부재(19건의 no-main-module 앵커 모두 타 파일)
→ **origin/main 자체가 동일 1건으로 check-arch red**다. 위반 수용(baseline 앵커 추가)은
owner 결정이 필요한 정책 처분이므로 본 슬라이스에서 침묵 패치·앵커 흡수하지 않는다(§2.2
범위 폐쇄, §0.10). check-arch는 `PUSH_ADMISSIBILITY_GATES`(14종)에 없어 랜딩 경로와
무관하며, #539가 동일 상태로 merge queue를 통과한 것이 그 관측 증거다. follow-up으로
owner 처분(앵커 또는 `when isMainModule` 제거) 권고.

## 착지 전 실측 (워크트리, 커밋 기준)

### Phase 2 부정 drill (`bash /tmp/debt478_drills.sh <worktree>`) — 25 PASS / 0 FAIL

| # | drill | 기대 | 실측 |
|---|---|---|---|
| 1 | 직접 바이너리 × 4 세팅 (unset/warn/error/bogus), 1-위반 fixture | 전부 exit 1, `[GUARD] 1`, byte-동일, `GUARD:WARN` 부재 | 전부 일치 (warn = pre-closure exit 0 → **exit 1**) |
| 2 | orchestrator 진입 (AXIOM_SINGLE_GATE_ID=import-encapsulation-gate) ± `AXIOM_GATE_SEVERITY=warn` | 출력 byte-동일, exit 동일, `GUARD:WARN` 부재, baseline 무재작성 | PASS ×4 (in-process 경로, ProjectMap 공집합 — 아래 범위 참고) |
| 3 | 진입 `AXIOM_REBASELINE=1` (env-only) | baseline md5 불변, "Baseline updated" 부재 | PASS (exit 1 — asset-hygiene 위반 정상 판정) |
| 4 | 진입 `--rebaseline` 플래그 | sanctioned 경로 생존: baseline 재작성 | PASS (md5 변경 + `Rebaseline mode` 로그, 이후 git checkout 복원) |
| 5 | `AXIOM_UPDATE_BASELINE=1` 직접 (asset_hygiene / coverage_ratchet) | baseline 무재작성 | PASS ×2 (md5 불변) |
| 5b | effect gate ± `AXIOM_GATE_SEVERITY=warn`, 위반 fixture | exit≠0 유지 | PASS ×2 (exit 1) |

### 구조적 제거 실측

| 측정 | 결과 |
|---|---|
| `grep -rn 'getAxiomEnv(ev' src/ \| grep -E 'Severity\|Rebaseline\|UpdateBaseline'` | **0건** |
| `grep -rn 'AXIOM_GATE_SEVERITY\|AXIOM_REBASELINE\|AXIOM_UPDATE_BASELINE' src/` | **0건** (reader·putEnv·enum 모두) |
| feature 테스트 `make test-fast-one T=tests/gateway/import_encapsulation_gate_feature_test.nim` | 7/7 OK — 신규 "ambient verdict-shaping env cannot change the verdict" 포함 |
| debt 검증 | `--validate` 1400/1400 PASS, metric 5 PASS 0 DRIFT |
| check-arch | PASS (4 fingerprint 재앵커 후, §nimtry 재앵커) |
| 변경 규모 | 21경로, +334/−328 (baseline_manager.nim −94 전체 삭제 포함) |

## 발견 → 신규 등록 (범위 밖, §0.9 준수)

drill 설계 중 발견한 극장을 조용히 패치하지 않고 **DEBT#493( open, Theater/Vacuous Check )로
등록**: `passFilenames=true` 게이트의 서브프로세스 폴백은 argv에 리터럴 `--stdin-files` 토큰을
넣고 실제 파일명은 stdin으로 쓰는데(`executor.nim:183-184,191-196`), 당해 러너
(`import_encapsulation_gate.nim:134-135` · `binary_artifact_gate.nim:176-180`)는 argv 토큰을
전부 파일명으로 취급해 stdin을 읽지 않음 → 존재하지 않는 경로를 스캔해 공 PASS.
실측: fallback argv 형태로 1-위반 fixture 실행 → **exit 0 PASS**; 실제 파일명 argv 대조군 →
exit 1 위반 검출. protocol을 올바히 구현한 유일 소비자는 `quality_gate_runner.nim:115-119`.
contentHash 바인딩: `runSingleGateImpl`
`sha256:d22cc16776c71ae13d12a8cb0cb9d3e8269b9da0d10cd446921b0d582ab56ea7`.

## 범위 정직화 — 본 클로저가 닫은 것과 닫지 않은 것

- **닫힌 것**: ambient env 3종의 판정 입력 경로(reader · putEnv 전송 · argv 주입 · enum)가
  src/ 전역에서 소멸. 판정은 manifest 선언·CLI 플래그만으로 형성된다.
- **닫지 않은 것 (기록만, 기존 동작)**:
  1. import-encapsulation의 **생산 집행은 in-process 스캐너**
     (`pipeline_orchestrator.nim:99`)이며 이는 애초 env reader가 없었다 — 서브프로세스 폴백의
     공실행은 DEBT#493로 등록, 본 PR에서 수정하지 않음.
  2. in-process 단일 게이트 진입은 ProjectMap 기반 전체 스캔이며 changed-file 리스트를 무시 —
     ProjectMap 공집합(단일 게이트 진입에서 관측) 시 0파일 스캔 PASS. DEBT#493 description에
     관측 기록.
  3. `binary_artifact_gate`는 코드 판독상 동급(argv 패턴 동일)이나 worktree에 바이너리 미빌드로
     미실측 — DEBT#493에 same-class로 기록.

## 착지 상태 — base-policy surface 판정과 push 차단 (2026-10-07)

본 브랜치 HEAD 기준 `make check-repository-surface`(binding: base, policyVersion 60):
changeCount 21 중 **19 modify + 1 add + 1 delete PASS**, 그러나 2경로가
`SURFACE_FORBIDDEN`으로 FAIL — `src/gate/runners/asset_hygiene_gate.nim` ·
`src/gate/runners/coverage_ratchet_gate.nim` (changeClass FROZEN — base v60의
`src/gate/**` glob 흡수, v60 재승인 3경로에 미포함). pre-push 훅 Part 4가 push-target
OID 스냅샷에서 동일 판정으로 push를 차단했다 (`[Pre-push FAIL] Push-target OID
f4d5baf3f… failed static admissibility` — 원격 전송 없음).

이 2파일의 편집은 클로저에 구조적으로 필수다: `baseline_manager.nim` 모듈 삭제(src/core,
PRODUCT)가 두 파일의 env reader import를 제거하므로, reader 분기를 남기면 트리가
컴파일되지 않는다. 따라서 소비 본문 분할 착지는 불가능하며, 필요한 것은 v60과 동일
형태의 **인간 아키텍트 FROZEN 재승인(v61)**이다 — "re-authorise 2 paths required by
the DEBT#478 Ambient Severity Authority Closure (AXIOM_UPDATE_BASELINE reader
removal): src/gate/runners/asset_hygiene_gate.nim · src/gate/runners/coverage_ratchet_gate.nim".
정책 자체 수정은 본 슬라이스에서 수행하지 않았다(v51 자기승인 봉쇄 + §0.10).

**해소(2026-10-07)**: v61은 PR #542로 착지(merge `0b4309420`). 본 브랜치를 그 위에
리베이스한 뒤 `make check-repository-surface` 재실측 → **verdict PASS, policyVersion 61,
changeCount 22 (19 modify + 1 add + 1 delete + 1 rename-class 0)** — SURFACE_FORBIDDEN 0건.
push는 정상 경로(--no-verify 불요)로 진행된다.

## 리베이스 후 재실측 (post-rebase, pre-push; 커밋 `f54c77a88`)

`git rebase` onto `0b4309420` — 충돌 4파일(`data/debt_ledger.json` ·
`data/debt_registry.json` · `docs/DEBT_REGISTRY.md` · `src/generated/debt_constants.nim`)은
SSOT 우선 해소: registry는 main #541의 DEBT#491/492(accepted)와 본 슬라이스의 DEBT#478
closed + DEBT#493(open)을 통합(총 223 entries), 나머지 3파일은 `bin/debt_engine
--codegen --sync-budget` 결정론 재생성(#539 선례). 발견 항목은 재번호되었다:
구 DEBT#491(out-of-scope vacuous check) → **DEBT#493**.

| 재실측 | 결과 |
|---|---|
| `bin/debt_engine --validate` | **1411/1411 PASS**, metric 5 PASS 0 DRIFT, policy freshness fresh |
| Phase 2 부정 drill 25항목 재실행 | **25 PASS / 0 FAIL** (경고 주입 직접 바이너리 exit 1 · entry byte-동일 · env-only baseline 불변 · `--rebaseline` 플래그 정상 갱신 후 복원) |
| feature 테스트 | 7/7 OK (`make test-fast-one T=tests/gateway/import_encapsulation_gate_feature_test.nim`) |
| `make check-repository-surface` | PASS (policyVersion 61, changeCount 22) |
| `make gate-binaries` | PASS (증분 재빌드, BUILD-EXIT 0) |
| reader grep | `getAxiomEnv(ev'`×Severity/Rebaseline/UpdateBaseline = 0건; env 이름 3종 src/ = 0건 |

## main 병합 후 운영 실측

병합 후 동일 drill 스크립트를 main에서 재실행해 본 절의 표를 확정한다 (선례: #528 acceptance
record). 본 문서는 착지 전 스냅샷으로 병합 PR에 포함되며, Phase 3 실측 수치는 병합 후
후속 기록으로 보강된다.

## Phase 3 — main 착지 + acceptance 실측 (2026-10-07, main `2c30c55b1`)

**착지**: PR #545 병합 — state MERGED, mergedAt 2026-10-07T06:55:57Z, mergeCommit
`2c30c55b1ad799b4fc125fe417b4dfe6a849c911` (2-parent native MERGE). `tools/ci/landing_observe.sh 545`
판정 **TERMINAL_SUCCESS**(graphql↔rest 일치, admission-gate run 37583483896 + landing-integrity
37583483370 + probe-merge-queue 37583483495 전부 success 후 착지). pre-push는 본문 push 시
14개 push-admissibility 스냅샷 게이트 전부 green(`PASS: check-debt … check-layer-negative green
(snapshot)`) 후 원격 전송됐다.

main 클론판정(메인 클론, clean tree, 바이너리 재빌드 후):

| # | acceptance 항목 | 실측 |
|---|---|---|
| 1 | `AXIOM_GATE_SEVERITY=warn bin/import_encapsulation_gate <1-위반 fixture>` | **exit 1**, `[GUARD] 1`, `[GUARD:WARN]` 부재 (unset/error/bogus와 [GUARD] 행 byte-동일) |
| 2 | 오케스트레이터 entry(`AXIOM_SINGLE_GATE_ID=import-encapsulation-gate bin/axiom-gate hook pre-commit`) ± warn | 출력 byte-동일, exit 동일(0), `GUARD:WARN` 부재 |
| 3 | `AXIOM_REBASELINE=1` entry(env-only) | baseline md5 불변, `--update-baseline` 미주입(`Baseline updated` 로그 0건) |
| 4 | `--rebaseline` 플래그 | 정상 갱신: baseline md5 변경 + `Rebaseline mode`·`Baseline updated` 로그, 이후 `git checkout` 복원 |
| 5 | `AXIOM_UPDATE_BASELINE=1` 직접(asset_hygiene / coverage_ratchet) | ×2 baseline md5 불변, 재작성 없음 |
| 6 | reader grep | `getAxiomEnv(ev'`×Severity/Rebaseline/UpdateBaseline = **0건**; env 이름 3종 src/ 전역 = **0건** |
| 7 | 불변성 테스트 + 기존 게이트 테스트 | `make test-fast-one T=tests/gateway/import_encapsulation_gate_feature_test.nim` **7/7 OK**(신규 ambient 테스트 포함); `make test-fast` 플래그 5건은 **모두 #545 이전 main(`90795baa7`)에서 동일 서명으로 재현되는 사전 존재/harness 오탐**(하단 비고 (c)) |
| 8 | G7 + digest | `make verify-contract-release-e2e-full` **PASS**(G7-EXIT 0, `G7 pass tier=z3-verified status=not_verifiable`); `bin/ax report --canonical-digest` ×2 **동일**(`d461f1cb7d0cef9a6c65cdace020162383ab54ba03271bf9389ff8450f79a37e`) |
| 9 | debt 엔진 | `bin/debt_engine --validate` **1411/1411 PASS**, codegen 투영 diff 0(push-admissibility Projection byte-identity guard PASS), DEBT#478 **closed/FIXED**(registry 223 entries, BUDGET#006 closed=176 delta 0) |
| 10 | PR→queue→main | pre-push green → PR #545 → queue round(admission-gate 37583483896 success) → **병합 SHA `2c30c55b1ad7`** |

비고: (a) 병합 직후 최초 drill 1회는 재빌드 직후 과도 상태로 entry-level 2항목이 공 출력
exit=1로 실패했으나 비재현 — clean 재실행에서 25 PASS / 0 FAIL, entry 수동 재확인에서
unset/warn byte-동일 확인. (b) G7 로그 내부의 `Fail: 3`(normalizeMaxWorkers·
calcDynamicTimeoutCore·safeSpeedupRatioCore·proximityScore psFail)은 #518이 문서화한
내부 레지스트리 fail-closed 잔여로 본 클로저와 무관하며, G7 판정은 status=not_verifiable
경로로 PASS다. (c) `make test-fast` 플래그 5건의 판별 실측 — harness 판정은 로그 grep(`Error|FAILED|Traceback`) 기반이다.
**#545 직전 main(`90795baa7`)에서 동일 5종을 harness 동일 커맨드로 재실행한 결과 전부 동일 재현**:
unit 19 `test_theater_allowlist_structure`(`allowlist.len was 166` vs 기대 139 — 양 트리 동일,
데이터 드리프트), unit 21 `test_vkd_determinism`(SIGSEGV nil-read — 양 트리 동일), unit 22
`test_certificate_trust_closure`(journal replay [FAILED] — 양 트리 동일)는 진성 사전 존재 실패;
unit 24 `resolve_node_outcome_test`·unit 34 `test_g6_runtime_reference_divergence`는 **바이너리
exit 0**(직접 실행 확인 `/tmp/opencode/ax-ut24`·`ax-ut34` → exit 0)이며 로그 내 "FAILED"/"Error"
문자열(34는 PASS 메시지의 "reference vault FAILED state")을 grep한 harness 오탐이다. 결론:
**#545가 가져온 테스트 회귀 0건**. (d) main 클론 check-arch는 리베이스 절에 기록한 main 측
pre-existing 무앵커 위반 1건을 동일히 보고한다(본 슬라이스 불착지).
