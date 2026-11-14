# CI Optimization TCB Judgments — Phase 2 (P2) Criteria Specification

> **종류**: 판정(judgment) 규범 사양 — CI 최적화 후보가 **VALID**로 승격되기 전에 반드시 통과해야 하는 4가지 증명 의무(proof obligation)의 정의와 실행 가능한 판정 프로토콜.
> **작성일**: 2026-09-25 — 승인된 CI-pareto 계획 Phase 2의 산출물. 실험 결과는 이 문서의 대상이 아니며(결과는 후속 Phase), 이 문서는 판정의 **정의**와 **기계적 실행 방법**만 규정한다.
> **위치**: 판정 도구 `tools/ci/tcb_judgments.nim` (selftest 포함). 판정 규칙의 유일 구현은 이 문서 + 도구 한 벌이다(중복 정의 금지, AGENTS.md §1).

---

## 0. 판정 체계 (Judgment Framework)

### 0.1 목적

CI 최적화 후보(캐시 도입/확장, 병렬화, 실행 계획 변경, 기판트 변경 등)는 **머지 권한(authority)** 에 영향을 주는 변경이다. 후보가 다음 4가지 증명 의무를 모두 통과해야만 **VALID**로 취급할 수 있다:

| # | 증명 의무 | 요약 |
|---|---|---|
| J1 | **Semantic Parity** | 검증 결과가 계획/병렬성/하드웨어와 무관하게 동일 |
| J2 | **Evidence Equivalence** | invariant 증거 집합(claim/증명서/정체성)이 동등 |
| J3 | **Cache Soundness** | 캐시는 증거가 아니어도 실행-의미론 입력이 아니어야 함 — 캐시 재사용이 검증 의미론을 바꾸지 않아야 함 |
| J4 | **Worker Determinism** | `AXIOM_PROVE_WORKERS > 1` 승격은 반복 실험으로만 입증 |

**하나라도 FAIL이면 후보는 VALID가 아니다** (fail-closed). 판정은 항상 기계적으로 재실행 가능해야 하며(§0.2), "항상 통과"하는 판정은 죽은 게이트(극장, AGENTS.md §0.9)다 — 도구는 selftest로 각 판정의 FAIL 경로가 실제로 FAIL함을 증명한다(§6).

### 0.2 기계적 판정 가능성 (Mechanical Checkability)

각 판정은 다음 조건을 만족해야 한다:

1. **결정적**: 동일 입력 → 동일 출력 (AGENTS.md §0.2).
2. **기계적 재실행**: 판정 도구는 산출물(JSON 측정 파일, 워크플로 YAML, 실행 로그)만 입력으로 받아 0(PASS) / 2(JUDGMENT-FAIL) / 1(ERROR) 종료 코드를 반환한다(§6 도구 명세).
3. **판정 사유 라인 기록**: FAIL 시 정확한 근거(파일:라인 또는 측정값)를 출력에 남긴다.
4. **주장 ≠ 증거 금지**: "구현되었다", "동작한다" 같은 서술은 증거가 아니다(§2.2, AGENTS.md §2.2-1). 판정은 실행 산출물 또는 고정 소스의 기계적 비교만 인정한다.

### 0.3 판정 결과의 위치 (SSOT)

- 판정 실행 결과는 `data/ci_optimization/` 아래에 기록한다(생성 데이터 — AGENTS.md §5).
- 판정 규칙(이 문서)과 도구(`tools/ci/tcb_judgments.nim`)는 저장소 SSOT이며, 결과 JSON은 측정 SSOT다.
- **평가 결과는 사양을 갱신하지 않는다**: 판정 통과가 이 문서의 기준을 바꾸지 않는다. 기준 변경은 이 문서 개정(architect 승인)으로만 가능하다.

---

## 1. JUDGMENT 1 — Semantic Parity (의미론적 동일성)

### 1.1 정의 (기계적 기준)

**PASS 조건**: 두 실행(또는 두 계획 하)의 **canonical semantic projection**이 모든 공통 unit에 대해 동일하다.

```
Proj_sem(Result(U, Plan_A)) == Proj_sem(Result(U, Plan_B))   ∀U ∈ Selected_A ∩ Selected_B
```

근거 — `docs/spec/canonical_execution_semantics.md`:
- §8.1 `Result(U, Plan_A) == Result(U, Plan_B)` (동일 unit semantic input, U ∈ 양쪽): **:337**.
- §7.2 selection-invariant semantic projection 성분(unit별 판정 / ProofStatus / 실패·vacuity 분류 / certificate identity): **:305-312**.
- §7.3 golden 불변식 `Project(FULL, Selected) == PRUNED`: **:316-322** — **직접 비교 금지**: 반드시 `Project(FullResult, Selected)`와 `PrunedResult`를 비교한다(**:322**).

**비교 단위**: unit별 판정(verdict)/ProofStatus/분류 — 계약 §6 R3 canonical projection의 포함 필드(claim/verdict, assurance tier, proofDigest, input sourceHash — `docs/spec/productization_contract.md:197-203`).

**제외**(substrate/실행-측정 성분): timestamp, runId, tmp path, processId, solver 내부 trace, 성능 telemetry(`solverElapsedMs`, `wallElapsedMs`, `parallelOverheadMs`, `cacheHitCount`, `startedAtMs`, `endedAtMs`, `elapsedMs`, `totalWallTimeMs` — `productization_contract.md:203`, canonicalProjectionHash 제외 목록 **:209**).

### 1.2 근거 계약

