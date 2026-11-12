# Axiom v1 Productization Contract (SSOT)

> Status: Ratified baseline for Axiom productization readiness evaluation (2026-08-16).
> 이 문서는 제품화 판정의 단일 진실 공급원(SSOT)이다. `config/readiness_policy.json`은 이 문서 §2 규칙의 기계판독 파라미터일 뿐이며, 판정 의미(semantics)는 `tools/readiness_evaluator.nim` 코드에 구현된다.
> **People investigate and interpret evidence; the verdict is decided by a pure function, never by a human.**

---

## §1. Product Profile (Axiom v1)

> **제품 정의 (v1)**: "지원되는 subject 범위 내에서 결정적 검증 결과 + assurance tier + 로컬 리플레이가 가능한 증거 산출물을 제공하는 개발자 CLI". 지원 subject scope = (i) **Nim 커널 범위** + (ii) **선언된 Rust certified subset** ([docs/spec/rust_certified_subset.md] 선언 범위 한정 — 전체 Rust 지원 주장이 아니다).

| 항목 | 내용 |
|---|---|
| Primary user | AI-generated code의 무결성을 검증하려는 로컬 개발자 (subject scope: Nim 커널 범위 + 선언된 Rust certified subset [docs/spec/rust_certified_subset.md] — 전체 Rust 지원 아님) |
| Primary surface | 로컬 CLI: `ax prove` / `ax report` (`ax status`는 Candidate — §7 v1 Contract Scope) |
| **Distribution (v1)** | **Dual-surface**: (i) **Developer-source install** (prereqs: Nim 2.2.10+, Lean 4.29+, Z3 4.13+; README 문서 준수) + (ii) **Public binary distribution** — `Archright/axiom-cli` 공개 릴리즈(immutable releases)의 검증 번들(`ax` + 카탈로그 + 시드 + grounds, Linux x86_64 단일 타깃) — §1b 참조. |
| Primary output | 기계판독 가능한 verification result(JSON) + **local replay-bound verification artifact**(per-function certificate) |
| **Core promise** | 동일한 **canonical input** + 동일한 **execution contract**(toolchain·solver·config·cache policy)에 대해 **재현 가능한(canonical semantic 동일) verification result**를 제공한다 |
| Verification semantics | 출력의 `verified` 계열 상태는 **확정된 규칙으로만 산출**되며, Z3-only 경로와 dual-assurance 경로가 식별 가능해야 한다 (R2) |
| Non-goals (v1) | CI platform 자체가 핵심 surface / enterprise orchestration / **broad AI-code verification guarantee** / **portable self-contained certification** / **mission-critical assurance** / **Race-Memory-Logic 전면 증명 (마케팅 표현 금지)** / 법적·규제적 보증 서비스. certificate는 출력 artifact로 존재하되 promise는 **"local replay-bound verification artifact"**로 제한됨. **Portable evidence artifact = NO (v1 non-goal)** — v1 artifact는 `(cert + trusted journal + claims/solver + source repo)` 의 합으로 정의되는 **local replay-bound** 이다. "provenance-bearing" 같은 표현은 v1에서 local replay-bound 로 재명한다. README? 에 대한 수정은 Phase 4 담당. **[ADR-0020 carve-out]**: "CI platform 자체"는 CI **실행·오케스트레이션 플랫폼**을 지칭한다. CI **출력을 소비하는** verification/admission 계층(merge admission, speculative candidate queue semantics — `docs/adr/0020-axiom-queue-semantics-and-executor-boundary.md`)은 이 non-goal에 포함되지 않으며, 이미 커밋된 merge admission 계약(`docs/spec/merge_admission_controller.md`)의 확장으로 취급된다. |

**Documented commands (v1 contract surface)**: `ax prove`, `ax report` (각각 help surface 필수). `ax status`는 Candidate surface — §7 v1 Contract Scope 참조.

---

## §1b. Binary Distribution Contract (Phase 6)

> Status: Ratified 2026-11-08 (Phase 6). 소스 공개 전환과 독립적으로 유효(소스가 공개돼도 본 경로 유효).
> **Non-goal 무변경**: §1b는 배포 경로 계약이지 portable evidence 약속이 아니다 — §1 "Non-goals (v1)"의 local replay-bound non-goal은 본 경로에서도 그대로 유지된다.

**배포 자산**(Archright/axiom-cli, immutable releases 활성):

- 번들 tar.gz: `ax`(루트 직접 배치 — `bin/` 하위 배치 시 SourceCoherence FATAL) + `config/spec/` + `data/verification_scope.lock`·`data/baseline.json`·`data/bug_attribution/` + 루트 앵커 `.axiom_root`
- SHA256SUMS + attestation bundle(오프라인 `--bundle` 검증, `--signer-repo Archright/Axiom` 핀) + manifest.json(버전·원본 소스 커밋·빌드 SHA·바이너리 sha256)
- 태그 = `axiom.nimble` 버전(release-ship verify-metadata 게이트 준수)

**실행 계약**:

- 루트 해석: `AXIOM_ROOT` env 최우선 → 미설정 시 바이너리 위치에서 상향 `.axiom_root`/`axiom.toml` 앵커 탐색(첫 앵커 종료). 번들 루트에 `ax`+`.axiom_root` 배치 시 자동 재현. 트리 밖 앵커 미스는 카탈로그 read fail-closed(Q-013, `docs/spec/nim_2_2_10_stdlib_quirks.md`)
- 상태: `AXIOM_STATE_DIR` 지정(시드는 `$AXIOM_STATE_DIR/data` 우선 탐색)
- 런타임 툴체인(전부 공개 소스, 고객 CI 버전 핀 프로비저닝): nim 2.2.10(harness 런타임 컴파일 — 제품 설계상 의도)·z3 4.13.3·lean 4.33.0/elan·git·libpcre3(로드 타임 dlopen 하드 의존)
- replay deps 4종: 번들 미포함 — 공개 repo에서 SHA 핀 클론(카탈로그 지정 slug)
- exit 5-state(§v1 CLI Exit-State Contract)**무변경** — 고객 Check 판정은 워크플로우 어댑터가 state rollup을 읽어 매핑: DISPROVED→FAIL, UNKNOWN→FAIL(fail-closed), 전명제 INCAPABLE→정직 요약(판정 없는 green 금지), exit 3/4→FAIL

**재현성(D-입력 집합)**: 바이너리 배포 경로의 재현성은 **D = H(Axiom Bundle, Proposals, Subject, Toolchain, Replay Dependencies, Execution Configuration)**의 전 입력 고정으로 정의. 결속은 2층: (a) **워크플로우 관측 결속(관측 계약의 정본)** — 4-tuple(proposals sha256·subject 커밋·axiom 커밋·canonicalRunDigest) + dep manifest(각 dep slug/commit/clean 단언) + 툴체인 관찰 + 잡 컨테이너 image digest 핀 + libpcre3 버전 기록 + `AXIOM_PROVE_WORKERS=1` 고정 + 동일 입력 2회 실행 digest `cmp` 기계 단언; (b) 엔진 digest 결속(ReplayRecord dep fingerprint + canonicalSerialize 개정)은 후속 회전 PR 후보. 근거: canonicalRunDigest는 판정 회계(runAccounting+executionEvidence+runOutcome)만 해시 — dep·툴체인·proposals 바이트를 직접 결속하지 않는다.

**신뢰 모델**: 고객측 = sha256 + attestation 오프라인 bundle 검증(고객 자기 GITHUB_TOKEN만 — Archright 접근 0). provenance 게이트(`--check-provenance`)는 릴리즈 빌드 측 전용.

**라이선스 준수(SAL 1.0)**: §5.1(사용·재현·상업 목적 허가)·§6.1(재배포 시 LICENSE·LICENSES/·THIRD-PARTY-NOTICES.md 동반) — axiom-cli 배포소가 동반. 공개 소스 검증은 §1.1 무료, 비공개 소스 검증은 §1.2 상업 계약 필요.

---

## §2. Readiness Invariant Registry

상태는 `PASS | FAIL | UNKNOWN` 3값. **evidence 누락·무효·상충 → UNKNOWN (fail-closed, 조용한 PASS 금지).**

불변식 판정 규칙에서 사용하는 관찰 키는 §4 스키마로 고정된다. 각 규칙은 evidence의 observation만으로 계산되며, 사람 판단이 개입하지 않는다.

### R1 — Product Contract (critical)

> 문서화된 promise(§1)가 실제 CLI surface와 일치한다.

| key | type | 의미 |
|---|---|---|
| `documentedCommand` | string | README/문서에서 발견되는 명령 문자열 (subject=문서 위치) |
| `commandExists` | bool | CLI에 실존 (scope=`surface`, subject=명령) |
| `promiseOutputExists` | bool | promised output(JSON 결과 / artifact / certificate) 산출물 실존 (subject=출력 종류) |
| `subjectLane` | stringlist | readiness GO가 청구되는 subject-language lane (subject=lane 명, policy `r1.trustBoundaryLanes` 등록명) |

규칙: 모든 `documentedCommand` subject에 대해 `commandExists=true` (subject 동일 문자열) 필요. 1개라도 false/부재 → **FAIL**. observation 부재 → UNKNOWN.

규칙 (신뢰 경계 연동 — U1, ADR-0030): `subjectLane`으로 청구된 각 lane에 대해 policy `r1.trustBoundaryLanes[lane]`의 모든 경계 컴포넌트가 `src/core/trusted/trust_boundary.nim` 레지스터에서 `exists:true`여야 한다. lane 미등록 · 경계 미선언 · `exists:false` 중 하나라도 → **FAIL** (해당 lane에 대한 GO 발행 불가, fail-closed). `subjectLane` 청구가 없으면 이 규칙은 발화하지 않는다. 레지스터는 읽기 전용으로 소비된다 — readiness가 `exists`/`category`를 뒤집지 않으며, 레지스터 내용 변경은 본 규칙 밖의 인간 승인 사항이다.

