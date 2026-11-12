# Orphan Gate Authority Closure — Completion Evidence (Phase 1–4)

- **Date**: 2026-10-08
- **Branch**: `fix/orphan-gate-authority-closure` (worktree `orca/workspaces/Axiom/orphan-gate-closure`, base = origin/main `5dc62ebba`)
- **Terminal outcome**: 거짓 보호 주장(stages 허위 선언)이 철회되고, 실제 authority만이 제품 결정에 참여함이 기계로 증명된 상태
- **정책 시퀀스(2단계) — 완료**: 본 PR은 base 정책(FROZEN `src/gate/**`) 하에서 수정 불가 경로 48건을 포함하므로 표면 재승인 정책 PR이 선행된다. 정책 PR은 **v70, PR #596**으로 착지(`31bf2b1e9`, 2026-10-08T07:58:19Z MERGED, merge queue) — v66/v67 2단계 선례와 동일하며, v69 번호는 동시 착지한 hollow-CAS 정책 PR #595에 선점되어 v64 = PR #555 선례대로 후행 PR이 rebase + renumber했다. 정책 PR의 advisory repository-surface FAIL(자기승인 블록 — v51 knownBlindSpots 문서화)은 PR 본문에 전문 공개, push는 문서화된 advisory bypass(`git -c core.hooksPath=/dev/null push`, `--no-verify` 미사용)로 수행. 소비 PR(본문)은 base v70 하에서 surface_guard **PASS** 재측정.

## Root cause (기계 추적)

1. **은퇴 체인**: `ci.yml`(verify-integration-r1 job) → `make ci-gates` → 구 Makefile:679 `AXIOM_CI=1 AXIOM_CI_PRESERVE_CACHE=1 bin/gate_hook ci` — 이것이 manifest stage-dispatch 평면(gate_hook → orchestrator_hook → executor → `tryDispatchInProcess` + `runSingleGateImpl`)의 **유일한 프로덕션 호출자**였다.
2. **fa069d610** (2026-09-16, "clean slate — retire active CI workflows") 이 ci.yml 545행을 은퇴시키고, **ce92fc2d1** 이 Makefile의 `bin/gate_hook ci` 실행행을 제거했다. 현행 Makefile·ci/checker.mk·.github/workflows의 `bin/gate_hook` 참조 33건은 전부 artifact/chmod/sha256/provenance 문맥이고 **실행 문맥 0건**(하니스 (c) 실측).
3. 결과: `ci` stage 선언 전부와 gateway-dispatch `pre-push` 선언은 **호출 근거가 소멸한 거짓 보호 주장**이 되었다. 살아있는 판정 권한은 .githooks 직접 호출 4개뿐이다 (하니스 (a) 실측).

## Changes landed (62 files)

| 축 | 내용 |
|---|---|
| `src/gate/topology_spec.nim` | 52/54 엔트리 stages 정직화: nim-check·stale-cert `ci→pre-commit`(실제 hook 호출), layer-enforcement `pre-commit→pre-commit,pre-push`(미선언 authority 정정), 나머지 48개 `→manual`(수동 실행 계약), baseline-migration `[]→manual`(minItems 정합). 최종 분포: `[pre-commit]×3 + [pre-commit,pre-push]×1 + [manual]×50` |
| `src/gate/manifest.d/*.json` (52) | `bin/sync_topology` 재생성 투영 (id·entry 불변 → `_index.json`·`gate_registry.nim`·`manifest_registry.nim`·`helper_registry.nim`·`gates.manifest.toml`·`gates.json` 전부 unchanged 실측) |
| `src/gate/gate_manifest.schema.json` | stages 의미 명시(pre-commit/pre-push=hook 기계검증, ci=활성 gate_hook lane 요구, manual=문서화된 direct-run 계약; minItems=1 강제 근거) |
| `src/gate/runners/manifest_consistency_gate.nim` | **Check 10 선언↔호출 정합** 추가 + minItems 실집행 + 중복 stage 검사 |
| `docs/spec/coverage_ratchet_protocol.md` | §Stage Support 허위 서술("runs in the pre-push and ci stages") 철회 — 실제: 수동 계약 + `reliability_score.json` auto-bump 부작용 명시 |
| `data/debt_registry.json` 등 | DEBT#498/499/500 신규 + DEBT#483 흡수 갱신 (아래 레지스트리 절) |

