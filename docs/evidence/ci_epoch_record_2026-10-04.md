# CI Epoch Record — authority/identity/DAG restructuring (2026-10-04)

> §2.5 CI Epoch Cutover, 단계 1–2 (Freeze · Record). 정본 규칙: `AGENTS.md` §2.5 / `docs/agents/ci_epoch_cutover.md`.
> 이 기록은 **롤백 기준선**과 **원자 결속(binding) 대상 목록**을 고정한다.

## 1. Freeze (단계 1)

| 항목 | 값 |
|---|---|
| freeze tag | `ci-epoch-pre-authority-structure-2026-10-04` (annotated) |
| HEAD at freeze | `959b1fd8476603a369f417bb6161675d0b3945fb` |
| workstream branch | `fix/ci-authority-verdict-dag` (§2.1 — `main` 아님) |
| 기존 freeze 태그 (참고) | `ci-epoch-pre-mq-freeze`, `ci-epoch-pre-scope-freeze` |

### 전이 작업 트리 상태 (2026-10-04 소각 승인 수령)

Freeze 시점에 `main` 작업 트리에 **미커MITTED 변경**이 존재했다. 이는 본 epoch의 소유물이 아니었고, 다른 위치에서 동일 내용으로 별도 작업이 진행 중이어서 **사용자의 명시적 승인(2026-10-04)으로 소거**되었다. 소거 직전 전체 diff를 `tmp/preserve/pre-cleanup-20261004-105909.patch` (4137줄)로 보존했다.

소거된 경로(요약): `src/gate/orchestrator.nim`(삭제) · `src/gate/{gateway,orchestrator_hook,predicates/base,resource_guard,static_gate_scanner,handlers/security_handlers}.nim` · `src/gate/runners/{gate_hook,readiness_start_gate}.nim` · `src/core/trusted/{axiom_pragmas_macros,env_access,env_types}.nim` · `src/generated/debt_constants.nim` · `tools/{decision_binding_checker,hermetic_build}.nim` · `tests/{gateway/import_encapsulation_gate_feature_test,test_gate_matrix}.nim` · `docs/spec/{architecture_v2,decision_binding_framework,github_delegation_residuals,productization_contract,provenance_contract_v3}.md` · `docs/agents/operations.md` · `data/trusted/**`

보존된 경로(본 epoch 소유): `Makefile` · `ci/checker.mk` · `.github/workflows/runner-pool-acceptance.yml` · `src/cli/axiom_engine.nim` · `src/verification/**` · `src/gate/runners/evidence_truth_boundary_gate.nim` · `tools/local_purity_check.nim` · `tests/unit/report_engine_test.nim` · `docs/spec/{execution_accounting_contract,verification_dag_contract,merge_admission_controller}.md` · `docs/agents/{merge_admission_observation,ci_epoch_cutover}.md` · `data/debt_registry.json` · `docs/DEBT_REGISTRY.md` · `docs/adr/0028-*.md`

## 2. Record (단계 2) — 신뢰·권위 binding

### 2.1 admission binding

`config/policy/merge_admission.json` **v1.9.0**

| 항목 | 값 |
|---|---|
| `requiredValidations` | 단일: `.github/workflows/admission-check.yml`, `workflowId 365692388`, job `admission-check`, `acceptableConclusion: "success"` |
| `requiredWorkflowDetection` | org ruleset `Archright/.github/.github/workflows/admission-gate.yml`, `repositoryId 1182157951`, `verdictJob: admission-check` |
| `certRequired` | `true` |
| `speculativeDepth` | `3` |
| 코드 이중 결속 | `src/cli/merge_cli.nim` `RequiredChecks = @["admission-check"]` / `RequiredWorkflowIds = @[("admission-check", 365692388)]` |

### 2.2 trustSurface (11) — 변경 시 auto-merge 거부

```
.github/workflows/repository_surface.yml
.github/workflows/runner-pool-acceptance.yml      ← 본 epoch가 수정
.github/workflows/admission-check.yml
.github/workflows/certificate-mint.yml
.github/actions/setup-axiom-toolchain/**
config/policy/merge_admission.json
config/app_landing_binding.json
config/executor_authority.json
config/trusted_writer_set.json
src/cli/merge_cli.nim
src/verification/verification_subject.nim
```