- 결정론 약속 정의: **canonical semantic equality이지 raw artifact byte equality가 아니다** — `productization_contract.md:192-205` (§6 표: 포함/제외) 및 **:205** (Phase 6 실측: 2회 실행 A/B에서 canonical semantic projection 해시 동일, 유일 차이는 excluded telemetry).
- `canonicalProjectionHash`의 유일 구현: `src/core/utils/canonical_projection.nim::canonicalProjectionHash` (`productization_contract.md:209`). CLI 노출: `ax report --canonical-digest`.

### 1.3 패리티는 검증 장치(device)이지 TCB가 아니다 (설계 교정 유지)

- shadow-pariy 메커니즘(`tools/ci_shadow_runner.sh`)은 **rollout 관측 장치**다. exit 0 = parity+equivalence 관측 성공, exit 2 = 불일치 → rollout 정지(fail-closed) — `ci_shadow_runner.sh:17-19`, 관측 파이썬 로직 **:66-91**, 판정 분기 **:95-99`.
- **패리티 green은 그 자체로 아무것도 승인하지 않는다**: TCB(머지 권한 컴포넌트 집합)는 패리티 관측과 별개의 불변식 집합(§2의 invariant 집합 + 기존 게이트 스택)이다. 패리티는 권한의 증거가 아니라 "관측 유지" 신호다 — `ci_shadow_runner.sh:96` ("PASS — Project(Full,Selected) == plan-run (관측 유지)").
- 이 구분은 설계 교정으로 확정된 사항이며, 사양은 이를 **보존**한다(회귀 금지).

### 1.4 KNOWN VIOLATION — 해소됨 (2026-11-14, 판정 이력으로 보존)

전역 budget 스케일링은 §8 위반으로 문서화되었고, **2026-11-14에 코드와 사양이 동일 세대로 해소**되었다. 본 절은 판정 이력이므로 삭제하지 않고 해소 사실과 기계적 근거를 함께 기록한다.

- 해소 전 표면: `src/cli/axiom_engine.nim`의 `max(1, prepared.frontier.len)` 스케일링 — 문서 v1.0.0(2026-09-25)의 `:844-845` 인용은 public history에서 유효한 적이 없고, B5 이전 main `80a5119` 실측 위치는 `:5727-5728`이었다(해소 후 그 라인은 `buildPreRunContext`/`resolveAxStatePath`이며 스케일링은 부재). `src/verification/batch_uap/loop_driver.nim:606-618`은 해소 전후 동일하며, 전역 결속은 B5가 제거한 `gasLimit` 파라미터(`:776`/`:910`)였다.
- 해소 후 실측(2026-11-14, `workstream/vs-b5-per-unit-budget`): `initAxiomEngine(startMono: int64)`(`axiom_engine.nim:271-277`) — 엔진에 gas 풀이 없다. 오케스트레이션 호출부의 `gasLimit = engine.budget.gasTotal` 전달이 제거되어 집계 gas는 telemetry 전용이며, ci-cd 게이트는 `depthCoverage`만 판정한다(`:559-563`). `loop_driver.nim:606`의 `checkBudget(unitBudget)`은 유닛 고유 예산만 소비한다.
- 기계적 근거: `tests/cli/test_axiom_engine.nim`의 음성 통제(`not compiles(initAxiomEngine(..., expectedNodeCount = …))`) + `tests/unit/batch_uap_orchestrator_test.nim` exit 0.
- 미해소 잔여(본 슬라이스 밖, 조용히 수정 금지): `checkBudget(unitBudget)`이 생성 직후 fresh 예산에 수행되는 도달 불가 경로. **DEBT 미등록 상태이며, 등록은 이를 다루는 별도 슬라이스의 착수 조건**이다.

### 1.5 판정 프로토콜

- 도구: `--judgment parity --baseline <file> --candidate <file>` — per-symbol 판정 비교(§2 시맨틱스 미러, `ci_shadow_runner.sh`의 exit 0/2 관례).
- 실행: baseline/candidate는 canonical projection이 적용된 JSON(예: `ax prove --json` → canonical projection 후 측정 저장). 도구는 projection 필드만 비교한다(제외 필드 무시).
- exit: 0 = parity 유지, 2 = 불일치(기계적 출력: 불일치 symbol 목록), 1 = 입력 오류.

---

## 2. JUDGMENT 2 — Evidence Equivalence (증거 등가, 3부)

### 2.1 정의

후보(최적화)가 생성·변경하는 증거가 다음 **3중 등가**를 만족해야 한다:

```
semantic equivalence ∧ evidence equivalence ∧ canonical identity equivalence
```

### 2.2 (a) Semantic equivalence

- 비교 대상: verdict / ProofStatus / 분류 (판정·증명 상태·실패/vacuity 분류).
- 근거: `canonical_execution_semantics.md:305-312` (§7.2 projection 성분) — J1의 비교 단위와 동일.

### 2.3 (b) Evidence equivalence — witness/증명서 체인 등가

- 비교 대상: `InstantiationWitness` 체인(`src/infrastructure/evidence_artifact_io.nim:114-212` — witnessDigest 포함 직렬화 + `evidence_artifact_io.nim:205-207` 로드 시 재계산 fail-closed) 및 SelectionDerivation 도출 증명서(`canonical_execution_semantics.md:163-178`).
- 기준: 동일 입력에 대해 witness 체인(topology·IR·후보·결과 witness)의 **구조와 digest**가 동일해야 한다. witnessDigest 재계산 불일치 = 전에 없던 산출물은 FAIL(fail-closed).
- proofDigest는 현재 `null` 고정(증명 artifact 파이프라인 부재 — `provenance_contract_v3.md:41,68`): 등가 비교 대상에 포함하되 null 유지가 정상.

### 2.4 (c) Canonical identity equivalence — INVARIANT digest 집합

**동일해야 하는 집합**(arch/substrate 독립 — invariant):

| 성분 | SSOT 근거 |
|---|---|
| claim / verdict / tier / ProofStatus | `productization_contract.md:197-199` (claim/verdict, assurance tier, proofDigest) + `canonical_execution_semantics.md:307-310` |
| canonical projection hash | `productization_contract.md:205,209` — `canonicalProjectionHash` |
| certificate identity — **13필드 projection** | `src/verification/certificate_identity.nim:32-36` `canonicalV3FieldKeys`(13개: schemaVersion, modulePath, functionName, sourceHash, irHash, leanProposition, solverStatus, status, winningStrategy, inputHash, solverInputDigest, solverResultDigest, evidenceId) — 문서의 12개 목록(`provenance_contract_v3.md:76-81`)은 evidenceId 없음; **현행 코드(13)를 판정 기준으로 삼는다**. identity 계산 = SHA-256 over join("\n") (`fingerprint_generator.nim:23-29`) |
| solverInputDigest / solverResultDigest | `provenance_contract_v3.md:66-67` — z3: sha256(smtlib2) / sha256(z3 stdout); lean: sha256(leanProposition) / sha256(lean result) |
| ledger subjectId | `data/verification_subject_schema.json:8-10` — required 목록에 subjectId 포함(**8-9** = `required:` 시작, **:10** = `"subjectId"`); canonical wire `sha256Hex('axiom.subject.v1\n' + candidateRef + '\x1f' + candidateCommit + '\x1f' + treeDigest + '\x1f' + baseSha)` (**:5**) |

**동일할 필요가 없는 집합**(substrate·toolchain 특이 — 스코핑 메커니즘, 불일치 FAIL 아님):

| 성분 | 근거 |
|---|---|
| `ArtifactDigest` | `artifact_determinism.md:10` — (source+toolchain+build policy) 바운드 산출물 digest |
| `WorkUnitFingerprint` / toolchainDigest에 포함된 `axiomExecutableDigest` | `src/verification/obligation/identity.nim:178` (`axiomExecutableDigest*: string`) + **:188-206** (`canonicalExecutionBundleFingerprint`) |
| `GateEnvLock`의 `hostOS` / `hostCPU` / `kernelVersion` 키 | `docs/spec/aot_pipeline.md:224-238` (타입 정의 **:226-238**) + **:247-248** (변경 시 전체 재컴파일) |

### 2.5 Cross-arch 위치 규정 (pending 항목)

- `RelocationInvariance`는 **동일 substrate 내 루트 재배치**만 보장한다 — `artifact_determinism.md:11` (정의) + **:146-149** (`ArtifactDigest(build(root=A)) == ArtifactDigest(build(root=B))` — A≠B는 서로 다른 물리 루트). cross-arch/x86-64↔arm64 **byte identity는 MUST 계약이 아니다** — `artifact_determinism.md:11`은 relocation을 정의하고 cross-arch를 규정하지 않음.
- **cert-level cross-arch 정책은 UNKNOWN**: 이를 다루는 ADR이 존재하지 않는다(저장소 `docs/adr/` 전수 확인 — ADR-0017은 CI=0 cutover/select, ADR-0023은 runner pool). → **pending으로 기록**: cross-arch 증명서 정체성 정책 확정은 후속 작업이며, 그 전에 cross-arch 증명서 동일성을 주장하는 후보는 J2 FAIL.

### 2.6 판정 프로토콜

- 도구: `--judgment canonical-identity-set --baseline <json> --candidate <json>` — **invariant 집합만** 등가 비교, substrate 특이 digest는 "보고(report, scoping)"만 하고 실패로 취급하지 않는다. invariant 불일치 시 exit 2 + 상세 출력.
- 입력 JSON 규격: 측정 digest 집합을 담은 객체(성분 이름 → digest). 성분 이름은 §2.4 표의 키를 사용한다. Invariant 키는 도구가 내장 상수로 보유하며, 추가 키는 보고만 한다.
- 이 판정은 각 후보의 **증명서 정체성**이 성분 집합 기준으로 보존되는지를 자동 검증한다.

---

## 3. JUDGMENT 3 — Cache Soundness (캐시 건전성)

### 3.1 기본 원칙

"cache ≠ evidence"(가속이지 증거가 아님)는 **캐시가 실행-의미론 입력(execution-semantics input)이 아니어야 한다는 것을 의미하지 않는다.** 캐시가 검증 결과의 의미론을 바꿀 수 있는 경로(§3.3a)는 판정 대상이다.

**용어 계약 (2026-10-07 정정 — "cache ≠ evidence" 불변 하)**:

> **HIT = 검증된 계산(프로그램) 공급 재사용 — 판정은 항상 재계산된다.**

- HIT는 프로그램 온기(nimcache 등)와 검증된 산출물의 **공급**을 재사용하는 것이지, 검증 결과(evidence)의 재사용이 아니다.
- HIT여도 판정(gate/검증 실행)은 항상 재계산된다 — 실측: B-HIT 레인에서도 4개 ci-compile 바이너리 재컴파일이 유지된다(census 2026-09-30, `docs/evidence/ci_structural_duplicate_census_2026-09-30.md:43`). S5(build-skip)가 봉인 해제되어 재컴파일을 생략하는 경우에도, 생략되는 것은 **검증된 공급의 재사용**이지 판정 재계약이 아니다 — 판정은 실행된다.
- 캐시 HIT는 correctness 증거로 인용될 수 없다: correctness = exact key → 신뢰 입력 재유도 검증 → 사용(`action.yml:317-493`), fail 시 폐기·네이티브 재실행.

- 근거: `.github/actions/setup-axiom-toolchain/action.yml:4-7` — correctness contract = "exact key → restore → content fingerprint verify → use; verify FAIL → discard and build natively (fail-closed)"; **:7** `cache is acceleration, never evidence`; **:50-52** hit-rate는 나중에 측정할 PERFORMANCE 지표이며 correctness의 일부가 아님(correctness = exact key → verify → use).

### 3.2 판정 대상 캐시 구조 (실측)

- A-layer(환경/toolchain memo): `~/.nimble`, `~/.choosenim`, `~/.elan`, `~/.local/bin` — action.yml:15. 키 = toolchain pin + OS package fingerprint(gcc/glibc) + build-script identity (:9-18, :173) — 러너 이미지 **라벨**(ImageOS/ImageVersion)은 2026-10-01 제거(LABEL_NOISE 실측 — §3.6 FLAG 기준 재정의 참조). `provision-scope` 변형은 경로 집합과 키 네임스페이스를 함께 좁힌다(2026-11-12 실측): `runtime` = `~/.local/bin`(`axiom-a-rt-*`), `nim` = `~/.nimble` + `~/.choosenim` + `~/.local/bin`(`axiom-a-nim-<os>-<arch>-nim<ver>-<gcc>-<glibc>-<script>`; RUNNER_ARCH와 nim 버전이 키에 결속되어 arch/버전 변경은 새 세대를 만든다). `~/.nimble`은 필수다 — 평가기 소스는 stdlib+in-repo만 import하지만 `config/integrity.nims`의 manifest bootstrap이 모든 `nim c`에서 `tools/feature_manifest_generator.nim`(`import checksums/sha2`)을 컴파일하므로 nimble 패키지 폐쇄가 빌드 시점 의존성이다(격리 HOME 실측: `~/.nimble` 부재 시 6개 평가기 컴파일 전부 rc=1). `~/.elan`만 제외된다., `full` = 네 경로 전부(`axiom-a-*`). paths가 다르면 cache version(path+compression hash)이 갈라지므로 네임스페이스 간 cross-hit는 구조적으로 불가능하다.
- B-layer(per-base build artifact memo): `build/nimcache`, `.axiom/cache`, `proofs/.lake`, `proofs/build`, `.axiom-b-fingerprint.json`, 4개 ci-compile 바이너리 — action.yml:20-24, :168-177. 키 = exact build source + recipe identity + A-fingerprint (:96-100).

### 3.3 (a) Manifest 원형성 (Circularity) — 필수 개선 기준

**착지 전 상태(원형 — 2026-10-07 이전 역사)**: B-layer fingerprint manifest는 **캐시 payload 내부에 실려** save 시점에 작성되고(`ci-cache-publisher.yml` — save-side, 단일 씨딩 writer가 검증 후 발행; 2026-09-29 ADR-0025 Amendment B 이전은 `runner-pool-acceptance.yml` push@main 전용) restore 시점에 같은 payload에서 읽혔다. restore-side 검증은 **payload 자신이 싣고 온 manifest의 `files{}` 값과 복원 파일의 sha256을 재계산 비교**하는 구조로, manifest와 payload가 함께 저장·복원되므로 둘 다 오염되면 staleness가 per-entry sha256을 통과했다.

**원형이 아닌 앵커 (현재 존재)**:
- exact-key 구성 — restore는 GitHub platform이 exact key 매치일 때만 `cache-hit=true` 보고 (`action.yml:28-30`) — 키는 `cache-build-source`(호출자 B) + recipe/A fingerprint로 구성.
- `buildSha`/`bKey` 대 호출자 제공 `EXPECT_BUILD_SHA`/`EXPECT_B_KEY` 검증 — 신뢰 입력 기반.
- SourceCoherence FATAL — `src/cli/main.nim:69-87` (`checkAndSelfBootstrap`, mismatch 시 `quit(1)`): 복원된 `bin/ax`가 임베드된 BuildSourceHash와 live source가 다르면 실행 거부.

**REQUIRED improvement criterion (기계적 기준)**:

> restore-side의 `files{}` digest 검증은 **신뢰 입력(trusted input)에서 파생된 기대값**과 비교해야 한다 — 즉 (1) 소스-파생 기대(예: build recipe가 만든 산출물의 기대 digest를 소스/레시피에서 재계산) 또는 (2) 키(키-파생 기대) 또는 (3) 플랫폼 검증(서명)된 manifest — **payload 자신이 싣고 온 manifest의 자기 일관성만으로는 PASS할 수 없다**.

이 기준을 도구로 점검: `--judgment cache-manifest` — `files{}` 비교 대상이 "payload 내부 manifest 값"이면 **원형 → FAIL (exit 2)**; 신뢰 입력 기반 재계산/서명이 있으면 PASS. **착지 전에는 이 판정이 항상 FAIL이었다** (도구를 허위 PASS로 만들지 않는다, §6 theater check).

**구현 상태 (2026-10-07 착지 — P2-3(a))**: 기준 (1)+(2)가 action.yml restore-side에 구현되었다. 이 기준은 J1 §1.2의 semantic identity(treeOID + recipeHash + a_fp — 바이너리 바이트 hashing 금지, `evidence_cas.nim:199-250` artifactDigests 배제 선례)를 기대값 파생 소스로 사용한다.

- **키-파생 + 소스-파생 identity 재유도 (B-layer fingerprint verify, `action.yml:317-410`)**: verify python 블록이 `expect = os.environ["EXPECT_B_KEY"]`(keygen 산출 env — `:372`)와 recipe 파일 4종의 sha256 체인 재계산(`:374-377`, keygen의 `sha256sum <files> | sha256sum`과 바이트 동일), `a_fp = sha256(A_KEY)[:32]`(`:378`)로 기대 b-key를 재유도하고, manifest `bKey`/`buildSha`를 이 **재유도된 identity**와 대조한다(`:384-389`). payload가 싣는 identity 자기주장은 더 이상 앵커가 아니며, 재유도 소스(identity = tree OID + recipe + a_fp)는 검증 로그에 명시 기록된다(`:380` — "anchor — derivation source"). save-side writer(publisher)는 schema v1의 `buildSha`(tree OID)·`bKey`(`axiom-b-<tree>-<recipe><a_fp>`) 필드로 파생 소스를 manifest에 기록한다(publisher 변경 없음).
- **semantic provenance probe (B-layer semantic provenance probe step, `action.yml:444-511`)**: digest 루프가 닫지 못하는 **payload+manifest 동시 변조**(자기일관 stale)를 닫는 비순환 앵커. 신뢰 트리(b-identity)를 호출자 git 객체 저장소에서 `git archive "$identity" -- .axiom_root src`로 materialize하고(`:485`), 복원된 **4종 ci-compile 바이너리 전부**(bin/ax + bin/gate_hook + bin/precompile_gates + bin/install_ax_cas)를 그 트리에서 `--check-provenance`로 실행해 **바이너리 각자의 SourceCoherence 검사**(임베드 BuildSourceHash vs 신뢰 트리 src 재계산 — 런타임 SSOT `src/infrastructure/provenance_probe.nim` + 순수 지문 커널 `src/core/utils/build_provenance.nim`, bin/ax 기존 검사 `src/cli/main.nim` `checkAndSelfBootstrap`과 동일 의미)를 재실행한다. 커버리지가 4종 전부이므로 **bin/ax를 정상으로 남긴 보조 바이너리 단독 교체+manifest 재작성**(PR #566 증거 §6 잔여)도 동일하게 감지된다. 트리에서 빌드되지 않은 바이너리는 FATAL(exit 1) → 전체 B payload 폐기 → cold fallback(`:508-511`). 키의 트리 == 바이너리 빌드 트리는 구조적으로 성립한다(publisher가 `cache-build-source = manifest build_sha`로 키 파생 — 오탐 없음). exp-* 네임스페이스는 SKIP(`:476-479`), git archive 실패도 폐기(fail-closed, `:484-489`), payload 바이너리 누락도 폐기(`:496-499`). libpcre 의존(바이너리 링크)으로 install step 이후 배치. 기대값은 트리 단위이며 바이트 단위가 아니다 — 동일 트리 리빌드의 바이트 드리프트(build_env 각인)는 수용(semantic identity, J1 §1.2).
- **실측**: (i) 정상 복원 probe OK / stale 트리(0ad074a50 — src 재계산 해시 -9023095428418420061 vs HEAD -7055811655676579384 상이) 감지·폐기, (ii) 파손 시뮬레이션 계약 테스트 `tests/ci/test_b_cache_anchor.nim`(15 tests — (c) 동시 변조에서 digest 레이어 자기일관 통과 사실과 probe 감지를 각각 고정, (c2)+(p4)는 보조 바이너리 잔여 클래스 고정), (iii) 판정 exit 2 → 0 전환은 §3.7. 전체 실측 기록: `docs/evidence/j3_manifest_anchoring_2026-10-07.md`, `docs/evidence/b_verify_binary_coverage_2026-10-08.md`.

### 3.4 (b) 무효화(invalidation) 정확성 — 프로브 커버리지 판정

**현재 프로브 실측**:
- A-layer fingerprint verify: 복원된 바이너리 버전(`nim --version`, `lean --version`, `z3 --version`) + gcc/glibc fingerprint를 키-파생 기대와 비교 — action.yml:120-162. FAIL 시 경로 삭제(rm -rf) + 네이티브 설치(fail-closed, :155-159).
- Lake 기능 프로브: `import Lake`를 격리 dir에서 실제 로드(`check_lake_probe`) — 파일 존재(`-f`)가 아닌 **기능 검사** — action.yml:314-333. 파일-존재-but-손상 incident: **:299-311** (run 35678120915 — `Lake.olean` 누락/불완전 → `unknown namespace 'Lake'` → 16레그 전부 INTERNAL_ERROR(2)); **:308-311** "file-present-but-corrupt/incomplete Lake.olean (fleet 2026-09-22, run 35681814055)".
- compiler/ast.nim 존재 검사: `[ -f "…/Nim-2.2.10/compiler/ast.nim" ]` — action.yml:265-268 (:271-274 FAIL 시 exit 1; `import compiler/*`는 kernel 빌드 전제 — :255-256).

**판정 기준 — 프로브 커버리지 vs 캐시 클래스**: 판정은 캐시 클래스(nimcache / .lake / .axiom/cache / toolchain / ci binaries)별로 무효화/검증 프로브를 열거하고, 각 프로브가 **기능 검사(load/execute) 또는 신뢰 입력 대비 digest**인지 분류한다. **프로브 없는 클래스는 `[COVERAGE-GAP] UNCOVERED` FLAG로 보고**되며, "존재 검사만 있는 클래스"는 기능 검사로 승격되어야 함을 경고로 보고한다. **커버리지 갭은 exit를 바꾸지 않는다(보고 전용)**: B-layer payload 전체가 exact-key + `buildSha`/`bKey` 대 `EXPECT_*`(action.yml:207-212)로 소스 바인딩되어 오늘날 갭 클래스는 전이적으로 커버된다 — payload 수준 앵커가 사라질 때만 커버리지 갭이 soundness FAIL로 승격된다. 도구의 열거 규칙은 §3.6 + `enumerateProbeCoverage`(tools/ci/tcb_judgments.nim)가 유일 구현이다.

**fail-closed 규칙**: 프로브 FAIL 시 캐시는 폐기(discard)되고 네이티브 경로로 실행되어야 하며, 폐기 없이 진행하면 즉시 FAIL이다. 실측: A-layer :155-159, B-layer :189-196 (:194-198 manifest 누락 → 폐기, :232-233 검증 실패 → `discard_b`), Lake 재설치 후 검증 :328-333.

### 3.5 (c) restore-keys 금지 — FORBIDDEN (건전성 필수)

- prefix fallback(`restore-keys`)은 "may be stale" 휴리스틱이며 정확성 계약(복원 digest == 기대)을 충족할 수 없다 — action.yml:28-30. 검증 단계는 `cache-hit == 'true'`(exact key) 게이트에서만 실행된다 — action.yml:121 (`if: steps.a-restore.outputs.cache-hit == 'true'`), **:181** (b-restore 동일). restore-keys로 인한 hit는 이 게이트를 통과하지 못해 **검증 없이 소비**된다.
- **판정 규칙: 두 계층 모두에서 `restore-keys:` 사용은 즉시 J3 FAIL이다** (action.yml:28 "restore-keys are FORBIDDEN on both layers" + :110, :164).
- **부분 일치는 `restore-keys` 없이도 발생한다** (GitHub Docs "Cache key matching": exact → primary key의 prefix match → restore-keys 순서). 따라서 "restore-keys 0건"은 exact-only의 증거가 아니다. A-layer는 `cache-hit != 'true'`(부분 일치 또는 미스)이면 복원된 스코프 경로를 **폐기**한 뒤 네이티브 설치를 수행한다(action.yml "A-layer non-exact discard"). 폐기 방식은 경로 성질로 갈린다: action이 소유한 스코프 디렉터리(`~/.nimble`, `~/.choosenim`, `~/.elan`)는 `rm -rf`, **`~/.local/bin`은 디렉터리 전체를 `$RUNNER_TEMP`로 격리(mv)**하고 빈 디렉터리를 재생성한 뒤 비어 있음을 단언한다. `~/.local/bin`은 PATH에서 시스템 디렉터리보다 **앞**에 놓이므로, 페이로드가 심은 임의 이름(`git`·`python3`·`sha256sum` 등)이 이후 모든 스텝에서 시스템 바이너리를 섀도잉한다 — "페이로드 구성원은 z3/jq뿐"이라는 가정은 미검증 페이로드에 대해 성립하지 않는다(실측: 런 43067710160에서 `~/.local/bin` 캐너리만 생존, 43068818512에서 3종 전부 소멸). exact 판정은 `cache-hit == 'true'` 하나뿐이며(구현 `isExactKeyMatch`), `cache-matched-key`가 실행 로그에 기록되어 비-exact 복원을 귀속할 수 있다.

### 3.5a exact-hit은 provenance가 아니다 (2026-11-12 실측)

`cache-hit == 'true'`는 **키 동일성**만 의미하며 **scope(출처)의 증거가 아니다**. GitHub 문서는 "workflow runs can restore caches created in either the current branch or the default branch" 및 PR 런의 base-branch fallback을 규정하므로, PR 런(`refs/pull/N/merge`)과 merge_group 런(`refs/heads/gh-readonly-queue/<base>/pr-<N>-<sha>`) 모두 **default branch 스코프 엔트리에서 exact-hit을 받을 수 있다**.

- **실측**: 런 43086206129(merge_group)가 `refs/heads/main`에만 존재하던 키를 `exact-hit=true`로 복원했다. 해당 queue ref의 첫 저장은 복원 **이후**였고 ref 이름에 merge-group head SHA가 박혀 있어 사전 존재가 불가능하다 — scope fallback의 결정적 증거다.
- **계약**: Axiom은 exact-hit을 provenance로 사용하지 않는다. 복원 내용은 `A_VERIFY`(nim/z3 버전 + gcc/glibc fingerprint)와 B-layer의 신뢰 입력 재유도(§3.3)로 독립 검증하며, 실패 시 폐기·네이티브 재설치한다. exact-hit은 "무엇을 복원했는가"만 증명하고 "누가/어느 커밋이 썼는가"는 증명하지 않는다.
- **문서 공백**: merge_group 캐시 스코프는 공식 문서에 존재하지 않는다(UNDOCUMENTED). 관측된 동작은 default-branch fallback이며, PR 런이 merge_group 스코프를 읽는 것은 문서상 열거(자기 merge ref·base·default만 접근)로 **불가**로 추론되나 미실측이다.
- **운영 함의**: 10GB 풀은 저장소 전역이고 동일 키가 22개 ref에 복제된다(2026-11-12 실측: 8.47/10GB, 35개). per-ref 복제는 저장량 위험이며 7일 미사용 제거로 자연 소거된다.

### 3.6 역사적 incident — 판정 테스트 케이스

판정은 다음 incident를 재현하는 경로를 규칙적으로 잡아야 한다:

| Incident | 실측 근거 | 판정 대응 |
|---|---|---|
| Lake.olean corrupt-but-present | action.yml:299-311 (존재 검사 통과 but 기능 실패) | 기능 프로브 없이 존재 검사만 하는 lake 클래스 → FLAG (b-기준) |
| LTO 13.1 vs 11.3 image drift | action.yml:20-33 (헤더 계약 — LABEL_NOISE 근거), :145-160 (지문 키 구성), :173 (키 = RUNNER_OS + gcc_fp + glibc_fp + script_hash) | restore-key fallback 존재 시 즉시 FAIL (c-기준); **FLAG 기준 재정의(2026-10-01)** — 실측 툴체인 지문(gcc/glibc/nim 등) **결손** 키 → FLAG (키 건전성). 러너 라벨(ImageOS/ImageVersion) 미포함은 **FLAG 아님**: LABEL_NOISE 실측(114/114 런, 2026-09-30 창)에서 gcc_fp/glibc_fp/script_hash는 이미지 롤 전후 동일하고 a_fp만 라벨로 변동 — 라벨은 false-MISS만 유발해 이미지 롤 기간 시드를 구조적으로 소비 불가로 만든다(census §2-§3: 구·신 이미지에서 동일 트리·레시피 내용이 a_fp만 달리 2개 키로 시딩). LTO 사고 클래스(gcc 11.3→13.1)는 gcc --version 지문이 직접 포착(패키지 개정 포함). 라벨 제거 후 잔여 위협(라벨만 포착 가능한 비-gcc/glibc 드리프트) = residuals R9 |

### 3.7 판정 프로토콜

- 도구: `--judgment cache-manifest --workflow <path>` — action.yml + save/restore 정의(또는 추출 발췌)를 최소 파싱하여 §3.3 기준 충족 여부를 점검한다. 실행 정의가 예외적으로 발췌 파일이면 `--workflow`를 발췌 텍스트 파일로도 허용(단, 명시된 기준 3.3-1..3을 위한 충분 정보 포함).
- 도구가 기대하는 최소 구조(2026-10-07 착지 후 action.yml에 실재): B-layer restore의 fingerprint-verify step 안의 `files` 루프 + manifest 경로(`build/.axiom-b-fingerprint.json`) + `EXPECT_BUILD_SHA`/`EXPECT_B_KEY`/`A_KEY` env + **verify 블록 안의 신뢰 입력 재유도**(`expect = os.environ[...]` + recipe sha256 체인 재계산 — §3.3 구현 상태) + `restore-keys` 부재. 도구는 추가로 **semantic provenance probe(`git archive` + SourceCoherence)의 존재를 report-only 행으로 출력한다**(exit에는 개입하지 않음 — probe 부재 PASS는 "동시 변조 커버리지가 in-block 재유도에만 의존"한다는 보고를 수반).
- selftest fixture(12): 원형 FAIL, 서명 PASS, 블록 외부 서명 프록스 FAIL, 신뢰 입력 재유도 PASS, 블록 외부 probe 마커 FAIL(보고 전용 회귀 방지), J1/J2/J4 경로.
- exit: 0 = 신뢰 입력 기반 검증 존재(§3.3 criterion 충족), 2 = 원형(unfixed — precision findings 포함) 또는 restore-keys 위반, 1 = 입력 오류. 프로브 커버리지 갭(§3.4)은 exit와 무관하게 FLAG 로 보고된다.

---

## 4. JUDGMENT 4 — Worker Determinism (워커 결정론)

### 4.1 정의

`AXIOM_PROVE_WORKERS > 1`(현재 **1로 고정** — `runner-pool-acceptance.yml:360`) 승격 후보는 **동일 입력에 대해 N-워커/싱글-워커 결과가 결정적으로 동일함**을 반복 실행으로 증명해야 한다.

- 근거: `productization_contract.md:203` — `parallelOverheadMs`는 제외(성능 telemetry)지만, verification **결정론**은 병렬 실행에서도 유지되어야 한다(canonical semantic equality — §1.1, :192-209).
- 병렬 정책 선례: `config.nims:23-41` — `getDeterministicParallelJobs`는 컴파일-타임에 host RAM/CPU에서 결정적 병렬 잡 수를 산출(:27-39), `switch("parallelBuild", …)` :41 — **config.nims는 §-1 불변 파일이므로 판정은 측정만 할 수 있고 수정할 수 없다.**

### 4.2 판정 기준 (기계적)

1. **반복 수**: ≥ **5회** 반복(동일 입력, 동일 substrate). **1회 일치 = 미입증**(표본 1은 우연 일치를 배제할 수 없음 — §0.2-4 주장≠증거).
2. **스케줄 변동 노출**: 5회 반복은 서로 다른 스케줄/로드 조건에서 실행되어야 한다(예: 병렬 작업 수치 변조, 부하 동반 실행, 다른 워커 수). 순수 연속 실행 5회는 "스케줄 perturbation"이 아니므로 PASS로 인정하지 않는다 — 실행 기록에 스케줄/로드 변조 증거가 있어야 한다.
3. **비교 대상 = canonical digests**: 각 실행의 canonical projection digest가 모두 동일해야 한다(projection 제외 목록 §1.1 그대로 — `parallelOverheadMs` 포함 제외).
4. **z3-pool 결정론 결합 검사**: z3 solver 풀(연동 병렬성)이 결과 digest에 개입하는 경로를 점검한다 — solver 실행 결과 digest(`provenance_contract_v3.md:66-67`)가 반복 간 동일해야 하며, 풀 크기 변화로 solver 결과가 달라지는 경로는 J4 FAIL(혹은 J1 FAIL — 병렬성 의존 결과).

### 4.3 판정 프로토콜

- 도구: `--judgment worker-determinism --runs <dir>` — `<dir>`에 N개 실행 결과 파일(`*.json`)이 있고, **N ≥ 5**이며 **모든 canonical digest가 동일**하면 PASS.
- N < 5 → **FAIL** (exit 2) — "5회 미만 반복은 미입증".
- digest 불일치 → FAIL (exit 2), 불일치 목록 출력.
- 실행 메타(스케줄/부하 노출 기록)는 각 결과 JSON의 메타 필드로 참고 출력한다(판정의 필수 입력은 아님 — 누락 시 경고).

---

## 5. 판정 종합 (VALID 확정 규칙)

- 후보는 **J1 ∧ J2 ∧ J3 ∧ J4 전부 PASS**일 때만 VALID (각 판정의 exit 0).
- J1의 알려진 위반(§1.4)은 2026-11-14에 해소되었다(코드·사양 동일 세대). J1 FAIL 예외 조항은 효력을 종료하며, 이후 후보는 통상 J1 판정 절차를 따른다. 단, 해소 이전에 생성된 판정 증거는 재사용하지 않는다(§0.9).
- 중복 실행·반복 부수효과 관측 시: retry/cooldown 추가가 아닌 근본 권한 분석을 우선한다(AGENTS.md §2.2-8).
- P2는 판정 도구가 FAIL을 그대로 출력하는 상태를 유지한다 — **미구현 개선(P2-3(a) 등)을 은폐하려는 "통과" 조정 금지**(§0.9 theater).

---

## 6. 도구 명세 요약

`tools/ci/tcb_judgments.nim` — §0.2·§5·§1-4 프로토콜의 유일 구현.

| 서브명령 | 입력 | exit 0 | exit 2 | 보고 전용 |
|---|---|---|---|---|
| `--judgment parity --baseline B --candidate C` | B/C JSON (canonical projection) | parity 유지 | 불일치 symbol 목록 | — |
| `--judgment canonical-identity-set --baseline B --candidate C` | B/C 측정 digest JSON | invariant 집합 동일 | invariant 불일치 항목 | substrate digest 별도 보고 |
| `--judgment cache-manifest --workflow W` | action.yml (또는 발췌) | 신뢰 입력 기반 files{} 검증 존재(§3.3) | 원형(unfixed, §3.3), restore-keys 금지 위반(§3.5) | 프로브 커버리지 enum(§3.4 — `[COVERAGE-GAP]` FLAG, exit 변경 없음) |
| `--judgment worker-determinism --runs D` | D/*.json (N≥5) | N≥5 ∧ 전 digest 동일 | N<5 또는 digest 불일치 | 스케줄/부하 메타 |
| `selftest` | (고정 픽스처) | 전 FAIL 경로 실제 FAIL | — | — |

- 종료 코드: **0=PASS, 2=JUDGMENT-FAIL, 1=error** (입력/인자 오류). `ci_shadow_runner.sh:17-19` 관례와 동일.
- 결정적 출력(정렬·고정 스키마 JSON), 네트워크 없음, repo 파일 수정 없음, 예외 삼킴 없음(fail-closed — 읽기 실패는 error로 전파).
- 순수 로직은 `func {.raises: [].}`, I/O만 `proc` (AGENTS.md §0.6).
- **selftest 필수**: 각 판정의 FAIL 경로가 실제로 FAIL함을 고정 픽스처로 증명한다(항상 PASS = 죽은 게이트 = theater, AGENTS.md §0.9). selftest가 PASS면 즉시 도구 결함이다(§6.1).

### 6.1 selftest 수용 기준

```
tools/ci/tcb_judgments.nim selftest
→ 각 판정에 대해: (가) 반드시 PASS하는 픽스처가 PASS (exit 0),
  (나) 반드시 FAIL하는 픽스처가 FAIL (exit 2) — FAIL 경로 1건 이상 실증.
  전 항목 성립 시에만 selftest exit 0. FAIL 경로를 증명할 수 없는 판정
  (어떤 입력에도 FAIL하지 않는 판정)은 도구 결함 — selftest가 이를 노출.
```

---

## 7. 용어집

| 용어 | 의미 |
|---|---|
| VALID | 4개 증명 의무(J1..J4)를 전부 기계적으로 PASS한 CI 최적화 후보의 상태 |
| TCB (이 문서에서) | 머지 권한을 구성하는 컴포넌트/invariant 집합 — parity 관측 장치와 구분 |
| invariant digest 집합 | §2.4의 arch/substrate 독립 등가 성분 |
| substrate | 특정 runner image/OS/아키텍처/툴체인 조합 (cross-substrate 비교는 §2.5) |

---

## 8. 문서 변경 이력

| 버전 | 날짜 | 변경 |
|---|---|---|
| v1.0.0 | 2026-09-25 | P2 초안 — 승인된 CI-pareto 계획 Phase 2 (판정 정의 + 실행 프로토콜; 실험 결과는 후속 Phase) |

---

## 부록 A — P2 도구 구현 중 확인된 툴체인 quirk (AGENTS.md §0.5 의무 기록)

P2 도구(`tools/ci/tcb_judgments.nim`) 구현 중 확인된 Nim 툴체인 quirk를 기록한다. 정본 quirk 문서화 위치(`docs/spec/<topic>_quirks.md`) 별도 파일은 P2 산출물 범위 제약(이 문서 2개 파일만 생성)으로 이 부록에 수록하며, 후속 Phase에서 승인된 정본 파일로 분리 등록할 것을 권고한다.

1. **Nim 배열/const 리터럴 내부의 `##` doc 주석 파싱 불가**: `const k = [ "a", ## comment ... ]` 형태에서 `##` 주석이 연산자로 잘못 토큰화되어 `Error: expression expected, but found '...'` 발생(Nim 2.2.10). 배열 리터럴 내부 주석은 일반 `#` 사용 → 컴파일 성공. (2026-09-25 실측, tools/ci/tcb_judgments.nim).
2. **stdlib `sha1` 모듈의 sha256Hex 부재**: Nim 2.2.10에서 `import std/sha1`은 deprecated 경고 + `sha256Hex` 미제공(과거 stdlib API 아님). repo 관례 = `import checksums/sha1` + `$secureHash(...)` (`tools/ci/refresh_cli_binaries.nim:9,15`) — checksums 패키지 경로는 Makefile `NIM_TOOL_FLAGS`의 `--path:$(CHECKSUMS_PATH)`로 제공. (2026-09-25 실측)
3. **`node[k]`의 raises 추적**: `{.raises: [].}` 함수에서 `node[k]`(KeyError raisable)를 직접 사용하면 컴파일 차단 — `hasKey`+`kind` 가드 헬퍼(`strVal`)로 우회하되, **빈 문자열 결정적 처리**를 명시해야 함(예외 삼킴이 아님 — 무음 실패와 구분).