## 6-path harness (명령 + 출력 기록)

**(a) hooks ↔ manifest 대조** — manifest 게이트별 `.githooks/{pre-commit,pre-push}` 비주석 호출행 스윕:
```
anti-theater-gate       declared=pre-commit           hookPC=4 hookPP=0
layer-enforcement-gate  declared=pre-commit,pre-push  hookPC=4 hookPP=8
nim-check               declared=pre-commit           hookPC=3 hookPP=0
stale-cert-gate         declared=pre-commit           hookPC=4 hookPP=0
```
→ hook 호출 존재 게이트 = 정확히 4개, 선언과 일치(양방향). 나머지 50개는 hook 호출 0.

**(b) Makefile ↔ manifest** — 실행 계약 보유: env-gate(Makefile:111 `env-check`), manifest-consistency-gate(Makefile:298 `check-manifest-consistency`), quality-gate-runner(Makefile:360/1032 `check-quality-gate`·`audit`), readiness-start-gate(Makefile:880-881 `check-readiness-start`), layer-enforcement(Makefile:159-160 push-admissibility), gate-self-check(Makefile:232-235 mutation-harness 평면). golden-master/conflict-marker/hotspot-coverage의 checker.mk:71-72 참조는 **빌드 목록·컴파일행**이지 실행이 아님.

**(c) workflow gate_hook 실행 문맥 grep**:
```
total refs=33, execution-context refs=0   (.github/workflows/ 전체)
```

**(d) gsCI·interpreted-skip·in-process·memo**:
- `src/gate/gate_utils.nim:71` — `if gsCI in gate.stages and getAxiomEnv(evCi) != "1": return false` (로컬 환경 AXIOM_CI 미설정 → ci 태그 게이트 무실행; env 0건)
- `src/gate/gateway.nim:488` — interpreted 게이트는 CAS 카운트 제외
- `src/gate/utils/gate_safety_macro.nim:151` — `LightGateAllowlist = [debt-scan-gate, doc-completeness-gate, trust-commit-scope]` 3개뿐(대상 41게이트 부재) — 그리고 이 평면의 호출자(gate_hook) 자체가 무호출
- memo(`src/gate/orchestrator/hook/memo.nim`)는 orchestrator_hook 평면 내부 캐시 — 평면 무호출이므로 제품 판정 개입 0

**(e) ci.yml 은퇴 확인**:
```
fa069d610 chore(ci): clean slate — retire active CI workflows (freeze: tag ci-postmerge-2026-09) (2026-09-16)
 .github/workflows/ci.yml | 545 +--------------------
마지막 `bin/gate_hook ci` Makefile 제거 커밋: ce92fc2d1 "chore: remove CI infrastructure (CI=0 cutover)"
```

**(f) countMissingCasBinaries 간접 경로**: `src/gate/gateway.nim:474,486` (stage 필터) 소비처는 `gateway.nim:618,892`(hook-plane AOT preflight) 뿐이고, `bin/gateway`의 Makefile/hooks/workflows 실행 참조 = 0. stages 변경은 이 죽은 평면의 CAS 열거 수만 변동시키고 판정에는 개입 불가. precompile_gates는 `_index.json`(id 목록, 불변)만 읽음 — 투영 영향 0.

## 54게이트 분류표 (라벨: authority | advisory-executed | unwired-helper | dead)

- **authority(4)**: hook 직접 호출, 차단 판정
- **advisory-executed(5)**: check 로직이 착지 필수 gateway feature test(LG 카탈로그)에서 실행되나, manifest stage 판정으로서는 불발
- **unwired-helper(10)**: 자동 스테이지 미배선 + 문서화/기계적 수동 실행 계약 보유
- **dead(35)**: 호출 스윕 0건 — standalone 존재만 (일부 유닛테스트·죽은 평면 표 참조)