### R2. Result Semantics (critical)

> 결정적 상태의 의미가 명확하고 Z3-only 항목가 dual-assurance 구분된다. **`verified`에 vacuous proof가 포함되면 FAIL.**

| key | 필수 | 의미 |
|---|---|---|
| `certGreenDualEvidenceRequired` | Y | canonical 경로에서 certGreen 산출에 dual evidence 요구 여부 (scope=`canonical-promotion`) |
| `z3OnlyCanProduceCertGreen` | Y | Z3-only 증거로 certGreen이 산출 가능한 경로 존재 여부. scope=`canonical-promotion`이 true이면 **FAIL** |
| `summaryVerifiedIncludesVacuous` | Y | CLI summary `verified` 카운터에 vacuous(자명) 증거 포함 여부. `true` → **FAIL** |
| `z3VsDualDistinguishable` | Y | 출력에서 Z3-only 상태와 dual 상태가 구분 필드/문자열 존재. `false` → **FAIL** |
| `verifiedSemanticsDocumented` | Y | 무슨을 의미하는지 기재한 문서 존재. `false` → **FAIL** |

### R3. Verification Determinism (critical)

> 정의: **Canonical Result Projection**(§6) 해시가 실행 간 동일.

| key | 필수 | 의미 |
|---|---|---|
| `canonicalProjectionHashEqual` | Y | 동일 입력+환경 2회 실행의 canonical projection hash 동일 여부. `false` → **FAIL** |
| `canonicalInputHash` | Y | 실행 입력의 SHA-256 |
| `configHash` | Y | 구성 스냅샷 hash |
| `solverIdentity` | Y | solver 버전 식별 (예: `z3-4.13.3`) |
| `cachePolicy` | Y | cache warm/cold/정의 상태 |
| `canonicalExecutionFingerprint` | Y | §6 범위의 실행 지문 (위 4개를 포함한 canonical contract hash) |
| `environmentControlled` | Y | 시간/난수/스케줄링 제어 문서 여부. `false` → **FAIL** |
| `subjectRunProjectionHashEqual` | Y | subject-scoped 실행 간 canonical projection hash 동일 여부. `false` → **FAIL**. 부재/미측정 → **UNKNOWN** (fail-closed, 조용한 PASS 금지) |
| `pathIndependentProjectionEqual` | Y | 동일 subject를 다른 물리경로에서 실행한 런 간 canonical projection hash 동일 여부(재배치 결정론). `false` → **FAIL**. 부재/미측정 → **UNKNOWN** (fail-closed, 조용한 PASS 금지) |

### R4. Artifact / Provenance Integrity (critical)

> 결과 artifact만으로 **local replay-bound** 로 정의되는 천(claim→evidence→toolchain→solver→input chain) 복원 가능하다. replay 범위 = `(cert + trusted journal + claims/solver + source repo)` 의 합 (§1, §7a). **Portable evidence artifact는 v1 non-goal** — R4의 복원 대상은 portable artifact가 아니라 local replay-bound artifact 이다.

| key | 필수 | 의미 |
|---|---|---|
| `certFieldPresent` | Y | certificate 필드 존재 (subject = policy의 requiredFields) |
| `provenanceReconstructible` | Y | artifact만으로 claim→evidence→toolchain→solver→input chain 복원 가능 여부. `false` → **FAIL** |

requiredFields는 policy(`r4.requiredFields`)에서: `claim, attestation, inputHash, provenance, toolchainIdentity, solverInvocation, solverInputDigest, solverResultDigest`. `proofDigest`는 현재 증명 artifact 파이프라인이 미구현되어 null 유지 — optional. 정식 corpus scope = 평가 시점 기준 `src/verification/certificates/` 아래의 모든 v3 certificate; 아카이브된 레거시 certificate는 역사적 데이터로 scope 밖.

### R5. CLI Contract Stability (critical)

| key | 필수 | 의미 (subject=커맨드) |
|---|---|---|
| `commandExists` | Y | 커맨드 존재 |
| `helpSurface` | Y | 도움말 surface 존재 |
| `successExitCode` | Y | 성공 exit code (int) |
| `verificationFailureExitCode` | int (있으면) | 검증 실패 전용 exit code. success와 동일 → **FAIL** |
| `invalidInputExitCode` | int (있으면) | 잘못된 입력 전용. 미정의 → **FAIL** (정의해야 함) |
| `internalErrorExitCode` | int (있으면) | 내부 오류 전용. success와 동일 → **FAIL** |
| `jsonSchemaVersion` | string | 출력 JSON 스키마 버전 표기 존재 |
| `stdoutStderrSplit` | bool | stdout(structure)와 stderr(diagnostic) 분리 여부. `false` → **FAIL** |

### R6. Failure Semantics (critical)

> 실패가 성공으로 둔갑해선 안 된다. 정의가 없는 실패 경로는 fail-closed가 아님.

| key | 필수 | 의미 |
|---|---|---|
| `failureConvertsToSuccess` | Y | 실패 사건이 성공 상태로 상향되는 경로 존재 (subject=계층). 하나라도 `true` → **FAIL** |
| `exceptionSwallowed` | Y | 예외를 흘리며 성공 반환하는 경계 (subject=계층). 하나라도 `true` → **FAIL** |

### R7. Scope / Coverage Honesty (non-critical)

> 제품이 "verified"라고 표시하는 범위가 문서가 약속한 범위를 초과하지 않는다. 낮은 적용범위 자체는 조건부 허용, **과장은 R1/R2 FAIL로 승격**.

| key | 필수 | 의미 |
|---|---|---|
| `claimedScope` | Y | 문서가 주장하는 검증 범위 (string[], subject=문서 위치) |
| `measuredCoverage` | Y | 측정된 적용 범위 (float, subject=`vkd` 또는 `module-coverage`, scope=측정 단위) |
| `verifiedEmitterScope` | Y | 실제 "verified" 상태를 산출하는 표면/대상 (string[], subject=위치) |

평가 규칙(R7, evaluator code):
1. `measuredCoverage`(subject=`vkd`/`module-coverage` 등 모든 항목)에 대해: 존재하지 않으면 → R7 **UNKNOWN**. `vkd < policy.r7.vkdMinThreshold` → **FAIL** (non-critical)
2. **Promotion (evaluator 고정 규칙)**: `verifiedEmitterScope` token 중 `claimedScope` token 집합에 없는 token이 1개라도 존재 → **R1 FAIL + R2 FAIL** (승격, over-scope 검증)
3. claimed scope에 대한 measurement 누락 → R7 FAIL

### R8. Reproducible Operability (critical)

> 개발자 머신에서 문서만으로 설치 → 실행 → 결과 재현이 **수동 개입 없이** 가능하다. 성능은 판정 대상 아님.
>
> **명확화 (2026-10-14, 성능 제외의 범위)**: "성능은 판정 대상 아님"은 **R1–R8 readiness 판정의 축에 한정**된 제외다 — 판정 축은 환경 간 재현 가능해야 하므로, 하드웨어 의존적인 wall-clock·처리량은 PASS/FAIL/UNKNOWN을 뒤집지 못한다. 이 제외가 성능 **최적화를 금지하는 것은 아니다**: 성능은 독립 트랙으로 예산·회귀 게이트(`data/benchmarks/perf_budget.json` + `make perf-check`)가 관리한다.

| key | 필수 | 의미 |
|---|---|---|
| `installFollowed` | Y | 문서 순서대로 설치 경로 성공 여부. `false` → **FAIL** |
| `manualStepsRequired` | Y | 수동 개입(환경변수, 캐시 복사, 미커밋 파일, 시크릿 주입) 없이 실행되는지를 표시 (subject=개입 종류). `true` → **FAIL** |
| `cleanRunSucceeded` | Y | 격리 환경 1회 실행 성공 여부. `false` → **FAIL** |
| `documentedRunSteps` | bool | 문서화된 실행 절차 존재. `false` → **FAIL** |

---

## §3. Decision Table (verdict, evaluator)

```
invariantState ∈ {PASS, FAIL, UNKNOWN}
GO            ⟺ 모든 invariant = PASS
CONDITIONAL GO ⟺ critical 전부 PASS ∧ ∃ non-critical ∉ PASS
                 (conditions는 evaluator가 해당 상태에서 기계 생성)
NO-GO         ⟺ ∃ critical ∈ {FAIL, UNKNOWN}
```

- UNKNOWN은 PASS로 승격 금지. 상충/무효/missing → UNKNOWN.
- 조건 목록(conditions)은 사람 입력이 아니라 **state에서 자동 생성**.

## §4. Evidence Envelope & Validity

```json
{
  "schemaVersion": 1,
  "invariantId": "R2",
  "repoIdentity": {"head": "...", "branch": "main", "workingTreeClean": true,
                   "treeDigest": "sha256:..."},
  "toolchain": {"nim": "2.2.10", "z3": "4.13.3", "lean": "4.33.0"},  // observed
  "collection": {"collector": "evidence-r2-subagent", "method": "manual",
                 "generatedAt": "ISO8601", "freshUntil": "ISO8601"},
  "observations": [{"key": "...", "value": true|0|1.5|"..."|["..."],
                    "scope": "...", "subject": "..."}],
  "incidents": [{"violationId": "INC-001", "kind": "string",
                 "invariants": ["R2","R5","R6"], "summary": "string"}],
  "sources": [{"file": "...", "lines": "1-10", "symbol": "...",
                "sha256": "sha256:...", "repoHead": "49aa5813c"}],
  "commands": [{"cmd": "...", "exitCode": 0, "outputDigest": "sha256:..."}]
}
```