### 2.3 writer pin — **원자 결속 대상**

`config/trusted_writer_set.json`

| 키 | 값 | 본 epoch 영향 |
|---|---|---|
| `trustedWriterWorkflow` | `.github/workflows/certificate-mint.yml` | 무변경 |
| `trustedAdmissionWorkflowSha` | `62d150b8266a9a8b8138b8191fff5a1abdfbf930` | `admission-check.yml` 변경 시 회전 |
| `trustedCheckerTreeClosure["ci/checker.mk"].sha` | `cef1df553ca83221b59d03d7fa21d1c3637bf8bf` | **`ci/checker.mk` 변경 시 회전 필수** |

> **§2.5 단계 5 Atomic Binding Update**: 파일 변경과 pin/digest 갱신은 **하나의 논리적 cutover 단위**에서 이뤄진다. 일부만 갱신된 상태(digest 불일치)는 **fail-closed**이며 허용되지 않는다.

### 2.4 cache binding

| 계층 | key | writer |
|---|---|---|
| A (toolchain) | `axiom-a-<os>-<gcc_fp>-<glibc_fp>-<script_hash>` | composite action (job-local) |
| B (build artifacts) | `axiom-b-<treeOID>-<recipe_hash><a_fp>` | **`ci-cache-publisher.yml` 단독** (`workflow_run` on `admission-gate` completed, default-branch scope) |

`restore-keys` 금지 계약 유지 (`.github/actions/setup-axiom-toolchain/action.yml:65-67`).

### 2.5 B1 단일 생성 authority — 확장 대상 (기존 규칙)

`.github/workflows/runner-pool-acceptance.yml:590-594`

```
# B1 생성 authority 정규성: candidate-산출물/arch → authority = 이 잡 1개/arch,
# shard 재생성 0 (compile=0 — shard는 download-artifact 소비만).
```

x64 `ci-bootstrap`(ubuntu-24.04) · arm64 `candidate-build-arm`(ubuntu-24.04-arm) — **producer가 둘**이며 전역 단일 producer가 아니다. 본 epoch는 이 패턴을 10개 바이너리로 **확장**한다.

## 3. Baseline 측정 (Record 시점)

| 지표 | 값 | 근거 |
|---|---|---|
| 라이브 admission 벽시계 | **406–419 s** | `docs/evidence/ci_structural_duplicate_census_2026-09-30.md:13-19` |
| base compile | 182–195 s (구조적 콜드) | 같은 문서 §2.1 |
| shard당 `nim c` | 10개 × 8 legs = **80회 중복** (총 105 컴파일) | `ci/checker.mk:86-94,109,316-317` |
| B-cache HIT | **0 / 8** | 같은 문서 §2.1 |
| critical path toolchain | 248 s | run 36572463965 |

> 옛 `ci.yml` 74분 수치는 tombstone 기준이므로 사용하지 않는다.

## 4. 실제 실행 증거 (2026-10-04)

`make -n` 계획이 아니라 **실제 실행**으로 확인한 항목:

| 항목 | 결과 |
|---|---|
| `make gateway-binaries` | 102.8 s, exit 0, 8 product |
| `make ci-compile` | 100.1 s, exit 0, 4 product. nimcache `{ax,gate_hook,precompile_gates}`에 1259 / 271 / 115 object |
| `make verify-contract` | 224.88 s, exit 0, `[PASS] g2/g1/g6g4/g7`, status 파일 4개 모두 순수 정수 |
| DEBT#481 레이스 시그니처 | **0건** (`can't create`·`cannot find`·`Integrity Violation`·`IOError`·`Illegal number`·`No such file`) |
| producer manifest ↔ consumer sha256 | 14/14 일치, **1바이트 변조 감지 실증** |
| consume 모드 fail-closed | 빈 루트 → exit 2, product 단위, 비실행 파일 검출 |
| EMPTY 6케이스 | 무기록→FAIL / 유효기록→exit 0 + 13개 LG-* RECORDED N/A / 나머지 4종→FAIL |
| 결정론 | 8 product 중 6개 byte-identical 재현 |
| producer 빌드 총량 | ≈3.5 min (14 product, x64) |

### 4.1 본 epoch가 도입 후 수정한 fail-open (회귀)