| gate | stages(정직화 후) | label | 근거 (file:line) |
|---|---|---|---|
| anti-theater-gate | pre-commit | authority | .githooks/pre-commit:88 (직접 호출, 차단) |
| asset-hygiene-gate | manual | dead | 호출 스윕 0건(hooks·Makefile·workflows·src/tests 임포트) — standalone 존재만 |
| baseline-migration-gate | manual | dead | 호출 스윕 0건(hooks·Makefile·workflows·src/tests 임포트) — standalone 존재만 — 기존 stages=[] — minItems 정합화로 manual 재선언 |
| binary-artifact-gate | manual | dead | 호출 스윕 0건(hooks·Makefile·workflows·src/tests 임포트) — standalone 존재만 |
| binary-freshness-gate | manual | dead | 호출 스윕 0건(hooks·Makefile·workflows·src/tests 임포트) — standalone 존재만 |
| cli-build | manual | dead | 호출 스윕 0건(hooks·Makefile·workflows·src/tests 임포트) — standalone 존재만 |
| conflict-marker-gate | manual | advisory-executed | LG-005 (+ 빌드 평면: ci/checker.mk:71, runner-pool-acceptance artifact) |
| core-invariant-gate | manual | advisory-executed | LG-003 |
| coverage-ratchet-gate | manual | unwired-helper | docs/spec/coverage_ratchet_protocol.md §Stage Support(철회 후 수동 계약) — 수동 실행 시 reliability_score.json auto-bump |
| debt-integrity-gate | manual | dead | 호출 스윕 0건(hooks·Makefile·workflows·src/tests 임포트) — standalone 존재만 |
| decision-binding-gate | manual | unwired-helper | 레거시 디스패치 인터페이스(all_gate_runners registerAllManifestGates) + 병행 live 강제: Makefile:239-242 hermetic_build --check-decision-bindings |
| delegation-enforcer | manual | dead | 호출 스윕 0건(hooks·Makefile·workflows·src/tests 임포트) — standalone 존재만 |
| discarded-write-audit-gate | manual | dead | 호출 스윕 0건(hooks·Makefile·workflows·src/tests 임포트) — standalone 존재만 |
| doc-completeness-gate | manual | unwired-helper | in-process case inprocess_dispatch.nim:469 — 평면 무호출 |
| documentation-first-gate | manual | dead | 호출 스윕 0건(hooks·Makefile·workflows·src/tests 임포트) — standalone 존재만 |
| effect-inference-gate | manual | dead | 호출 스윕 0건(hooks·Makefile·workflows·src/tests 임포트) — standalone 존재만 |
| env-gate | manual | unwired-helper | Makefile:109-112 `make env-check` |
| evidence-truth-boundary-gate | manual | dead | 호출 스윕 0건(hooks·Makefile·workflows·src/tests 임포트) — standalone 존재만 |
| external-cli-smoke | manual | dead | 호출 스윕 0건(hooks·Makefile·workflows·src/tests 임포트) — standalone 존재만 |
| gate-self-check | manual | unwired-helper | Makefile:232-235 mutation-harness 평면 + standalone |
| gateway-test | manual | dead | 호출 스윕 0건(hooks·Makefile·workflows·src/tests 임포트) — standalone 존재만 |
| golden-master-gate | manual | dead | 호출 스윕 0건(hooks·Makefile·workflows·src/tests 임포트) — standalone 존재만 — 빌드전용(artifact 까지 컴파일·봉함, 실행 0) + GateEnablement=false |
| hermetic-test-gate | manual | dead | 호출 스윕 0건(hooks·Makefile·workflows·src/tests 임포트) — standalone 존재만 |
| hotspot-coverage-gate | manual | advisory-executed | LG-010 (+ 빌드 평면: ci/checker.mk:71) |
| hotspot-gate | manual | dead | 호출 스윕 0건(hooks·Makefile·workflows·src/tests 임포트) — standalone 존재만 |
| immunity-gate | manual | dead | 호출 스윕 0건(hooks·Makefile·workflows·src/tests 임포트) — standalone 존재만 |
| import-encapsulation-gate | manual | advisory-executed | config/policy/landing_required_gateway_tests.json LG-002 (착지 필수 feature test) |
| integrity-test | manual | dead | 호출 스윕 0건(hooks·Makefile·workflows·src/tests 임포트) — standalone 존재만 |
| integrity-workflow | manual | dead | 호출 스윕 0건(hooks·Makefile·workflows·src/tests 임포트) — standalone 존재만 |
| intent-gate | manual | dead | 호출 스윕 0건(hooks·Makefile·workflows·src/tests 임포트) — standalone 존재만 |
| language-ban-gate | manual | dead | 호출 스윕 0건(hooks·Makefile·workflows·src/tests 임포트) — standalone 존재만 |
| layer-enforcement-gate | pre-commit,pre-push | authority | .githooks/pre-commit:99 + .githooks/pre-push:38 (+ Makefile:159-160 push-admissibility) |
| lean-z3-consensus-gate | manual | dead | 호출 스윕 0건(hooks·Makefile·workflows·src/tests 임포트) — standalone 존재만 |
| manifest-consistency-gate | manual | unwired-helper | Makefile:296-298 `make check-manifest-consistency` |
| mcp-tool-usage-gate | manual | dead | 호출 스윕 0건(hooks·Makefile·workflows·src/tests 임포트) — standalone 존재만 |
| monotonic-whitelist-gate | manual | dead | 호출 스윕 0건(hooks·Makefile·workflows·src/tests 임포트) — standalone 존재만 |
| nim-check | pre-commit | authority | .githooks/pre-commit:74 (직접 호출, 차단) |
| policy-validator | manual | dead | 호출 스윕 0건(hooks·Makefile·workflows·src/tests 임포트) — standalone 존재만 |
| procedure-gate | manual | dead | 호출 스윕 0건(hooks·Makefile·workflows·src/tests 임포트) — standalone 존재만 |
| proof-universe-lock-gate | manual | dead | 호출 스윕 0건(hooks·Makefile·workflows·src/tests 임포트) — standalone 존재만 |
| quality-gate-runner | manual | unwired-helper | Makefile:355-360 `check-quality-gate` (+ Makefile:1032 make audit; DEBT#483) |
| readiness-start-gate | manual | unwired-helper | Makefile:880-881 `make check-readiness-start` |
| release-version-gate | manual | dead | 호출 스윕 0건(hooks·Makefile·workflows·src/tests 임포트) — standalone 존재만 |
| reliability-gate | manual | advisory-executed | LG-014 |
| sorry-audit-gate | manual | dead | 호출 스윕 0건(hooks·Makefile·workflows·src/tests 임포트) — standalone 존재만 |
| spec-binding-gate | manual | dead | 호출 스윕 0건(hooks·Makefile·workflows·src/tests 임포트) — standalone 존재만 |
| spec-presence-gate | manual | dead | 호출 스윕 0건(hooks·Makefile·workflows·src/tests 임포트) — standalone 존재만 |
| stale-cert-gate | pre-commit | authority | .githooks/pre-commit:112 (직접 호출, 차단) |
| static-analyzer | manual | dead | 호출 스윕 0건(hooks·Makefile·workflows·src/tests 임포트) — standalone 존재만 — GateEnablement=false (DEBT#426) |
| tcb-coverage-gate | manual | dead | 호출 스윕 0건(hooks·Makefile·workflows·src/tests 임포트) — standalone 존재만 |
| test-coverage-gate | manual | dead | 호출 스윕 0건(hooks·Makefile·workflows·src/tests 임포트) — standalone 존재만 |
| trust-commit-scope | manual | unwired-helper | in-process 계약: src/gate/utils/inprocess_dispatch.nim:471 + LightGateAllowlist(gate_safety_macro.nim:151-166) — 단, 오케스트레이터 평면 자체가 무호출(DEBT#498) |
| unstaged-guard | manual | dead | 호출 스윕 0건(hooks·Makefile·workflows·src/tests 임포트) — standalone 존재만 — GateEnablement=false |
| verification-auditor | manual | unwired-helper | docs/spec/verification_oracle_contract.md:22,27 정확한 수동 명령 계약 |

## Check 10 — 음성 시험(위반 주입 → FAIL, 복원 → PASS)

| # | 주입 | 관측 |
|---|---|---|
| 1 | golden-master-gate에 `ci` 재선언 (lane 없음) | `FAIL — declares stage 'ci' but no production bin/gate_hook <stage> invocation lane exists (retired fa069d610)` |
| 2 | coverage-ratchet-gate에 `pre-commit` 추가 (hook 호출 없음) | `FAIL — declares stage 'pre-commit' but no invocation exists in .githooks/pre-commit` |
| 3 | anti-theater-gate stages=[] (minItems 위반 + 미선언 authority) | `FAIL — 'stages' must contain at least 1 stage (minItems; remove the gate instead — DEBT#425 precedent)` **+** `FAIL — invoked by .githooks/pre-commit but does not declare stage 'pre-commit' (undeclared authority)` |
| 복원 | 3케이스 원복 후 재실행 | `PASS — manifest consistent (54 gates validated)` |

추가로, 구현 과정에서 anti-theater-gate가 신규 Check 10 코드의 `except OSError: discard`(예외 삼킴)를 실제로 검출 → fail-closed(열거 실패 시 게이트 FAIL)로 수정 후 PASS — 게이트 체인의 살아있음이 관측됨.

## Authority 판정 불변 (before/after 스냅샷)

| gate | main 클론(변경 전) | 본 worktree(변경 후) |
|---|---|---|
| anti-theater-gate | exit 0 | exit 0 |
| layer-enforcement-gate --strict | exit 0 | exit 0 |
| stale-cert-gate | exit 0 | exit 0 |
| nim-check (변경 소스 대상) | — | PASS (corpusHash=6f08e160…, durationMs=9137) |

stages 선언 변경은 선언 투영(manifest.d)만 바꾸고 4개 authority의 실행·판정 경로는 전혀 건드리지 않는다(hooks는 manifest를 읽지 않고 직접 호출).

## Debt registry (Phase 3)

- **DEBT#483 흡수 갱신**: description에 2026-10-08 UPDATE 첨부(ci→manual 재선언, Check 10 기계검증, 24 SoC는 DEBT#500으로 분리) — 중복 엔트리 없음
- **DEBT#498 신규**(closed/WONT_FIX): orphan 파이프라인 시스템 원인(ci.yml 은퇴 → `bin/gate_hook ci` 소멸) + 41개 선언 철회 기록 + 재발 방지(Check 10) — anchor `src/gate/topology_spec.nim`
- **DEBT#499 신규**(closed/WONT_FIX): AGENTS.md §0.5c 문서-현실 갭(debt_integrity_gate는 orphan, 실제 강제는 `bin/debt_engine --validate`) — **AGENTS.md 불변(§-1)**, 레지스트리가 추적 차량
- **DEBT#500 신규**(closed/WONT_FIX): 24개 잠재 SoC 위변 수용(DEBT#491/492 선례, 계획 서면 승인 근거) — 재평가 트리거: runner 차단 배선 시
- 검증: `bin/debt_engine --codegen` + `--sync-budget`(BUDGET#005 43=43 재정렬) + `--regen-arch`(manifest_consistency_gate 정준 해시 갱신) + **`--validate` → "All debt validation checks passed"**

## Evidence 1–10 (수용 배터리)

| # | Acceptance | Procedure | Observation | Result |
|---|---|---|---|---|
| 1 | 54게이트 선언-호출 정합 green | `make check-manifest-consistency` | `PASS — manifest consistent (54 gates validated)` (Check 10 포함) | PASS |
| 2 | 토폴로지 SSOT 투영 무드리프트 | `make check-topology-drift` (커밋 후) | sync_topology 재생성 == HEAD (커밋 전 실행 시 예상대로 working-tree diff 검출 = 기능 정상) | PASS |
| 3 | 허위 주장 음성 차단 | Check 10 위반 3종 주입 | 3건 전부 FAIL(위 표), 복원 시 PASS | PASS |
| 4 | authority 판정 불변 | 4게이트 before/after 스냅샷 | exit 코드 3개 동일 + nim-check PASS (위 표) | PASS |
| 5 | 부정 변경 동일 차단 | 3케이스 뮤테이션(=#3) + 게이트 체인 자체 검출(anti-theater가 구현 결함 검출) + **PR-형태 재검증**: 거짓 `ci` 재선언 커밋(`7831987b5`)을 브랜치로 제출 → PR #600 | 병합 트리 게이트가 PR 헤드에서 동일 판정: `[manifest-consistency] FAIL — gate golden-master-gate declares stage 'ci' but no production bin/gate_hook <stage> invocation lane exists (retired fa069d610)`, exit=1; PR #600은 **미병합 close**. 추가 관측: `make` 경로는 sync_topology 드리프트-락스텝이 working-tree 위조를 자가 복구한 뒤 검증(커밋 위조는 게이트가 직접 판정) | PASS |
| 6 | 결정론 | `bin/ax report --canonical-digest` ×2 — 병합 main `aeb0dcaaa` | **`8f57931cf6047f24393a0f5181a8b2329907fb5b484aedeb8bb16dc1c6415c02` ×2 동일** | PASS |
| 7 | debt 정합 | `bin/debt_engine --codegen --validate --sync-budget` | All debt validation checks passed | PASS |
| 8 | 54게이트 분류 완결 | 본 문서 분류표 | 4+5+10+35=54, 전 row file:line 근거 | PASS |
| 9 | G7 + canonical digest ×2 — 병합 main `aeb0dcaaa` | `make verify-contract-release-e2e-full`; `bin/ax report --canonical-digest` ×2 | G7 **PASSED** (tier=z3-verified, lean-verify PASS). 첫 시도는 DEBT#471 선례와 동일하게 SourceCoherence fail-closed → 오류가 처방한 `make build` 재시딩(`bin/hermetic_build --check-source-hash` PASS: tree=embedded=-7337430478021113845) 후 통과. digest ×2 = 위 6과 동일 단일값 | PASS |
| 10 | 정상 PR → queue → main + required check·admission 동일 | GitHub 관측 (merge authority) | 정책 **v70 = PR #596 MERGED**(`31bf2b1e9`, 2026-10-08T07:58:19Z, merge queue 그룹 `pr-596-*`: landing-integrity·admission-gate PASS; 필수 체크 admission-check SUCCESS, advisory repository-surface FAIL은 v66/v67/#595와 동일 공개 프로파일). 본문 **PR #599 MERGED**(`aeb0dcaaa`, 2026-10-08T08:37:59Z, merge queue; admission-check SUCCESS + repository-surface **SUCCESS** — v70 재승인 하에서 bypass 없이 정상 착지, pre-push 전체 PASS). 부정 PR #600은 동일 게이트 판정 하에 미병합 close(위 5) | PASS |

## 범위 밖 (Follow-up)

- stage-dispatch 평면(gate_hook/orchestrator)의 재배선 — DEBT#498 등록, 재배선 시 lane 증거와 함께 `ci` 재선언 가능
- LG 카탈로그·착지 경로에 check-manifest-consistency 재편입 검토(현재 수동 계약 — ci.yml 은퇴 이래 공통 상태)
- AGENTS.md §0.5c 문구 교정 — 인간 아키텍트 승인 필요(§-1), DEBT#499가 추적
