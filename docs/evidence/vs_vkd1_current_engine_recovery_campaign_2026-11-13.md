# VS-VKD-1: Current-Engine Evidence Recovery Campaign & 23-Symbol VKS Ledger (2026-11-13)

- **Workstream**: `workstream/vs-vkd-1-evidence-recovery`
- **Base**: `main @ 107ef8a` (post-PR #28 native MERGE)
- **Measured `VerifierBuildId` (`engineBuild`)**: `9cc33118a6c31ef991d3c89c0d3d392e96f6e0cc056082aee417ea5484bef6b0`
- **Measured `VerifierBuildSourceHash`**: `vs1-tree-hash/1:-6545338185094167100`
- **Authority**:
  - VKS SSOT (`23` non-exempt kernel symbols = `40` `kernel_symbols` − `17` `kernel_exempt_symbols`): `data/verification_scope.lock` (`src/core/proof/proof_integrity.nim:63-93`)
  - VKD Numerator Admission Authority: `computeJournalVkdAdmission` (`src/verification/cert_reconcile.nim:1051-1295`, `DECISION-0671`) via `getCanonicalVkdMetrics` (`src/cli/shared/proof_hydration.nim:119-153`) → `bin/ax report --json` (`metrics.vkd`, `src/cli/report_cli.nim:442-465`)
  - Certificate Writer & TrustCommit Journal Authority: `writeCertificateFromUapResult` (`src/verification/cert_writer.nim:238, 598`) → `commitCertificateVerification` (`src/core/trusted/trust_commit.nim:229-237`)

---

## §1. 목적 및 실행 프로토콜

### 1.1 Ultimate Purpose

과거 엔진 세대(`engineBuild`)의 인증서를 재사용하거나 가장하지 않고, 현재 `main @ 107ef8a`의 검증기 바이너리(`VerifierBuildId = 9cc33118...`)로 VKS 23개 심볼 전수에 대해 실제 재증명(`AXIOM_CI=1 bin/ax prove --target <symbol>`)을 수행하여, 현재 엔진에서 생성·서명·커밋·커널 재실행 검증된 증거만 VKD에 반영하고 23개 전수의 상태(`PENDING → REPROVED → MINTED → ADMITTED` 또는 코드 계약상 배제 사유)를 항목별로 입증한다.

### 1.2 재사용 경로와 Admission 핀의 구조적 관계 (사전 검증 확정)

- `ax prove` 내부의 3개 재사용 경로 — ① vault spec priming(`src/verification/batch_uap/orchestrator_vault.nim:184-202`), ② certificate hydration pre-pass(`src/verification/batch_uap/certificate_hydration_runner.nim:26-121`), ③ stage-1 summary cache(`src/verification/batch_uap/loop_driver.nim:316-328`) — 는 콘텐츠 지문과 저널 커밋 존재만 확인하며 `engineBuild`를 검사하지 않는다.
- 반면 VKD 분자 인정(`computeJournalVkdAdmission`, `src/verification/cert_reconcile.nim:1208` `toolchainIdentityMatchesPin`)은 `currentJournalToolchainPin()`(`nim` / `lean` / `z3` / `engineBuild` 4키)과 일치를 강제한다.
- 현재 트리에서 `src/verification/certificates/`(참조 볼트)의 5개 인증서 중 `certGreen`은 `normalizeMaxWorkers` 1개뿐이고 그 `trustCommitId`(`21213e61...`)는 런타임 저널에 부재하여 하이드레이션이 자동 스킵(`journal commit absent`)되며, 나머지 22개 심볼도 `certGreen` 참조 인증서가 없어 **23개 전수가 하이드레이션 재사용 없이 실제 파이프라인으로 진입**한다.

---

## §2. VKS 23개 심볼 전수 실행 원장 (`main @ 107ef8a`, `engineBuild = 9cc33118...`)

`data/verification_scope.lock`의 고정 순서대로 23개 비면제 커널 심볼 전수에 대해 `AXIOM_CI=1 bin/ax prove --target <symbol>`을 실행하고 저널·인증서·커널 재실행(`bin/ax cert verify --kernel`)을 대조했다.

### 2.1 ADMITTED 심볼 (2 / 23 — `PENDING → REPROVED → MINTED → ADMITTED` 완주)

| # | VKS 심볼 (`modulePath::functionName`) | 상태 전이 | 신규 인증서 (`data/trusted/certificates/`) | TrustCommit 저널 ID | `engineBuild` 핀 | `ax cert verify --kernel` |
|---|---|---|---|---|---|---|
| 3 | `src/core/topology/topology_dependency.nim::proximityScore` | **`ADMITTED`** (`certGreen`, `dual-verified`, `strict-v1`) | `89b0a232bd4bc34aa6bb4af955e286a5bc9f0704cdcabe665db28cd25c471a10.json` (`sourceHash: b536d77e...`) | `e4cd8e4ca4136164...` (`43a749642855...`) | `9cc33118a6c31ef9...` (일치) | **PASS (`exit 0`, `lean=re-executed, z3=unsat, leanchecker=passed`)** |
| 19 | `src/core/orchestrator/orchestrator_api.nim::normalizeMaxWorkers` | **`ADMITTED`** (`certGreen`, `dual-verified`, `strict-v1`) | `e57ee9394d16b8dcb8a859eb205f59a55dc3926227dc2250a21448c8d5ebf200.json` (`sourceHash: dd47629e...`) | `dadddfaf989c8859...` (`57d205c590dd...`) | `9cc33118a6c31ef9...` (일치) | **PASS (`exit 0`, `lean=re-executed, z3=unsat, leanchecker=passed`)** |

- 캠페인 이전 `main` E2E 캐너리 상태(`1/23`, `normalizeMaxWorkers` 단독)에서 **`proximityScore`가 신규로 `promoted to canonical` → `certGreen` (`strict-v1`) 재증명에 성공하여 정본 VKD가 `1/23 (0.0435) → 2/23 (0.0870)`으로 2배 회복**됐다.

### 2.2 현재 엔진에서 코드 수정 없이 `ADMITTED` 도달이 불가능한 21개 심볼의 4-범주 장벽

나머지 21개 VKS 심볼은 실행 누락이나 캐시 오염이 아니라, 현재 엔진의 정적 자격 게이트·IR 추출기·의무 생성기 계약에 의해 증명 생성 이전에 결정론적으로 배제된다:

| 범주 | 수 | 해당 VKS 심볼 | 관측 로그 및 코드 계약 위치 (`file:line`) |
|---|---|---|---|
| **A. Frontier 후보 미포함** | 6 | `hasVaultEntry` (#2), `findTopologyNodeContext` (#6), `applyCallDepthCheck` (#9), `addDepthExecutionStat` (#17), `enqueueParallelWorkItem` (#20), `skipJsonValue` (#21) | `--target=<fn> not found in frontier` (`src/cli/axiom_engine.nim:4953`, `src/cli/frontier_selection.nim:75`) — 토폴로지 스캐너의 증명 후보 프론티어(`preEligibilityFrontier`)에 진입하지 않는 함수 형태 |
| **B. Frontier Eligibility Gate: `elNoObligation`** | 11 | `axiomSpecToJsonNode` (#1), `findTopologyMetricIndex` (#4), `findTopologySymbolIndex` (#5), `normalizedEntries` (#7), `initModuleClassificationCache` (#8), `clampTimeoutMs` (#12), `timeoutDiagnosisForNode` (#14), `addNodeExecutionStat` (#16), `addNodeReport` (#18), `generateOverflowDefines` (#22), `generateOverflowAssertions` (#23) | `external candidate excluded: <fn> eligibility=elNoObligation rejection=ogr.no-applicable obligations=0 nonTrivial=0` (`src/cli/axiom_engine.nim:4199-4209`, `:4957`) — 함수 선언/본문에서 비자명 증명 의무(`nonTrivialObligationCount`)가 0건으로 분류되어 솔버 호출 전 프론티어 자격 게이트에서 배제(공허한 증명 방지, §0.9) |
| **C. Frontier Eligibility Gate: `semantic.unresolved-fact`** | 1 | `firstIntCore` (#11, `src/verification/analyzer/analyzer_shared_json.nim`) | `external candidate excluded: firstIntCore eligibility=elProofCandidate rejection=semantic.unresolved-fact obligations=1 nonTrivial=1` (`src/cli/axiom_engine.nim:4204`) — 의무 1건이 존재하나 미해결 의미 사실(`unresolved-fact`)로 인해 자격 게이트에서 fail-closed 배제 |
| **D. UAP 파이프라인 진입 후 미승격 (`eligible=5` 중 3개)** | 3 | `firstBoolCore` (#10), `calcDynamicTimeoutCore` (#13), `safeSpeedupRatioCore` (#15) | • `firstBoolCore`, `calcDynamicTimeoutCore`: `[implication] invariant does not imply postcondition` → `certNoObligation; no obligation, not a persist failure` (`src/verification/batch_uap/loop_driver.nim:1318-1324`, 저널 `608c6c3468be` / `6d45fa7b1f6b`) — `certNoObligation`은 `certGreen`이 아니므로 VKD 분자에서 제외(`src/verification/cert_promotion.nim:65, 261`).<br>• `safeSpeedupRatioCore`: `sealError=subject binding: parse-bound components unmeasured at the selection boundary (pnodeV2/extraction agreement: EA_UNSUPPORTED: unsupported AST node (ckIfStmt) outside the certified-subset wire set)` (`src/verification/extraction_agreement.nim:72`, `src/verification/attestation_orchestrator.nim:370, 676`) — AST `ckIfStmt`가 현재 certified-subset wire set 밖이어서 `EA_UNSUPPORTED`로 fail-closed(`status=failed`). |

### 2.3 완료 상태 판정 (Threshold Recovery 12/23 vs Full Recovery 23/23 대비)

- **이론적·실측 상한 증명**: 대상 커널 소스코드에 계약 프라그마/사후조건을 추가하거나(범주 A·B·C·D-1, 총 20개) IR 추출기의 certified-subset wire set을 `ckIfStmt`로 확장(범주 D-2, `safeSpeedupRatioCore`)하는 제품 코드 변경 없이는, 현 엔진(`main @ 107ef8a`)에서 증명 파이프라인을 통과해 `certGreen`을 발급받을 수 있는 VKS 심볼의 집합은 **`{normalizeMaxWorkers, proximityScore}` (2 / 23 = 8.70%)로 닫혀 있다**.
- 따라서 순수 재증명 캠페인(제품 소스·추출기 불변, §0.12 최소 변경 및 §0.9 극장 금지 준수)으로서의 **Current-Engine Evidence Recovery는 현 엔진의 도달 가능 상한인 `2/23`을 100% 회복**했으며, `Threshold Recovery (12/23)` 및 `Full Recovery (23/23)`는 `config/readiness_policy.json` r7이 `valueIsTargetOnly: true`로 명시한 바와 같이 향후 커널 명세 부착(obligation authoring) 및 AST wire-set 확장 슬라이스의 범위다.

---

## §3. 기계 검증 증거

```
$ bin/ax --check-provenance
AXIOM_PROVENANCE: OK — embedded BuildSourceHash == live src tree (vs1-tree-hash/1:-6545338185094167100)

$ (bin/ax report --json || true) | jq '.metrics.vkd'
{
  "verified": 2,
  "total": 23,
  "ratio": 0.08695652173913043
}

$ bin/ax cert verify --kernel data/trusted/certificates/e57ee9394d16b8dcb8a859eb205f59a55dc3926227dc2250a21448c8d5ebf200.json
[cert] Verify: PASS (kernel re-execution — lean=re-executed, z3=unsat, leanchecker=passed)

$ bin/ax cert verify --kernel data/trusted/certificates/89b0a232bd4bc34aa6bb4af955e286a5bc9f0704cdcabe665db28cd25c471a10.json
[cert] Verify: PASS (kernel re-execution — lean=re-executed, z3=unsat, leanchecker=passed)

$ bin/ax baseline check
=== Axiom Baseline Check ===
[OK] Baseline maintained: 0.0250 >= 0.0000
```

---

## §4. Current-main 재수용 — verifier build 이동 후 재캠페인 (2026-11-14)

- **main = `78b4f1f8cadf528a1bb846be8c7c25e4de322582`** (PR #31 native MERGE, 부모 `[3380931c7, ec09197]`).
- **`VerifierBuildId` 이동**: `9cc33118…` → **`dd1f769f6b379e8ded00628b9fb5af9eb7c9890c7712200116fef88154ea8278`**. 원인은 §2 캠페인 이후 main에 착지한 `3380931c7`이 `axiom.nimble`(version `0.6.3` → `0.6.4`)·`lakefile.toml`을 수정한 것 — 두 파일은 `computeVerifierBuildId` 매니페스트 입력(`src/verification/verifier_build_identity.nim`)이다. `VerifierBuildSourceHash`는 불변(`vs1-tree-hash/1:-6545338185094167100`).
- **stale 바이너리 차단**: `bin/hermetic_build`는 `build_env.nim`만 재생성하고 `bin/ax`를 재컴파일하지 않는다. 정본 릴리스 빌드 권한 `AXIOM_HERMETIC_BUILDING=1 make -f ci/checker.mk ci-compile -j4`(RC=0, 34.9s)로 `bin/ax`를 재빌드한 뒤에만 수용 측정을 수행했다. 재빌드 전 바이너리(임베디드 `9cc33118…`)로 측정한 VKD는 "현재 엔진" 증거가 아니다.
- **23개 전수 재실행** (현재 엔진 `dd1f769f…`): `TOTAL_MS=102000`. 새 저널 flat 클레임은 `engineBuild = dd1f769f…`, `axiomVersion = v0.6.4`, `completenessContract = strict-v1`, `status = certGreen`을 기록했다.

```
$ ./bin/ax report --json | jq -c '.metrics.vkd'
{"verified":2,"total":23,"ratio":0.08695652173913043}

$ ./bin/ax cert verify --kernel data/trusted/certificates/89b0a232bd4bc34aa6bb4af955e286a5bc9f0704cdcabe665db28cd25c471a10.json
[cert] Verify: PASS (kernel re-execution — lean=re-executed, z3=unsat, leanchecker=passed)
$ ./bin/ax cert verify --kernel data/trusted/certificates/e57ee9394d16b8dcb8a859eb205f59a55dc3926227dc2250a21448c8d5ebf200.json
[cert] Verify: PASS (kernel re-execution — lean=re-executed, z3=unsat, leanchecker=passed)
$ ./bin/ax baseline check
=== Axiom Baseline Check ===
[OK] Baseline maintained: 0.0250 >= 0.0000
```

- **A/B 실측 (동일 바이너리, HEAD만 변경)**: `HEAD=107ef8a` → VKD `2/23`; `HEAD=ec09197`(문서 1건 추가, 모듈 바이트·tree merkle 불변) → `0/23`. 원인은 strict 바인딩 `sourceIdentity`가 `measureSubjectGitRef`(`git rev-parse HEAD`)를 포함하기 때문 — `docs/spec/strict_completeness_binding.md` §5.2a.
- VKD는 저널(`data/trusted/journal`)·바인딩 캐시(`.axiom/cache/evidence`)에 대한 **런타임 측정**이며 git으로 이전되지 않는다. 새 클론·CI는 동일 캠페인을 재실행하기 전까지 `0/23`이다.