- **재현성**: evidence의 작업 tree는 tracked 파일이 무변경(`git status --porcelain --untracked-files=no` 기준)이어야 evidence를 `repoIdentity.workingTreeClean=false(변경)로 invalid 처리해서는 안 된다 — 단, R1/R3/R8 evidence는 `workingTreeClean=true` 필수.
- **generatedAt/freshUntil**: collector가 수집 시점에 둘 다 고정 기록. evaluator는 `context.evaluationTime <= freshUntil`만 검사. 시간은 validity에만 사용되고 verdict 직접 입력 금지.
- **contradiction**: `same key ∧ same scope ∧ same subject ∧ 상충 value` → UNKNOWN. key/scope/subject가 다르면 정상 병합.
- **sources**: file:line은 참조일 뿐, 고정 앵커는 `sha256`(파일 바이트 hash) + `repoRef`.
- **commands**: 재현 명령과 exit code, `outputDigest=SHA-256` 필수.
- **evidenceDigest/bundleDigest/decisionDigest**: SHA-256, canonical 같다(키 정렬) 기준.

추가: **incidents는 보고서용 root-cause 채널** — 상태 판정에 직접 사용하지 않는다 (`invariantStates`는 observation만으로 산출, 중복 집계 방지용).

---

## §5. Evaluation Context & Purity Boundary

```nim
{ "repoHead": "49aa5813c", "branch": "main", "workingTreeClean": true,
  "treeDigest": "sha256:...", "toolchain": {"nim": "2.2.10", ...},
  "evaluationTime": "ISO8601" }