`Makefile:536`의 `contract_fanout` 매크로가 `$$$$?`를 사용했다. 본문이 `$(call)`로 한 번, recipe로 한 번 더 확장되어 셸에 `$$?` = **PID + `?`**가 전달되고, status 파일이 `850676?`가 되었다. join의 `[ "$status" -ne 0 ]`가 "Illegal number"로 실패해 else 분기 = **`[PASS]` 무조건 출력**이 되었다. 실제 exit 2였던 `g1`이 `[PASS] g1`로 보고되었다. `HEAD`의 인라인 `$$?`는 정상이었고, 회귀는 `$(call)` 리팩터링이 만든 것이다. `ci/checker.mk:430-432`는 직접 `$$?`를 써서 영향이 없다.

→ `echo $$? > …$(1).status`로 수정. A/B 실증: 수정 전 `[PASS] bad` / 수정 후 `[FAIL] bad (exit code: 1)`. Negative control 포함.

## 5. pin drift 감사 — **두 기준 분리**

`config/trusted_writer_set.json` `trustedCheckerTreeClosure`는 **840개** 항목. 본 절은 **HEAD 기준과 worktree 기준을 분리**해 기록한다(§5.1 재현 명령 참조).

### 5.1 재현 명령

```bash
git ls-tree -r HEAD > /tmp/h.txt
python3 - /tmp/h.txt <<'PY'   # JSONC 주석 제거 포함, 자체 완결
```

관측 결과: **total=840 · stale@HEAD=22 · HEAD-match/worktree-drift=7 · missing=0**
(840 = 811 exact + 22 stale@HEAD + 7 worktree drift)

### 5.2 표 A — HEAD에서 이미 stale (22, 본 epoch 이전부터 존재)

대표: `config.nims` · `src/cli/{axiom_engine,cli_outcome,landing_cli,merge_cli,precompile_gates,wf_runners}.nim` · `src/core/trusted/trust_commit.nim` · `src/core/utils/canonical_projection.nim` · `src/gate/daemon/{gate_daemon_client,gate_daemon_types}.nim` · `src/gate/orchestrator/hook/memo.nim` · `src/gate/topology_spec.nim` · `src/verification/accounting/run_accounting.nim` · `src/verification/batch_uap/{loop_depth_scheduler,loop_driver}.nim` · `src/verification/obligation/{canonical_verification,lean_kernel_boundary,verification_decision_authority}.nim` · `src/verification/report_engine.nim` · `tools/ci/{impact_closure_selector,proof_reconcile_gate}.nim`

### 5.3 표 B — HEAD에서는 일치, worktree에서만 어긋남 (본 epoch 소유)

| 경로 | pin | HEAD | worktree | 소유 |
|---|---|---|---|---|
| `ci/checker.mk` | `cef1df55…` | `cef1df55…` ✅ | `be9e216e…` | **본 epoch** |
| `src/verification/obligation/identity.nim` | `f941576e…` | `f941576e…` ✅ | `7782203d…` | **본 epoch** |

### 5.4 closure membership 실측 (2026-10-04)

`tools/ci/derive_checker_closure.nim`을 H에 대해 실제 실행(`git ls-tree -r --full-tree`, `:469-470`):

| | 값 |
|---|---|
| `pinBSet` 라인 수 | **840** |
| `derived(H)` 라인 수 | **841** |
| membership **ADD** | **1 — `src/core/utils/decision_algebra.nim`** |
| membership REMOVE | 0 |
| sha-only divergence | 22 (표 A와 정확히 일치) |
| `closureEqual` | false → ROTATION 후보 |

`src/verification/accounting/execution_context.nim`은 untracked라 HEAD 트리에 없고, deriver는 설계상 worktree 무지(git ref만 수신)라 **착지 후** `--ref <H commit>` 재실행 시 추가 +1이 예상된다.

### 5.5 결론 — 기계적 재해시가 아니다

`docs/adr/0025-gateway-landing-authority.md:321-322` — "**closure 멤버 추가·제거 자체가 승인 대상**". 멤버십이 실제로 변경되므로(§5.4) 순수 sha 재입력이 아니다.

### 5.6 회전 미수행 사유 (BLOCKED — 인간 아키텍트 결정 필요)

**단일 차단 사유: `ROT_OLD_PIN`.**

