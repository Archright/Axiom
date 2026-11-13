# VS-DEBT-1 재조사 원장 및 레지스트리 정합 복구 (2026-11-13)

- **Workstream**: `workstream/vs-debt-1-registry-reconciliation`
- **Base**: `main @ 923633f` (initial observation at `2f32580`; merged with PR #21/#22 landing `923633f`)
- **D3 폐쇄 권한 (MUST-T2a)**: 사용자 전면 승인(2026-11-13 4-Slice 계획 승인) — 인간 전용 D3 판정(`docs/evidence/stale_debt_verification_2026-11-02.md` 헤더)을 계획 승인이 대행.

---

## §1. 목적 및 반박 검증 결과 (설계 주장 교정)

### 1.1 Ultimate Purpose

부채 레지스트리(`data/debt_registry.json`, 정본)와 실제 소스코드의 관계를 건별 증거로 대조해, 해결된 부채만 정식 수명주기(ADR-0029 §5)로 폐쇄하고, 여전히 유효한 부채는 의도된 무마커 등록(`binding: "registry_disposition"`)으로 보존한다.

### 1.2 사전 설계 주장 반박 3건 (코드·실측 확정)

| 주장 | 판정 | 근거 (`file:line` + 실측) |
|---|---|---|
| "4275 − 17 = 4258이므로 17건을 폐쇄하면 nimtry 카운트 캡 4,259 이하로 내려간다" | **반박 (범주 오류)** | `nimtry_violation_count`(4,275)는 `data/nimtry_baseline.json` `["total_violations"]`에서 읽으며(`src/gate/runners/debt_integrity_gate.nim:177-181`), 레지스트리 파싱(`:240-248`)·마커 스캔(`:311`)과 완전히 분리된 코드 경로다. `evalNimtryViolations`(`tools/debt_engine.nim:1670-1686`)도 live `bin/nimtry src/`만 실행하고 레지스트리를 읽지 않는다. 17건 폐쇄의 nimtry 카운트 영향 = **0**. 실제 격차도 4275 − 4259 = **16**이지 17이 아니다. 캡 해소는 재앵커 시퀀스(`nimtry --update-baseline` + `debt_engine --regen-arch` + `debt_integrity_gate --update-baseline` + `--sync-budget`)의 문제로 본 슬라이스 범위 밖이다. |
| "BUDGET#005가 54 → 37로 동기화된다" | **교정 (모수 혼동)** | BUDGET#005는 `debt_registry_open` 미터릭(`data/debt_ledger.json:70-74`, evaluator `evalDebtRegistryOpen` `tools/debt_engine.nim:1624-1632` = `isOpen` 엔트리 수 = `open + deferred`; `isOpen` 정의 `src/core/debt/debt_registry_projection.nim:79-84`). 착수 전 실측: open 36 + deferred 18 = **54**(closed 203, 총 257). 37은 17건 전체 폐쇄를 가정한 수치였고, 증거상 폐쇄 가능한 2건(#506·#523)만 닫으면 기대값은 **54 − 2 = 52**(closed 203 → **205**, BUDGET#006). |
| "`debt_engine --validate` PASS 및 dev-mode STALE 감소가 운영 신뢰 경계 복구를 증명한다" | **교정 (지표 구분)** | `--validate`는 착수 전 이미 PASS(1616/1616)이며 STALE 검사를 포함하지 않는다. STALE 검사는 `debt_integrity_gate.nim:316-335`(Step 5)에만 있는데, `parseRegistry`(:240-248)가 `id`·`status`만 추출하고 **`binding` 필드를 전혀 읽지 않아** `open` + 무마커 항목은 `binding: "registry_disposition"` 보유와 무관하게 무조건 STALE로 플래그된다(게이트 자체도 orphan — DEBT#499 closed/WONT_FIX, 파이프라인 소비자 0). `docs/evidence/debt_binding_contract_2026-11-03.md:58`이 이 FAIL을 "정상"으로 문서 승인한 상태다. 따라서 STALE 17 → 15 감소는 **진단 지표**이며, 실제 정합성 증명은 본 원장과 `--codegen` / `--sync-budget` / `--validate` 3단계 통과다. |

---

## §2. 17건 STALE 전수 재조사 원장

판정 기준은 `docs/evidence/stale_debt_verification_2026-11-02.md` §1(still-holds / partially-holds / resolved / unverifiable)을 그대로 적용한다. 기존 10건은 2026-11-02 검증 결과를 계승·재확인하고, 신규 7건(#517–#525)은 금일 `main @ 2f32580`에서 전수 정적 관측·contentHash 재검증을 수행했다.

### 2.1 원장 총괄표 (17건)

| # | ID | 대상 표면 | 마커 부재 사유 (`binding`) | 검증 판정 | 본 슬라이스 처분 | 근거 요약 |
|---|---|---|---|---|---|---|
| 1 | DEBT-CI#003 | `.github/workflows/runner-pool-acceptance.yml` | 비-Nim YAML (`registry_disposition`) | still-holds | **OPEN 유지** | `:806-811`, `:915-920` 양 업로드 사이트 무 `overwrite` 현존 (2026-11-02 §3.1) |
| 2 | DEBT#432 | `Makefile`(FROZEN) + hist. `ci.yml` | FROZEN 표면 (`registry_disposition`) | partially-holds | **OPEN 유지** | 4종 테스트는 `f12ea744c`로 와이어됐으나 잔여 클레임 유효 (2026-11-02 §3.2) |
| 3 | DEBT#472 | `.github/workflows/certificate-mint.yml` | 비-Nim YAML (`registry_disposition`) | still-holds | **OPEN 유지** | SL-09 승격 시 재점검 조건부 (2026-11-02 §3.3) |
| 4 | DEBT#496 | `ast_to_ir.nim` 등 5개 Nim | ADR-0029 §5 승인 무마커 (`registry_disposition`) | still-holds | **OPEN 유지** | 도달가능성 0, loss flag fail-closed 현존 (2026-11-02 §3.4) |
| 5 | DEBT#504 | `proof_state_projection.nim:202` | rotation-class PR 대기 (`registry_disposition`) | still-holds | **OPEN 유지** | `trustedCheckerTreeClosure` 회전 대기, contentHash 완전 일치 재현 (2026-11-02 §3.5) |
| 6 | DEBT#505 | `counterexample_replay.nim:1234`, `rust_replay_adapter.nim:865` | nimtry dry-duplicates 앵커 처분 (`registry_disposition`) | partially-holds | **OPEN 유지** (선행 코드 작업 필요) | 엔트리 자체 서술: "extract one generic replay-orchestration skeleton … then resolve the anchor and close this entry — its own slice". 스켈레톤 추출 전 폐쇄 불가 |
| 7 | **DEBT#506** | `Makefile:883-935`, `axiom-operational-slice.yml`, `Makefile:943-947` | 비-Nim 매체 (`registry_disposition`) | **resolved** | **CLOSED (`FIXED`)** | 2026-11-02 §3.7 resolved 검증 + 금일 재확인: workflow `:92-109` `make ci-compile`(-d:release authority, `0d3336ae7`)이 E2E(`:143`)에 선행하고 타깃이 `bin/ax --check-provenance` 단언 |
| 8 | DEBT#507 | `decision_algebra.nim:188-228` | rotation 후속 (`registry_disposition`) | still-holds | **OPEN 유지** | pinned-file rotation 대기, CI는 G7-full verdict assert로 보상 중 (2026-11-02 §3.8) |
| 9 | DEBT#509 | `ci/checker.mk:16-17` 등 | 비-Nim 매체 (`registry_disposition`) | still-holds | **OPEN 유지** | 2026-11-02 §3.9 |
| 10 | DEBT#512 | `debt_integrity_gate.nim:60-62`, `debt_schema.json` | FROZEN 게이트 (`registry_disposition`) | still-holds | **OPEN 유지** | ADR-0038 pending, STALE 상태 자체를 등록한 항목 (2026-11-02 §3.10) |
| 11 | DEBT#517 | `config.nims:118-145, 147-215` | NimScript 매체 (`registry_disposition`) | still-holds (금일 신규 검증) | **OPEN 유지** | `computeSourceHash(path)` 인자 참조 0회, 고정 5-파일 gorge 해시, `buildGateRunners` 자동 호출자 0건, contentHash `7a3c48a8…` 완전 재현 |
| 12 | DEBT#518 | `config.nims:203-215` | NimScript 매체 (`registry_disposition`) | still-holds (금일 신규 검증) | **OPEN 유지** | `binary_checksums.json`에 5-파일 소스 해시 기록·G1 문서 괴리·소비자 0건, contentHash `29b8a761…` 완전 재현 |
| 13 | DEBT#519 | `config.nims:114-119, 204` | NimScript 주석 (`registry_disposition`) | still-holds (금일 신규 검증) | **OPEN 유지** | 허위 주석 3종(zero shell / FarmHash / matches integrity.nims) 현존, `config/integrity.nims:50-63` 상이 체인 대조 확인 |
| 14 | DEBT#520 | `src/gate/runners/gate_hook.nim:399-400` | FROZEN `src/gate/**` (`registry_disposition`) | still-holds (금일 신규 검증) | **OPEN 유지** | `repoRoot / g.entry` 확장자 미해석 그대로, `src/gate/manifest.d/` 54개 중 비-`.nim` 40 / `.nim` 14 정확 재현 |
| 15 | **DEBT#523** | `src/core/gate/gate_cas.nim` | 미래 설계 제약 등록 (`registry_disposition`) | **resolved-by-adjudication** | **CLOSED (`FIXED`)** | `bindingRationale`에 `resolved-by-observation 2026-11-09` + Owner 최종 판정("CAS 공유 범위는 현재 워크트리 내부로 한정", F 기각, `docs/evidence/ef_cas_isolation_verdict_2026-11-09.md` §2·§7) 이미 기록. 고정 정책 하에서 교차 워크트리 오재사용 경로 불가능. 재오픈 조건 3항 보존 |
| 16 | DEBT#524 | `src/core/gate/gate_cas.nim:180,202,241-242` | 조건부 등록 (`registry_disposition`) | still-holds (금일 신규 검증) | **OPEN 유지** | `fileExists(casBinary)` 단일 HIT 판정·저장 digest 비교 부재·`getBinaryHash` 호출자 0건 현존 (#523 재오픈 조건 (3)의 짝 항목) |
| 17 | **DEBT#525** | `src/core/gate/cache_manifest.nim:1-81`, `tests/features/cache_manifest.feature` | `main @ 923633f`(VS-2 `389fa03`)에서 코드 마커(`const debtMarker525 {.axiomDebt: "DEBT#525".} = true`)로 바인딩 완료 | still-holds (금일 신규 검증) | **OPEN 유지** (코드 마커 바인딩 보존) | 극장 요소 3종(`computeContentHash` `$payload` 반환 `:31-36`, `compactManifests` 무조건 ok `:79-81`, `.axiom/cache/manifests` 부재 `:28`) 및 importer 0건 현존. `389fa03`이 코드 마커 바인딩을 부여했으므로 중복 `registry_disposition` 없이 `marker-bound` 분류 그대로 보존 |

주의: `bin/debt_engine --prune` dry-run이 표시하는 "files missing" 4건(#506/#507/#509/#512)은 `cmdPrune`(`tools/debt_engine.nim:2004-2007`)이 `Makefile:883-935` 형태의 라인 범위 접미사를 제거하지 않는 오탐이며, `--validate`의 live-file 검사(`:1319-1335`)는 접미사 제거 후 정상 통과한다.

### 2.2 신규 7건(#517–#525) 상세 검증 기록

- **공통 git 맥락**: 7건 모두 Clean-Room Gen-4 초기 베이스라인 `c021c33`(2026-11-12)에 레지스트리와 함께 착지했고 이후 본체 미수정. 대상 파일 중 `gate_hook.nim`·`gate_cas.nim`·`cache_manifest.nim`·`cache_manifest.feature`는 `c021c33` 이후 변경 0건, `config.nims`는 hermetic 빌드 영역(`764e108`·`910155e`)만 변경되어 결함 블록(`:114-215`)은 바이트 불변(+7 라인 이동만 존재).
- **DEBT#517 (`still-holds`)**: `config.nims:118-145` `computeSourceHash(path)` 본문에서 `path` 참조 0회, 고정 5-파일(`gate_hook.nim`, `orchestrator_hook.nim`, `gate_utils.nim`, `git.nim`, `types.nim`) `gorge("sha256sum …")` 320-hex 반환; `buildGateRunners`(`:147-215`) 6 러너 중 5종 소스가 5-파일 집합 밖. 자동 호출자 전 저장소 grep 0건. 블록 sha256 `7a3c48a8caae0d2cf862aa4201e2a6feaf69c61503e534a92610888156f0cf38` 등록값과 완전 일치.
- **DEBT#518 (`still-holds`)**: `config.nims:203-215`가 `computeSourceHash(bin)`(5-파일 소스 해시)을 `.axiom/cache/binary_checksums.json`에 기록하고 `"Binary checksums saved (atomic)"` 출력; `docs/spec/gorge_inventory.md:28` G1 원 의도(`sha256sum <bin>`)와 괴리 유지. `src/` 소비자 0건. 블록 sha256 `29b8a761f490181f8f82e9d09bbfc6d9ad9460beb0676d6500602584e8d9c8a9` 완전 일치.
- **DEBT#519 (`still-holds`)**: `config.nims:114-115`("zero external shell dependency", "std/hashes hash() + readFile"), `:119`("matches config/integrity.nims merkle algorithm" — 실제 `config/integrity.nims:50-63`은 서로소인 4개 `src/core/trusted` 파일 개별 해시 후 최종 sha256 1회), `:204`("std/hashes FarmHash — no external shell") 허위 주석 3종 현존. (등록 `contentHash` `fc83bfed…`는 슬라이싱 규약 미재현으로 비고 기록 — 2026-11-02 템플릿 DEBT#512 사례와 동일.)
- **DEBT#520 (`still-holds`)**: `src/gate/runners/gate_hook.nim:399-400` `let srcPath = repoRoot / g.entry; if fileExists(srcPath):` 그대로; `src/gate/manifest.d/*.json` 54개 엔트리 중 `.nim` 접미 14 / 비-`.nim` 40 실측 재현.
- **DEBT#523 (`resolved-by-adjudication` → CLOSED)**: `gate_cas.nim:58-95, 112+` 클로저 키의 소스 전용 해싱 자체는 구조 특성으로 남아 있으나, `bindingRationale`에 기록된 `docs/evidence/ef_cas_isolation_verdict_2026-11-09.md` §2(2-워크트리 54-키 매트릭스: 50/54 바이트 동일, 4/54 경로 임베딩 자체 빌드 증명, 교차 조회 0) 및 §7(2026-11-09 Owner 판정: "CAS 공유 범위는 현재 워크트리 내부로 한정", F 병렬화 기각)에 의해 등록 당시의 미결 조건("revisit before any cross-worktree CAS sharing")이 고정 정책으로 종결됨. 재오픈 조건 3항은 `bindingRationale` 및 `resolutionNote`에 보존하고, 무결성 검증 짝 항목인 DEBT#524는 OPEN으로 유지한다.
- **DEBT#524 (`still-holds`)**: `gate_cas.nim:180, 202, 241-242` `if fileExists(casBinary): return casBinary` 단일 판정, 파일 내 `digest` 매치 0건, `getBinaryHash`(`:156-166`) 호출자 0건, `precompile_gates.nim:545-551` 결측만 재빌드 그대로 관측.
- **DEBT#525 (`still-holds` + `binding` 보강)**: `src/core/gate/cache_manifest.nim`(81행) sha256 `68edad41b5f74ce386c7c85c5aecd03255b17a35e1c02ad074115b6da9c9aaac` 완전 일치, repo-wide importer 0건, `{.axiomDebt.}` 마커 0건, 극장 요소 3종(`computeContentHash` `$payload` 반환 `:31-36`, `compactManifests` 무조건 `ok: true` `:79-81`, `.axiom/cache/manifests` 미존재 `:28`) 그대로. 일반 Nim 모듈이므로 구문상 프라그마 삽입은 가능하나, 엔트리 `resolution`이 명시하듯 모듈·spec 삭제 자체가 Owner 결정 대기 사안이고 코드 편집은 등록된 `contentHash` 결속을 깨뜨리므로 최소 변경 원칙(§0.12, §2.2)에 따라 `binding: "registry_disposition"` + `bindingRationale`을 부여해 17건 전원의 바인딩 스키마 일관성을 확립한다.

---

## §3. 실행 및 기계 검증 증거

`main @ 923633f`(`389fa03`)에서 착지한 원자적 5-단계 폐쇄 명령 `bin/debt_engine --close DEBT#506 ...` 및 `bin/debt_engine --close DEBT#523 ...`(`validate → mutate SSOT → regenerate P1 → sync P2 ledger → re-validate`)을 그대로 실행했다.

### 3.1 `bin/debt_engine --close DEBT#506` & `--close DEBT#523`

- 원자적 갱신 파일: `data/debt_registry.json`, `docs/DEBT_REGISTRY.md`, `src/generated/debt_constants.nim`, `data/debt_ledger.json` (`ProjectionStatus: P1=complete P2=synced`).
- `BUDGET#005` (`debt_registry_open`): `current: 54 → 52` (`status: open`, `open: 35 + deferred: 17 = 52`).
- `BUDGET#006` (`debt_registry_closed`): `current: 204 → 206` (`status: closed`, 총 258 엔트리).
- 사전 계산 기대값(`54 - 2 = 52`)과 evaluator 산출값이 정확히 일치한다.

### 3.2 `bin/debt_engine --validate` (in-process post-validation)

```
Checks: 1621 total, 1621 passed, 0 failed
Metric evaluation: 6 PASS, 0 DRIFT
Post-validation passed.
EXIT=0
```

### 3.3 `bin/debt_integrity_gate` (release 빌드 정식 게이트)

```
[INFO] [debt-integrity-gate]: nimtry — Active Violations: 4275 / Historical Baseline Cap: 4275
[INFO] [debt-integrity-gate]: Registry: 258 entries (35 open, 0 accepted)
[INFO] [debt-integrity-gate]: Open: 20 marker-bound, 15 registry_disposition-bound (rationale verified)
[INFO] [debt-integrity-gate]: Code: 24 {.axiomDebt.} markers found
[INFO] [debt-integrity-gate]: All 35 open debts have code markers. PASS.
GATE_EXIT=0
```

- `registry_disposition-bound` open 엔트리가 **17(구 STALE) → 16(`389fa03`의 `#525` 코드 마커 전환) → 15(본 슬라이스의 `#506`, `#523` 폐쇄)**로 감소했고, 잔여 15건 전원의 `bindingRationale` 비공백 계약 및 20건 `marker-bound` 양방향 바인딩이 `GATE_EXIT=0`으로 검증됐다.