```

- Pure core = `validateEvidence / normalizeBundle / evaluateReadiness` — `{.raises: [].}`
- IO(`loadEvidenceFiles`)는 loader에만. `evaluateReadiness(policy, bundle, context)`가 순수 시그니처.
- repository identity: `repoHead`(commit) ≠ `treeDigest`(실제 source state, `sha256(git ls-tree -r HEAD)`). 모두 context/evidence에서 항상 2개가 불일치하면 evidence invalid.
- toolchain identity 불일치 → invalid.

---

## §6. R3 Canonical Result Projection

semantic equality 정의 — raw artifact byte equality 아님:

| 포함 | 제외 |
|---|---|
| claim/verdict (per-function status) | timestamp, generatedAt |
| assurance tier / verificationTier | runId |
| proofDigest(reason/smtlib hash 등) | tmp path, absolutePath, vaultPath, sourcePath, subjectRoot/stateRoot/repoRoot (경로·위치 identity) |
| policyIdentity / config | processId, randomness |
| input(sourceHash) | solver 내부 trace(비결정), evidenceLogJson(런 스코프 증거 로그) |
|  | 실행·성능 telemetry (solverElapsedMs, wallElapsedMs, parallelOverheadMs, startedAtMs/endedAtMs/elapsedMs, cacheHit, cacheHitCount, totalWallTimeMs 등 — 머신 측정값) |

**Phase 6 실측 (2026-08-17)**: 증명·report 출력의 canonical semantic projection 해시가 동일 입력·동일 execution contract에서 2회 실행(A/B)에 대해 **동일**함 — prove `H(pS) = 931ccedd…` (semantic equality 소요 후 남는 유일 차이는 위 excluded telemetry 필드), report `H(pS) = 92ff6cd6…`.

`canonicalProjectionHash` = SHA-256(정렬된 포함 필드 JSON). `canonicalExecutionFingerprint` = SHA-256({canonicalInputHash, configHash, solverIdentity, cachePolicy, claimedToolchainIdentity}).

**단일 구현 (2026-08-26)**: `core/utils/canonical_projection.nim::canonicalProjectionHash`가 본 해시의 유일한 구현이다. CLI 노출: `ax report --canonical-digest` (SSOT `logs/ax_proof_state.json` 기준). 제외 규칙 — 최상위 `runtimeMeta` 객체 전체와, 트리 전체에서 다음 volatile 키를 재귀 제거한다: `timestamp, startedAtMs, endedAtMs, elapsedMs, solverElapsedMs, parallelOverheadMs, activeNodeCount, availableMemoryBytes, cpuLoadRatio, recommendedWorkerCount, totalWallTimeMs, hotspotElapsedMs, hotspotLabel, runId, generatedAt, processId, timedOut, timeout, timeoutCount, timeoutNodes, timeoutImpactNodes, timeoutHotspots, timeoutComplexityWeight, wallElapsedMs, vaultPath, tmpPath, absolutePath, path, sourcePath, subjectRoot, stateRoot, repoRoot, cacheHit, cacheHitCount, evidenceLogJson`. 나머지 모든 필드는 포함하며, 직렬화는 객체 키 정렬 순으로 수행한다. 새로운 타이밍/런타임 관측 필드 추가 시 이 목록을 갱신하는 것이 이 구현의 유일한 유지 지점이다.

**동기화 (2026-10-03, wall-clock 분리)**: §7·R3 결정론에서 wall-clock 만료는 hang-guard **run abort**(검증 판정 아님)이므로, 같은 입력이 느린 머신에서 다른 해시를 내지 않도록 timeout 계열(`timedOut*`)과 런 식별자(`runId, generatedAt, processId`)를 volatile로 편입했다. gas/rlimit 소진은 입력+execution contract로 결정되므로 volatile이 아니며 해시에 남는다(검증 실패는 결정적 결과의 일부).

**동기화 (2026-10-12, 경로·캐시 키 편입)**: 위 제외표의 "tmp path, absolutePath"·"cacheHitCount" 행이 구현(`stripVolatile`)에 누락되어 있던 문서-구현 불일치를 해소했다. 동일 logical subject를 다른 물리경로(다른 `AXIOM_STATE_DIR`)에서 재검증해도 같은 해시가 나와야 하는 R3 `pathIndependentProjectionEqual`을 관측하려면 위치 identity가 투영에 스며들면 안 되므로, 경로·위치 키(`vaultPath, tmpPath, absolutePath, path, sourcePath, subjectRoot, stateRoot, repoRoot` — `vaultPath`는 `orchestrator_vault.nim:175`의 `joinPath(vaultDir, …)`로 state-root 의존)와 캐시 상태 관측 키(`cacheHit, cacheHitCount` — cold/warm 경계에서 동일 입력에 대해 뒤집히는 값으로 logical identity가 아님), 런 스코프 증거 로그(`evidenceLogJson` — §6 제외 "solver 내부 trace"; 상태 필드와 중복 및 런-로컬 경로 내장 가능)를 volatile로 편입했다. 측정: `tools/ci/wp5_relocation_measure.nim` (negative control must-flip + comment-only must-not-flip 통제 포함, cold cache policy).

---

## §6a. Input Identity Contract (v1)

**Input identity = `(sourceHash, irHash)`** — semantic: 입력 소스 + 번역 상태(input source + translation state).

- `sourceHash`: 입력 소스의 canonical digest.
- `irHash`: 번역 상태(번역된 IR)의 canonical digest.
- **`canonicalInputHash` 신규 구현은 v1 non-goal** — v1에서는 `(sourceHash, irHash)` 쌍 자체가 identity로 사용되며, 두 값을 합성한 단일 `canonicalInputHash` 필드는 v1에서 요구하지 않는다. Phase 3 이후 필요 시 도입.

---

## §6b. VKD Contract (v1)

**VKD (Verified Kernel Density) = |VKS ∩ certGreen| / |VKS|**

- 분모 `|VKS|` = `Kernel_total` − `kernel_exempt_symbols`. **23 (kernel 40 − exempt 17)은 `ax scope lock`이 산출한 스냅샷 값이지 고정 상수가 아니다** — 규칙(rule)은 `kernel_total − kernel_exempt_symbols`를 동적 재계산하는 것이며, 정본 값은 `data/verification_scope.lock`(`updated_by: "ax scope lock"`)이 운반한다. 이는 [docs/spec/verification_density.md §Binary Contract — Baseline vs Scope]의 "dynamic value, **not** a hardcoded `40`" 규칙과 동일 계약이다.
- 분자 `|VKS ∩ certGreen|` 는 **`isVkdAdmissible` 만 사용**한다.
- **`isDeepVerified`(broad)는 VKD numerator에 사용 금지** — `isDeepVerified`는 더 넓은 증명 범위를 의미하며, VKD 분자로 쓰면 VKD가 과장되다.
- **실측값 (Phase 3 완료, 2026-08-17)**: `ax report --json` → `metrics.vkd` = **0/23 = 0.0%** (HEAD 이후 변경 트리 기준, `getCanonicalVkdMetrics` 단일 projection). 이 값은 측정 truth이며 목표가 아니다. 과거 문서의 21.7% (5/23) 주장은 certGreen 자격 조건 강화(`isVkdAdmissible` 도입, v33) 전 산출로 **현재 계약 정의에서는 재현되지 않는다** — `metrics.vkd`만이 판정 수치다. AGENTS.md §0.11의 `vkd (5/23 ≈ 21.7%)` 기재는 **rev.3.1 승인 (2026-08-17)으로 값 제거 완료** — 값 대신 "VKD is derived exclusively from the canonical verification-density projection. Do not treat historical, documented, or cached VKD values as authoritative." 원칙 블록으로 교체됨.

---

## §6c. R3-④ Rust skReport 교차 실행 경로 재현 비교 (v2, 2026-11-01)

**대상 산출물**: Rust 서브젝트 레인이 trajectory SSOT에 기록하는 lane report 페이로드(`logStage(skReport, extra)` → `ax_prove_trajectory.jsonl`; `schemaVersion: axiom.report.v1`, `subjectLane: "rust"`)와, v2에서 레인이 report 생산과 동일 시점에 생산하는 identity sidecar(`skreport-identity.json`, 아래 **번들 생산 authority**). 본 절은 서로 다른 두 실행 경로(다른 checkout/state)에서 얻은 두 (페이로드, sidecar) 쌍의 **재현 비교 판정**을 정의한다. skReport 자체의 생산 authority는 변경되지 않는다(레인 `src/cli/rust_lane_cli.nim` + trajectory sink).

**Authority**: "동등" 판정의 유일한 구현은 §6c 규칙의 단일 함수다(`src/core/utils/skreport_comparison.nim`). 이는 순수 projection이며 새 CLI 표면·새 exit 의미를 만들지 않는다(§7 표·exit 계약 불변). 원본 skReport·원본 reason 문자열은 절대 재작성되지 않는다 — 비교 기록은 원문을 참조(sha256)하고 reason을 **그대로 인용**해 보존한다. **번들 생산 authority (v2 선언)**: identity sidecar의 유일한 생산자는 레인이다 — report 생산과 **동일한 `finish` 경로**에서, run이 실제로 소비한 객체들(스코프 락 항목, `specEntryFor` 스펙 사이드카, 해석된 모듈 파일, charon 핀 게이트의 측정 라인)과 기존 측정 프리미티브(`subjectGitIdentity`, `rustToolchainFingerprint`+`rustToolchainIdentityToken`, `fileSha256Hex`, D1 파일셋 지문, `$NimVersion`)로 측정해 생산한다. 측정은 **all-or-nothing**이다: 필수 필드 하나라도 미측정이면 sidecar를 쓰지 않고 측정 갭 사유를 기존 lane 로그 채널(stderr)에 verbatim 남긴다 — sidecar 부재 = identity 축 unknown(새 판정 없음, 기존 규칙 재사용). 원격 원장 착지(issuance 경로)는 현 위치에 그대로 둔다; sidecar는 로컬 state 산출물이며 `GITHUB_TOKEN` 부재 환경에서도 생산되어야 한다.

**번들 생산 규격 (v2)**: sidecar 경로는 `<AXIOM_STATE_DIR>/.axiom/rust-lane/<sha256Hex(projectAbs)[0..15]>/skreport-identity.json` — `(projectAbs, stateRoot)`의 결정적 함수라 소비자가 재발견 가능하다. 문서 구조: `{"schemaVersion": "axiom.skreport-identity.v2", "identity": {…}, "binding": {…}}`.
- **`identity` 섹션 (비교 대상, 위치 독립 — run 가변 데이터 금지)**: `subject{commit, modulePath, moduleSha256, sourceFingerprint}` · `claim{symbol, specRef, postSha256}` · `scope{rustTargetsSha256}` · `toolchain{charon, rustc, cargoLockSha256, cargoManifestSha256, nim}` · `rejection`(구조화 거절 기록, 아래; 없으면 null). `subject.modulePath`는 **서브젝트 루트 상대 POSIX 경로**다(절대 경로·`..` 포함 형태는 측정 갭 — 위치 identity가 비교에 스며드는 것을 금지). `subject.sourceFingerprint`는 D1 파일셋 지문(`rustSourcePolicy` 수집 + `finalizeSourceFingerprint`)으로 커밋되지 않은 비모듈 소스 변경까지 결속한다. `toolchain.cargo`는 v1의 단일 문자열 대신 `RustCargoIdentity`와 동일 정의의 `cargoLockSha256`+`cargoManifestSha256` 쌍이다(Cargo.lock 부재 = 측정 갭 — 의존성 미고정 run은 비교 불가, fail-closed). digest-typed 키(`subject.moduleSha256`·`subject.sourceFingerprint`·`claim.postSha256`·`scope.rustTargetsSha256`·`toolchain.cargoLockSha256`·`toolchain.cargoManifestSha256`)는 64자 소문자 hex sha256이어야 한다.
- **`binding` 섹션 (무결성 체인, 위치 의존 허용 — 비교 대상 아님)**: `{"payloadSha256": <해시 캐논 페이로드>, "rejection": {"reasonLeaf": "targets[0].reason", "rawPath": <거절 엔트리 원경로>}}` — `rejection`은 구조화 거절이 있을 때만 존재한다. `rawPath`는 run-relative 물리경로로 **이 섹션에만** 존재하며 identity 섹션·페이로드 어디에도 들어가지 않는다(§10.1 D3 물리경로 비포함 원칙).
- **생산시점 결속 체인 (기계적 재검증 가능 — caller 플래그가 아니다)**: ① `payload.identityBundleDigest` = `sha256Hex(sortedCanonicalJson(sidecar에서 binding 섹션을 제거한 문서))` — 페이로드가 자신의 identity 선언을 운반한다; ② `sidecar.binding.payloadSha256` = `sha256Hex(sortedCanonicalJson(최종 페이로드))` — sidecar가 자신의 페이로드를 운반한다. 두 검사는 비교 시점에 순수 재계산으로 확인되며, 쌍의 치환·단편 변조를 fail-closed로 만든다. 이 체인은 변조 불가능한 서명이 아니다 — equal의 신뢰 근거는 (a) 레인의 생산시점 측정(선언 authority), (b) 이 digest 체인, (c) 제공된 경우 비교시점 재측정과의 일치이며, 세 가지 모두 기계적이다.

**구조화 거절 기록 (v2 — 판정 불변의 감사 결속)**: `validateLlbcFileTable`은 첫 위반 지점에서 자신이 이미 알고 있는 사실을 구조화해 반환한다(`RustFileTableRejection`: rule 태그·offending index·crate_name·원경로·임베디드 contents의 sha256) — 거절 판정·reason 문자열은 변경되지 않는다. 이 값은 `rustSubjectInputContract` → `RustSubjectOutcome.rejection`으로 전파되고, 레인이 단일 target의 거절에서 sidecar에 결속한다: `identity.rejection = {rule, index, crateName, contentSha256, skeletonSha256}`(`skeletonSha256` = 리프 reason 전체에서 `rawPath`를 상수 마커 `<offending-path>`(`axiomSkReportSkeletonMarker`)로 치환한 문자열의 sha256 — 레인 생산, 비교자 재계산 가능). 생성물 내용의 **신뢰/허용은 §6d 영역**으로, 본 기록은 거절된 문서의 생산시점 신원 결속일 뿐이다(내용 digest는 "거절된 파일이 무엇이었는가"의 측정이지 생성물 신뢰가 아니다).

**판정의 의미 (조건부 — 과대 해석 금지)**: 비교기는 두 (페이로드, sidecar) 쌍을 대조하는 순수 projection이다. **equal은 "양측 쌍이 각자의 생산시점 결속 체인을 통과하고, 양측 identity 섹션이 서로 일치하며(구조화 거절 신원 포함), 양측 페이로드가 structure·reason 축에서 일치한다"는 판정**이다. equal은 여전히 certified reproduction 전부가 아니라 — 변조 불가 서명이 없으므로 — 생산시점 측정·digest 체인·(제공 시) 재측정으로 방어된 조건부 판정이다. 비교 입력에 `measured`(재측정 anchor — 비교 시점에 `subjectGitIdentity`·`fileSha256Hex` 등 기존 프리미티브로 측정한 identity 경로 값)가 제공되면: 선언≠측정 → identity 축 **not_equal**(반증), 측정 갭 → unknown-note, 일치 → note로 기록. 미제공이면 기록된 생산시점 측정(tcRecorded 동급)이 서며, 세계가 살아있는 동안 재검증 가능하다.

**Identity 결속 (v2 필수 키)**: 필수 경로는 `subject.commit`·`subject.modulePath`·`subject.moduleSha256`·`subject.sourceFingerprint`·`claim.symbol`·`claim.specRef`·`claim.postSha256`·`scope.rustTargetsSha256`·`toolchain.charon`·`toolchain.rustc`·`toolchain.cargoLockSha256`·`toolchain.cargoManifestSha256`·`toolchain.nim`. 필수 키 누락·빈 값, sidecar schemaVersion 누락·미인식, digest 형식 위반, dotted 경로의 중간 비객체 hop, `claim.symbol`이 양쪽 `targets[0].name`과 미결속 → identity 축 **unknown**(malformed → fail-closed). 생산시점 결속 체인 불일치(①·② 재계산 미일치, sidecar 부재, 페이로드에 `identityBundleDigest` 키 부재) → identity 축 unknown.

**판정 규칙 (결정적)**: 세 축 — identity / structure / reason.
1. **identity**: 양측의 결속 체인·필수 키·스키마가 완전하고 identity 트리(구조화 거절 신원 포함)가 깊이 동등하며 제공된 재측정 anchor와 일치하면 equal; 하나라도 다르면(선언간 차이 또는 선언≠재측정) not_equal; 결속 실패·누락·malformed면 unknown.
2. **structure**: 양쪽 페이로드에 §6의 단일 canonicalizer(`canonical_projection.stripVolatile`)를 적용한 뒤 대조한다. `reason` 키는 **임의 깊이에서**, `identityBundleDigest` 키는 **문서 루트에서만** 구조 축에서 제외된다(각각 reason 축·identity 축 관할 — sidecar 결손이 구조를 오염시키지 않는다; 루트 한정은 재감사 F1 수정으로 구현된 더 엄격한 규칙이며 본 문면이 이를 규정한다 — 재감사 2026-11-01). **범위·한계 (재감사 2026-11-01 실행 확인)**: stripVolatile은 §6/R3 규정에 따라 volatile **이름** 키(`path`, `subjectRoot`, `stateRoot`, `repoRoot`, `cacheHit`, `timeoutCount` 등 — `src/core/utils/canonical_projection.nim` volatileKeys)를 임의 깊이에서 제거하므로, 중첩 volatile명 키 **안에만** 존재하는 차이는 세 축 어디의 관할도 아니며 **equal**로 판정된다. 이는 위치·캐시·시간 관측값을 논리 정체에서 의도적으로 분리하는 §6 semantic-equality 규정의 직접 귀결로 계약 부합 동작이지만, 오늘의 레인 페이로드(axiom.report.v1 rust lane)는 해당 이름을 중첩하지 않아 정직 산출물에는 잠재 표면이고, 소비자 공급·위조 입력에서는 일관-sidecar 위조(B3iii 동급 최소 조건)로 도달 가능한 false-equal 표면이다 — **잔존 한계로 명시 수용**하며, 제거하려면 §6 canonicalizer 개정이 선행한다(구현이 단독으로 canonicalizer를 이탈하지 않는다). 그 외 잎이 하나라도 다르면 not_equal. `targets` 길이가 양쪽 1이 아니면(단일 target이 ④ 인증 범위 — `--target` 정확히 1 매치 사용법) 구조 축은 unknown이다. `schemaVersion`이 `axiom.report.v1`이 아니면 unknown이다. `subjectLane`이 양쪽 `"rust"`가 아니거나 absent면 구조 축은 unknown이다.
3. **reason**: raw 페이로드의 모든 `reason` 잎(문서 순서, `charon.reason` 포함)을 문자열끼리 비교한다. 모두 동등하면 equal. 차이 쌍이 있으면 **전부 검사한다 — 첫 차이 후 판정을 중단하지 않는다(재감사 F2 수정: 승격된 잎이 뒤잎의 실차이를 은폐하지 않는다)**. 차이 쌍별로: **(v2 승격 규칙)** 그 잎 쌍이 양측 `targets[0].reason`에 있고 — 위치 결속: 비교자가 잎의 문서 순서 경로를 식별해 양측 `binding.rejection.reasonLeaf` 기록과의 일치까지 강제한다(재감사 F3 수정 — 기록 부재·공란·변조·위치 불일치는 승격 실패) — 양측의 `identity.rejection`이 깊이 동등하며, 양측 `binding.rejection.rawPath`가 각자의 리프 reason에 실제로 포함되고, 각 리프에서 자신의 `rawPath`를 마커로 치환한 문자열의 sha256이 자신의 `identity.rejection.skeletonSha256`와 일치하면 — reason 차이가 **기록된 offending 경로 하나로 완전히 설명**되고 거절의 논리 신원(rule·index·crate·내용 지문·skeleton)이 동등하다는 생산시점 측정 근거가 있으므로 그 잎 쌍은 **equal**이다(기록에 마커 치환 근거를 남긴다). 이는 소비자 측 경로 정규화가 아니다 — 치환 대상은 생산자가 기록한 자기 reason의 자기 경로이며, 원문은 어디에도 재작성되지 않는다. 승격 요건이 하나라도 빠지면(거절 기록 부재, rawPath 비포함, skeleton 재계산 불일치, 문서형 거절, 위치·기록 불일치) 그 쌍은 미승격이며, **차이 쌍 중 하나라도 미승격이면 reason 축은 unknown이다**(승격된 쌍의 근거 노트는 기록에 유지) — v1의 측정 판정이 유지된다. `reason` 키의 값이 JString이 아니면 reason 축은 unknown이다.

**최종판정**: not_equal 증거가 하나라도 있으면 `not_equal` > 아니면 unknown 축이 하나라도 있으면 `unknown` > 아니면 `equal`. 기본값은 없다(fail-closed — 어떤 경우에도 기본 equal이 아니다).

**기존 canonical projection과의 관계 (재사용 검증, 2026-10-31 측정)**: `canonicalProjectionHash`는 volatile **키**만 제거하며 reason **문자열 내부**의 경로는 제거하지 않는다 — 실측: d1/d2 페이로드의 canonical 해시는 서로 달랐고(단일 hunk = reason 내 임베디드 경로), 이는 같은 논리 실행의 재현이 아님을 뜻하지 않는다. 따라서 ④는 canonicalizer를 구조 축의 재료로 **재사용**하되, canonical 해시 일치를 동등 판정으로 승격하지 않는다(해시 불일치 = reason 축 검사 요건일 뿐).

**Failure semantics**: 오류는 판정이 아니라 unknown이거나 not_equal의 근거로 기록된다. 비교 함수는 판정 불가·범위 밖·malformed를 예외가 아니라 unknown 축 + 기계적 note로 반환한다(`{.raises: [].}`). malformed에는 다음이 포함된다: identity 필수키 누락·빈 값, sidecar schemaVersion 누락·미인식, digest 형식 위반, dotted 경로의 중간 비객체 hop, 비-v1 페이로드 문서, `subjectLane` 비-rust·absent, 비문자열 reason 트리, 생산시점 결속 체인 불일치, 측정 갭.

**Proof (게이트)**: 비즈니스 gateway 테스트가 판정표를 강제한다 — v1 케이스 전부(동일 선언 positive, 기록 없는 임베디드 경로 치형 → unknown + 원문 보존, source/claim/scope/toolchain 변경 → not_equal, 오류 종류 변경 → not_equal, identity 누락·다중 target·flat 번들·비문자열 reason·schemaVersion 위반·digest 위반·lane 검사 → unknown)에 더해 v2 케이스: **relocation positive (d1/d2 실측 형상 + 생산시점 결속 체인 + 구조화 거절 기록 → equal; 결속은 순수 재계산으로 검증)**, 결속 체인 위조(identityBundleDigest·payloadSha256 불일치·sidecar 부재·키 부재) → unknown, 거절 기록의 contentSha256·index 변경(다른 파일) → not_equal + reason 미승격, rawPath 비포함·skeleton 재계산 불일치 → reason unknown, 재측정 anchor 불일치 → not_equal, 재측정 갭 → unknown-note. 캠페인 증거 `experiments/serde-json-claim-2026-10-31/`(d1/d2/d3)는 본 계약의 측정 근거로 **참조**될 뿐 소급 변경되지 않는다. offending 생성물의 내용 결속은 세 콜드 런에서 동일함이 실측되었다(sha256 `30c7e046…` ×3) — 생성물의 producer·입력·생성환경 결속(허용)은 §6d의 영역으로 남는다.

## §6d. LLBC files-table 절대경로 항목 출처 분류 — `embeddedContentAttested` (v1, 2026-11-01)

**대상**: `translated.files[]` 중 주체 크레이트 엔트리(`crate_name == translated.crate_name`)의 `name.Local`이 **절대경로**인 항목. §6c v2까지는 전량 rule 5 `path_absolute` 거절이었다; 본 절은 이 항목을 내용 결속 기준으로 분류한다. 측정 근거: serde_json @ `8c535a26`, charon 0.1.281(`79801650`) — files 테이블 151 엔트리 중 주체 15(상대경로 소스 14 + 절대경로 생성 private.rs 1, index=1, contents sha256 `30c7e046…`), 외부 136(전원 contents=null, `/rustc/…`·`/cargo/…` 경로).

**판정 규칙 (결정적)**:
- 절대경로 + `contents`가 문자열 → **`embeddedContentAttested` 수용**: 해당 엔트리는 주체 소스가 아니므로 디스크 집합 동치에서 **제외**되고, §6c identity sidecar에 항목당 `{index, crateName, contentSha256}`이 기록된다(identity 섹션의 가산 키 `embeddedContentAttested` — **항목이 0개면 키 자체를 생략**해 embedded 없는 크레이트의 sidecar가 기존과 byte 동일하게 유지된다).
- 절대경로 + `contents` null/누락 → **거절**(§6c v2 rule 5 `path_absolute` — reason·판정 byte 불변).
- 절대경로 embedded 항목의 rawPath 중복 → **거절**(신규 규칙 태그; charon의 stable_id 중복 제거로 정상 산출에서는 불가능 — malformed 방어).
- 외부 크레이트 엔트리는 기존대로 스킵(§6c v2 rule 6 policy — contents 미독취).

**주장 / 비주장 (핀 charon 소스 확인 — 79801650)**: 이 분류가 주장하는 것은 (a) rustc가 번역 시점에 이 텍스트를 읽었다(`File.contents = SourceFile.src` — 경로·크레이트 필터 없음), (b) 파일이 추출 cwd 밖에 있었다(절대경로 `Local`), (c) rustc가 주체 크레이트에 귀속했다(`crate_name`)의 세 가지뿐이다. **비주장**: build.rs가 생성했다는 생산자 provenance(`FileName`은 `Virtual`/`Local`/`NotReal`뿐이며 "generated" 종별이 없다 — 절대경로는 cwd-외 위치의 유일 관측 신호일 뿐이다), 생성 환경·입력(cargo 부트스트랩은 LLBC에 미기록), 디스크 상태(디스크 결속 없음 — 결속된 것은 내용뿐). "이 핀 invocation(cwd=크레이트 루트, 별도 charon-target)에서 절대경로 주체 엔트리가 OUT_DIR 산출물이라는 것"은 경험적 규칙성이지 계약 주장이 아니다.

**index의 의미와 안정성**: `index`는 files[] 배열 순위이며 charon `IndexVec`의 push_with 순차 할당으로 **FileId와 동치**다(핀 소스 + 151 엔트리 전수 실측 일치, 0–150 무공극). 테이블 순서는 span 최초 등장 순 append다(정렬·HashMap 순회 없음) — 핀된 (charon, rustc, subject, deps) 튜플에 대해 결정적(실측: d1/d2/d3/probe 4본의 정규화 해시 동일 — 변동은 `options.dest_file`·`files[1].name.Local` 두 run-relative 필드뿐), identity digest는 **순서 민감이 설계 의도**다: 재배치된 테이블은 다른 입력 산출물이며 다른 identity를 갖는다. A/B 재현 acceptance가 index·contentSha256 동일성을 실증한다.

**위장 방지 (fail-closed)**: 주체 `.rs` 파일을 절대경로 항목으로 재분류하면 디스크 집합이 대응하는 상대 항목 없이 남아 집합 동치가 `missingInLlbc`로 실패한다 — 소스 집합은 재분류로 조용히 줄어들 수 없다.

**D3 준수**: rawPath는 run-relative 데이터로 identity·binding·payload 어디에도 기록하지 않는다(수용 후 결속 역할이 없다; §6c의 skeleton 메커니즘도 이 경로에 불필요하다 — 거절 reason이 존재하지 않는다).

---

## §7. R5 CLI Contract 표 (per command)

| command | exists | help | success | verification-failure | invalid-input | internal-error | json schema v | stdout/stderr |
|---|---|---|---|---|---|---|---|---|
| `ax prove` | ✔ | ✔ | 0 | 1 (Phase 5 SATISFIED) | 1·3 (deferred) | 2 (OPEN) | `axiom.report.v1` (top-level `schemaVersion`, Phase 5) | split |
| `ax report` | ✔ | ✔ | 0 | 1 (SATISFIED) | 1·3 (deferred) | 2 (OPEN) | `axiom.report.v1` (top-level `schemaVersion`, Phase 5) | split |
| `ax status` | Candidate (dead code, §v1 Scope) | — | — | — | — | — | — | — |

문자 계약: exit code는 Phase 5 "v1 CLI Exit-State Contract" 섹션에서-doc화되어 있고, success와 failure가 구분된다.

**Report document schema identity (Phase 5)**: `ax prove` 출력 및 `ax report --json` 문서의 최상위에 `"schemaVersion": "axiom.report.v1"` 이 존재한다 (`src/cli/axiom_engine.nim` prove 출력, `src/cli/report_cli.nim` inject+검증 — 다른 값이 들어온 state는 에러로 거부). 상수 정의: `src/core/utils/constants.nim` (`axiomReportSchemaVersion`).

**Report flag surface (2026-10-21)**: `ax report` 가 받아들이는 인자는 `--json`, `--state-file <path>`, `--canonical-digest`, 그리고 `resilience` 서브커맨드(`--clean`) 뿐이다. **report 는 certificate 을 동기화하지 않는다** — 증빙 상태 문서를 읽고(§10.3 state) canonical VKD 를 TrustCommit journal 에서 투영한다(`src/verification/report_engine.nim`, `src/core/telemetry/verification_scope.nim`); certificate 디렉터리 스캔/수렴 단계 자체가 CLI 에 존재하지 않는다(`src/verification/proof_state_convergence.nim` 은 CLI 에서 호출되지 않는다). 따라서 cert-sync 플래그도 존재하지 않는다: 과거 `--no-cert-sync` 플래그의 파싱은 `677f167ab`(2026-06-01)에서 삭제되었고, 이후 **아무것도 선택하지 않는** 유령 플래그로만 남아 조용히 무시되었다(현재의 `ax report --no-cert-sync` 결과는 플래그 없는 호출과 바이트 동일 — 계약 테스트 `tests/cli/test_report_cli.nim` suite "report flag contract"). 이 PR 은 모든 in-repo 호출부에서 이 플래그를 제거했다(`tools/ci/smoke_test.nim`, `tools/ci/cold_replay_acceptance.sh`, `tests/gateway/productization_start_vertical_slice_feature_test.nim`, @deprecated `.feature` 시나리오). **잔여 구멍(follow-up)**: report CLI 는 알 수 없는 옵션을 조용히 무시한다 — 명시적 거절로 바꾸려면 `src/cli/report_cli.nim` 수정이 필요한데, 이 파일은 회전 핀(`config/trusted_writer_set.json` `trustedCheckerTreeClosure`)에 앵커되어 **일반 PR 경로로는 수정할 수 없다**(회전 절차/allowlist 경로가 유일 승격 경로 — `docs/evidence/rotation_preflight_prereg_2026-10-20.md` §6). `ax prove` 는 알 수 없는 옵션을 거절한다(`unknown option: …`) — report 도 같은 매핑으로 수렴해야 하나, 그 수정은 회전 절차 경로에 속한다. **계약 선언 (2026-10-31)**: `ax report --upstream` 플래그가 upstream 보고 표면으로 계약되었다(§11 — 계약 SSOT `upstream_reporting_contract.md`) — 위 열거는 2026-10-21 관측 기준이며, 구현 착지 시 개정된다.

---

## v1 CLI Exit-State Contract (Phase 5)

> **Status: DRAFT (Phase 5 freeze).** This section records the v1 product exit-code contract as a 5-state model (4-state + `NOT_CURRENT`). It captures **current verified behavior** (with file:line anchors) alongside the **v1 target**. Open items are marked `OPEN-ITEM` — they are NOT recorded as satisfied.

### 5-State Model (v1 Exit Contract)

v1 exit contract = **5-state (4-state + `NOT_CURRENT`) + non-contract signal**. 5-state는 계약의 일원이며, signal은 계약 밖이다.

| State | Exit code | Meaning | Current behavior (verified file:line) | v1 Target | Status |
|---|---|---|---|---|---|
| `success` | `0` | Verification ran; no failures | `ax prove` → `0` (`src/cli/wf_runners.nim` `axProofShortcutExitCode`, dispatched at `src/cli/axiom_engine.nim` `runVerifyWorkflow`); `ax report --json` → `0` when `failedCount==0 ∧ timeoutCount==0 ∧ verified>0` (`src/verification/report_engine.nim` `computeReportExitCode`, called at `src/cli/report_cli.nim` `runReportCli`) | `0` (prove) / `0` (report) | SATISFIED |
| `verification-failure` | `1` | **Verification claims not established** — ≥1 failed node, `verified==0` with failed/aborted nodes, or hang-guard aborted (incomplete) verification | ONE rule: `src/core/utils/decision_algebra.nim` `projectRunOutcome` (BLOCK / UNRESOLVED / CONTINUE), consumed by `ax prove` at `src/cli/wf_runners.nim` `axProofShortcutExitCode` and by `ax report --json` at `src/verification/report_engine.nim` `computeReportExitCode`; both project the decision through the same exit mapping (`src/cli/cli_outcome.nim` `exitCode`). BLOCK = failed node, UNRESOLVED = aborted/incomplete run or unreadable summary — the DECISION keeps that distinction, the exit code is deliberately coarse (both `1`). topology-only 프리뷰(`verified` 키 부재)는 규칙 대상 아님 — 기존 행동 보존 | `ax prove` → `1`; `ax report --json` → `1` | **SATISFIED (one rule, prove+report)** — 검증: `tests/unit/wf_runners_exit_code_test.nim`, `tests/unit/test_readiness_outcome_test.nim`, `tests/unit/report_engine_test.nim` |
| `invalid-input` | `3` | CLI argument / schema error | `1` — parser path `quit(1)` (`src/cli/action_plan_cli.nim:233`, `:242`) | `3` | **OPEN-ITEM** — deferred to post-v1; current `1` documented as-is |
| `internal-error` | `2` | Normal-classifiable internal error (Nim unhandled exception 기본) | `139` (SIGSEGV) — observed; no handler installed at CLI boundary | `2` | **OPEN-ITEM** — SIGSEGV is a BUG state, not a contract state |
| `not-current` | `4` | Artifact is structurally valid but not current product truth (stale toolchain / execution contract) | `ax verify <cert>` — not a failure: the artifact is valid, the contract it was taken under is not (`src/core/utils/decision_algebra.nim` `isCurrent`) | `4` | **SATISFIED** — 검증: `tests/unit/cli_outcome_test.nim` |

**Non-contract signal (out-of-contract failure):** **Uncaught process signal (SIGSEGV=139 등) = out-of-contract failure** — 5-state의 일원이 아니다. supported execution에서 관측되면 R5/R8 FAIL로 기록한다. signal→exit-code 변환 shim 신설 금지 (signal은 계약 상태가 아니며, 변환 shim은 theater risk).

**5-state ↔ exit code 매핑 (고정):**

| Exit code | State |
|---|---|
| `0` | VERIFIED (success) |
| `1` | VERIFICATION_FAILED (verification-failure) |
| `2` | INTERNAL_ERROR (normal-classifiable internal error에 한함 — Nim unhandled exception 기본) |
| `3` | INVALID_INPUT |
| `4` | NOT_CURRENT (valid artifact, not current product truth) |
| signal (e.g. 139) | out-of-contract failure — 5-state 밖 |

### Notes

- **One run-exit rule (v1)**: `projectRunOutcome` (`src/core/utils/decision_algebra.nim`) is the only place a run summary becomes an exit-axis decision. `ax prove` (`axProofShortcutExitCode`) and `ax report --json` (`computeReportExitCode`) are thin projections of it — neither re-derives the rule. `CONTINUE → 0`, `BLOCK → 1`, `UNRESOLVED → 1`. A topology-only preview (no `verified` key — e.g. the shortcut scan path) is not covered by the rule and preserves legacy `0` behavior; a summary that is missing, malformed, or missing its count keys is `UNRESOLVED` (fail-closed). Contract tests: `tests/unit/wf_runners_exit_code_test.nim`, `tests/unit/test_readiness_outcome_test.nim`.
- **Wall-clock closure (verdict axis ≠ exit axis)**: a wall-clock timeout is a hang-guard node abort, **not** a verification verdict — only gas/rlimit exhaustion is a deterministic verification failure (`src/verification/batch_uap/loop_driver.nim`, `loop_depth_scheduler.nim`, `isDeterministicFailure`). The exit axis stays fail-closed about it: a run with a timeout but no failed node is `UNRESOLVED` → `1` (previously `ax prove` returned `0` when `verified>0 ∧ timeoutCount>0`; that hole is closed). Timeout keys stay out of the canonical verification hash (§6), so this does not change what "verified" means.
- **`ax report` (non-`--json`)**: exits `0` unconditionally (`src/cli/report_cli.nim:316`). The JSON path (`--json`) is the only report surface with a failure-distinguishing exit code; the plain-text report is informational only.
- **Report flag surface**: `ax report` accepts `--json`, `--state-file <path>`, `--canonical-digest` and `resilience [--clean]` — nothing else (see §7 "Report flag surface"). The removed `--no-cert-sync` flag selects no behaviour (the report never synchronizes certificates), and unknown options are silently ignored by the report CLI — a residual gap whose fix requires the rotation-pin path, not an ordinary PR.
- **`ax prove` has no `--json` flag** (K2): JSON output is exclusive to `ax report --json`. Prove consumers must read the report JSON, not expect a JSON stream from prove.
- **JSON is emitted regardless of exit code** (`src/cli/report_cli.nim:480-485` — `$stateJson` is always serialized into `outputJson`). Consumers must not infer success from JSON presence; read the exit code.
- **Internal-error handling**: no trap/panic handler is installed at the CLI boundary. A `SIGSEGV` (`139`) is an observed bug state, not a designed contract state. v1 target is that internal faults exit a distinct, documented code — currently OPEN-ITEM.
- **Signal policy (v1)**: uncaught process signal (SIGSEGV=139 등) 은 **out-of-contract failure** 이다. 5-state(0/1/2/3/4)의 일원이 아니며, supported execution에서 관측되면 R5/R8 FAIL로 기록한다. **signal→exit-code 변환 shim 신설 금지** — signal은 계약 상태가 아니며, shim은 theater risk (§0.9)를 유발한다.
- **Invalid-input 해석 규칙 (v1)**: 지원되지 않는/잘못된 입력 → 문서화된 non-success → verification claim이 아니다 (Not a verification claim). INVALID_INPUT=3 확장/result.status 구현은 post-v1 유지 — 코드 변경 금지.

### v1 Contract Scope

v1 contract scope: `ax prove` / `ax report --json` are **Primary**; `ax status` is **Candidate** — a status command is NOT part of the v1 contract until census shows independent user value. `ax status` is not registered in the CLI dispatch (`src/cli/action_plan_cli.nim:230-333` — no `status` token in `parseAxSubcommandKind` at `:153-214`); the module `src/cli/axiom_status.nim` exists but is dead code. It is documented here as candidate surface only, not shipped.

---

## §7a. Semantic Mapping Table (v1 Contract)

다음 표는 **Product concept ↔ Existing representation** 의 정확한 매핑을 정의한다. 이 표의 목적은 **기존 representation을 수정하거나 새로운 필드를 freshly 만드는 것이 아니라**, 지금 cert에 없는 필드를 새로 만들 것처럼 보이지 않게 **기존 representation을 정확히 매핑**하는 것이다.

| Product concept | Existing representation | 의미 |
|---|---|---|
| Input identity | `sourceHash` + `irHash` | 입력/번역 상태 (§6a) |
| Proof identity | `proofArtifactDigest` | 증명 artifact digest |
| Certificate identity | `identityDigest` | certificate canonical digest (**provenance가 아니다** — certificate identity ≠ provenance) |
| Attestation reference | `trustCommitId` | journal-backed attestation 참조 (Phase 2에서 신규 추가 예정) |
| Toolchain | `solverIdentity` + `buildEnv` | 실행 환경 (solver + build environment) |
| Policy | `policyId` | 정책 식별 |
| Verdict | `status` + `verificationTier` | 결과/등급 |

---

## §7b. tierCounts Contract (v1)

**단일 출처 정의 (contract)**:

- `sum(tierCounts) == classifiedNodes` — 전체 status가 정상 분류되는 노드 수. 각 tier count는 해당 tier에 속한 classified node 수이며, 합은 분류된 전체 노드 수와 일치해야 한다.
- failed/skipped/timeout 은 **`statusCounts` 에 별도 집계** — `tierCounts` 에는 포함되지 않는다. `tierCounts` 는 오직 정상 분류된(verified/등급 부여된) 노드만 다루며, 실패/스킵/타임아웃은 verdict/status 축에 별도로 기록된다.
- **Phase 5에서 happy** — 현재는 계약 정의만 기재하고, 구현은 Phase 5에서 완성한다.

---

## §8. Policy / Evaluator 경계 & 장기 방향

- **Policy(data)**: criticality / observation key 스키마 / thresholds / freshness / requiredFields / R5 각 항목의 정의된 exit code 집합 — **파라미터만**. rule 언어 금지.
- **Evaluator(code)**: PASS/FAIL/UNKNOWN 대수, criticality 의미, 승격 규칙(R7 promotion), 결정표, 정규화·digest·fail-closed — 전부 고정 코드.
- **주의**: "LLM-generated evidence is transitional and not itself the canonical enforcement mechanism." — 장기적으로 evidence는 `collectR1..collectR8` 같은 **deterministic collector 도구**가 생산해야 하며, subagent 조사는 전환기 방법(method=`manual`)이다.
- 이번 단계 범위: standalone evaluator + golden tests + 실제 evidence 8건. **gate/topology 등록은 다음 단계** (`오늘 evaluateReadiness(policy,bundle,context)` 연결만 하면 됨).

---

## 9. Evaluator Interface (구현 사양)

```nim
# tools/readiness_evaluator.nim
proc loadEvidenceFiles(dir: string): Result[seq[JsonNode], string]                  # IO (유일)
proc validateEvidence(raw: JsonNode, ctx: EvaluationContext): Result[ValidatedEvidence, string]  # pure
proc normalizeBundle(validated: seq[ValidatedEvidence], policy: JsonNode): Result[CanonicalBundle, string]  # pure
proc evaluateReadiness(policy: JsonNode, bundle: CanonicalBundle): ReadinessDecision # pure (context는 validation에만)
```

CLI:
```
tools/readiness_evaluator --policy config/readiness_policy.json \
  --evidence-dir data/readiness/evidence \
  --repo-head <sha> --tree-digest <sha> --working-tree-clean true|false \
  --toolchain-nim 2.2.10 --toolchain-z3 4.13.3 --toolchain-lean 4.33.0 \
  --eval-time <ISO8601> --out <decision.json>