```
closureEqual=false (merge_cli.nim:488) → rqRotation
allowlistOk=true   (merge_cli.nim:500-505)   ← drift 경로가 전부 pin@B key
oldAnchorOk=false  (merge_cli.nim:510)       ← line-set(pin@B) != set(B)
→ rqNone / ROT_OLD_PIN (merge_cli.nim:522-527)
```

`oldAnchorOk = genesis ∨ line-set(pin@B) == set(B)`이므로 H 기준으로 sha를 완벽히 재해시해도 `oldAnchorOk`는 B와 비교되므로 건드리지 못한다. sha drift 22건과 membership +1이 **모두 이 한 조건**을 깨뜨린다.

> **정정**: 이전 판정에서 "`identity.nim`이 A2 회전 allowlist 밖이라 차단"이라고 적은 것은 **틀렸다**. `identity.nim`은 pin key(클로저 멤버)이고 allowlist ①은 "pin@B keys"를 포함한다(`merge_cli.nim:466-469`). `RotationAllowlistExtra`(`:115-122`)는 보조 companion 경로 목록일 뿐이다.

**"re-anchor"/"re-baseline"은 제3의 허가 범주가 아니다** — `adjudicateRotation`(`:475-538`)의 출력은 `rqNormal|rqRotation|rqNone|rqUnspecified` 4개뿐이고, `ADR-0025:209-211`은 "**시스템 증설 금지** … SHA/closure 교체 lifecycle 절차 하나가 유일한 갱신 경로"라고 못박는다.

**게이트 휴면 상태(독립 확인)**: `derived-closure`를 업로드하는 코드가 없고 env 3종이 부재해 `rqUnspecified` → Pass 2.97 스킵. 게다가 핀 파일이 trustSurface라 Pass 2.7이 먼저 단락(`:644` vs `:718`) → `TRUST_SURFACE_MODIFIED` → `dryRunExit` 0(`:759-760`) → architect 수동 merge 경로. **게이트 잠잠함은 승인이 아니라 무판정**이다.

**권한 경로**: ① CODEOWNERS `@architect` 승인(`.github/CODEOWNERS:34`) ② trustSurface 수동 merge ③ 규칙 변경 시 ADR A2 (iv) 개정(`ADR-0025:476-478`). `decision_binding.waiver`와 `break_glass_protocol`은 회전 판정기에 무관.

## 6. 다음 단계

단계 4 New Epoch(완료) · 단계 5 Atomic Binding Update(**BLOCKED** — §5.6) · 단계 6 Local/Targeted Verification(일부 완료 — §4) · 단계 7 Short Validation · 단계 8 Canonical Cutover(단계 5에 의존) · 단계 9 Production Acceptance(**아키텍트 수동 merge 필요** — `docs/agents/rules_workflow.md:128` MUST-T2) · 단계 10 Rollback(§1 tag).

> 단계 9는 trust-surface PR의 정상 착지 경로가 인간 수동 merge다. `dryRunExit`이 0이라 `admission-check`는 GREEN으로 착지하지만, **green ≠ landing authority**(`AGENTS.md` §2.3 — GitHub이 최종 판정).

## 7. 용어 고정

### 7.1 `executionEpoch` vs `ciGeneration`

정본 정의는 `docs/spec/execution_accounting_contract.md` §15.4(`executionEpoch` = identity 성분, `ciGeneration` = 절대 identity 성분 아님, wire 필드 `currentEpoch`/`validatedAtEpoch`는 호환성 위해 유지), `docs/spec/merge_admission_controller.md` §2b(3종 구분), `docs/agents/ci_epoch_cutover.md`(용어 구분 절).

### 7.2 reuse ≠ reproduction

`docs/spec/execution_accounting_contract.md` §15.0. 캐시 적중은 **이전 결과의 재사용**이며 reproduction이 아니다. 현재 context에 대해 재검증될 때에만 authoritative reuse. negative half 유지: "**캐시는 가속일 뿐 증거가 아니며 판정 입력도 아니다**"(J3). 단 "캐시가 실행-의미론 입력이 아니다"로 과잉 교정하지 않는다(`docs/spec/ci_optimization_tcb_judgments.md:146`).

### 7.3 platform 잔여