```
출력: decision object(§3+§4) + 진단 로그(stderr). 실패 시 exit 1, 무효 evidence는 UNKNOWN 처리 후 계속.
## §10. External Verification Subject Execution Context (Act 2)

Status: Ratified 2026-08-27. 정규 원문: 본 문서 §10의 D1-D4 규칙 +
experiments/act2-wp0-execution-context/wp0bc-completion-report.md.
원래 지칭되던 `experiments/act2-wp0-execution-context/D1-D4-spec.md`는 **한 번도 커밋된 적 없고
SHA256도 고정된 적 없다**(전 이력 `git log --all` 부재; 해당 디렉터리에는 wp0a/wp0bc 완결 문서만
존재) — 그 파일을 정본으로 지칭하던 기존 참조는 무효이며, D1-D4 규칙의 정본은 위 두 위치다.

### §10.1 Surface
- `ax prove --project <dir>`: 명시적 subject root. 플래그 부재 시 cwd convenience로 강등 —
  Explicit > Canonical > cwd-convenience 서열 고정.
- 모든 신원 digest는 물리경로 비포함(D3): 위치는 `<subject>/<state>/<execution>`
  canonical path role로만 표기한다. canonicalization은 projection이지 filesystem transform이
  아니다 — subject 프로그램이 관측하는 fs 의미론은 보존된다.

### §10.2 Identity (신원 축)
| 개념 | 정의 | 소유주 |
|---|---|---|
| sourceFingerprint | D1 캐논 직렬화(u32 LE len-prefix · UTF-8 무정규화 · raw sha256 · 바이트사전순) | Axiom |
| lockfileDigest | nimble.lock 원시 sha256 (absent 리터럴 허용) | subject 출처증거 |
| dependencyFingerprint | resolved closure {module, resolvedVersion, basis}의 D1식 해시 | Axiom |
| toolchainFingerprint | version/provenance identity (D2). Lean KAA receipt 번들 identity와 별개 키·상호파생 금지 | Axiom |

Rust subject 확장: `lockfileDigest` — Rust subject의 lockfile은 `Cargo.lock`이며 정의는 동일하게
원시 sha256이다 (`nimble.lock` 선례 미러링; 내용이 경로 자유(path-free)이므로 raw 해싱이 안전하다).
`dependencyFingerprint` — Rust에서는 resolved closure의 **canonical projection**(경로 정규화·정렬)을
D1식으로 해시한다. raw `cargo metadata` JSON은 identity에 절대 진입하지 않는다 —
`manifest_path`/`workspace_root`/`target_directory` 등 절대경로를 포함하며, 이를 해싱하면
D3 "물리경로 비포함" 위반이다.

**Rust identity 입력 → 기존 필드 매핑 (정정 11)**:

| Rust identity 입력 | 기존 representation | 보장 |
|---|---|---|
| RustCanonical digest | 기존 nimDigest→`irHash`→fingerprint/inputHash/identityDigest 체인에 Rust lane 연결 | 완전 (staleness+변조) |
| `llbcDigest` (LLBC raw sha256 — LLBC 문서 자체는 digest를 공급하지 않으므로 Axiom이 산출, [docs/spec/llbc_quirks.md] Q7) | `evidenceBundleWire` 필드 → `evidenceId` (identity 13번째 필드, [docs/spec/provenance_contract_v3.md] §3(c)) | 변조 감지 (verifier가 LLBC를 재유도하지 않음 — staleness 재유도는 명시적으로 미보장) |
| Cargo.toml `manifestDigest`·Cargo.lock `lockfileDigest` | subject-cert binding 서명 필드 (identity 13필드 미포함) | 변조 감지 한정 (staleness 거절은 계약 개정 필요 — 보장하지 않음) |
| `.rs` 파일집합 (D1) | 런 봉투(envelope) + LLBC 소비 전 fail-closed 입력 게이트 (`dvcNotCurrent` 축) | 입력 게이트 |
| LLBC files-table 절대경로 주체 항목 (§6d `embeddedContentAttested`) | 사이드카 identity 섹션 `{index, crateName, contentSha256}` | 내용 결속 한정 (생성 provenance·환경·디스크 미보장 — §6d 비주장) |

함수 단위 Input identity = `(sourceHash, irHash)` (§6a) — **변경 없음**. subject 핑거프린트는
런 봉투(envelope) 식별이며 §6a의 canonicalInputHash 대체가 아니므로 "canonicalInputHash 신규
구현 v1 non-goal"(§6a)과 충돌하지 않는다. **D1 subject fingerprint는 인증서 체인에 유입되지
않는다** — 런 봉투 전용이며 이는 위 Rust 확장의 의도된 설계다. 인증서 `inputHash`는
`modulePath`+`functionName`+`sourceHash`+`irHash`에서 파생된다
([docs/spec/provenance_contract_v3.md] §3(a)).

**Assurance 매핑 (정정 2)** — 제품 보장 축을 기존 representation에 고정한다:

| Assurance 축 | 기존 representation (필드 + 검증자) |
|---|---|
| Subject identity | `modulePath`+`functionName`+`sourceHash`+`inputHash` |
| Extractor provenance | `toolchainIdentity`/`toolchainFingerprint`/`translationVersion`/`semanticProfileId` |
| Claim·obligation | `leanProposition`+`obligationId`+`propositionHash`+`status` |
| KAA receipt | `canonicalKaa`+`kaaDigest`+`evidenceId`+`axiomsUsed` |
| Vault certificate | `identityDigest`+`provenance.certificateDigest`+`attestation` |
| Readiness·verifier | `verificationTier`/`solverStatus` + R7 `claimedScope`/`verifiedEmitterScope` |

### §10.3 Workspace 격리
- immutable subject / ephemeral execution workspace / state root. state 기본치는 Axiom repo 내;
  `AXIOM_STATE_DIR` 로 재배치 가능. trust journal은 로컬 잔존(Axiom repo `data/trusted/**`) —
  portable evidence non-goal(§1) 불변.
- "`--project` 지정 시에는 `AXIOM_STATE_DIR` 설정이 필요하다. 누락된 실행은 상태 기록 없이 즉시 실패한다(fail-closed)."

### §10.4 범위 선언
- submodule 내용물은 subject file set 제외; 검증 결과는 submodule을 커버하지 않는다(비주장).
- binary/image digest identity, container runner-image pinning: **Phase 6 계약화** — 바이너리 배포 경로(§1b)의 D-입력 집합(컨테이너 image digest 핀·툴체인 버전 핀·replay dep SHA 핀·AXIOM_PROVE_WORKERS=1)으로 관측 폐쇄. 소스 트리 내 검증 경로는 기존 계약 유지.
- 기존 비목표(§1 행) 전부 유지.

### §10.5 Acceptance (M1)
P1 Result Equality ∧ P2 Clean Replay(Axiom 관할 cold-set 한정) ∧ P3 Path Independence ∧
P4 Subject Immutability(safety; 위반 런은 InfrastructureFailure로 무효).

### §10.6 Rust subject 준비 순서 (prepare order)

Rust subject 실행 준비는 다음 순서로 고정한다: `cargo fetch --locked` (또는 고정 vendor 경로) →
`cargo metadata --format-version=1 --locked` → `cargo build --frozen`. R8 `documentedRunSteps`는
이 **시퀀스 전체**가 문서화될 것을 요구한다 — 현행 R8 관측 키는 실행 절차의 존재 여부만 검사하고
순서는 검사하지 않으므로, 순서 문서화는 이 계약의 명시 요구항이다.

### §10.7 완료 관측 4축 분리 (Rust lane)

Rust lane의 "완료"는 서로 다른 관측 축 4개로 분리되며, 한 축의 성공이 다른 축의 완료를 증명하지
않는다:

| 축 | 항목 | 완료 판정 |
|---|---|---|
| 제품 실행 | #1-8 | `ax prove` 경로 — Rust subject 검증이 실제 실행되고 산출물이 나오는 증거 |
| 외부 prepare | #9 | R8 evidence (§10.6 prepare order 전체의 문서화·재현) |
| Readiness | #10 | 레지스터 관측 (§2 R1 `subjectLane` × trust_boundary 레지스터) — **GO 선언은 `exists:true` 전환 승인 후 별개** |
| 통합 완료 | #11-12 | acceptance record + merge 후 canonical main (merge authority = GitHub, §2.3) |

**Readiness GO는 별개 승인이다**: Rust lane의 readiness GO는
`src/core/trusted/trust_boundary.nim` 레지스터의 해당 경계 컴포넌트(`rustc to LLBC lowering` 등)
가 `exists:false` → `exists:true`로 전환된 **후에만** 가능하다 (§2 R1 신뢰 경계 연동 규칙 — U1;
레지스터 전환 자체는 그 규칙 밖의 인간 승인 사항). readiness는 이미 레지스터를 소비한다
(commit e6cc760a9) — 현재 Rust 경계는 `exists:false`로 등록되어 있으므로
**Rust lane = NOT READY**다. "제품 실행 축이 녹색"은 readiness GO의 증거가 아니며, 그 역도
마찬가지다.

---

## §11. Upstream Reporting Surface — `ax report --upstream` (2026-10-31)

> Status: Committed contract (계약 선행 — 구현은 별도 workstream, AGENTS.md §0.12). 계약 SSOT: [upstream_reporting_contract.md](./upstream_reporting_contract.md). 입력단(intake) 계약 SSOT: [byo_agent_proposition_contract.md](./byo_agent_proposition_contract.md) — `ax prove --proposals` (2026-11-02).

- **표면**: `ax report --upstream` — 검증/의심된 외부 결함(defect)의 upstream 보고(GitHub Issues). 새 커맨드가 아니라 `ax report`의 플래그 표면 확장이다.
- **정당화 (§0.12 수직 슬라이스)**: 제품 체인 **발견→재현→판정→보고**의 마지막 단계를 표면화한다 — 결함이 유지보수자에게 도달하지 못하면 검증 결과의 고객 가치는 로컬에서 끊긴다. 판정 어휘와 귀속 규칙: [bug_verdict_glossary.md](./bug_verdict_glossary.md) (2026-10-31 2차 판정 모델 — `BUG_FOUND`/`BUG_SUSPECTED`는 보고 입력 상태).
- **경계**: 유일한 외부 쓰기 표면이며 `gh` 서브프로세스로만 수행된다 — 자격 증명은 `gh auth` 네이티브 클라이언트 전용(AGENTS.md §2.4). `ax prove`는 외부 쓰기가 없다(§0.3 신뢰 경계 불변). 게이트·CI required check·기계 판정 enum은 이 표면과 그 상태(`reportStatus`)를 소비하지 않는다.
- **R5/§7 관계**: §7 "Report flag surface"(2026-10-21 관측)는 이 섹션으로 폐기되지 않는다 — 구현 착지 시 §7의 플래그 열거가 개정되고, R1/R5 관측(`commandExists`·`helpSurface`·exit 계약)은 착지된 구현에 대해 수행된다. 구현 전까지 본 표면은 **문서화된 계약**이지 관측된 동작이 아니다 (fail-closed — 관측 없는 PASS 주장 금지).
- **입력단 확장 — BYO Agent intake (2026-11-02)**: 제품 체인 **발견→재현→판정→보고**의 입력단에 고객 AI 에이전트 명제 intake 표면 `ax prove --proposals`를 추가한다 — 고객 에이전트가 카탈로그 명제(config/spec specId 참조·파라미터화)를 제출하면 기존 검증 레인과 보고 체인(본 섹션의 표면)이 소비한다. 판정 어휘·귀속 규칙·exit 계약·receipt SSOT는 **무변경**이며, Agent Adoption(에이전트 선택)과 Proposition Adoption(인간 `soExplicit` 채택)은 분리된다. 계약 정본: [byo_agent_proposition_contract.md](./byo_agent_proposition_contract.md) (구현 — 병렬 workstream `work/byoa-phase1-intake`). **non-goal 보존 (HARD RULE)**: 이 확장은 §1 non-goal "broad AI-code verification guarantee"의 광역화가 **아니다** — 검증 주장을 생성하는 주체·범위는 기존 레인과 동일하게 유지되는 입력 채널 추가다.