`platform`이 `linux-x86_64` 하드코딩 리터럴이었고 CI는 `ubuntu-24.04-arm`에서 도는 동안 arch 축이 판별력을 잃었다. → `src/verification/obligation/identity.nim:106-115`의 `hostPlatformId`로 실측값화, 측정 지점을 `src/verification/accounting/execution_context.nim` 하나로 수렴(§0.2 Fundamental).

### 7.4 Red-team 기각 사항

재제안되지 않도록 기록한다:
- (a) publisher를 producer post-step `actions/cache/save`로 대체 — GitHub cache는 branch-scoped라 PR-scope 저장은 다음 PR에서 가시 불가, publisher는 run-level 성공 게이트
- (b) `producer/workflow identity`를 artifact identity에 결속 — provenance의 identity digest 진입 금지(`src/verification/run_identity.nim:13,20`), 재실행이 identity를 바꾸면 안 됨
- (c) `orchestrationVerified`/`FreshExecutionObservedSet` 일괄 차단 — 범위가 과도. 금지 대상은 **cache-derived state의 fresh-execution witness 승격**뿐이며 genuine fresh execution은 정상
- (d) G7 제거 — exit↔summary 정합성의 유일 독립 관측자(`Makefile:723-728`)이므로 제거는 independent observation 삭제

## 8. 미폐쇄 등록 — Open register (deferred, NOT fixed)

`AGENTS.md` §0.9 (극장 금지): a deferral that is not recorded is indistinguishable from a gap nobody looked for. Three items were investigated during this workstream and consciously **deferred**; none of them appears anywhere else in this record. They are registered here. **None is closed. None is a fix.**

Every claim below was re-verified against the working tree on 2026-10-04. Cited line numbers are from the **current worktree state**, not from `HEAD`, unless the text says `HEAD:`.

### 8.1 R6 part 3 of 3 — NOT performed (deferred; the code defect in parts 1–2 is closed)

The R6 fix restored `src/verification/obligation/verification_decision_authority.nim` (VDA) as the single writer of `runOutcome.verdict` / `.basis` / `.gateVerdict`. It had three parts:

| Part | Scope | Status |
|---|---|---|
| 1 | delete `applyRestoredStateFailClosed` | **done**, machine-verified |
| 2 | decide through VDA's `makeRunOutcomeVerdict` | **done**, machine-verified |
| 3 | retire the content-free scenarios that assert the *old* restored-state behaviour | **NOT PERFORMED** |

**Part 1** — `applyRestoredStateFailClosed` is **0 occurrences repo-wide** (grep over `*.nim`, `*.md`, `*.json`).

**Part 2** — `makeRunOutcomeVerdict` is **called from exactly 2 sites**, `verification_decision_authority.nim:283` and `:335` (definition at `:200`). No other module calls it; `src/gate/runners/evidence_truth_boundary_gate.nim:135` names the symbol only as a `SymbolGuard` ownership assertion. The deciding case is asserted at `tests/unit/report_engine_test.nim:263-281` — zero reused rows (`demoteRestoredReusedUnits == 0`) plus envelope mismatch ⇒ `vrInconclusive` / `rbNone` / `gvFail` (checks at `:273-275`).

**Part 3 is open.** `tests/features/generated/report_engine.feature:17-23` still carries the content-free pair "func loadReportProofState is callable" / "func computeReportExitCode is callable", each asserting only "…should return a valid value".

#### 8.1.1 Why it was not performed (six points, all verified)

1. **Regeneration is impossible.** `tools/feature_scaffold_generator.nim:268-270` — `if fileExists(outPath): stats.skipped += 1; return`. An existing scaffold is skipped, never rewritten, so running the generator cannot refresh this file.
2. **Nothing executes it.** `tools/feature_runner_compiler.nim:624` walks `walkFiles("tests/features/*.feature")` — top level only. `tests/features/generated/**` is outside the walk, and no other executor consumes that directory.
3. **The generator itself declares them non-executable.** Header, `tools/feature_scaffold_generator.nim:4-10`: the outputs are "structured TODO manifests with generation markers — **NOT executable tests**".
4. **The manifest records it as SSOT, with no runner.** `data/feature_manifest.json` → entry `report_engine`: `"path": "generated/report_engine.feature"`, `"runner": ""`. Derived at `tools/feature_manifest_generator.nim:148` through `findRunner` (`:52-63`), which searches **only** `tests/gateway/` (`:119`) for `<name>_feature_test.nim` and returns `""` when absent; `tests/gateway/report_engine_feature_test.nim` does not exist. Structural note: the runner compiler writes its output to `tests/generated/` (`feature_runner_compiler.nim:626`), a directory `findRunner` never consults — so for any `generated/` feature the `runner` field is `""` **by construction**, not by oversight.
5. **…but the directory is consumed as spec-presence evidence.** `src/gate/runners/spec_presence_gate.nim:125-128` (`walkDirRec(FeaturesDir)` filtered on `.feature`, with `FeaturesDir = "tests/features/"` at `:44`) and `tools/feature_manifest_generator.nim:128-130` (the same recursive walk, feeding the manifest's 770 entries — 423 `generated`, 347 hand-written). Removing or emptying the directory is therefore not neutral: it changes spec-presence inputs.
6. **Editing the file makes `data/` stale, and `data/` is owned elsewhere.** `computeSourceHash` (`tools/feature_manifest_generator.nim:86-102`) hashes each `.feature`'s relative path **plus content** into `source_hash` (`:189`); `verifyFeatureManifest` (`:196-200`) recomputes and reports STALE on any content change, by design rather than by mtime. Refreshing it means rewriting `data/feature_manifest.json`, which this workstream does not own.

#### 8.1.2 Gate status — this is **not** currently red

Stub-density gates do not scan `.feature`:

- `tools/ci/verify_stubs.nim:59-60` — `walkDir(srcCore)` filtered by `path.endsWith(".nim")`.
- `src/gate/runners/anti_theater_gate.nim:50-52` (`matchesSrcOrToolsNim`) and `:54-55` (`matchesTestNim`) — both require `fileName.endsWith(".nim")`.

So these scenarios are invisible to the `AGENTS.md` §0.8 stub-density gate and to the anti-theater scan. **"Not red" is not "closed"**: the defect is real and is simply unobserved by the current gate set.

#### 8.1.3 Decision — DEFERRED, contract decision required

Closing part 3 requires deciding what a `.feature` file **means** in this repository. That is an `AGENTS.md` §0.12 / §0.10 contract question, not a CI-restructuring one. Three options were sketched; **none is chosen here**:

- **Option A — tag enforcement (make it executable).** Widen the compile walk to `tests/features/generated/**`, or add a second compile pass, and give the scaffold scenarios real assertions. Cost: 423 generated scaffolds become test surface at once with undefined scenario semantics, and the generator must stop skipping existing files (`:268-270`) or every file becomes hand-maintained.
- **Option B — manifest-as-spec-input (make it explicitly inert).** Declare `data/feature_manifest.json` + `spec_presence_gate` the spec-presence SSOT and treat every `.feature` as non-executable evidence. Then the current text is acceptable but misleading, and the correct follow-up is to regenerate scaffolds with explicit non-executable markers instead of assertion-shaped wording.
- **Option C — retire the directory.** Delete `tests/features/generated/**` and stop emitting it from `feature_scaffold_generator.nim`. Spec-presence would then rest on the 347 hand-written features alone, changing the manifest's `total_count` / `generated_count` and the gate's existing-feature set.

Not chosen because all three amend what the contract asserts, which belongs to the contract owner; selecting one here would be an unauthorised contract change. **Status: DEFERRED — contract decision pending. Not fixed. Not closed.**

### 8.2 `docs/spec/verification_dag_contract.md:102` — a spec statement that is now false (flagged, NOT amended)

`docs/spec/verification_dag_contract.md` §9 "병렬화 안전성 3계층", item 2 (Host-global state) asserts in the same line: *"유일한 실제 동시성 race는 GitHub-side actions/cache save였으며"* — the only real concurrency race was the GitHub-side actions/cache save.

The same line also cites `flock per-host singleton(tools/ci/runner/jit_supervisor.sh:67-68)` as load-bearing, and then records — in the same sentence — that its source (`docs/spec/self_hosted_ci_migration.md:154-161`) was deleted by the CI=0 cutover (2026-09-20) with "러너 인프라 제거로 해당 singleton도 소멸". It therefore states as an invariant a mechanism the same sentence reports as already gone.

**Superseded by this workstream's findings.** `tools/local_purity_check.nim` pinned a single fixed path — `PureCheckRoot = getHomeDir() / ".cache" / "axiom" / "purity-check"` (`:96`) — with no locking, so two concurrent invocations raced on one mutable git worktree (`reset --hard`, `clean -ffdx`, `worktree add` / `worktree remove`).

Failure mechanism: when actor A's `git worktree add` fails because actor B's directory already occupies the path, the exactly-once stale-path recovery branch calls `removeDir(wtPath)` **on the shared path a peer is actively executing inside**. Pre-fix location: `tools/local_purity_check.nim:205-227` at `HEAD` (`removeDir(wtPath)` at `:215`; the `git worktree remove --force` → `removeDir` fallback at `HEAD:431-438`).

Both reported symptoms follow from that single call: the run's `--exec-cmd` target `tools/invariant_mutation_harness.sh` (`:62`) vanishing mid-run, and a leftover-worktree removal failure.

Fixed 2026-10-04 by content-addressed slots plus a per-slot blocking `flock`:

- the slot path is content-addressed — `wtPath = PureCheckRoot / slotId` with `slotId = slotStamp(...)` (`:288`, `:282`; `slotStamp` at `:160`) — so runs over different inputs never share a directory;
- runs over the **same** inputs share a slot by construction and are serialised by a blocking exclusive `flock` (`acquireSlotLock` `:169-181`) taken **before** the worktree-add path (`:290-291`). Therefore the recovery branch at `:356-375` (`removeDir(wtPath)` at `:366`) can no longer target a live peer;
- the reclaim sweep `sweepStaleSlots` (`:200-223`) skips every slot whose lock is busy (`slotLockFree` `:183-198`; fail-closed — an unprobeable lock counts as BUSY), so it cannot delete a live peer's directory;
- slot-identity or lock failure is FAIL-CLOSED with a dedicated exit 6 (`:277`, `:283-286`, `:292-295`) instead of silently falling back to a shared path.

**Status of the spec sentence: SUPERSEDED. The contract file is deliberately NOT edited here** — this workstream is registration, not contract amendment, and `docs/spec/` has its own owner. Flagged for that owner. The correction to make is to replace "the only real concurrency race" with the superseding fact (the fixed-path purity-check race, since fixed), and to drop the `flock` reference to a mechanism the CI=0 cutover already removed.

### 8.3 The rotation path is dormant and does **not** block this landing

`ROT_OLD_PIN` (§5.6) is a real blockage — but of the **next rotation ceremony**, not of this landing. Three independent facts, verified 2026-10-04:

1. **No workflow in this repository uploads `derived-closure`.** Every occurrence is a soft download: `.github/workflows/runner-pool-acceptance.yml:947-952` and `.github/workflows/admission-check.yml:850-856`, both `actions/download-artifact` with `continue-on-error: true`. Their comments attribute production to the org gate's closure job, outside this repo, and `admission-check.yml:849` states plainly that no deriver runs in this workflow.
2. **The rotation pass is gated on `F.rotation.isSome`.** `src/cli/merge_cli.nim:721`, inside the pass at `:713-727`. With no inputs, `collectRotationInputs` returns `ok(none(RotationAdjudication))` (`:927-928`; env names `AXIOM_DERIVED_H_PATH` / `AXIOM_DERIVED_B_PATH` at `:98-99`), so `F.rotation` is `none` and the pass is skipped — the pass comment records that as deliberate ("Env absent → rotation = none → Pass skipped (late merge keeps working — detection-safe)", `:717-718`).
3. **`trustSurfaceOutcome` returns before the rotation pass.** `let surfaceOutcome = trustSurfaceOutcome(F)` / `if surfaceOutcome.isSome: return surfaceOutcome.get` at `src/cli/merge_cli.nim:644-646`, ahead of `:713`. Because the pin file is trust surface (§2.2 and §2.3 of this record), Pass 2.7 short-circuits with `TRUST_SURFACE_MODIFIED` and the rotation pass is never reached.

Stated so it cannot be misread as closure: the rotation gate is **silent, not adjudicated**, and dormancy is not a verdict. As §5.6 records, green is not landing authority (`AGENTS.md` §2.3).